import XCTest
@testable import OpenTVTracker

@MainActor
final class EpisodeTrackingTests: XCTestCase {
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

    func testMarkThisAndPreviousWatchedIncludesEarlierSeasons() throws {
        let model = try makeModel()

        model.markEpisodesWatchedThrough(titleID: "severance", seasonNumber: 2, episodeNumber: 1)

        XCTAssertTrue(model.isEpisodeWatched(titleID: "severance", seasonNumber: 1, episodeID: "s1e1"))
        XCTAssertTrue(model.isEpisodeWatched(titleID: "severance", seasonNumber: 1, episodeID: "s1e2"))
        XCTAssertTrue(model.isEpisodeWatched(titleID: "severance", seasonNumber: 2, episodeID: "s2e1"))
        XCTAssertFalse(model.isEpisodeWatched(titleID: "severance", seasonNumber: 2, episodeID: "s2e2"))
        XCTAssertTrue(
            model.areEpisodesWatchedThrough(
                titleID: "severance",
                seasonNumber: 2,
                episodeNumber: 1
            )
        )
        XCTAssertEqual(
            model.mediaTitle(withID: "severance")?.progress,
            EpisodeProgress(season: 2, episode: 1, totalEpisodes: 2)
        )
        XCTAssertEqual(model.sharedSpace.watchEvents?.filter { $0.titleID == "severance" }.count, 3)
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

    private func makeModel() throws -> AppModel {
        var snapshot = LibrarySnapshot.sample
        let titleIndex = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[titleIndex].seasons = Self.seasons
        snapshot.titles[titleIndex].progress = EpisodeProgress(season: 1, episode: 0, totalEpisodes: 2)
        snapshot.titles[titleIndex].watchedEpisodeIDs = []
        snapshot.sharedSpace.watchEvents = []
        return AppModel(store: MemoryLibraryStore(), seed: snapshot)
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
