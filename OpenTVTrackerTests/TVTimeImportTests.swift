import XCTest
import ZIPFoundation
@testable import OpenTVTracker

final class TVTimeImportTests: XCTestCase {
    func testTVTimeZIPRestoresEpisodeHistoryRatingAndWatchDate() async throws {
        let archive = try makeArchive([
            "tracking-prod-records-v2.csv": """
            key,s_id,series_name,s_no,ep_no,created_at,is_followed
            watch-episode-101,42,Severance,1,1,2025-02-14T20:30:00Z,true
            """,
            "tv_show_rate.csv": """
            tv_show_id,tv_show_name,rate
            42,Severance,5
            """
        ])
        let snapshot = snapshotWithSeveranceEpisodes()

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: LocalCatalogService(titles: snapshot.titles),
            region: .malta
        )

        let severance = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "severance" }))
        XCTAssertEqual(severance.watchedEpisodeIDs, Set(["severance-s1e1"]))
        XCTAssertEqual(severance.userRating, 10)
        XCTAssertEqual(severance.state, .watching)
        XCTAssertTrue(severance.isOnPersonalWatchlist)
        XCTAssertEqual(preview.sourceName, "TV Time")
        XCTAssertEqual(preview.matchedCount, 1)
        XCTAssertEqual(preview.watchedEpisodeCount, 1)
        XCTAssertEqual(preview.watchEventCount, 1)
        XCTAssertEqual(preview.snapshot.sharedSpace.watchEvents?.first?.season, 1)
        XCTAssertEqual(preview.snapshot.sharedSpace.watchEvents?.first?.episode, 1)
    }

    func testReimportDoesNotDuplicateDatedWatchEvents() async throws {
        let archive = try makeArchive([
            "tracking-prod-records-v2.csv": """
            key,s_id,series_name,s_no,ep_no,created_at
            watch-episode-101,42,Severance,1,1,2025-02-14T20:30:00Z
            """
        ])
        let snapshot = snapshotWithSeveranceEpisodes()
        let catalog = LocalCatalogService(titles: snapshot.titles)
        let first = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: catalog,
            region: .malta
        )

        let second = try await TVTimeImportService.previewImport(
            archive,
            into: first.snapshot,
            catalog: catalog,
            region: .malta
        )

        XCTAssertEqual(first.snapshot.sharedSpace.watchEvents?.count, 1)
        XCTAssertEqual(second.snapshot.sharedSpace.watchEvents?.count, 1)
        XCTAssertEqual(second.watchEventCount, 0)
    }

    func testNativeExportIgnoresUnwatchedEpisodesAndRestoresMovieRewatches() async throws {
        let archive = try makeArchive([
            "tvtime-series-episodes-2026.csv": """
            series_tvdb_id,title,season,episode,is_watched,watched_at,rewatch_count
            42,Severance,1,1,true,2025-02-14 20:30:00,1
            42,Severance,1,2,false,,0
            """,
            "tvtime-movies-2026.csv": """
            tvdb_id,title,year,watched_at,is_watched,rewatch_count
            99,Past Lives,2023,2025-03-01T21:00:00Z,true,2
            """
        ])
        let snapshot = snapshotWithSeveranceEpisodes()

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: LocalCatalogService(titles: snapshot.titles),
            region: .malta
        )

        let severance = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "severance" }))
        let movie = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "past-lives" }))
        XCTAssertEqual(severance.watchedEpisodeIDs, Set(["severance-s1e1"]))
        XCTAssertEqual(movie.state, .completed)
        XCTAssertEqual(movie.completedRewatches, 2)
        XCTAssertEqual(preview.watchedEpisodeCount, 1)
        XCTAssertEqual(preview.watchEventCount, 2)
    }

    func testLegacyExportRestoresEpochWatchDateAndMovieRating() async throws {
        let archive = try makeArchive([
            "tracking-prod-records.csv": """
            uuid,type,entity_type,movie_name,release_date,alpha_range_key,watch_date_range_key,created_at
            movie-1,watch,movie,Past Lives,2023-01-01,watch-alpha-past-lives,watch-date-1740862800,2025-03-01 21:00:00
            """,
            "ratings-live-votes.csv": """
            uuid,episode_id,movie_name,vote_key
            movie-1,0,Past Lives,stars-wording-scalev2-29
            """
        ])
        let snapshot = snapshotWithSeveranceEpisodes()

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: LocalCatalogService(titles: snapshot.titles),
            region: .malta
        )

        let movie = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "past-lives" }))
        XCTAssertEqual(movie.state, .completed)
        XCTAssertEqual(movie.userRating, 8)
        XCTAssertEqual(movie.lastWatchedAt, Date(timeIntervalSince1970: 1_740_862_800))
        XCTAssertEqual(preview.watchEventCount, 1)
    }

    func testZIPWithoutTVTimeTrackingDataIsRejected() async throws {
        let archive = try makeArchive(["profile.csv": "name\nVincent\n"])

        do {
            _ = try await TVTimeImportService.previewImport(
                archive,
                into: .sample,
                catalog: LocalCatalogService(titles: LibrarySnapshot.sample.titles),
                region: .malta
            )
            XCTFail("Expected unsupported TV Time data to be rejected")
        } catch let error as TVTimeImportError {
            XCTAssertEqual(error.errorDescription, "This ZIP does not contain recognizable TV Time tracking data.")
        }
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
                    ),
                    EpisodeSummary(
                        id: "severance-s1e2",
                        number: 2,
                        title: "Half Loop",
                        airDate: Date(timeIntervalSince1970: 1_645_747_200),
                        runtimeMinutes: 53
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
