import Foundation
import Observation
@MainActor
@Observable
final class AppModel {
    private let store: any LibraryPersisting
    private let recommendationService: any RecommendationProviding
    let catalogService: any CatalogProviding
    private let seed: LibrarySnapshot
    private var saveTask: Task<Void, Never>?
    private var persistenceRevision = 0

    var titles: [MediaTitle]
    var sharedSpace: SharedSpace
    private(set) var selectedProviderIDs: Set<StreamingProvider.ID>
    private(set) var allowsAIReranking: Bool
    private(set) var hasLoaded = false
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
        catalogService: (any CatalogProviding)? = nil,
        seed: LibrarySnapshot = .sample
    ) {
        self.store = store
        self.recommendationService = recommendationService
        self.catalogService = catalogService ?? FallbackCatalogService(
            primary: AppServiceConfiguration.apiBaseURL.map { ServerCatalogService(baseURL: $0) },
            fallback: LocalCatalogService(titles: seed.titles)
        )
        self.seed = seed
        titles = seed.titles
        sharedSpace = seed.sharedSpace
        selectedProviderIDs = seed.selectedProviderIDs ?? Self.defaultProviderIDs
        allowsAIReranking = seed.allowsAIReranking ?? false
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
    var titlesOnSelectedProviders: [MediaTitle] {
        titles.filter(isAvailableOnSelectedProviders)
    }

    var selectedProviders: [StreamingProvider] {
        StreamingProvider.supportedSubscriptions.filter { selectedProviderIDs.contains($0.id) }
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
            allowsAIReranking: allowsAIReranking
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

        do {
            if let snapshot = try await store.load() {
                titles = merging(savedTitles: snapshot.titles, catalogTitles: seed.titles)
                sharedSpace = snapshot.sharedSpace
                selectedProviderIDs = snapshot.selectedProviderIDs ?? Self.defaultProviderIDs
                allowsAIReranking = snapshot.allowsAIReranking ?? false
            }
        } catch {
            persistenceError = "Your saved library could not be opened. Preview data is shown instead."
        }
        await refreshRecommendations()
    }
}

extension AppModel {
    func markNextWatched(_ id: MediaTitle.ID) {
        guard let index = titles.firstIndex(where: { $0.id == id }) else { return }

        if titles[index].kind == .movie {
            guard titles[index].state != .completed else { return }
            titles[index].state = .completed
        } else if var progress = titles[index].progress {
            guard progress.episode < progress.totalEpisodes else { return }
            progress.episode = min(progress.episode + 1, progress.totalEpisodes)
            titles[index].progress = progress
            titles[index].state = progress.episode == progress.totalEpisodes ? .completed : .watching
        }

        titles[index].lastWatchedAt = .now
        appendWatchEvent(title: titles[index], kind: .watched)

        addActivity(description: "watched \(titles[index].title) \(titles[index].progress?.label ?? "")")
        persist()
        syncSharedStateSoon()
    }

    func setWatchState(_ state: WatchState, for id: MediaTitle.ID) {
        guard let index = titles.firstIndex(where: { $0.id == id }) else { return }
        titles[index].state = state
        if state == .planned {
            titles[index].personalWatchlist = true
        }
        persist()
    }

    func setUserRating(_ rating: Double?, for id: MediaTitle.ID) {
        guard let index = titles.firstIndex(where: { $0.id == id }) else { return }
        titles[index].userRating = rating.map { min(max($0, 0), 10) }
        persist()
    }

    func updateNotes(_ notes: String, for id: MediaTitle.ID) {
        guard let index = titles.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        titles[index].notes = trimmed.isEmpty ? nil : trimmed
        persist()
    }

    func recordRewatch(_ id: MediaTitle.ID) {
        guard let index = titles.firstIndex(where: { $0.id == id }) else { return }
        titles[index].rewatchCount = titles[index].completedRewatches + 1
        titles[index].lastWatchedAt = .now
        appendWatchEvent(title: titles[index], kind: .rewatch)
        addActivity(description: "rewatched \(titles[index].title)")
        persist()
        syncSharedStateSoon()
    }

    func correctProgress(_ progress: EpisodeProgress, for id: MediaTitle.ID) {
        guard let index = titles.firstIndex(where: { $0.id == id }), titles[index].kind == .series else { return }
        let corrected = EpisodeProgress(
            season: max(progress.season, 1),
            episode: min(max(progress.episode, 0), max(progress.totalEpisodes, 1)),
            totalEpisodes: max(progress.totalEpisodes, 1)
        )
        let supersededID = sharedSpace.watchEvents?.last(where: { $0.titleID == id })?.id
        titles[index].progress = corrected
        titles[index].state = corrected.episode == corrected.totalEpisodes ? .completed : .watching
        appendWatchEvent(title: titles[index], kind: .correction, supersedesEventID: supersededID)
        addActivity(description: "corrected \(titles[index].title) to \(corrected.label)")
        persist()
        syncSharedStateSoon()
    }

    func setRecommendationDismissed(_ dismissed: Bool, for id: MediaTitle.ID) {
        guard let index = titles.firstIndex(where: { $0.id == id }) else { return }
        titles[index].isDismissed = dismissed
        persist()
        refreshRecommendationsSoon()
    }

    func setRecommendationDisliked(_ disliked: Bool, for id: MediaTitle.ID) {
        guard let index = titles.firstIndex(where: { $0.id == id }) else { return }
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

    func replaceLibrary(with snapshot: LibrarySnapshot) {
        titles = merging(savedTitles: snapshot.titles, catalogTitles: seed.titles)
        sharedSpace = snapshot.sharedSpace
        selectedProviderIDs = snapshot.selectedProviderIDs ?? Self.defaultProviderIDs
        allowsAIReranking = snapshot.allowsAIReranking ?? false
        persist()
    }

    func toggleWatchlist(_ id: MediaTitle.ID) {
        guard let index = titles.firstIndex(where: { $0.id == id }) else { return }
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
    func addActivity(description: String) {
        let currentMember = sharedSpace.members.first(where: \.isCurrentUser)
        let activity = SharedActivity(
            id: UUID().uuidString,
            memberID: currentMember?.id ?? "local-user",
            description: description.trimmingCharacters(in: .whitespaces),
            relativeDate: "Now",
            symbol: "checkmark"
        )
        sharedSpace.activity.insert(activity, at: 0)
    }

    func persist() {
        let snapshot = self.snapshot
        let store = store
        persistenceRevision += 1
        let revision = persistenceRevision
        saveTask?.cancel()

        saveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                try await store.save(snapshot)
                if revision == persistenceRevision {
                    persistenceError = nil
                }
            } catch is CancellationError {
                return
            } catch {
                if revision == persistenceRevision {
                    persistenceError = "Your latest change is visible but could not be saved."
                }
            }
        }
    }

    private func refreshRecommendationsSoon() {
        Task { await refreshRecommendations() }
    }

    private func merging(savedTitles: [MediaTitle], catalogTitles: [MediaTitle]) -> [MediaTitle] {
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
            return refreshedTitle
        }
        let localOnlyTitles = savedTitles.filter { !catalogIDs.contains($0.id) }
        return refreshedCatalog + localOnlyTitles
    }

    func appendWatchEvent(
        title: MediaTitle,
        kind: WatchEventKind,
        memberID: SpaceMember.ID? = nil,
        supersedesEventID: String? = nil
    ) {
        let resolvedMemberID = memberID ?? sharedSpace.members.first(where: \.isCurrentUser)?.id ?? "local-user"
        let event = SharedWatchEvent(
            id: UUID().uuidString,
            titleID: title.id,
            memberID: resolvedMemberID,
            kind: kind,
            season: title.progress?.season,
            episode: title.progress?.episode,
            occurredAt: .now,
            supersedesEventID: supersedesEventID
        )
        var events = sharedSpace.watchEvents ?? []
        events.append(event)
        sharedSpace.watchEvents = events
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
