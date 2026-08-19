import XCTest
@testable import OpenTVTracker

@MainActor
final class TitleSimilarityTests: XCTestCase {
    func testStrongestSharedGenresRankFirst() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)

        let matches = model.moreLikeThis("severance")

        XCTAssertEqual(matches.first?.title.id, "stranger-things")
        XCTAssertEqual(matches.first?.reason, "Shares Drama + Mystery")
    }

    func testMatchesExcludeSourceCompletedTitlesAndUnavailableServices() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)

        let matches = model.moreLikeThis("severance")

        XCTAssertFalse(matches.contains(where: { $0.title.id == "severance" }))
        XCTAssertFalse(matches.contains(where: { $0.title.state == .completed }))
        XCTAssertTrue(matches.allSatisfy { model.isAvailableOnSelectedProviders($0.title) })
    }

    func testChangingSubscriptionsImmediatelyChangesMatches() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)
        XCTAssertTrue(model.moreLikeThis("severance").contains(where: { $0.title.id == "stranger-things" }))

        model.toggleProvider(StreamingProvider.netflix.id)

        XCTAssertFalse(model.moreLikeThis("severance").contains(where: { $0.title.id == "stranger-things" }))
    }

    func testDismissedTitlesRemainBrowsableInMoreLikeThis() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)
        model.setRecommendationDismissed(true, for: "stranger-things")

        XCTAssertTrue(model.moreLikeThis("severance").contains(where: { $0.title.id == "stranger-things" }))
    }

    func testSearchOnlySourceReturnsMatchesFromSeededCatalog() async {
        let catalogOnly = MediaTitle(
            id: "search-only-mystery",
            catalogID: 88_001,
            title: "Search Only Mystery",
            year: 2024,
            kind: .series,
            synopsis: "A catalog-only title used to verify More Like This does not require a library row.",
            genres: ["Drama", "Mystery", "Sci-Fi"],
            runtimeMinutes: 52,
            state: .planned,
            progress: nil,
            rating: 8.4,
            nextReleaseDescription: nil,
            recommendationReason: nil,
            mood: .thoughtful,
            palette: PosterPalette(primaryHex: "245C7A", secondaryHex: "101A2B"),
            providers: [.appleTV],
            reviews: []
        )
        let sampleTitles = LibrarySnapshot.sample.titles
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: LocalCatalogService(titles: sampleTitles + [catalogOnly]),
            seed: .sample
        )

        await model.searchCatalog(text: "Search Only Mystery")

        XCTAssertNil(model.titleIndex(for: catalogOnly.id))
        XCTAssertEqual(model.mediaTitle(withID: catalogOnly.id)?.id, catalogOnly.id)

        let matches = model.moreLikeThis(catalogOnly.id)

        XCTAssertFalse(matches.isEmpty)
        XCTAssertTrue(matches.contains(where: { $0.title.id == "stranger-things" }))
    }
}
