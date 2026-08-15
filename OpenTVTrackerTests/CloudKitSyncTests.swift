import CloudKit
import XCTest
@testable import OpenTVTracker

final class CloudKitSyncTests: XCTestCase {
    func testSystemFieldsRoundTripForNextSave() throws {
        let zoneID = CKRecordZone.ID(zoneName: "partner-test")
        let recordID = CKRecord.ID(recordName: "space-state", zoneID: zoneID)
        let record = CKRecord(recordType: "PartnerSpaceState", recordID: recordID)
        record["payload"] = Data("server-payload".utf8) as CKRecordValue
        let systemFields = try CloudRecordSystemFields.encode(record)

        let restored = try CloudRecordSystemFields.decode(systemFields)

        XCTAssertEqual(restored.recordID, recordID)
        XCTAssertEqual(restored.recordType, "PartnerSpaceState")
        XCTAssertEqual(restored.recordChangeTag, record.recordChangeTag)
        XCTAssertNil(restored["payload"])
    }

    func testConflictMergePreservesLocalAndServerChanges() throws {
        let zoneID = CKRecordZone.ID(zoneName: "partner-test")
        let recordID = CKRecord.ID(recordName: "space-state", zoneID: zoneID)
        let serverRecord = CKRecord(recordType: "PartnerSpaceState", recordID: recordID)
        serverRecord["payload"] = try CloudSyncPayloadCodec.encode(
            Self.space(
                titleIDs: ["server-title"],
                memberIDs: ["server-member"],
                watchEventIDs: ["server-watch"]
            )
        ) as CKRecordValue
        serverRecord["updatedAt"] = Date(timeIntervalSince1970: 200) as CKRecordValue
        let mutation = try Self.mutation(
            zoneID: zoneID,
            space: Self.space(
                titleIDs: ["local-title"],
                memberIDs: ["local-member"],
                watchEventIDs: ["local-watch"]
            ),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let mergedMutation = try XCTUnwrap(
            CloudSyncConflictResolver.merging(mutation: mutation, into: serverRecord)
        )
        let mergedRecord = CloudSyncRecordBuilder.populate(serverRecord, from: mergedMutation)
        let payload = try XCTUnwrap(mergedRecord["payload"] as? Data)
        let mergedSpace = try CloudSyncPayloadCodec.decode(payload)

        XCTAssertTrue(mergedRecord === serverRecord)
        XCTAssertEqual(Set(mergedSpace.titleIDs), ["local-title", "server-title"])
        XCTAssertEqual(Set(mergedSpace.members.map(\.id)), ["local-member", "server-member"])
        XCTAssertEqual(Set(mergedSpace.watchEvents?.map(\.id) ?? []), ["local-watch", "server-watch"])
        XCTAssertEqual(mergedRecord["updatedAt"] as? Date, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(mergedRecord.parent?.recordID.recordName, "space-root")
    }

    func testConflictResolutionRetriesOnceThenStops() {
        let record = CKRecord(recordType: "PartnerSpaceState")
        let conflict = CKError(
            _nsError: NSError(
                domain: CKErrorDomain,
                code: CKError.serverRecordChanged.rawValue,
                userInfo: [CKRecordChangedErrorServerRecordKey: record]
            )
        )

        XCTAssertEqual(
            CloudSyncFailurePolicy.saveDecision(
                for: conflict,
                scope: .privateDatabase,
                applicationRetryCount: 0
            ),
            .retryServerRecord
        )
        XCTAssertEqual(
            CloudSyncFailurePolicy.saveDecision(
                for: conflict,
                scope: .privateDatabase,
                applicationRetryCount: 1
            ),
            .deferUntilNextSync
        )
    }

    func testFailedSaveRecreatesOnlyPrivateMissingZone() {
        let zoneNotFound = CKError(
            _nsError: NSError(
                domain: CKErrorDomain,
                code: CKError.zoneNotFound.rawValue
            )
        )

        XCTAssertEqual(
            CloudSyncFailurePolicy.saveDecision(
                for: zoneNotFound,
                scope: .privateDatabase,
                applicationRetryCount: 0
            ),
            .recreateZoneAndRetry
        )
        XCTAssertEqual(
            CloudSyncFailurePolicy.saveDecision(
                for: zoneNotFound,
                scope: .sharedDatabase,
                applicationRetryCount: 0
            ),
            .noRetry
        )
        XCTAssertEqual(
            CloudSyncFailurePolicy.saveDecision(
                for: zoneNotFound,
                scope: .privateDatabase,
                applicationRetryCount: 1
            ),
            .deferUntilNextSync
        )
    }

    func testFailedDeleteTreatsMissingServerRecordAsCompleted() {
        let unknownItem = CKError(
            _nsError: NSError(
                domain: CKErrorDomain,
                code: CKError.unknownItem.rawValue
            )
        )
        let quotaError = CKError(
            _nsError: NSError(
                domain: CKErrorDomain,
                code: CKError.quotaExceeded.rawValue
            )
        )

        XCTAssertEqual(
            CloudSyncFailurePolicy.deleteDecision(for: unknownItem),
            .acknowledgeAlreadyDeleted
        )
        XCTAssertEqual(CloudSyncFailurePolicy.deleteDecision(for: quotaError), .noRetry)
    }

    func testZoneBootstrapDoesNotMaskOtherFailures() {
        let zoneNotFound = CKError(
            _nsError: NSError(
                domain: CKErrorDomain,
                code: CKError.zoneNotFound.rawValue
            )
        )
        let rejected = CKError(
            _nsError: NSError(
                domain: CKErrorDomain,
                code: CKError.serverRejectedRequest.rawValue
            )
        )

        XCTAssertEqual(
            CloudKitPartnerSharingService.zoneBootstrapDecision(for: zoneNotFound),
            .bootstrapZone
        )
        XCTAssertEqual(
            CloudKitPartnerSharingService.zoneBootstrapDecision(for: rejected),
            .noRetry
        )
    }

    func testDiagnosticDoesNotIncludeRecordIdentifiers() {
        let privateIdentifier = "partner-private-record-123"
        let error = CKError(
            _nsError: NSError(
                domain: CKErrorDomain,
                code: CKError.serverRecordChanged.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Conflict for \(privateIdentifier)"]
            )
        )

        let diagnostic = CloudKitDiagnostics.record(
            error,
            operation: .syncRecordSave,
            scope: .privateDatabase,
            retryDecision: .retryServerRecord
        )

        XCTAssertEqual(diagnostic.errorCode, CKError.serverRecordChanged.rawValue)
        XCTAssertFalse(diagnostic.summary.contains(privateIdentifier))
        XCTAssertEqual(
            diagnostic.summary,
            "operation=syncRecordSave databaseScope=privateDatabase ckErrorCode=14 retryDecision=retryServerRecord"
        )
    }
}

extension CloudKitSyncTests {
    func testStorePersistsSystemFieldsAcrossReload() async throws {
        let persistence = Self.persistence()
        defer { persistence.purge() }
        let zoneID = CKRecordZone.ID(zoneName: "partner-test")
        let mutation = try Self.mutation(
            zoneID: zoneID,
            space: Self.space(titleIDs: ["local-title"]),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let firstStore = CloudKitSyncStore(scope: .privateDatabase, persistence: persistence)
        await firstStore.enqueue(mutation)
        let savedRecord = CloudSyncRecordBuilder.record(for: mutation, systemFields: nil)

        await firstStore.acknowledge(saved: [savedRecord], deleted: [])

        let reloadedStore = CloudKitSyncStore(scope: .privateDatabase, persistence: persistence)
        let hasSystemFields = await reloadedStore.hasSystemFields(for: mutation.recordID)
        XCTAssertTrue(hasSystemFields)
        await reloadedStore.enqueue(mutation.replacing(
            payload: try CloudSyncPayloadCodec.encode(Self.space(titleIDs: ["next-title"])),
            updatedAt: Date(timeIntervalSince1970: 200)
        ))
        let restoredRecord = await reloadedStore.record(for: mutation.recordID)
        XCTAssertEqual(restoredRecord?.recordID, mutation.recordID)
        XCTAssertEqual(restoredRecord?.recordType, mutation.recordType)
    }

    func testStoreConflictRetryMergesPayloadAndKeepsIndependentBudgets() async throws {
        let persistence = Self.persistence()
        defer { persistence.purge() }
        let zoneID = CKRecordZone.ID(zoneName: "partner-test")
        let mutation = try Self.mutation(
            zoneID: zoneID,
            space: Self.space(titleIDs: ["local-title"]),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let store = CloudKitSyncStore(scope: .privateDatabase, persistence: persistence)
        await store.enqueue(mutation)
        let serverRecord = CKRecord(recordType: mutation.recordType, recordID: mutation.recordID)
        serverRecord["payload"] = try CloudSyncPayloadCodec.encode(
            Self.space(titleIDs: ["server-title"])
        ) as CKRecordValue
        serverRecord["updatedAt"] = Date(timeIntervalSince1970: 200) as CKRecordValue

        let preparedConflict = await store.prepareConflictRetry(serverRecord, recordID: mutation.recordID)
        XCTAssertTrue(preparedConflict)
        await store.prepareRetryWithoutSystemFields(recordID: mutation.recordID, reason: .zoneRecovery)
        let storedRetryRecord = await store.record(for: mutation.recordID)
        let retryRecord = try XCTUnwrap(storedRetryRecord)
        let retryPayload = try XCTUnwrap(retryRecord["payload"] as? Data)
        let retrySpace = try CloudSyncPayloadCodec.decode(retryPayload)
        let conflictCount = await store.applicationRetryCount(for: mutation.recordID, reason: .conflict)
        let zoneCount = await store.applicationRetryCount(for: mutation.recordID, reason: .zoneRecovery)
        let missingCount = await store.applicationRetryCount(for: mutation.recordID, reason: .missingRecord)

        XCTAssertEqual(Set(retrySpace.titleIDs), ["local-title", "server-title"])
        XCTAssertEqual(conflictCount, 1)
        XCTAssertEqual(zoneCount, 1)
        XCTAssertEqual(missingCount, 0)
    }

    func testDeferredConflictKeepsOutboxUntilFreshMutationResetsRetry() async throws {
        let persistence = Self.persistence()
        defer { persistence.purge() }
        let zoneID = CKRecordZone.ID(zoneName: "partner-test")
        let mutation = try Self.mutation(zoneID: zoneID, space: Self.space(titleIDs: []))
        let store = CloudKitSyncStore(scope: .privateDatabase, persistence: persistence)
        await store.enqueue(mutation)
        let serverRecord = CKRecord(recordType: mutation.recordType, recordID: mutation.recordID)
        serverRecord["payload"] = try XCTUnwrap(mutation.payload) as CKRecordValue
        let preparedConflict = await store.prepareConflictRetry(serverRecord, recordID: mutation.recordID)
        XCTAssertTrue(preparedConflict)

        let hasDeferredMutation = await store.hasPendingMutation(for: mutation.recordID)
        let deferredConflictCount = await store.applicationRetryCount(
            for: mutation.recordID,
            reason: .conflict
        )
        XCTAssertTrue(hasDeferredMutation)
        XCTAssertEqual(deferredConflictCount, 1)

        await store.enqueue(mutation.replacing(
            payload: try CloudSyncPayloadCodec.encode(Self.space(titleIDs: ["fresh-title"])),
            updatedAt: Date(timeIntervalSince1970: 300)
        ))
        let hasFreshMutation = await store.hasPendingMutation(for: mutation.recordID)
        let freshConflictCount = await store.applicationRetryCount(for: mutation.recordID, reason: .conflict)
        XCTAssertTrue(hasFreshMutation)
        XCTAssertEqual(freshConflictCount, 0)
    }

    func testPrivateZoneRecoveryPlanIncludesRootAndShare() throws {
        let zoneID = CKRecordZone.ID(zoneName: "partner-test")
        let mutation = try Self.mutation(zoneID: zoneID, space: Self.space(titleIDs: []))

        let plan = try XCTUnwrap(
            CloudKitPartnerZoneRecoveryPlan.make(mutation: mutation, scope: .privateDatabase)
        )

        XCTAssertEqual(plan.zoneID, zoneID)
        XCTAssertEqual(plan.root.recordID.recordName, "space-root")
        XCTAssertEqual(plan.root["spaceID"] as? String, "space")
        XCTAssertEqual(plan.share.recordID.zoneID, zoneID)
        XCTAssertNil(CloudKitPartnerZoneRecoveryPlan.make(mutation: mutation, scope: .sharedDatabase))
    }

}

private extension CloudKitSyncTests {
    static func mutation(
        zoneID: CKRecordZone.ID,
        space: SharedSpace,
        updatedAt: Date = Date(timeIntervalSince1970: 100)
    ) throws -> CloudSyncMutation {
        CloudSyncMutation(
            id: "space-state",
            recordType: "PartnerSpaceState",
            recordName: "space-state",
            zoneName: zoneID.zoneName,
            ownerName: zoneID.ownerName,
            parentRecordName: "space-root",
            payload: try CloudSyncPayloadCodec.encode(space),
            updatedAt: updatedAt
        )
    }

    static func space(
        titleIDs: [MediaTitle.ID],
        memberIDs: [String] = ["local-member"],
        watchEventIDs: [String] = []
    ) -> SharedSpace {
        SharedSpace(
            id: "space",
            name: "Our space",
            members: memberIDs.map {
                SpaceMember(id: $0, name: $0, initials: "T", isCurrentUser: $0 == memberIDs.first)
            },
            titleIDs: titleIDs,
            activity: [],
            isCloudSharingEnabled: true,
            membershipState: .accepted,
            watchEvents: watchEventIDs.map {
                SharedWatchEvent(
                    id: $0,
                    titleID: titleIDs.first ?? "title",
                    memberID: memberIDs.first ?? "member",
                    kind: .watched,
                    season: nil,
                    episode: nil,
                    occurredAt: Date(timeIntervalSince1970: 100),
                    supersedesEventID: nil
                )
            },
            isCurrentUserShareOwner: true
        )
    }

    static func persistence() -> CloudKitSyncPersistence {
        CloudKitSyncPersistence(
            scope: .privateDatabase,
            keyPrefix: "opentv.cloudkit.tests.\(UUID().uuidString)"
        )
    }
}
