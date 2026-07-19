import Foundation

enum TVTimeImportAliasResolver {
    static func resolve(
        _ entities: [TVTimeEntity],
        aliases: [String: ImportResolutionAlias],
        catalog: any CatalogProviding,
        region: StreamingRegion
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
                            catalog: catalog,
                            region: region
                        )
                    }
                }
                for await result in group {
                    switch result {
                    case .resolved(let identity, let title):
                        resolved[identity] = title
                    case .stale(let warning):
                        warnings.append(warning)
                    }
                }
            }
        }
        return (resolved, warnings.sorted { $0.id < $1.id })
    }

    private static func resolve(
        _ entity: TVTimeEntity,
        alias: ImportResolutionAlias,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async -> AliasResolutionResult {
        do {
            let title = try await catalog.title(
                kind: alias.kind,
                catalogID: alias.catalogID,
                region: region
            )
            return .resolved(entity.identity, title)
        } catch {
            let displayName = entity.title.isEmpty
                ? entity.sourceID.map { "\(entity.kind.label) source ID \($0)" }
                    ?? "an unnamed \(entity.kind.label.lowercased())"
                : entity.title
            return .stale(
                ImportWarning(
                    id: "stale-alias-\(entity.identity)",
                    message: "A saved match for \(displayName) is no longer available. OpenTV searched the catalog again."
                )
            )
        }
    }
}

private enum AliasResolutionResult: Sendable {
    case resolved(String, MediaTitle)
    case stale(ImportWarning)
}
