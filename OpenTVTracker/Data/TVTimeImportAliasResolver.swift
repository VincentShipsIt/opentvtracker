import Foundation

enum TVTimeImportAliasResolver {
    static func resolve(
        _ entities: [TVTimeEntity],
        aliases: [String: ImportResolutionAlias],
        region: StreamingRegion,
        requestBudget: TVTimeCatalogRequestBudget
    ) async -> (resolved: [String: MediaTitle], warnings: [ImportWarning]) {
        let aliasedEntities = entities.compactMap { entity -> (TVTimeEntity, ImportResolutionAlias)? in
            guard let alias = aliases[entity.identity] else { return nil }
            return (entity, alias)
        }
        var resolved: [String: MediaTitle] = [:]
        var warnings: [ImportWarning] = []

        for batchStart in stride(from: 0, to: aliasedEntities.count, by: 6) {
            let batch = Array(
                aliasedEntities[batchStart..<min(batchStart + 6, aliasedEntities.count)]
            )
            await withTaskGroup(of: AliasResolutionResult.self) { group in
                for (entity, alias) in batch {
                    group.addTask {
                        await resolve(
                            entity,
                            alias: alias,
                            region: region,
                            requestBudget: requestBudget
                        )
                    }
                }
                for await result in group {
                    switch result {
                    case .resolved(let identity, let title):
                        resolved[identity] = title
                    case .stale(let warning):
                        warnings.append(warning)
                    case .requestLimitReached:
                        break
                    }
                }
            }
        }
        return (resolved, warnings.sorted { $0.id < $1.id })
    }

    private static func resolve(
        _ entity: TVTimeEntity,
        alias: ImportResolutionAlias,
        region: StreamingRegion,
        requestBudget: TVTimeCatalogRequestBudget
    ) async -> AliasResolutionResult {
        switch await requestBudget.title(
            kind: alias.kind,
            catalogID: alias.catalogID,
            region: region
        ) {
        case .value(let title):
            // The active catalog may have changed namespace since the alias
            // was saved (TVmaze fallback vs TMDB proxy). A numeric ID from the
            // wrong namespace resolves to an unrelated title, so re-search.
            guard alias.matches(title) else {
                return .stale(staleAliasWarning(for: entity))
            }
            return .resolved(entity.identity, title)
        case .unavailable:
            return .stale(staleAliasWarning(for: entity))
        case .requestLimitReached:
            return .requestLimitReached
        }
    }

    private static func staleAliasWarning(for entity: TVTimeEntity) -> ImportWarning {
        let displayName = entity.title.isEmpty
            ? entity.sourceID.map { "\(entity.kind.label) source ID \($0)" }
                ?? "an unnamed \(entity.kind.label.lowercased())"
            : entity.title
        return ImportWarning(
            id: "stale-alias-\(entity.identity)",
            message: "A saved match for \(displayName) is no longer available. OpenTV ignored that saved match rather than trusting it."
        )
    }
}

private enum AliasResolutionResult: Sendable {
    case resolved(String, MediaTitle)
    case stale(ImportWarning)
    case requestLimitReached
}
