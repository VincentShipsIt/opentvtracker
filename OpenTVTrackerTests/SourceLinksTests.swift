import Foundation
import XCTest
@testable import OpenTVTracker

final class SourceLinksTests: XCTestCase {
    func testTMDBLinksUseDistinctMediaNamespaces() {
        XCTAssertEqual(
            SourceLinks.tmdb(kind: .movie, catalogID: 123)?.absoluteString,
            "https://www.themoviedb.org/movie/123"
        )
        XCTAssertEqual(
            SourceLinks.tmdb(kind: .series, catalogID: 123)?.absoluteString,
            "https://www.themoviedb.org/tv/123"
        )
    }

    func testIMDbSearchEncodesTitleAndYear() throws {
        let url = try XCTUnwrap(SourceLinks.imdbSearch(title: "The Bear", year: 2022))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "q" })?
            .value

        XCTAssertEqual(query, "The Bear 2022")
    }
}
