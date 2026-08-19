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
