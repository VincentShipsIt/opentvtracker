import CloudKit
import XCTest
@testable import OpenTVTracker

@MainActor
final class CloudSharingModelTests: XCTestCase {
    func testTogetherToggleStoresSanitizedMetadataAndIsReversible() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)
        if let titleIndex = model.titles.firstIndex(where: { $0.id == "past-lives" }) {
            model.titles[titleIndex].isUpNextPinned = true
            model.titles[titleIndex].upNextSnoozedUntil = .now
            model.titles[titleIndex].upNextManualOrder = 3
        }
        XCTAssertTrue(model.isShared("past-lives"))

        model.toggleTogether("past-lives")
        XCTAssertFalse(model.isShared("past-lives"))

        model.toggleTogether("past-lives")
        XCTAssertTrue(model.isShared("past-lives"))
        let sharedTitle = model.sharedSpace.titleMetadata?.first { $0.id == "past-lives" }
        XCTAssertEqual(sharedTitle?.title, "Past Lives")
        XCTAssertEqual(sharedTitle?.state, .planned)
        XCTAssertNil(sharedTitle?.userRating)
        XCTAssertNil(sharedTitle?.notes)
        XCTAssertNil(sharedTitle?.watchedEpisodeIDs)
        XCTAssertNil(sharedTitle?.isUpNextPinned)
        XCTAssertNil(sharedTitle?.upNextSnoozedUntil)
        XCTAssertNil(sharedTitle?.upNextManualOrder)
    }

    func testTogetherTogglePersistsCatalogOnlyTitleBeforeSharing() async throws {
        let catalogTitle = try XCTUnwrap(
            LibrarySnapshot.sample.titles.first(where: { $0.id == "past-lives" })
        )
        let store = MemoryLibraryStore()
        let model = AppModel(
            store: store,
            catalogService: LocalCatalogService(titles: [catalogTitle]),
            seed: .empty
        )

        await model.searchCatalog(text: "Past Lives")
        XCTAssertTrue(model.titles.isEmpty)

        model.toggleTogether(catalogTitle.id)
        await model.flushPendingPersistence()

        let loaded = try await store.load()
        let saved = try XCTUnwrap(loaded)
        let savedTitle = try XCTUnwrap(saved.titles.first(where: { $0.id == catalogTitle.id }))
        XCTAssertEqual(savedTitle.title, catalogTitle.title)
        XCTAssertEqual(saved.sharedSpace.titleIDs, [catalogTitle.id])
        XCTAssertEqual(saved.sharedSpace.titleMetadata?.first?.id, catalogTitle.id)
    }

    func testSharedTitleMetadataHydratesPartnerLibraryWithEpisodes() throws {
        var ownerSnapshot = LibrarySnapshot.sample
        let ownerIndex = try XCTUnwrap(ownerSnapshot.titles.firstIndex(where: { $0.id == "severance" }))
        ownerSnapshot.titles[ownerIndex].seasons = Self.seasons
        ownerSnapshot.titles[ownerIndex].watchedEpisodeIDs = ["s1e1"]
        ownerSnapshot.sharedSpace.titleIDs = ["severance"]
        ownerSnapshot.sharedSpace.titleMetadata = nil
        let owner = AppModel(store: MemoryLibraryStore(), seed: ownerSnapshot)
        owner.prepareSharedTitleMetadataForSync()
        let metadata = try XCTUnwrap(owner.sharedSpace.titleMetadata)

        let partner = AppModel(store: MemoryLibraryStore(), seed: .empty)
        partner.mergeSharedTitleMetadataIntoLibrary(metadata)

        let sharedTitle = try XCTUnwrap(partner.mediaTitle(withID: "severance"))
        XCTAssertEqual(sharedTitle.seasons, Self.seasons)
        XCTAssertNil(sharedTitle.watchedEpisodeIDs)
        XCTAssertEqual(sharedTitle.state, .planned)
    }

    func testCustomListSharingIsExplicitSanitizedAndReversible() throws {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)
        let listID = try XCTUnwrap(model.createList(named: "Date night"))
        model.addTitle("past-lives", toList: listID)

        XCTAssertFalse(model.isListShared(listID))
        model.shareListWithPartner(listID)

        let sharedList = try XCTUnwrap(model.sharedSpace.sharedLists?.first(where: { $0.id == listID }))
        XCTAssertEqual(sharedList.name, "Date night")
        XCTAssertEqual(sharedList.titleIDs, ["past-lives"])
        XCTAssertFalse(sharedList.isDeleted)
        let metadata = try XCTUnwrap(model.sharedSpace.titleMetadata?.first(where: { $0.id == "past-lives" }))
        XCTAssertNil(metadata.userRating)
        XCTAssertNil(metadata.notes)

        model.stopSharingList(listID)

        XCTAssertFalse(model.isListShared(listID))
        let tombstone = try XCTUnwrap(model.sharedSpace.sharedLists?.first(where: { $0.id == listID }))
        XCTAssertNotNil(tombstone.deletedAt)
        XCTAssertEqual(tombstone.name, "")
        XCTAssertTrue(tombstone.titleIDs.isEmpty)
    }

    func testLegacyLocalListIsNotPresentedAsPartnerOwnedWithoutMemberMetadata() {
        var snapshot = LibrarySnapshot.empty
        snapshot.sharedSpace.members = []
        snapshot.sharedSpace.sharedLists = [
            SharedMediaList(
                id: "date-night",
                name: "Date night",
                titleIDs: [],
                ownerMemberID: "local-user",
                updatedAt: .now
            )
        ]
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        XCTAssertTrue(model.partnerSharedLists.isEmpty)
    }

    func testCloudKitInvitationFailureUsesSafeUserFacingMessage() {
        let underlyingError = NSError(
            domain: CKErrorDomain,
            code: CKError.serverRejectedRequest.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Error saving record <private CloudKit record details>"]
        )

        let error = CloudKitPartnerSharingService.invitationError(from: underlyingError)

        XCTAssertEqual(error, .shareUnavailable)
        XCTAssertEqual(error.localizedDescription, "OpenTV could not create the private invitation. Try again.")
        XCTAssertFalse(error.localizedDescription.contains("record"))
    }

    func testCloudKitInvitationQuotaFailureDirectsUserToManageICloudStorage() {
        let quotaError = CKError(
            _nsError: NSError(
                domain: CKErrorDomain,
                code: CKError.quotaExceeded.rawValue
            )
        )

        let error = CloudKitPartnerSharingService.invitationError(from: quotaError)

        XCTAssertEqual(error, .iCloudStorageFull)
        XCTAssertEqual(
            error.localizedDescription,
            "iCloud reported that this invitation exceeded the account's storage quota. Check iCloud storage in Settings, then try again."
        )
    }

    func testCloudKitInvitationFindsQuotaFailureInsidePartialError() {
        let quotaError = CKError(
            _nsError: NSError(
                domain: CKErrorDomain,
                code: CKError.quotaExceeded.rawValue
            )
        )
        let partialError = CKError(
            _nsError: NSError(
                domain: CKErrorDomain,
                code: CKError.partialFailure.rawValue,
                userInfo: [CKPartialErrorsByItemIDKey: ["private-save": quotaError]]
            )
        )

        XCTAssertEqual(
            CloudKitPartnerSharingService.invitationError(from: partialError),
            .iCloudStorageFull
        )
    }

    func testCloudKitPrivateInvitationCreatesAnonymousReadWriteParticipant() {
        let participant = CloudKitPartnerSharingService.makePrivateInvitationParticipant()

        XCTAssertEqual(participant.permission, .readWrite)
        XCTAssertNil(participant.userIdentity.lookupInfo)
    }

    func testCloudKitPrivateInvitationsUseDistinctParticipants() {
        let first = CloudKitPartnerSharingService.makePrivateInvitationParticipant()
        let second = CloudKitPartnerSharingService.makePrivateInvitationParticipant()

        XCTAssertNotEqual(first.participantID, second.participantID)
    }

    func testCloudKitInvitationRetriesOnlyServerRecordConflicts() {
        let conflict = CKError(
            _nsError: NSError(
                domain: CKErrorDomain,
                code: CKError.serverRecordChanged.rawValue
            )
        )
        let networkFailure = CKError(
            _nsError: NSError(
                domain: CKErrorDomain,
                code: CKError.networkFailure.rawValue
            )
        )

        XCTAssertTrue(CloudKitPartnerSharingService.isServerRecordChanged(conflict))
        XCTAssertFalse(CloudKitPartnerSharingService.isServerRecordChanged(networkFailure))
        XCTAssertFalse(CloudKitPartnerSharingService.isServerRecordChanged(PartnerSharingError.shareUnavailable))
    }

    func testCloudKitSharingFailuresHaveActionSpecificMessages() {
        XCTAssertEqual(
            PartnerSharingError.acceptanceUnavailable.localizedDescription,
            "OpenTV could not accept the private invitation. Try again."
        )
        XCTAssertEqual(
            PartnerSharingError.revokeUnavailable.localizedDescription,
            "OpenTV could not revoke the private invitation. Try again."
        )
        XCTAssertEqual(
            PartnerSharingError.leaveUnavailable.localizedDescription,
            "OpenTV could not leave the shared space. Try again."
        )
    }

    func testInvitationBootstrapAttachesShareWhenRootExistsWithoutShare() {
        XCTAssertEqual(
            PartnerShareBootstrap.action(hasRoot: true, hasShare: false),
            .attachShareToExistingRoot
        )
        XCTAssertEqual(
            PartnerShareBootstrap.action(hasRoot: true, hasShare: true),
            .reuseExistingShare
        )
        XCTAssertEqual(
            PartnerShareBootstrap.action(hasRoot: false, hasShare: false),
            .createInitialShare
        )
        XCTAssertEqual(
            PartnerShareBootstrap.action(hasRoot: false, hasShare: true),
            .createInitialShare
        )
    }

    func testMakeShareOnExistingRootKeepsPrivateInvitationSettings() {
        let zoneID = CKRecordZone.ID(zoneName: "partner-primary-partner-space")
        let rootID = CKRecord.ID(recordName: "space-root", zoneID: zoneID)
        let root = CKRecord(recordType: "PartnerSpace", recordID: rootID)
        root["spaceID"] = "primary-partner-space" as CKRecordValue

        let share = CloudKitPartnerSharingService.makeShare(on: root)

        XCTAssertEqual(share.publicPermission, .none)
        XCTAssertEqual(
            share[CKShare.SystemFieldKey.shareType] as? String,
            "dev.opentvtracker.app.partner-space"
        )
        XCTAssertEqual(
            share[CKShare.SystemFieldKey.title] as? String,
            "OpenTV partner space"
        )
        XCTAssertEqual(root.share?.recordID, share.recordID)
        XCTAssertEqual(root.recordID.recordName, "space-root")
        XCTAssertEqual(root["spaceID"] as? String, "primary-partner-space")
    }

    func testMakeShareReusesStaleShareRecordID() {
        let zoneID = CKRecordZone.ID(zoneName: "partner-primary-partner-space")
        let rootID = CKRecord.ID(recordName: "space-root", zoneID: zoneID)
        let shareID = CKRecord.ID(recordName: "ckshare-stale", zoneID: zoneID)
        let root = CKRecord(recordType: "PartnerSpace", recordID: rootID)
        _ = CKShare(rootRecord: root, shareID: shareID)

        let share = CloudKitPartnerSharingService.makeShare(on: root)

        XCTAssertEqual(share.recordID, shareID)
        XCTAssertEqual(share.publicPermission, .none)
    }

    func testInvitationLinkStoreKeepsCreatedLinksAcrossSessions() throws {
        let suiteName = "partner-invitation-links-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let firstStore = PartnerInvitationLinkStore(defaults: defaults)
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let link = PartnerInvitationLink(
            url: try XCTUnwrap(URL(string: "https://www.icloud.com/share/reopen-me")),
            createdAt: createdAt
        )

        firstStore.append(link, spaceID: "primary-partner-space")

        let reloaded = PartnerInvitationLinkStore(defaults: defaults)
            .load(spaceID: "primary-partner-space")
        XCTAssertEqual(reloaded, [link])
    }

    func testInvitationLinkStoreDeduplicatesAndClearsOnRevoke() throws {
        let suiteName = "partner-invitation-links-clear-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let store = PartnerInvitationLinkStore(defaults: defaults)
        let url = try XCTUnwrap(URL(string: "https://www.icloud.com/share/same-link"))
        let older = PartnerInvitationLink(url: url, createdAt: Date(timeIntervalSince1970: 10))
        let newer = PartnerInvitationLink(url: url, createdAt: Date(timeIntervalSince1970: 20))
        let other = PartnerInvitationLink(
            url: try XCTUnwrap(URL(string: "https://www.icloud.com/share/other-link")),
            createdAt: Date(timeIntervalSince1970: 15)
        )

        store.append(older, spaceID: "space")
        store.append(other, spaceID: "space")
        store.append(newer, spaceID: "space")

        XCTAssertEqual(store.load(spaceID: "space").map(\.url), [url, other.url])
        XCTAssertEqual(store.load(spaceID: "space").first?.createdAt, newer.createdAt)

        store.removeAll(spaceID: "space")
        XCTAssertTrue(store.load(spaceID: "space").isEmpty)
    }

    func testInvitationLinkMergeKeepsStoredCreatedAtAndAddsRemoteOnlyLinks() throws {
        let storedURL = try XCTUnwrap(URL(string: "https://www.icloud.com/share/stored"))
        let remoteOnlyURL = try XCTUnwrap(URL(string: "https://www.icloud.com/share/remote"))
        let stored = PartnerInvitationLink(url: storedURL, createdAt: Date(timeIntervalSince1970: 50))
        let remoteDuplicate = PartnerInvitationLink(url: storedURL, createdAt: Date(timeIntervalSince1970: 90))
        let remoteOnly = PartnerInvitationLink(url: remoteOnlyURL, createdAt: Date(timeIntervalSince1970: 80))

        let merged = PartnerInvitationLinkStore.merging(
            stored: [stored],
            remote: [remoteDuplicate, remoteOnly]
        )

        XCTAssertEqual(merged.map(\.url), [remoteOnlyURL, storedURL])
        XCTAssertEqual(merged.first(where: { $0.url == storedURL })?.createdAt, stored.createdAt)
    }

    private static let seasons = [
        SeasonSummary(
            id: "season-1",
            number: 1,
            title: "Season 1",
            episodes: [
                EpisodeSummary(id: "s1e1", number: 1, title: "Episode 1", airDate: nil, runtimeMinutes: 50),
                EpisodeSummary(id: "s1e2", number: 2, title: "Episode 2", airDate: nil, runtimeMinutes: 52)
            ]
        )
    ]
}
