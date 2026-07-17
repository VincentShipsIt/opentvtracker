import Foundation

enum LibraryBackupMerge {
    static func appearsToBeJSON(_ data: Data) -> Bool {
        var bytes = Array(data.prefix(64))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes.removeFirst(3)
        }
        return bytes.first(where: { ![0x09, 0x0A, 0x0D, 0x20].contains($0) }) == 0x7B
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
                current: current,
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
        return merged
    }

    static func importNotice(
        for snapshot: LibrarySnapshot,
        current: LibrarySnapshot
    ) -> String {
        let regionSetting = snapshot.streamingRegionCode == nil
            ? "Streaming region keeps its current setting."
            : "Streaming region restores from the backup."
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
        return "Matching titles use archived tracking values. Together history merges without deleting newer shared entries. \(regionSetting) Saved subscriptions restore when present. \(aiSetting)"
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

    private static func applyConversation(
        _ conversation: SharedConversationState,
        imported: SharedSpace,
        current: SharedSpace,
        to merged: inout SharedSpace
    ) {
        merged.reactions = preserveOptionality(
            conversation.reactions,
            imported: imported.reactions,
            current: current.reactions
        )
        merged.notes = preserveOptionality(
            conversation.notes,
            imported: imported.notes,
            current: current.notes
        )
        merged.conversationDeletions = preserveOptionality(
            conversation.deletions,
            imported: imported.conversationDeletions,
            current: current.conversationDeletions
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
