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
