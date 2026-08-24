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
        XCTAssertFalse(title?.isOnPersonalWatchlist ?? true)
    }

    func testMarkNextDoesNotRecordWatchForSeriesWithoutEpisodeProgress() throws {
        var snapshot = LibrarySnapshot.sample
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[index].seasons = nil
        snapshot.titles[index].progress = nil
        snapshot.sharedSpace.watchEvents = []
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        model.markNextWatched("severance")

        XCTAssertTrue(model.sharedSpace.watchEvents?.isEmpty == true)
        XCTAssertNil(model.mediaTitle(withID: "severance")?.lastWatchedAt)
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
}

extension AppModelTests {
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

    func testLoadingScrubsAndPersistsLegacyUnsafeRemoteMetadata() async throws {
        let snapshot = try remoteMetadataSnapshot(
            RemoteMetadataURLs(
                posterURL: URL(string: "https://attacker.invalid/poster.jpg")!,
                backdropURL: URL(string: "http://media.themoviedb.org/backdrop.jpg")!,
                trailerURL: URL(fileURLWithPath: "/private/trailer.mov"),
                sourceURL: URL(string: "https://www.themoviedb.org@attacker.invalid/tv/95396")!,
                reviewAvatarURL: URL(string: "https://secure.gravatar.com@attacker.invalid/avatar")!,
                reviewSourceURL: URL(string: "https://attacker.invalid/review")!,
                seasonArtworkURL: URL(string: "https://static.tvmaze.com.attacker.invalid/season.jpg")!,
                episodeStillURL: URL(string: "http://image.tmdb.org/still.jpg")!
            )
        )
        let originalTitle = try XCTUnwrap(snapshot.titles.first)
        let store = MemoryLibraryStore(snapshot: snapshot)
        let model = AppModel(
            store: store,
            reminderScheduler: NoopReminderScheduler(),
            partnerActivityNotifier: NoopPartnerActivityNotifier(),
            catalogService: LocalCatalogService(titles: []),
            traktService: UnconfiguredTraktSyncService(),
            seed: .empty
        )

        await model.load()

        try await assertSanitizedLoad(
            model: model,
            store: store,
            snapshot: snapshot,
            originalTitle: originalTitle
        )
    }

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

    func testLoadingPreservesAllowlistedHTTPSMetadataAndPrivateState() async throws {
        let snapshot = try remoteMetadataSnapshot(
            RemoteMetadataURLs(
                posterURL: URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg")!,
                backdropURL: URL(string: "https://media.themoviedb.org/t/p/w780/backdrop.jpg")!,
                trailerURL: URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!,
                sourceURL: URL(string: "https://www.themoviedb.org/tv/95396")!,
                reviewAvatarURL: URL(string: "https://secure.gravatar.com/avatar/hash")!,
                reviewSourceURL: URL(string: "https://www.themoviedb.org/review/1")!,
                seasonArtworkURL: URL(string: "https://static.tvmaze.com/uploads/season.jpg")!,
                episodeStillURL: URL(string: "https://image.tmdb.org/t/p/w300/still.jpg")!
            )
        )
        let store = MemoryLibraryStore(snapshot: snapshot)
        let model = AppModel(
            store: store,
            reminderScheduler: NoopReminderScheduler(),
            partnerActivityNotifier: NoopPartnerActivityNotifier(),
            catalogService: LocalCatalogService(titles: []),
            traktService: UnconfiguredTraktSyncService(),
            seed: .empty
        )

        await model.load()

        let loadedTitle = try XCTUnwrap(model.titles.first)
        let expectedTitle = try XCTUnwrap(snapshot.titles.first)
        XCTAssertEqual(loadedTitle, expectedTitle)
        XCTAssertEqual(model.sharedSpace.titleMetadata, snapshot.sharedSpace.titleMetadata)
        XCTAssertEqual(model.diaryEntries, snapshot.diaryEntries)
        XCTAssertEqual(model.lists, snapshot.lists)
        let persisted = try await store.load()
        XCTAssertEqual(persisted, snapshot)
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
    private func assertSanitizedLoad(
        model: AppModel,
        store: MemoryLibraryStore,
        snapshot: LibrarySnapshot,
        originalTitle: MediaTitle
    ) async throws {
        let loadedTitle = try XCTUnwrap(model.titles.first)
        let loadedSharedTitle = try XCTUnwrap(model.sharedSpace.titleMetadata?.first)
        XCTAssertNil(loadedTitle.posterURL)
        XCTAssertNil(loadedTitle.backdropURL)
        XCTAssertNil(loadedTitle.trailerURL)
        XCTAssertNil(loadedTitle.sourceURL)
        XCTAssertNil(loadedTitle.reviews.first?.avatarURL)
        XCTAssertNil(loadedTitle.reviews.first?.sourceURL)
        XCTAssertNil(loadedTitle.seasons?.first?.artworkURL)
        XCTAssertNil(loadedTitle.seasons?.first?.episodes.first?.stillURL)
        XCTAssertNil(loadedSharedTitle.posterURL)
        XCTAssertNil(loadedSharedTitle.reviews.first?.avatarURL)
        XCTAssertNil(loadedSharedTitle.seasons?.first?.episodes.first?.stillURL)
        XCTAssertEqual(loadedTitle.state, originalTitle.state)
        XCTAssertEqual(loadedTitle.progress, originalTitle.progress)
        XCTAssertEqual(loadedTitle.userRating, originalTitle.userRating)
        XCTAssertEqual(loadedTitle.notes, originalTitle.notes)
        XCTAssertEqual(loadedTitle.rewatchCount, originalTitle.rewatchCount)
        XCTAssertEqual(loadedTitle.lastWatchedAt, originalTitle.lastWatchedAt)
        XCTAssertEqual(loadedTitle.personalWatchlist, originalTitle.personalWatchlist)
        XCTAssertEqual(loadedTitle.watchedEpisodeIDs, originalTitle.watchedEpisodeIDs)
        XCTAssertEqual(model.diaryEntries, snapshot.diaryEntries)
        XCTAssertEqual(model.lists, snapshot.lists)

        let persistedSnapshot = try await store.load()
        let persisted = try XCTUnwrap(persistedSnapshot)
        XCTAssertEqual(persisted, ImportedLibraryMetadataSanitizer.sanitized(snapshot))
        let persistedTitle = try XCTUnwrap(persisted.titles.first)
        let persistedSharedTitle = try XCTUnwrap(persisted.sharedSpace.titleMetadata?.first)
        XCTAssertNil(persistedTitle.posterURL)
        XCTAssertNil(persistedTitle.reviews.first?.avatarURL)
        XCTAssertNil(persistedTitle.seasons?.first?.artworkURL)
        XCTAssertNil(persistedSharedTitle.backdropURL)
        XCTAssertNil(persistedSharedTitle.reviews.first?.sourceURL)
        XCTAssertNil(persistedSharedTitle.seasons?.first?.episodes.first?.stillURL)
        XCTAssertEqual(persistedTitle.userRating, originalTitle.userRating)
        XCTAssertEqual(persistedTitle.notes, originalTitle.notes)
        XCTAssertEqual(persisted.diaryEntries, snapshot.diaryEntries)
        XCTAssertEqual(persisted.lists, snapshot.lists)
    }

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

@MainActor
final class CatalogSearchTests: XCTestCase {
    func testCatalogSearchKeepsProviderFuzzyMatches() async throws {
        let fuzzyMatch = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "past-lives" }))
        let service = CatalogSearchStub { _ in [fuzzyMatch] }
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: service,
            seed: .sample
        )

        await model.searchCatalog(text: "Korean romance")

        XCTAssertEqual(model.catalogSearchResults.map(\.id), [fuzzyMatch.id])
        XCTAssertNil(model.catalogSearchError)
    }

    func testNewerCatalogSearchWinsWhenOlderRequestFinishesLast() async throws {
        let slowResult = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" }))
        let fastResult = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "fallout" }))
        let service = CatalogSearchStub { query in
            if query.text == "slow" {
                do {
                    try await Task.sleep(for: .milliseconds(400))
                } catch {
                    // Simulate a provider that cannot cancel an in-flight request.
                }
                return [slowResult]
            }
            try await Task.sleep(for: .milliseconds(20))
            return [fastResult]
        }
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: service,
            seed: .sample
        )

        let slowSearch = Task { await model.searchCatalog(text: "slow") }
        try await Task.sleep(for: .milliseconds(300))
        let fastSearch = Task { await model.searchCatalog(text: "fast") }

        await fastSearch.value
        await slowSearch.value

        XCTAssertEqual(model.catalogSearchQuery, "fast")
        XCTAssertEqual(model.catalogSearchResults.map(\.id), [fastResult.id])
        XCTAssertFalse(model.isSearchingCatalog)
    }

    func testClearingCatalogSearchInvalidatesInFlightResults() async throws {
        let delayedResult = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" }))
        let service = CatalogSearchStub { _ in
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                // Native cancellation can be advisory once a provider request has started.
            }
            return [delayedResult]
        }
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: service,
            seed: .sample
        )

        let pendingSearch = Task { await model.searchCatalog(text: "slow") }
        try await Task.sleep(for: .milliseconds(300))
        await model.searchCatalog(text: "")
        await pendingSearch.value

        XCTAssertTrue(model.catalogSearchResults.isEmpty)
        XCTAssertEqual(model.catalogSearchQuery, "")
        XCTAssertFalse(model.isSearchingCatalog)
    }

    func testCatalogSearchFailureHasDistinctErrorState() async {
        let service = CatalogSearchStub { _ in throw CatalogServiceError.unavailable }
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: service,
            seed: .sample
        )

        await model.searchCatalog(text: "Severance")

        XCTAssertTrue(model.catalogSearchResults.isEmpty)
        XCTAssertEqual(model.catalogSearchError, CatalogServiceError.unavailable.localizedDescription)
        XCTAssertFalse(model.isSearchingCatalog)
    }

    func testRefreshCatalogDetailsLoadsTVMazeSeasonsFromFallback() async throws {
        var searchResult = try XCTUnwrap(Self.tvmazeSearchResult)
        searchResult.seasons = nil
        var detailed = searchResult
        detailed.seasons = [
            SeasonSummary(
                id: "tvmaze-season-1396-1",
                number: 1,
                title: "Season 1",
                episodes: [
                    EpisodeSummary(
                        id: "tvmaze-episode-1",
                        number: 1,
                        title: "Good News About Hell",
                        airDate: nil,
                        runtimeMinutes: 57
                    )
                ]
            )
        ]
        let catalog = FallbackCatalogService(
            primary: RecordingCatalogStub(title: detailed, searchResults: [], shouldFailTitle: true),
            fallback: RecordingCatalogStub(title: detailed, searchResults: [searchResult])
        )
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: catalog,
            seed: .empty
        )

        await model.searchCatalog(text: "Severance")
        await model.refreshCatalogDetails(for: searchResult.id)

        let refreshed = try XCTUnwrap(model.mediaTitle(withID: searchResult.id))
        XCTAssertEqual(refreshed.seasons?.first?.episodes.first?.id, "tvmaze-episode-1")
        XCTAssertNil(model.catalogSearchError)
        XCTAssertNil(model.catalogDetailError(for: searchResult.id))
    }

    func testRefreshCatalogDetailsFailureDoesNotClobberSearchError() async throws {
        let searchResult = try XCTUnwrap(Self.tvmazeSearchResult)
        let catalog = FallbackCatalogService(
            primary: RecordingCatalogStub(
                title: searchResult,
                searchResults: [],
                shouldFailTitle: true
            ),
            fallback: RecordingCatalogStub(
                title: searchResult,
                searchResults: [searchResult],
                shouldFailTitle: true
            )
        )
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: catalog,
            seed: .empty
        )

        await model.searchCatalog(text: "Severance")
        XCTAssertNil(model.catalogSearchError)
        await model.refreshCatalogDetails(for: searchResult.id)

        XCTAssertEqual(model.catalogSearchResults.map(\.id), [searchResult.id])
        XCTAssertNil(model.catalogSearchError)
        XCTAssertEqual(
            model.catalogDetailError(for: searchResult.id),
            CatalogServiceError.unavailable.localizedDescription
        )
        XCTAssertNil(model.catalogDetailError(for: "severance"))
    }

    private static let tvmazeSearchResult: MediaTitle? = {
        guard var title = LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" }) else {
            return nil
        }
        title = MediaTitle(
            id: "tvmaze-series-1396",
            catalogID: 1396,
            title: title.title,
            year: title.year,
            kind: .series,
            synopsis: title.synopsis,
            genres: title.genres,
            runtimeMinutes: title.runtimeMinutes,
            state: .planned,
            progress: nil,
            rating: title.rating,
            nextReleaseDescription: nil,
            recommendationReason: nil,
            mood: title.mood,
            palette: title.palette,
            providers: title.providers,
            reviews: [],
            metadataSource: .tvmaze
        )
        return title
    }()
}
