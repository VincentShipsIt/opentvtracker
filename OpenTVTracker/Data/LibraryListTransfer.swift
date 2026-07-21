import Foundation

enum LibraryListTransferService {
    static func exportCSV(_ snapshot: LibrarySnapshot) -> Data {
        let header = [
            "list_id", "list_name", "list_position", "item_position",
            "title_id", "catalog_id", "title", "year", "kind"
        ]
        let titlesByID = Dictionary(uniqueKeysWithValues: snapshot.titles.map { ($0.id, $0) })
        let rows = (snapshot.lists ?? []).enumerated().flatMap { listPosition, list in
            if list.titleIDs.isEmpty {
                return [[
                    list.id, list.name, String(listPosition), "", "", "", "", "", ""
                ]]
            }
            return list.titleIDs.enumerated().map { itemPosition, titleID in
                let title = titlesByID[titleID]
                return [
                    list.id,
                    list.name,
                    String(listPosition),
                    String(itemPosition),
                    titleID,
                    title.map { String($0.catalogID) } ?? "",
                    title?.title ?? "",
                    title.map { String($0.year) } ?? "",
                    title?.kind.rawValue ?? ""
                ]
            }
        }
        return LibraryTransferService.csvData(header: header, rows: rows)
    }

    static func mergeCSV(
        _ rows: ArraySlice<[String]>,
        header: [String],
        into current: LibrarySnapshot
    ) -> LibraryImportPreview {
        let isTVTime = header.contains("tvdb_id") || header.contains("custom_order")
        let accumulation = accumulate(rows, header: header, current: current, isTVTime: isTVTime)
        let importedLists = makeLists(from: accumulation.importedByID)
        let preservingExistingIDs = isTVTime
            ? Set(importedLists.map(\.id))
            : accumulation.listIDsWithSkippedMemberships
        var merged = current
        merged.lists = LibraryTransferService.mergingLists(
            importedLists,
            into: current.lists ?? [],
            preservingExistingIDs: preservingExistingIDs
        )
        return LibraryImportPreview(
            snapshot: merged,
            matchedCount: accumulation.matchedCount,
            addedCount: 0,
            duplicateCount: 0,
            skippedCount: accumulation.skippedCount,
            sourceName: isTVTime ? "TV Time lists" : "OpenTV lists",
            listCount: importedLists.count,
            listMembershipCount: importedLists.reduce(0) { $0 + $1.titleIDs.count }
        )
    }
}

private extension LibraryListTransferService {
    static func accumulate(
        _ rows: ArraySlice<[String]>,
        header: [String],
        current: LibrarySnapshot,
        isTVTime: Bool
    ) -> ListCSVAccumulation {
        var result = ListCSVAccumulation()
        for row in rows where row.contains(where: { !$0.isEmpty }) {
            let values = LibraryTransferService.csvValues(header: header, row: row)
            guard let name = LibraryTransferService.stringValue(
                in: values,
                keys: ["list_name", "name"]
            ) else {
                result.skippedCount += 1
                continue
            }
            let sourceID = LibraryTransferService.stringValue(in: values, keys: ["list_id"])
                ?? stableListIdentifier(name)
            let listID = isTVTime ? "tvtime:\(sourceID)" : sourceID
            let listPosition = LibraryTransferService.intValue(in: values, keys: ["list_position"])
                ?? result.importedByID.count
            var accumulator = result.importedByID[listID] ?? ListCSVAccumulator(
                id: listID,
                name: name,
                position: listPosition
            )

            if hasTitleReference(values) {
                guard let titleIndex = LibraryTransferService.matchingTitleIndex(
                    values,
                    titles: current.titles
                ) else {
                    result.skippedCount += 1
                    result.listIDsWithSkippedMemberships.insert(listID)
                    result.importedByID[listID] = accumulator
                    continue
                }
                let itemPosition = LibraryTransferService.intValue(
                    in: values,
                    keys: ["item_position", "custom_order"]
                ) ?? accumulator.members.count
                accumulator.members.append(
                    (position: itemPosition, titleID: current.titles[titleIndex].id)
                )
                result.matchedCount += 1
            }
            result.importedByID[listID] = accumulator
        }
        return result
    }

    static func hasTitleReference(_ values: [String: String]) -> Bool {
        ["title_id", "catalog_id", "tmdb_id", "tvdb_id", "title", "name"]
            .contains { values[$0]?.isEmpty == false }
    }

    static func makeLists(
        from importedByID: [MediaList.ID: ListCSVAccumulator]
    ) -> [MediaList] {
        importedByID.values
            .sorted { lhs, rhs in
                lhs.position == rhs.position
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : lhs.position < rhs.position
            }
            .map { accumulator in
                MediaList(
                    id: accumulator.id,
                    name: accumulator.name,
                    titleIDs: orderedUniqueTitleIDs(accumulator.members),
                    updatedAt: .now
                )
            }
    }

    static func orderedUniqueTitleIDs(
        _ members: [(position: Int, titleID: MediaTitle.ID)]
    ) -> [MediaTitle.ID] {
        var seen = Set<MediaTitle.ID>()
        return members
            .sorted { lhs, rhs in
                lhs.position == rhs.position ? lhs.titleID < rhs.titleID : lhs.position < rhs.position
            }
            .compactMap { seen.insert($0.titleID).inserted ? $0.titleID : nil }
    }

    static func stableListIdentifier(_ name: String) -> String {
        name.utf8.map { String(format: "%02x", $0) }.joined()
    }
}

private struct ListCSVAccumulator {
    let id: MediaList.ID
    let name: String
    let position: Int
    var members: [(position: Int, titleID: MediaTitle.ID)] = []
}

private struct ListCSVAccumulation {
    var importedByID: [MediaList.ID: ListCSVAccumulator] = [:]
    var listIDsWithSkippedMemberships = Set<MediaList.ID>()
    var skippedCount = 0
    var matchedCount = 0
}
