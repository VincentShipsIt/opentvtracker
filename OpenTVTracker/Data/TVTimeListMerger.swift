import Foundation

enum TVTimeListMerger {
    static func merge(
        _ imported: [TVTimeList],
        into current: [MediaList],
        resolved: [String: MediaTitle]
    ) -> TVTimeListMergeResult {
        var lists = current
        var importedMemberships = 0
        var skippedMemberships = 0
        var listIndexByID: [MediaList.ID: Array<MediaList>.Index] = [:]
        listIndexByID.reserveCapacity(current.count + imported.count)
        for index in lists.indices where listIndexByID[lists[index].id] == nil {
            listIndexByID[lists[index].id] = index
        }

        for importedList in imported {
            var seen = Set<MediaTitle.ID>()
            let resolvedIDs = importedList.memberships
                .sorted { lhs, rhs in
                    lhs.order == rhs.order
                        ? lhs.entityIdentity < rhs.entityIdentity
                        : lhs.order < rhs.order
                }
                .compactMap { membership -> MediaTitle.ID? in
                    guard let titleID = resolved[membership.entityIdentity]?.id else {
                        skippedMemberships += 1
                        return nil
                    }
                    guard seen.insert(titleID).inserted else { return nil }
                    return titleID
                }

            if let index = listIndexByID[importedList.id] {
                let existingIDs = Set(lists[index].titleIDs)
                let addedIDs = resolvedIDs.filter { !existingIDs.contains($0) }
                lists[index].titleIDs.append(contentsOf: addedIDs)
                lists[index].updatedAt = .now
                importedMemberships += addedIDs.count
            } else {
                lists.append(
                    MediaList(
                        id: importedList.id,
                        name: importedList.name,
                        titleIDs: resolvedIDs,
                        updatedAt: .now
                    )
                )
                listIndexByID[importedList.id] = lists.index(before: lists.endIndex)
                importedMemberships += resolvedIDs.count
            }
        }
        return TVTimeListMergeResult(
            lists: lists,
            importedMemberships: importedMemberships,
            skippedMemberships: skippedMemberships
        )
    }
}

struct TVTimeListMergeResult {
    let lists: [MediaList]
    let importedMemberships: Int
    let skippedMemberships: Int
}
