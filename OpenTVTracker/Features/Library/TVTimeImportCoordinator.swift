import Foundation
import Observation

@MainActor
@Observable
final class TVTimeImportCoordinator {
    private let session: TVTimeImportSession
    private var manualResolutions: [ImportResolutionIssue.ID: MediaTitle] = [:]
    private var resolutionWaiters: [CheckedContinuation<Void, Never>] = []

    private(set) var preview: LibraryImportPreview?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

    init(session: TVTimeImportSession) {
        self.session = session
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        preview = await session.preview(manualResolutions: manualResolutions)
        errorMessage = nil
    }

    func resolve(
        _ issue: ImportResolutionIssue,
        with title: MediaTitle
    ) async -> Bool {
        await acquireResolutionSlot()
        defer { releaseResolutionSlot() }
        do {
            let detailedTitle = try await session.detailedTitle(title)
            manualResolutions[issue.id] = detailedTitle
            preview = await session.preview(manualResolutions: manualResolutions)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func acquireResolutionSlot() async {
        guard isRefreshing else {
            isRefreshing = true
            return
        }
        await withCheckedContinuation { continuation in
            resolutionWaiters.append(continuation)
        }
    }

    private func releaseResolutionSlot() {
        guard !resolutionWaiters.isEmpty else {
            isRefreshing = false
            return
        }
        resolutionWaiters.removeFirst().resume()
    }

    func search(
        _ text: String,
        kind: MediaKind
    ) async throws -> [MediaTitle] {
        do {
            let results = try await session.search(text, kind: kind)
            errorMessage = nil
            return results
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }
}
