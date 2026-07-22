@testable import OpenTVTracker

struct CatalogSearchStub: CatalogProviding {
    let searchHandler: @Sendable (MediaSearchQuery) async throws -> [MediaTitle]

    init(searchHandler: @escaping @Sendable (MediaSearchQuery) async throws -> [MediaTitle]) {
        self.searchHandler = searchHandler
    }

    func search(_ query: MediaSearchQuery) async throws -> [MediaTitle] {
        try await searchHandler(query)
    }

    func title(kind: MediaKind, catalogID: Int, region: StreamingRegion) async throws -> MediaTitle {
        throw CatalogServiceError.notFound
    }
}
