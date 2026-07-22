extension LibraryTransferService {
    static func backupPreview(
        snapshot: LibrarySnapshot,
        imported: LibrarySnapshot,
        current: LibrarySnapshot,
        titleCounts: LibraryTitleImportCounts,
        listCounts: LibraryListImportCounts
    ) -> LibraryImportPreview {
        LibraryImportPreview(
            snapshot: snapshot,
            matchedCount: titleCounts.matched,
            addedCount: titleCounts.added,
            duplicateCount: titleCounts.duplicates,
            skippedCount: 0,
            sourceName: "OpenTV backup",
            watchedEpisodeCount: imported.titles.reduce(0) {
                $0 + ($1.watchedEpisodeIDs?.count ?? 0)
            },
            watchEventCount: imported.sharedSpace.watchEvents?.count ?? 0,
            listCount: listCounts.lists,
            listMembershipCount: listCounts.memberships,
            importNotice: LibraryBackupMerge.importNotice(
                for: imported,
                current: current
            )
        )
    }
}
