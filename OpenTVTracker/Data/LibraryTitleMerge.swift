import Foundation

extension LibraryTransferService {
    static func titlesMatch(_ lhs: MediaTitle, _ rhs: MediaTitle) -> Bool {
        if lhs.catalogID > 0, rhs.catalogID > 0 { return lhs.catalogID == rhs.catalogID }
        return normalizedTitle(lhs.title) == normalizedTitle(rhs.title) && lhs.year == rhs.year
    }

    static func identityKey(for title: MediaTitle) -> String {
        title.catalogID > 0 ? "catalog:\(title.catalogID)" : "title:\(normalizedTitle(title.title)):\(title.year)"
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
