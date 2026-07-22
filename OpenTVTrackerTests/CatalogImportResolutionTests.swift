import XCTest
import ZIPFoundation
@testable import OpenTVTracker

final class CatalogImportResolutionTests: XCTestCase {
    func testTVDBResolutionIsCachedForOfflineReimport() async throws {
        let resolved = makeTitle(
            id: "tmdb-series-95396",
            catalogID: 95_396,
            title: "Severance",
            year: 2022
        )
        let archive = try makeArchive([
            "tvtime-series-2026.csv": """
            tvdb_id,title,status
            371980,Severance,watching
            """
        ])
        let catalog = StubCatalog(resolvedTitle: resolved)

        let first = try await TVTimeImportService.previewImport(
            archive,
            into: .empty,
            catalog: catalog,
            region: .malta
        )

        XCTAssertEqual(first.addedCount, 1)
        XCTAssertEqual(
            first.snapshot.importResolutionAliases?["series:tvdb:371980"],
            ImportResolutionAlias(kind: resolved.kind, catalogID: resolved.catalogID)
        )
        let firstCounts = await catalog.callCounts()
        XCTAssertEqual(firstCounts.resolve, 1)
        XCTAssertEqual(firstCounts.search, 0)

        let offlineCatalog = StubCatalog(failsAllRequests: true)
        let second = try await TVTimeImportService.previewImport(
            archive,
            into: first.snapshot,
            catalog: offlineCatalog,
            region: .malta
        )

        XCTAssertEqual(second.matchedCount, 1)
        XCTAssertTrue(second.resolutionIssues.isEmpty)
        let offlineCounts = await offlineCatalog.callCounts()
        XCTAssertEqual(offlineCounts.resolve, 0)
        XCTAssertEqual(offlineCounts.search, 0)
    }

    func testLocalizedAlternativeTitleAndYearResolveUniquely() async throws {
        let localized = makeTitle(
            id: "tmdb-series-1429",
            catalogID: 1_429,
            title: "Attack on Titan",
            alternativeTitles: ["進撃の巨人", "L'Attaque des Titans"],
            year: 2013
        )
        let archive = try makeArchive([
            "tracking-prod-records-v2.csv": """
            key,s_id,series_name,year,is_followed
            user-series-1,legacy-1,進撃の巨人,2013,true
            """
        ])

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: .empty,
            catalog: StubCatalog(searchResults: [localized]),
            region: .malta
        )

        XCTAssertEqual(preview.addedCount, 1)
        XCTAssertTrue(preview.resolutionIssues.isEmpty)
        XCTAssertEqual(preview.snapshot.titles.first?.catalogID, 1_429)
    }

    func testLocalDiscoverySearchIncludesLocalizedAliases() async throws {
        let localized = makeTitle(
            id: "tmdb-series-1429",
            catalogID: 1_429,
            title: "Attack on Titan",
            alternativeTitles: ["進撃の巨人"],
            year: 2013
        )

        let results = try await LocalCatalogService(titles: [localized]).search(
            MediaSearchQuery(
                text: "進撃",
                kind: .series,
                page: 1,
                region: .malta
            )
        )

        XCTAssertEqual(results.map(\.id), [localized.id])
    }

    func testYearSuffixIsStrippedOnlyWhenItConfirmsTheRelease() async throws {
        let release = makeTitle(
            id: "tmdb-series-70523",
            catalogID: 70_523,
            title: "Dark",
            year: 2017
        )
        let archive = try makeArchive([
            "tracking-prod-records-v2.csv": """
            key,s_id,series_name,year,is_followed
            user-series-1,legacy-2,Dark (2017),2017,true
            """
        ])

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: .empty,
            catalog: StubCatalog(searchResults: [release]),
            region: .malta
        )

        XCTAssertEqual(preview.addedCount, 1)
        XCTAssertTrue(preview.resolutionIssues.isEmpty)
    }

    func testAmbiguousRemakesRequireManualResolutionAndPersistTheChoice() async throws {
        let original = makeTitle(
            id: "tmdb-movie-1",
            catalogID: 1,
            title: "Suspiria",
            year: 1977,
            kind: .movie
        )
        let remake = makeTitle(
            id: "tmdb-movie-2",
            catalogID: 2,
            title: "Suspiria",
            year: 2018,
            kind: .movie
        )
        let archive = try makeArchive([
            "tracking-prod-records.csv": """
            type,entity_type,movie_name
            towatch,movie,Suspiria
            """
        ])
        let session = try await TVTimeImportService.prepareImport(
            archive,
            into: .empty,
            catalog: StubCatalog(searchResults: [original, remake]),
            region: .malta
        )

        let unresolved = await session.preview()
        let issue = try XCTUnwrap(unresolved.resolutionIssues.first)
        XCTAssertEqual(issue.reason, .ambiguousCatalogMatch)
        XCTAssertEqual(unresolved.skippedCount, 1)
        XCTAssertEqual(unresolved.addedCount, 0)

        let resolved = await session.preview(manualResolutions: [issue.id: remake])
        XCTAssertTrue(resolved.resolutionIssues.isEmpty)
        XCTAssertEqual(resolved.addedCount, 1)
        XCTAssertEqual(
            resolved.snapshot.importResolutionAliases?[issue.id],
            ImportResolutionAlias(kind: remake.kind, catalogID: remake.catalogID)
        )
    }

    func testExplicitAnimeSeasonMapsSourceSeasonOneToCatalogSeason() async throws {
        let anime = makeTitle(
            id: "tmdb-series-85937",
            catalogID: 85_937,
            title: "Demon Slayer",
            year: 2019,
            genres: ["Animation", "Action"],
            seasons: [
                SeasonSummary(
                    id: "season-2",
                    number: 2,
                    title: "Season 2",
                    episodes: [
                        EpisodeSummary(
                            id: "season-2-episode-1",
                            number: 1,
                            title: "Flame Hashira Kyojuro Rengoku",
                            airDate: Date(timeIntervalSince1970: 1_633_219_200),
                            runtimeMinutes: 24
                        )
                    ]
                )
            ]
        )
        let archive = try makeArchive([
            "tracking-prod-records-v2.csv": """
            key,s_id,series_name,s_no,ep_no,created_at
            watch-episode-1,legacy-anime,Demon Slayer Season 2,1,1,2021-10-10T18:00:00Z
            """
        ])

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: .empty,
            catalog: StubCatalog(searchResults: [anime]),
            region: .malta
        )

        let imported = try XCTUnwrap(preview.snapshot.titles.first)
        XCTAssertEqual(imported.watchedEpisodeIDs, Set(["season-2-episode-1"]))
        XCTAssertEqual(imported.progress?.season, 2)
        XCTAssertEqual(preview.watchedEpisodeCount, 1)
        XCTAssertTrue(preview.resolutionIssues.isEmpty)
        try await assertOfflineAnimeReimport(archive: archive, snapshot: preview.snapshot)
    }

    func testUnsafeAnimePartAndCatalogMissAreReported() {
        let anime = makeTitle(
            id: "tmdb-series-1",
            catalogID: 1,
            title: "Demon Slayer",
            year: 2019,
            genres: ["Animation"]
        )
        let unsafeEntity = TVTimeEntity(
            identity: "series:source:anime-part",
            sourceID: "anime-part",
            source: nil,
            title: "Demon Slayer Part 2",
            kind: .series
        )
        let missingEntity = TVTimeEntity(
            identity: "series:source:missing",
            sourceID: "missing",
            source: nil,
            title: "Unknown Foreign Series",
            kind: .series
        )

        switch CatalogImportMatcher.select(entity: unsafeEntity, candidates: [anime]) {
        case .issue(let reason, _):
            XCTAssertEqual(reason, .unsafeAnimeRelation)
        case .resolved:
            XCTFail("Unsafe anime relations must require manual confirmation")
        }

        switch CatalogImportMatcher.select(entity: missingEntity, candidates: [anime]) {
        case .issue(let reason, let detail):
            XCTAssertEqual(reason, .noCatalogMatch)
            XCTAssertTrue(detail.contains("display, original, or localized title"))
        case .resolved:
            XCTFail("Catalog misses must not use an unrelated first result")
        }
    }

    func testAnimeSeasonRequiresTheResolvedCatalogSeason() {
        let anime = makeTitle(
            id: "tmdb-series-1",
            catalogID: 1,
            title: "Demon Slayer",
            year: 2019,
            genres: ["Animation"],
            seasons: []
        )
        let entity = TVTimeEntity(
            identity: "series:source:anime-season",
            sourceID: "anime-season",
            source: nil,
            title: "Demon Slayer Season 2",
            kind: .series
        )

        switch CatalogImportMatcher.select(entity: entity, candidates: [anime]) {
        case .issue(let reason, let detail):
            XCTAssertEqual(reason, .unsafeAnimeRelation)
            XCTAssertTrue(detail.contains("does not contain the numbered season"))
        case .resolved:
            XCTFail("Anime season labels must map to an existing catalog season")
        }
    }

    private func makeArchive(_ files: [String: String]) throws -> Data {
        let archive = try Archive(accessMode: .create)
        for (path, contents) in files.sorted(by: { $0.key < $1.key }) {
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
        }
        return try XCTUnwrap(archive.data)
    }
}

private func assertOfflineAnimeReimport(
    archive: Data,
    snapshot: LibrarySnapshot
) async throws {
    let offlineCatalog = StubCatalog(failsAllRequests: true)
    let reimport = try await TVTimeImportService.previewImport(
        archive,
        into: snapshot,
        catalog: offlineCatalog,
        region: .malta
    )

    XCTAssertEqual(reimport.snapshot.titles.first?.progress?.season, 2)
    XCTAssertEqual(reimport.watchedEpisodeCount, 1)
    XCTAssertEqual(reimport.skippedCount, 0)
    let offlineCounts = await offlineCatalog.callCounts()
    XCTAssertEqual(offlineCounts.resolve, 0)
    XCTAssertEqual(offlineCounts.search, 0)
}

private actor StubCatalog: CatalogProviding {
    private let searchResults: [MediaTitle]
    private let resolvedTitle: MediaTitle?
    private let failsAllRequests: Bool
    private var searchCallCount = 0
    private var resolveCallCount = 0

    init(
        searchResults: [MediaTitle] = [],
        resolvedTitle: MediaTitle? = nil,
        failsAllRequests: Bool = false
    ) {
        self.searchResults = searchResults
        self.resolvedTitle = resolvedTitle
        self.failsAllRequests = failsAllRequests
    }

    func search(_: MediaSearchQuery) async throws -> [MediaTitle] {
        searchCallCount += 1
        if failsAllRequests { throw StubCatalogError.unavailable }
        return searchResults
    }

    func title(
        kind: MediaKind,
        catalogID: Int,
        region _: StreamingRegion
    ) async throws -> MediaTitle {
        if failsAllRequests { throw StubCatalogError.unavailable }
        if let resolvedTitle,
           resolvedTitle.kind == kind,
           resolvedTitle.catalogID == catalogID {
            return resolvedTitle
        }
        guard let title = searchResults.first(where: {
            $0.kind == kind && $0.catalogID == catalogID
        }) else {
            throw CatalogServiceError.notFound
        }
        return title
    }

    func resolve(
        _: ExternalCatalogReference,
        region _: StreamingRegion
    ) async throws -> MediaTitle? {
        resolveCallCount += 1
        if failsAllRequests { throw StubCatalogError.unavailable }
        return resolvedTitle
    }

    func callCounts() -> (search: Int, resolve: Int) {
        (searchCallCount, resolveCallCount)
    }
}

private enum StubCatalogError: Error {
    case unavailable
}

private func makeTitle(
    id: String,
    catalogID: Int,
    title: String,
    alternativeTitles: [String] = [],
    year: Int,
    kind: MediaKind = .series,
    genres: [String] = [],
    seasons: [SeasonSummary]? = nil
) -> MediaTitle {
    MediaTitle(
        id: id,
        catalogID: catalogID,
        title: title,
        alternativeTitles: alternativeTitles,
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
