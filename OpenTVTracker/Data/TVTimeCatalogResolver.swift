import Foundation

private enum AutomaticResolutionResult: Sendable {
    case resolved(String, CatalogResolvedTitle)
    case issue(ImportResolutionIssue)
}

enum TVTimeCatalogResolver {
    static func validatedAliases(
        _ entities: [TVTimeEntity],
        resolved aliasTitles: [String: MediaTitle],
        warnings initialWarnings: [ImportWarning]
    ) -> TVTimeTitleResolution {
        var resolved: [String: CatalogResolvedTitle] = [:]
        var warnings = initialWarnings
        for entity in entities {
            guard let title = aliasTitles[entity.identity] else { continue }
            let seasonNumber = CatalogImportMatcher.safeAnimeSeasonNumber(in: entity.title)
            if let seasonNumber,
               title.seasons?.contains(where: { $0.number == seasonNumber }) != true {
                warnings.append(
                    ImportWarning(
                        id: "unsafe-alias-\(entity.identity)",
                        message: "The saved match no longer contains Season \(seasonNumber). Confirm the release."
                    )
                )
                continue
            }
            resolved[entity.identity] = CatalogResolvedTitle(
                title: title,
                seasonNumberOverride: seasonNumber
            )
        }
        return TVTimeTitleResolution(resolved: resolved, issues: [:], warnings: warnings)
    }

    static func resolveTitles(
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
                resolutionIssue(
                    entity,
                    reason: .missingTitle,
                    detail: "This record has no title and its source identifier did not resolve."
                )
            )
        }
        guard let candidates = await searchCandidates(entity, catalog: catalog, region: region) else {
            return .issue(
                resolutionIssue(
                    entity,
                    reason: .catalogUnavailable,
                    detail: "OpenTV could not reach the catalog. Retry when it is available."
                )
            )
        }
        switch CatalogImportMatcher.select(entity: entity, candidates: candidates) {
        case .issue(let reason, let detail):
            return .issue(resolutionIssue(entity, reason: reason, detail: detail))
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
              sourceID > 0 else { return nil }
        do {
            let reference = ExternalCatalogReference(
                source: source,
                sourceID: sourceID,
                kind: entity.kind
            )
            guard let title = try await catalog.resolve(reference, region: region) else { return nil }
            return .resolved(
                entity.identity,
                CatalogResolvedTitle(title: title, seasonNumberOverride: nil)
            )
        } catch {
            guard entity.title.isEmpty else { return nil }
            return .issue(
                resolutionIssue(
                    entity,
                    reason: .catalogUnavailable,
                    detail: "OpenTV could not resolve this legacy source ID. Retry later."
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
            ) else { continue }
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
        if let seasonNumber = resolved.seasonNumberOverride,
           detailed.seasons?.contains(where: { $0.number == seasonNumber }) != true {
            return .issue(
                resolutionIssue(
                    entity,
                    reason: .unsafeAnimeRelation,
                    detail: "The catalog title lacks Season \(seasonNumber). Choose the intended release."
                )
            )
        }
        return .resolved(
            entity.identity,
            CatalogResolvedTitle(
                title: detailed,
                seasonNumberOverride: resolved.seasonNumberOverride
            )
        )
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
}
