import XCTest
@testable import OpenTVTracker

final class RecommendationServiceTests: XCTestCase {
    override func tearDown() {
        TestURLProtocol.handler = nil
        super.tearDown()
    }

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

    func testUserFundedOpenRouterRerankingCallsProviderDirectlyWithKeychainCredential() async throws {
        let store = MemorySecureCredentialStore()
        try store.set(Data("sk-or-v1-user-key".utf8), for: OpenRouterOAuthClient.apiKeyAccount)
        let session = TestURLProtocol.session()
        let deterministic = DeterministicRecommendationEngine.rank(
            snapshot: .sample,
            context: RecommendationContext(
                mood: .any,
                maximumRuntimeMinutes: nil,
                sharedSpaceID: LibrarySnapshot.sample.sharedSpace.id
            )
        )
        let expected = Array(deterministic.prefix(2).reversed()).map(\.title.catalogID)
        TestURLProtocol.handler = { request in
            try Self.openRouterResponse(for: request, rankedCatalogIDs: expected)
        }
        let service = OpenRouterRecommendationService(
            model: "openai/gpt-4o-mini",
            siteURL: URL(string: "https://github.com/VincentShipsIt/opentvtracker"),
            credentials: store,
            session: session
        )

        let reranked = try await service.rerank(
            Array(deterministic.prefix(2)),
            context: RecommendationContext(
                mood: .any,
                maximumRuntimeMinutes: nil,
                sharedSpaceID: LibrarySnapshot.sample.sharedSpace.id,
                allowsRemoteReranking: true,
                viewingProfile: RecommendationViewingProfiler.profile(from: .sample)
            )
        )

        XCTAssertEqual(reranked.map(\.title.catalogID), expected)
    }

    private static func openRouterResponse(
        for request: URLRequest,
        rankedCatalogIDs: [Int]
    ) throws -> (HTTPURLResponse, Data) {
        XCTAssertEqual(request.url?.host, "openrouter.ai")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-v1-user-key")
        let body = try XCTUnwrap(TestURLProtocol.bodyData(for: request))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        let userContent = try XCTUnwrap(messages.last?["content"] as? String)
        let userPayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(userContent.utf8)) as? [String: Any]
        )
        let viewingProfile = try XCTUnwrap(userPayload["viewingProfile"] as? [String: Any])
        XCTAssertGreaterThan(try XCTUnwrap(viewingProfile["watchedEpisodeCount"] as? Int), 0)
        let content = try JSONSerialization.data(withJSONObject: ["catalogIDs": rankedCatalogIDs])
        let contentString = try XCTUnwrap(String(data: content, encoding: .utf8))
        let response = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": contentString]]]
        ])
        return (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            response
        )
    }

    func testOpenRouterRerankingRejectsMoreThanTwentyCandidatesBeforeNetworkAccess() async throws {
        let store = MemorySecureCredentialStore()
        try store.set(Data("sk-or-v1-user-key".utf8), for: OpenRouterOAuthClient.apiKeyAccount)
        let service = OpenRouterRecommendationService(
            model: "openai/gpt-4o-mini",
            siteURL: nil,
            credentials: store,
            session: TestURLProtocol.session()
        )
        let recommendation = try XCTUnwrap(DeterministicRecommendationEngine.rank(
            snapshot: .sample,
            context: RecommendationContext(
                mood: .any,
                maximumRuntimeMinutes: nil,
                sharedSpaceID: LibrarySnapshot.sample.sharedSpace.id
            )
        ).first)

        do {
            _ = try await service.rerank(
                Array(repeating: recommendation, count: 21),
                context: RecommendationContext(
                    mood: .any,
                    maximumRuntimeMinutes: nil,
                    sharedSpaceID: LibrarySnapshot.sample.sharedSpace.id,
                    allowsRemoteReranking: true
                )
            )
            XCTFail("Expected candidate bound rejection")
        } catch let error as OpenRouterRecommendationError {
            guard case .tooManyCandidates = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}

final class CinemaServiceTests: XCTestCase {
    func testMaltaDirectoryUsesOfficialVenues() {
        let service = MaltaCinemaService(endpoint: nil)

        XCTAssertEqual(service.venues.map(\.id), ["eden", "embassy", "citadel"])
        XCTAssertTrue(service.venues.allSatisfy { $0.listingsURL.scheme == "https" })
    }
}
