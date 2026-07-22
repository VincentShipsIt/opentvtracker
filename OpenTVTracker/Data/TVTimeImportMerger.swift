import Foundation

struct TVTimeTitleResolution: Sendable {
    var resolved: [String: CatalogResolvedTitle]
    var issues: [String: ImportResolutionIssue]
    var warnings: [ImportWarning]
}

enum TVTimeImportMerger {
    static func resolveTitles(
        _ entities: [TVTimeEntity],
        current: LibrarySnapshot,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async -> TVTimeTitleResolution {
        var resolved: [String: CatalogResolvedTitle] = [:]
        var issues: [String: ImportResolutionIssue] = [:]
        var warnings: [ImportWarning] = []
        var unresolved: [TVTimeEntity] = []
        let currentTitles = TVTimeMediaTitleLookup(current.titles)
        let aliases = current.importResolutionAliases ?? [:]
        var aliasTitles: [String: MediaTitle] = [:]
        for entity in entities {
            guard let alias = aliases[entity.identity],
                  let localTitle = current.titles.first(where: {
                      $0.kind == alias.kind && $0.catalogID == alias.catalogID
                  }) else { continue }
            aliasTitles[entity.identity] = localTitle
        }

        let aliasResolution = await TVTimeImportAliasResolver.resolve(
            entities.filter { aliasTitles[$0.identity] == nil },
            aliases: aliases,
            catalog: catalog,
            region: region
        )
        aliasTitles.merge(aliasResolution.resolved) { _, remoteTitle in remoteTitle }
        let validatedAliases = TVTimeCatalogResolver.validatedAliases(
            entities,
            resolved: aliasTitles,
            warnings: aliasResolution.warnings
        )
        resolved = validatedAliases.resolved
        warnings = validatedAliases.warnings

        for entity in entities {
            if resolved[entity.identity] != nil {
                continue
            }
            if let localIndex = currentTitles.index(matching: entity) {
                resolved[entity.identity] = CatalogResolvedTitle(
                    title: current.titles[localIndex],
                    seasonNumberOverride: nil
                )
            } else {
                unresolved.append(entity)
            }
        }

        let catalogResolution = await TVTimeCatalogResolver.resolveTitles(
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
        cacheResolutionAliases(archive.entities, resolved: resolved, in: &snapshot)
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
        resolved: inout [String: CatalogResolvedTitle],
        issues: inout [String: ImportResolutionIssue],
        snapshot: inout LibrarySnapshot
    ) {
        for (identity, title) in manualResolutions {
            let seasonNumber = CatalogImportMatcher.safeAnimeSeasonNumber(
                in: issues[identity]?.title ?? ""
            )
            let safeOverride = seasonNumber.flatMap { number in
                title.seasons?.contains(where: { $0.number == number }) == true ? number : nil
            }
            resolved[identity] = CatalogResolvedTitle(
                title: title,
                seasonNumberOverride: safeOverride
            )
            issues.removeValue(forKey: identity)
            var aliases = snapshot.importResolutionAliases ?? [:]
            aliases[identity] = ImportResolutionAlias(kind: title.kind, catalogID: title.catalogID)
            snapshot.importResolutionAliases = aliases
        }
    }

    private static func cacheResolutionAliases(
        _ entities: [TVTimeEntity],
        resolved: [String: CatalogResolvedTitle],
        in snapshot: inout LibrarySnapshot
    ) {
        var aliases = snapshot.importResolutionAliases ?? [:]
        for entity in entities {
            guard let title = resolved[entity.identity]?.title else { continue }
            aliases[entity.identity] = ImportResolutionAlias(
                kind: title.kind,
                catalogID: title.catalogID
            )
        }
        snapshot.importResolutionAliases = aliases.isEmpty ? nil : aliases
    }

    private static func mergeArchive(
        _ archive: TVTimeArchive,
        resolved: [String: CatalogResolvedTitle],
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
            resolved: resolved.mapValues(\.title)
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
        resolved: [String: CatalogResolvedTitle],
        state: inout TVTimeMergeState,
        shouldShare: Bool
    ) -> EntityMergeResult? {
        guard let resolvedTitle = resolved[entity.identity] else { return nil }
        var catalogTitle = resolvedTitle.title
        let existingIndex = state.titleLookup.index(for: catalogTitle, matching: entity)
        if let existingIndex {
            catalogTitle = snapshot.titles[existingIndex]
        }

        let applied = TVTimeHistoryApplier.apply(
            entity,
            to: &catalogTitle,
            state: &state,
            seasonNumberOverride: resolvedTitle.seasonNumberOverride
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
