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
}
