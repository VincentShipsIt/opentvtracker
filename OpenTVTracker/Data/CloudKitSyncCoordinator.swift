import CloudKit
import Foundation

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

    func purge(scope: CloudDatabaseScope) async {
        await worker(for: scope).purge()
    }

    private func worker(for scope: CloudDatabaseScope) -> CloudKitSyncWorker {
        scope == .privateDatabase ? privateWorker : sharedWorker
    }
}

private final class CloudKitSyncWorker: CKSyncEngineDelegate, @unchecked Sendable {
    private let scope: CloudDatabaseScope
    private let store: CloudKitSyncStore
    private let database: CKDatabase
    private let persistence: CloudKitSyncPersistence

    private lazy var engine: CKSyncEngine = {
        let serialization = persistence.loadState()
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
        let persistence = CloudKitSyncPersistence(scope: scope)
        self.persistence = persistence
        store = CloudKitSyncStore(scope: scope, persistence: persistence)
    }

    func start() async {
        do {
            try await engine.fetchChanges()
        } catch {
            let diagnostic = CloudKitDiagnostics.record(
                error,
                operation: .syncFetchChanges,
                scope: scope,
                retryDecision: .noRetry
            )
            await store.recordRecoverableError(diagnostic.summary)
            return
        }
        do {
            try await engine.sendChanges()
        } catch {
            let diagnostic = CloudKitDiagnostics.record(
                error,
                operation: .syncSendChanges,
                scope: scope,
                retryDecision: .noRetry
            )
            await store.recordRecoverableError(diagnostic.summary)
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

    func purge() async {
        await engine.cancelOperations()
        await store.purge()
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            persistence.saveState(update.stateSerialization)
        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                await store.cache(modification.record)
                if modification.record.recordID.recordName == "space-state" {
                    NotificationCenter.default.post(name: .openTVCloudSharedStateChanged, object: nil)
                }
            }
            for deletion in changes.deletions {
                await store.removeCached(recordID: deletion.recordID)
            }
        case .sentRecordZoneChanges(let changes):
            await handleSentRecordZoneChanges(changes, syncEngine: syncEngine)
        case .sentDatabaseChanges(let changes):
            await handleSentDatabaseChanges(changes)
        case .accountChange(let change):
            await store.handleAccountChange(change.changeType)
        default:
            break
        }
    }
}

private extension CloudKitSyncWorker {
    private func handleSentRecordZoneChanges(
        _ changes: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async {
        await store.acknowledge(saved: changes.savedRecords, deleted: changes.deletedRecordIDs)
        let pendingChanges = await retryChanges(for: changes.failedRecordSaves)
        await handleFailedDeletes(changes.failedRecordDeletes)
        syncEngine.state.add(pendingDatabaseChanges: pendingChanges.database)
        syncEngine.state.add(pendingRecordZoneChanges: pendingChanges.records)
    }

    private func retryChanges(
        for failedSaves: [CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave]
    ) async -> (records: [CKSyncEngine.PendingRecordZoneChange], database: [CKSyncEngine.PendingDatabaseChange]) {
        var records: [CKSyncEngine.PendingRecordZoneChange] = []
        var database: [CKSyncEngine.PendingDatabaseChange] = []
        for failedSave in failedSaves {
            let changes = await retryChanges(for: failedSave)
            records.append(contentsOf: changes.records)
            database.append(contentsOf: changes.database)
        }
        return (records, database)
    }

    private func retryChanges(
        for failedSave: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave
    ) async -> (records: [CKSyncEngine.PendingRecordZoneChange], database: [CKSyncEngine.PendingDatabaseChange]) {
        let recordID = failedSave.record.recordID
        let hasPendingZoneRecovery = await store.requiresZoneRecovery(for: recordID)
        let retryReason = CloudSyncFailurePolicy.retryReason(
            for: failedSave.error,
            scope: scope,
            pendingZoneRecovery: hasPendingZoneRecovery
        )
        let retryCount = if let retryReason {
            await store.applicationRetryCount(for: recordID, reason: retryReason)
        } else {
            0
        }
        let decision = CloudSyncFailurePolicy.saveDecision(
            for: failedSave.error,
            scope: scope,
            applicationRetryCount: retryCount,
            pendingZoneRecovery: hasPendingZoneRecovery
        )
        let diagnostic = CloudKitDiagnostics.record(
            failedSave.error,
            operation: .syncRecordSave,
            scope: scope,
            retryDecision: decision
        )

        switch decision {
        case .retryServerRecord:
            return await conflictRetryChanges(for: failedSave, diagnostic: diagnostic)
        case .recreateZoneAndRetry:
            return await zoneRecoveryChanges(recordID: recordID, diagnostic: diagnostic)
        case .retryWithoutSystemFields:
            await store.prepareRetryWithoutSystemFields(recordID: recordID, reason: .missingRecord)
            return ([.saveRecord(recordID)], [])
        case .engineManaged:
            return ([], [])
        case .deferUntilNextSync, .noRetry:
            await store.recordRecoverableError(diagnostic.summary)
        case .acknowledgeAlreadyDeleted, .bootstrapZone:
            await store.recordRecoverableError(diagnostic.summary)
        }
        return ([], [])
    }

    private func conflictRetryChanges(
        for failedSave: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave,
        diagnostic: CloudKitDiagnostic
    ) async -> (records: [CKSyncEngine.PendingRecordZoneChange], database: [CKSyncEngine.PendingDatabaseChange]) {
        let recordID = failedSave.record.recordID
        guard let serverRecord = failedSave.error.serverRecord else {
            await store.recordRecoverableError(diagnostic.summary)
            return ([], [])
        }
        guard await store.prepareConflictRetry(serverRecord, recordID: recordID) else {
            let deferred = CloudKitDiagnostics.record(
                failedSave.error,
                operation: .syncRecordSave,
                scope: scope,
                retryDecision: .deferUntilNextSync
            )
            await store.recordRecoverableError(deferred.summary)
            return ([], [])
        }
        return ([.saveRecord(recordID)], [])
    }

    private func zoneRecoveryChanges(
        recordID: CKRecord.ID,
        diagnostic: CloudKitDiagnostic
    ) async -> (records: [CKSyncEngine.PendingRecordZoneChange], database: [CKSyncEngine.PendingDatabaseChange]) {
        guard let mutation = await store.mutation(for: recordID) else {
            await store.recordRecoverableError(diagnostic.summary)
            return ([], [])
        }
        await store.markZoneRecoveryRequired(for: recordID)
        let recovery = CloudKitPartnerZoneRecovery(database: database, scope: scope)
        let recoveryResult = await recovery.recreate(for: mutation)
        if case .failed(let recoveryFailure) = recoveryResult {
            await store.registerZoneRecoveryFailure(for: recordID)
            await store.recordRecoverableError(recoveryFailure.summary)
            return ([], [])
        }
        await store.completeZoneRecovery(for: recordID)
        await store.prepareRetryWithoutSystemFields(recordID: recordID, reason: .zoneRecovery)
        if case .createdShareRequiresInvitation = recoveryResult {
            await MainActor.run {
                NotificationCenter.default.post(name: .openTVCloudShareRequiresInvitation, object: nil)
            }
        }
        return ([.saveRecord(recordID)], [])
    }

    private func handleFailedDeletes(_ failedDeletes: [CKRecord.ID: CKError]) async {
        for (recordID, error) in failedDeletes {
            let decision = CloudSyncFailurePolicy.deleteDecision(for: error)
            let diagnostic = CloudKitDiagnostics.record(
                error,
                operation: .syncRecordDelete,
                scope: scope,
                retryDecision: decision
            )
            switch decision {
            case .acknowledgeAlreadyDeleted:
                await store.acknowledgeDeleted(recordID)
            case .engineManaged:
                break
            default:
                await store.recordRecoverableError(diagnostic.summary)
            }
        }
    }

    private func handleSentDatabaseChanges(
        _ changes: CKSyncEngine.Event.SentDatabaseChanges
    ) async {
        for failedSave in changes.failedZoneSaves {
            let decision = CloudSyncFailurePolicy.zoneSaveDecision(for: failedSave.error)
            let diagnostic = CloudKitDiagnostics.record(
                failedSave.error,
                operation: .syncZoneSave,
                scope: scope,
                retryDecision: decision
            )
            if decision == .noRetry {
                await store.recordRecoverableError(diagnostic.summary)
            }
        }
        for error in changes.failedZoneDeletes.values {
            let decision = CloudSyncFailurePolicy.deleteDecision(for: error)
            let diagnostic = CloudKitDiagnostics.record(
                error,
                operation: .syncZoneDelete,
                scope: scope,
                retryDecision: decision
            )
            if decision == .noRetry {
                await store.recordRecoverableError(diagnostic.summary)
            }
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

extension Notification.Name {
    static let openTVCloudSharedStateChanged = Notification.Name("OpenTVCloudSharedStateChanged")
    static let openTVCloudShareRequiresInvitation = Notification.Name("OpenTVCloudShareRequiresInvitation")
}
