import Foundation

extension LibraryTransferService {
    static func exportListsCSV(_ snapshot: LibrarySnapshot) -> Data {
        LibraryListTransferService.exportCSV(snapshot)
    }

    static func previewListImport(
        _ rows: [[String]],
        into current: LibrarySnapshot
    ) -> LibraryImportPreview? {
        guard let header = rows.first?.map(normalizedHeaderName),
              header.contains("list_name") else {
            return nil
        }
        return LibraryListTransferService.mergeCSV(
            rows.dropFirst(),
            header: header,
            into: current
        )
    }

    static func mergeLists(
        imported: LibrarySnapshot,
        titleIDMap: [MediaTitle.ID: MediaTitle.ID],
        into merged: inout LibrarySnapshot
    ) -> LibraryListImportCounts {
        let availableTitleIDs = Set(merged.titles.map(\.id))
        let importedLists = (imported.lists ?? []).map { list in
            var remapped = list
            remapped.titleIDs = list.titleIDs.compactMap {
                titleIDMap[$0] ?? (availableTitleIDs.contains($0) ? $0 : nil)
            }
            return remapped
        }
        merged.lists = mergingLists(importedLists, into: merged.lists ?? [])
        return LibraryListImportCounts(
            lists: importedLists.count,
            memberships: importedLists.reduce(0) { $0 + $1.titleIDs.count }
        )
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
                    merged[index].titleIDs.append(
                        contentsOf: importedList.titleIDs.filter { !existingIDs.contains($0) }
                    )
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

struct LibraryListImportCounts {
    let lists: Int
    let memberships: Int
}
