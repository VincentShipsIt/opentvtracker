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

    func testCategoriesKeepDismissedAndDislikedTitlesBrowsable() throws {
        var catalog = LibrarySnapshot.sample.titles
        let index = try XCTUnwrap(catalog.firstIndex(where: { $0.kind == .movie && $0.state != .completed }))
        catalog[index].isDismissed = true
        catalog[index].isDisliked = true

        let movies = DiscoverCategory.movies.titles(from: catalog)

        XCTAssertTrue(movies.contains(where: { $0.id == catalog[index].id }))
    }

    func testTopRatedIsSortedByRating() {
        let titles = DiscoverCategory.topRated.titles(from: LibrarySnapshot.sample.titles)

        XCTAssertFalse(titles.isEmpty)
        XCTAssertEqual(titles.map(\.rating), titles.map(\.rating).sorted(by: >))
        XCTAssertTrue(titles.allSatisfy { $0.rating >= 7.5 })
    }

    func testAvailableCategoriesUseDistinctLeadTitles() {
        let sections = DiscoverCategorySection.available(in: LibrarySnapshot.sample.titles)
        let leadTitleIDs = sections.compactMap(\.leadTitle?.id)

        XCTAssertFalse(sections.isEmpty)
        XCTAssertEqual(Set(leadTitleIDs).count, leadTitleIDs.count)
    }

    func testAvailableCategoriesExcludeFeaturedTitleFromLeads() throws {
        let originalSections = DiscoverCategorySection.available(in: LibrarySnapshot.sample.titles)
        let featuredTitleID = try XCTUnwrap(originalSections.compactMap(\.leadTitle?.id).first)

        let sections = DiscoverCategorySection.available(
            in: LibrarySnapshot.sample.titles,
            excludingLeadTitleIDs: [featuredTitleID]
        )

        XCTAssertFalse(sections.compactMap(\.leadTitle?.id).contains(featuredTitleID))
    }

    func testLeadDeduplicationPreservesCategoryOrdering() throws {
        let sections = DiscoverCategorySection.available(in: LibrarySnapshot.sample.titles)
        let scienceFiction = try XCTUnwrap(
            sections.first(where: { $0.category == .scienceFiction })
        )

        XCTAssertEqual(
            scienceFiction.titles,
            DiscoverCategory.scienceFiction.titles(from: LibrarySnapshot.sample.titles)
        )
    }
}
