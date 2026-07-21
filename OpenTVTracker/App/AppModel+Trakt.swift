import Foundation

extension AppModel {
    var traktPendingChangeCount: Int {
        TraktSyncEngine.pendingChangeCount(in: snapshot)
    }

    func refreshTraktAuthorizationStatus() async {
        isTraktAuthorized = await traktService.isAuthorized()
    }

    func beginTraktAuthorization() async throws -> TraktDeviceAuthorization {
        traktSyncError = nil
        return try await traktService.beginAuthorization()
    }

    func completeTraktAuthorization(_ authorization: TraktDeviceAuthorization) async throws {
        do {
            try await traktService.completeAuthorization(authorization)
            isTraktAuthorized = true
            traktSyncError = nil
        } catch {
            traktSyncError = error.localizedDescription
            throw error
        }
    }

    func disconnectTrakt() async {
        do {
            try await traktService.disconnect()
            isTraktAuthorized = false
            traktSyncState = .empty
            traktSyncSummary = nil
            traktSyncError = nil
            persist()
        } catch {
            traktSyncError = error.localizedDescription
        }
    }

    func syncTrakt() async {
        guard !isTraktSyncing else { return }
        isTraktSyncing = true
        traktSyncError = nil
        defer { isTraktSyncing = false }

        do {
            let syncSnapshot = snapshot
            let result = try await traktService.sync(syncSnapshot)
            titles = Self.mergingTraktTitles(
                baseline: syncSnapshot.titles,
                current: titles,
                synced: result.snapshot.titles
            )
            traktSyncState = result.snapshot.traktSyncState ?? .empty
            traktSyncSummary = result.summary.description
            isTraktAuthorized = true
            persist()
        } catch {
            traktSyncError = error.localizedDescription
            traktSyncState.lastError = error.localizedDescription
            isTraktAuthorized = await traktService.isAuthorized()
            persist()
        }
    }

    static func mergingTraktTitles(
        baseline: [MediaTitle],
        current: [MediaTitle],
        synced: [MediaTitle]
    ) -> [MediaTitle] {
        let baselineByID = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        var merged = synced.compactMap { syncedTitle -> MediaTitle? in
            guard let baselineTitle = baselineByID[syncedTitle.id] else {
                return currentByID[syncedTitle.id] ?? syncedTitle
            }
            guard let currentTitle = currentByID[syncedTitle.id] else {
                return nil
            }
            return currentTitle == baselineTitle ? syncedTitle : currentTitle
        }
        let mergedIDs = Set(merged.map(\.id))
        merged.append(contentsOf: current.filter { baselineByID[$0.id] == nil && !mergedIDs.contains($0.id) })
        return merged
    }
}
