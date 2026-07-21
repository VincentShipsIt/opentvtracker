import Foundation

struct TVTimeTitleResolution: Sendable {
    var resolved: [String: MediaTitle]
    var issues: [String: ImportResolutionIssue]
    var warnings: [ImportWarning]
}

private enum AutomaticResolutionResult: Sendable {
    case resolved(String, MediaTitle)
    case issue(ImportResolutionIssue)
}

private enum CandidateSelection {
    case candidate(MediaTitle)
    case issue(ImportResolutionReason, String)
}

enum TVTimeImportMerger {
    static func resolveTitles(
        _ entities: [TVTimeEntity],
        current: LibrarySnapshot,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async -> TVTimeTitleResolution {
        var resolved: [String: MediaTitle] = [:]
        var issues: [String: ImportResolutionIssue] = [:]
        var warnings: [ImportWarning] = []
        var unresolved: [TVTimeEntity] = []
        let currentTitles = TVTimeMediaTitleLookup(current.titles)

        let aliasResolution = await TVTimeImportAliasResolver.resolve(
            entities,
            aliases: current.importResolutionAliases ?? [:],
            catalog: catalog,
            region: region
        )
        resolved = aliasResolution.resolved
        warnings = aliasResolution.warnings

        for entity in entities {
            if resolved[entity.identity] != nil {
                continue
            }
            if let localIndex = currentTitles.index(matching: entity) {
                resolved[entity.identity] = current.titles[localIndex]
            } else {
                unresolved.append(entity)
            }
        }

        let catalogResolution = await resolveCatalogTitles(
            unresolved,
            catalog: catalog,
            region: region
        )
        resolved.merge(catalogResolution.resolved) { _, catalogTitle in catalogTitle }
        issues.merge(catalogResolution.issues) { _, catalogIssue in catalogIssue }
        return TVTimeTitleResolution(
            resolved: resolved,
            issues: issues,
            warnings: warnings + catalogResolution.warnings
        )
    }

    static func mergedPreview(
        _ archive: TVTimeArchive,
        into current: LibrarySnapshot,
        automaticResolution: TVTimeTitleResolution,
        manualResolutions: [ImportResolutionIssue.ID: MediaTitle]
    ) -> LibraryImportPreview {
        var snapshot = current
        var resolved = automaticResolution.resolved
        var resolutionIssues = automaticResolution.issues
        applyManualResolutions(
            manualResolutions,
            resolved: &resolved,
            issues: &resolutionIssues,
            snapshot: &snapshot
        )
        let totals = mergeArchive(archive, resolved: resolved, into: &snapshot)
        let warnings = TVTimeImportReportBuilder.warnings(
            automaticResolution.warnings,
            diagnostics: archive.diagnostics,
            resolutionIssueCount: resolutionIssues.count,
            unmatchedEpisodeCount: totals.unmatchedEpisodeCount
        )
        let sourceCounts = TVTimeImportReportBuilder.sourceCounts(for: archive)
        return LibraryImportPreview(
            snapshot: snapshot,
            matchedCount: totals.matchedCount,
            addedCount: totals.addedCount,
            duplicateCount: archive.duplicateCount,
            skippedCount: totals.skippedCount,
            sourceName: "TV Time",
            watchedEpisodeCount: totals.watchedEpisodeCount,
            watchEventCount: totals.watchEventCount,
            listCount: totals.listCount,
            listMembershipCount: totals.listMembershipCount,
            integrityCounts: ImportMetricCategory.allCases.map { category in
                ImportCountComparison(
                    category: category,
                    sourceCount: sourceCounts[category, default: 0],
                    importedCount: totals.destinationCounts[category, default: 0]
                )
            },
            resolutionIssues: resolutionIssues.values.sorted {
                $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
            },
            warnings: warnings
        )
    }
}

private extension TVTimeImportMerger {
    private static func applyManualResolutions(
        _ manualResolutions: [ImportResolutionIssue.ID: MediaTitle],
        resolved: inout [String: MediaTitle],
        issues: inout [String: ImportResolutionIssue],
        snapshot: inout LibrarySnapshot
    ) {
        for (identity, title) in manualResolutions {
            resolved[identity] = title
            issues.removeValue(forKey: identity)
            var aliases = snapshot.importResolutionAliases ?? [:]
            aliases[identity] = ImportResolutionAlias(kind: title.kind, catalogID: title.catalogID)
            snapshot.importResolutionAliases = aliases
        }
    }

    private static func mergeArchive(
        _ archive: TVTimeArchive,
        resolved: [String: MediaTitle],
        into snapshot: inout LibrarySnapshot
    ) -> PreviewMergeTotals {
        var totals = PreviewMergeTotals(
            skippedCount: archive.diagnostics.missingIdentityCount
                + archive.diagnostics.unsupportedRecordCount
        )
        var watchEvents = snapshot.sharedSpace.watchEvents ?? []
        var diaryEntries = snapshot.diaryEntries ?? []
        var mergeState = TVTimeMergeState(snapshot: snapshot)
        for entity in archive.entities {
            guard let result = merge(
                entity,
                into: &snapshot,
                resolved: resolved,
                state: &mergeState,
                shouldShare: !archive.containsListOnly(entity)
            ) else {
                totals.skippedCount += 1
                continue
            }
            totals.add(result)
            watchEvents.append(contentsOf: result.watchEvents)
            diaryEntries.append(contentsOf: result.diaryEntries)
        }
        snapshot.sharedSpace.watchEvents = watchEvents
        snapshot.diaryEntries = diaryEntries
        let listMerge = TVTimeListMerger.merge(
            archive.lists,
            into: snapshot.lists ?? [],
            resolved: resolved
        )
        snapshot.lists = listMerge.lists
        totals.listCount = archive.lists.count
        totals.listMembershipCount = listMerge.importedMemberships
        totals.skippedCount += listMerge.skippedMemberships
        return totals
    }

    private static func merge(
        _ entity: TVTimeEntity,
        into snapshot: inout LibrarySnapshot,
        resolved: [String: MediaTitle],
        state: inout TVTimeMergeState,
        shouldShare: Bool
    ) -> EntityMergeResult? {
        guard var catalogTitle = resolved[entity.identity] else { return nil }
        let existingIndex = state.titleLookup.index(for: catalogTitle, matching: entity)
        if let existingIndex {
            catalogTitle = snapshot.titles[existingIndex]
        }

        let applied = TVTimeHistoryApplier.apply(
            entity,
            to: &catalogTitle,
            state: &state
        )
        if let existingIndex {
            snapshot.titles[existingIndex] = catalogTitle
        } else {
            snapshot.titles.append(catalogTitle)
            state.titleLookup.insert(
                catalogTitle,
                at: snapshot.titles.index(before: snapshot.titles.endIndex)
            )
        }
        if shouldShare, state.titleIDs.insert(catalogTitle.id).inserted {
            snapshot.sharedSpace.titleIDs.append(catalogTitle.id)
        }

        var destinationCounts: [ImportMetricCategory: Int] = [
            (entity.kind == .series ? .shows : .movies): 1,
            .episodes: applied.watchedEpisodes,
            .rewatches: applied.rewatches
        ]
        if entity.rating != nil { destinationCounts[.ratings] = 1 }
        if applied.watchlisted {
            destinationCounts[.watchlist] = 1
        }
        return EntityMergeResult(
            matchedCount: existingIndex == nil ? 0 : 1,
            addedCount: existingIndex == nil ? 1 : 0,
            watchedEpisodeCount: applied.watchedEpisodes,
            watchEventCount: applied.watchEvents.count,
            skippedCount: applied.unmatchedEpisodes,
            unmatchedEpisodeCount: applied.unmatchedEpisodes,
            destinationCounts: destinationCounts,
            watchEvents: applied.watchEvents,
            diaryEntries: applied.diaryEntries
        )
    }

    private static func resolve(
        _ entity: TVTimeEntity,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async -> AutomaticResolutionResult {
        guard !entity.title.isEmpty else {
            return .issue(
                resolutionIssue(
                    entity,
                    reason: .missingTitle,
                    detail: "The export includes a source identifier but no searchable title."
                )
            )
        }
        do {
            let results = try await catalog.search(
                MediaSearchQuery(text: entity.title, kind: entity.kind, page: 1, region: region)
            )
            switch selectCandidate(for: entity, from: results) {
            case .issue(let reason, let detail):
                return .issue(
                    resolutionIssue(entity, reason: reason, detail: detail)
                )
            case .candidate(let candidate):
                let detailed = (try? await catalog.title(
                    kind: candidate.kind,
                    catalogID: candidate.catalogID,
                    region: region
                )) ?? candidate
                return .resolved(entity.identity, detailed)
            }
        } catch {
            return .issue(
                resolutionIssue(
                    entity,
                    reason: .catalogUnavailable,
                    detail: "OpenTV could not reach the catalog. Retry or choose a match when the catalog is available."
                )
            )
        }
    }

    private static func resolveCatalogTitles(
        _ entities: [TVTimeEntity],
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async -> TVTimeTitleResolution {
        var resolution = TVTimeTitleResolution(resolved: [:], issues: [:], warnings: [])
        for batchStart in stride(from: 0, to: entities.count, by: 6) {
            let batch = Array(entities[batchStart..<min(batchStart + 6, entities.count)])
            await withTaskGroup(of: AutomaticResolutionResult.self) { group in
                for entity in batch {
                    group.addTask {
                        await resolve(entity, catalog: catalog, region: region)
                    }
                }
                for await result in group {
                    switch result {
                    case .resolved(let identity, let title):
                        resolution.resolved[identity] = title
                    case .issue(let issue):
                        resolution.issues[issue.id] = issue
                    }
                }
            }
        }
        return resolution
    }

    private static func resolutionIssue(
        _ entity: TVTimeEntity,
        reason: ImportResolutionReason,
        detail: String
    ) -> ImportResolutionIssue {
        ImportResolutionIssue(
            id: entity.identity,
            sourceID: entity.sourceID,
            title: entity.title,
            year: entity.year,
            kind: entity.kind,
            reason: reason,
            detail: detail
        )
    }

    private static func selectCandidate(
        for entity: TVTimeEntity,
        from results: [MediaTitle]
    ) -> CandidateSelection {
        let matchingKind = results.filter { $0.kind == entity.kind }
        let exactTitles = matchingKind.filter {
            TVTimeCSV.normalizedTitle($0.title) == TVTimeCSV.normalizedTitle(entity.title)
        }
        let candidates = entity.year.map { year in
            exactTitles.filter { $0.year == year }
        } ?? exactTitles
        if candidates.count == 1, let candidate = candidates.first {
            return .candidate(candidate)
        }
        if candidates.count > 1 {
            return .issue(
                .ambiguousCatalogMatch,
                "The catalog returned several exact title matches. Choose the correct release."
            )
        }
        if candidates.isEmpty, exactTitles.count == 1, entity.year != nil {
            return .issue(
                .ambiguousCatalogMatch,
                "The catalog found this exact title with a different release year. Confirm the correct release."
            )
        }
        return .issue(
            .noCatalogMatch,
            matchingKind.isEmpty
                ? "The active catalog returned no \(entity.kind.label.lowercased()) results."
                : "The catalog results did not match the exported title and year exactly."
        )
    }

}

private struct PreviewMergeTotals {
    var matchedCount = 0
    var addedCount = 0
    var watchedEpisodeCount = 0
    var watchEventCount = 0
    var unmatchedEpisodeCount = 0
    var listCount = 0
    var listMembershipCount = 0
    var skippedCount: Int
    var destinationCounts = Dictionary(
        uniqueKeysWithValues: ImportMetricCategory.allCases.map { ($0, 0) }
    )

    mutating func add(_ result: EntityMergeResult) {
        matchedCount += result.matchedCount
        addedCount += result.addedCount
        watchedEpisodeCount += result.watchedEpisodeCount
        watchEventCount += result.watchEventCount
        unmatchedEpisodeCount += result.unmatchedEpisodeCount
        skippedCount += result.skippedCount
        for (category, count) in result.destinationCounts {
            destinationCounts[category, default: 0] += count
        }
    }
}

private struct EntityMergeResult {
    let matchedCount: Int
    let addedCount: Int
    let watchedEpisodeCount: Int
    let watchEventCount: Int
    let skippedCount: Int
    let unmatchedEpisodeCount: Int
    let destinationCounts: [ImportMetricCategory: Int]
    let watchEvents: [SharedWatchEvent]
    let diaryEntries: [ViewingDiaryEntry]
}
