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

struct LibraryTitleMatchIndex {
    private struct CatalogKey: Hashable {
        let catalogID: Int
        let kind: MediaKind?
        let metadataSource: MetadataSource?
    }

    private struct TitleKey: Hashable {
        let normalizedTitle: String
        let year: Int?
        let kind: MediaKind?
    }

    typealias TitleIndex = Array<MediaTitle>.Index

    private var indexByTitleID: [MediaTitle.ID: TitleIndex] = [:]
    private var catalogIndex: [CatalogKey: TitleIndex] = [:]
    private var titleIndex: [TitleKey: TitleIndex] = [:]

    init(titles: [MediaTitle]) {
        indexByTitleID.reserveCapacity(titles.count)
        catalogIndex.reserveCapacity(titles.count)
        titleIndex.reserveCapacity(titles.count)

        for index in titles.indices {
            let title = titles[index]
            if indexByTitleID[title.id] == nil {
                indexByTitleID[title.id] = index
            }

            if title.catalogID > 0 {
                let metadataSource = LibraryTransferService.resolvedMetadataSource(title)
                for key in [
                    CatalogKey(catalogID: title.catalogID, kind: nil, metadataSource: nil),
                    CatalogKey(catalogID: title.catalogID, kind: title.kind, metadataSource: nil),
                    CatalogKey(catalogID: title.catalogID, kind: nil, metadataSource: metadataSource),
                    CatalogKey(
                        catalogID: title.catalogID,
                        kind: title.kind,
                        metadataSource: metadataSource
                    )
                ] where catalogIndex[key] == nil {
                    catalogIndex[key] = index
                }
            }

            let normalizedTitle = LibraryTransferService.normalizedTitle(title.title)
            for key in [
                TitleKey(normalizedTitle: normalizedTitle, year: nil, kind: nil),
                TitleKey(normalizedTitle: normalizedTitle, year: title.year, kind: nil),
                TitleKey(normalizedTitle: normalizedTitle, year: nil, kind: title.kind),
                TitleKey(normalizedTitle: normalizedTitle, year: title.year, kind: title.kind)
            ] where titleIndex[key] == nil {
                titleIndex[key] = index
            }
        }
    }

    func matchingIndex(_ values: [String: String]) -> TitleIndex? {
        if let titleID = LibraryTransferService.stringValue(in: values, keys: ["title_id"]),
           let index = indexByTitleID[titleID] {
            return index
        }
        let catalogID = LibraryTransferService.intValue(
            in: values,
            keys: ["catalog_id", "tmdb_id", "id"]
        )
        let metadataSource = LibraryTransferService.stringValue(
            in: values,
            keys: ["metadata_source", "source"]
        ).flatMap(MetadataSource.init(csvValue:))
        let kind = LibraryTransferService.stringValue(
            in: values,
            keys: ["kind", "media_kind", "type"]
        ).flatMap(MediaKind.init(rawValue:))

        if let catalogID, catalogID > 0 {
            return catalogIndex[
                CatalogKey(
                    catalogID: catalogID,
                    kind: kind,
                    metadataSource: metadataSource
                )
            ]
        }
        guard let titleName = LibraryTransferService.stringValue(
            in: values,
            keys: ["title", "name", "series_name", "movie_name"]
        ) else {
            return nil
        }
        let year = LibraryTransferService.intValue(in: values, keys: ["year", "release_year"])
        return titleIndex[
            TitleKey(
                normalizedTitle: LibraryTransferService.normalizedTitle(titleName),
                year: year,
                kind: kind
            )
        ]
    }
}
