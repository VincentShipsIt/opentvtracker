import Foundation
import Observation

@MainActor
@Observable
final class TVTimeImportCoordinator {
    private let session: TVTimeImportSession
    private var manualResolutions: [ImportResolutionIssue.ID: MediaTitle] = [:]

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
        manualResolutions[issue.id] = await session.detailedTitle(title)
        await refresh()
    }

    func search(
        _ text: String,
        kind: MediaKind
    ) async -> [MediaTitle] {
        do {
            let results = try await session.search(text, kind: kind)
            errorMessage = nil
            return results
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }
}
