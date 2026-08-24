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
