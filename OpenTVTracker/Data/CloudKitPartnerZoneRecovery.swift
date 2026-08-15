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
