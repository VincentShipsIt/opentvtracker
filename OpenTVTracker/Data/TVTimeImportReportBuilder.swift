import Foundation

enum TVTimeImportReportBuilder {
    static func warnings(
        _ initial: [ImportWarning],
        diagnostics: TVTimeImportDiagnostics,
        resolutionIssueCount: Int,
        skippedCount: Int
    ) -> [ImportWarning] {
        var warnings = initial
        appendDiagnosticWarnings(diagnostics, to: &warnings)
        if resolutionIssueCount > 0 {
            warnings.append(
                ImportWarning(
                    id: "catalog-resolution-\(resolutionIssueCount)",
                    message: "\(resolutionIssueCount) title \(resolutionIssueCount == 1 ? "needs" : "need") a manual catalog match before it can be imported."
                )
            )
        }
        let unmatchedEpisodes = skippedCount
            - diagnostics.missingIdentityCount
            - diagnostics.unsupportedRecordCount
            - resolutionIssueCount
        if unmatchedEpisodes > 0 {
            warnings.append(
                ImportWarning(
                    id: "unmatched-episodes-\(unmatchedEpisodes)",
                    message: "\(unmatchedEpisodes) watched episode \(unmatchedEpisodes == 1 ? "was" : "were") not present in current catalog metadata."
                )
            )
        }
        return warnings
    }

    static func sourceCounts(
        for archive: TVTimeArchive
    ) -> [ImportMetricCategory: Int] {
        var counts = Dictionary(
            uniqueKeysWithValues: ImportMetricCategory.allCases.map { ($0, 0) }
        )
        for entity in archive.entities {
            counts[entity.kind == .series ? .shows : .movies, default: 0] += 1
            counts[.episodes, default: 0] += entity.watches.filter {
                entity.kind == .series && $0.season != nil && $0.episode != nil
            }.count
            counts[.rewatches, default: 0] += importedRewatchCount(for: entity)
            if entity.rating != nil {
                counts[.ratings, default: 0] += 1
            }
            if isWatchlistEntry(entity) {
                counts[.watchlist, default: 0] += 1
            }
        }
        return counts
    }

    static func isWatchlistEntry(_ entity: TVTimeEntity) -> Bool {
        entity.isForLater || (entity.isFollowed && entity.watches.isEmpty)
    }

    private static func appendDiagnosticWarnings(
        _ diagnostics: TVTimeImportDiagnostics,
        to warnings: inout [ImportWarning]
    ) {
        if diagnostics.missingIdentityCount > 0 {
            warnings.append(
                ImportWarning(
                    id: "missing-identities-\(diagnostics.missingIdentityCount)",
                    message: "\(diagnostics.missingIdentityCount) record \(diagnostics.missingIdentityCount == 1 ? "was" : "were") missing both a title and source identifier."
                )
            )
        }
        if diagnostics.unsupportedRecordCount > 0 {
            warnings.append(
                ImportWarning(
                    id: "unsupported-records-\(diagnostics.unsupportedRecordCount)",
                    message: "\(diagnostics.unsupportedRecordCount) source record \(diagnostics.unsupportedRecordCount == 1 ? "uses" : "use") a format OpenTV does not import yet."
                )
            )
        }
        if diagnostics.unsupportedEpisodeRatingCount > 0 {
            warnings.append(
                ImportWarning(
                    id: "episode-ratings-\(diagnostics.unsupportedEpisodeRatingCount)",
                    message: "\(diagnostics.unsupportedEpisodeRatingCount) episode rating \(diagnostics.unsupportedEpisodeRatingCount == 1 ? "is" : "are") not supported yet; title-level ratings are imported normally."
                )
            )
        }
        if diagnostics.unreadableFileCount > 0 {
            warnings.append(
                ImportWarning(
                    id: "unreadable-files-\(diagnostics.unreadableFileCount)",
                    message: "\(diagnostics.unreadableFileCount) CSV \(diagnostics.unreadableFileCount == 1 ? "file was" : "files were") not valid UTF-8."
                )
            )
        }
    }

    private static func importedRewatchCount(for entity: TVTimeEntity) -> Int {
        if entity.kind == .movie {
            return [
                entity.rewatchCount,
                max(entity.watches.count - 1, 0),
                entity.watches.filter(\.isRewatch).count
            ].max() ?? 0
        }
        return entity.watches.reduce(0) {
            $0 + $1.importedRewatchCount
        }
    }
}
