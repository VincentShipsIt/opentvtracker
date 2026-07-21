import XCTest
@testable import OpenTVTracker

@MainActor
final class UpNextIntentTests: XCTestCase {
    func testSchemaFiveCompletedContinuingSeriesMigratesToCaughtUp() throws {
        var snapshot = LibrarySnapshot.sample
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[index].state = .completed
        snapshot.titles[index].seriesLifecycle = .continuing
        snapshot.schemaVersion = 5

        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        XCTAssertEqual(model.mediaTitle(withID: "severance")?.state, .caughtUp)
    }

    func testEndedSeriesKeepsCompletedSemantics() throws {
        var snapshot = LibrarySnapshot.sample
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[index].state = .completed
        snapshot.titles[index].seriesLifecycle = .ended

        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        XCTAssertEqual(model.mediaTitle(withID: "severance")?.state, .completed)
    }

    func testWatchingFinalAvailableEpisodeUsesCatalogLifecycle() throws {
        let continuing = try modelWithSingleEpisode(lifecycle: .continuing)
        continuing.setEpisodeWatched(
            true,
            titleID: "severance",
            seasonNumber: 1,
            episodeID: "s1e1"
        )

        XCTAssertEqual(continuing.mediaTitle(withID: "severance")?.state, .caughtUp)
        XCTAssertTrue(continuing.upNext.isEmpty)

        let ended = try modelWithSingleEpisode(lifecycle: .ended)
        ended.setEpisodeWatched(
            true,
            titleID: "severance",
            seasonNumber: 1,
            episodeID: "s1e1"
        )

        XCTAssertEqual(ended.mediaTitle(withID: "severance")?.state, .completed)
    }

    func testCurrentSchemaPreservesManualCompletedAndWatchingStates() throws {
        var snapshot = LibrarySnapshot.sample
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles = [snapshot.titles[index]]
        snapshot.titles[0].state = .completed
        snapshot.titles[0].seriesLifecycle = .continuing

        let completed = AppModel(store: MemoryLibraryStore(), seed: snapshot)
        XCTAssertEqual(completed.mediaTitle(withID: "severance")?.state, .completed)

        snapshot.titles[0].state = .watching
        snapshot.titles[0].watchedEpisodeIDs = Set(
            snapshot.titles[0].seasons?.flatMap(\.episodes).map(\.id) ?? []
        )
        let watching = AppModel(store: MemoryLibraryStore(), seed: snapshot)
        XCTAssertEqual(watching.mediaTitle(withID: "severance")?.state, .watching)
    }

    func testManualTerminalStateRespectsSeriesLifecycle() throws {
        let continuing = try modelWithSingleEpisode(lifecycle: .continuing)
        continuing.setWatchState(.caughtUp, for: "severance")
        XCTAssertEqual(continuing.mediaTitle(withID: "severance")?.state, .caughtUp)

        let eventCount = continuing.sharedSpace.watchEvents?.count
        let lastWatchedAt = continuing.mediaTitle(withID: "severance")?.lastWatchedAt
        continuing.setWatchState(.caughtUp, for: "severance")
        XCTAssertEqual(continuing.sharedSpace.watchEvents?.count, eventCount)
        XCTAssertEqual(continuing.mediaTitle(withID: "severance")?.lastWatchedAt, lastWatchedAt)

        continuing.setWatchState(.completed, for: "severance")
        XCTAssertEqual(continuing.mediaTitle(withID: "severance")?.state, .completed)

        let ended = try modelWithSingleEpisode(lifecycle: .ended)
        ended.setWatchState(.caughtUp, for: "severance")
        XCTAssertEqual(ended.mediaTitle(withID: "severance")?.state, .completed)

        var movieSnapshot = LibrarySnapshot.sample
        let movieIndex = try XCTUnwrap(movieSnapshot.titles.firstIndex(where: { $0.kind == .movie }))
        movieSnapshot.titles = [movieSnapshot.titles[movieIndex]]
        let movie = AppModel(store: MemoryLibraryStore(), seed: movieSnapshot)
        movie.setWatchState(.caughtUp, for: movieSnapshot.titles[0].id)
        XCTAssertEqual(movie.mediaTitle(withID: movieSnapshot.titles[0].id)?.state, .completed)
    }

    func testNewEpisodeResumesCaughtUpSeriesWithoutLosingManualIntent() throws {
        var snapshot = LibrarySnapshot.sample
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles = [snapshot.titles[index]]
        snapshot.titles[0].state = .caughtUp
        snapshot.titles[0].seriesLifecycle = .continuing
        snapshot.titles[0].seasons = [
            SeasonSummary(
                id: "season-1",
                number: 1,
                title: "Season 1",
                episodes: [
                    EpisodeSummary(id: "s1e1", number: 1, title: "Episode 1", airDate: nil, runtimeMinutes: 50)
                ]
            )
        ]
        snapshot.titles[0].watchedEpisodeIDs = ["s1e1"]
        snapshot.titles[0].progress = EpisodeProgress(season: 1, episode: 1, totalEpisodes: 1)
        snapshot.titles[0].isUpNextPinned = true
        snapshot.titles[0].upNextManualOrder = 4
        snapshot.titles[0].upNextSnoozedUntil = Date(timeIntervalSince1970: 2_000_000_000)
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        var refreshed = snapshot.titles[0]
        refreshed.state = .planned
        refreshed.watchedEpisodeIDs = nil
        refreshed.progress = nil
        refreshed.isUpNextPinned = nil
        refreshed.upNextManualOrder = nil
        refreshed.upNextSnoozedUntil = nil
        refreshed.seasons = [
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

        model.mergeCatalogTitles([refreshed])

        let title = try XCTUnwrap(model.mediaTitle(withID: "severance"))
        XCTAssertEqual(title.state, .watching)
        XCTAssertEqual(title.watchedEpisodeIDs, ["s1e1"])
        XCTAssertEqual(title.isUpNextPinned, true)
        XCTAssertEqual(title.upNextManualOrder, 4)
        XCTAssertEqual(title.upNextSnoozedUntil, Date(timeIntervalSince1970: 2_000_000_000))
    }

    func testLegacyProgressKeepsNewReleaseUnwatchedWhenEpisodeIDsAreMissing() throws {
        var snapshot = LibrarySnapshot.sample
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles = [snapshot.titles[index]]
        snapshot.titles[0].state = .caughtUp
        snapshot.titles[0].seriesLifecycle = .continuing
        snapshot.titles[0].watchedEpisodeIDs = nil
        snapshot.titles[0].progress = EpisodeProgress(season: 1, episode: 0, totalEpisodes: 1)
        snapshot.titles[0].seasons = [
            SeasonSummary(
                id: "season-1",
                number: 1,
                title: "Season 1",
                episodes: [
                    EpisodeSummary(id: "s1e1", number: 1, title: "Episode 1", airDate: nil, runtimeMinutes: 50)
                ]
            )
        ]

        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        XCTAssertEqual(model.mediaTitle(withID: "severance")?.state, .watching)
    }

    func testPinSnoozeAndMoveLowerDeterministicallyReorderQueue() throws {
        var snapshot = LibrarySnapshot.sample
        snapshot.titles = snapshot.titles.filter { ["severance", "the-bear"].contains($0.id) }
        let severanceIndex = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        let bearIndex = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "the-bear" }))
        snapshot.titles[severanceIndex].lastWatchedAt = Date(timeIntervalSince1970: 200)
        snapshot.titles[bearIndex].lastWatchedAt = Date(timeIntervalSince1970: 100)
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        XCTAssertEqual(model.upNext.map(\.id), ["severance", "the-bear"])

        model.setUpNextPinned(true, for: "the-bear")
        XCTAssertEqual(model.upNext.first?.id, "the-bear")

        model.snoozeUpNext("the-bear", until: Date(timeIntervalSinceNow: 3_600))
        XCTAssertFalse(model.upNext.contains(where: { $0.id == "the-bear" }))

        model.snoozeUpNext("the-bear", until: nil)
        model.setUpNextPinned(false, for: "the-bear")
        model.moveUpNextLower("severance")

        XCTAssertEqual(model.upNext.map(\.id), ["the-bear", "severance"])

        if let bearIndex = model.titles.firstIndex(where: { $0.id == "the-bear" }) {
            model.titles[bearIndex].isUpNextPinned = false
        }
        XCTAssertEqual(model.upNext.map(\.id), ["the-bear", "severance"])
    }

    func testStaleQueueSeparatesTitlesIdleForThirtyDays() throws {
        var snapshot = LibrarySnapshot.sample
        snapshot.titles = snapshot.titles.filter { ["severance", "the-bear"].contains($0.id) }
        let severanceIndex = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        let bearIndex = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "the-bear" }))
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        snapshot.titles[severanceIndex].lastWatchedAt = Calendar.current.date(
            byAdding: .day,
            value: -31,
            to: now
        )
        snapshot.titles[bearIndex].lastWatchedAt = Calendar.current.date(
            byAdding: .day,
            value: -2,
            to: now
        )
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        XCTAssertEqual(model.staleUpNext(at: now).map(\.id), ["severance"])
    }

    func testNewWatchingTitleWithoutWatchDateStaysInActiveQueue() throws {
        var snapshot = LibrarySnapshot.sample
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles = [snapshot.titles[index]]
        snapshot.titles[0].state = .watching
        snapshot.titles[0].lastWatchedAt = nil
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        XCTAssertTrue(model.staleUpNext(at: Date(timeIntervalSince1970: 2_000_000_000)).isEmpty)
        XCTAssertEqual(model.activeUpNext.map(\.id), ["severance"])
    }

    func testCompletingCaughtUpSeriesIncludesNewlyReleasedEpisodes() throws {
        var snapshot = LibrarySnapshot.sample
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles = [snapshot.titles[index]]
        snapshot.titles[0].state = .caughtUp
        snapshot.titles[0].seriesLifecycle = .continuing
        snapshot.titles[0].watchedEpisodeIDs = ["s1e1"]
        snapshot.titles[0].progress = EpisodeProgress(season: 1, episode: 1, totalEpisodes: 2)
        snapshot.titles[0].seasons = [
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
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        model.setWatchState(.completed, for: "severance")

        XCTAssertEqual(model.mediaTitle(withID: "severance")?.state, .completed)
        XCTAssertEqual(model.mediaTitle(withID: "severance")?.watchedEpisodeIDs, ["s1e1", "s1e2"])
    }

    private func modelWithSingleEpisode(lifecycle: SeriesLifecycle) throws -> AppModel {
        var snapshot = LibrarySnapshot.sample
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles = [snapshot.titles[index]]
        snapshot.titles[0].state = .watching
        snapshot.titles[0].seriesLifecycle = lifecycle
        snapshot.titles[0].progress = EpisodeProgress(season: 1, episode: 0, totalEpisodes: 1)
        snapshot.titles[0].watchedEpisodeIDs = []
        snapshot.titles[0].seasons = [
            SeasonSummary(
                id: "season-1",
                number: 1,
                title: "Season 1",
                episodes: [
                    EpisodeSummary(id: "s1e1", number: 1, title: "Episode 1", airDate: nil, runtimeMinutes: 50)
                ]
            )
        ]
        return AppModel(store: MemoryLibraryStore(), seed: snapshot)
    }
}
