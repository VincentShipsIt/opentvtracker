import CloudKit
import Foundation

actor CloudKitSyncStore {
    private let scope: CloudDatabaseScope
    private let persistence: CloudKitSyncPersistence
    private var outbox: [String: CloudSyncMutation]
    private var cache: [String: Data]
    private var systemFields: [String: Data]
    private var applicationRetryCounts: [String: [String: Int]]
    private var pendingZoneRecoveries: Set<String>

    init(scope: CloudDatabaseScope) {
        self.init(scope: scope, persistence: CloudKitSyncPersistence(scope: scope))
    }

    init(scope: CloudDatabaseScope, persistence: CloudKitSyncPersistence) {
        self.scope = scope
        self.persistence = persistence
        outbox = persistence.loadOutbox()
        cache = persistence.loadCache()
        systemFields = persistence.loadSystemFields()
        applicationRetryCounts = persistence.loadApplicationRetryCounts()
        pendingZoneRecoveries = persistence.loadPendingZoneRecoveries()
    }

    func enqueue(_ mutation: CloudSyncMutation) {
        outbox[mutation.id] = mutation
        applicationRetryCounts[mutation.id] = nil
        persistOutbox()
        persistApplicationRetryCounts()
    }

    func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let mutation = outbox[recordID.recordName], mutation.payload != nil else { return nil }
        return CloudSyncRecordBuilder.record(
            for: mutation,
            systemFields: systemFields[recordID.recordName]
        )
    }

    func cache(_ record: CKRecord) {
        persistSystemFields(for: record)
        if let payload = record["payload"] as? Data {
            cache[record.recordID.recordName] = payload
            persistence.saveCache(cache)
        }
    }

    func removeCached(recordID: CKRecord.ID) {
        cache.removeValue(forKey: recordID.recordName)
        systemFields.removeValue(forKey: recordID.recordName)
        persistence.saveCache(cache)
        persistSystemFields()
    }

    func cachedPayload(stableID: String) -> Data? {
        cache[stableID]
    }

    func acknowledge(saved: [CKRecord], deleted: [CKRecord.ID]) {
        for record in saved {
            guard persistSystemFields(for: record) else { continue }
            if let pending = outbox[record.recordID.recordName],
               let savedAt = record["updatedAt"] as? Date,
               pending.updatedAt > savedAt {
                continue
            }
            outbox.removeValue(forKey: record.recordID.recordName)
            applicationRetryCounts[record.recordID.recordName] = nil
            pendingZoneRecoveries.remove(record.recordID.recordName)
        }
        for recordID in deleted {
            acknowledgeDeleted(recordID)
        }
        persistOutbox()
        persistApplicationRetryCounts()
        persistence.savePendingZoneRecoveries(pendingZoneRecoveries)
    }

    func acknowledgeDeleted(_ recordID: CKRecord.ID) {
        outbox.removeValue(forKey: recordID.recordName)
        systemFields.removeValue(forKey: recordID.recordName)
        applicationRetryCounts[recordID.recordName] = nil
        pendingZoneRecoveries.remove(recordID.recordName)
        persistOutbox()
        persistSystemFields()
        persistApplicationRetryCounts()
        persistence.savePendingZoneRecoveries(pendingZoneRecoveries)
    }

    func applicationRetryCount(
        for recordID: CKRecord.ID,
        reason: CloudSyncRetryReason
    ) -> Int {
        applicationRetryCounts[recordID.recordName]?[reason.rawValue, default: 0] ?? 0
    }

    func prepareConflictRetry(_ serverRecord: CKRecord, recordID: CKRecord.ID) -> Bool {
        guard let mutation = outbox[recordID.recordName],
              let mergedMutation = CloudSyncConflictResolver.merging(
                  mutation: mutation,
                  into: serverRecord
              ) else {
            return false
        }
        CloudSyncRecordBuilder.populate(serverRecord, from: mergedMutation)
        guard persistSystemFields(for: serverRecord) else { return false }
        outbox[recordID.recordName] = mergedMutation
        persistOutbox()
        registerApplicationRetry(for: recordID, reason: .conflict)
        return true
    }

    func prepareRetryWithoutSystemFields(
        recordID: CKRecord.ID,
        reason: CloudSyncRetryReason
    ) {
        systemFields.removeValue(forKey: recordID.recordName)
        persistSystemFields()
        registerApplicationRetry(for: recordID, reason: reason)
    }

    func markZoneRecoveryRequired(for recordID: CKRecord.ID) {
        pendingZoneRecoveries.insert(recordID.recordName)
        persistence.savePendingZoneRecoveries(pendingZoneRecoveries)
    }

    func completeZoneRecovery(for recordID: CKRecord.ID) {
        pendingZoneRecoveries.remove(recordID.recordName)
        persistence.savePendingZoneRecoveries(pendingZoneRecoveries)
    }

    func requiresZoneRecovery(for recordID: CKRecord.ID) -> Bool {
        pendingZoneRecoveries.contains(recordID.recordName)
    }

    func registerZoneRecoveryFailure(for recordID: CKRecord.ID) {
        registerApplicationRetry(for: recordID, reason: .zoneRecovery)
    }

    func mutation(for recordID: CKRecord.ID) -> CloudSyncMutation? {
        outbox[recordID.recordName]
    }

    func hasPendingMutation(for recordID: CKRecord.ID) -> Bool {
        outbox[recordID.recordName] != nil
    }

    func hasSystemFields(for recordID: CKRecord.ID) -> Bool {
        systemFields[recordID.recordName] != nil
    }

    func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange.ChangeType) {
        switch change {
        case .signIn(let currentUser):
            persistence.saveAccountID(currentUser.recordName)
        case .signOut, .switchAccounts:
            purge()
        @unknown default:
            purge()
        }
    }

    func recordRecoverableError(_ message: String) {
        persistence.saveError(message)
    }

    func purge() {
        cache = [:]
        outbox = [:]
        systemFields = [:]
        applicationRetryCounts = [:]
        pendingZoneRecoveries = []
        persistence.purge()
    }

    private func persistOutbox() {
        persistence.saveOutbox(outbox)
    }

    @discardableResult
    private func persistSystemFields(for record: CKRecord) -> Bool {
        do {
            systemFields[record.recordID.recordName] = try CloudRecordSystemFields.encode(record)
            persistSystemFields()
            return true
        } catch {
            let diagnostic = CloudKitDiagnostics.record(
                error,
                operation: .syncPersistSystemFields,
                scope: scope,
                retryDecision: .deferUntilNextSync
            )
            persistence.saveError(diagnostic.summary)
            return false
        }
    }

    private func persistSystemFields() {
        persistence.saveSystemFields(systemFields)
    }

    private func registerApplicationRetry(
        for recordID: CKRecord.ID,
        reason: CloudSyncRetryReason
    ) {
        applicationRetryCounts[recordID.recordName, default: [:]][reason.rawValue, default: 0] += 1
        persistApplicationRetryCounts()
    }

    private func persistApplicationRetryCounts() {
        persistence.saveApplicationRetryCounts(applicationRetryCounts)
    }
}

struct CloudKitSyncPersistence: @unchecked Sendable {
    private let scope: CloudDatabaseScope
    private let defaults: UserDefaults
    private let keyPrefix: String

    init(
        scope: CloudDatabaseScope,
        defaults: UserDefaults = .standard,
        keyPrefix: String = "opentv.cloudkit"
    ) {
        self.scope = scope
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    func loadState() -> CKSyncEngine.State.Serialization? {
        data(key: "state").flatMap {
            try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
        }
    }

    func saveState(_ state: CKSyncEngine.State.Serialization) {
        save(try? JSONEncoder().encode(state), key: "state")
    }

    func loadOutbox() -> [String: CloudSyncMutation] {
        data(key: "outbox")
            .flatMap { try? JSONDecoder().decode([String: CloudSyncMutation].self, from: $0) } ?? [:]
    }

    func saveOutbox(_ outbox: [String: CloudSyncMutation]) {
        save(try? JSONEncoder().encode(outbox), key: "outbox")
    }

    func loadCache() -> [String: Data] {
        data(key: "cache")
            .flatMap { try? JSONDecoder().decode([String: Data].self, from: $0) } ?? [:]
    }

    func saveCache(_ cache: [String: Data]) {
        save(try? JSONEncoder().encode(cache), key: "cache")
    }

    func loadSystemFields() -> [String: Data] {
        data(key: "system-fields")
            .flatMap { try? JSONDecoder().decode([String: Data].self, from: $0) } ?? [:]
    }

    func saveSystemFields(_ systemFields: [String: Data]) {
        save(try? JSONEncoder().encode(systemFields), key: "system-fields")
    }

    func loadApplicationRetryCounts() -> [String: [String: Int]] {
        data(key: "application-retries")
            .flatMap { try? JSONDecoder().decode([String: [String: Int]].self, from: $0) } ?? [:]
    }

    func saveApplicationRetryCounts(_ counts: [String: [String: Int]]) {
        save(try? JSONEncoder().encode(counts), key: "application-retries")
    }

    func loadPendingZoneRecoveries() -> Set<String> {
        data(key: "pending-zone-recoveries")
            .flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []
    }

    func savePendingZoneRecoveries(_ recordNames: Set<String>) {
        save(try? JSONEncoder().encode(recordNames), key: "pending-zone-recoveries")
    }

    func saveAccountID(_ id: String) {
        defaults.set(id, forKey: key("account"))
    }

    func saveError(_ message: String) {
        defaults.set(message, forKey: key("error"))
    }

    func purge() {
        let values = [
            "state", "outbox", "cache", "system-fields", "application-retries",
            "pending-zone-recoveries", "account", "error"
        ]
        for value in values {
            defaults.removeObject(forKey: key(value))
        }
    }

    private func data(key value: String) -> Data? {
        defaults.data(forKey: key(value))
    }

    private func save(_ data: Data?, key value: String) {
        defaults.set(data, forKey: key(value))
    }

    private func key(_ value: String) -> String {
        "\(keyPrefix).\(scope.rawValue).\(value)"
    }
}
