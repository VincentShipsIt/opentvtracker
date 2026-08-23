import XCTest
import ZIPFoundation
@testable import OpenTVTracker

final class CatalogImportSafetyTests: XCTestCase {
    func testDistinctEntityLimitRejectsBeforeCatalogResolution() async throws {
        var rows = ["tv_show_id,tv_show_name,is_followed"]
        rows.reserveCapacity(LibraryImportLimits.maximumTVTimeEntityCount + 2)
        for index in 0...LibraryImportLimits.maximumTVTimeEntityCount {
            rows.append("source-\(index),Title \(index),true")
        }
        let archive = try makeArchive(
            path: "followed_tv_show.csv",
            contents: rows.joined(separator: "\n")
        )
        let catalog = CountingSafetyCatalog()

        do {
            _ = try await TVTimeImportService.previewImport(
                archive,
                into: .empty,
                catalog: catalog,
                region: .malta
            )
            XCTFail("Expected the semantic entity limit to reject the archive")
        } catch {
            XCTAssertEqual(error as? LibraryImportSafetyError, .tooManyTVTimeEntities)
        }

        let requestCount = await catalog.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testMaximumAllowedEntitiesReuseLegacyAliasesWithoutRepeatedTitleScans() async {
        let entityCount = LibraryImportLimits.maximumTVTimeEntityCount
        var current = LibrarySnapshot.empty
        current.titles = (0..<entityCount).map { index in
            Self.title(
                id: "local-\(index)",
                catalogID: index + 1,
                title: "Local Title \(index)",
                year: 2_000 + index % 25
            )
        }
        let entities = current.titles.enumerated().map { index, title in
            TVTimeEntity(
                identity: "series:source:\(index)",
                sourceID: "\(index)",
                title: title.title,
                year: title.year,
                kind: title.kind
            )
        }
        current.importResolutionAliases = Dictionary(
            uniqueKeysWithValues: entities.enumerated().map { index, entity in
                (
                    entity.identity,
                    ImportResolutionAlias(
                        kind: entity.kind,
                        catalogID: index + 1
                    )
                )
            }
        )
        let catalog = CountingSafetyCatalog()

        let resolution = await TVTimeImportMerger.resolveTitles(
            entities,
            current: current,
            catalog: catalog,
            region: .malta
        )

        XCTAssertEqual(resolution.resolved.count, entityCount)
        XCTAssertTrue(resolution.issues.isEmpty)
        XCTAssertTrue(resolution.warnings.isEmpty)
        let requestCount = await catalog.requestCount
        XCTAssertEqual(requestCount, 0)
    }

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
            archive: TVTimeArchive(
                entities: [entity],
                duplicateCount: 0,
                diagnostics: TVTimeImportDiagnostics()
            ),
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

    private func makeArchive(path: String, contents: String) throws -> Data {
        let archive = try Archive(accessMode: .create)
        let data = Data(contents.utf8)
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            provider: { position, size in
                let start = Int(position)
                return data.subdata(in: start..<(start + size))
            }
        )
        return try XCTUnwrap(archive.data)
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

private actor CountingSafetyCatalog: CatalogProviding {
    private(set) var requestCount = 0

    func search(_: MediaSearchQuery) async throws -> [MediaTitle] {
        requestCount += 1
        return []
    }

    func title(kind _: MediaKind, catalogID _: Int, region _: StreamingRegion) async throws -> MediaTitle {
        requestCount += 1
        throw CatalogServiceError.notFound
    }

    func resolve(_: ExternalCatalogReference, region _: StreamingRegion) async throws -> MediaTitle? {
        requestCount += 1
        return nil
    }
}
