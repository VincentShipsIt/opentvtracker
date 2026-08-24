import Foundation

enum LibraryBackupMerge {
    static func appearsToBeJSON(_ data: Data) -> Bool {
        var bytes = Array(data.prefix(64))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes.removeFirst(3)
        }
        return bytes.first(where: { ![0x09, 0x0A, 0x0D, 0x20].contains($0) }) == 0x7B
    }

    static func merge(
        imported: LibrarySnapshot,
        into current: LibrarySnapshot
    ) -> LibraryImportPreview {
        var accumulation = LibraryBackupTitleAccumulation(current: current)
        for sourceTitle in imported.titles {
            accumulation.merge(
                sourceTitle,
                fromSchemaVersion: imported.schemaVersion
            )
        }

        var merged = accumulation.snapshot
        mergeLibraryMetadata(imported: imported, current: current, into: &merged)
        mergeDiaryMetadata(
            imported: imported,
            current: current,
            titleIDMap: accumulation.importedTitleIDMap,
            into: &merged
        )
        let listCounts = LibraryTransferService.mergeLists(
            imported: imported,
            titleIDMap: accumulation.importedTitleIDMap,
            into: &merged
        )
        return LibraryTransferService.backupPreview(
            snapshot: merged,
            imported: imported,
            current: current,
            titleCounts: accumulation.titleCounts,
            listCounts: listCounts
        )
    }

    static func sharedSpace(
        imported: SharedSpace,
        into current: SharedSpace
    ) -> SharedSpace {
        if current == LibrarySnapshot.empty.sharedSpace {
            var restored = imported
            let conversation = SharedConversationReconciler.reconcile(
                remote: imported,
                local: current
            )
            applyConversation(
                conversation,
                imported: imported,
                current: nil,
                to: &restored
            )
            return restored
        }

        var merged = current
        merged.members = mergeByID(imported: imported.members, into: current.members)
        merged.titleIDs = mergeValues(imported: imported.titleIDs, into: current.titleIDs)
        merged.activity = mergeByID(imported: imported.activity, into: current.activity)
        merged.watchEvents = mergeOptionalByID(
            imported: imported.watchEvents,
            into: current.watchEvents
        )
        merged.tasteProfiles = mergeOptionalByID(
            imported: imported.tasteProfiles,
            into: current.tasteProfiles
        )
        let conversation = SharedConversationReconciler.reconcile(
            remote: imported,
            local: current
        )
        applyConversation(
            conversation,
            imported: imported,
            current: current,
            to: &merged
        )
        merged.titleMetadata = mergeOptionalByID(
            imported: imported.titleMetadata,
            into: current.titleMetadata
        )
        merged.sharedLists = mergeSharedLists(
            imported: imported.sharedLists,
            into: current.sharedLists
        )
        return merged
    }

    static func importNotice(
        for snapshot: LibrarySnapshot,
        current: LibrarySnapshot
    ) -> String {
        let regionSetting = snapshot.streamingRegionCode == nil
            ? "Streaming region keeps its current setting."
            : "Streaming region restores from the backup."
        let languageSetting = snapshot.contentLanguageSettingWasPresent == true
            ? "Content language restores from the backup."
            : "Content language keeps its current setting."
        let aiSetting: String
        if let allowsAIReranking = snapshot.allowsAIReranking {
            aiSetting = allowsAIReranking
                ? "Optional AI reranking will be enabled from this backup."
                : "Optional AI reranking will be off."
        } else {
            aiSetting = current.allowsAIReranking == true
                ? "Optional AI reranking keeps its current enabled setting."
                : "Optional AI reranking keeps its current off setting."
        }
        return "Matching titles use archived tracking values. Together history merges without deleting newer shared entries. \(regionSetting) \(languageSetting) Saved subscriptions restore when present. \(aiSetting)"
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
        let importedEntries = LibraryTransferService.remappingDiaryEntries(
            ViewingDiaryMigration.resolvedEntries(from: imported),
            titleIDMap: titleIDMap,
            destinationTitles: merged.titles
        )
        merged.diaryEntries = LibraryTransferService.mergedDiaryEntries(
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
            let retainedAliases = Set(merged.titles.map(ImportResolutionAlias.init(title:)))
            merged.importResolutionAliases = mergedAliases.filter { _, alias in
                retainedAliases.contains(
                    ImportResolutionAlias(
                        kind: alias.kind,
                        catalogID: alias.catalogID,
                        metadataSource: alias.resolvedMetadataSource
                    )
                )
            }
        }
        merged.sharedSpace = sharedSpace(
            imported: imported.sharedSpace,
            into: current.sharedSpace
        )
        merged.allowsAIReranking = imported.allowsAIReranking ?? merged.allowsAIReranking
        merged.streamingRegionCode = imported.streamingRegionCode ?? merged.streamingRegionCode
        if imported.contentLanguageSettingWasPresent == true {
            merged.contentLanguageCode = imported.contentLanguageCode
        }
        merged.hasCompletedFirstRun = imported.hasCompletedFirstRun ?? merged.hasCompletedFirstRun
    }

    private static func mergeByID<Element: Identifiable>(
        imported: [Element],
        into current: [Element]
    ) -> [Element] where Element.ID: Hashable {
        var merged = current
        var identifiers = Set(current.map(\.id))
        for item in imported where identifiers.insert(item.id).inserted {
            merged.append(item)
        }
        return merged
    }

    private static func mergeOptionalByID<Element: Identifiable>(
        imported: [Element]?,
        into current: [Element]?
    ) -> [Element]? where Element.ID: Hashable {
        guard imported != nil || current != nil else { return nil }
        return mergeByID(imported: imported ?? [], into: current ?? [])
    }

    private static func mergeSharedLists(
        imported: [SharedMediaList]?,
        into current: [SharedMediaList]?
    ) -> [SharedMediaList]? {
        guard imported != nil || current != nil else { return nil }
        var valuesByID = (current ?? []).keyedByKeepingNewest(\.id, updatedAt: \.updatedAt)
        for list in imported ?? [] where list.updatedAt > (valuesByID[list.id]?.updatedAt ?? .distantPast) {
            valuesByID[list.id] = list
        }
        return valuesByID.values.sorted { $0.id < $1.id }
    }

    private static func applyConversation(
        _ conversation: SharedConversationState,
        imported: SharedSpace,
        current: SharedSpace?,
        to merged: inout SharedSpace
    ) {
        merged.reactions = preserveOptionality(
            conversation.reactions,
            imported: imported.reactions,
            current: current?.reactions
        )
        merged.notes = preserveOptionality(
            conversation.notes,
            imported: imported.notes,
            current: current?.notes
        )
        merged.conversationDeletions = preserveOptionality(
            conversation.deletions,
            imported: imported.conversationDeletions,
            current: current?.conversationDeletions
        )
    }

    private static func preserveOptionality<Element>(
        _ merged: [Element],
        imported: [Element]?,
        current: [Element]?
    ) -> [Element]? {
        guard imported != nil || current != nil else { return nil }
        return merged
    }

    private static func mergeValues<Value: Hashable>(
        imported: [Value],
        into current: [Value]
    ) -> [Value] {
        var merged = current
        var values = Set(current)
        for value in imported where values.insert(value).inserted {
            merged.append(value)
        }
        return merged
    }
}

private struct LibraryBackupTitleAccumulation {
    var snapshot: LibrarySnapshot
    var importedTitleIDMap: [MediaTitle.ID: MediaTitle.ID] = [:]
    private var matchedCount = 0
    private var addedCount = 0
    private var duplicateCount = 0
    private var seen = Set<String>()
    private var catalogIndexByIdentity: [String: Array<MediaTitle>.Index] = [:]
    private var allTitleIndexByIdentity: [String: Array<MediaTitle>.Index] = [:]
    private var uncatalogedTitleIndexByIdentity: [String: Array<MediaTitle>.Index] = [:]

    init(current: LibrarySnapshot) {
        snapshot = current
        catalogIndexByIdentity.reserveCapacity(current.titles.count)
        allTitleIndexByIdentity.reserveCapacity(current.titles.count)
        uncatalogedTitleIndexByIdentity.reserveCapacity(current.titles.count)
        for index in current.titles.indices {
            indexTitle(current.titles[index], at: index)
        }
    }

    var titleCounts: LibraryTitleImportCounts {
        LibraryTitleImportCounts(
            matched: matchedCount,
            added: addedCount,
            duplicates: duplicateCount
        )
    }

    mutating func merge(_ sourceTitle: MediaTitle, fromSchemaVersion schemaVersion: Int?) {
        let importedTitle = sourceTitle.migratedTrackingState(fromSchemaVersion: schemaVersion)
        let identity = LibraryTransferService.identityKey(for: importedTitle)
        let titleIdentity = LibraryTransferService.titleIdentityKey(for: importedTitle)
        let destinationIndex = destinationIndex(
            for: importedTitle,
            identity: identity,
            titleIdentity: titleIdentity
        )
        guard seen.insert(identity).inserted else {
            if let destinationIndex {
                importedTitleIDMap[importedTitle.id] = snapshot.titles[destinationIndex].id
            }
            duplicateCount += 1
            return
        }
        if let destinationIndex {
            mergeTracking(importedTitle, at: destinationIndex, schemaVersion: schemaVersion)
        } else {
            append(importedTitle)
        }
    }

    private func destinationIndex(
        for title: MediaTitle,
        identity: String,
        titleIdentity: String
    ) -> Array<MediaTitle>.Index? {
        guard title.catalogID > 0 else {
            return allTitleIndexByIdentity[titleIdentity]
        }
        let catalogIndex = catalogIndexByIdentity[identity]
        let uncatalogedIndex = uncatalogedTitleIndexByIdentity[titleIdentity]
        if let catalogIndex, let uncatalogedIndex {
            return min(catalogIndex, uncatalogedIndex)
        }
        return catalogIndex ?? uncatalogedIndex
    }

    private mutating func mergeTracking(
        _ importedTitle: MediaTitle,
        at index: Array<MediaTitle>.Index,
        schemaVersion: Int?
    ) {
        importedTitleIDMap[importedTitle.id] = snapshot.titles[index].id
        snapshot.titles[index] = LibraryTransferService.mergingTracking(
            from: importedTitle,
            into: snapshot.titles[index],
            fromSchemaVersion: schemaVersion
        )
        matchedCount += 1
    }

    private mutating func append(_ importedTitle: MediaTitle) {
        importedTitleIDMap[importedTitle.id] = importedTitle.id
        snapshot.titles.append(importedTitle)
        indexTitle(importedTitle, at: snapshot.titles.index(before: snapshot.titles.endIndex))
        addedCount += 1
    }

    private mutating func indexTitle(_ title: MediaTitle, at index: Array<MediaTitle>.Index) {
        let titleIdentity = LibraryTransferService.titleIdentityKey(for: title)
        if allTitleIndexByIdentity[titleIdentity] == nil {
            allTitleIndexByIdentity[titleIdentity] = index
        }
        if title.catalogID > 0 {
            let identity = LibraryTransferService.identityKey(for: title)
            if catalogIndexByIdentity[identity] == nil {
                catalogIndexByIdentity[identity] = index
            }
        } else if uncatalogedTitleIndexByIdentity[titleIdentity] == nil {
            uncatalogedTitleIndexByIdentity[titleIdentity] = index
        }
    }
}
