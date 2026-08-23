import Foundation

extension LibraryTransferService {
    static func titlesMatch(_ lhs: MediaTitle, _ rhs: MediaTitle) -> Bool {
        if lhs.catalogID > 0, rhs.catalogID > 0 {
            return lhs.catalogID == rhs.catalogID
                && lhs.kind == rhs.kind
                && resolvedMetadataSource(lhs) == resolvedMetadataSource(rhs)
        }
        return normalizedTitle(lhs.title) == normalizedTitle(rhs.title)
            && lhs.year == rhs.year
            && lhs.kind == rhs.kind
    }

    static func identityKey(for title: MediaTitle) -> String {
        if title.catalogID > 0 {
            return "catalog:\(resolvedMetadataSource(title).rawValue):\(title.kind.rawValue):\(title.catalogID)"
        }
        return titleIdentityKey(for: title)
    }

    static func titleIdentityKey(for title: MediaTitle) -> String {
        "title:\(title.kind.rawValue):\(normalizedTitle(title.title)):\(title.year)"
    }

    static func resolvedMetadataSource(_ title: MediaTitle) -> MetadataSource {
        title.metadataSource ?? .tmdb
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
        let metadataSource = stringValue(in: values, keys: ["metadata_source", "source"])
            .flatMap(MetadataSource.init(csvValue:))
        let titleName = stringValue(in: values, keys: ["title", "name", "series_name", "movie_name"])
        let year = intValue(in: values, keys: ["year", "release_year"])
        let kind = stringValue(in: values, keys: ["kind", "media_kind", "type"])
            .flatMap(MediaKind.init(rawValue:))

        return titles.firstIndex { title in
            if let catalogID, catalogID > 0 {
                return title.catalogID == catalogID
                    && (kind == nil || title.kind == kind)
                    && (metadataSource == nil || resolvedMetadataSource(title) == metadataSource)
            }
            guard let titleName else { return false }
            return normalizedTitle(title.title) == normalizedTitle(titleName)
                && (year == nil || title.year == year)
                && (kind == nil || title.kind == kind)
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
