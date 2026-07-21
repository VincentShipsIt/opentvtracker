import XCTest
import ZIPFoundation
@testable import OpenTVTracker

final class TVTimeImportIntegrityTests: XCTestCase {
    func testIntegrityReportKeepsUnmatchedTitlesInResolutionQueue() async throws {
        let archive = try makeArchive([
            "tracking-prod-records-v2.csv": """
            key,s_id,series_name,s_no,ep_no,created_at
            watch-episode-101,42,Severance,1,1,2025-02-14T20:30:00Z
            """,
            "tracking-prod-records.csv": """
            uuid,type,entity_type,movie_name,release_date,watch_date_range_key
            missing-movie,watch,movie,Unknown Festival Film,2024-01-01,watch-date-1740862800
            """
        ])
        let snapshot = snapshotWithSeveranceEpisodes()

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: LocalCatalogService(titles: snapshot.titles),
            region: .malta
        )

        XCTAssertEqual(preview.resolutionIssues.count, 1)
        XCTAssertEqual(preview.resolutionIssues.first?.displayTitle, "Unknown Festival Film")
        XCTAssertEqual(preview.resolutionIssues.first?.reason, .noCatalogMatch)
        XCTAssertEqual(metric(.shows, in: preview), ImportCountComparison(
            category: .shows,
            sourceCount: 1,
            importedCount: 1
        ))
        XCTAssertEqual(metric(.movies, in: preview), ImportCountComparison(
            category: .movies,
            sourceCount: 1,
            importedCount: 0
        ))
        XCTAssertEqual(metric(.episodes, in: preview)?.importedCount, 1)
    }

    func testAmbiguousExactTitlesRequireManualResolution() async throws {
        var first = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.kind == .series }))
        first.title = "The Office"
        first.year = 2001
        var second = try XCTUnwrap(LibrarySnapshot.sample.titles.dropFirst().first(where: { $0.kind == .series }))
        second.title = "The Office"
        second.year = 2005
        let archive = try makeArchive([
            "followed_tv_show.csv": """
            tv_show_id,tv_show_name,is_followed
            office-source,The Office,true
            """
        ])

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: .empty,
            catalog: LocalCatalogService(titles: [first, second]),
            region: .malta
        )

        XCTAssertEqual(preview.resolutionIssues.first?.reason, .ambiguousCatalogMatch)
        XCTAssertEqual(metric(.shows, in: preview)?.sourceCount, 1)
        XCTAssertEqual(metric(.shows, in: preview)?.importedCount, 0)
    }
}

extension TVTimeImportIntegrityTests {
    func testAmbiguousLocalTitlesWithoutYearRequireManualResolution() async throws {
        var first = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.kind == .series }))
        first.title = "The Office"
        first.year = 2001
        var second = try XCTUnwrap(
            LibrarySnapshot.sample.titles.dropFirst().first(where: { $0.kind == .series })
        )
        second.title = "The Office"
        second.year = 2005
        let archive = try makeArchive([
            "followed_tv_show.csv": """
            tv_show_id,tv_show_name,is_followed
            office-source,The Office,true
            """
        ])
        var snapshot = LibrarySnapshot.empty
        snapshot.titles = [first, second]

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: LocalCatalogService(titles: []),
            region: .malta
        )

        XCTAssertEqual(preview.resolutionIssues.count, 1)
        XCTAssertEqual(preview.resolutionIssues.first?.reason, .noCatalogMatch)
        XCTAssertEqual(preview.snapshot.titles.count, 2)
    }

    func testSavedAliasWinsOverAmbiguousLocalTitleMatch() async throws {
        var first = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.kind == .series }))
        first.title = "The Office"
        first.year = 2001
        first.personalWatchlist = false
        var second = try XCTUnwrap(LibrarySnapshot.sample.titles.dropFirst().first(where: { $0.kind == .series }))
        second.title = "The Office"
        second.year = 2005
        second.personalWatchlist = false
        let identity = "series:source:office-source"
        let archive = try makeArchive([
            "followed_tv_show.csv": """
            tv_show_id,tv_show_name,is_followed
            office-source,The Office,true
            """
        ])
        var snapshot = LibrarySnapshot.empty
        snapshot.titles = [first, second]
        snapshot.importResolutionAliases = [
            identity: ImportResolutionAlias(kind: second.kind, catalogID: second.catalogID)
        ]

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: AliasOnlyCatalog(title: second),
            region: .malta
        )

        XCTAssertEqual(preview.snapshot.titles[0].personalWatchlist, false)
        XCTAssertEqual(preview.snapshot.titles[1].personalWatchlist, true)
    }

    func testManualResolutionPersistsAliasForSafeReimport() async throws {
        let archive = try makeArchive([
            "tvtime-movies-2026.csv": """
            tvdb_id,title,year,watched_at,is_watched,rewatch_count
            777,Moon Festival Cut,2024,2025-03-01T21:00:00Z,true,1
            """
        ])
        let snapshot = snapshotWithSeveranceEpisodes()
        let chosenTitle = try XCTUnwrap(snapshot.titles.first(where: { $0.kind == .movie }))
        let session = try await TVTimeImportService.prepareImport(
            archive,
            into: snapshot,
            catalog: LocalCatalogService(titles: snapshot.titles),
            region: .malta
        )
        let initial = await session.preview()
        let issue = try XCTUnwrap(initial.resolutionIssues.first)

        let resolved = await session.preview(manualResolutions: [issue.id: chosenTitle])

        XCTAssertTrue(resolved.resolutionIssues.isEmpty)
        XCTAssertEqual(
            resolved.snapshot.importResolutionAliases?[issue.id],
            ImportResolutionAlias(kind: chosenTitle.kind, catalogID: chosenTitle.catalogID)
        )

        let reimported = try await TVTimeImportService.previewImport(
            archive,
            into: resolved.snapshot,
            catalog: AliasOnlyCatalog(title: chosenTitle),
            region: .malta
        )

        XCTAssertTrue(reimported.resolutionIssues.isEmpty)
        XCTAssertEqual(reimported.snapshot.titles.filter { $0.id == chosenTitle.id }.count, 1)
    }

    func testImportWarnsAboutMissingAndUnsupportedRecords() async throws {
        let archive = try makeArchive([
            "tracking-prod-records.csv": """
            uuid,type,entity_type,movie_name,series_name,s_id,season_number,episode_number
            ,watch,series,,Severance,42,1,1
            ,watch,series,,Severance,42,1,99
            ,reaction,series,,Severance,42,1,1
            ,watch,series,,,,1,2
            """
        ])
        let snapshot = snapshotWithSeveranceEpisodes()

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: LocalCatalogService(titles: snapshot.titles),
            region: .malta
        )

        XCTAssertTrue(preview.warnings.contains { $0.id.hasPrefix("unsupported-records-1") })
        XCTAssertTrue(preview.warnings.contains { $0.id.hasPrefix("missing-identities-1") })
        XCTAssertTrue(preview.warnings.contains { $0.id == "unmatched-episodes-1" })
    }

    func testDiagnosticsOnlyArchiveReturnsAReportablePreview() async throws {
        let archive = try makeArchive([
            "tracking-prod-records.csv": """
            uuid,type,entity_type,movie_name,series_name,s_id
            ,watch,series,,,
            """
        ])

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: .empty,
            catalog: LocalCatalogService(titles: []),
            region: .malta
        )

        XCTAssertEqual(preview.skippedCount, 1)
        XCTAssertTrue(preview.warnings.contains { $0.id == "missing-identities-1" })
    }

    func testHundredThousandRowsRemainIdempotent() async throws {
        let header = "key,s_id,series_name,s_no,ep_no,created_at,padding\n"
        let padding = String(repeating: "x", count: 220)
        var rows: [String] = []
        rows.reserveCapacity(100_000)
        for episode in 1...50_000 {
            let row = "watch-episode-\(episode),42,Severance,1,\(episode),2025-02-14T20:30:00Z,\(padding)\n"
            rows.append(row)
            rows.append(row)
        }
        let archive = try makeArchive([
            "tracking-prod-records-v2.csv": header + rows.joined()
        ])

        let parsed = try TVTimeArchiveParser.parse(archive)

        XCTAssertEqual(parsed.duplicateCount, 50_000)
        XCTAssertEqual(parsed.entities.first?.watches.count, 50_000)
    }

    func testArchivedSourceWatchlistEntryReportsDestinationMismatch() async throws {
        let archive = try makeArchive([
            "tracking-prod-records.csv": """
            type,entity_type,series_name,s_id
            towatch,series,Severance,42
            """,
            "tvtime-series-2026.csv": """
            tvdb_id,title,status
            42,Severance,stopped
            """
        ])
        let snapshot = snapshotWithSeveranceEpisodes()

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: LocalCatalogService(titles: snapshot.titles),
            region: .malta
        )

        XCTAssertEqual(metric(.watchlist, in: preview)?.sourceCount, 1)
        XCTAssertEqual(metric(.watchlist, in: preview)?.importedCount, 0)
    }

    func testUnmatchedEpisodeDoesNotAdvanceProgressOrWatchDate() async throws {
        let archive = try makeArchive([
            "tracking-prod-records-v2.csv": """
            key,s_id,series_name,s_no,ep_no,created_at
            watch-episode-101,42,Severance,1,1,2025-02-14T20:30:00Z
            watch-episode-999,42,Severance,1,99,2025-03-14T20:30:00Z
            """
        ])
        var snapshot = snapshotWithSeveranceEpisodes()
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[index].progress = nil
        snapshot.titles[index].lastWatchedAt = nil

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: LocalCatalogService(titles: snapshot.titles),
            region: .malta
        )

        let severance = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "severance" }))
        let event = try XCTUnwrap(preview.snapshot.sharedSpace.watchEvents?.first)
        XCTAssertEqual(severance.progress?.episode, 1)
        XCTAssertEqual(severance.lastWatchedAt, event.occurredAt)
        XCTAssertEqual(event.episode, 1)
        XCTAssertEqual(preview.watchedEpisodeCount, 1)
        XCTAssertEqual(preview.skippedCount, 1)
        XCTAssertEqual(metric(.episodes, in: preview)?.sourceCount, 2)
        XCTAssertEqual(metric(.episodes, in: preview)?.importedCount, 1)
    }

    private func metric(
        _ category: ImportMetricCategory,
        in preview: LibraryImportPreview
    ) -> ImportCountComparison? {
        preview.integrityCounts.first { $0.category == category }
    }

    private func snapshotWithSeveranceEpisodes() -> LibrarySnapshot {
        var snapshot = LibrarySnapshot.sample
        guard let index = snapshot.titles.firstIndex(where: { $0.id == "severance" }) else {
            return snapshot
        }
        snapshot.titles[index].watchedEpisodeIDs = []
        snapshot.titles[index].seasons = [
            SeasonSummary(
                id: "severance-s1",
                number: 1,
                title: "Season 1",
                episodes: [
                    EpisodeSummary(
                        id: "severance-s1e1",
                        number: 1,
                        title: "Good News About Hell",
                        airDate: Date(timeIntervalSince1970: 1_645_142_400),
                        runtimeMinutes: 57
                    )
                ]
            )
        ]
        snapshot.sharedSpace.watchEvents = []
        return snapshot
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

private struct AliasOnlyCatalog: CatalogProviding {
    let title: MediaTitle

    func search(_ query: MediaSearchQuery) async throws -> [MediaTitle] {
        throw CatalogServiceError.unavailable
    }

    func title(kind: MediaKind, catalogID: Int, region: StreamingRegion) async throws -> MediaTitle {
        guard title.kind == kind, title.catalogID == catalogID else {
            throw CatalogServiceError.notFound
        }
        return title
    }
}
