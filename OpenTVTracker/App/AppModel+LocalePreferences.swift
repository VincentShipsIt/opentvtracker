import Foundation

extension AppModel {
    var streamingRegion: StreamingRegion {
        streamingRegionOverride ?? .deviceDefault()
    }

    var contentLanguage: ContentLanguage {
        contentLanguageOverride ?? .deviceDefault()
    }

    func catalogQuery(
        text: String,
        kind: MediaKind? = nil,
        page: Int
    ) -> MediaSearchQuery {
        MediaSearchQuery(
            text: text,
            kind: kind,
            page: page,
            region: streamingRegion,
            contentLanguage: contentLanguage
        )
    }

    func setStreamingRegionOverride(_ region: StreamingRegion?) {
        let previousRegion = streamingRegion
        storeStreamingRegionOverride(region)
        persist()

        guard streamingRegion != previousRegion else { return }
        refreshCatalogForLocaleChange()
    }

    func setContentLanguageOverride(_ language: ContentLanguage?) {
        let previousLanguage = contentLanguage
        storeContentLanguageOverride(language)
        persist()

        guard contentLanguage != previousLanguage else { return }
        refreshCatalogForLocaleChange()
    }

    private func refreshCatalogForLocaleChange() {
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
        // Keep only rows the user has actually touched (or that belong to shared/list sets).
        // Discovery browse lives in discoveryCatalogPagination and is already cleared above.
        titles.removeAll { title in
            title.state == .planned
                && !title.isOnPersonalWatchlist
                && title.userRating == nil
                && title.notes == nil
                && title.completedRewatches == 0
                && title.isUpNextPinned != true
                && title.upNextSnoozedUntil == nil
                && title.upNextManualOrder == nil
                && (title.watchedEpisodeIDs ?? []).isEmpty
                && title.progress == nil
                && title.lastWatchedAt == nil
                && !retainedTitleIDs.contains(title.id)
        }
    }
}
