import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private let store: any LibraryPersisting

    private(set) var titles: [MediaTitle]
    private(set) var sharedSpace: SharedSpace
    private(set) var hasLoaded = false
    private(set) var persistenceError: String?

    var selectedMood: Mood = .any

    init(
        store: any LibraryPersisting = FileLibraryStore(),
        seed: LibrarySnapshot = .sample
    ) {
        self.store = store
        titles = seed.titles
        sharedSpace = seed.sharedSpace
    }

    var upNext: [MediaTitle] {
        titles.filter { $0.state == .watching }
    }

    var recommendations: [MediaTitle] {
        titles.filter { title in
            title.state == .planned && (selectedMood == .any || title.mood == selectedMood)
        }
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
                titles = snapshot.titles
                sharedSpace = snapshot.sharedSpace
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
            titles[index].state = .watching
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
        let snapshot = LibrarySnapshot(titles: titles, sharedSpace: sharedSpace)
        let store = store

        Task {
            do {
                try await store.save(snapshot)
                persistenceError = nil
            } catch {
                persistenceError = "Your latest change is visible but could not be saved."
            }
        }
    }
}
