import Foundation

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
                    publishWidgetSnapshot()
                }
            } catch is CancellationError {
                return
            } catch {
                if revision == persistenceRevision {
                    persistenceError = "Your latest change is visible but could not be saved."
                }
            }
        }
        if reminderSettings.isEnabled {
            refreshRemindersSoon()
        }
    }

    func refreshRecommendationsSoon() {
        Task { await refreshRecommendations() }
    }
}
