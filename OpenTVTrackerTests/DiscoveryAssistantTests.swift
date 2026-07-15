import XCTest
@testable import OpenTVTracker

final class DiscoveryAssistantTests: XCTestCase {
    func testParserUnderstandsKindMoodAndRuntime() {
        let intent = DiscoveryAssistantEngine.parse("A funny show under 60 minutes")

        XCTAssertEqual(intent.kind, .series)
        XCTAssertEqual(intent.mood, .funny)
        XCTAssertEqual(intent.maximumRuntimeMinutes, 60)
    }

    func testAssistantHonorsSelectedServicesAndRating() {
        let response = DiscoveryAssistantEngine.respond(
            to: "A highly rated movie",
            titles: LibrarySnapshot.sample.titles,
            selectedProviderIDs: [StreamingProvider.primeVideo.id],
            tasteProfiles: LibrarySnapshot.sample.sharedSpace.tasteProfiles ?? []
        )

        XCTAssertFalse(response.matches.isEmpty)
        XCTAssertTrue(response.matches.allSatisfy { $0.title.kind == .movie })
        XCTAssertTrue(response.matches.allSatisfy { $0.title.rating >= 7.5 })
        XCTAssertTrue(response.matches.allSatisfy { match in
            match.title.providers.contains(where: { $0.id == StreamingProvider.primeVideo.id })
        })
    }

    func testAssistantUsesBothTasteProfilesForSharedRequest() {
        let shared = DiscoveryAssistantEngine.respond(
            to: "Something thoughtful we would both like",
            titles: LibrarySnapshot.sample.titles,
            selectedProviderIDs: LibrarySnapshot.sample.selectedProviderIDs ?? [],
            tasteProfiles: LibrarySnapshot.sample.sharedSpace.tasteProfiles ?? []
        )
        let personal = DiscoveryAssistantEngine.respond(
            to: "Something thoughtful",
            titles: LibrarySnapshot.sample.titles,
            selectedProviderIDs: LibrarySnapshot.sample.selectedProviderIDs ?? [],
            tasteProfiles: LibrarySnapshot.sample.sharedSpace.tasteProfiles ?? []
        )

        XCTAssertFalse(shared.matches.isEmpty)
        XCTAssertNotEqual(shared.matches.map(\.score), personal.matches.map(\.score))
    }

    func testAssistantReturnsClearEmptyState() {
        let response = DiscoveryAssistantEngine.respond(
            to: "A movie rated above 9.9 under 10 minutes",
            titles: LibrarySnapshot.sample.titles,
            selectedProviderIDs: LibrarySnapshot.sample.selectedProviderIDs ?? [],
            tasteProfiles: []
        )

        XCTAssertTrue(response.matches.isEmpty)
        XCTAssertTrue(response.summary.contains("No exact match"))
    }
}
