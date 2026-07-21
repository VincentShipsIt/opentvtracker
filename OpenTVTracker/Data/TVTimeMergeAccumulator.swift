import Foundation

struct TVTimeHistoryDeduplicator {
    var eventIDs: Set<String>
    var diaryIDs: Set<String>

    init(snapshot: LibrarySnapshot) {
        eventIDs = Set((snapshot.sharedSpace.watchEvents ?? []).map(\.id))
        diaryIDs = Set((snapshot.diaryEntries ?? []).map(\.id))
    }
}

struct TVTimeMergeAccumulator {
    var snapshot: LibrarySnapshot
    var matchedCount = 0
    var addedCount = 0
    var skippedCount = 0
    var watchedEpisodeCount = 0
    var watchEventCount = 0
    private let memberID: String
    private var deduplicator: TVTimeHistoryDeduplicator

    init(snapshot: LibrarySnapshot) {
        self.snapshot = snapshot
        memberID = snapshot.sharedSpace.members.first(where: \.isCurrentUser)?.id ?? "local-user"
        deduplicator = TVTimeHistoryDeduplicator(snapshot: snapshot)
    }

    mutating func merge(_ entity: TVTimeEntity, resolvedTitle: MediaTitle?) {
        guard var catalogTitle = resolvedTitle else {
            skippedCount += 1
            return
        }
        let existingIndex = snapshot.titles.firstIndex { TVTimeImportMerger.matches($0, entity) }
        if let existingIndex {
            catalogTitle = snapshot.titles[existingIndex]
            matchedCount += 1
        } else {
            addedCount += 1
        }

        let applied = TVTimeImportMerger.apply(
            entity,
            to: &catalogTitle,
            memberID: memberID,
            deduplicator: &deduplicator
        )
        incorporate(applied, title: catalogTitle, existingIndex: existingIndex)
    }

    func preview(duplicateCount: Int) -> LibraryImportPreview {
        LibraryImportPreview(
            snapshot: snapshot,
            matchedCount: matchedCount,
            addedCount: addedCount,
            duplicateCount: duplicateCount,
            skippedCount: skippedCount,
            sourceName: "TV Time",
            watchedEpisodeCount: watchedEpisodeCount,
            watchEventCount: watchEventCount
        )
    }

    private mutating func incorporate(
        _ applied: AppliedHistory,
        title: MediaTitle,
        existingIndex: Int?
    ) {
        watchedEpisodeCount += applied.watchedEpisodes
        watchEventCount += applied.watchEvents.count
        skippedCount += applied.unmatchedEpisodes
        snapshot.sharedSpace.watchEvents = (snapshot.sharedSpace.watchEvents ?? []) + applied.watchEvents
        snapshot.diaryEntries = (snapshot.diaryEntries ?? []) + applied.diaryEntries
        if let existingIndex {
            snapshot.titles[existingIndex] = title
        } else {
            snapshot.titles.append(title)
        }
        if !snapshot.sharedSpace.titleIDs.contains(title.id) {
            snapshot.sharedSpace.titleIDs.append(title.id)
        }
    }
}
