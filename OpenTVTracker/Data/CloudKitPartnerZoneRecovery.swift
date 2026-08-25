import CloudKit
import Foundation

struct CloudKitPartnerZoneRecoveryPlan {
    let zoneID: CKRecordZone.ID
    let root: CKRecord
    let share: CKShare

    static func make(
        mutation: CloudSyncMutation,
        scope: CloudDatabaseScope
    ) -> Self? {
        guard scope == .privateDatabase,
              mutation.recordType == "PartnerSpaceState",
              mutation.parentRecordName == "space-root",
              let payload = mutation.payload,
              let space = try? CloudSyncPayloadCodec.decode(payload) else {
            return nil
        }
        let zoneID = mutation.recordID.zoneID
        let rootID = CKRecord.ID(recordName: "space-root", zoneID: zoneID)
        let (root, share) = CloudKitPartnerSharingService.makeInitialShare(
            spaceID: space.id,
            rootID: rootID
        )
        return Self(zoneID: zoneID, root: root, share: share)
    }
}

enum CloudKitPartnerZoneRecoveryResult {
    case recoveredExistingShare
    case createdShareRequiresInvitation
    case failed(CloudKitDiagnostic)
}

struct CloudKitPartnerZoneRecovery {
    let database: CKDatabase
    let scope: CloudDatabaseScope

    func recreate(for mutation: CloudSyncMutation) async -> CloudKitPartnerZoneRecoveryResult {
        guard let plan = CloudKitPartnerZoneRecoveryPlan.make(mutation: mutation, scope: scope) else {
            return .failed(CloudKitDiagnostics.record(
                NSError(domain: "OpenTVCloudSync", code: 1),
                operation: .syncZoneSave,
                scope: scope,
                retryDecision: .deferUntilNextSync
            ))
        }

        if let diagnostic = await saveZone(plan.zoneID) { return .failed(diagnostic) }
        return await saveShare(root: plan.root, share: plan.share)
    }

    private func saveZone(_ zoneID: CKRecordZone.ID) async -> CloudKitDiagnostic? {
        do {
            let result = try await database.modifyRecordZones(
                saving: [CKRecordZone(zoneID: zoneID)],
                deleting: []
            )
            try CloudKitBatchResultValidator.savedZone(zoneID, in: result.saveResults)
            return nil
        } catch {
            return CloudKitDiagnostics.record(
                error,
                operation: .syncZoneSave,
                scope: scope,
                retryDecision: .deferUntilNextSync
            )
        }
    }

    private func saveShare(
        root: CKRecord,
        share: CKShare
    ) async -> CloudKitPartnerZoneRecoveryResult {
        do {
            let result = try await CloudKitPartnerSharingService.saveInitialShare(
                root: root,
                share: share,
                rootID: root.recordID,
                database: database
            )
            return result.reusedExistingShare
                ? .recoveredExistingShare
                : .createdShareRequiresInvitation
        } catch {
            return .failed(CloudKitDiagnostics.record(
                error,
                operation: .createShare,
                scope: scope,
                retryDecision: .deferUntilNextSync
            ))
        }
    }
}

extension CloudKitPartnerSharingService {
    static func saveInitialShare(
        root: CKRecord,
        share: CKShare,
        rootID: CKRecord.ID,
        database: CKDatabase
    ) async throws -> (share: CKShare, reusedExistingShare: Bool) {
        do {
            let result = try await database.modifyRecords(
                saving: [root, share],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            try CloudKitBatchResultValidator.savedRecords(
                [root.recordID, share.recordID],
                in: result.saveResults
            )
            guard let shareResult = result.saveResults[share.recordID],
                  let share = try shareResult.get() as? CKShare else {
                throw PartnerSharingError.invitationUnavailable
            }
            return (share, false)
        } catch {
            guard Self.isServerRecordChanged(error) else {
                throw error
            }
            CloudKitDiagnostics.record(
                error,
                operation: .createShare,
                scope: .privateDatabase,
                retryDecision: .retryServerRecord
            )
            if let existingShare = try await existingShare(rootID: rootID, database: database) {
                return (existingShare, true)
            }
            guard let existingRoot = try await fetchRoot(rootID: rootID, database: database) else {
                throw error
            }
            let attachedShare = try await saveShareOnExistingRoot(
                existingRoot,
                rootID: rootID,
                database: database
            )
            return (attachedShare, false)
        }
    }

    static func saveShareOnExistingRoot(
        _ root: CKRecord,
        rootID: CKRecord.ID,
        database: CKDatabase
    ) async throws -> CKShare {
        let share = makeShare(on: root)
        do {
            let result = try await database.modifyRecords(
                saving: [root, share],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            try CloudKitBatchResultValidator.savedRecords(
                [root.recordID, share.recordID],
                in: result.saveResults
            )
            guard let shareResult = result.saveResults[share.recordID],
                  let savedShare = try shareResult.get() as? CKShare else {
                throw PartnerSharingError.invitationUnavailable
            }
            return savedShare
        } catch {
            guard isServerRecordChanged(error),
                  let latestShare = try await existingShare(rootID: rootID, database: database) else {
                throw error
            }
            return latestShare
        }
    }

    static func isServerRecordChanged(_ error: Error) -> Bool {
        CloudKitErrorInspector.contains(.serverRecordChanged, in: error)
    }

    static func zoneBootstrapDecision(for error: Error) -> CloudKitRetryDecision {
        CloudKitErrorInspector.contains(.zoneNotFound, in: error) ? .bootstrapZone : .noRetry
    }

    static func zoneID(for spaceID: SharedSpace.ID) -> CKRecordZone.ID {
        let safeID = spaceID
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9-]", with: "-", options: .regularExpression)
        return CKRecordZone.ID(zoneName: "partner-\(safeID)")
    }

    static func shareReference(on root: CKRecord) -> CKRecord.Reference? {
        root.share
    }

    static func makeShare(on root: CKRecord) -> CKShare {
        let share: CKShare
        if let shareID = shareReference(on: root)?.recordID {
            share = CKShare(rootRecord: root, shareID: shareID)
        } else {
            share = CKShare(rootRecord: root)
        }
        share[CKShare.SystemFieldKey.title] = "OpenTV partner space" as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "dev.opentvtracker.app.partner-space" as CKRecordValue
        share.publicPermission = .none
        return share
    }

    static func makeInitialShare(
        spaceID: SharedSpace.ID,
        rootID: CKRecord.ID
    ) -> (root: CKRecord, share: CKShare) {
        let root = CKRecord(recordType: "PartnerSpace", recordID: rootID)
        root["spaceID"] = spaceID as CKRecordValue
        root["schemaVersion"] = 1 as CKRecordValue
        root["createdAt"] = Date.now as CKRecordValue
        return (root, makeShare(on: root))
    }
}
