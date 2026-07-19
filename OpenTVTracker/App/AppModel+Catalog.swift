import Foundation

extension AppModel {
    var titlesOnSelectedProviders: [MediaTitle] {
        titles.filter(isAvailableOnSelectedProviders)
    }

    var selectedProviders: [StreamingProvider] {
        StreamingProvider.supportedSubscriptions.filter { selectedProviderIDs.contains($0.id) }
    }

    var streamingRegion: StreamingRegion {
        streamingRegionOverride ?? .deviceDefault()
    }

    func trackableTitleIndex(for id: MediaTitle.ID) -> Int? {
        if let index = titles.firstIndex(where: { $0.id == id }) { return index }
        guard let catalogTitle = catalogSearchResults.first(where: { $0.id == id }) else { return nil }
        titles.append(catalogTitle)
        return titles.indices.last
    }

    func mergeCatalogTitles(_ catalogTitles: [MediaTitle]) {
        titles = merging(savedTitles: titles, catalogTitles: catalogTitles)
    }

    func refreshDiscoveryCatalog() async {
        do {
            let results = try await catalogService.search(
                MediaSearchQuery(text: "", kind: nil, page: 1, region: streamingRegion)
            )
            mergeCatalogTitles(results)
            catalogSearchError = nil
        } catch {
            catalogSearchError = error.localizedDescription
        }
    }

    func mediaTitle(withID id: MediaTitle.ID) -> MediaTitle? {
        titles.first(where: { $0.id == id })
            ?? catalogSearchResults.first(where: { $0.id == id })
    }

    func mediaTitle(for activity: SharedActivity) -> MediaTitle? {
        if let titleID = activity.titleID, let title = mediaTitle(withID: titleID) {
            return title
        }
        return titles.first { title in
            activity.description.localizedCaseInsensitiveContains(title.title)
        }
    }

    func refreshCatalogDetails(for id: MediaTitle.ID) async {
        guard let existing = mediaTitle(withID: id) else { return }

        do {
            let details = try await catalogService.title(
                kind: existing.kind,
                catalogID: existing.catalogID,
                region: streamingRegion
            )
            let refreshed = mergingCatalogDetails(details, into: existing)

            let index = trackableTitleIndex(for: id)
            if let index {
                titles[index] = refreshed
                if isShared(id) {
                    prepareSharedTitleMetadataForSync()
                    syncSharedStateSoon()
                }
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
                MediaSearchQuery(text: queryText, kind: nil, page: 1, region: streamingRegion)
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
                MediaSearchQuery(text: queryText, kind: nil, page: nextPage, region: streamingRegion)
            )
            let existingIDs = Set(catalogSearchResults.map(\.id))
            catalogSearchResults.append(contentsOf: results.filter { !existingIDs.contains($0.id) })
            catalogSearchPage = nextPage
            hasMoreCatalogResults = results.count >= 20
        } catch {
            catalogSearchError = error.localizedDescription
        }
    }

    func setStreamingRegionOverride(_ region: StreamingRegion?) {
        let previousRegion = streamingRegion
        storeStreamingRegionOverride(region)
        persist()

        guard streamingRegion != previousRegion else { return }
        invalidateUpcomingCalendarRefresh()
        clearUntrackedCatalogTitles()
        catalogSearchResults = []
        catalogSearchPage = 0
        catalogSearchQuery = ""
        hasMoreCatalogResults = false

        Task {
            await refreshDiscoveryCatalog()
            await refreshUpcomingCalendar(force: true)
            await refreshRecommendations()
        }
    }

    private func clearUntrackedCatalogTitles() {
        let sharedTitleIDs = Set(sharedSpace.titleIDs)
        titles.removeAll { title in
            title.state == .planned
                && !title.isOnPersonalWatchlist
                && title.userRating == nil
                && title.notes == nil
                && title.completedRewatches == 0
                && !sharedTitleIDs.contains(title.id)
        }
    }

    func mergingCatalogDetails(_ details: MediaTitle, into existing: MediaTitle) -> MediaTitle {
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
        result.nextEpisodeAirDateIsAllDay = details.nextEpisodeAirDateIsAllDay
        result.releaseDate = details.releaseDate
        result.seasons = details.seasons
        return result
    }
}
