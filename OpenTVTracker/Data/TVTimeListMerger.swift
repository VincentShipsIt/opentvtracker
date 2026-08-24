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
        let initialIndexes = initialListIndexes(lists, additionalCapacity: imported.count)
        var listIndexByID = initialIndexes.byID
        let legacyListIndexByGeneratedID = initialIndexes.legacyByGeneratedID

        for importedList in imported {
            guard let targetListID = collisionSafeID(
                for: importedList,
                lists: lists,
                listIndexByID: listIndexByID
            ) else {
                skippedMemberships += importedList.memberships.count
                continue
            }
            let resolvedIDs = resolvedTitleIDs(
                importedList.memberships,
                resolved: resolved,
                skippedMemberships: &skippedMemberships
            )
            let legacyIndex = importedList.generatedIDPrefix == nil
                ? nil : legacyListIndexByGeneratedID[targetListID]

            if let index = listIndexByID[targetListID] ?? legacyIndex {
                let existingIDs = Set(lists[index].titleIDs)
                let addedIDs = resolvedIDs.filter { !existingIDs.contains($0) }
                lists[index].titleIDs.append(contentsOf: addedIDs)
                lists[index].updatedAt = .now
                importedMemberships += addedIDs.count
            } else {
                lists.append(
                    MediaList(
                        id: targetListID,
                        name: importedList.name,
                        titleIDs: resolvedIDs,
                        updatedAt: .now
                    )
                )
                listIndexByID[targetListID] = lists.index(before: lists.endIndex)
                importedMemberships += resolvedIDs.count
            }
        }
        return TVTimeListMergeResult(
            lists: lists,
            importedMemberships: importedMemberships,
            skippedMemberships: skippedMemberships
        )
    }

    private static func resolvedTitleIDs(
        _ memberships: [TVTimeListMembership],
        resolved: [String: MediaTitle],
        skippedMemberships: inout Int
    ) -> [MediaTitle.ID] {
        var seen = Set<MediaTitle.ID>()
        return memberships
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
                return seen.insert(titleID).inserted ? titleID : nil
            }
    }

    private static func collisionSafeID(
        for importedList: TVTimeList,
        lists: [MediaList],
        listIndexByID: [MediaList.ID: Array<MediaList>.Index]
    ) -> MediaList.ID? {
        guard let prefix = importedList.generatedIDPrefix,
              prefix == "tvtime:" || prefix == "tvtime:gdpr:",
              let collidingIndex = listIndexByID[importedList.id] else {
            return importedList.id
        }
        if lists[collidingIndex].name == importedList.name { return importedList.id }

        for collisionAttempt in 0..<TVTimeListIdentifier.maximumCollisionAttempts {
            let candidate = prefix + BoundedStableIdentifier.identifier(
                for: importedList.name,
                collisionAttempt: collisionAttempt
            )
            guard let existingIndex = listIndexByID[candidate] else { return candidate }
            if lists[existingIndex].name == importedList.name { return candidate }
        }
        return nil
    }

    private static func initialListIndexes(
        _ lists: [MediaList],
        additionalCapacity: Int
    ) -> (
        byID: [MediaList.ID: Array<MediaList>.Index],
        legacyByGeneratedID: [MediaList.ID: Array<MediaList>.Index]
    ) {
        var byID: [MediaList.ID: Array<MediaList>.Index] = [:]
        var legacyByGeneratedID: [MediaList.ID: Array<MediaList>.Index] = [:]
        byID.reserveCapacity(lists.count + additionalCapacity)
        legacyByGeneratedID.reserveCapacity(lists.count)
        for index in lists.indices where byID[lists[index].id] == nil {
            byID[lists[index].id] = index
            if let generatedID = generatedIDForLegacyList(lists[index]),
               legacyByGeneratedID[generatedID] == nil {
                legacyByGeneratedID[generatedID] = index
            }
        }
        return (byID, legacyByGeneratedID)
    }

    private static func generatedIDForLegacyList(_ list: MediaList) -> MediaList.ID? {
        let prefix: String
        if list.id.hasPrefix("tvtime:gdpr:") {
            prefix = "tvtime:gdpr:"
        } else if list.id.hasPrefix("tvtime:") {
            prefix = "tvtime:"
        } else {
            return nil
        }
        let legacyIdentifier = list.id.dropFirst(prefix.count)
        guard !legacyIdentifier.hasPrefix("sha256-"),
              BoundedStableIdentifier.legacyHexIdentifier(
                legacyIdentifier,
                matches: list.name
              ) else {
            return nil
        }
        return prefix + BoundedStableIdentifier.identifier(for: list.name)
    }
}

struct TVTimeListMergeResult {
    let lists: [MediaList]
    let importedMemberships: Int
    let skippedMemberships: Int
}
