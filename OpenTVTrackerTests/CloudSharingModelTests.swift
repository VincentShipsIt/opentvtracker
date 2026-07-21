import XCTest
@testable import OpenTVTracker

@MainActor
final class CloudSharingModelTests: XCTestCase {
    func testTogetherToggleStoresSanitizedMetadataAndIsReversible() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)
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
