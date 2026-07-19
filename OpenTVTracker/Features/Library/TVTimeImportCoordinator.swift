import Foundation
import Observation

@MainActor
@Observable
final class TVTimeImportCoordinator {
    private let session: TVTimeImportSession
    private var manualResolutions: [ImportResolutionIssue.ID: MediaTitle] = [:]
    private var resolutionTail: Task<Void, Never>?
    private var pendingResolutionCount = 0

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
    ) async {
        let previous = resolutionTail
        pendingResolutionCount += 1
        isRefreshing = true
        let task = Task { @MainActor in
            await previous?.value
            self.manualResolutions[issue.id] = await self.session.detailedTitle(title)
            self.preview = await self.session.preview(manualResolutions: self.manualResolutions)
            self.errorMessage = nil
            self.pendingResolutionCount -= 1
            if self.pendingResolutionCount == 0 {
                self.isRefreshing = false
                self.resolutionTail = nil
            }
        }
        resolutionTail = task
        await task.value
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
