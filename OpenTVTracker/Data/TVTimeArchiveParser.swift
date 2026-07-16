import Foundation

enum TVTimeArchiveParser {
    static func parse(_ data: Data) throws -> TVTimeArchive {
        try parse(files: TVTimeZIPReader.recognizedFiles(in: data))
    }

    private static func parse(files: [String: Data]) throws -> TVTimeArchive {
        var entities: [String: TVTimeEntity] = [:]
        var duplicateCount = 0
        var diagnostics = TVTimeImportDiagnostics()

        for (path, data) in files.sorted(by: { filePriority($0.key) < filePriority($1.key) }) {
            guard let csv = String(data: data, encoding: .utf8) else {
                diagnostics.unreadableFileCount += 1
                continue
            }
            let rows = TVTimeCSV.rows(csv)
            guard let header = rows.first, !header.isEmpty else { continue }
            let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            for row in rows.dropFirst() where row.contains(where: { !$0.isEmpty }) {
                parseRecord(
                    filename,
                    values: TVTimeCSV.record(header: header, row: row),
                    entities: &entities,
                    duplicates: &duplicateCount,
                    diagnostics: &diagnostics
                )
            }
        }

        guard !entities.isEmpty else { throw TVTimeImportError.noSupportedData }
        return TVTimeArchive(
            entities: entities.values.sorted { $0.identity < $1.identity },
            duplicateCount: duplicateCount,
            diagnostics: diagnostics
        )
    }

    private static func parseRecord(
        _ filename: String,
        values: [String: String],
        entities: inout [String: TVTimeEntity],
        duplicates: inout Int,
        diagnostics: inout TVTimeImportDiagnostics
    ) {
        if filename == "tracking-prod-records-v2.csv" {
            parseEpisodeRecord(
                values,
                entities: &entities,
                duplicates: &duplicates,
                diagnostics: &diagnostics
            )
        } else if filename == "tracking-prod-records.csv" {
            parseLegacyRecord(
                values,
                entities: &entities,
                duplicates: &duplicates,
                diagnostics: &diagnostics
            )
        } else if filename.contains("tvtime-series-episodes") {
            TVTimeNativeRecordParser.parseEpisodeRecord(
                values,
                entities: &entities,
                duplicates: &duplicates,
                diagnostics: &diagnostics
            )
        } else if filename.contains("tvtime-movies-") {
            TVTimeNativeRecordParser.parseMovieRecord(
                values,
                entities: &entities,
                duplicates: &duplicates,
                diagnostics: &diagnostics
            )
        } else if filename == "followed_tv_show.csv" {
            parseFollowedShow(values, entities: &entities, diagnostics: &diagnostics)
        } else if filename.contains("tvtime-series-") {
            TVTimeNativeRecordParser.parseSeriesRecord(
                values,
                entities: &entities,
                diagnostics: &diagnostics
            )
        } else if filename == "tv_show_rate.csv" {
            parseShowRating(values, entities: &entities, diagnostics: &diagnostics)
        } else if filename == "ratings-live-votes.csv" {
            parseRatingVote(values, entities: &entities, diagnostics: &diagnostics)
        }
    }

    private static func filePriority(_ path: String) -> Int {
        let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        if filename.contains("rating") || filename == "tv_show_rate.csv" { return 2 }
        if filename == "followed_tv_show.csv" || filename.contains("tvtime-series-") { return 1 }
        return 0
    }
}

private extension TVTimeArchiveParser {
    private static func parseEpisodeRecord(
        _ values: [String: String],
        entities: inout [String: TVTimeEntity],
        duplicates: inout Int,
        diagnostics: inout TVTimeImportDiagnostics
    ) {
        let key = TVTimeCSV.string(values, ["key", "type"])?.lowercased() ?? ""
        let title = TVTimeCSV.string(values, ["series_name", "tv_show_name", "show_name", "name"])
        let sourceID = TVTimeCSV.string(values, ["s_id", "series_id", "tv_show_id"])
        guard let identity = identity(kind: .series, sourceID: sourceID, title: title) else {
            diagnostics.missingIdentityCount += 1
            return
        }
        let initial = TVTimeEntity(
            identity: identity,
            sourceID: sourceID,
            title: title ?? "",
            year: TVTimeCSV.int(values, ["year", "release_year"]),
            kind: .series
        )
        fillMetadata(
            sourceID: sourceID,
            title: title,
            values: values,
            entity: &entities[identity, default: initial]
        )
        fillFlags(values, entity: &entities[identity, default: initial])

        let season = TVTimeCSV.int(values, ["s_no", "season_number", "season"])
        let episode = TVTimeCSV.int(values, ["ep_no", "episode_number", "episode"])
        let isEpisodeWatch = season != nil && episode != nil
            && (key.contains("watch") || key.isEmpty)
            && !key.contains("unwatch")
        if isEpisodeWatch {
            addWatch(
                TVTimeWatch(
                    season: season,
                    episode: episode,
                    occurredAt: TVTimeCSV.date(values, ["watch_date_range_key", "watched_at", "created_at"]),
                    isRewatch: key.contains("rewatch")
                ),
                to: &entities[identity, default: initial],
                duplicates: &duplicates
            )
        }
    }

    private static func parseLegacyRecord(
        _ values: [String: String],
        entities: inout [String: TVTimeEntity],
        duplicates: inout Int,
        diagnostics: inout TVTimeImportDiagnostics
    ) {
        let type = TVTimeCSV.string(values, ["type", "key"])?.lowercased() ?? ""
        guard type == "watch" || type == "towatch" else {
            diagnostics.unsupportedRecordCount += 1
            return
        }
        let entityType = TVTimeCSV.string(values, ["entity_type", "kind"])?.lowercased() ?? ""
        let kind: MediaKind = entityType.contains("movie") || TVTimeCSV.string(values, ["movie_name"]) != nil
            ? .movie : .series
        let title = kind == .movie
            ? legacyMovieTitle(values, type: type)
            : TVTimeCSV.string(values, ["series_name", "title", "name"])
        let sourceID = TVTimeCSV.string(values, kind == .movie
            ? ["uuid", "movie_id", "entity_id", "id"]
            : ["s_id", "series_id", "tv_show_id"])
        guard let identity = identity(kind: kind, sourceID: sourceID, title: title) else {
            diagnostics.missingIdentityCount += 1
            return
        }
        let initial = TVTimeEntity(
            identity: identity,
            sourceID: sourceID,
            title: title ?? "",
            year: TVTimeCSV.year(values),
            kind: kind
        )
        fillMetadata(
            sourceID: sourceID,
            title: title,
            values: values,
            entity: &entities[identity, default: initial]
        )
        if type == "towatch" {
            entities[identity, default: initial].isForLater = true
        } else {
            addWatch(
                TVTimeWatch(
                    season: kind == .series ? TVTimeCSV.int(values, ["season_number", "season", "s_no"]) : nil,
                    episode: kind == .series ? TVTimeCSV.int(values, ["episode_number", "episode", "ep_no"]) : nil,
                    occurredAt: TVTimeCSV.date(values, ["watch_date_range_key", "watched_at", "created_at"]),
                    isRewatch: false
                ),
                to: &entities[identity, default: initial],
                duplicates: &duplicates
            )
        }
    }

    private static func parseFollowedShow(
        _ values: [String: String],
        entities: inout [String: TVTimeEntity],
        diagnostics: inout TVTimeImportDiagnostics
    ) {
        let title = TVTimeCSV.string(values, ["tv_show_name", "series_name", "name", "title"])
        let sourceID = TVTimeCSV.string(values, ["tv_show_id", "series_id", "s_id", "id"])
        guard let identity = identity(kind: .series, sourceID: sourceID, title: title) else {
            diagnostics.missingIdentityCount += 1
            return
        }
        let initial = TVTimeEntity(
            identity: identity,
            sourceID: sourceID,
            title: title ?? "",
            year: TVTimeCSV.year(values),
            kind: .series
        )
        fillMetadata(
            sourceID: sourceID,
            title: title,
            values: values,
            entity: &entities[identity, default: initial]
        )
        entities[identity, default: initial].isFollowed = true
        fillFlags(values, entity: &entities[identity, default: initial])
    }

    private static func parseShowRating(
        _ values: [String: String],
        entities: inout [String: TVTimeEntity],
        diagnostics: inout TVTimeImportDiagnostics
    ) {
        let title = TVTimeCSV.string(values, ["tv_show_name", "series_name", "name", "title"])
        let sourceID = TVTimeCSV.string(values, ["tv_show_id", "series_id", "s_id", "id"])
        guard let identity = identity(kind: .series, sourceID: sourceID, title: title) else {
            diagnostics.missingIdentityCount += 1
            return
        }
        let initial = TVTimeEntity(
            identity: identity,
            sourceID: sourceID,
            title: title ?? "",
            year: TVTimeCSV.year(values),
            kind: .series
        )
        fillMetadata(
            sourceID: sourceID,
            title: title,
            values: values,
            entity: &entities[identity, default: initial]
        )
        if let rating = TVTimeCSV.double(values, ["rate", "rating", "value"]) {
            entities[identity, default: initial].rating = min(max(rating * 2, 0), 10)
        } else {
            diagnostics.unsupportedRecordCount += 1
        }
    }

    private static func parseRatingVote(
        _ values: [String: String],
        entities: inout [String: TVTimeEntity],
        diagnostics: inout TVTimeImportDiagnostics
    ) {
        let scores = [1: 2.0, 27: 4.0, 28: 6.0, 29: 8.0, 3: 10.0]
        guard TVTimeCSV.int(values, ["episode_id"]) ?? 0 == 0 else {
            diagnostics.unsupportedEpisodeRatingCount += 1
            return
        }
        guard let uuid = TVTimeCSV.string(values, ["uuid"]),
              let vote = TVTimeCSV.string(values, ["vote_key"])?.split(separator: "-").last,
              let voteID = Int(vote), let rating = scores[voteID] else {
            diagnostics.unsupportedRecordCount += 1
            return
        }
        let identity = "\(MediaKind.movie.rawValue):source:\(uuid)"
        if entities[identity] != nil {
            entities[identity]?.rating = rating
        } else {
            diagnostics.unsupportedRecordCount += 1
        }
    }

    private static func legacyMovieTitle(_ values: [String: String], type: String) -> String? {
        if let alphaKey = TVTimeCSV.string(values, ["alpha_range_key"]) {
            let prefix = "\(type)-alpha-"
            let title = alphaKey.replacingOccurrences(of: prefix, with: "")
                .replacingOccurrences(of: "-", with: " ")
            if !title.isEmpty { return title }
        }
        return TVTimeCSV.string(values, ["movie_name", "title", "name"])
    }

    private static func addWatch(
        _ watch: TVTimeWatch,
        to entity: inout TVTimeEntity,
        duplicates: inout Int
    ) {
        if !entity.watchKeys.insert(watch).inserted {
            duplicates += 1
        } else {
            entity.watches.append(watch)
        }
    }

    private static func fillFlags(_ values: [String: String], entity: inout TVTimeEntity) {
        entity.isFollowed = TVTimeCSV.bool(values, ["is_followed", "followed"]) ?? entity.isFollowed
        entity.isForLater = TVTimeCSV.bool(values, ["is_for_later", "for_later"]) ?? entity.isForLater
        entity.isArchived = TVTimeCSV.bool(values, ["is_archived", "archived"]) ?? entity.isArchived
    }

    private static func fillMetadata(
        sourceID: String?,
        title: String?,
        values: [String: String],
        entity: inout TVTimeEntity
    ) {
        if entity.sourceID == nil { entity.sourceID = sourceID }
        if entity.title.isEmpty, let title { entity.title = title }
        if entity.year == nil { entity.year = TVTimeCSV.year(values) }
    }

    private static func identity(kind: MediaKind, sourceID: String?, title: String?) -> String? {
        if let sourceID, !sourceID.isEmpty { return "\(kind.rawValue):source:\(sourceID)" }
        guard let title, !title.isEmpty else { return nil }
        return "\(kind.rawValue):title:\(TVTimeCSV.normalizedTitle(title))"
    }
}
