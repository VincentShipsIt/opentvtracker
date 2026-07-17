import Foundation

struct LibraryImportPreview: Sendable {
    let snapshot: LibrarySnapshot
    let matchedCount: Int
    let addedCount: Int
    let duplicateCount: Int
    let skippedCount: Int
    let sourceName: String
    let watchedEpisodeCount: Int
    let watchEventCount: Int
    let listCount: Int
    let listMembershipCount: Int

    init(
        snapshot: LibrarySnapshot,
        matchedCount: Int,
        addedCount: Int,
        duplicateCount: Int,
        skippedCount: Int,
        sourceName: String = "OpenTV",
        watchedEpisodeCount: Int = 0,
        watchEventCount: Int = 0,
        listCount: Int = 0,
        listMembershipCount: Int = 0
    ) {
        self.snapshot = snapshot
        self.matchedCount = matchedCount
        self.addedCount = addedCount
        self.duplicateCount = duplicateCount
        self.skippedCount = skippedCount
        self.sourceName = sourceName
        self.watchedEpisodeCount = watchedEpisodeCount
        self.watchEventCount = watchEventCount
        self.listCount = listCount
        self.listMembershipCount = listMembershipCount
    }

    var summary: String {
        "\(matchedCount) matched · \(addedCount) new · \(duplicateCount) duplicates · \(skippedCount) skipped"
    }
}
