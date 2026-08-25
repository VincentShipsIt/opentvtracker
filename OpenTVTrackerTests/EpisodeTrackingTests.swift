import XCTest
@testable import OpenTVTracker

@MainActor
final class EpisodeTrackingTests: XCTestCase {
    func testMarkWatchedFromCatalogAddsTitleToRecommendationHistory() async throws {
        let catalog = LocalCatalogService(titles: LibrarySnapshot.sample.titles)
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: catalog,
            seed: .empty
        )

        await model.searchCatalog(text: "Past Lives")
        model.markWatched("past-lives")

        let title = try XCTUnwrap(model.mediaTitle(withID: "past-lives"))
        XCTAssertEqual(title.state, .completed)
        XCTAssertFalse(title.isOnPersonalWatchlist)
        XCTAssertNotNil(title.lastWatchedAt)
        XCTAssertEqual(model.sharedSpace.watchEvents?.last?.kind, .watched)
    }

    func testTogetherActivityExcludesCurrentUsersSoloViewing() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)

        XCTAssertFalse(model.togetherActivity.contains(where: { $0.id == "activity-2" }))
        XCTAssertTrue(model.togetherActivity.contains(where: { $0.id == "activity-1" }))
        XCTAssertTrue(model.togetherActivity.contains(where: { $0.id == "activity-3" }))
    }

    func testLibraryHistorySortsMostRecentlyWatchedFirst() throws {
        var snapshot = LibrarySnapshot.sample
        let olderIndex = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        let newerIndex = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "arrival" }))
        snapshot.titles[olderIndex].lastWatchedAt = Date(timeIntervalSince1970: 100)
        snapshot.titles[newerIndex].lastWatchedAt = Date(timeIntervalSince1970: 200)
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        XCTAssertEqual(model.recentlyWatchedTitles.map(\.id), ["arrival", "severance"])
    }

    func testMarkAllSeasonEpisodesWatchedUpdatesEveryEpisodeOnce() throws {
        let model = try makeModel()
        let originalActivityCount = model.sharedSpace.activity.count

        model.setSeasonEpisodesWatched(true, titleID: "severance", seasonNumber: 1)

        XCTAssertTrue(model.isEpisodeWatched(titleID: "severance", seasonNumber: 1, episodeID: "s1e1"))
        XCTAssertTrue(model.isEpisodeWatched(titleID: "severance", seasonNumber: 1, episodeID: "s1e2"))
        XCTAssertFalse(model.isEpisodeWatched(titleID: "severance", seasonNumber: 2, episodeID: "s2e1"))
        XCTAssertEqual(
            model.mediaTitle(withID: "severance")?.progress,
            EpisodeProgress(season: 1, episode: 2, totalEpisodes: 2)
        )
        XCTAssertEqual(model.sharedSpace.watchEvents?.filter { $0.titleID == "severance" }.count, 2)
        XCTAssertEqual(model.sharedSpace.activity.count, originalActivityCount + 1)
    }

    func testMarkThisAndPreviousWatchedOnlyIncludesCurrentSeason() throws {
        let model = try makeModel()

        model.markEpisodesWatchedThrough(titleID: "severance", seasonNumber: 2, episodeNumber: 2)

        XCTAssertFalse(model.isEpisodeWatched(titleID: "severance", seasonNumber: 1, episodeID: "s1e1"))
        XCTAssertFalse(model.isEpisodeWatched(titleID: "severance", seasonNumber: 1, episodeID: "s1e2"))
        XCTAssertTrue(model.isEpisodeWatched(titleID: "severance", seasonNumber: 2, episodeID: "s2e1"))
        XCTAssertTrue(model.isEpisodeWatched(titleID: "severance", seasonNumber: 2, episodeID: "s2e2"))
        XCTAssertTrue(
            model.areEpisodesWatchedThrough(
                titleID: "severance",
                seasonNumber: 2,
                episodeNumber: 2
            )
        )
        XCTAssertEqual(
            model.mediaTitle(withID: "severance")?.progress,
            EpisodeProgress(season: 2, episode: 2, totalEpisodes: 6)
        )
        XCTAssertEqual(model.sharedSpace.watchEvents?.filter { $0.titleID == "severance" }.count, 2)
    }

    func testMarkEpisodeSixWatchedThroughRecordsEachEpisodeOnceForRecommendations() throws {
        let model = try makeModel()
        let initialProfile = RecommendationViewingProfiler.profile(from: model.snapshot)

        model.setEpisodeWatched(true, titleID: "severance", seasonNumber: 2, episodeID: "s2e2")
        XCTAssertTrue(
            model.hasUnwatchedEpisodesBefore(
                titleID: "severance",
                seasonNumber: 2,
                episodeNumber: 6
            )
        )

        model.markEpisodesWatchedThrough(titleID: "severance", seasonNumber: 2, episodeNumber: 6)

        for episodeNumber in 1...6 {
            XCTAssertTrue(
                model.isEpisodeWatched(
                    titleID: "severance",
                    seasonNumber: 2,
                    episodeID: "s2e\(episodeNumber)"
                )
            )
        }
        XCTAssertFalse(model.isEpisodeWatched(titleID: "severance", seasonNumber: 1, episodeID: "s1e1"))
        XCTAssertFalse(
            model.hasUnwatchedEpisodesBefore(
                titleID: "severance",
                seasonNumber: 2,
                episodeNumber: 6
            )
        )
        XCTAssertEqual(model.sharedSpace.watchEvents?.filter { $0.titleID == "severance" }.count, 6)

        let profile = RecommendationViewingProfiler.profile(from: model.snapshot)
        XCTAssertEqual(profile.watchedEpisodeCount, initialProfile.watchedEpisodeCount + 6)
        XCTAssertEqual(profile.recentTitles.first?.watchedEpisodeCount, 6)
        XCTAssertTrue(profile.topGenres.contains(where: { $0.genre == "Drama" }))
    }

    func testMarkAllSeasonEpisodesUnwatchedCreatesCorrections() throws {
        let model = try makeModel()

        model.setSeasonEpisodesWatched(true, titleID: "severance", seasonNumber: 1)
        model.setSeasonEpisodesWatched(false, titleID: "severance", seasonNumber: 1)

        XCTAssertEqual(model.watchedEpisodeCount(titleID: "severance", season: Self.seasons[0]), 0)
        XCTAssertEqual(model.sharedSpace.watchEvents?.map(\.kind), [
            .watched, .watched, .correction, .correction
        ])
    }

    func testMarkSeasonZeroSpecialsWatchedUsesRequestedSeason() throws {
        let model = try makeModel(includingSpecials: true)

        model.setSeasonEpisodesWatched(true, titleID: "severance", seasonNumber: 0)

        XCTAssertTrue(model.isEpisodeWatched(titleID: "severance", seasonNumber: 0, episodeID: "s0e1"))
        XCTAssertTrue(model.isEpisodeWatched(titleID: "severance", seasonNumber: 0, episodeID: "s0e2"))
        XCTAssertFalse(model.isEpisodeWatched(titleID: "severance", seasonNumber: 1, episodeID: "s1e1"))

        model.setSeasonEpisodesWatched(false, titleID: "severance", seasonNumber: 0)
        XCTAssertTrue(
            model.hasUnwatchedEpisodesBefore(
                titleID: "severance",
                seasonNumber: 0,
                episodeNumber: 2
            )
        )

        model.markEpisodesWatchedThrough(titleID: "severance", seasonNumber: 0, episodeNumber: 2)
        XCTAssertTrue(model.isEpisodeWatched(titleID: "severance", seasonNumber: 0, episodeID: "s0e2"))
        XCTAssertFalse(
            model.hasUnwatchedEpisodesBefore(
                titleID: "severance",
                seasonNumber: 0,
                episodeNumber: 2
            )
        )
    }

    func testProgressSummaryCountsEpisodesAcrossSeasons() throws {
        let model = try makeModel()

        model.markEpisodesWatchedThrough(titleID: "severance", seasonNumber: 2, episodeNumber: 1)

        let title = try XCTUnwrap(model.mediaTitle(withID: "severance"))
        let summary = model.progressSummary(for: title)
        XCTAssertEqual(summary.label, "1 of 8 episodes")
        XCTAssertEqual(summary.fraction, 0.125)
    }

    private func makeModel(includingSpecials: Bool = false) throws -> AppModel {
        var snapshot = LibrarySnapshot.sample
        let titleIndex = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[titleIndex].seasons = includingSpecials ? Self.seasonsWithSpecials : Self.seasons
        snapshot.titles[titleIndex].progress = EpisodeProgress(season: 1, episode: 0, totalEpisodes: 2)
        snapshot.titles[titleIndex].watchedEpisodeIDs = []
        snapshot.sharedSpace.watchEvents = []
        return AppModel(store: MemoryLibraryStore(), seed: snapshot)
    }

    private static let seasonsWithSpecials = [
        SeasonSummary(
            id: "season-0",
            number: 0,
            title: "Specials",
            episodes: [
                EpisodeSummary(id: "s0e1", number: 1, title: "Special 1", airDate: nil, runtimeMinutes: 20),
                EpisodeSummary(id: "s0e2", number: 2, title: "Special 2", airDate: nil, runtimeMinutes: 22)
            ]
        )
    ] + seasons

    private static let seasons = [
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
                EpisodeSummary(id: "s2e2", number: 2, title: "Episode 2", airDate: nil, runtimeMinutes: 54),
                EpisodeSummary(id: "s2e3", number: 3, title: "Episode 3", airDate: nil, runtimeMinutes: 51),
                EpisodeSummary(id: "s2e4", number: 4, title: "Episode 4", airDate: nil, runtimeMinutes: 49),
                EpisodeSummary(id: "s2e5", number: 5, title: "Episode 5", airDate: nil, runtimeMinutes: 50),
                EpisodeSummary(id: "s2e6", number: 6, title: "Episode 6", airDate: nil, runtimeMinutes: 53)
            ]
        )
    ]
}

extension AppModelTests {
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

    /// Marking a show watched has to land in analytics as the whole show. It used to write one
    /// series-scoped event, and analytics counts events — so a season's worth of viewing was
    /// credited a single episode's runtime.
    func testMarkWatchedCreditsEveryEpisodeToAnalytics() throws {
        var snapshot = LibrarySnapshot.sample
        let titleIndex = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[titleIndex].seasons = Self.episodeTrackingSeasons
        snapshot.titles[titleIndex].watchedEpisodeIDs = []
        snapshot.titles = [snapshot.titles[titleIndex]]
        snapshot.sharedSpace.watchEvents = []
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        model.markWatched("severance")

        let summary = ViewingAnalyticsEngine.summarize(snapshot: model.snapshot, scope: .personal)
        XCTAssertEqual(summary.episodeCount, 4)
        XCTAssertEqual(summary.totalMinutes, 50 + 52 + 48 + 54)
        // Every event is episode-scoped, which is what lets analytics resolve real runtimes
        // instead of falling back to the title's.
        let events = try XCTUnwrap(model.sharedSpace.watchEvents)
        XCTAssertEqual(events.count, 4)
        XCTAssertTrue(events.allSatisfy { $0.season != nil && $0.episode != nil })
    }

    /// The whole-show action is offered from the details menu only while it would do something.
    func testUnwatchedReleasedEpisodesDrivesTheWholeShowAction() throws {
        var snapshot = LibrarySnapshot.sample
        let titleIndex = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[titleIndex].seasons = Self.episodeTrackingSeasons
        snapshot.titles[titleIndex].watchedEpisodeIDs = []
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        let title = try XCTUnwrap(model.mediaTitle(withID: "severance"))
        XCTAssertTrue(model.hasUnwatchedReleasedEpisodes(for: title))

        model.markWatched("severance")

        let watched = try XCTUnwrap(model.mediaTitle(withID: "severance"))
        XCTAssertFalse(model.hasUnwatchedReleasedEpisodes(for: watched))

        let movie = try XCTUnwrap(model.mediaTitle(withID: "past-lives"))
        XCTAssertFalse(model.hasUnwatchedReleasedEpisodes(for: movie))
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
}

private extension AppModelTests {
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
