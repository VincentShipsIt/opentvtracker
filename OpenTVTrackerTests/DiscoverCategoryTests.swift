import XCTest
@testable import OpenTVTracker

final class DiscoverCategoryTests: XCTestCase {
    func testScienceFictionIsSortedNewestFirst() {
        let titles = DiscoverCategory.scienceFiction.titles(from: LibrarySnapshot.sample.titles)

        XCTAssertEqual(titles.first?.id, "fallout")
        XCTAssertEqual(titles.map(\.year), titles.map(\.year).sorted(by: >))
    }

    func testCategoriesExcludeCompletedTitles() {
        let movies = DiscoverCategory.movies.titles(from: LibrarySnapshot.sample.titles)

        XCTAssertFalse(movies.contains(where: { $0.state == .completed }))
    }

    func testAvailableCategoriesAlwaysHaveAnIllustratedLatestTitle() {
        let sections = DiscoverCategorySection.available(in: LibrarySnapshot.sample.titles)

        XCTAssertFalse(sections.isEmpty)
        XCTAssertTrue(sections.allSatisfy { $0.latestTitle != nil })
    }
}
