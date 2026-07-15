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
        XCTAssertEqual(model.sharedSpace.activity.first?.titleID, "severance")
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

    func testPersonalWatchlistToggleDoesNotStartTitle() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)
        XCTAssertTrue(model.titles(in: .planned).contains(where: { $0.id == "past-lives" }))

        model.toggleWatchlist("past-lives")

        let title = model.titles.first(where: { $0.id == "past-lives" })
        XCTAssertEqual(title?.state, .planned)
        XCTAssertEqual(title?.isOnPersonalWatchlist, false)
        XCTAssertFalse(model.titles(in: .planned).contains(where: { $0.id == "past-lives" }))

        model.toggleWatchlist("past-lives")

        XCTAssertEqual(model.titles.first(where: { $0.id == "past-lives" })?.state, .planned)
        XCTAssertTrue(model.titles(in: .planned).contains(where: { $0.id == "past-lives" }))
    }

    func testMoodFiltersRecommendations() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)

        model.selectedMood = .funny

        XCTAssertFalse(model.recommendations.isEmpty)
        XCTAssertTrue(model.recommendations.allSatisfy { $0.mood == .funny })
    }

    func testDefaultRecommendationsOnlyUseOwnedServices() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)
        let expectedServices: Set<StreamingProvider.ID> = [.netflix, .primeVideo, .appleTV]

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
        await model.flushPendingPersistence()

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

    func testRefreshingCatalogDetailsPreservesTrackingAndLoadsEpisodes() async throws {
        var liveSnapshot = LibrarySnapshot.sample
        let liveIndex = try XCTUnwrap(liveSnapshot.titles.firstIndex(where: { $0.id == "severance" }))
        liveSnapshot.titles[liveIndex].rating = 9.2
        liveSnapshot.titles[liveIndex].reviews = [
            CommunityReview(
                id: "live-review",
                author: "Reviewer",
                excerpt: "Live review",
                rating: 9,
                source: "TMDB",
                containsSpoilers: false
            )
        ]
        liveSnapshot.titles[liveIndex].seasons = [
            SeasonSummary(
                id: "season-1",
                number: 1,
                title: "Season 1",
                episodes: [
                    EpisodeSummary(
                        id: "episode-1",
                        number: 1,
                        title: "Good News About Hell",
                        airDate: nil,
                        runtimeMinutes: 57
                    )
                ]
            )
        ]
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: LocalCatalogService(titles: liveSnapshot.titles),
            seed: .sample
        )

        await model.refreshCatalogDetails(for: "severance")

        let refreshed = try XCTUnwrap(model.mediaTitle(withID: "severance"))
        XCTAssertEqual(refreshed.id, "severance")
        XCTAssertEqual(refreshed.state, .watching)
        XCTAssertEqual(refreshed.progress?.episode, 3)
        XCTAssertEqual(refreshed.rating, 9.2)
        XCTAssertEqual(refreshed.reviews.first?.id, "live-review")
        XCTAssertEqual(refreshed.seasons?.first?.episodes.first?.runtimeMinutes, 57)
    }

    func testTrackingMetadataAndExplicitCorrectionPersist() async throws {
        let store = MemoryLibraryStore()
        let model = AppModel(store: store, seed: .sample)

        model.setWatchState(.paused, for: "severance")
        model.setUserRating(9.5, for: "severance")
        model.updateNotes("Pause after episode four.", for: "severance")
        model.correctProgress(
            EpisodeProgress(season: 2, episode: 2, totalEpisodes: 10),
            for: "severance"
        )
        await model.flushPendingPersistence()

        let saved = try await store.load()
        let title = try XCTUnwrap(saved?.titles.first(where: { $0.id == "severance" }))
        XCTAssertEqual(title.userRating, 9.5)
        XCTAssertEqual(title.notes, "Pause after episode four.")
        XCTAssertEqual(title.progress?.episode, 2)
        XCTAssertEqual(saved?.sharedSpace.watchEvents?.last?.kind, .correction)
    }

    func testOrdinaryWatchUpdateNeverMovesProgressBackward() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)

        model.markNextWatched("severance")
        model.markNextWatched("severance")

        XCTAssertEqual(model.titles.first(where: { $0.id == "severance" })?.progress?.episode, 5)
        XCTAssertEqual(model.sharedSpace.watchEvents?.filter { $0.titleID == "severance" }.count, 2)
    }

    func testLegacyProgressMapsToIndividualEpisodeRows() throws {
        var snapshot = LibrarySnapshot.sample
        let titleIndex = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[titleIndex].seasons = Self.episodeTrackingSeasons
        snapshot.titles[titleIndex].progress = EpisodeProgress(season: 2, episode: 1, totalEpisodes: 2)
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        XCTAssertTrue(model.isEpisodeWatched(titleID: "severance", seasonNumber: 1, episodeID: "s1e1"))
        XCTAssertTrue(model.isEpisodeWatched(titleID: "severance", seasonNumber: 1, episodeID: "s1e2"))
        XCTAssertTrue(model.isEpisodeWatched(titleID: "severance", seasonNumber: 2, episodeID: "s2e1"))
        XCTAssertFalse(model.isEpisodeWatched(titleID: "severance", seasonNumber: 2, episodeID: "s2e2"))
    }

    func testMarkWatchedCompletesEveryKnownEpisode() throws {
        var snapshot = LibrarySnapshot.sample
        let titleIndex = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[titleIndex].seasons = Self.episodeTrackingSeasons
        snapshot.titles[titleIndex].watchedEpisodeIDs = []
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        model.markWatched("severance")

        let title = try XCTUnwrap(model.mediaTitle(withID: "severance"))
        XCTAssertEqual(title.state, .completed)
        XCTAssertEqual(title.watchedEpisodeIDs, Set(["s1e1", "s1e2", "s2e1", "s2e2"]))
        XCTAssertEqual(model.progressSummary(for: title).fraction, 1)
    }

    func testEpisodeSwipeTrackingPersistsExactEpisode() async throws {
        var snapshot = LibrarySnapshot.sample
        let titleIndex = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[titleIndex].seasons = Self.episodeTrackingSeasons
        snapshot.titles[titleIndex].progress = EpisodeProgress(season: 1, episode: 0, totalEpisodes: 2)
        let store = MemoryLibraryStore()
        let model = AppModel(store: store, seed: snapshot)

        model.setEpisodeWatched(true, titleID: "severance", seasonNumber: 1, episodeID: "s1e1")
        await model.flushPendingPersistence()

        let storedSnapshot = try await store.load()
        let saved = try XCTUnwrap(storedSnapshot)
        let savedTitle = try XCTUnwrap(saved.titles.first(where: { $0.id == "severance" }))
        XCTAssertEqual(savedTitle.watchedEpisodeIDs, Set(["s1e1"]))
        XCTAssertEqual(savedTitle.progress, EpisodeProgress(season: 1, episode: 1, totalEpisodes: 2))
        XCTAssertEqual(savedTitle.state, .watching)
        XCTAssertEqual(saved.sharedSpace.watchEvents?.last?.season, 1)
        XCTAssertEqual(saved.sharedSpace.watchEvents?.last?.episode, 1)
    }

    func testMarkingEpisodeUnwatchedRemovesItFromAnalytics() throws {
        var snapshot = LibrarySnapshot.sample
        let titleIndex = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[titleIndex].seasons = Self.episodeTrackingSeasons
        snapshot.titles[titleIndex].progress = EpisodeProgress(season: 1, episode: 0, totalEpisodes: 2)
        snapshot.titles = [snapshot.titles[titleIndex]]
        snapshot.sharedSpace.watchEvents = []
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        model.setEpisodeWatched(true, titleID: "severance", seasonNumber: 1, episodeID: "s1e1")
        model.setEpisodeWatched(false, titleID: "severance", seasonNumber: 1, episodeID: "s1e1")

        XCTAssertFalse(model.isEpisodeWatched(titleID: "severance", seasonNumber: 1, episodeID: "s1e1"))
        XCTAssertEqual(
            ViewingAnalyticsEngine.summarize(snapshot: model.snapshot, scope: .personal).episodeCount,
            0
        )
        XCTAssertEqual(model.sharedSpace.watchEvents?.map(\.kind), [.watched, .correction])
    }

    private static let episodeTrackingSeasons = [
        SeasonSummary(
            id: "season-1",
            number: 1,
            title: "Season 1",
            episodes: [
                EpisodeSummary(id: "s1e1", number: 1, title: "Episode 1", airDate: nil, runtimeMinutes: 50),
                EpisodeSummary(id: "s1e2", number: 2, title: "Episode 2", airDate: nil, runtimeMinutes: 52)
            ]
        ),
        SeasonSummary(
            id: "season-2",
            number: 2,
            title: "Season 2",
            episodes: [
                EpisodeSummary(id: "s2e1", number: 1, title: "Episode 1", airDate: nil, runtimeMinutes: 48),
                EpisodeSummary(id: "s2e2", number: 2, title: "Episode 2", airDate: nil, runtimeMinutes: 54)
            ]
        )
    ]
}
