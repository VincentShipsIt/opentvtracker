import Foundation

private enum AutomaticResolutionResult: Sendable {
    case resolved(String, CatalogResolvedTitle)
    case issue(ImportResolutionIssue)
}

private enum CatalogCandidateRequestResult: Sendable {
    case candidates([MediaTitle])
    case unavailable
    case requestLimitReached
}

enum BudgetedCatalogRequest<Value: Sendable>: Sendable {
    case value(Value)
    case unavailable
    case requestLimitReached
}

private struct CatalogTitleRequestKey: Hashable, Sendable {
    let kind: MediaKind
    let catalogID: Int
    let region: StreamingRegion
}

private struct CatalogResolveRequestKey: Hashable, Sendable {
    let reference: ExternalCatalogReference
    let region: StreamingRegion
}

actor TVTimeCatalogRequestBudget {
    private let catalog: any CatalogProviding
    private var remainingRequestCount: Int
    private var searchTasks: [
        MediaSearchQuery: Task<BudgetedCatalogRequest<[MediaTitle]>, Never>
    ] = [:]
    private var titleTasks: [
        CatalogTitleRequestKey: Task<BudgetedCatalogRequest<MediaTitle>, Never>
    ] = [:]
    private var resolveTasks: [
        CatalogResolveRequestKey: Task<BudgetedCatalogRequest<MediaTitle?>, Never>
    ] = [:]

    init(
        catalog: any CatalogProviding,
        maximumRequestCount: Int = LibraryImportLimits.maximumTVTimeCatalogRequestCount
    ) {
        self.catalog = catalog
        remainingRequestCount = max(maximumRequestCount, 0)
    }

    func search(_ query: MediaSearchQuery) async -> BudgetedCatalogRequest<[MediaTitle]> {
        if let task = searchTasks[query] { return await task.value }
        guard reserveRequest() else { return .requestLimitReached }
        let catalog = catalog
        let task = Task<BudgetedCatalogRequest<[MediaTitle]>, Never> {
            do {
                return .value(try await catalog.search(query))
            } catch {
                return .unavailable
            }
        }
        searchTasks[query] = task
        return await task.value
    }

    func title(
        kind: MediaKind,
        catalogID: Int,
        region: StreamingRegion
    ) async -> BudgetedCatalogRequest<MediaTitle> {
        let key = CatalogTitleRequestKey(kind: kind, catalogID: catalogID, region: region)
        if let task = titleTasks[key] { return await task.value }
        guard reserveRequest() else { return .requestLimitReached }
        let catalog = catalog
        let task = Task<BudgetedCatalogRequest<MediaTitle>, Never> {
            do {
                return .value(
                    try await catalog.title(kind: kind, catalogID: catalogID, region: region)
                )
            } catch {
                return .unavailable
            }
        }
        titleTasks[key] = task
        return await task.value
    }

    func resolve(
        _ reference: ExternalCatalogReference,
        region: StreamingRegion
    ) async -> BudgetedCatalogRequest<MediaTitle?> {
        let key = CatalogResolveRequestKey(reference: reference, region: region)
        if let task = resolveTasks[key] { return await task.value }
        guard reserveRequest() else { return .requestLimitReached }
        let catalog = catalog
        let task = Task<BudgetedCatalogRequest<MediaTitle?>, Never> {
            do {
                return .value(try await catalog.resolve(reference, region: region))
            } catch {
                return .unavailable
            }
        }
        resolveTasks[key] = task
        return await task.value
    }

    private func reserveRequest() -> Bool {
        guard remainingRequestCount > 0 else { return false }
        remainingRequestCount -= 1
        return true
    }
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
        region: StreamingRegion,
        requestBudget: TVTimeCatalogRequestBudget
    ) async -> TVTimeTitleResolution {
        var resolution = TVTimeTitleResolution(resolved: [:], issues: [:], warnings: [])
        for batchStart in stride(from: 0, to: entities.count, by: 6) {
            let batch = Array(entities[batchStart..<min(batchStart + 6, entities.count)])
            await withTaskGroup(of: AutomaticResolutionResult.self) { group in
                for entity in batch {
                    group.addTask {
                        await resolve(
                            entity,
                            region: region,
                            requestBudget: requestBudget
                        )
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
        region: StreamingRegion,
        requestBudget: TVTimeCatalogRequestBudget
    ) async -> AutomaticResolutionResult {
        if let external = await resolveExternal(
            entity,
            region: region,
            requestBudget: requestBudget
        ) {
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
        let candidates: [MediaTitle]
        switch await searchCandidates(
            entity,
            region: region,
            requestBudget: requestBudget
        ) {
        case .candidates(let result):
            candidates = result
        case .unavailable:
            return .issue(
                resolutionIssue(
                    entity,
                    reason: .catalogUnavailable,
                    detail: "OpenTV could not reach the catalog. Retry when it is available."
                )
            )
        case .requestLimitReached:
            return .issue(automaticResolutionLimitIssue(entity))
        }
        switch CatalogImportMatcher.select(entity: entity, candidates: candidates) {
        case .issue(let reason, let detail):
            return .issue(resolutionIssue(entity, reason: reason, detail: detail))
        case .resolved(let resolved):
            return await detailedResolution(
                entity,
                resolved: resolved,
                region: region,
                requestBudget: requestBudget
            )
        }
    }

    private static func resolveExternal(
        _ entity: TVTimeEntity,
        region: StreamingRegion,
        requestBudget: TVTimeCatalogRequestBudget
    ) async -> AutomaticResolutionResult? {
        guard let source = entity.source,
              let sourceID = entity.sourceID.flatMap(Int.init),
              sourceID > 0 else { return nil }
        let reference = ExternalCatalogReference(
            source: source,
            sourceID: sourceID,
            kind: entity.kind
        )
        switch await requestBudget.resolve(reference, region: region) {
        case .value(let title?):
            return .resolved(
                entity.identity,
                CatalogResolvedTitle(title: title, seasonNumberOverride: nil)
            )
        case .value(nil):
            return nil
        case .unavailable:
            guard entity.title.isEmpty else { return nil }
            return .issue(
                resolutionIssue(
                    entity,
                    reason: .catalogUnavailable,
                    detail: "OpenTV could not resolve this legacy source ID. Retry later."
                )
            )
        case .requestLimitReached:
            return .issue(automaticResolutionLimitIssue(entity))
        }
    }

    private static func searchCandidates(
        _ entity: TVTimeEntity,
        region: StreamingRegion,
        requestBudget: TVTimeCatalogRequestBudget
    ) async -> CatalogCandidateRequestResult {
        var candidates: [MediaTitle.ID: MediaTitle] = [:]
        var completedSearch = false
        for query in CatalogImportMatcher.searchQueries(for: entity) {
            let request = MediaSearchQuery(
                text: query,
                kind: entity.kind,
                page: 1,
                region: region
            )
            switch await requestBudget.search(request) {
            case .requestLimitReached:
                return .requestLimitReached
            case .unavailable:
                continue
            case .value(let results):
                completedSearch = true
                for result in results where result.kind == entity.kind {
                    candidates[result.id] = result
                }
            }
        }
        return completedSearch ? .candidates(Array(candidates.values)) : .unavailable
    }

    private static func detailedResolution(
        _ entity: TVTimeEntity,
        resolved: CatalogResolvedTitle,
        region: StreamingRegion,
        requestBudget: TVTimeCatalogRequestBudget
    ) async -> AutomaticResolutionResult {
        let detailed: MediaTitle
        switch await requestBudget.title(
            kind: resolved.title.kind,
            catalogID: resolved.title.catalogID,
            region: region
        ) {
        case .value(let title):
            detailed = title
        case .unavailable, .requestLimitReached:
            // Detail hydration already falls back to the safe search result on provider failure.
            // Budget exhaustion uses the same compatibility-preserving path without another call.
            detailed = resolved.title
        }
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

    private static func automaticResolutionLimitIssue(
        _ entity: TVTimeEntity
    ) -> ImportResolutionIssue {
        resolutionIssue(
            entity,
            reason: .automaticResolutionLimit,
            detail: "OpenTV limited automatic catalog requests for this import. Search for this title to confirm it manually."
        )
    }
}
