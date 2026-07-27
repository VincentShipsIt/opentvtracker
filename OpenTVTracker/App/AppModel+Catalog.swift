import Foundation

extension AppModel {
    var titlesOnSelectedProviders: [MediaTitle] {
        titles.filter(isAvailableOnSelectedProviders)
    }

    var discoveryCatalogTitles: [MediaTitle] {
        discoveryCatalogPagination.titles
    }

    var hasMoreDiscoveryCatalogTitles: Bool {
        discoveryCatalogPagination.nextPage != nil
    }

    var discoverableTitles: [MediaTitle] {
        var seenIDs: Set<MediaTitle.ID> = []
        return (titles + discoveryCatalogTitles).filter { seenIDs.insert($0.id).inserted }
    }

    var discoverableTitlesOnSelectedProviders: [MediaTitle] {
        discoverableTitles.filter(isAvailableOnSelectedProviders)
    }

    var selectedProviders: [StreamingProvider] {
        StreamingProvider.supportedSubscriptions.filter { selectedProviderIDs.contains($0.id) }
    }

    func newReleasesOnSelectedProviders(referenceDate: Date = .now) -> [MediaTitle] {
        let cutoff = referenceDate.addingTimeInterval(-14 * 24 * 60 * 60)
        return titlesOnSelectedProviders
            .filter { title in
                guard let releaseDate = title.nextEpisodeAirDate ?? title.releaseDate else { return false }
                return releaseDate >= cutoff && releaseDate <= referenceDate
            }
            .sorted {
                ($0.nextEpisodeAirDate ?? $0.releaseDate ?? .distantPast)
                    > ($1.nextEpisodeAirDate ?? $1.releaseDate ?? .distantPast)
            }
    }

    var streamingRegion: StreamingRegion {
        streamingRegionOverride ?? .deviceDefault()
    }

    func trackableTitleIndex(for id: MediaTitle.ID) -> Int? {
        if let index = titles.firstIndex(where: { $0.id == id }) { return index }
        guard let catalogTitle = catalogSearchResults.first(where: { $0.id == id })
            ?? discoveryCatalogTitles.first(where: { $0.id == id })
        else { return nil }
        titles.append(catalogTitle)
        return titles.indices.last
    }

    func mergeCatalogTitles(_ catalogTitles: [MediaTitle]) {
        titles = merging(savedTitles: titles, catalogTitles: catalogTitles)
    }

    /// How many index titles a refresh keeps beyond today's premieres.
    ///
    /// `titles` is what gets persisted in the snapshot, and the catalog index returns
    /// hundreds of shows per page, so the whole page cannot simply be merged. Untracked
    /// catalog rows are disposable — `clearUntrackedCatalogTitles` already drops them on
    /// a region change — but the cap is what keeps the store from growing every launch.
    static let discoveryCatalogLimit = 90

    /// Fills the browse pool the home and Discover screens read from.
    ///
    /// One day of premieres is not a catalog. `schedule/web` on a quiet day returns a
    /// handful of shows, most on networks the provider mapping does not recognize, and
    /// the recommendation filter then discards those for having no known service — which
    /// is why Today rendered a single card above an empty screen. Pulling the catalog
    /// index in behind the schedule gives every browse surface something real to show.
    /// The first two pages also seed a transient paginator so Discover can keep loading
    /// without adding hundreds of untouched rows to the persisted library.
    func refreshDiscoveryCatalog() async {
        let requestID = UUID()
        discoveryCatalogRequestID = requestID
        discoveryCatalogError = nil
        isLoadingDiscoveryCatalog = true
        defer {
            if discoveryCatalogRequestID == requestID {
                isLoadingDiscoveryCatalog = false
            }
        }

        do {
            let scheduled = try await catalogService.search(
                MediaSearchQuery(text: "", kind: nil, page: 1, region: streamingRegion)
            )
            guard discoveryCatalogRequestID == requestID else { return }

            var pagination = DiscoveryCatalogPagination()
            try pagination.apply(scheduled, requestedPage: 1)

            let indexed: [MediaTitle]
            do {
                let results = try await catalogService.search(
                    MediaSearchQuery(text: "", kind: nil, page: 2, region: streamingRegion)
                )
                guard discoveryCatalogRequestID == requestID else { return }
                try pagination.apply(results, requestedPage: 2)
                indexed = results
            } catch {
                guard discoveryCatalogRequestID == requestID else { return }
                indexed = []
            }

            let scheduledIDs = Set(scheduled.map(\.id))
            let browsable = indexed
                .filter { !scheduledIDs.contains($0.id) && $0.posterURL != nil }
                .sorted { $0.rating > $1.rating }
                .prefix(Self.discoveryCatalogLimit)

            discoveryCatalogPagination = pagination
            mergeCatalogTitles(scheduled + browsable)
            discoveryCatalogError = nil
        } catch {
            guard discoveryCatalogRequestID == requestID else { return }
            discoveryCatalogError = error.localizedDescription
        }
    }

    func loadMoreDiscoveryCatalog() async {
        guard !isLoadingDiscoveryCatalog else { return }
        let requestID = discoveryCatalogRequestID
        discoveryCatalogError = nil
        isLoadingDiscoveryCatalog = true
        defer {
            if discoveryCatalogRequestID == requestID {
                isLoadingDiscoveryCatalog = false
            }
        }

        do {
            var insertedCount = 0
            repeat {
                guard let nextPage = discoveryCatalogPagination.nextPage else { return }
                let results = try await catalogService.search(
                    MediaSearchQuery(text: "", kind: nil, page: nextPage, region: streamingRegion)
                )
                guard discoveryCatalogRequestID == requestID else { return }

                var pagination = discoveryCatalogPagination
                insertedCount = try pagination.apply(results, requestedPage: nextPage)
                discoveryCatalogPagination = pagination
            } while insertedCount == 0 && discoveryCatalogPagination.nextPage != nil

            discoveryCatalogError = nil
        } catch is CancellationError {
            return
        } catch {
            guard discoveryCatalogRequestID == requestID else { return }
            discoveryCatalogError = error.localizedDescription
        }
    }

    /// Everything in the catalog the user has not touched, best first.
    ///
    /// Deliberately not filtered by streaming service. `recommendations` is a re-ranking
    /// of the plan queue on selected subscriptions, so on a fresh library it is one or
    /// two entries — and a title whose network we could not map to a service is unknown,
    /// not unavailable. Hiding those is what left the home screen blank. Selected
    /// services still win the ordering, they just no longer decide what exists.
    func browsableCatalogTitles(limit: Int = 24, excluding excludedIDs: Set<MediaTitle.ID> = []) -> [MediaTitle] {
        discoverableTitles
            .filter { title in
                title.state == .planned
                    && !title.isOnPersonalWatchlist
                    && title.isDismissed != true
                    && title.isDisliked != true
                    && title.posterURL != nil
                    && !excludedIDs.contains(title.id)
            }
            .sorted { lhs, rhs in
                let lhsOnService = isAvailableOnSelectedProviders(lhs)
                let rhsOnService = isAvailableOnSelectedProviders(rhs)
                if lhsOnService != rhsOnService { return lhsOnService }
                return lhs.rating > rhs.rating
            }
            .prefix(limit)
            .map { $0 }
    }

    func mediaTitle(withID id: MediaTitle.ID) -> MediaTitle? {
        titles.first(where: { $0.id == id })
            ?? catalogSearchResults.first(where: { $0.id == id })
            ?? discoveryCatalogTitles.first(where: { $0.id == id })
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
            // This runs on every appearance of a detail screen, so for an already-enriched
            // title the merge usually reproduces exactly what is on screen. Writing it back
            // anyway re-rendered the whole screen — and re-persisted the library — in the
            // middle of the push animation, for no change at all.
            if refreshed != existing, let index = trackableTitleIndex(for: id) {
                titles[index] = refreshed
                if isShared(id) || isTitleSharedViaList(id) {
                    prepareSharedTitleMetadataForSync()
                    syncSharedStateSoon()
                }
                persist()
            }
            if let index = catalogSearchResults.firstIndex(where: { $0.id == id }),
               catalogSearchResults[index] != refreshed {
                catalogSearchResults[index] = refreshed
            }
        } catch {
            catalogSearchError = error.localizedDescription
        }
    }

    func searchCatalog(text: String) async {
        let queryText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = UUID()
        catalogSearchRequestID = requestID

        guard !queryText.isEmpty else {
            catalogSearchResults = []
            catalogSearchError = nil
            isSearchingCatalog = false
            catalogSearchPage = 0
            catalogSearchQuery = ""
            hasMoreCatalogResults = false
            return
        }

        catalogSearchResults = []
        catalogSearchError = nil
        catalogSearchPage = 0
        catalogSearchQuery = queryText
        hasMoreCatalogResults = false
        isSearchingCatalog = true
        defer {
            if catalogSearchRequestID == requestID {
                isSearchingCatalog = false
            }
        }
        do {
            try await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, catalogSearchRequestID == requestID else { return }
            let results = try await catalogService.search(
                MediaSearchQuery(text: queryText, kind: nil, page: 1, region: streamingRegion)
            )
            guard catalogSearchRequestID == requestID, catalogSearchQuery == queryText else { return }
            catalogSearchResults = results
            catalogSearchPage = 1
            hasMoreCatalogResults = results.count >= 20
            catalogSearchError = nil
        } catch is CancellationError {
            return
        } catch {
            guard catalogSearchRequestID == requestID else { return }
            catalogSearchResults = []
            catalogSearchError = error.localizedDescription
        }
    }

    func loadMoreCatalogResults(text: String) async {
        let queryText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSearchingCatalog, hasMoreCatalogResults, queryText == catalogSearchQuery else { return }
        let requestID = catalogSearchRequestID
        catalogSearchError = nil
        isSearchingCatalog = true
        defer {
            if catalogSearchRequestID == requestID {
                isSearchingCatalog = false
            }
        }
        do {
            let nextPage = catalogSearchPage + 1
            let results = try await catalogService.search(
                MediaSearchQuery(text: queryText, kind: nil, page: nextPage, region: streamingRegion)
            )
            guard catalogSearchRequestID == requestID, catalogSearchQuery == queryText else { return }
            let existingIDs = Set(catalogSearchResults.map(\.id))
            catalogSearchResults.append(contentsOf: results.filter { !existingIDs.contains($0.id) })
            catalogSearchPage = nextPage
            hasMoreCatalogResults = results.count >= 20
            catalogSearchError = nil
        } catch {
            guard catalogSearchRequestID == requestID else { return }
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
        catalogSearchRequestID = UUID()
        catalogSearchResults = []
        catalogSearchError = nil
        isSearchingCatalog = false
        catalogSearchPage = 0
        catalogSearchQuery = ""
        hasMoreCatalogResults = false
        discoveryCatalogRequestID = UUID()
        discoveryCatalogPagination = DiscoveryCatalogPagination()
        discoveryCatalogError = nil
        isLoadingDiscoveryCatalog = false

        Task {
            await refreshDiscoveryCatalog()
            await refreshUpcomingCalendar(force: true)
            await refreshRecommendations()
        }
    }

    private func clearUntrackedCatalogTitles() {
        let listTitleIDs = lists.flatMap(\.titleIDs)
        let sharedListTitleIDs = (sharedSpace.sharedLists ?? [])
            .filter { !$0.isDeleted }
            .flatMap(\.titleIDs)
        let retainedTitleIDs = Set(sharedSpace.titleIDs + listTitleIDs + sharedListTitleIDs)
        titles.removeAll { title in
            title.state == .planned
                && !title.isOnPersonalWatchlist
                && title.userRating == nil
                && title.notes == nil
                && title.completedRewatches == 0
                && title.isUpNextPinned != true
                && title.upNextSnoozedUntil == nil
                && title.upNextManualOrder == nil
                && !retainedTitleIDs.contains(title.id)
        }
    }

    func mergingCatalogDetails(_ details: MediaTitle, into existing: MediaTitle) -> MediaTitle {
        var result = existing
        result.title = details.title
        result.alternativeTitles = details.alternativeTitles
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
        result.seriesLifecycle = details.seriesLifecycle ?? existing.seriesLifecycle
        return refreshedTrackingTitle(result)
    }
}

struct DiscoveryCatalogPagination: Hashable, Sendable {
    static let maximumPage = 20

    private(set) var titles: [MediaTitle] = []
    private(set) var loadedPages: Set<Int> = []
    private(set) var nextPage: Int? = 1

    @discardableResult
    mutating func apply(_ results: [MediaTitle], requestedPage: Int) throws -> Int {
        guard requestedPage == nextPage else {
            throw DiscoveryCatalogPaginationError.unexpectedPage
        }
        guard !loadedPages.contains(requestedPage) else { return 0 }

        var seenIDs = Set(titles.map(\.id))
        let uniqueResults = results.filter { seenIDs.insert($0.id).inserted }
        titles.append(contentsOf: uniqueResults)
        loadedPages.insert(requestedPage)
        // Page one may be an empty daily schedule while page two starts the full
        // catalog index, so only an empty index page means the catalog is exhausted.
        nextPage = (results.isEmpty && requestedPage > 1) || requestedPage >= Self.maximumPage
            ? nil
            : requestedPage + 1
        return uniqueResults.count
    }
}

enum DiscoveryCatalogPaginationError: LocalizedError {
    case unexpectedPage

    var errorDescription: String? {
        "The catalog returned an unexpected page. Try again."
    }
}
