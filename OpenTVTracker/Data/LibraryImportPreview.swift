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
    let importNotice: String?
    let resolutionIssues: [ImportResolutionIssue]

    init(
        snapshot: LibrarySnapshot,
        matchedCount: Int,
        addedCount: Int,
        duplicateCount: Int,
        skippedCount: Int,
        sourceName: String = "OpenTV",
        watchedEpisodeCount: Int = 0,
        watchEventCount: Int = 0,
        importNotice: String? = nil,
        resolutionIssues: [ImportResolutionIssue] = []
    ) {
        self.snapshot = snapshot
        self.matchedCount = matchedCount
        self.addedCount = addedCount
        self.duplicateCount = duplicateCount
        self.skippedCount = skippedCount
        self.sourceName = sourceName
        self.watchedEpisodeCount = watchedEpisodeCount
        self.watchEventCount = watchEventCount
        self.importNotice = importNotice
        self.resolutionIssues = resolutionIssues
    }

    var summary: String {
        "\(matchedCount) matched · \(addedCount) new · \(duplicateCount) duplicates · \(skippedCount) skipped"
    }
}
