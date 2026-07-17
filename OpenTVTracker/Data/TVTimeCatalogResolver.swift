import Foundation

struct TVTimeTitleResolution: Sendable {
    var resolved: [String: CatalogResolvedTitle]
    var issues: [String: ImportResolutionIssue]
}

enum TVTimeCatalogResolver {
    static func resolveTitles(
        _ entities: [TVTimeEntity],
        current: LibrarySnapshot,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async -> TVTimeTitleResolution {
        let local = localResolution(entities, current: current)
        let remote = await resolveRemote(
            local.unresolved,
            catalog: catalog,
            region: region
        )
        var resolved = local.resolved
        resolved.merge(remote.resolved) { _, remoteTitle in remoteTitle }
        return TVTimeTitleResolution(resolved: resolved, issues: remote.issues)
    }

    private static func localResolution(
        _ entities: [TVTimeEntity],
        current: LibrarySnapshot
    ) -> (resolved: [String: CatalogResolvedTitle], unresolved: [TVTimeEntity]) {
        var resolved: [String: CatalogResolvedTitle] = [:]
        var unresolved: [TVTimeEntity] = []
        let aliases = current.importResolutionAliases ?? [:]
        let seasonOverrides = current.importResolutionSeasonOverrides ?? [:]

        for entity in entities {
            let local = aliases[entity.identity].flatMap { titleID in
                current.titles.first { $0.id == titleID }
            } ?? current.titles.first {
                CatalogImportMatcher.matches($0, entity: entity)
            }
            if let local {
                resolved[entity.identity] = CatalogResolvedTitle(
                    title: local,
                    seasonNumberOverride: seasonOverrides[entity.identity]
                )
            } else {
                unresolved.append(entity)
            }
        }
        return (resolved, unresolved)
    }

    private static func resolveRemote(
        _ entities: [TVTimeEntity],
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async -> TVTimeTitleResolution {
        var resolution = TVTimeTitleResolution(resolved: [:], issues: [:])
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

    private static func resolve(
        _ entity: TVTimeEntity,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async -> AutomaticResolutionResult {
        if let external = await resolveExternal(entity, catalog: catalog, region: region) {
            return external
        }
        guard !entity.title.isEmpty else {
            return .issue(
                issue(
                    entity,
                    reason: .noCatalogMatch,
                    detail: "This record has no title and its source identifier did not resolve."
                )
            )
        }
        guard let candidates = await searchCandidates(
            entity,
            catalog: catalog,
            region: region
        ) else {
            return .issue(
                issue(
                    entity,
                    reason: .catalogUnavailable,
                    detail: "OpenTV could not reach the catalog. Retry or choose a match when it is available."
                )
            )
        }

        switch CatalogImportMatcher.select(entity: entity, candidates: candidates) {
        case .issue(let reason, let detail):
            return .issue(issue(entity, reason: reason, detail: detail))
        case .resolved(let resolved):
            return await detailedResolution(
                entity,
                resolved: resolved,
                catalog: catalog,
                region: region
            )
        }
    }

    private static func resolveExternal(
        _ entity: TVTimeEntity,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async -> AutomaticResolutionResult? {
        guard let source = entity.source,
              let sourceID = entity.sourceID.flatMap(Int.init),
              sourceID > 0 else {
            return nil
        }
        do {
            let reference = ExternalCatalogReference(
                source: source,
                sourceID: sourceID,
                kind: entity.kind
            )
            guard let title = try await catalog.resolve(reference, region: region) else {
                return nil
            }
            return .resolved(
                entity.identity,
                CatalogResolvedTitle(title: title, seasonNumberOverride: nil)
            )
        } catch {
            guard entity.title.isEmpty else { return nil }
            return .issue(
                issue(
                    entity,
                    reason: .catalogUnavailable,
                    detail: "OpenTV could not resolve this legacy source ID. Retry when the catalog is available."
                )
            )
        }
    }

    private static func searchCandidates(
        _ entity: TVTimeEntity,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async -> [MediaTitle]? {
        var candidates: [MediaTitle.ID: MediaTitle] = [:]
        var completedSearch = false
        for query in CatalogImportMatcher.searchQueries(for: entity) {
            guard let results = try? await catalog.search(
                MediaSearchQuery(text: query, kind: entity.kind, page: 1, region: region)
            ) else {
                continue
            }
            completedSearch = true
            for result in results where result.kind == entity.kind {
                candidates[result.id] = result
            }
        }
        return completedSearch ? Array(candidates.values) : nil
    }

    private static func detailedResolution(
        _ entity: TVTimeEntity,
        resolved: CatalogResolvedTitle,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async -> AutomaticResolutionResult {
        let detailed = (try? await catalog.title(
            kind: resolved.title.kind,
            catalogID: resolved.title.catalogID,
            region: region
        )) ?? resolved.title
        return .resolved(
            entity.identity,
            CatalogResolvedTitle(
                title: detailed,
                seasonNumberOverride: resolved.seasonNumberOverride
            )
        )
    }

    private static func issue(
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
}

private enum AutomaticResolutionResult: Sendable {
    case resolved(String, CatalogResolvedTitle)
    case issue(ImportResolutionIssue)
}
