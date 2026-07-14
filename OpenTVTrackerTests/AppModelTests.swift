import XCTest
@testable import OpenTVTracker

@MainActor
final class AppModelTests: XCTestCase {
    func testMarkNextWatchedAdvancesEpisodeAndAddsActivity() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)
        let originalActivityCount = model.sharedSpace.activity.count

        model.markNextWatched("severance")

        let title = model.titles.first(where: { $0.id == "severance" })
        XCTAssertEqual(title?.progress?.episode, 4)
        XCTAssertEqual(model.sharedSpace.activity.count, originalActivityCount + 1)
        XCTAssertEqual(model.sharedSpace.activity.first?.memberID, "vincent")
    }

    func testMarkMovieWatchedCompletesIt() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)

        model.markNextWatched("past-lives")

        let title = model.titles.first(where: { $0.id == "past-lives" })
        XCTAssertEqual(title?.state, .completed)
    }

    func testFinalEpisodeLeavesUpNext() throws {
        var snapshot = LibrarySnapshot.sample
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[index].progress = EpisodeProgress(season: 2, episode: 9, totalEpisodes: 10)
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        model.markNextWatched("severance")

        XCTAssertFalse(model.upNext.contains(where: { $0.id == "severance" }))
        XCTAssertEqual(model.titles[index].state, .completed)
    }

    func testTogetherToggleIsReversible() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)
        XCTAssertTrue(model.isShared("past-lives"))

        model.toggleTogether("past-lives")
        XCTAssertFalse(model.isShared("past-lives"))

        model.toggleTogether("past-lives")
        XCTAssertTrue(model.isShared("past-lives"))
    }

    func testMoodFiltersRecommendations() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)

        model.selectedMood = .funny

        XCTAssertFalse(model.recommendations.isEmpty)
        XCTAssertTrue(model.recommendations.allSatisfy { $0.mood == .funny })
    }

    func testDefaultRecommendationsOnlyUseOwnedServices() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)
        let expectedServices: Set<StreamingProvider.ID> = ["netflix", "prime-video", "apple-tv"]

        XCTAssertEqual(model.selectedProviderIDs, expectedServices)
        XCTAssertFalse(model.recommendations.isEmpty)
        XCTAssertTrue(model.recommendations.allSatisfy { model.isAvailableOnSelectedProviders($0) })
    }

    func testTogglingProviderImmediatelyUpdatesRecommendations() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)

        model.toggleProvider(StreamingProvider.netflix.id)
        model.toggleProvider(StreamingProvider.primeVideo.id)
        model.toggleProvider(StreamingProvider.appleTV.id)

        XCTAssertTrue(model.selectedProviderIDs.isEmpty)
        XCTAssertTrue(model.recommendations.isEmpty)

        model.toggleProvider(StreamingProvider.netflix.id)

        XCTAssertEqual(model.recommendations.map(\.id), ["stranger-things"])
    }

    func testProviderSelectionPersists() async throws {
        let store = MemoryLibraryStore()
        let model = AppModel(store: store, seed: .sample)

        model.toggleProvider(StreamingProvider.netflix.id)
        try await Task.sleep(for: .milliseconds(250))

        let saved = try await store.load()
        XCTAssertFalse(try XCTUnwrap(saved?.selectedProviderIDs).contains(StreamingProvider.netflix.id))
    }

    func testLoadingRefreshesCatalogArtworkWithoutLosingProgress() async throws {
        var legacySnapshot = LibrarySnapshot.sample
        legacySnapshot.titles.removeAll(where: { $0.id == "fallout" })
        let severanceIndex = try XCTUnwrap(legacySnapshot.titles.firstIndex(where: { $0.id == "severance" }))
        legacySnapshot.titles[severanceIndex].posterURL = nil
        legacySnapshot.titles[severanceIndex].progress = EpisodeProgress(season: 2, episode: 7, totalEpisodes: 10)
        let store = MemoryLibraryStore(snapshot: legacySnapshot)
        let model = AppModel(store: store, seed: .sample)

        await model.load()

        let severance = try XCTUnwrap(model.titles.first(where: { $0.id == "severance" }))
        XCTAssertNotNil(severance.posterURL)
        XCTAssertEqual(severance.progress?.episode, 7)
        XCTAssertTrue(model.titles.contains(where: { $0.id == "fallout" }))
    }
}
