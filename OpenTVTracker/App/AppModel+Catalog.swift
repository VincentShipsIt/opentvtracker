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

    func mergeCatalogTitles(_ catalogTitles: [MediaTitle]) {
        titles = LibraryTitleIndex.deduplicated(merging(savedTitles: titles, catalogTitles: catalogTitles))
    }

    /// How many index titles a refresh keeps beyond today's premieres in the *transient*
    /// discovery cache. Browse rows stay out of the persisted personal library until the
    /// user tracks them (`ensureTrackableTitleIndex`).
    static let discoveryCatalogLimit = 90

    /// Fills the browse pool the home and Discover screens read from.
    ///
    /// One day of premieres is not a catalog. `schedule/web` on a quiet day returns a
    /// handful of shows, most on networks the provider mapping does not recognize, and
    /// the recommendation filter then discards those for having no known service — which
    /// is why Today rendered a single card above an empty screen. Pulling the catalog
    /// index in behind the schedule gives every browse surface something real to show.
    /// Results live only in `discoveryCatalogPagination` so launch/export does not grow
    /// the durable library with untouched browse rows.
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
                catalogQuery(text: "", page: 1)
            )
            guard discoveryCatalogRequestID == requestID else { return }

            var pagination = DiscoveryCatalogPagination()
            try pagination.apply(scheduled, requestedPage: 1)

            let indexed: [MediaTitle]
            var indexFetchError: String?
            do {
                let results = try await catalogService.search(
                    catalogQuery(text: "", page: 2)
                )
                guard discoveryCatalogRequestID == requestID else { return }
                try pagination.apply(results, requestedPage: 2)
                indexed = results
            } catch {
                guard discoveryCatalogRequestID == requestID else { return }
                indexed = []
                indexFetchError = error.localizedDescription
            }

            let scheduledIDs = Set(scheduled.map(\.id))
            let prioritized = scheduled
                + indexed
                .filter { !scheduledIDs.contains($0.id) && $0.posterURL != nil }
                .sorted { $0.rating > $1.rating }
            let limited = Array(
                CollectionUniquing.uniqued(prioritized, by: \.id).prefix(Self.discoveryCatalogLimit)
            )
            var capped = DiscoveryCatalogPagination()
            capped.replaceTitles(limited, preservingCursorFrom: pagination)
            // Browse rows stay in the transient cache only — never the durable library.
            discoveryCatalogPagination = capped
            discoveryCatalogError = indexFetchError
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
                    catalogQuery(text: "", page: nextPage)
                )
                guard discoveryCatalogRequestID == requestID else { return }

                var pagination = discoveryCatalogPagination
                insertedCount = try pagination.apply(results, requestedPage: nextPage)
                discoveryCatalogPagination = pagination
            } while insertedCount == 0 && discoveryCatalogPagination.nextPage != nil

            discoveryCatalogError = nil
        } catch CatalogServiceError.notFound {
            guard discoveryCatalogRequestID == requestID else { return }
            var pagination = discoveryCatalogPagination
            pagination.markExhausted()
            discoveryCatalogPagination = pagination
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
        if let index = titleIndex(for: id) {
            return titles[index]
        }
        return catalogSearchResults.first(where: { $0.id == id })
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

    func catalogDetailError(for id: MediaTitle.ID) -> String? {
        catalogDetailErrorTitleID == id ? catalogDetailError : nil
    }

    func refreshCatalogDetails(for id: MediaTitle.ID) async {
        guard let existing = mediaTitle(withID: id) else { return }

        if catalogDetailErrorTitleID == id {
            catalogDetailError = nil
            catalogDetailErrorTitleID = nil
        }

        do {
            let details = try await catalogService.title(
                kind: existing.kind,
                catalogID: existing.catalogID,
                region: streamingRegion,
                contentLanguage: contentLanguage,
                metadataSource: existing.metadataSource
            )
            let refreshed = mergingCatalogDetails(details, into: existing)
            // This runs on every appearance of a detail screen, so for an already-enriched
            // title the merge usually reproduces exactly what is on screen. Writing it back
            // anyway re-rendered the whole screen — and re-persisted the library — in the
            // middle of the push animation, for no change at all.
            if refreshed != existing {
                if let index = titleIndex(for: id) {
                    // Only update library rows in place — never promote browse-only titles
                    // just because the detail screen enriched metadata.
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
                var pagination = discoveryCatalogPagination
                pagination.updateTitle(refreshed)
                discoveryCatalogPagination = pagination
            }
        } catch {
            catalogDetailError = error.localizedDescription
            catalogDetailErrorTitleID = id
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
                catalogQuery(text: queryText, page: 1)
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
                catalogQuery(text: queryText, page: nextPage)
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
