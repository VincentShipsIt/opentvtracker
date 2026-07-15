import Foundation

extension AppModel {
    func mediaTitle(withID id: MediaTitle.ID) -> MediaTitle? {
        titles.first(where: { $0.id == id })
            ?? catalogSearchResults.first(where: { $0.id == id })
    }

    func refreshCatalogDetails(for id: MediaTitle.ID) async {
        guard let existing = mediaTitle(withID: id) else { return }

        do {
            let details = try await catalogService.title(
                kind: existing.kind,
                catalogID: existing.catalogID
            )
            let refreshed = mergingCatalogDetails(details, into: existing)

            if let index = titles.firstIndex(where: { $0.id == id }) {
                titles[index] = refreshed
                persist()
            }
            if let index = catalogSearchResults.firstIndex(where: { $0.id == id }) {
                catalogSearchResults[index] = refreshed
            }
        } catch {
            catalogSearchError = error.localizedDescription
        }
    }

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

    private func mergingCatalogDetails(_ details: MediaTitle, into existing: MediaTitle) -> MediaTitle {
        var result = existing
        result.title = details.title
        result.year = details.year
        result.kind = details.kind
        result.synopsis = details.synopsis
        result.genres = details.genres
        result.runtimeMinutes = details.runtimeMinutes
        result.rating = details.rating
        result.nextReleaseDescription = details.nextReleaseDescription
        result.recommendationReason = details.recommendationReason
        result.mood = details.mood
        result.palette = details.palette
        result.providers = details.providers
        result.reviews = details.reviews
        result.posterURL = details.posterURL
        result.backdropURL = details.backdropURL
        result.trailerURL = details.trailerURL
        result.nextEpisodeAirDate = details.nextEpisodeAirDate
        result.releaseDate = details.releaseDate
        result.seasons = details.seasons
        return result
    }
}
