import Foundation

extension LibraryTransferService {
    static func titlesMatch(_ lhs: MediaTitle, _ rhs: MediaTitle) -> Bool {
        if lhs.catalogID > 0, rhs.catalogID > 0 { return lhs.catalogID == rhs.catalogID }
        return normalizedTitle(lhs.title) == normalizedTitle(rhs.title) && lhs.year == rhs.year
    }

    static func identityKey(for title: MediaTitle) -> String {
        title.catalogID > 0 ? "catalog:\(title.catalogID)" : "title:\(normalizedTitle(title.title)):\(title.year)"
    }

    static func matchingTitleIndex(
        _ values: [String: String],
        titles: [MediaTitle]
    ) -> Array<MediaTitle>.Index? {
        if let titleID = stringValue(in: values, keys: ["title_id"]),
           let index = titles.firstIndex(where: { $0.id == titleID }) {
            return index
        }
        let catalogID = intValue(in: values, keys: ["catalog_id", "tmdb_id", "id"])
        let titleName = stringValue(in: values, keys: ["title", "name", "series_name", "movie_name"])
        let year = intValue(in: values, keys: ["year", "release_year"])

        return titles.firstIndex { title in
            if let catalogID, catalogID > 0 { return title.catalogID == catalogID }
            guard let titleName else { return false }
            return normalizedTitle(title.title) == normalizedTitle(titleName)
                && (year == nil || title.year == year)
        }
    }

    static func normalizedTitle(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func mergingTracking(from imported: MediaTitle, into catalog: MediaTitle) -> MediaTitle {
        var result = catalog
        result.state = imported.state
        result.progress = imported.progress
        result.userRating = imported.userRating
        result.notes = imported.notes
        result.rewatchCount = imported.rewatchCount
        result.lastWatchedAt = imported.lastWatchedAt
        result.isDismissed = imported.isDismissed
        result.isDisliked = imported.isDisliked
        result.personalWatchlist = imported.personalWatchlist
        if let watchedEpisodeIDs = imported.watchedEpisodeIDs {
            result.watchedEpisodeIDs = watchedEpisodeIDs
        }
        result.seriesLifecycle = imported.seriesLifecycle ?? catalog.seriesLifecycle
        result.isUpNextPinned = imported.isUpNextPinned
        result.upNextSnoozedUntil = imported.upNextSnoozedUntil
        result.upNextManualOrder = imported.upNextManualOrder
        return result
    }
}
