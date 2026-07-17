import Foundation

actor TVTimeImportSession {
    private let archive: TVTimeArchive
    private let current: LibrarySnapshot
    private let catalog: any CatalogProviding
    private let region: StreamingRegion
    private var automaticResolution: TVTimeTitleResolution?
    private var automaticResolutionTask: Task<TVTimeTitleResolution, Never>?

    init(
        archive: TVTimeArchive,
        current: LibrarySnapshot,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) {
        self.archive = archive
        self.current = current
        self.catalog = catalog
        self.region = region
    }

    func preview(
        manualResolutions: [ImportResolutionIssue.ID: MediaTitle] = [:]
    ) async -> LibraryImportPreview {
        let resolution = await resolvedTitles()
        return TVTimeImportMerger.mergedPreview(
            archive,
            into: current,
            automaticResolution: resolution,
            manualResolutions: manualResolutions
        )
    }

    func search(_ text: String, kind: MediaKind) async throws -> [MediaTitle] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let results = try await catalog.search(
            MediaSearchQuery(text: trimmed, kind: kind, page: 1, region: region)
        )
        var seen = Set<MediaTitle.ID>()
        return results.filter { $0.kind == kind && seen.insert($0.id).inserted }
    }

    func detailedTitle(_ candidate: MediaTitle) async -> MediaTitle {
        (try? await catalog.title(
            kind: candidate.kind,
            catalogID: candidate.catalogID,
            region: region
        )) ?? candidate
    }

    private func resolvedTitles() async -> TVTimeTitleResolution {
        if let automaticResolution { return automaticResolution }
        if let automaticResolutionTask { return await automaticResolutionTask.value }

        let entities = archive.entities
        let current = self.current
        let catalog = self.catalog
        let region = self.region
        let task = Task {
            await TVTimeCatalogResolver.resolveTitles(
                entities,
                current: current,
                catalog: catalog,
                region: region
            )
        }
        automaticResolutionTask = task
        let resolved = await task.value
        automaticResolution = resolved
        automaticResolutionTask = nil
        return resolved
    }
}
