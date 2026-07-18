import Foundation
import Observation
@MainActor
@Observable
final class AppModel {
    let store: any LibraryPersisting
    private let recommendationService: any RecommendationProviding
    let reminderScheduler: any ReminderScheduling
    let partnerActivityNotifier: any PartnerActivityNotifying
    let catalogService: any CatalogProviding
    private let seed: LibrarySnapshot
    var saveTask: Task<Void, Never>?
    var reminderTask: Task<Void, Never>?
    var persistenceRevision = 0

    var titles: [MediaTitle]
    var sharedSpace: SharedSpace
    private(set) var selectedProviderIDs: Set<StreamingProvider.ID>
    private(set) var allowsAIReranking: Bool
    private(set) var streamingRegionOverride: StreamingRegion?
    var reminderSettings: ReminderSettings
    var reminderCapability = ReminderCapability.unknown
    var reminderError: String?
    private(set) var hasLoaded = false
    private var isLoading = false
    private var hasLoadedPersistedState = false
    var persistenceError: String?
    private(set) var remoteRankedRecommendations: [Recommendation] = []
    var catalogSearchResults: [MediaTitle] = []
    var catalogSearchError: String?
    var isSearchingCatalog = false
    var catalogSearchPage = 0
    var catalogSearchQuery = ""
    var hasMoreCatalogResults = false

    var selectedMood: Mood = .any {
        didSet { refreshRecommendationsSoon() }
    }
    init(
        store: any LibraryPersisting = LibraryStoreFactory.makeDefault(),
        recommendationService: any RecommendationProviding = ProviderNeutralRecommendationService(),
        reminderScheduler: (any ReminderScheduling)? = nil,
        partnerActivityNotifier: (any PartnerActivityNotifying)? = nil,
        catalogService: (any CatalogProviding)? = nil,
        seed: LibrarySnapshot = .empty
    ) {
        self.store = store
        self.recommendationService = recommendationService
        if let reminderScheduler {
            self.reminderScheduler = reminderScheduler
        } else if seed == .empty {
            self.reminderScheduler = LocalNotificationReminderService()
        } else {
            self.reminderScheduler = NoopReminderScheduler()
        }
        if let partnerActivityNotifier {
            self.partnerActivityNotifier = partnerActivityNotifier
        } else if seed == .empty {
            self.partnerActivityNotifier = PartnerActivityNotificationService()
        } else {
            self.partnerActivityNotifier = NoopPartnerActivityNotifier()
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
        selectedProviderIDs = seed.selectedProviderIDs ?? Self.defaultProviderIDs
        allowsAIReranking = seed.allowsAIReranking ?? false
        streamingRegionOverride = seed.streamingRegionCode.flatMap(StreamingRegion.init(code:))
        reminderSettings = seed.reminderSettings ?? ReminderSettings()
    }
    var upNext: [MediaTitle] {
        titles
            .filter { title in
                if title.state == .watching { return true }
                guard title.kind == .movie,
                      title.state == .planned,
                      title.isOnPersonalWatchlist,
                      let releaseDate = title.releaseDate else {
                    return false
                }
                return releaseDate <= .now
            }
            .sorted(by: isHigherUpNextPriority)
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
            reminderSettings: reminderSettings
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
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        await loadPersistedState()
        if sharedSpace.isCloudSharingEnabled {
            await partnerActivityNotifier.requestAuthorization()
        }

        await refreshDiscoveryCatalog()
        await refreshRecommendations()
        await refreshReminderCapability()
        await refreshReminders()
        publishWidgetSnapshot()
    }
    func loadPersistedState() async {
        guard !hasLoadedPersistedState else { return }
        hasLoadedPersistedState = true

        do {
            if let snapshot = try await store.load() {
                titles = merging(savedTitles: snapshot.titles, catalogTitles: seed.titles)
                sharedSpace = snapshot.sharedSpace
                selectedProviderIDs = snapshot.selectedProviderIDs ?? Self.defaultProviderIDs
                allowsAIReranking = snapshot.allowsAIReranking ?? false
                streamingRegionOverride = snapshot.streamingRegionCode.flatMap(StreamingRegion.init(code:))
                reminderSettings = snapshot.reminderSettings ?? ReminderSettings()
            }
        } catch {
            persistenceError = "Your saved library could not be opened. Your catalog and saved data remain separate."
        }
    }
}
extension AppModel {
    func markNextWatched(_ id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }

        if titles[index].kind == .movie {
            guard titles[index].state != .completed else { return }
            titles[index].state = .completed
        } else if let next = nextUnwatchedEpisode(for: titles[index]) {
            setEpisodeWatched(
                true,
                titleID: id,
                seasonNumber: next.season.number,
                episodeID: next.episode.id
            )
            return
        } else if var progress = titles[index].progress {
            guard progress.episode < progress.totalEpisodes else { return }
            progress.episode = min(progress.episode + 1, progress.totalEpisodes)
            titles[index].progress = progress
            titles[index].state = progress.episode == progress.totalEpisodes ? .completed : .watching
        }

        titles[index].lastWatchedAt = .now
        appendWatchEvent(title: titles[index], kind: .watched)

        addActivity(
            description: "watched \(titles[index].title) \(titles[index].progress?.label ?? "")",
            titleID: titles[index].id
        )
        persist()
        syncSharedStateSoon()
    }

    func setWatchState(_ state: WatchState, for id: MediaTitle.ID) {
        if state == .completed {
            markWatched(id)
            return
        }
        guard let index = trackableTitleIndex(for: id) else { return }
        titles[index].state = state
        if state == .planned {
            titles[index].personalWatchlist = true
        }
        persist()
        refreshRecommendationsSoon()
    }

    func setUserRating(_ rating: Double?, for id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }
        titles[index].userRating = rating.map { min(max($0, 0), 10) }
        persist()
    }

    func updateNotes(_ notes: String, for id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        titles[index].notes = trimmed.isEmpty ? nil : trimmed
        persist()
    }

    func recordRewatch(_ id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }
        titles[index].rewatchCount = titles[index].completedRewatches + 1
        titles[index].lastWatchedAt = .now
        appendWatchEvent(title: titles[index], kind: .rewatch)
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
        titles[index].state = corrected.episode == corrected.totalEpisodes ? .completed : .watching
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

    func replaceLibrary(with snapshot: LibrarySnapshot) {
        titles = merging(savedTitles: snapshot.titles, catalogTitles: seed.titles)
        sharedSpace = snapshot.sharedSpace
        selectedProviderIDs = snapshot.selectedProviderIDs ?? Self.defaultProviderIDs
        allowsAIReranking = snapshot.allowsAIReranking ?? false
        streamingRegionOverride = snapshot.streamingRegionCode.flatMap(StreamingRegion.init(code:))
        reminderSettings = snapshot.reminderSettings ?? reminderSettings
        persist()
        refreshRemindersSoon()
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
    func merging(savedTitles: [MediaTitle], catalogTitles: [MediaTitle]) -> [MediaTitle] {
        let savedByID = Dictionary(uniqueKeysWithValues: savedTitles.map { ($0.id, $0) })
        let catalogIDs = Set(catalogTitles.map(\.id))
        let refreshedCatalog = catalogTitles.map { catalogTitle in
            guard let savedTitle = savedByID[catalogTitle.id] else { return catalogTitle }
            var refreshedTitle = catalogTitle
            refreshedTitle.state = savedTitle.state
            refreshedTitle.progress = savedTitle.progress
            refreshedTitle.userRating = savedTitle.userRating
            refreshedTitle.notes = savedTitle.notes
            refreshedTitle.rewatchCount = savedTitle.rewatchCount
            refreshedTitle.lastWatchedAt = savedTitle.lastWatchedAt
            refreshedTitle.isDismissed = savedTitle.isDismissed
            refreshedTitle.isDisliked = savedTitle.isDisliked
            refreshedTitle.personalWatchlist = savedTitle.personalWatchlist
            refreshedTitle.watchedEpisodeIDs = savedTitle.watchedEpisodeIDs
            return refreshedTitle
        }
        let localOnlyTitles = savedTitles.filter { !catalogIDs.contains($0.id) }
        return refreshedCatalog + localOnlyTitles
    }

    private func isHigherUpNextPriority(_ lhs: MediaTitle, _ rhs: MediaTitle) -> Bool {
        if lhs.state != rhs.state { return lhs.state == .watching }

        let lhsDate = lhs.nextEpisodeAirDate ?? lhs.releaseDate
        let rhsDate = rhs.nextEpisodeAirDate ?? rhs.releaseDate
        switch (lhsDate, rhsDate) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate < rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        if lhs.lastWatchedAt != rhs.lastWatchedAt {
            return (lhs.lastWatchedAt ?? .distantPast) > (rhs.lastWatchedAt ?? .distantPast)
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private static let defaultProviderIDs: Set<StreamingProvider.ID> = [
        StreamingProvider.netflix.id,
        StreamingProvider.primeVideo.id,
        StreamingProvider.appleTV.id
    ]
}
