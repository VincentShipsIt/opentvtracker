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
