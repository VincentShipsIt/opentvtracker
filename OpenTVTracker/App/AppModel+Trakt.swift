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
            let result = try await traktService.sync(snapshot)
            titles = result.snapshot.titles
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
}
