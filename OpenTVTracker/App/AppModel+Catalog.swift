import Foundation

extension AppModel {
    func searchCatalog(text: String) async {
        let queryText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !queryText.isEmpty else {
            catalogSearchResults = []
            catalogSearchError = nil
            isSearchingCatalog = false
            return
        }

        isSearchingCatalog = true
        defer { isSearchingCatalog = false }
        do {
            try await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            catalogSearchResults = try await catalogService.search(
                MediaSearchQuery(text: queryText, kind: nil, page: 1)
            )
            catalogSearchError = nil
        } catch is CancellationError {
            return
        } catch {
            catalogSearchResults = []
            catalogSearchError = error.localizedDescription
        }
    }
}
