@testable import OpenTVTracker

struct CancellingCatalog: CatalogProviding {
    func search(_: MediaSearchQuery) async throws -> [MediaTitle] {
        throw CancellationError()
    }

    func title(kind _: MediaKind, catalogID _: Int, region _: StreamingRegion) async throws -> MediaTitle {
        throw CancellationError()
    }
}

actor ControlledResolutionCatalog: CatalogProviding {
    let titles: [MediaTitle]
    private(set) var requestedCatalogIDs: [Int] = []
    private var releasedCatalogIDs: Set<Int> = []

    init(titles: [MediaTitle]) {
        self.titles = titles
    }

    func search(_: MediaSearchQuery) async throws -> [MediaTitle] {
        []
    }

    func title(
        kind: MediaKind,
        catalogID: Int,
        region _: StreamingRegion
    ) async throws -> MediaTitle {
        requestedCatalogIDs.append(catalogID)
        while !releasedCatalogIDs.contains(catalogID) {
            try Task.checkCancellation()
            await Task.yield()
        }
        guard let title = titles.first(where: {
            $0.kind == kind && $0.catalogID == catalogID
        }) else {
            throw CatalogServiceError.notFound
        }
        return title
    }

    func waitUntilRequested(catalogID: Int) async {
        while !requestedCatalogIDs.contains(catalogID) {
            await Task.yield()
        }
    }

    func hasRequested(catalogID: Int) -> Bool {
        requestedCatalogIDs.contains(catalogID)
    }

    func release(catalogID: Int) {
        releasedCatalogIDs.insert(catalogID)
    }
}
