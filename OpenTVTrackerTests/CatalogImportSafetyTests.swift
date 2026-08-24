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

    func testThousandsOfUnresolvedEntitiesShareOneAutomaticCatalogRequestBudget() async {
        let entityCount = 2_000
        let aliasedEntityCount = 25
        let entities = Self.unresolvedEntities(count: entityCount)
        let current = Self.snapshotWithAliases(
            for: entities,
            count: aliasedEntityCount
        )
        let catalog = CountingSafetyCatalog(
            searchResultsByText: Self.searchResults(for: entities)
        )

        let resolution = await TVTimeImportMerger.resolveTitles(
            entities,
            current: current,
            catalog: catalog,
            region: .malta
        )

        let counts = await catalog.callCounts()
        XCTAssertEqual(counts.total, LibraryImportLimits.maximumTVTimeCatalogRequestCount)
        XCTAssertGreaterThan(counts.title, aliasedEntityCount)
        XCTAssertGreaterThan(counts.resolve, 0)
        XCTAssertGreaterThan(counts.search, 0)
        XCTAssertFalse(resolution.resolved.isEmpty)
        XCTAssertEqual(resolution.resolved.count + resolution.issues.count, entityCount)
        let deferredCount = resolution.issues.values.filter {
            $0.reason == .automaticResolutionLimit
        }.count
        XCTAssertEqual(deferredCount, resolution.issues.count)
        XCTAssertGreaterThanOrEqual(
            deferredCount,
            entityCount - LibraryImportLimits.maximumTVTimeCatalogRequestCount
        )
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

    private static func unresolvedEntities(count: Int) -> [TVTimeEntity] {
        (0..<count).map { index in
            TVTimeEntity(
                identity: "series:tvdb:\(index + 1)",
                sourceID: "\(index + 1)",
                source: .tvdb,
                title: "Unresolved Title \(index)",
                year: 2_000 + index % 25,
                kind: .series
            )
        }
    }

    private static func snapshotWithAliases(
        for entities: [TVTimeEntity],
        count: Int
    ) -> LibrarySnapshot {
        var snapshot = LibrarySnapshot.empty
        snapshot.importResolutionAliases = Dictionary(
            uniqueKeysWithValues: entities.prefix(count).enumerated().map { index, entity in
                (
                    entity.identity,
                    ImportResolutionAlias(kind: .series, catalogID: index + 1)
                )
            }
        )
        return snapshot
    }

    private static func searchResults(
        for entities: [TVTimeEntity]
    ) -> [String: MediaTitle] {
        Dictionary(
            uniqueKeysWithValues: entities.enumerated().map { index, entity in
                (
                    entity.title,
                    title(
                        id: "catalog-\(index)",
                        catalogID: 10_001 + index,
                        title: entity.title,
                        year: entity.year ?? 2_000
                    )
                )
            }
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
    private let searchResultsByText: [String: MediaTitle]
    private var searchRequestCount = 0
    private var titleRequestCount = 0
    private var resolveRequestCount = 0

    var requestCount: Int {
        searchRequestCount + titleRequestCount + resolveRequestCount
    }

    init(searchResultsByText: [String: MediaTitle] = [:]) {
        self.searchResultsByText = searchResultsByText
    }

    func search(_ query: MediaSearchQuery) async throws -> [MediaTitle] {
        searchRequestCount += 1
        return searchResultsByText[query.text].map { [$0] } ?? []
    }

    func title(kind _: MediaKind, catalogID _: Int, region _: StreamingRegion) async throws -> MediaTitle {
        titleRequestCount += 1
        throw CatalogServiceError.notFound
    }

    func resolve(_: ExternalCatalogReference, region _: StreamingRegion) async throws -> MediaTitle? {
        resolveRequestCount += 1
        return nil
    }

    func callCounts() -> CatalogRequestCounts {
        CatalogRequestCounts(
            search: searchRequestCount,
            title: titleRequestCount,
            resolve: resolveRequestCount,
            total: requestCount
        )
    }
}

private struct CatalogRequestCounts {
    let search: Int
    let title: Int
    let resolve: Int
    let total: Int
}
