import XCTest
@testable import OpenTVTracker

@MainActor
final class LibraryIntegrityTests: XCTestCase {
    func testCollectionUniquingKeepsFirstAndLastAsDocumented() {
        let firstWins = CollectionUniquing.dictionary(keepingFirst: [
            ("a", 1),
            ("a", 2),
            ("b", 3),
        ])
        XCTAssertEqual(firstWins, ["a": 1, "b": 3])

        let lastWins = CollectionUniquing.dictionary(keepingLast: [
            ("a", 1),
            ("a", 2),
            ("b", 3),
        ])
        XCTAssertEqual(lastWins, ["a": 2, "b": 3])
    }

    func testLibraryTitleIndexDedupesAndIndexesFirstOccurrence() {
        let severance = LibrarySnapshot.sample.titles.first { $0.id == "severance" }!
        var duplicate = severance
        duplicate.notes = "second copy"
        let titles = [severance, duplicate, LibrarySnapshot.sample.titles.first { $0.id == "fallout" }!]
        let deduped = LibraryTitleIndex.deduplicated(titles)
        XCTAssertEqual(deduped.map(\.id), ["severance", "fallout"])
        XCTAssertEqual(deduped[0].notes, severance.notes)

        let index = LibraryTitleIndex.indexByID(deduped)
        XCTAssertEqual(index["severance"], 0)
        XCTAssertEqual(index["fallout"], 1)
    }

    func testApplyLibraryStateDedupesDuplicateTitleIDs() {
        let severance = LibrarySnapshot.sample.titles.first { $0.id == "severance" }!
        var clone = severance
        clone.notes = "dup"
        var seed = LibrarySnapshot.sample
        seed.titles = [severance, clone]
        let model = AppModel(store: MemoryLibraryStore(), seed: seed)

        XCTAssertEqual(model.titles.filter { $0.id == "severance" }.count, 1)
        XCTAssertEqual(model.titleIndex(for: "severance"), 0)
        XCTAssertEqual(model.titles[0].notes, severance.notes)
    }

    func testDiscoveryRefreshDoesNotPersistBrowseTitles() async throws {
        let severance = try XCTUnwrap(LibrarySnapshot.sample.titles.first { $0.id == "severance" })
        let fallout = try XCTUnwrap(LibrarySnapshot.sample.titles.first { $0.id == "fallout" })
        let service = IntegrityDiscoveryStub(pages: [
            1: [severance],
            2: [fallout],
        ])
        let store = MemoryLibraryStore()
        let model = AppModel(store: store, catalogService: service, seed: .empty)

        await model.refreshDiscoveryCatalog()
        await model.flushPendingPersistence()

        XCTAssertEqual(model.discoveryCatalogTitles.map(\.id), [severance.id, fallout.id])
        XCTAssertTrue(model.titles.isEmpty)
        let saved = try await store.load()
        XCTAssertNil(saved)
    }

    func testTitleIndexIsNonMutatingWhileEnsurePromotes() {
        let fallout = LibrarySnapshot.sample.titles.first { $0.id == "fallout" }!
        let model = AppModel(
            store: MemoryLibraryStore(),
            seed: .empty
        )
        model.catalogSearchResults = [fallout]

        XCTAssertNil(model.titleIndex(for: fallout.id))
        XCTAssertTrue(model.titles.isEmpty)

        XCTAssertEqual(model.ensureTrackableTitleIndex(for: fallout.id), 0)
        XCTAssertEqual(model.titles.map(\.id), [fallout.id])
        XCTAssertEqual(model.titleIndex(for: fallout.id), 0)
    }

    func testRecommendationRefreshHonorsLatestRequestID() async {
        let service = SequencedRecommendationStub(delaysMilliseconds: [80, 5])
        var seed = LibrarySnapshot.sample
        seed.allowsAIReranking = true
        let model = AppModel(
            store: MemoryLibraryStore(),
            recommendationService: service,
            seed: seed
        )

        async let first: Void = model.refreshRecommendations()
        try? await Task.sleep(for: .milliseconds(10))
        async let second: Void = model.refreshRecommendations()
        _ = await (first, second)

        // The second (faster) response must win; the slower first response is discarded.
        XCTAssertEqual(model.remoteRankedRecommendations.map(\.id), ["second"])
        let completed = await service.completedCalls()
        XCTAssertEqual(completed, 2)
    }

    func testSnapshotHydrationMatchesLoadAndReplacePaths() {
        var snapshot = LibrarySnapshot.sample
        snapshot.allowsAIReranking = true
        snapshot.streamingRegionCode = "MT"
        snapshot.hasCompletedFirstRun = true

        let preferences = LibrarySnapshotHydration.preferences(
            from: snapshot,
            defaultFirstRunCompleted: false
        )
        XCTAssertTrue(preferences.allowsAIReranking)
        XCTAssertEqual(preferences.streamingRegionOverride?.code, "MT")
        XCTAssertTrue(preferences.hasCompletedFirstRun)
        XCTAssertEqual(preferences.sharedSpace.id, snapshot.sharedSpace.id)
    }

    func testSharedSpaceResolvedCurrentMemberIDFallsBack() {
        var space = LibrarySnapshot.empty.sharedSpace
        XCTAssertEqual(space.resolvedCurrentMemberID, "local-user")

        space.members = [
            SpaceMember(id: "partner", name: "P", initials: "P", isCurrentUser: false),
            SpaceMember(id: "me", name: "Me", initials: "ME", isCurrentUser: true),
        ]
        XCTAssertEqual(space.currentMemberID, "me")
        XCTAssertEqual(space.resolvedCurrentMemberID, "me")
    }
}

private actor IntegrityDiscoveryStub: CatalogProviding {
    private let pages: [Int: [MediaTitle]]

    init(pages: [Int: [MediaTitle]]) {
        self.pages = pages
    }

    func search(_ query: MediaSearchQuery) async throws -> [MediaTitle] {
        pages[query.page] ?? []
    }

    func title(kind: MediaKind, catalogID: Int, region: StreamingRegion) async throws -> MediaTitle {
        throw CatalogServiceError.notFound
    }
}

private actor SequencedRecommendationStub: RecommendationProviding {
    private let delaysMilliseconds: [UInt64]
    private var callCount = 0
    private var completed = 0

    init(delaysMilliseconds: [UInt64]) {
        self.delaysMilliseconds = delaysMilliseconds
    }

    func recommendations(
        from snapshot: LibrarySnapshot,
        context: RecommendationContext
    ) async throws -> [Recommendation] {
        callCount += 1
        let call = callCount
        let delay = delaysMilliseconds[min(call - 1, delaysMilliseconds.count - 1)]
        try await Task.sleep(for: .milliseconds(delay))
        completed += 1
        let label = call == 1 ? "first" : "second"
        guard let title = snapshot.titles.first else { return [] }
        return [
            Recommendation(id: label, title: title, reason: label, score: Double(call))
        ]
    }

    func completedCalls() -> Int { completed }
}
