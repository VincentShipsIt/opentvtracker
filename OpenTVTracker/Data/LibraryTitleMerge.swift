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

    static func mergingTracking(
        from imported: MediaTitle,
        into catalog: MediaTitle,
        fromSchemaVersion schemaVersion: Int?
    ) -> MediaTitle {
        let preservesMissingLegacyValues = (schemaVersion ?? 1) < LibraryArchiveEnvelope.currentSchemaVersion
        var result = catalog
        result.state = imported.state
        result.progress = preservesMissingLegacyValues ? imported.progress ?? catalog.progress : imported.progress
        result.userRating = preservesMissingLegacyValues ? imported.userRating ?? catalog.userRating : imported.userRating
        result.notes = preservesMissingLegacyValues ? imported.notes ?? catalog.notes : imported.notes
        result.rewatchCount = preservesMissingLegacyValues ? imported.rewatchCount ?? catalog.rewatchCount : imported.rewatchCount
        result.lastWatchedAt = preservesMissingLegacyValues ? imported.lastWatchedAt ?? catalog.lastWatchedAt : imported.lastWatchedAt
        result.isDismissed = preservesMissingLegacyValues ? imported.isDismissed ?? catalog.isDismissed : imported.isDismissed
        result.isDisliked = preservesMissingLegacyValues ? imported.isDisliked ?? catalog.isDisliked : imported.isDisliked
        result.personalWatchlist = preservesMissingLegacyValues ? imported.personalWatchlist ?? catalog.personalWatchlist : imported.personalWatchlist
        if let watchedEpisodeIDs = imported.watchedEpisodeIDs {
            result.watchedEpisodeIDs = watchedEpisodeIDs
        }
        result.seriesLifecycle = imported.seriesLifecycle ?? catalog.seriesLifecycle
        result.isUpNextPinned = preservesMissingLegacyValues ? imported.isUpNextPinned ?? catalog.isUpNextPinned : imported.isUpNextPinned
        result.upNextSnoozedUntil = preservesMissingLegacyValues ? imported.upNextSnoozedUntil ?? catalog.upNextSnoozedUntil : imported.upNextSnoozedUntil
        result.upNextManualOrder = preservesMissingLegacyValues ? imported.upNextManualOrder ?? catalog.upNextManualOrder : imported.upNextManualOrder
        return result
    }
}
