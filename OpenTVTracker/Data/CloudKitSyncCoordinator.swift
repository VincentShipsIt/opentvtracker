import CloudKit
import Foundation

enum CloudDatabaseScope: String, Codable, Sendable {
    case privateDatabase
    case sharedDatabase
}

struct CloudSyncMutation: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let recordType: String
    let recordName: String
    let zoneName: String
    let ownerName: String
    let parentRecordName: String?
    let payload: Data?
    let updatedAt: Date

    var recordID: CKRecord.ID {
        CKRecord.ID(
            recordName: recordName,
            zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        )
    }
}

actor CloudKitSyncCoordinator {
    static let shared = CloudKitSyncCoordinator()

    private let privateWorker: CloudKitSyncWorker
    private let sharedWorker: CloudKitSyncWorker

    init(container: CKContainer = CKContainer(identifier: CloudKitPartnerSharingService.containerIdentifier)) {
        privateWorker = CloudKitSyncWorker(database: container.privateCloudDatabase, scope: .privateDatabase)
        sharedWorker = CloudKitSyncWorker(database: container.sharedCloudDatabase, scope: .sharedDatabase)
    }

    func start() async {
        await privateWorker.start()
        await sharedWorker.start()
    }

    func enqueue(
        payload: Data,
        recordType: String,
        stableID: String,
        zoneID: CKRecordZone.ID,
        parentStableID: String? = nil,
        scope: CloudDatabaseScope
    ) async throws {
        let mutation = CloudSyncMutation(
            id: stableID,
            recordType: recordType,
            recordName: stableID,
            zoneName: zoneID.zoneName,
            ownerName: zoneID.ownerName,
            parentRecordName: parentStableID,
            payload: payload,
            updatedAt: .now
        )
        try await worker(for: scope).enqueue(mutation)
    }

    func enqueueDeletion(
        stableID: String,
        recordType: String,
        zoneID: CKRecordZone.ID,
        scope: CloudDatabaseScope
    ) async throws {
        let tombstone = CloudSyncMutation(
            id: stableID,
            recordType: recordType,
            recordName: stableID,
            zoneName: zoneID.zoneName,
            ownerName: zoneID.ownerName,
            parentRecordName: nil,
            payload: nil,
            updatedAt: .now
        )
        try await worker(for: scope).enqueue(tombstone)
    }

    func cachedPayload(stableID: String, scope: CloudDatabaseScope) async -> Data? {
        await worker(for: scope).cachedPayload(stableID: stableID)
    }

    private func worker(for scope: CloudDatabaseScope) -> CloudKitSyncWorker {
        scope == .privateDatabase ? privateWorker : sharedWorker
    }
}

private final class CloudKitSyncWorker: CKSyncEngineDelegate, @unchecked Sendable {
    private let scope: CloudDatabaseScope
    private let store: CloudKitSyncStore
    private let database: CKDatabase

    private lazy var engine: CKSyncEngine = {
        let serialization = CloudKitSyncPersistence.loadState(scope: scope)
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: serialization,
            delegate: self
        )
        configuration.automaticallySync = true
        configuration.subscriptionID = "opentv-\(scope.rawValue)"
        return CKSyncEngine(configuration)
    }()

    init(database: CKDatabase, scope: CloudDatabaseScope) {
        self.database = database
        self.scope = scope
        store = CloudKitSyncStore(scope: scope)
    }

    func start() async {
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
        } catch {
            await store.recordRecoverableError(error.localizedDescription)
        }
    }

    func enqueue(_ mutation: CloudSyncMutation) async throws {
        await store.enqueue(mutation)
        let change: CKSyncEngine.PendingRecordZoneChange = mutation.payload == nil
            ? .deleteRecord(mutation.recordID)
            : .saveRecord(mutation.recordID)
        engine.state.add(pendingRecordZoneChanges: [change])
        try await engine.sendChanges(.init(scope: .recordIDs([mutation.recordID])))
    }

    func cachedPayload(stableID: String) async -> Data? {
        await store.cachedPayload(stableID: stableID)
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            CloudKitSyncPersistence.saveState(update.stateSerialization, scope: scope)
        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                await store.cache(modification.record)
            }
            for deletion in changes.deletions {
                await store.removeCached(recordID: deletion.recordID)
            }
        case .sentRecordZoneChanges(let changes):
            await store.acknowledge(
                saved: changes.savedRecords.map(\.recordID),
                deleted: changes.deletedRecordIDs
            )
        case .accountChange(let change):
            await store.handleAccountChange(change.changeType)
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pendingChanges = syncEngine.state.pendingRecordZoneChanges.filter(context.options.scope.contains)
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pendingChanges) { [store] recordID in
            await store.record(for: recordID)
        }
    }
}

private actor CloudKitSyncStore {
    private let scope: CloudDatabaseScope
    private var outbox: [String: CloudSyncMutation]
    private var cache: [String: Data]

    init(scope: CloudDatabaseScope) {
        self.scope = scope
        outbox = CloudKitSyncPersistence.loadOutbox(scope: scope)
        cache = CloudKitSyncPersistence.loadCache(scope: scope)
    }

    func enqueue(_ mutation: CloudSyncMutation) {
        outbox[mutation.id] = mutation
        persistOutbox()
    }

    func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let mutation = outbox[recordID.recordName], let payload = mutation.payload else { return nil }
        let record = CKRecord(recordType: mutation.recordType, recordID: recordID)
        if let parentRecordName = mutation.parentRecordName {
            let parentID = CKRecord.ID(recordName: parentRecordName, zoneID: recordID.zoneID)
            record.parent = CKRecord.Reference(recordID: parentID, action: .none)
        }
        record["payload"] = payload as CKRecordValue
        record["updatedAt"] = mutation.updatedAt as CKRecordValue
        record["schemaVersion"] = 1 as CKRecordValue
        return record
    }

    func cache(_ record: CKRecord) {
        if let payload = record["payload"] as? Data {
            cache[record.recordID.recordName] = payload
            CloudKitSyncPersistence.saveCache(cache, scope: scope)
        }
    }

    func removeCached(recordID: CKRecord.ID) {
        cache.removeValue(forKey: recordID.recordName)
        CloudKitSyncPersistence.saveCache(cache, scope: scope)
    }

    func cachedPayload(stableID: String) -> Data? {
        cache[stableID]
    }

    func acknowledge(saved: [CKRecord.ID], deleted: [CKRecord.ID]) {
        for recordID in saved + deleted { outbox.removeValue(forKey: recordID.recordName) }
        persistOutbox()
    }

    func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange.ChangeType) {
        switch change {
        case .signIn(let currentUser):
            CloudKitSyncPersistence.saveAccountID(currentUser.recordName, scope: scope)
        case .signOut, .switchAccounts:
            cache = [:]
            outbox = [:]
            CloudKitSyncPersistence.purge(scope: scope)
        @unknown default:
            cache = [:]
            outbox = [:]
            CloudKitSyncPersistence.purge(scope: scope)
        }
    }

    func recordRecoverableError(_ message: String) {
        CloudKitSyncPersistence.saveError(message, scope: scope)
    }

    private func persistOutbox() {
        CloudKitSyncPersistence.saveOutbox(outbox, scope: scope)
    }
}

private enum CloudKitSyncPersistence {
    static func loadState(scope: CloudDatabaseScope) -> CKSyncEngine.State.Serialization? {
        data(key: "state", scope: scope).flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
    }

    static func saveState(_ state: CKSyncEngine.State.Serialization, scope: CloudDatabaseScope) {
        save(try? JSONEncoder().encode(state), key: "state", scope: scope)
    }

    static func loadOutbox(scope: CloudDatabaseScope) -> [String: CloudSyncMutation] {
        data(key: "outbox", scope: scope)
            .flatMap { try? JSONDecoder().decode([String: CloudSyncMutation].self, from: $0) } ?? [:]
    }

    static func saveOutbox(_ outbox: [String: CloudSyncMutation], scope: CloudDatabaseScope) {
        save(try? JSONEncoder().encode(outbox), key: "outbox", scope: scope)
    }

    static func loadCache(scope: CloudDatabaseScope) -> [String: Data] {
        data(key: "cache", scope: scope)
            .flatMap { try? JSONDecoder().decode([String: Data].self, from: $0) } ?? [:]
    }

    static func saveCache(_ cache: [String: Data], scope: CloudDatabaseScope) {
        save(try? JSONEncoder().encode(cache), key: "cache", scope: scope)
    }

    static func saveAccountID(_ id: String, scope: CloudDatabaseScope) {
        UserDefaults.standard.set(id, forKey: key("account", scope: scope))
    }

    static func saveError(_ message: String, scope: CloudDatabaseScope) {
        UserDefaults.standard.set(message, forKey: key("error", scope: scope))
    }

    static func purge(scope: CloudDatabaseScope) {
        for value in ["state", "outbox", "cache", "account", "error"] {
            UserDefaults.standard.removeObject(forKey: key(value, scope: scope))
        }
    }

    private static func data(key value: String, scope: CloudDatabaseScope) -> Data? {
        UserDefaults.standard.data(forKey: key(value, scope: scope))
    }

    private static func save(_ data: Data?, key value: String, scope: CloudDatabaseScope) {
        UserDefaults.standard.set(data, forKey: key(value, scope: scope))
    }

    private static func key(_ value: String, scope: CloudDatabaseScope) -> String {
        "opentv.cloudkit.\(scope.rawValue).\(value)"
    }
}
