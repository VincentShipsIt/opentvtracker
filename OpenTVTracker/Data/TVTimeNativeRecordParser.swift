import Foundation

enum TVTimeNativeRecordParser {
    static func parseEpisodeRecord(
        _ values: [String: String],
        entities: inout [String: TVTimeEntity],
        duplicates: inout Int,
        diagnostics: inout TVTimeImportDiagnostics
    ) {
        guard TVTimeCSV.bool(values, ["is_watched"]) == true else { return }
        let title = TVTimeCSV.string(values, ["title", "show_name", "series_name"])
        let sourceID = TVTimeCSV.string(values, ["series_tvdb_id", "series_id", "s_id"])
        guard let identity = identity(kind: .series, sourceID: sourceID, title: title) else {
            diagnostics.missingIdentityCount += 1
            return
        }
        let initial = TVTimeEntity(
            identity: identity,
            sourceID: sourceID,
            title: title ?? "",
            kind: .series
        )
        let rewatchCount = max(TVTimeCSV.int(values, ["rewatch_count"]) ?? 0, 0)
        addWatch(
            TVTimeWatch(
                season: TVTimeCSV.int(values, ["season", "episode_season_number", "season_number"]),
                episode: TVTimeCSV.int(values, ["episode", "episode_number"]),
                occurredAt: TVTimeCSV.date(values, ["watched_at", "ts", "created_at"]),
                rating: TVTimeCSV.double(values, ["episode_rating", "rating", "rate"]),
                isRewatch: rewatchCount > 0,
                rewatchCount: rewatchCount
            ),
            to: &entities[identity, default: initial],
            duplicates: &duplicates
        )
    }

    static func parseMovieRecord(
        _ values: [String: String],
        entities: inout [String: TVTimeEntity],
        duplicates: inout Int,
        diagnostics: inout TVTimeImportDiagnostics
    ) {
        let title = TVTimeCSV.string(values, ["title", "movie_name", "name"])
        let sourceID = TVTimeCSV.string(values, ["tvdb_id", "movie_id", "uuid"])
        guard let identity = identity(kind: .movie, sourceID: sourceID, title: title) else {
            diagnostics.missingIdentityCount += 1
            return
        }
        let initial = TVTimeEntity(
            identity: identity,
            sourceID: sourceID,
            title: title ?? "",
            year: TVTimeCSV.year(values),
            kind: .movie
        )
        if TVTimeCSV.bool(values, ["is_watched"]) == true {
            addWatch(
                TVTimeWatch(
                    occurredAt: TVTimeCSV.date(values, ["watched_at", "created_at"]),
                    rating: TVTimeCSV.double(values, ["rating", "rate"]),
                    isRewatch: false
                ),
                to: &entities[identity, default: initial],
                duplicates: &duplicates
            )
            let importedRewatchCount = TVTimeCSV.int(values, ["rewatch_count"]) ?? 0
            let existingRewatchCount = entities[identity, default: initial].rewatchCount
            entities[identity, default: initial].rewatchCount = max(
                existingRewatchCount,
                importedRewatchCount
            )
        } else {
            entities[identity, default: initial].isForLater = true
        }
    }

    static func parseSeriesRecord(
        _ values: [String: String],
        entities: inout [String: TVTimeEntity],
        diagnostics: inout TVTimeImportDiagnostics
    ) {
        let title = TVTimeCSV.string(values, ["title", "series_name", "name"])
        let sourceID = TVTimeCSV.string(values, ["tvdb_id", "series_tvdb_id", "series_id"])
        guard let identity = identity(kind: .series, sourceID: sourceID, title: title) else {
            diagnostics.missingIdentityCount += 1
            return
        }
        let initial = TVTimeEntity(
            identity: identity,
            sourceID: sourceID,
            title: title ?? "",
            kind: .series
        )
        switch TVTimeCSV.string(values, ["status"])?.lowercased() {
        case "not_started_yet": entities[identity, default: initial].isForLater = true
        case "stopped": entities[identity, default: initial].isArchived = true
        default: entities[identity, default: initial].isFollowed = true
        }
    }

    private static func addWatch(
        _ watch: TVTimeWatch,
        to entity: inout TVTimeEntity,
        duplicates: inout Int
    ) {
        if let index = entity.watches.firstIndex(where: { $0.hasSameIdentity(as: watch) }) {
            duplicates += 1
            if let rating = watch.rating {
                entity.watches[index].rating = rating
            }
        } else {
            entity.watches.append(watch)
        }
    }

    private static func identity(kind: MediaKind, sourceID: String?, title: String?) -> String? {
        if let sourceID, !sourceID.isEmpty { return "\(kind.rawValue):source:\(sourceID)" }
        guard let title, !title.isEmpty else { return nil }
        return "\(kind.rawValue):title:\(TVTimeCSV.normalizedTitle(title))"
    }
}
