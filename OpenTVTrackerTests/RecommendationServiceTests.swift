import XCTest
@testable import OpenTVTracker

final class RecommendationServiceTests: XCTestCase {
    func testRankingIsReproducibleAndExplained() {
        let context = RecommendationContext(
            mood: .any,
            maximumRuntimeMinutes: nil,
            sharedSpaceID: LibrarySnapshot.sample.sharedSpace.id
        )

        let first = DeterministicRecommendationEngine.rank(snapshot: .sample, context: context)
        let second = DeterministicRecommendationEngine.rank(snapshot: .sample, context: context)

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.allSatisfy { !$0.reason.isEmpty })
    }

    func testRankingHonorsRuntimeProvidersAndFeedbackExclusions() throws {
        var snapshot = LibrarySnapshot.sample
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "slow-horses" }))
        snapshot.titles[index].isDisliked = true
        snapshot.selectedProviderIDs = [StreamingProvider.appleTV.id, StreamingProvider.primeVideo.id]
        let context = RecommendationContext(
            mood: .any,
            maximumRuntimeMinutes: 55,
            sharedSpaceID: snapshot.sharedSpace.id
        )

        let results = DeterministicRecommendationEngine.rank(snapshot: snapshot, context: context)
        let selectedProviderIDs = snapshot.selectedProviderIDs ?? []

        XCTAssertFalse(results.contains(where: { $0.title.id == "slow-horses" }))
        XCTAssertTrue(results.allSatisfy { $0.title.runtimeMinutes <= 55 })
        XCTAssertTrue(results.allSatisfy { result in
            !selectedProviderIDs.isDisjoint(with: Set(result.title.providers.map(\.id)))
        })
    }

    func testCoupleProfilesProduceCompromiseExplanation() {
        let context = RecommendationContext(
            mood: .thoughtful,
            maximumRuntimeMinutes: 120,
            sharedSpaceID: LibrarySnapshot.sample.sharedSpace.id
        )

        let results = DeterministicRecommendationEngine.rank(snapshot: .sample, context: context)

        XCTAssertTrue(results.contains(where: { $0.reason.contains("both taste profiles") }))
    }
}

final class CinemaServiceTests: XCTestCase {
    func testMaltaDirectoryUsesOfficialVenuesWithoutInventingShowtimes() async throws {
        let service = MaltaCinemaService(endpoint: nil)

        let showings = try await service.showings(on: .now, region: "MT")

        XCTAssertEqual(service.venues.map(\.id), ["eden", "embassy", "citadel"])
        XCTAssertTrue(showings.isEmpty)
        XCTAssertTrue(service.venues.allSatisfy { $0.listingsURL.scheme == "https" })
    }
}
