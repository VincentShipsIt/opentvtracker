import CloudKit
import XCTest
@testable import OpenTVTracker

final class CloudKitSyncRecoveryTests: XCTestCase {
    func testBatchResultValidationSurfacesPerItemFailures() {
        let zoneID = CKRecordZone.ID(zoneName: "partner-test")
        let recordID = CKRecord.ID(recordName: "space-root", zoneID: zoneID)
        let quotaError = CKError(
            _nsError: NSError(domain: CKErrorDomain, code: CKError.quotaExceeded.rawValue)
        )

        XCTAssertThrowsError(
            try CloudKitBatchResultValidator.savedZone(
                zoneID,
                in: [zoneID: .failure(quotaError)]
            )
        )
        XCTAssertThrowsError(
            try CloudKitBatchResultValidator.savedRecords(
                [recordID],
                in: [recordID: .failure(quotaError)]
            )
        )
    }

    func testPartialZoneRecoveryPersistsUntilFreshSyncCanResume() async throws {
        let persistence = Self.persistence()
        defer { persistence.purge() }
        let mutation = try Self.mutation()
        let firstStore = CloudKitSyncStore(scope: .privateDatabase, persistence: persistence)
        await firstStore.enqueue(mutation)
        await firstStore.markZoneRecoveryRequired(for: mutation.recordID)
        await firstStore.registerZoneRecoveryFailure(for: mutation.recordID)

        let reloadedStore = CloudKitSyncStore(scope: .privateDatabase, persistence: persistence)
        let requiresRecovery = await reloadedStore.requiresZoneRecovery(for: mutation.recordID)
        let priorAttempts = await reloadedStore.applicationRetryCount(
            for: mutation.recordID,
            reason: .zoneRecovery
        )
        XCTAssertTrue(requiresRecovery)
        XCTAssertEqual(priorAttempts, 1)
        XCTAssertEqual(
            CloudSyncFailurePolicy.pendingZoneRecoveryDecision(applicationRetryCount: priorAttempts),
            .deferUntilNextSync
        )

        await reloadedStore.enqueue(mutation)
        let freshAttempts = await reloadedStore.applicationRetryCount(
            for: mutation.recordID,
            reason: .zoneRecovery
        )
        let stillRequiresRecovery = await reloadedStore.requiresZoneRecovery(for: mutation.recordID)
        XCTAssertTrue(stillRequiresRecovery)
        XCTAssertEqual(freshAttempts, 0)
        XCTAssertEqual(
            CloudSyncFailurePolicy.pendingZoneRecoveryDecision(applicationRetryCount: freshAttempts),
            .recreateZoneAndRetry
        )

        await reloadedStore.completeZoneRecovery(for: mutation.recordID)
        let completedRecovery = await reloadedStore.requiresZoneRecovery(for: mutation.recordID)
        XCTAssertFalse(completedRecovery)
    }
}

private extension CloudKitSyncRecoveryTests {
    static func mutation() throws -> CloudSyncMutation {
        let zoneID = CKRecordZone.ID(zoneName: "partner-test")
        let space = SharedSpace(
            id: "space",
            name: "Our space",
            members: [
                SpaceMember(id: "local-member", name: "You", initials: "Y", isCurrentUser: true)
            ],
            titleIDs: [],
            activity: [],
            isCloudSharingEnabled: true,
            membershipState: .accepted,
            isCurrentUserShareOwner: true
        )
        return CloudSyncMutation(
            id: "space-state",
            recordType: "PartnerSpaceState",
            recordName: "space-state",
            zoneName: zoneID.zoneName,
            ownerName: zoneID.ownerName,
            parentRecordName: "space-root",
            payload: try CloudSyncPayloadCodec.encode(space),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    static func persistence() -> CloudKitSyncPersistence {
        CloudKitSyncPersistence(
            scope: .privateDatabase,
            keyPrefix: "opentv.cloudkit.recovery-tests.\(UUID().uuidString)"
        )
    }
}
