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

    func testDiscoveryCatalogLoadsWithoutSearchDeduplicatesAndRetries() async throws {
        let severance = try sampleTitle(id: "severance")
        let theBear = try sampleTitle(id: "the-bear")
        let fallout = try sampleTitle(id: "fallout")
        let slowHorses = try sampleTitle(id: "slow-horses")
        let service = DiscoveryCatalogPaginationStub(
            pages: [
                1: [severance, theBear],
                2: [theBear, fallout],
                3: [fallout, slowHorses],
            ],
            pageThatFailsOnce: 3,
            notFoundPage: 4
        )
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: service,
            seed: .empty
        )

        await model.refreshDiscoveryCatalog()

        XCTAssertEqual(model.discoveryCatalogTitles.map(\.id), [
            severance.id,
            theBear.id,
            fallout.id,
        ])
        XCTAssertEqual(model.discoveryCatalogPagination.nextPage, 3)
        XCTAssertTrue(model.hasMoreDiscoveryCatalogTitles)

        await model.loadMoreDiscoveryCatalog()

        XCTAssertEqual(model.discoveryCatalogError, CatalogServiceError.unavailable.localizedDescription)
        XCTAssertEqual(model.discoveryCatalogPagination.nextPage, 3)

        await model.loadMoreDiscoveryCatalog()

        XCTAssertNil(model.discoveryCatalogError)
        XCTAssertEqual(model.discoveryCatalogTitles.map(\.id), [
            severance.id,
            theBear.id,
            fallout.id,
            slowHorses.id,
        ])
        XCTAssertEqual(model.discoveryCatalogPagination.nextPage, 4)
        XCTAssertEqual(model.mediaTitle(withID: slowHorses.id)?.id, slowHorses.id)
        XCTAssertNotNil(model.trackableTitleIndex(for: slowHorses.id))

        await model.loadMoreDiscoveryCatalog()

        XCTAssertFalse(model.hasMoreDiscoveryCatalogTitles)
        let requestedPages = await service.requestedPages()
        XCTAssertEqual(requestedPages, [1, 2, 3, 3, 4])
    }

    func testDiscoveryPaginationContinuesPastEmptyFilteredPages() throws {
        let severance = try sampleTitle(id: "severance")
        var pagination = DiscoveryCatalogPagination()

        try pagination.apply([], requestedPage: 1)
        XCTAssertEqual(pagination.nextPage, 2)

        try pagination.apply([], requestedPage: 2)
        XCTAssertEqual(pagination.nextPage, 3)

        try pagination.apply([severance], requestedPage: 3)
        XCTAssertEqual(pagination.titles.map(\.id), [severance.id])
        XCTAssertEqual(pagination.nextPage, 4)

        pagination.markExhausted()
        XCTAssertNil(pagination.nextPage)
    }

    func testDiscoveryCatalogSurfacesIndexFailureAndRetriesPageTwo() async throws {
        let severance = try sampleTitle(id: "severance")
        let fallout = try sampleTitle(id: "fallout")
        let service = DiscoveryCatalogPaginationStub(
            pages: [
                1: [severance],
                2: [fallout],
            ],
            pageThatFailsOnce: 2,
            notFoundPage: 3
        )
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: service,
            seed: .empty
        )

        await model.refreshDiscoveryCatalog()

        XCTAssertEqual(model.discoveryCatalogError, CatalogServiceError.unavailable.localizedDescription)
        XCTAssertEqual(model.discoveryCatalogPagination.nextPage, 2)

        await model.loadMoreDiscoveryCatalog()

        XCTAssertNil(model.discoveryCatalogError)
        XCTAssertEqual(model.discoveryCatalogTitles.map(\.id), [severance.id, fallout.id])
        XCTAssertEqual(model.discoveryCatalogPagination.nextPage, 3)
    }

    private func sampleTitle(id: MediaTitle.ID) throws -> MediaTitle {
        try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == id }))
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

private actor DiscoveryCatalogPaginationStub: CatalogProviding {
    private let pages: [Int: [MediaTitle]]
    private let pageThatFailsOnce: Int
    private let notFoundPage: Int?
    private var failedPages: Set<Int> = []
    private var requests: [Int] = []

    init(
        pages: [Int: [MediaTitle]],
        pageThatFailsOnce: Int,
        notFoundPage: Int? = nil
    ) {
        self.pages = pages
        self.pageThatFailsOnce = pageThatFailsOnce
        self.notFoundPage = notFoundPage
    }

    func search(_ query: MediaSearchQuery) async throws -> [MediaTitle] {
        requests.append(query.page)
        if query.page == pageThatFailsOnce, failedPages.insert(query.page).inserted {
            throw CatalogServiceError.unavailable
        }
        if query.page == notFoundPage {
            throw CatalogServiceError.notFound
        }
        return pages[query.page] ?? []
    }

    func title(kind: MediaKind, catalogID: Int, region: StreamingRegion) async throws -> MediaTitle {
        throw CatalogServiceError.notFound
    }

    func requestedPages() -> [Int] {
        requests
    }
}
