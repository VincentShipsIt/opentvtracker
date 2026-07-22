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
    let integrityCounts: [ImportCountComparison]
    let resolutionIssues: [ImportResolutionIssue]
    let warnings: [ImportWarning]
    let importNotice: String?

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
        listMembershipCount: Int = 0,
        integrityCounts: [ImportCountComparison] = [],
        resolutionIssues: [ImportResolutionIssue] = [],
        warnings: [ImportWarning] = [],
        importNotice: String? = nil
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
        self.integrityCounts = integrityCounts
        self.resolutionIssues = resolutionIssues
        self.warnings = warnings
        self.importNotice = importNotice
    }

    var summary: String {
        "\(matchedCount) matched · \(addedCount) new · \(duplicateCount) duplicates · \(skippedCount) skipped"
    }
}
