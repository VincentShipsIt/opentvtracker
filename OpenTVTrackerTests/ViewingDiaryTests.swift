import XCTest
@testable import OpenTVTracker

@MainActor
final class ViewingDiaryTests: XCTestCase {
    func testEpisodeWatchDateCanBeEditedRemovedAndRewatchedSeparately() throws {
        let model = try makeModel()
        let target = ViewingDiaryTarget.episode(
            titleID: "severance",
            seasonID: "season-1",
            seasonNumber: 1,
            episodeID: "s1e1",
            episodeNumber: 1
        )

        model.setEpisodeWatched(true, titleID: "severance", seasonNumber: 1, episodeID: "s1e1")

        let firstWatch = try XCTUnwrap(model.diaryEntries(for: target).first)
        XCTAssertNotNil(firstWatch.watchedAt)
        XCTAssertFalse(firstWatch.isRewatch)

        let editedDate = Date(timeIntervalSince1970: 1_700_000_000)
        model.updateDiaryWatchDate(editedDate, entryID: firstWatch.id)
        XCTAssertEqual(model.diaryEntries(for: target).first?.watchedAt, editedDate)

        model.updateDiaryWatchDate(nil, entryID: firstWatch.id)
        XCTAssertNil(model.diaryEntries(for: target).first?.watchedAt)
        XCTAssertTrue(model.isEpisodeWatched(titleID: "severance", seasonNumber: 1, episodeID: "s1e1"))

        let rewatchDate = Date(timeIntervalSince1970: 1_800_000_000)
        model.recordEpisodeRewatch(
            titleID: "severance",
            seasonNumber: 1,
            episodeID: "s1e1",
            watchedAt: rewatchDate
        )

        let entries = model.diaryEntries(for: target)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first(where: \.isRewatch)?.watchedAt, rewatchDate)
        XCTAssertEqual(model.sharedSpace.watchEvents?.last?.kind, .rewatch)
    }

    func testSeasonRatingAndNoteRemainPrivateDiaryMetadata() throws {
        let model = try makeModel()
        let target = ViewingDiaryTarget.season(
            titleID: "severance",
            seasonID: "season-1",
            seasonNumber: 1
        )

        model.updateDiaryRating(8.5, for: target)
        model.updateDiaryNote("The finale pays off the setup.", for: target)

        XCTAssertEqual(model.diaryRating(for: target), 8.5)
        XCTAssertEqual(model.diaryNote(for: target), "The finale pays off the setup.")
        XCTAssertEqual(model.diaryEntries(for: target).count, 1)
        XCTAssertNil(model.diaryEntries(for: target).first?.watchedAt)
        XCTAssertNil(model.sharedSpace.notes?.first(where: { $0.titleID == "severance" }))
    }

    func testUnwatchRemovesEpisodeDatesButPreservesPrivateRating() throws {
        let model = try makeModel()
        let target = ViewingDiaryTarget.episode(
            titleID: "severance",
            seasonID: "season-1",
            seasonNumber: 1,
            episodeID: "s1e1",
            episodeNumber: 1
        )
        model.setEpisodeWatched(true, titleID: "severance", seasonNumber: 1, episodeID: "s1e1")
        model.updateDiaryRating(9, for: target)

        model.setEpisodeWatched(false, titleID: "severance", seasonNumber: 1, episodeID: "s1e1")

        XCTAssertFalse(model.isDiaryTargetWatched(target))
        XCTAssertEqual(model.diaryRating(for: target), 9)
        XCTAssertTrue(model.diaryEntries(for: target).allSatisfy { $0.watchedAt == nil })
    }

    func testDiaryDaysAreNewestFirst() throws {
        let model = try makeModel()
        let target = ViewingDiaryTarget.title(titleID: "past-lives")
        model.recordDiaryWatch(
            for: target,
            watchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isRewatch: false
        )
        model.recordDiaryWatch(
            for: target,
            watchedAt: Date(timeIntervalSince1970: 1_800_000_000),
            isRewatch: true
        )

        XCTAssertEqual(model.diaryRecords.map(\.entry.isRewatch), [true, false])
        XCTAssertGreaterThan(model.diaryDays[0].date, model.diaryDays[1].date)
    }

    func testLegacyWatchEventsMigrateOnceAndIgnoreCorrectionsAndOtherMembers() throws {
        var snapshot = try makeSnapshot()
        let watchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        snapshot.diaryEntries = nil
        snapshot.sharedSpace.watchEvents = legacyEvents(at: watchedAt)

        let firstModel = AppModel(store: MemoryLibraryStore(), seed: snapshot)
        let migrated = try XCTUnwrap(firstModel.diaryEntries.first)
        XCTAssertEqual(firstModel.diaryEntries.count, 1)
        XCTAssertEqual(migrated.id, "diary:current-watch")
        XCTAssertEqual(migrated.episodeID, "s1e1")

        let secondModel = AppModel(store: MemoryLibraryStore(), seed: firstModel.snapshot)
        XCTAssertEqual(secondModel.diaryEntries, firstModel.diaryEntries)
    }

    private func legacyEvents(at watchedAt: Date) -> [SharedWatchEvent] {
        [
            SharedWatchEvent(
                id: "current-watch",
                titleID: "severance",
                memberID: "local-user",
                kind: .watched,
                season: 1,
                episode: 1,
                occurredAt: watchedAt,
                supersedesEventID: nil
            ),
            SharedWatchEvent(
                id: "superseded-watch",
                titleID: "severance",
                memberID: "local-user",
                kind: .watched,
                season: 1,
                episode: 2,
                occurredAt: watchedAt,
                supersedesEventID: nil
            ),
            SharedWatchEvent(
                id: "correction",
                titleID: "severance",
                memberID: "local-user",
                kind: .correction,
                season: 1,
                episode: 2,
                occurredAt: watchedAt,
                supersedesEventID: "superseded-watch"
            ),
            SharedWatchEvent(
                id: "partner-watch",
                titleID: "severance",
                memberID: "partner",
                kind: .watched,
                season: 1,
                episode: 1,
                occurredAt: watchedAt,
                supersedesEventID: nil
            )
        ]
    }

    func testTrackingEditsStayInSyncWithTitleDiaryMetadata() throws {
        let model = try makeModel()
        let target = ViewingDiaryTarget.title(titleID: "past-lives")
        model.updateDiaryRating(9, for: target)
        model.updateDiaryNote("Original note", for: target)

        model.setUserRating(3, for: "past-lives")
        model.updateNotes("Updated note", for: "past-lives")

        XCTAssertEqual(model.diaryRating(for: target), 3)
        XCTAssertEqual(model.diaryNote(for: target), "Updated note")
        XCTAssertEqual(model.diaryEntries(for: target).first?.rating, 3)
        XCTAssertEqual(model.diaryEntries(for: target).first?.note, "Updated note")
    }

    func testCompletingSeriesDoesNotDuplicateExistingEpisodeWatch() throws {
        let model = try makeModel()
        let firstTarget = ViewingDiaryTarget.episode(
            titleID: "severance",
            seasonID: "season-1",
            seasonNumber: 1,
            episodeID: "s1e1",
            episodeNumber: 1
        )
        let secondTarget = ViewingDiaryTarget.episode(
            titleID: "severance",
            seasonID: "season-1",
            seasonNumber: 1,
            episodeID: "s1e2",
            episodeNumber: 2
        )
        model.setEpisodeWatched(true, titleID: "severance", seasonNumber: 1, episodeID: "s1e1")

        model.markWatched("severance")

        XCTAssertEqual(model.diaryEntries(for: firstTarget).filter { $0.watchedAt != nil }.count, 1)
        XCTAssertEqual(model.diaryEntries(for: secondTarget).filter { $0.watchedAt != nil }.count, 1)
        XCTAssertTrue(model.diaryEntries(for: .title(titleID: "severance")).isEmpty)
    }

    func testWatchNextAndTogetherRecordEpisodeScopeOnly() throws {
        let soloModel = try makeModel()
        soloModel.markNextWatched("severance")
        XCTAssertEqual(soloModel.diaryEntries.first?.episodeID, "s1e1")
        XCTAssertFalse(soloModel.diaryEntries.contains { $0.scope == .title })

        let togetherModel = try makeModel()
        togetherModel.markWatchedTogether("severance")
        XCTAssertEqual(togetherModel.diaryEntries.first?.episodeID, "s1e1")
        XCTAssertFalse(togetherModel.diaryEntries.contains { $0.scope == .title })
    }

    private func makeModel() throws -> AppModel {
        AppModel(store: MemoryLibraryStore(), seed: try makeSnapshot())
    }

    private func makeSnapshot() throws -> LibrarySnapshot {
        var snapshot = LibrarySnapshot.sample
        let titleIndex = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[titleIndex].state = .planned
        snapshot.titles[titleIndex].progress = EpisodeProgress(season: 1, episode: 0, totalEpisodes: 2)
        snapshot.titles[titleIndex].watchedEpisodeIDs = []
        snapshot.titles[titleIndex].seasons = [
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
        snapshot.sharedSpace.watchEvents = []
        snapshot.diaryEntries = []
        return snapshot
    }
}
