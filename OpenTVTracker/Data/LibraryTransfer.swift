import Foundation

enum LibraryTransferService {
    static func exportJSON(_ snapshot: LibrarySnapshot) throws -> Data {
        try LibraryArchiveCodec.encode(snapshot, prettyPrinted: true)
    }

    static func exportTitlesCSV(_ snapshot: LibrarySnapshot) -> Data {
        let header = [
            "catalog_id", "title", "year", "kind", "state", "personal_watchlist", "season", "episode",
            "total_episodes", "rating", "notes", "rewatches", "last_watched_at",
            "series_lifecycle", "is_up_next_pinned", "up_next_snoozed_until", "up_next_manual_order"
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

    static func previewImport(_ data: Data, into current: LibrarySnapshot) throws -> LibraryImportPreview {
        if LibraryBackupMerge.appearsToBeJSON(data) {
            do {
                return merge(imported: try LibraryArchiveCodec.decode(data), into: current)
            } catch let error as LibraryArchiveError {
                throw error
            } catch {
                throw LibraryTransferError.unreadableFile
            }
        }
        guard let csv = String(data: data, encoding: .utf8) else {
            throw LibraryTransferError.unreadableFile
        }
        let rows = parseCSV(csv)
        if let listPreview = previewListImport(rows, into: current) {
            return listPreview
        }
        if let header = rows.first?.map(normalizedHeaderName) {
            if header.contains("entry_id"), header.contains("scope") {
                return try mergeDiaryCSV(rows, into: current)
            }
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
        var importedTitleIDMap: [MediaTitle.ID: MediaTitle.ID] = [:]

        for sourceTitle in imported.titles {
            let importedTitle = sourceTitle.migratedTrackingState(
                fromSchemaVersion: imported.schemaVersion
            )
            let identity = identityKey(for: importedTitle)
            guard seen.insert(identity).inserted else {
                if let destination = merged.titles.first(where: { titlesMatch($0, importedTitle) }) {
                    importedTitleIDMap[importedTitle.id] = destination.id
                }
                duplicates += 1
                continue
            }

            if let index = merged.titles.firstIndex(where: { titlesMatch($0, importedTitle) }) {
                importedTitleIDMap[importedTitle.id] = merged.titles[index].id
                merged.titles[index] = mergingTracking(
                    from: importedTitle,
                    into: merged.titles[index],
                    fromSchemaVersion: imported.schemaVersion
                )
                matched += 1
            } else {
                importedTitleIDMap[importedTitle.id] = importedTitle.id
                merged.titles.append(importedTitle)
                added += 1
            }
        }

        mergeLibraryMetadata(imported: imported, current: current, into: &merged)
        mergeDiaryMetadata(
            imported: imported,
            current: current,
            titleIDMap: importedTitleIDMap,
            into: &merged
        )
        let listCounts = mergeLists(
            imported: imported,
            titleIDMap: importedTitleIDMap,
            into: &merged
        )

        return backupPreview(
            snapshot: merged,
            imported: imported,
            current: current,
            titleCounts: LibraryTitleImportCounts(
                matched: matched,
                added: added,
                duplicates: duplicates
            ),
            listCounts: listCounts
        )
    }

    private static func mergeDiaryMetadata(
        imported: LibrarySnapshot,
        current: LibrarySnapshot,
        titleIDMap: [MediaTitle.ID: MediaTitle.ID],
        into merged: inout LibrarySnapshot
    ) {
        guard imported.diaryEntries != nil || imported.sharedSpace.watchEvents?.isEmpty == false else {
            if current.titles.isEmpty, current.diaryEntries?.isEmpty != false {
                merged.diaryEntries = nil
            }
            return
        }
        let importedEntries = remappingDiaryEntries(
            ViewingDiaryMigration.resolvedEntries(from: imported),
            titleIDMap: titleIDMap,
            destinationTitles: merged.titles
        )
        merged.diaryEntries = mergedDiaryEntries(
            current: merged.diaryEntries ?? [],
            imported: importedEntries
        )
    }

    private static func mergeLibraryMetadata(
        imported: LibrarySnapshot,
        current: LibrarySnapshot,
        into merged: inout LibrarySnapshot
    ) {
        merged.selectedProviderIDs = imported.selectedProviderIDs ?? merged.selectedProviderIDs
        if let aliases = imported.importResolutionAliases {
            var mergedAliases = merged.importResolutionAliases ?? [:]
            mergedAliases.merge(aliases) { _, importedAlias in importedAlias }
            merged.importResolutionAliases = mergedAliases.filter { _, alias in
                merged.titles.contains {
                    $0.kind == alias.kind && $0.catalogID == alias.catalogID
                }
            }
        }
        merged.sharedSpace = LibraryBackupMerge.sharedSpace(
            imported: imported.sharedSpace,
            into: current.sharedSpace
        )
        merged.allowsAIReranking = imported.allowsAIReranking ?? merged.allowsAIReranking
        merged.streamingRegionCode = imported.streamingRegionCode ?? merged.streamingRegionCode
        merged.hasCompletedFirstRun = imported.hasCompletedFirstRun ?? merged.hasCompletedFirstRun
    }

    private static func mergeCSV(
        _ csv: String,
        into current: LibrarySnapshot
    ) throws -> LibraryImportPreview {
        let rows = parseCSV(csv)
        guard let header = rows.first, !header.isEmpty else { throw LibraryTransferError.emptyFile }
        let normalizedHeader = header.map(normalizedHeaderName)
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

    private static func applyCSVTracking(_ values: [String: String], title: inout MediaTitle) {
        if let stateValue = stringValue(in: values, keys: ["state", "status"]),
           let state = WatchState(rawValue: stateValue.lowercased()) {
            title.state = state == .caughtUp && title.kind != .series ? .completed : state
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
        if let lifecycle = stringValue(in: values, keys: ["series_lifecycle"]),
           let seriesLifecycle = SeriesLifecycle(rawValue: lifecycle.lowercased()) {
            title.seriesLifecycle = seriesLifecycle
        }
        if let pinned = boolValue(in: values, keys: ["is_up_next_pinned", "up_next_pinned"]) {
            title.isUpNextPinned = pinned ? true : nil
        }
        if let snoozedUntil = stringValue(in: values, keys: ["up_next_snoozed_until"]) {
            title.upNextSnoozedUntil = iso8601Date(snoozedUntil)
        }
        if let manualOrder = intValue(in: values, keys: ["up_next_manual_order"]) {
            title.upNextManualOrder = max(manualOrder, 0)
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

}

extension LibraryTransferService {
    private static func titleCSVRow(_ title: MediaTitle) -> [String] {
        let season = title.progress.map { String($0.season) } ?? ""
        let episode = title.progress.map { String($0.episode) } ?? ""
        let totalEpisodes = title.progress.map { String($0.totalEpisodes) } ?? ""
        let rating = title.userRating.map { String($0) } ?? ""
        let lastWatchedAt = title.lastWatchedAt.map(iso8601String) ?? ""
        let snoozedUntil = title.upNextSnoozedUntil.map(iso8601String) ?? ""

        return [
            String(title.catalogID), title.title, String(title.year), title.kind.rawValue,
            title.state.rawValue, String(title.isOnPersonalWatchlist), season, episode,
            totalEpisodes, rating, title.notes ?? "",
            String(title.completedRewatches), lastWatchedAt,
            title.seriesLifecycle?.rawValue ?? "",
            String(title.isUpNextPinned == true),
            snoozedUntil,
            title.upNextManualOrder.map(String.init) ?? ""
        ]
    }

    static func csvData(header: [String], rows: [[String]]) -> Data {
        ([header] + rows)
            .map { $0.map(escapedCSVField).joined(separator: ",") }
            .joined(separator: "\n")
            .appending("\n")
            .data(using: .utf8) ?? Data()
    }

    private static func escapedCSVField(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"")
                || field.contains("\n") || field.contains("\r") else {
            return field
        }
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

    static func normalizedHeaderName(_ header: String) -> String {
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

    static func doubleValue(in values: [String: String], keys: [String]) -> Double? {
        stringValue(in: values, keys: keys).flatMap(Double.init)
    }

    static func boolValue(in values: [String: String], keys: [String]) -> Bool? {
        guard let value = stringValue(in: values, keys: keys)?.lowercased() else { return nil }
        switch value {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }

    static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func iso8601Date(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

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
