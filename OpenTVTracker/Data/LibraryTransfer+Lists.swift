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
        var indexByID: [MediaList.ID: Array<MediaList>.Index] = [:]
        var membershipIndexes = current.map { Set($0.titleIDs) }
        indexByID.reserveCapacity(current.count + imported.count)
        membershipIndexes.reserveCapacity(current.count + imported.count)
        for index in merged.indices where indexByID[merged[index].id] == nil {
            indexByID[merged[index].id] = index
        }
        for importedList in imported {
            if let index = indexByID[importedList.id] {
                if preservingExistingIDs.contains(importedList.id) {
                    merged[index].titleIDs.append(
                        contentsOf: importedList.titleIDs.filter {
                            !membershipIndexes[index].contains($0)
                        }
                    )
                    merged[index].updatedAt = .now
                } else {
                    merged[index] = mergingList(
                        importedList,
                        into: merged[index],
                        currentMembershipIDs: membershipIndexes[index]
                    )
                }
                membershipIndexes[index].formUnion(importedList.titleIDs)
            } else {
                merged.append(importedList)
                indexByID[importedList.id] = merged.index(before: merged.endIndex)
                membershipIndexes.append(Set(importedList.titleIDs))
            }
        }
        return merged
    }

    private static func mergingList(
        _ imported: MediaList,
        into current: MediaList,
        currentMembershipIDs: Set<MediaTitle.ID>
    ) -> MediaList {
        if imported.updatedAt > current.updatedAt {
            var merged = imported
            let importedIDs = Set(imported.titleIDs)
            merged.titleIDs.append(contentsOf: current.titleIDs.filter { !importedIDs.contains($0) })
            return merged
        }
        var merged = current
        merged.titleIDs.append(
            contentsOf: imported.titleIDs.filter { !currentMembershipIDs.contains($0) }
        )
        return merged
    }
}

struct LibraryListImportCounts {
    let lists: Int
    let memberships: Int
}
