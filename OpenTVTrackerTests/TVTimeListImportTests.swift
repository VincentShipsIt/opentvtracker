import Foundation
import XCTest
import ZIPFoundation
@testable import OpenTVTracker

final class TVTimeListImportTests: XCTestCase {
    func testNativeExportImportsMixedCustomListInManualOrder() async throws {
        let archive = try makeArchive([
            "tvtime-lists-2026-07-05.csv": """
            list_id,list_name,item_type,tvdb_id,uuid,name,custom_order
            7,Favorites,movie,99,movie-uuid,Past Lives,0
            7,Favorites,series,42,series-uuid,Severance,1
            """
        ])
        var snapshot = snapshotWithSeveranceEpisodes()
        snapshot.sharedSpace.titleIDs = []

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: LocalCatalogService(titles: snapshot.titles),
            region: .malta
        )

        let list = try XCTUnwrap(preview.snapshot.lists?.first(where: { $0.id == "tvtime:7" }))
        XCTAssertEqual(list.name, "Favorites")
        XCTAssertEqual(list.titleIDs, ["past-lives", "severance"])
        XCTAssertEqual(preview.listCount, 1)
        XCTAssertEqual(preview.listMembershipCount, 2)
        XCTAssertTrue(preview.snapshot.sharedSpace.titleIDs.isEmpty)

        let reimport = try await TVTimeImportService.previewImport(
            archive,
            into: preview.snapshot,
            catalog: LocalCatalogService(titles: preview.snapshot.titles),
            region: .malta
        )
        XCTAssertEqual(reimport.listMembershipCount, 0)
    }

    func testGDPRExportImportsSeriesAndMovieMembershipFromGoMapObjects() async throws {
        let archive = try makeArchive([
            "tracking-prod-records-v2.csv": """
            key,s_id,series_name,s_no,ep_no,created_at
            user-series-42,42,Severance,,,2025-02-14T20:30:00Z
            """,
            "tracking-prod-records.csv": """
            uuid,type,entity_type,movie_name,release_date
            movie-uuid,towatch,movie,Past Lives,2023-01-01
            """,
            "lists-prod-lists.csv": """
            name,is_public,objects
            Favorites,false,"[map[created_at:2020-01-01 id:42 type:series uuid:series-uuid] map[created_at:2020-01-01 type:movie uuid:movie-uuid]]"
            favorites,false,"[map[created_at:2020-01-01 id:42 type:series uuid:series-uuid]]"
            """
        ])
        let snapshot = snapshotWithSeveranceEpisodes()

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: LocalCatalogService(titles: snapshot.titles),
            region: .malta
        )

        let list = try XCTUnwrap(
            preview.snapshot.lists?.first(where: { $0.name == "Favorites" })
        )
        XCTAssertEqual(list.titleIDs, ["severance", "past-lives"])
        XCTAssertEqual(preview.snapshot.lists?.count, 2)
        XCTAssertEqual(preview.listMembershipCount, 3)
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
