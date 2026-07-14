import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private let store: any LibraryPersisting
    private let seed: LibrarySnapshot
    private var saveTask: Task<Void, Never>?
    private var persistenceRevision = 0

    private(set) var titles: [MediaTitle]
    private(set) var sharedSpace: SharedSpace
    private(set) var selectedProviderIDs: Set<StreamingProvider.ID>
    private(set) var hasLoaded = false
    private(set) var persistenceError: String?

    var selectedMood: Mood = .any

    init(
        store: any LibraryPersisting = FileLibraryStore(),
        seed: LibrarySnapshot = .sample
    ) {
        self.store = store
        self.seed = seed
        titles = seed.titles
        sharedSpace = seed.sharedSpace
        selectedProviderIDs = seed.selectedProviderIDs ?? Self.defaultProviderIDs
    }

    var upNext: [MediaTitle] {
        titles.filter { $0.state == .watching }
    }

    var recommendations: [MediaTitle] {
        titles.filter { title in
            title.state == .planned
                && (selectedMood == .any || title.mood == selectedMood)
                && isAvailableOnSelectedProviders(title)
        }
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

    func titles(in state: WatchState) -> [MediaTitle] {
        titles.filter { $0.state == state }
    }

    func load() async {
        guard !hasLoaded else { return }
        defer { hasLoaded = true }

        do {
            if let snapshot = try await store.load() {
                titles = merging(savedTitles: snapshot.titles, catalogTitles: seed.titles)
                sharedSpace = snapshot.sharedSpace
                selectedProviderIDs = snapshot.selectedProviderIDs ?? Self.defaultProviderIDs
            }
        } catch {
            persistenceError = "Your saved library could not be opened. Preview data is shown instead."
        }
    }

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

        addActivity(description: "watched \(titles[index].title) \(titles[index].progress?.label ?? "")")
        persist()
    }

    func toggleWatchlist(_ id: MediaTitle.ID) {
        guard let index = titles.firstIndex(where: { $0.id == id }) else { return }
        titles[index].state = titles[index].state == .planned ? .watching : .planned
        persist()
    }

    func toggleTogether(_ id: MediaTitle.ID) {
        if let index = sharedSpace.titleIDs.firstIndex(of: id) {
            sharedSpace.titleIDs.remove(at: index)
        } else {
            sharedSpace.titleIDs.append(id)
            if let title = titles.first(where: { $0.id == id }) {
                addActivity(description: "added \(title.title)")
            }
        }
        persist()
    }

    func isShared(_ id: MediaTitle.ID) -> Bool {
        sharedSpace.titleIDs.contains(id)
    }

    func toggleProvider(_ id: StreamingProvider.ID) {
        if selectedProviderIDs.contains(id) {
            selectedProviderIDs.remove(id)
        } else {
            selectedProviderIDs.insert(id)
        }
        persist()
    }

    func isProviderSelected(_ id: StreamingProvider.ID) -> Bool {
        selectedProviderIDs.contains(id)
    }

    func isAvailableOnSelectedProviders(_ title: MediaTitle) -> Bool {
        !selectedProviderIDs.isDisjoint(with: Set(title.providers.map(\.id)))
    }

    private func addActivity(description: String) {
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

    private func persist() {
        let snapshot = LibrarySnapshot(
            titles: titles,
            sharedSpace: sharedSpace,
            selectedProviderIDs: selectedProviderIDs
        )
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

    private func merging(savedTitles: [MediaTitle], catalogTitles: [MediaTitle]) -> [MediaTitle] {
        let savedByID = Dictionary(uniqueKeysWithValues: savedTitles.map { ($0.id, $0) })
        let catalogIDs = Set(catalogTitles.map(\.id))
        let refreshedCatalog = catalogTitles.map { catalogTitle in
            guard let savedTitle = savedByID[catalogTitle.id] else { return catalogTitle }
            var refreshedTitle = catalogTitle
            refreshedTitle.state = savedTitle.state
            refreshedTitle.progress = savedTitle.progress
            return refreshedTitle
        }
        let localOnlyTitles = savedTitles.filter { !catalogIDs.contains($0.id) }
        return refreshedCatalog + localOnlyTitles
    }

    private static let defaultProviderIDs: Set<StreamingProvider.ID> = [
        StreamingProvider.netflix.id,
        StreamingProvider.primeVideo.id,
        StreamingProvider.appleTV.id
    ]
}
