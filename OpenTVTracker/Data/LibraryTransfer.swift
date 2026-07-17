import Foundation

enum LibraryTransferService {
    static func exportJSON(_ snapshot: LibrarySnapshot) throws -> Data {
        try LibraryArchiveCodec.encode(snapshot, prettyPrinted: true)
    }

    static func exportTitlesCSV(_ snapshot: LibrarySnapshot) -> Data {
        let header = [
            "catalog_id", "title", "year", "kind", "state", "personal_watchlist", "season", "episode",
            "total_episodes", "rating", "notes", "rewatches", "last_watched_at"
        ]
        let rows = snapshot.titles.map(titleCSVRow)
        return csvData(header: header, rows: rows)
    }

    static func exportWatchEventsCSV(_ snapshot: LibrarySnapshot) -> Data {
        let header = [
            "event_id", "title_id", "member_id", "kind", "season", "episode",
            "occurred_at", "supersedes_event_id"
        ]
        let rows = (snapshot.sharedSpace.watchEvents ?? []).map { event in
            [
                event.id,
                event.titleID,
                event.memberID,
                event.kind.rawValue,
                event.season.map { String($0) } ?? "",
                event.episode.map { String($0) } ?? "",
                iso8601String(event.occurredAt),
                event.supersedesEventID ?? ""
            ]
        }
        return csvData(header: header, rows: rows)
    }

    static func exportListsCSV(_ snapshot: LibrarySnapshot) -> Data {
        LibraryListTransferService.exportCSV(snapshot)
    }

    static func previewImport(_ data: Data, into current: LibrarySnapshot) throws -> LibraryImportPreview {
        if let imported = try? LibraryArchiveCodec.decode(data) {
            return merge(imported: imported, into: current)
        }
        guard let csv = String(data: data, encoding: .utf8) else {
            throw LibraryTransferError.unreadableFile
        }
        return try mergeCSV(csv, into: current)
    }
}

extension LibraryTransferService {
    private static func merge(
        imported: LibrarySnapshot,
        into current: LibrarySnapshot
    ) -> LibraryImportPreview {
        var merged = current
        var matched = 0
        var added = 0
        var duplicates = 0
        var seen = Set<String>()
        var importedTitleIDs: [MediaTitle.ID: MediaTitle.ID] = [:]

        for importedTitle in imported.titles {
            let identity = identityKey(for: importedTitle)
            guard seen.insert(identity).inserted else {
                duplicates += 1
                if let existing = merged.titles.first(where: { titlesMatch($0, importedTitle) }) {
                    importedTitleIDs[importedTitle.id] = existing.id
                }
                continue
            }

            if let index = merged.titles.firstIndex(where: { titlesMatch($0, importedTitle) }) {
                merged.titles[index] = mergingTracking(from: importedTitle, into: merged.titles[index])
                importedTitleIDs[importedTitle.id] = merged.titles[index].id
                matched += 1
            } else {
                merged.titles.append(importedTitle)
                importedTitleIDs[importedTitle.id] = importedTitle.id
                added += 1
            }
        }

        if let selectedProviderIDs = imported.selectedProviderIDs {
            merged.selectedProviderIDs = selectedProviderIDs
        }
        let availableTitleIDs = Set(merged.titles.map(\.id))
        let importedLists = (imported.lists ?? []).map { list in
            var remapped = list
            remapped.titleIDs = list.titleIDs.compactMap {
                importedTitleIDs[$0] ?? (availableTitleIDs.contains($0) ? $0 : nil)
            }
            return remapped
        }
        merged.lists = mergingLists(importedLists, into: merged.lists ?? [])

        return LibraryImportPreview(
            snapshot: merged,
            matchedCount: matched,
            addedCount: added,
            duplicateCount: duplicates,
            skippedCount: 0,
            listCount: importedLists.count,
            listMembershipCount: importedLists.reduce(0) { $0 + $1.titleIDs.count }
        )
    }

    private static func mergeCSV(
        _ csv: String,
        into current: LibrarySnapshot
    ) throws -> LibraryImportPreview {
        let rows = parseCSV(csv)
        guard let header = rows.first, !header.isEmpty else { throw LibraryTransferError.emptyFile }
        let normalizedHeader = header.map(normalizedHeaderName)
        if normalizedHeader.contains("list_name") {
            return LibraryListTransferService.mergeCSV(
                rows.dropFirst(),
                header: normalizedHeader,
                into: current
            )
        }
        var merged = current
        var matched = 0
        var duplicates = 0
        var skipped = 0
        var seen = Set<MediaTitle.ID>()

        for row in rows.dropFirst() where row.contains(where: { !$0.isEmpty }) {
            let values = csvValues(header: normalizedHeader, row: row)
            switch applyCSVRow(values, titles: &merged.titles, seen: &seen) {
            case .matched: matched += 1
            case .duplicate: duplicates += 1
            case .skipped: skipped += 1
            }
        }

        return LibraryImportPreview(
            snapshot: merged,
            matchedCount: matched,
            addedCount: 0,
            duplicateCount: duplicates,
            skippedCount: skipped
        )
    }

    static func csvValues(header: [String], row: [String]) -> [String: String] {
        let paddedRow = row + Array(repeating: "", count: max(0, header.count - row.count))
        return zip(header, paddedRow).reduce(into: [String: String]()) { result, pair in
            result[pair.0] = pair.1
        }
    }

    private static func applyCSVRow(
        _ values: [String: String],
        titles: inout [MediaTitle],
        seen: inout Set<MediaTitle.ID>
    ) -> CSVRowResult {
        guard let index = matchingTitleIndex(values, titles: titles) else { return .skipped }
        guard seen.insert(titles[index].id).inserted else { return .duplicate }
        applyCSVTracking(values, title: &titles[index])
        applyCSVProgress(values, title: &titles[index])
        return .matched
    }

    static func matchingTitleIndex(
        _ values: [String: String],
        titles: [MediaTitle]
    ) -> Array<MediaTitle>.Index? {
        if let titleID = stringValue(in: values, keys: ["title_id"]),
           let index = titles.firstIndex(where: { $0.id == titleID }) { return index }
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

    private static func applyCSVTracking(_ values: [String: String], title: inout MediaTitle) {
        if let stateValue = stringValue(in: values, keys: ["state", "status"]),
           let state = WatchState(rawValue: stateValue.lowercased()) {
            title.state = state
        }
        if let watchlist = boolValue(
            in: values,
            keys: ["personal_watchlist", "watchlist", "in_watchlist"]
        ) {
            title.personalWatchlist = watchlist
        }
        if let rating = doubleValue(in: values, keys: ["rating", "user_rating"]) {
            title.userRating = min(max(rating, 0), 10)
        }
        if let notes = stringValue(in: values, keys: ["notes", "comment"]), !notes.isEmpty {
            title.notes = notes
        }
        if let rewatches = intValue(in: values, keys: ["rewatches", "rewatch_count"]) {
            title.rewatchCount = max(rewatches, 0)
        }
        if let watchedAt = stringValue(in: values, keys: ["last_watched_at", "watched_at"]) {
            title.lastWatchedAt = iso8601Date(watchedAt)
        }
    }

    private static func applyCSVProgress(_ values: [String: String], title: inout MediaTitle) {
        let season = intValue(in: values, keys: ["season", "season_number"])
        let episode = intValue(in: values, keys: ["episode", "episode_number"])
        let totalEpisodes = intValue(in: values, keys: ["total_episodes", "episode_count"])
        guard let season, let episode else { return }
        title.progress = EpisodeProgress(
            season: max(season, 1),
            episode: max(episode, 0),
            totalEpisodes: max(totalEpisodes ?? episode, 1)
        )
    }

    private static func mergingTracking(from imported: MediaTitle, into catalog: MediaTitle) -> MediaTitle {
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
        return result
    }

    static func mergingLists(
        _ imported: [MediaList],
        into current: [MediaList],
        preservingExistingIDs: Set<MediaList.ID> = []
    ) -> [MediaList] {
        var merged = current
        for importedList in imported {
            if let index = merged.firstIndex(where: { $0.id == importedList.id }) {
                if preservingExistingIDs.contains(importedList.id) {
                    let existingIDs = Set(merged[index].titleIDs)
                    merged[index].titleIDs.append(contentsOf: importedList.titleIDs.filter { !existingIDs.contains($0) })
                    merged[index].updatedAt = .now
                } else {
                    merged[index] = mergingList(importedList, into: merged[index])
                }
            } else {
                merged.append(importedList)
            }
        }
        return merged
    }
    private static func mergingList(_ imported: MediaList, into current: MediaList) -> MediaList {
        if imported.updatedAt > current.updatedAt {
            var merged = imported
            let importedIDs = Set(imported.titleIDs)
            merged.titleIDs.append(contentsOf: current.titleIDs.filter { !importedIDs.contains($0) })
            return merged
        }
        var merged = current
        let currentIDs = Set(current.titleIDs)
        merged.titleIDs.append(contentsOf: imported.titleIDs.filter { !currentIDs.contains($0) })
        return merged
    }
}
extension LibraryTransferService {
    private static func titleCSVRow(_ title: MediaTitle) -> [String] {
        let season = title.progress.map { String($0.season) } ?? ""
        let episode = title.progress.map { String($0.episode) } ?? ""
        let totalEpisodes = title.progress.map { String($0.totalEpisodes) } ?? ""
        let rating = title.userRating.map { String($0) } ?? ""
        let lastWatchedAt = title.lastWatchedAt.map(iso8601String) ?? ""

        return [
            String(title.catalogID), title.title, String(title.year), title.kind.rawValue,
            title.state.rawValue, String(title.isOnPersonalWatchlist), season, episode,
            totalEpisodes, rating, title.notes ?? "",
            String(title.completedRewatches), lastWatchedAt
        ]
    }

    private static func titlesMatch(_ lhs: MediaTitle, _ rhs: MediaTitle) -> Bool {
        if lhs.catalogID > 0, rhs.catalogID > 0 { return lhs.catalogID == rhs.catalogID }
        return normalizedTitle(lhs.title) == normalizedTitle(rhs.title) && lhs.year == rhs.year
    }

    private static func identityKey(for title: MediaTitle) -> String {
        title.catalogID > 0 ? "catalog:\(title.catalogID)" : "title:\(normalizedTitle(title.title)):\(title.year)"
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func csvData(header: [String], rows: [[String]]) -> Data {
        ([header] + rows)
            .map { $0.map(escapedCSVField).joined(separator: ",") }
            .joined(separator: "\n")
            .appending("\n")
            .data(using: .utf8) ?? Data()
    }

    private static func escapedCSVField(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func parseCSV(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = csv.startIndex

        while index < csv.endIndex {
            let character = csv[index]
            if character == "\"" {
                let next = csv.index(after: index)
                if isQuoted, next < csv.endIndex, csv[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    isQuoted.toggle()
                }
            } else if character == ",", !isQuoted {
                row.append(field)
                field = ""
            } else if character == "\n", !isQuoted {
                row.append(field.trimmingCharacters(in: .newlines))
                rows.append(row)
                row = []
                field = ""
            } else if character != "\r" || isQuoted {
                field.append(character)
            }
            index = csv.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static func normalizedHeaderName(_ header: String) -> String {
        header.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }

    static func stringValue(in values: [String: String], keys: [String]) -> String? {
        keys.lazy.compactMap { values[$0] }.first { !$0.isEmpty }
    }

    static func intValue(in values: [String: String], keys: [String]) -> Int? {
        stringValue(in: values, keys: keys).flatMap(Int.init)
    }

    private static func doubleValue(in values: [String: String], keys: [String]) -> Double? {
        stringValue(in: values, keys: keys).flatMap(Double.init)
    }

    private static func boolValue(in values: [String: String], keys: [String]) -> Bool? {
        guard let value = stringValue(in: values, keys: keys)?.lowercased() else { return nil }
        switch value {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }

    private static func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func iso8601Date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}
private enum CSVRowResult {
    case matched
    case duplicate
    case skipped
}
enum LibraryTransferError: LocalizedError {
    case emptyFile
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .emptyFile: "The selected import file is empty."
        case .unreadableFile: "OpenTV could not read this JSON or CSV file."
        }
    }
}
