import Foundation
import Observation
@MainActor
@Observable
final class AppModel {
    let store: any LibraryPersisting
    private let recommendationService: any RecommendationProviding
    let traktService: any TraktSyncProviding
    let sharedConversationNotifier: any SharedConversationNotifying
    let reminderScheduler: any ReminderScheduling
    let catalogService: any CatalogProviding
    private let seed: LibrarySnapshot
    var saveTask: Task<Void, Never>?
    var reminderTask: Task<Void, Never>?
    var persistenceRevision = 0
    var titles: [MediaTitle]
    var sharedSpace: SharedSpace
    var diaryEntries: [ViewingDiaryEntry]
    private(set) var selectedProviderIDs: Set<StreamingProvider.ID>
    private(set) var allowsAIReranking: Bool
    private(set) var streamingRegionOverride: StreamingRegion?
    var traktSyncState: TraktSyncState
    var isTraktAuthorized = false
    var isTraktSyncing = false
    var traktSyncSummary: String?
    var traktSyncError: String?
    var reminderSettings: ReminderSettings
    var reminderCapability = ReminderCapability.unknown
    var reminderError: String?
    private(set) var importResolutionAliases: [String: ImportResolutionAlias]
    private(set) var hasCompletedFirstRun: Bool
    private(set) var hasLoaded = false
    var persistenceError: String?
    private(set) var remoteRankedRecommendations: [Recommendation] = []
    var catalogSearchResults: [MediaTitle] = []
    var catalogSearchError: String?
    var isSearchingCatalog = false
    var catalogSearchPage = 0
    var catalogSearchQuery = ""
    var hasMoreCatalogResults = false
    var isRefreshingUpcomingCalendar = false
    var upcomingCalendarLastRefreshedAt: Date?
    var upcomingCalendarLastAttemptedAt: Date?
    var upcomingCalendarRefreshError: String?
    var upcomingCalendarRefreshRevision = 0
    var hasQueuedUpcomingCalendarRefresh = false
    var catalogSearchRequestID = UUID()
    var selectedMood: Mood = .any {
        didSet { refreshRecommendationsSoon() }
    }
    init(
        store: any LibraryPersisting = LibraryStoreFactory.makeDefault(),
        recommendationService: any RecommendationProviding = ProviderNeutralRecommendationService(),
        sharedConversationNotifier: any SharedConversationNotifying = SharedConversationNotificationService(),
        reminderScheduler: (any ReminderScheduling)? = nil,
        catalogService: (any CatalogProviding)? = nil,
        traktService: any TraktSyncProviding = TraktSyncServiceFactory.makeDefault(),
        seed: LibrarySnapshot = .empty
    ) {
        self.store = store
        self.recommendationService = recommendationService
        self.traktService = traktService
        self.sharedConversationNotifier = sharedConversationNotifier
        if let reminderScheduler {
            self.reminderScheduler = reminderScheduler
        } else if seed == .empty {
            self.reminderScheduler = LocalNotificationReminderService()
        } else {
            self.reminderScheduler = NoopReminderScheduler()
        }
        if let catalogService {
            self.catalogService = catalogService
        } else if seed == .empty {
            self.catalogService = CatalogServiceFactory.makeDefault()
        } else {
            self.catalogService = LocalCatalogService(titles: seed.titles)
        }
        self.seed = seed
        titles = seed.titles
        sharedSpace = seed.sharedSpace
        diaryEntries = Self.resolvedDiaryEntries(from: seed)
        selectedProviderIDs = seed.selectedProviderIDs ?? Self.defaultProviderIDs
        allowsAIReranking = seed.allowsAIReranking ?? false
        streamingRegionOverride = seed.streamingRegionCode.flatMap(StreamingRegion.init(code:))
        traktSyncState = seed.traktSyncState ?? .empty
        reminderSettings = seed.reminderSettings ?? ReminderSettings()
        importResolutionAliases = seed.importResolutionAliases ?? [:]
        hasCompletedFirstRun = seed.hasCompletedFirstRun ?? (seed != .empty)
        titles = migratedTrackingTitles(titles, fromSchemaVersion: seed.schemaVersion)
    }

    var recommendations: [MediaTitle] {
        rankedRecommendations.map { recommendation in
            var title = recommendation.title
            title.recommendationReason = recommendation.reason
            return title
        }
    }
    var rankedRecommendations: [Recommendation] {
        if allowsAIReranking, !remoteRankedRecommendations.isEmpty {
            return remoteRankedRecommendations
        }
        return DeterministicRecommendationEngine.rank(
            snapshot: snapshot,
            context: RecommendationContext(
                mood: selectedMood,
                maximumRuntimeMinutes: nil,
                sharedSpaceID: sharedSpace.id,
                allowsRemoteReranking: allowsAIReranking
            )
        )
    }
    var sharedTitles: [MediaTitle] {
        let sharedIDs = Set(sharedSpace.titleIDs)
        return titles.filter { sharedIDs.contains($0.id) }
    }
    var snapshot: LibrarySnapshot {
        LibrarySnapshot(
            titles: titles,
            sharedSpace: sharedSpace,
            selectedProviderIDs: selectedProviderIDs,
            allowsAIReranking: allowsAIReranking,
            streamingRegionCode: streamingRegionOverride?.code,
            diaryEntries: diaryEntries,
            reminderSettings: reminderSettings,
            importResolutionAliases: importResolutionAliases,
            traktSyncState: traktSyncState,
            hasCompletedFirstRun: hasCompletedFirstRun
        )
    }

    func titles(in state: WatchState) -> [MediaTitle] {
        titles.filter { title in
            if state == .planned { return title.isOnPersonalWatchlist }
            return title.state == state
        }
    }

    func moreLikeThis(_ id: MediaTitle.ID, limit: Int = 12) -> [SimilarTitleMatch] {
        guard let source = titles.first(where: { $0.id == id }) else { return [] }
        return TitleSimilarity.matches(for: source, among: titlesOnSelectedProviders, limit: limit)
    }

    func load() async {
        guard !hasLoaded else { return }
        defer { hasLoaded = true }
        var canReconcileReminders = true

        do {
            if let snapshot = try await store.load() {
                titles = migratedTrackingTitles(
                    merging(savedTitles: snapshot.titles, catalogTitles: seed.titles),
                    fromSchemaVersion: snapshot.schemaVersion
                )
                sharedSpace = snapshot.sharedSpace
                diaryEntries = Self.resolvedDiaryEntries(from: snapshot)
                selectedProviderIDs = snapshot.selectedProviderIDs ?? Self.defaultProviderIDs
                allowsAIReranking = snapshot.allowsAIReranking ?? false
                streamingRegionOverride = snapshot.streamingRegionCode.flatMap(StreamingRegion.init(code:))
                traktSyncState = snapshot.traktSyncState ?? .empty
                reminderSettings = snapshot.reminderSettings ?? ReminderSettings()
                importResolutionAliases = snapshot.importResolutionAliases ?? [:]
                hasCompletedFirstRun = snapshot.hasCompletedFirstRun ?? true
            }
        } catch {
            persistenceError = "Your saved library could not be opened. Your catalog and saved data remain separate."
            canReconcileReminders = false
        }
        await refreshDiscoveryCatalog()
        await refreshRecommendations()
        isTraktAuthorized = await traktService.isAuthorized()
        await refreshReminderCapability()
        if canReconcileReminders {
            await refreshReminders()
        }
        publishWidgetSnapshot()
    }
}

extension AppModel {
    func setWatchState(_ state: WatchState, for id: MediaTitle.ID) {
        if state == .completed || state == .caughtUp {
            markWatched(id)
            guard let index = trackableTitleIndex(for: id) else { return }
            let canBeCaughtUp = titles[index].kind == .series
                && titles[index].resolvedSeriesLifecycle != .ended
            let resolvedState: WatchState = state == .caughtUp && canBeCaughtUp ? .caughtUp : .completed
            guard titles[index].state != resolvedState else { return }
            titles[index].state = resolvedState
            persist()
            refreshRecommendationsSoon()
            return
        }
        guard let index = trackableTitleIndex(for: id) else { return }
        titles[index].state = state
        if state == .planned {
            titles[index].personalWatchlist = true
        } else if state == .dropped {
            titles[index].personalWatchlist = false
            titles[index].isUpNextPinned = nil
            titles[index].upNextSnoozedUntil = nil
            titles[index].upNextManualOrder = nil
        } else if state == .watching {
            titles[index].upNextSnoozedUntil = nil
        }
        persist()
        refreshRecommendationsSoon()
    }

    func setUserRating(_ rating: Double?, for id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }
        let clampedRating = rating.map { min(max($0, 0), 10) }
        titles[index].userRating = clampedRating
        synchronizeTitleDiaryRating(clampedRating, titleID: id)
        persist()
    }

    func updateNotes(_ notes: String, for id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = trimmed.isEmpty ? nil : trimmed
        titles[index].notes = note
        synchronizeTitleDiaryNote(note, titleID: id)
        persist()
    }

    func recordRewatch(_ id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }
        let watchedAt = Date.now
        titles[index].rewatchCount = titles[index].completedRewatches + 1
        titles[index].lastWatchedAt = watchedAt
        recordTitleRewatchInDiary(titles[index], watchedAt: watchedAt)
        appendWatchEvent(title: titles[index], kind: .rewatch, occurredAt: watchedAt)
        addActivity(
            description: "rewatched \(titles[index].title)",
            titleID: titles[index].id,
            symbol: "arrow.clockwise"
        )
        persist()
        syncSharedStateSoon()
    }

    func correctProgress(_ progress: EpisodeProgress, for id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id), titles[index].kind == .series else { return }
        let corrected = EpisodeProgress(
            season: max(progress.season, 1),
            episode: min(max(progress.episode, 0), max(progress.totalEpisodes, 1)),
            totalEpisodes: max(progress.totalEpisodes, 1)
        )
        let supersededID = sharedSpace.watchEvents?.last(where: { $0.titleID == id })?.id
        titles[index].progress = corrected
        titles[index].state = corrected.episode == corrected.totalEpisodes
            ? finishedState(for: titles[index])
            : .watching
        appendWatchEvent(title: titles[index], kind: .correction, supersedesEventID: supersededID)
        addActivity(
            description: "corrected \(titles[index].title) to \(corrected.label)",
            titleID: titles[index].id,
            symbol: "slider.horizontal.3"
        )
        persist()
        syncSharedStateSoon()
    }

    func setRecommendationDismissed(_ dismissed: Bool, for id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }
        titles[index].isDismissed = dismissed
        persist()
        refreshRecommendationsSoon()
    }

    func setRecommendationDisliked(_ disliked: Bool, for id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }
        titles[index].isDisliked = disliked
        persist()
        refreshRecommendationsSoon()
    }

    func setAIRerankingEnabled(_ enabled: Bool) {
        allowsAIReranking = enabled
        if !enabled { remoteRankedRecommendations = [] }
        persist()
        refreshRecommendationsSoon()
    }

    func storeStreamingRegionOverride(_ region: StreamingRegion?) {
        streamingRegionOverride = region
    }

    func completeFirstRun() {
        guard !hasCompletedFirstRun else { return }
        hasCompletedFirstRun = true
        persist()
    }
    func replaceLibrary(with snapshot: LibrarySnapshot) {
        titles = migratedTrackingTitles(
            merging(savedTitles: snapshot.titles, catalogTitles: seed.titles),
            fromSchemaVersion: snapshot.schemaVersion
        )
        sharedSpace = snapshot.sharedSpace
        diaryEntries = Self.resolvedDiaryEntries(from: snapshot)
        selectedProviderIDs = snapshot.selectedProviderIDs ?? Self.defaultProviderIDs
        allowsAIReranking = snapshot.allowsAIReranking ?? false
        streamingRegionOverride = snapshot.streamingRegionCode.flatMap(StreamingRegion.init(code:))
        traktSyncState = snapshot.traktSyncState ?? .empty
        reminderSettings = snapshot.reminderSettings ?? ReminderSettings()
        importResolutionAliases = snapshot.importResolutionAliases ?? [:]
        hasCompletedFirstRun = snapshot.hasCompletedFirstRun ?? true
        persist()
    }

    func toggleWatchlist(_ id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }
        titles[index].personalWatchlist = !titles[index].isOnPersonalWatchlist
        persist()
    }

    func toggleProvider(_ id: StreamingProvider.ID) {
        if selectedProviderIDs.contains(id) {
            selectedProviderIDs.remove(id)
        } else {
            selectedProviderIDs.insert(id)
        }
        persist()
        refreshRecommendationsSoon()
    }

    func isProviderSelected(_ id: StreamingProvider.ID) -> Bool {
        selectedProviderIDs.contains(id)
    }

    func isAvailableOnSelectedProviders(_ title: MediaTitle) -> Bool {
        !selectedProviderIDs.isDisjoint(with: Set(title.providers.map(\.id)))
    }

    func flushPendingPersistence() async {
        await saveTask?.value
    }

    func flushPendingReminders() async {
        await reminderTask?.value
    }

    func refreshRecommendations() async {
        guard allowsAIReranking else {
            remoteRankedRecommendations = []
            return
        }
        let context = RecommendationContext(
            mood: selectedMood,
            maximumRuntimeMinutes: nil,
            sharedSpaceID: sharedSpace.id,
            allowsRemoteReranking: true
        )
        remoteRankedRecommendations = (try? await recommendationService.recommendations(
            from: snapshot,
            context: context
        )) ?? []
    }
}

extension AppModel {
    private static let defaultProviderIDs: Set<StreamingProvider.ID> = [
        StreamingProvider.netflix.id,
        StreamingProvider.primeVideo.id,
        StreamingProvider.appleTV.id
    ]
}
