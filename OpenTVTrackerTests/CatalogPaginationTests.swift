import XCTest
@testable import OpenTVTracker

@MainActor
final class CatalogPaginationTests: XCTestCase {
    func testPaginationCanRetryAfterFailure() async throws {
        let firstPageTitle = try XCTUnwrap(
            LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" })
        )
        let secondPageTitle = try XCTUnwrap(
            LibrarySnapshot.sample.titles.first(where: { $0.id == "fallout" })
        )
        let service = CatalogPaginationRetryStub(
            firstPage: Array(repeating: firstPageTitle, count: 20),
            secondPage: [secondPageTitle]
        )
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: service,
            seed: .sample
        )

        await model.searchCatalog(text: "series")
        await model.loadMoreCatalogResults(text: "series")

        XCTAssertEqual(model.catalogSearchError, CatalogServiceError.unavailable.localizedDescription)
        XCTAssertEqual(model.catalogSearchPage, 1)
        XCTAssertTrue(model.hasMoreCatalogResults)

        await model.loadMoreCatalogResults(text: "series")

        XCTAssertNil(model.catalogSearchError)
        XCTAssertEqual(model.catalogSearchPage, 2)
        XCTAssertEqual(model.catalogSearchResults.last?.id, secondPageTitle.id)
        XCTAssertFalse(model.hasMoreCatalogResults)
    }
}

private actor CatalogPaginationRetryStub: CatalogProviding {
    private let firstPage: [MediaTitle]
    private let secondPage: [MediaTitle]
    private var secondPageAttempts = 0

    init(firstPage: [MediaTitle], secondPage: [MediaTitle]) {
        self.firstPage = firstPage
        self.secondPage = secondPage
    }

    func search(_ query: MediaSearchQuery) async throws -> [MediaTitle] {
        guard query.page > 1 else { return firstPage }
        secondPageAttempts += 1
        if secondPageAttempts == 1 {
            throw CatalogServiceError.unavailable
        }
        return secondPage
    }

    func title(kind: MediaKind, catalogID: Int, region: StreamingRegion) async throws -> MediaTitle {
        throw CatalogServiceError.notFound
    }
}
