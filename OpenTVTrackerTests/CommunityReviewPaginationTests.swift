import Foundation
import XCTest
@testable import OpenTVTracker

final class CommunityReviewPaginationTests: XCTestCase {
    func testPaginationDeduplicatesReviewsAndStopsAtLastPage() throws {
        var pagination = CommunityReviewPagination()

        try pagination.apply(
            CommunityReviewPage(
                page: 1,
                totalPages: 2,
                results: [
                    review(id: "one"),
                    review(id: "duplicate")
                ]
            ),
            requestedPage: 1
        )
        try pagination.apply(
            CommunityReviewPage(
                page: 2,
                totalPages: 2,
                results: [
                    review(id: "duplicate"),
                    review(id: "two"),
                    review(id: "two")
                ]
            ),
            requestedPage: 2
        )

        XCTAssertEqual(pagination.reviews.map(\.id), ["one", "duplicate", "two"])
        XCTAssertEqual(pagination.loadedPages, Set([1, 2]))
        XCTAssertNil(pagination.nextPage)
    }

    func testPaginationIgnoresAnAlreadyAppliedPage() throws {
        var pagination = CommunityReviewPagination()
        let firstPage = CommunityReviewPage(
            page: 1,
            totalPages: 2,
            results: [review(id: "one")]
        )

        try pagination.apply(firstPage, requestedPage: 1)
        try pagination.apply(firstPage, requestedPage: 1)

        XCTAssertEqual(pagination.reviews.map(\.id), ["one"])
        XCTAssertEqual(pagination.nextPage, 2)
    }

    func testPaginationRejectsAnUnexpectedPage() {
        var pagination = CommunityReviewPagination()

        XCTAssertThrowsError(
            try pagination.apply(
                CommunityReviewPage(page: 2, totalPages: 2, results: []),
                requestedPage: 1
            )
        )
        XCTAssertTrue(pagination.reviews.isEmpty)
        XCTAssertEqual(pagination.nextPage, 1)
    }

    func testCatalogFallsBackWhenPrimaryReviewRequestFails() async throws {
        let fallbackPage = CommunityReviewPage(
            page: 2,
            totalPages: 3,
            results: [review(id: "fallback")]
        )
        let service = FallbackCatalogService(
            primary: ReviewCatalogStub(result: .failure(.unavailable)),
            fallback: ReviewCatalogStub(result: .success(fallbackPage))
        )

        let page = try await service.reviews(kind: .series, catalogID: 42, page: 2)

        XCTAssertEqual(page.page, fallbackPage.page)
        XCTAssertEqual(page.totalPages, fallbackPage.totalPages)
        XCTAssertEqual(page.results.map(\.id), ["fallback"])
    }

    private func review(id: String) -> CommunityReview {
        CommunityReview(
            id: id,
            author: "Reviewer",
            excerpt: "Review \(id)",
            rating: 8,
            source: "TMDB",
            containsSpoilers: true
        )
    }
}

private struct ReviewCatalogStub: CatalogProviding {
    let result: Result<CommunityReviewPage, CatalogServiceError>

    func search(_: MediaSearchQuery) async throws -> [MediaTitle] {
        throw CatalogServiceError.notFound
    }

    func title(kind _: MediaKind, catalogID _: Int, region _: StreamingRegion) async throws -> MediaTitle {
        throw CatalogServiceError.notFound
    }

    func reviews(kind _: MediaKind, catalogID _: Int, page _: Int) async throws -> CommunityReviewPage {
        try result.get()
    }
}
