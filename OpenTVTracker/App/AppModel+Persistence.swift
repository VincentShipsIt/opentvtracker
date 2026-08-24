import Foundation

struct PendingLibraryPersistence: Sendable {
    let revision: Int
    let snapshot: LibrarySnapshot
}

extension AppModel {
    /// Registers a load-time metadata cleanup with the same revisioned writer as UI mutations.
    /// A user edit made while this save is suspended becomes a newer pending revision and is
    /// therefore written only after the cleanup finishes.
    func persistMetadataCleanup(_ cleanedSnapshot: LibrarySnapshot) async -> Bool {
        persistenceRevision += 1
        let revision = persistenceRevision
        pendingPersistence = PendingLibraryPersistence(
            revision: revision,
            snapshot: cleanedSnapshot
        )
        persistenceDebounceTask?.cancel()
        persistenceDebounceTask = nil
        await savePendingPersistence(expectedRevision: revision)
        return lastPersistedRevision >= revision
    }

    func merging(savedTitles: [MediaTitle], catalogTitles: [MediaTitle]) -> [MediaTitle] {
        let savedByID = savedTitles.keyedByKeepingFirst(\.id)
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
            refreshedTitle.seriesLifecycle = catalogTitle.seriesLifecycle ?? savedTitle.seriesLifecycle
            refreshedTitle.isUpNextPinned = savedTitle.isUpNextPinned
            refreshedTitle.upNextSnoozedUntil = savedTitle.upNextSnoozedUntil
            refreshedTitle.upNextManualOrder = savedTitle.upNextManualOrder
            return refreshedTrackingTitle(refreshedTitle)
        }
        let localOnlyTitles = savedTitles
            .filter { !catalogIDs.contains($0.id) }
            .map { refreshedTrackingTitle($0) }
        return LibraryTitleIndex.deduplicated(refreshedCatalog + localOnlyTitles)
    }

    func persist() {
        persistenceRevision += 1
        let revision = persistenceRevision
        pendingPersistence = PendingLibraryPersistence(
            revision: revision,
            snapshot: snapshot
        )
        persistenceDebounceTask?.cancel()

        if persistenceFlushCount == 0 {
            persistenceDebounceTask = Task {
                do {
                    try await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    await savePendingPersistence(expectedRevision: revision)
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        } else {
            persistenceDebounceTask = nil
        }
        if reminderSettings.isEnabled {
            refreshRemindersSoon()
        }
    }

    /// Cancels the foreground debounce and drains every pending revision through the one writer.
    /// Both inactive and background transitions call this boundary, so concurrent callers join
    /// the same save instead of issuing duplicate writes.
    func prepareForSuspension() async {
        await flushPendingPersistence()
    }

    func flushPendingPersistence() async {
        persistenceFlushCount += 1
        defer { persistenceFlushCount -= 1 }
        persistenceDebounceTask?.cancel()
        persistenceDebounceTask = nil

        while let pending = pendingPersistence {
            await savePendingPersistence()
            guard lastPersistedRevision >= pending.revision
                || pendingPersistence?.revision != pending.revision else { return }
        }
    }

    private func savePendingPersistence(expectedRevision: Int? = nil) async {
        while let activeSave = saveTask {
            await activeSave.value
            if expectedRevision != nil, Task.isCancelled { return }
        }

        if expectedRevision != nil, Task.isCancelled { return }
        guard let pending = pendingPersistence else { return }
        if let expectedRevision, pending.revision != expectedRevision { return }

        let task = Task {
            await writePendingPersistence(pending)
            saveTask = nil
        }
        saveTask = task
        await task.value
    }

    private func writePendingPersistence(_ pending: PendingLibraryPersistence) async {
        do {
            try await store.save(pending.snapshot)
            lastPersistedRevision = max(lastPersistedRevision, pending.revision)
            if pendingPersistence?.revision == pending.revision {
                pendingPersistence = nil
            }
            if pending.revision == persistenceRevision {
                persistenceError = nil
                publishWidgetSnapshot()
            }
        } catch is CancellationError {
            return
        } catch {
            if pending.revision == persistenceRevision {
                persistenceError = "Your latest change is visible but could not be saved."
            }
        }
    }

    func refreshRecommendationsSoon() {
        // Fire-and-forget; refreshRecommendations cancels/stamps prior in-flight work.
        Task { await refreshRecommendations() }
    }
}
