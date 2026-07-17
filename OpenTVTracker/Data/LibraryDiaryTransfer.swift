import Foundation

extension LibraryTransferService {
    static func mergedDiaryEntries(
        current: [ViewingDiaryEntry],
        imported: [ViewingDiaryEntry]
    ) -> [ViewingDiaryEntry] {
        var entriesByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for entry in imported {
            if let existing = entriesByID[entry.id], existing.updatedAt > entry.updatedAt {
                continue
            }
            entriesByID[entry.id] = entry
        }
        return entriesByID.values.sorted { lhs, rhs in
            lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt < rhs.createdAt
        }
    }

    static func exportDiaryCSV(_ snapshot: LibrarySnapshot) -> Data {
        let header = [
            "entry_id", "title_id", "scope", "season_number", "episode_id", "episode_number",
            "watched_at", "rating", "note", "is_rewatch", "created_at", "updated_at"
        ]
        let entries = (snapshot.diaryEntries ?? []).sorted { lhs, rhs in
            lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt < rhs.createdAt
        }
        let rows = entries.map { entry in
            [
                entry.id,
                entry.titleID,
                entry.scope.rawValue,
                entry.seasonNumber.map { String($0) } ?? "",
                entry.episodeID ?? "",
                entry.episodeNumber.map { String($0) } ?? "",
                entry.watchedAt.map(iso8601String) ?? "",
                entry.rating.map { String($0) } ?? "",
                entry.note ?? "",
                String(entry.isRewatch),
                iso8601String(entry.createdAt),
                iso8601String(entry.updatedAt)
            ]
        }
        return csvData(header: header, rows: rows)
    }

    static func mergeDiaryCSV(
        _ rows: [[String]],
        into current: LibrarySnapshot
    ) throws -> LibraryImportPreview {
        guard let header = rows.first, !header.isEmpty else { throw LibraryTransferError.emptyFile }
        let normalizedHeader = header.map(normalizedHeaderName)
        let validTitleIDs = Set(current.titles.map(\.id))
        var merged = current
        var entriesByID = Dictionary(uniqueKeysWithValues: (current.diaryEntries ?? []).map { ($0.id, $0) })
        var seen = Set<ViewingDiaryEntry.ID>()
        var matched = 0
        var added = 0
        var duplicates = 0
        var skipped = 0

        for row in rows.dropFirst() where row.contains(where: { !$0.isEmpty }) {
            let values = csvValues(header: normalizedHeader, row: row)
            guard let entry = diaryEntry(from: values), validTitleIDs.contains(entry.titleID) else {
                skipped += 1
                continue
            }
            guard seen.insert(entry.id).inserted else {
                duplicates += 1
                continue
            }
            if let existing = entriesByID[entry.id] {
                matched += 1
                if entry.updatedAt >= existing.updatedAt {
                    entriesByID[entry.id] = entry
                }
            } else {
                added += 1
                entriesByID[entry.id] = entry
            }
        }

        merged.diaryEntries = mergedDiaryEntries(current: [], imported: Array(entriesByID.values))
        return LibraryImportPreview(
            snapshot: merged,
            matchedCount: matched,
            addedCount: added,
            duplicateCount: duplicates,
            skippedCount: skipped,
            sourceName: "OpenTV diary",
            watchEventCount: merged.diaryEntries?.filter { $0.watchedAt != nil }.count ?? 0
        )
    }
}

private extension LibraryTransferService {
    static func diaryEntry(from values: [String: String]) -> ViewingDiaryEntry? {
        guard let id = stringValue(in: values, keys: ["entry_id", "id"]),
              let titleID = stringValue(in: values, keys: ["title_id"]),
              let scopeValue = stringValue(in: values, keys: ["scope"]),
              let scope = ViewingDiaryScope(rawValue: scopeValue) else {
            return nil
        }
        let seasonNumber = intValue(in: values, keys: ["season_number", "season"])
        let episodeID = stringValue(in: values, keys: ["episode_id"])
        let episodeNumber = intValue(in: values, keys: ["episode_number", "episode"])
        if scope == .season, seasonNumber == nil { return nil }
        if scope == .episode, seasonNumber == nil || episodeID == nil || episodeNumber == nil { return nil }

        let watchedAtValue = stringValue(in: values, keys: ["watched_at"])
        let createdAtValue = stringValue(in: values, keys: ["created_at"])
        let updatedAtValue = stringValue(in: values, keys: ["updated_at"])
        let watchedAt = watchedAtValue.flatMap(iso8601Date)
        guard watchedAtValue == nil || watchedAt != nil,
              createdAtValue == nil || createdAtValue.flatMap(iso8601Date) != nil,
              updatedAtValue == nil || updatedAtValue.flatMap(iso8601Date) != nil else {
            return nil
        }
        let createdAt = createdAtValue.flatMap(iso8601Date)
            ?? watchedAt ?? .now
        let updatedAt = updatedAtValue.flatMap(iso8601Date)
            ?? createdAt

        return ViewingDiaryEntry(
            id: id,
            titleID: titleID,
            scope: scope,
            seasonNumber: seasonNumber,
            episodeID: episodeID,
            episodeNumber: episodeNumber,
            watchedAt: watchedAt,
            rating: doubleValue(in: values, keys: ["rating"]).map { min(max($0, 0), 10) },
            note: stringValue(in: values, keys: ["note", "notes"]),
            isRewatch: boolValue(in: values, keys: ["is_rewatch", "rewatch"]) ?? false,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
