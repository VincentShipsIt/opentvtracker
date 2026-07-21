import XCTest
@testable import OpenTVTracker

final class CatalogImportSafetyTests: XCTestCase {
    func testAnimeSeasonMustExistOnDetailedCatalogTitle() async {
        let anime = Self.title(
            id: "anime",
            catalogID: 85_937,
            title: "Demon Slayer",
            year: 2019,
            genres: ["Animation"],
            seasons: [SeasonSummary(id: "season-2", number: 2, title: "Season 2", episodes: [])]
        )
        let entity = TVTimeEntity(
            identity: "series:source:anime",
            sourceID: "anime",
            title: "Demon Slayer Season 99",
            year: 2019,
            kind: .series
        )

        let resolution = await TVTimeImportMerger.resolveTitles(
            [entity],
            current: .empty,
            catalog: SafetyCatalog(searchResults: [anime]),
            region: .malta
        )

        XCTAssertEqual(resolution.issues[entity.identity]?.reason, .unsafeAnimeRelation)
        XCTAssertNil(resolution.resolved[entity.identity])
    }

    @MainActor
    func testManualResolutionRemainsPendingWhenDetailHydrationFails() async throws {
        let original = Self.title(id: "original", catalogID: 1, title: "Suspiria", year: 1977, kind: .movie)
        let remake = Self.title(id: "remake", catalogID: 2, title: "Suspiria", year: 2018, kind: .movie)
        let entity = TVTimeEntity(
            identity: "movie:title:suspiria",
            sourceID: nil,
            title: "Suspiria",
            kind: .movie
        )
        let session = TVTimeImportSession(
            archive: TVTimeArchive(entities: [entity], duplicateCount: 0),
            current: .empty,
            catalog: SafetyCatalog(searchResults: [original, remake], failsTitleRequests: true),
            region: .malta
        )
        let coordinator = TVTimeImportCoordinator(session: session)
        await coordinator.refresh()
        let issue = try XCTUnwrap(coordinator.preview?.resolutionIssues.first)

        let didResolve = await coordinator.resolve(issue, with: remake)

        XCTAssertFalse(didResolve)
        XCTAssertEqual(coordinator.preview?.resolutionIssues.map(\.id), [issue.id])
        XCTAssertNotNil(coordinator.errorMessage)
    }

    private static func title(
        id: String,
        catalogID: Int,
        title: String,
        year: Int,
        kind: MediaKind = .series,
        genres: [String] = [],
        seasons: [SeasonSummary]? = nil
    ) -> MediaTitle {
        MediaTitle(
            id: id,
            catalogID: catalogID,
            title: title,
            year: year,
            kind: kind,
            synopsis: "",
            genres: genres,
            runtimeMinutes: 0,
            state: .planned,
            progress: nil,
            rating: 0,
            nextReleaseDescription: nil,
            recommendationReason: nil,
            mood: .any,
            palette: PosterPalette(primaryHex: "000000", secondaryHex: "000000"),
            providers: [],
            reviews: [],
            posterURL: nil,
            backdropURL: nil,
            trailerURL: nil,
            seasons: seasons
        )
    }
}

private actor SafetyCatalog: CatalogProviding {
    let searchResults: [MediaTitle]
    let failsTitleRequests: Bool

    init(searchResults: [MediaTitle], failsTitleRequests: Bool = false) {
        self.searchResults = searchResults
        self.failsTitleRequests = failsTitleRequests
    }

    func search(_: MediaSearchQuery) async throws -> [MediaTitle] {
        searchResults
    }

    func title(kind: MediaKind, catalogID: Int, region _: StreamingRegion) async throws -> MediaTitle {
        if failsTitleRequests { throw CatalogServiceError.notFound }
        guard let title = searchResults.first(where: { $0.kind == kind && $0.catalogID == catalogID }) else {
            throw CatalogServiceError.notFound
        }
        return title
    }

    func resolve(_: ExternalCatalogReference, region _: StreamingRegion) async throws -> MediaTitle? {
        nil
    }
}
