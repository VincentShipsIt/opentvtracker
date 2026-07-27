import Foundation

struct DiscoveryCatalogPagination: Hashable, Sendable {
    static let maximumPage = 20

    private(set) var titles: [MediaTitle] = []
    private(set) var loadedPages: Set<Int> = []
    private(set) var nextPage: Int? = 1

    @discardableResult
    mutating func apply(_ results: [MediaTitle], requestedPage: Int) throws -> Int {
        guard requestedPage == nextPage else {
            throw DiscoveryCatalogPaginationError.unexpectedPage
        }
        guard !loadedPages.contains(requestedPage) else { return 0 }

        var seenIDs = Set(titles.map(\.id))
        let uniqueResults = results.filter { seenIDs.insert($0.id).inserted }
        titles.append(contentsOf: uniqueResults)
        loadedPages.insert(requestedPage)
        // The TVMaze fallback filters each raw page to English titles. A valid page can
        // therefore become empty without meaning the remote catalog is exhausted.
        nextPage = requestedPage >= Self.maximumPage ? nil : requestedPage + 1
        return uniqueResults.count
    }

    mutating func markExhausted() {
        nextPage = nil
    }
}

enum DiscoveryCatalogPaginationError: LocalizedError {
    case unexpectedPage

    var errorDescription: String? {
        "The catalog returned an unexpected page. Try again."
    }
}
