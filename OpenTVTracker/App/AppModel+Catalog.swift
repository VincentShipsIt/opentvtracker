import Foundation

extension AppModel {
    func searchCatalog(text: String) async {
        let queryText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !queryText.isEmpty else {
            catalogSearchResults = []
            catalogSearchError = nil
            isSearchingCatalog = false
            catalogSearchPage = 0
            catalogSearchQuery = ""
            hasMoreCatalogResults = false
            return
        }

        isSearchingCatalog = true
        defer { isSearchingCatalog = false }
        do {
            try await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let results = try await catalogService.search(
                MediaSearchQuery(text: queryText, kind: nil, page: 1)
            )
            guard queryText == text.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            catalogSearchResults = results
            catalogSearchPage = 1
            catalogSearchQuery = queryText
            hasMoreCatalogResults = results.count >= 20
            catalogSearchError = nil
        } catch is CancellationError {
            return
        } catch {
            catalogSearchResults = []
            catalogSearchError = error.localizedDescription
        }
    }

    func loadMoreCatalogResults(text: String) async {
        let queryText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSearchingCatalog, hasMoreCatalogResults, queryText == catalogSearchQuery else { return }
        isSearchingCatalog = true
        defer { isSearchingCatalog = false }
        do {
            let nextPage = catalogSearchPage + 1
            let results = try await catalogService.search(
                MediaSearchQuery(text: queryText, kind: nil, page: nextPage)
            )
            let existingIDs = Set(catalogSearchResults.map(\.id))
            catalogSearchResults.append(contentsOf: results.filter { !existingIDs.contains($0.id) })
            catalogSearchPage = nextPage
            hasMoreCatalogResults = results.count >= 20
        } catch {
            catalogSearchError = error.localizedDescription
        }
    }
}
