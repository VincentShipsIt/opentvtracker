import Foundation

extension AppModel {
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
