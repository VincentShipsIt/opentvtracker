import Foundation

enum TVTimeNativeRecordParser {
    static func parseEpisodeRecords(
        _ records: [[String: String]],
        entities: inout [String: TVTimeEntity],
        duplicates: inout Int
    ) {
        for values in records where TVTimeCSV.bool(values, ["is_watched"]) == true {
            let title = TVTimeCSV.string(values, ["title", "show_name", "series_name"])
            let sourceID = TVTimeCSV.string(values, ["series_tvdb_id", "series_id", "s_id"])
            guard let identity = identity(kind: .series, sourceID: sourceID, title: title) else { continue }
            var entity = entities[identity] ?? TVTimeEntity(
                identity: identity,
                sourceID: sourceID,
                title: title ?? "",
                kind: .series
            )
            addWatch(
                TVTimeWatch(
                    season: TVTimeCSV.int(values, ["season", "episode_season_number", "season_number"]),
                    episode: TVTimeCSV.int(values, ["episode", "episode_number"]),
                    occurredAt: TVTimeCSV.date(values, ["watched_at", "ts", "created_at"]),
                    rating: TVTimeCSV.double(values, ["episode_rating", "rating", "rate"]),
                    isRewatch: (TVTimeCSV.int(values, ["rewatch_count"]) ?? 0) > 0
                ),
                to: &entity,
                duplicates: &duplicates
            )
            entities[identity] = entity
        }
    }

    static func parseMovies(
        _ records: [[String: String]],
        entities: inout [String: TVTimeEntity],
        duplicates: inout Int
    ) {
        for values in records {
            let title = TVTimeCSV.string(values, ["title", "movie_name", "name"])
            let sourceID = TVTimeCSV.string(values, ["tvdb_id", "movie_id", "uuid"])
            guard let identity = identity(kind: .movie, sourceID: sourceID, title: title) else { continue }
            var entity = entities[identity] ?? TVTimeEntity(
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
                    to: &entity,
                    duplicates: &duplicates
                )
                entity.rewatchCount = max(
                    entity.rewatchCount,
                    TVTimeCSV.int(values, ["rewatch_count"]) ?? 0
                )
            } else {
                entity.isForLater = true
            }
            entities[identity] = entity
        }
    }

    static func parseSeries(
        _ records: [[String: String]],
        entities: inout [String: TVTimeEntity]
    ) {
        for values in records {
            let title = TVTimeCSV.string(values, ["title", "series_name", "name"])
            let sourceID = TVTimeCSV.string(values, ["tvdb_id", "series_tvdb_id", "series_id"])
            guard let identity = identity(kind: .series, sourceID: sourceID, title: title) else { continue }
            var entity = entities[identity] ?? TVTimeEntity(
                identity: identity,
                sourceID: sourceID,
                title: title ?? "",
                kind: .series
            )
            switch TVTimeCSV.string(values, ["status"])?.lowercased() {
            case "not_started_yet": entity.isForLater = true
            case "stopped": entity.isArchived = true
            default: entity.isFollowed = true
            }
            entities[identity] = entity
        }
    }

    private static func addWatch(
        _ watch: TVTimeWatch,
        to entity: inout TVTimeEntity,
        duplicates: inout Int
    ) {
        if entity.watches.contains(watch) {
            duplicates += 1
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
