import XCTest
@testable import OpenTVTracker

final class DiscoveryAssistantTests: XCTestCase {
    private let defaultProviderIDs: Set<StreamingProvider.ID> = [
        StreamingProvider.netflix.id,
        StreamingProvider.primeVideo.id,
        StreamingProvider.appleTV.id
    ]

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
            selectedProviderIDs: defaultProviderIDs,
            tasteProfiles: LibrarySnapshot.sample.sharedSpace.tasteProfiles ?? []
        )
        let personal = DiscoveryAssistantEngine.respond(
            to: "Something thoughtful",
            titles: LibrarySnapshot.sample.titles,
            selectedProviderIDs: defaultProviderIDs,
            tasteProfiles: LibrarySnapshot.sample.sharedSpace.tasteProfiles ?? []
        )

        XCTAssertFalse(shared.matches.isEmpty)
        XCTAssertNotEqual(shared.matches.map(\.score), personal.matches.map(\.score))
    }

    func testAssistantReturnsClearEmptyState() {
        let response = DiscoveryAssistantEngine.respond(
            to: "A movie rated above 9.9 under 10 minutes",
            titles: LibrarySnapshot.sample.titles,
            selectedProviderIDs: defaultProviderIDs,
            tasteProfiles: []
        )

        XCTAssertTrue(response.matches.isEmpty)
        XCTAssertTrue(response.summary.contains("No exact match"))
    }

    func testParserTreatsNegatedGenresAsExclusions() {
        let intent = DiscoveryAssistantEngine.parse("A show with no sci-fi, comedy instead")

        XCTAssertEqual(intent.excludedGenres, ["Sci-Fi"])
        XCTAssertEqual(intent.genres, ["Comedy"])
    }

    func testAssistantNeverReturnsAnExcludedGenre() {
        let response = DiscoveryAssistantEngine.respond(
            to: "A show, not sci-fi",
            titles: LibrarySnapshot.sample.titles,
            selectedProviderIDs: defaultProviderIDs,
            tasteProfiles: []
        )

        XCTAssertFalse(response.matches.isEmpty)
        XCTAssertTrue(response.matches.allSatisfy { $0.title.kind == .series })
        XCTAssertTrue(response.matches.allSatisfy { !$0.title.genres.contains("Sci-Fi") })
    }

    func testRefinedIntentKeepsEarlierConstraintsAndLetsFollowUpOverride() {
        let base = DiscoveryAssistantEngine.parse("A funny show under 60 minutes")
        let refined = base.refined(by: DiscoveryAssistantEngine.parse("make it a movie"))

        XCTAssertEqual(refined.kind, .movie)
        XCTAssertEqual(refined.mood, .funny)
        XCTAssertEqual(refined.maximumRuntimeMinutes, 60)
    }

    func testRefinedIntentSwapsRuledOutGenreForNewOne() {
        let base = DiscoveryAssistantEngine.parse("A sci-fi show")
        let refined = base.refined(by: DiscoveryAssistantEngine.parse("no sci-fi, comedy instead"))

        XCTAssertEqual(refined.genres, ["Comedy"])
        XCTAssertEqual(refined.excludedGenres, ["Sci-Fi"])
    }

    func testSuggestionsReturnThreeDistinctEligibleTitles() {
        let suggestions = DiscoveryAssistantEngine.suggestions(
            titles: LibrarySnapshot.sample.titles,
            selectedProviderIDs: defaultProviderIDs,
            tasteProfiles: []
        )

        XCTAssertEqual(suggestions.count, 3)
        XCTAssertEqual(Set(suggestions.map(\.id)).count, 3)
        XCTAssertTrue(suggestions.allSatisfy { $0.title.isRecommendationEligible })
        XCTAssertEqual(suggestions.map(\.score), suggestions.map(\.score).sorted(by: >))
    }

    func testSuggestionsAreEmptyWithoutSelectedServices() {
        let suggestions = DiscoveryAssistantEngine.suggestions(
            titles: LibrarySnapshot.sample.titles,
            selectedProviderIDs: [],
            tasteProfiles: []
        )

        XCTAssertTrue(suggestions.isEmpty)
    }

    func testConversationRefinesAndDoesNotRepeatSuggestedTitles() {
        let titles = LibrarySnapshot.sample.titles
        let all = DiscoveryAssistantEngine.respond(
            to: "A show",
            titles: titles,
            selectedProviderIDs: defaultProviderIDs,
            tasteProfiles: [],
            limit: 10
        ).matches
        XCTAssertGreaterThan(all.count, 2)

        var conversation = DiscoveryConversation()
        let first = conversation.ask(
            "A show",
            titles: titles,
            selectedProviderIDs: defaultProviderIDs,
            tasteProfiles: [],
            limit: 2
        )
        let second = conversation.ask(
            "another one",
            titles: titles,
            selectedProviderIDs: defaultProviderIDs,
            tasteProfiles: [],
            limit: 10
        )

        XCTAssertEqual(conversation.turns.count, 2)
        XCTAssertEqual(first.response.matches.count, 2)
        XCTAssertEqual(second.response.matches.count, all.count - 2)
        XCTAssertTrue(second.response.matches.allSatisfy { $0.title.kind == .series })
        XCTAssertTrue(
            Set(first.response.matches.map(\.id)).isDisjoint(with: Set(second.response.matches.map(\.id)))
        )
    }

    func testConversationResetForgetsEarlierConstraints() {
        let titles = LibrarySnapshot.sample.titles
        var conversation = DiscoveryConversation()
        conversation.ask(
            "A movie",
            titles: titles,
            selectedProviderIDs: defaultProviderIDs,
            tasteProfiles: []
        )
        conversation.reset()
        let turn = conversation.ask(
            "A show",
            titles: titles,
            selectedProviderIDs: defaultProviderIDs,
            tasteProfiles: []
        )

        XCTAssertEqual(conversation.turns.count, 1)
        XCTAssertFalse(turn.response.matches.isEmpty)
        XCTAssertTrue(turn.response.matches.allSatisfy { $0.title.kind == .series })
    }
}
