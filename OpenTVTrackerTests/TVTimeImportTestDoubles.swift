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

actor StubCatalog: CatalogProviding {
    private let searchResults: [MediaTitle]
    private let resolvedTitle: MediaTitle?
    private let failsAllRequests: Bool
    private var searchCallCount = 0
    private var resolveCallCount = 0

    init(
        searchResults: [MediaTitle] = [],
        resolvedTitle: MediaTitle? = nil,
        failsAllRequests: Bool = false
    ) {
        self.searchResults = searchResults
        self.resolvedTitle = resolvedTitle
        self.failsAllRequests = failsAllRequests
    }

    func search(_: MediaSearchQuery) async throws -> [MediaTitle] {
        searchCallCount += 1
        if failsAllRequests { throw StubCatalogError.unavailable }
        return searchResults
    }

    func title(
        kind: MediaKind,
        catalogID: Int,
        region _: StreamingRegion
    ) async throws -> MediaTitle {
        if failsAllRequests { throw StubCatalogError.unavailable }
        if let resolvedTitle,
           resolvedTitle.kind == kind,
           resolvedTitle.catalogID == catalogID {
            return resolvedTitle
        }
        guard let title = searchResults.first(where: {
            $0.kind == kind && $0.catalogID == catalogID
        }) else {
            throw CatalogServiceError.notFound
        }
        return title
    }

    func resolve(
        _: ExternalCatalogReference,
        region _: StreamingRegion
    ) async throws -> MediaTitle? {
        resolveCallCount += 1
        if failsAllRequests { throw StubCatalogError.unavailable }
        return resolvedTitle
    }

    func callCounts() -> (search: Int, resolve: Int) {
        (searchCallCount, resolveCallCount)
    }
}

enum StubCatalogError: Error {
    case unavailable
}
