import XCTest
@testable import OpenTVTracker

final class BackupHealthTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testMissingTimestampHasNoCompleteBackup() {
        XCTAssertNil(BackupHealth.lastSuccessfulExportAt(from: 0))
        XCTAssertEqual(
            BackupHealth.state(lastSuccessfulExportAt: nil, now: now),
            .neverExported
        )
    }

    func testBackupRemainsCurrentBeforeThirtyDays() {
        let lastExportedAt = now.addingTimeInterval(-(BackupHealth.reminderInterval - 1))

        XCTAssertEqual(
            BackupHealth.state(lastSuccessfulExportAt: lastExportedAt, now: now),
            .current(lastExportedAt: lastExportedAt)
        )
    }

    func testBackupBecomesDueAtThirtyDays() {
        let lastExportedAt = now.addingTimeInterval(-BackupHealth.reminderInterval)

        XCTAssertEqual(
            BackupHealth.state(lastSuccessfulExportAt: lastExportedAt, now: now),
            .due(lastExportedAt: lastExportedAt)
        )
    }

    func testFutureTimestampFromClockCorrectionRemainsCurrent() {
        let lastExportedAt = now.addingTimeInterval(60)

        XCTAssertEqual(
            BackupHealth.state(lastSuccessfulExportAt: lastExportedAt, now: now),
            .current(lastExportedAt: lastExportedAt)
        )
    }

    func testOnlyCompleteJSONSatisfiesBackupReminder() {
        XCTAssertTrue(LibraryExportKind.json.completesBackup)
        XCTAssertFalse(LibraryExportKind.titlesCSV.completesBackup)
        XCTAssertFalse(LibraryExportKind.eventsCSV.completesBackup)
        XCTAssertFalse(LibraryExportKind.preImportRollback.completesBackup)
        XCTAssertEqual(
            LibraryExportKind.preImportRollback.successMessage,
            "Rollback backup saved. Export complete JSON to protect your updated library."
        )
    }
}

@MainActor
final class AppModelPersistenceDurabilityTests: XCTestCase {
    func testPrepareForSuspensionFlushesLatestMutationBeforeRelaunch() async throws {
        let store = RecordingLibraryStore()
        let model = AppModel(store: store, seed: .sample)

        model.updateNotes("Saved on the way to the background.", for: "severance")
        await model.prepareForSuspension()

        let reloaded = makeReloadedModel(store: store)
        await reloaded.load()
        let metrics = await store.metrics()

        XCTAssertEqual(
            reloaded.mediaTitle(withID: "severance")?.notes,
            "Saved on the way to the background."
        )
        XCTAssertEqual(metrics.saveCount, 1)
    }

    func testRapidForegroundMutationsCoalesceIntoSingleSave() async throws {
        let store = RecordingLibraryStore()
        let model = AppModel(store: store, seed: .sample)

        model.setUserRating(7, for: "severance")
        model.setUserRating(8, for: "severance")
        model.setUserRating(9, for: "severance")
        await store.waitUntilFirstSaveStarts()
        await model.flushPendingPersistence()

        let loaded = try await store.load()
        let saved = try XCTUnwrap(loaded)
        let metrics = await store.metrics()

        XCTAssertEqual(saved.titles.first(where: { $0.id == "severance" })?.userRating, 9)
        XCTAssertEqual(metrics.saveCount, 1)
    }

    func testConcurrentSuspensionFlushesJoinSingleWriter() async throws {
        let store = RecordingLibraryStore(suspendsFirstSave: true)
        let model = AppModel(store: store, seed: .sample)
        model.updateNotes("One pending revision.", for: "severance")

        let inactiveFlush = Task { await model.prepareForSuspension() }
        await store.waitUntilFirstSaveStarts()
        let backgroundFlush = Task { await model.prepareForSuspension() }
        while model.persistenceFlushCount < 2 {
            await Task.yield()
        }

        await store.releaseFirstSave()
        await inactiveFlush.value
        await backgroundFlush.value
        let metrics = await store.metrics()

        XCTAssertEqual(metrics.saveCount, 1)
        XCTAssertEqual(metrics.maximumConcurrentSaveCount, 1)
    }

    func testMutationDuringSuspensionFlushIsWrittenAfterOlderSave() async throws {
        let store = RecordingLibraryStore(suspendsFirstSave: true)
        let model = AppModel(store: store, seed: .sample)
        model.updateNotes("Older value", for: "severance")

        let flush = Task { await model.prepareForSuspension() }
        await store.waitUntilFirstSaveStarts()
        model.updateNotes("Newest value", for: "severance")
        await store.releaseFirstSave()
        await flush.value

        let reloaded = makeReloadedModel(store: store)
        await reloaded.load()
        let metrics = await store.metrics()

        XCTAssertEqual(reloaded.mediaTitle(withID: "severance")?.notes, "Newest value")
        XCTAssertEqual(metrics.saveCount, 2)
        XCTAssertEqual(metrics.maximumConcurrentSaveCount, 1)
    }

    func testMutationDuringForegroundSaveIsWrittenAfterOlderSave() async throws {
        let store = RecordingLibraryStore(suspendsFirstSave: true)
        let model = AppModel(store: store, seed: .sample)
        model.updateNotes("Older value", for: "severance")

        await store.waitUntilFirstSaveStarts()
        model.updateNotes("Newest value", for: "severance")
        let newestDebounce = try XCTUnwrap(model.persistenceDebounceTask)
        await store.releaseFirstSave()
        await newestDebounce.value

        let reloaded = makeReloadedModel(store: store)
        await reloaded.load()
        let metrics = await store.metrics()

        XCTAssertEqual(reloaded.mediaTitle(withID: "severance")?.notes, "Newest value")
        XCTAssertEqual(metrics.saveCount, 2)
        XCTAssertEqual(metrics.maximumConcurrentSaveCount, 1)
    }

    func testNewerMutationDuringFailedSuspensionSaveIsRetried() async throws {
        let store = RecordingLibraryStore(suspendsFirstSave: true, failsFirstSave: true)
        let model = AppModel(store: store, seed: .sample)
        model.updateNotes("Older value", for: "severance")

        let flush = Task { await model.prepareForSuspension() }
        await store.waitUntilFirstSaveStarts()
        model.updateNotes("Newest value", for: "severance")
        await store.releaseFirstSave()
        await flush.value

        let reloaded = makeReloadedModel(store: store)
        await reloaded.load()
        let metrics = await store.metrics()

        XCTAssertEqual(reloaded.mediaTitle(withID: "severance")?.notes, "Newest value")
        XCTAssertEqual(metrics.saveCount, 2)
        XCTAssertEqual(metrics.maximumConcurrentSaveCount, 1)
        XCTAssertNil(model.persistenceError)
    }

    private func makeReloadedModel(store: any LibraryPersisting) -> AppModel {
        AppModel(
            store: store,
            recommendationService: DeterministicRecommendationService(),
            sharedConversationNotifier: NoopSharedConversationNotifier(),
            reminderScheduler: NoopReminderScheduler(),
            partnerActivityNotifier: NoopPartnerActivityNotifier(),
            catalogService: LocalCatalogService(titles: []),
            traktService: UnconfiguredTraktSyncService(),
            seed: .empty
        )
    }
}

private enum RecordingLibraryStoreError: Error {
    case forcedFailure
}

private actor RecordingLibraryStore: LibraryPersisting {
    private let suspendsFirstSave: Bool
    private let failsFirstSave: Bool
    private var snapshot: LibrarySnapshot?
    private var saveCount = 0
    private var activeSaveCount = 0
    private var maximumConcurrentSaveCount = 0
    private var firstSaveStarted = false
    private var firstSaveReleased = false

    init(
        snapshot: LibrarySnapshot? = nil,
        suspendsFirstSave: Bool = false,
        failsFirstSave: Bool = false
    ) {
        self.snapshot = snapshot
        self.suspendsFirstSave = suspendsFirstSave
        self.failsFirstSave = failsFirstSave
    }

    func load() async throws -> LibrarySnapshot? {
        snapshot
    }

    func save(_ snapshot: LibrarySnapshot) async throws {
        saveCount += 1
        let saveNumber = saveCount
        activeSaveCount += 1
        maximumConcurrentSaveCount = max(maximumConcurrentSaveCount, activeSaveCount)
        defer { activeSaveCount -= 1 }

        if saveNumber == 1 {
            firstSaveStarted = true
        }
        if suspendsFirstSave, saveNumber == 1 {
            while !firstSaveReleased {
                // Deliberately ignore cancellation to model a write that has already started.
                await Task.yield()
            }
        }
        if failsFirstSave, saveNumber == 1 {
            throw RecordingLibraryStoreError.forcedFailure
        }

        self.snapshot = snapshot
    }

    func waitUntilFirstSaveStarts() async {
        while !firstSaveStarted {
            await Task.yield()
        }
    }

    func releaseFirstSave() {
        firstSaveReleased = true
    }

    func metrics() -> (saveCount: Int, maximumConcurrentSaveCount: Int) {
        (saveCount, maximumConcurrentSaveCount)
    }
}

extension AppModelTests {
    func testLoadingCleanupCannotOverwriteNewerMutationWhileItsSaveIsSuspended() async throws {
        let snapshot = try remoteMetadataSnapshot(
            RemoteMetadataURLs(
                posterURL: URL(string: "https://attacker.invalid/poster.jpg")!,
                backdropURL: URL(string: "https://attacker.invalid/backdrop.jpg")!,
                trailerURL: URL(string: "https://attacker.invalid/trailer")!,
                sourceURL: URL(string: "https://attacker.invalid/source")!,
                reviewAvatarURL: URL(string: "https://attacker.invalid/avatar")!,
                reviewSourceURL: URL(string: "https://attacker.invalid/review")!,
                seasonArtworkURL: URL(string: "https://attacker.invalid/season.jpg")!,
                episodeStillURL: URL(string: "https://attacker.invalid/episode.jpg")!
            )
        )
        let store = RecordingLibraryStore(snapshot: snapshot, suspendsFirstSave: true)
        let model = AppModel(
            store: store,
            reminderScheduler: NoopReminderScheduler(),
            partnerActivityNotifier: NoopPartnerActivityNotifier(),
            catalogService: LocalCatalogService(titles: []),
            traktService: UnconfiguredTraktSyncService(),
            seed: .empty
        )

        let load = Task { await model.load() }
        await store.waitUntilFirstSaveStarts()
        model.updateNotes("Newer note written while cleanup was suspended.", for: "severance")
        await store.releaseFirstSave()
        await load.value
        await model.flushPendingPersistence()

        let storedSnapshot = try await store.load()
        let saved = try XCTUnwrap(storedSnapshot)
        let savedTitle = try XCTUnwrap(saved.titles.first(where: { $0.id == "severance" }))
        let metrics = await store.metrics()
        XCTAssertEqual(savedTitle.notes, "Newer note written while cleanup was suspended.")
        XCTAssertNil(savedTitle.posterURL)
        XCTAssertEqual(metrics.saveCount, 2)
        XCTAssertEqual(metrics.maximumConcurrentSaveCount, 1)
    }
}

private extension AppModelTests {
    private func remoteMetadataSnapshot(
        _ urls: RemoteMetadataURLs
    ) throws -> LibrarySnapshot {
        var snapshot = LibrarySnapshot.sample
        var title = try XCTUnwrap(snapshot.titles.first(where: { $0.id == "severance" }))
        title.state = .paused
        title.progress = EpisodeProgress(season: 1, episode: 1, totalEpisodes: 9)
        title.userRating = 9.25
        title.notes = "Private load migration note"
        title.rewatchCount = 3
        title.lastWatchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        title.personalWatchlist = true
        title.watchedEpisodeIDs = ["severance-s1e1"]
        title.posterURL = urls.posterURL
        title.backdropURL = urls.backdropURL
        title.trailerURL = urls.trailerURL
        title.sourceURL = urls.sourceURL

        var review = try XCTUnwrap(title.reviews.first)
        review.avatarURL = urls.reviewAvatarURL
        review.sourceURL = urls.reviewSourceURL
        title.reviews = [review]

        var episode = EpisodeSummary(
            id: "severance-s1e1",
            number: 1,
            title: "Good News About Hell",
            airDate: Date(timeIntervalSince1970: 1_645_142_400),
            runtimeMinutes: 57
        )
        episode.stillURL = urls.episodeStillURL
        var season = SeasonSummary(
            id: "severance-s1",
            number: 1,
            title: "Season 1",
            episodes: [episode]
        )
        season.artworkURL = urls.seasonArtworkURL
        title.seasons = [season]

        snapshot.titles = [title]
        snapshot.sharedSpace.titleIDs = [title.id]
        snapshot.sharedSpace.titleMetadata = [title]
        snapshot.diaryEntries = [LibraryDiaryTransferTests.diaryEntry]
        snapshot.lists = [
            MediaList(
                id: "private-list",
                name: "Private list",
                titleIDs: [title.id],
                updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        ]
        return snapshot
    }
}

private struct RemoteMetadataURLs {
    let posterURL: URL
    let backdropURL: URL
    let trailerURL: URL
    let sourceURL: URL
    let reviewAvatarURL: URL
    let reviewSourceURL: URL
    let seasonArtworkURL: URL
    let episodeStillURL: URL
}
