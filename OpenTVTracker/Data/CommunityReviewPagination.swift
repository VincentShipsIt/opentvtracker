import Foundation

struct CommunityReviewPagination: Hashable, Sendable {
    private(set) var reviews: [CommunityReview] = []
    private(set) var loadedPages: Set<Int> = []
    private(set) var nextPage: Int? = 1

    mutating func apply(_ response: CommunityReviewPage, requestedPage: Int) throws {
        guard response.page == requestedPage else {
            throw CommunityReviewPaginationError.unexpectedPage
        }
        guard !loadedPages.contains(response.page) else { return }

        var seenIDs = Set(reviews.map(\.id))
        reviews.append(contentsOf: response.results.filter { seenIDs.insert($0.id).inserted })
        loadedPages.insert(response.page)

        let boundedTotalPages = min(max(response.totalPages, response.page), 100)
        nextPage = response.page < boundedTotalPages ? response.page + 1 : nil
    }
}

enum CommunityReviewPaginationError: LocalizedError {
    case unexpectedPage

    var errorDescription: String? {
        "The review service returned an unexpected page. Try again."
    }
}
