import XCTest
@testable import OpenTVTracker

final class CatalogFallbackIdentityTests: XCTestCase {
    func testTitleDoesNotAskFallbackWithPrimaryCatalogID() async {
        let primary = RecordingCatalogStub(title: Self.tmdbTitle, shouldFailTitle: true)
        let fallback = RecordingCatalogStub(title: Self.tvmazeTitle)
        let catalog = FallbackCatalogService(primary: primary, fallback: fallback)

        do {
            _ = try await catalog.title(kind: .series, catalogID: 95396, region: .malta)
            XCTFail("Expected the primary failure to surface")
        } catch let error as CatalogServiceError {
            guard case .unavailable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(primary.titleRequests, [95396])
        XCTAssertTrue(fallback.titleRequests.isEmpty)
    }

    func testSearchStillFallsBackWhenPrimaryIsEmpty() async throws {
        let primary = RecordingCatalogStub(title: Self.tmdbTitle, searchResults: [])
        let fallback = RecordingCatalogStub(title: Self.tvmazeTitle, searchResults: [Self.tvmazeTitle])
        let catalog = FallbackCatalogService(primary: primary, fallback: fallback)

        let results = try await catalog.search(
            MediaSearchQuery(text: "Severance", kind: .series, page: 1, region: .malta)
        )

        XCTAssertEqual(results.map(\.id), [Self.tvmazeTitle.id])
        XCTAssertEqual(fallback.searchCalls, 1)
    }

    func testTitleWithTVMazeSourceUsesFallbackOnly() async throws {
        let primary = RecordingCatalogStub(title: Self.tmdbTitle, shouldFailTitle: true)
        let fallback = RecordingCatalogStub(title: Self.tvmazeTitle)
        let catalog = FallbackCatalogService(primary: primary, fallback: fallback)

        let result = try await catalog.title(
            kind: .series,
            catalogID: 1396,
            region: .malta,
            contentLanguage: .english,
            metadataSource: .tvmaze
        )

        XCTAssertEqual(result.id, Self.tvmazeTitle.id)
        XCTAssertTrue(primary.titleRequests.isEmpty)
        XCTAssertEqual(fallback.titleRequests, [1396])
    }

    func testTitleWithTMDBSourceStillDoesNotAskFallback() async {
        let primary = RecordingCatalogStub(title: Self.tmdbTitle, shouldFailTitle: true)
        let fallback = RecordingCatalogStub(title: Self.tvmazeTitle)
        let catalog = FallbackCatalogService(primary: primary, fallback: fallback)

        do {
            _ = try await catalog.title(
                kind: .series,
                catalogID: 95396,
                region: .malta,
                contentLanguage: .english,
                metadataSource: .tmdb
            )
            XCTFail("Expected the primary failure to surface")
        } catch let error as CatalogServiceError {
            guard case .unavailable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(primary.titleRequests, [95396])
        XCTAssertTrue(fallback.titleRequests.isEmpty)
    }

    func testReviewsDoNotCrossNamespaces() async {
        let primary = RecordingCatalogStub(title: Self.tmdbTitle, shouldFailReviews: true)
        let fallback = RecordingCatalogStub(title: Self.tvmazeTitle)
        let catalog = FallbackCatalogService(primary: primary, fallback: fallback)

        do {
            _ = try await catalog.reviews(kind: .series, catalogID: 95396, page: 1)
            XCTFail("Expected the primary failure to surface")
        } catch let error as CatalogServiceError {
            guard case .unavailable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(fallback.reviewRequests.isEmpty)
    }

    private static let tmdbTitle = {
        var title = LibrarySnapshot.sample.titles.first { $0.id == "severance" }!
        title.metadataSource = .tmdb
        return title
    }()

    private static let tvmazeTitle = {
        var title = LibrarySnapshot.sample.titles.first { $0.id == "severance" }!
        title = MediaTitle(
            id: "tvmaze-series-1396",
            catalogID: 1396,
            title: title.title,
            year: title.year,
            kind: .series,
            synopsis: title.synopsis,
            genres: title.genres,
            runtimeMinutes: title.runtimeMinutes,
            state: .planned,
            progress: nil,
            rating: title.rating,
            nextReleaseDescription: nil,
            recommendationReason: nil,
            mood: title.mood,
            palette: title.palette,
            providers: title.providers,
            reviews: [],
            metadataSource: .tvmaze
        )
        return title
    }()
}

final class RecordingCatalogStub: CatalogProviding, @unchecked Sendable {
    let title: MediaTitle
    let searchResults: [MediaTitle]
    let shouldFailTitle: Bool
    let shouldFailReviews: Bool
    private(set) var titleRequests: [Int] = []
    private(set) var reviewRequests: [Int] = []
    private(set) var searchCalls = 0

    init(
        title: MediaTitle,
        searchResults: [MediaTitle] = [],
        shouldFailTitle: Bool = false,
        shouldFailReviews: Bool = false
    ) {
        self.title = title
        self.searchResults = searchResults
        self.shouldFailTitle = shouldFailTitle
        self.shouldFailReviews = shouldFailReviews
    }

    func search(_ query: MediaSearchQuery) async throws -> [MediaTitle] {
        searchCalls += 1
        return searchResults
    }

    func title(kind: MediaKind, catalogID: Int, region: StreamingRegion) async throws -> MediaTitle {
        titleRequests.append(catalogID)
        if shouldFailTitle { throw CatalogServiceError.unavailable }
        return title
    }

    func reviews(kind: MediaKind, catalogID: Int, page: Int) async throws -> CommunityReviewPage {
        reviewRequests.append(catalogID)
        if shouldFailReviews { throw CatalogServiceError.unavailable }
        return CommunityReviewPage(page: page, totalPages: 1, results: [])
    }
}

@MainActor
final class CatalogSearchTests: XCTestCase {
    func testCatalogSearchKeepsProviderFuzzyMatches() async throws {
        let fuzzyMatch = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "past-lives" }))
        let service = CatalogSearchStub { _ in [fuzzyMatch] }
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: service,
            seed: .sample
        )

        await model.searchCatalog(text: "Korean romance")

        XCTAssertEqual(model.catalogSearchResults.map(\.id), [fuzzyMatch.id])
        XCTAssertNil(model.catalogSearchError)
    }

    func testNewerCatalogSearchWinsWhenOlderRequestFinishesLast() async throws {
        let slowResult = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" }))
        let fastResult = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "fallout" }))
        let service = CatalogSearchStub { query in
            if query.text == "slow" {
                do {
                    try await Task.sleep(for: .milliseconds(400))
                } catch {
                    // Simulate a provider that cannot cancel an in-flight request.
                }
                return [slowResult]
            }
            try await Task.sleep(for: .milliseconds(20))
            return [fastResult]
        }
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: service,
            seed: .sample
        )

        let slowSearch = Task { await model.searchCatalog(text: "slow") }
        try await Task.sleep(for: .milliseconds(300))
        let fastSearch = Task { await model.searchCatalog(text: "fast") }

        await fastSearch.value
        await slowSearch.value

        XCTAssertEqual(model.catalogSearchQuery, "fast")
        XCTAssertEqual(model.catalogSearchResults.map(\.id), [fastResult.id])
        XCTAssertFalse(model.isSearchingCatalog)
    }

    func testClearingCatalogSearchInvalidatesInFlightResults() async throws {
        let delayedResult = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" }))
        let service = CatalogSearchStub { _ in
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                // Native cancellation can be advisory once a provider request has started.
            }
            return [delayedResult]
        }
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: service,
            seed: .sample
        )

        let pendingSearch = Task { await model.searchCatalog(text: "slow") }
        try await Task.sleep(for: .milliseconds(300))
        await model.searchCatalog(text: "")
        await pendingSearch.value

        XCTAssertTrue(model.catalogSearchResults.isEmpty)
        XCTAssertEqual(model.catalogSearchQuery, "")
        XCTAssertFalse(model.isSearchingCatalog)
    }

    func testCatalogSearchFailureHasDistinctErrorState() async {
        let service = CatalogSearchStub { _ in throw CatalogServiceError.unavailable }
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: service,
            seed: .sample
        )

        await model.searchCatalog(text: "Severance")

        XCTAssertTrue(model.catalogSearchResults.isEmpty)
        XCTAssertEqual(model.catalogSearchError, CatalogServiceError.unavailable.localizedDescription)
        XCTAssertFalse(model.isSearchingCatalog)
    }

    func testRefreshCatalogDetailsLoadsTVMazeSeasonsFromFallback() async throws {
        var searchResult = try XCTUnwrap(Self.tvmazeSearchResult)
        searchResult.seasons = nil
        var detailed = searchResult
        detailed.seasons = [
            SeasonSummary(
                id: "tvmaze-season-1396-1",
                number: 1,
                title: "Season 1",
                episodes: [
                    EpisodeSummary(
                        id: "tvmaze-episode-1",
                        number: 1,
                        title: "Good News About Hell",
                        airDate: nil,
                        runtimeMinutes: 57
                    )
                ]
            )
        ]
        let catalog = FallbackCatalogService(
            primary: RecordingCatalogStub(title: detailed, searchResults: [], shouldFailTitle: true),
            fallback: RecordingCatalogStub(title: detailed, searchResults: [searchResult])
        )
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: catalog,
            seed: .empty
        )

        await model.searchCatalog(text: "Severance")
        await model.refreshCatalogDetails(for: searchResult.id)

        let refreshed = try XCTUnwrap(model.mediaTitle(withID: searchResult.id))
        XCTAssertEqual(refreshed.seasons?.first?.episodes.first?.id, "tvmaze-episode-1")
        XCTAssertNil(model.catalogSearchError)
        XCTAssertNil(model.catalogDetailError(for: searchResult.id))
    }

    func testRefreshCatalogDetailsFailureDoesNotClobberSearchError() async throws {
        let searchResult = try XCTUnwrap(Self.tvmazeSearchResult)
        let catalog = FallbackCatalogService(
            primary: RecordingCatalogStub(
                title: searchResult,
                searchResults: [],
                shouldFailTitle: true
            ),
            fallback: RecordingCatalogStub(
                title: searchResult,
                searchResults: [searchResult],
                shouldFailTitle: true
            )
        )
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: catalog,
            seed: .empty
        )

        await model.searchCatalog(text: "Severance")
        XCTAssertNil(model.catalogSearchError)
        await model.refreshCatalogDetails(for: searchResult.id)

        XCTAssertEqual(model.catalogSearchResults.map(\.id), [searchResult.id])
        XCTAssertNil(model.catalogSearchError)
        XCTAssertEqual(
            model.catalogDetailError(for: searchResult.id),
            CatalogServiceError.unavailable.localizedDescription
        )
        XCTAssertNil(model.catalogDetailError(for: "severance"))
    }

    private static let tvmazeSearchResult: MediaTitle? = {
        guard var title = LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" }) else {
            return nil
        }
        title = MediaTitle(
            id: "tvmaze-series-1396",
            catalogID: 1396,
            title: title.title,
            year: title.year,
            kind: .series,
            synopsis: title.synopsis,
            genres: title.genres,
            runtimeMinutes: title.runtimeMinutes,
            state: .planned,
            progress: nil,
            rating: title.rating,
            nextReleaseDescription: nil,
            recommendationReason: nil,
            mood: title.mood,
            palette: title.palette,
            providers: title.providers,
            reviews: [],
            metadataSource: .tvmaze
        )
        return title
    }()
}
