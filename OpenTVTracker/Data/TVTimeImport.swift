import Foundation

enum TVTimeImportService {
    static func isZIPArchive(_ data: Data) -> Bool {
        data.count >= 4 && data.prefix(2) == Data([0x50, 0x4B])
    }

    static func previewImport(
        _ data: Data,
        into current: LibrarySnapshot,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async throws -> LibraryImportPreview {
        let tvTimeArchive = try await Task.detached(priority: .userInitiated) {
            try TVTimeArchiveParser.parse(data)
        }.value

        return await TVTimeImportMerger.merge(
            tvTimeArchive,
            into: current,
            catalog: catalog,
            region: region
        )
    }
}

struct TVTimeArchive: Sendable {
    var entities: [TVTimeEntity]
    var duplicateCount: Int
}

struct TVTimeEntity: Sendable {
    let identity: String
    var sourceID: String?
    var title: String
    var year: Int?
    var kind: MediaKind
    var isFollowed = false
    var isForLater = false
    var isArchived = false
    var rating: Double?
    var rewatchCount = 0
    var watches: [TVTimeWatch] = []
}

struct TVTimeWatch: Hashable, Sendable {
    var season: Int?
    var episode: Int?
    var occurredAt: Date?
    var isRewatch: Bool
}

private enum TVTimeArchiveParser {
    static func parse(_ data: Data) throws -> TVTimeArchive {
        try parse(files: TVTimeZIPReader.recognizedFiles(in: data))
    }

    private static func parse(files: [String: Data]) throws -> TVTimeArchive {
        var entities: [String: TVTimeEntity] = [:]
        var duplicateCount = 0

        for (path, data) in files.sorted(by: { filePriority($0.key) < filePriority($1.key) }) {
            guard let csv = String(data: data, encoding: .utf8) else { continue }
            let rows = TVTimeCSV.rows(csv)
            guard let header = rows.first, !header.isEmpty else { continue }
            let records = rows.dropFirst().map { TVTimeCSV.record(header: header, row: $0) }
            let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            parseFile(
                filename,
                records: records,
                entities: &entities,
                duplicates: &duplicateCount
            )
        }

        guard !entities.isEmpty else { throw TVTimeImportError.noSupportedData }
        return TVTimeArchive(
            entities: entities.values.sorted { $0.identity < $1.identity },
            duplicateCount: duplicateCount
        )
    }

    private static func parseFile(
        _ filename: String,
        records: [[String: String]],
        entities: inout [String: TVTimeEntity],
        duplicates: inout Int
    ) {
        if filename == "tracking-prod-records-v2.csv" {
            parseEpisodeRecords(records, entities: &entities, duplicates: &duplicates)
        } else if filename == "tracking-prod-records.csv" {
            parseLegacyRecords(records, entities: &entities, duplicates: &duplicates)
        } else if filename.contains("tvtime-series-episodes") {
            TVTimeNativeRecordParser.parseEpisodeRecords(
                records,
                entities: &entities,
                duplicates: &duplicates
            )
        } else if filename.contains("tvtime-movies-") {
            TVTimeNativeRecordParser.parseMovies(records, entities: &entities, duplicates: &duplicates)
        } else if filename == "followed_tv_show.csv" {
            parseFollowedShows(records, entities: &entities)
        } else if filename.contains("tvtime-series-") {
            TVTimeNativeRecordParser.parseSeries(records, entities: &entities)
        } else if filename == "tv_show_rate.csv" {
            parseShowRatings(records, entities: &entities)
        } else if filename == "ratings-live-votes.csv" {
            parseRatingVotes(records, entities: &entities)
        }
    }

    private static func filePriority(_ path: String) -> Int {
        let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        if filename.contains("rating") || filename == "tv_show_rate.csv" { return 2 }
        if filename == "followed_tv_show.csv" || filename.contains("tvtime-series-") { return 1 }
        return 0
    }

    private static func parseEpisodeRecords(
        _ records: [[String: String]],
        entities: inout [String: TVTimeEntity],
        duplicates: inout Int
    ) {
        for values in records {
            let key = TVTimeCSV.string(values, ["key", "type"])?.lowercased() ?? ""
            let title = TVTimeCSV.string(values, ["series_name", "tv_show_name", "show_name", "name"])
            let sourceID = TVTimeCSV.string(values, ["s_id", "series_id", "tv_show_id"])
            guard let identity = identity(kind: .series, sourceID: sourceID, title: title) else { continue }
            var entity = entities[identity] ?? TVTimeEntity(
                identity: identity,
                sourceID: sourceID,
                title: title ?? "",
                year: TVTimeCSV.int(values, ["year", "release_year"]),
                kind: .series
            )
            fillMetadata(sourceID: sourceID, title: title, values: values, entity: &entity)
            fillFlags(values, entity: &entity)

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
                    to: &entity,
                    duplicates: &duplicates
                )
            }
            entities[identity] = entity
        }
    }

    private static func parseLegacyRecords(
        _ records: [[String: String]],
        entities: inout [String: TVTimeEntity],
        duplicates: inout Int
    ) {
        for values in records {
            let type = TVTimeCSV.string(values, ["type", "key"])?.lowercased() ?? ""
            guard type == "watch" || type == "towatch" else { continue }
            let entityType = TVTimeCSV.string(values, ["entity_type", "kind"])?.lowercased() ?? ""
            let kind: MediaKind = entityType.contains("movie") || TVTimeCSV.string(values, ["movie_name"]) != nil
                ? .movie : .series
            let title = kind == .movie
                ? legacyMovieTitle(values, type: type)
                : TVTimeCSV.string(values, ["series_name", "title", "name"])
            let sourceID = TVTimeCSV.string(values, kind == .movie
                ? ["uuid", "movie_id", "entity_id", "id"]
                : ["s_id", "series_id", "tv_show_id"])
            guard let identity = identity(kind: kind, sourceID: sourceID, title: title) else { continue }
            var entity = entities[identity] ?? TVTimeEntity(
                identity: identity,
                sourceID: sourceID,
                title: title ?? "",
                year: TVTimeCSV.year(values),
                kind: kind
            )
            fillMetadata(sourceID: sourceID, title: title, values: values, entity: &entity)
            if type == "towatch" {
                entity.isForLater = true
            } else {
                addWatch(
                    TVTimeWatch(
                        season: kind == .series ? TVTimeCSV.int(values, ["season_number", "season", "s_no"]) : nil,
                        episode: kind == .series ? TVTimeCSV.int(values, ["episode_number", "episode", "ep_no"]) : nil,
                        occurredAt: TVTimeCSV.date(values, ["watch_date_range_key", "watched_at", "created_at"]),
                        isRewatch: false
                    ),
                    to: &entity,
                    duplicates: &duplicates
                )
            }
            entities[identity] = entity
        }
    }

    private static func parseFollowedShows(
        _ records: [[String: String]],
        entities: inout [String: TVTimeEntity]
    ) {
        for values in records {
            let title = TVTimeCSV.string(values, ["tv_show_name", "series_name", "name", "title"])
            let sourceID = TVTimeCSV.string(values, ["tv_show_id", "series_id", "s_id", "id"])
            guard let identity = identity(kind: .series, sourceID: sourceID, title: title) else { continue }
            var entity = entities[identity] ?? TVTimeEntity(
                identity: identity,
                sourceID: sourceID,
                title: title ?? "",
                year: TVTimeCSV.year(values),
                kind: .series
            )
            fillMetadata(sourceID: sourceID, title: title, values: values, entity: &entity)
            entity.isFollowed = true
            fillFlags(values, entity: &entity)
            entities[identity] = entity
        }
    }

    private static func parseShowRatings(
        _ records: [[String: String]],
        entities: inout [String: TVTimeEntity]
    ) {
        for values in records {
            let title = TVTimeCSV.string(values, ["tv_show_name", "series_name", "name", "title"])
            let sourceID = TVTimeCSV.string(values, ["tv_show_id", "series_id", "s_id", "id"])
            guard let identity = identity(kind: .series, sourceID: sourceID, title: title) else { continue }
            var entity = entities[identity] ?? TVTimeEntity(
                identity: identity,
                sourceID: sourceID,
                title: title ?? "",
                year: TVTimeCSV.year(values),
                kind: .series
            )
            fillMetadata(sourceID: sourceID, title: title, values: values, entity: &entity)
            if let rating = TVTimeCSV.double(values, ["rate", "rating", "value"]) {
                entity.rating = min(max(rating * 2, 0), 10)
            }
            entities[identity] = entity
        }
    }

    private static func parseRatingVotes(
        _ records: [[String: String]],
        entities: inout [String: TVTimeEntity]
    ) {
        let scores = [1: 2.0, 27: 4.0, 28: 6.0, 29: 8.0, 3: 10.0]
        for values in records {
            guard TVTimeCSV.int(values, ["episode_id"]) ?? 0 == 0,
                  let uuid = TVTimeCSV.string(values, ["uuid"]),
                  let vote = TVTimeCSV.string(values, ["vote_key"])?.split(separator: "-").last,
                  let voteID = Int(vote), let rating = scores[voteID] else { continue }
            let identity = "\(MediaKind.movie.rawValue):source:\(uuid)"
            if var entity = entities[identity] {
                entity.rating = rating
                entities[identity] = entity
            }
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
        if entity.watches.contains(watch) {
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

enum TVTimeImportError: LocalizedError {
    case emptyArchive
    case invalidArchive
    case archiveTooLarge
    case noSupportedData

    var errorDescription: String? {
        switch self {
        case .emptyArchive: "The TV Time export ZIP is empty."
        case .invalidArchive: "OpenTV could not read this TV Time export ZIP."
        case .archiveTooLarge: "This archive is too large to import safely."
        case .noSupportedData: "This ZIP does not contain recognizable TV Time tracking data."
        }
    }
}
