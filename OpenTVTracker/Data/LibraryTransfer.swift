import Foundation

enum LibraryTransferService {
    static func exportJSON(_ snapshot: LibrarySnapshot) throws -> Data {
        try LibraryArchiveCodec.encode(snapshot, prettyPrinted: true)
    }

    static func exportTitlesCSV(_ snapshot: LibrarySnapshot) -> Data {
        let header = [
            "catalog_id", "title", "year", "kind", "state", "personal_watchlist", "season", "episode",
            "total_episodes", "rating", "notes", "rewatches", "last_watched_at",
            "series_lifecycle", "is_up_next_pinned", "up_next_snoozed_until", "up_next_manual_order",
            "metadata_source"
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
        guard data.count <= LibraryImportLimits.maximumLibraryFileSize else {
            throw LibraryImportSafetyError.fileTooLarge
        }
        if LibraryBackupMerge.appearsToBeJSON(data) {
            try LibraryJSONImportValidator.validateEncodedFields(in: data)
            let imported: LibrarySnapshot
            do {
                imported = try LibraryArchiveCodec.decode(data)
            } catch let error as LibraryArchiveError {
                throw error
            } catch {
                throw LibraryTransferError.unreadableFile
            }
            try LibraryJSONImportValidator.validateCollections(in: imported)
            return LibraryBackupMerge.merge(
                imported: ImportedLibraryMetadataSanitizer.sanitized(imported),
                into: current
            )
        }
        guard let csv = String(data: data, encoding: .utf8) else {
            throw LibraryTransferError.unreadableFile
        }
        let rows = try BoundedCSVParser.rows(csv)
        if let listPreview = previewListImport(rows, into: current) {
            return listPreview
        }
        if let header = rows.first?.map(normalizedHeaderName) {
            if header.contains("entry_id"), header.contains("scope") {
                return try mergeDiaryCSV(rows, into: current)
            }
        }
        return try mergeCSV(rows, into: current)
    }
}

extension LibraryTransferService {
    private static func mergeCSV(
        _ rows: [[String]],
        into current: LibrarySnapshot
    ) throws -> LibraryImportPreview {
        guard let header = rows.first, !header.isEmpty else { throw LibraryTransferError.emptyFile }
        let normalizedHeader = header.map(normalizedHeaderName)
        var merged = current
        var matched = 0
        var duplicates = 0
        var skipped = 0
        var seen = Set<MediaTitle.ID>()
        let titleMatchIndex = LibraryTitleMatchIndex(titles: current.titles)

        for row in rows.dropFirst() where row.contains(where: { !$0.isEmpty }) {
            let values = csvValues(header: normalizedHeader, row: row)
            switch applyCSVRow(
                values,
                titles: &merged.titles,
                titleMatchIndex: titleMatchIndex,
                seen: &seen
            ) {
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
        titleMatchIndex: LibraryTitleMatchIndex,
        seen: inout Set<MediaTitle.ID>
    ) -> CSVRowResult {
        guard let index = titleMatchIndex.matchingIndex(values) else { return .skipped }
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
            title.rewatchCount = LibraryImportLimits.boundedRewatchCount(rewatches)
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
            title.upNextManualOrder = LibraryImportLimits.boundedOrderingValue(manualOrder)
        }
    }

    private static func applyCSVProgress(_ values: [String: String], title: inout MediaTitle) {
        let season = intValue(in: values, keys: ["season", "season_number"])
        let episode = intValue(in: values, keys: ["episode", "episode_number"])
        let totalEpisodes = intValue(in: values, keys: ["total_episodes", "episode_count"])
        guard let season, let episode else { return }
        let boundedEpisode = LibraryImportLimits.boundedProgressValue(episode)
        let boundedTotal = max(
            LibraryImportLimits.boundedProgressValue(totalEpisodes ?? episode),
            1
        )
        title.progress = EpisodeProgress(
            season: max(LibraryImportLimits.boundedProgressValue(season), 1),
            episode: min(boundedEpisode, boundedTotal),
            totalEpisodes: boundedTotal
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
            title.upNextManualOrder.map(String.init) ?? "",
            resolvedMetadataSource(title).rawValue
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
        guard let value = stringValue(in: values, keys: keys).flatMap(Double.init),
              value.isFinite else {
            return nil
        }
        return value
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
