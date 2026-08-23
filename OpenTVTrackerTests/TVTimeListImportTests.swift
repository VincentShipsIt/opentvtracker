import Foundation
import XCTest
import ZIPFoundation
@testable import OpenTVTracker

final class TVTimeListImportTests: XCTestCase {
    func testTwentyThousandUniqueTVTimeListsMergeWithoutRepeatedListScans() {
        let listCount = 20_000
        let imported = (0..<listCount).map { index in
            TVTimeList(
                id: "tvtime:bulk:\(index)",
                name: "Bulk list \(index)",
                memberships: []
            )
        }

        let result = TVTimeListMerger.merge(imported, into: [], resolved: [:])

        XCTAssertEqual(result.lists.count, listCount)
        XCTAssertEqual(result.lists.first?.id, "tvtime:bulk:0")
        XCTAssertEqual(result.lists.last?.id, "tvtime:bulk:\(listCount - 1)")
        XCTAssertEqual(result.importedMemberships, 0)
        XCTAssertEqual(result.skippedMemberships, 0)
    }

    func testGDPRObjectsIsTheOnlyFieldGrantedTheLargerByteLimit() throws {
        let rows = try TVTimeCSV.rows(
            "name,objects\nList,123456789",
            maximumFieldSize: 8,
            maximumFieldSizesByHeader: ["objects": 16]
        )
        XCTAssertEqual(rows.last, ["List", "123456789"])

        XCTAssertThrowsError(
            try TVTimeCSV.rows(
                "name,objects\n123456789,short",
                maximumFieldSize: 8,
                maximumFieldSizesByHeader: ["objects": 16]
            )
        ) { error in
            XCTAssertEqual(error as? LibraryImportSafetyError, .fieldTooLarge)
        }
    }

    func testGDPRMembershipLimitDeduplicatesBeforeAppending() throws {
        var lists: [MediaList.ID: TVTimeList] = [:]
        var membershipAccumulator = TVTimeListMembershipAccumulator(maximumCount: 2)
        let records = [[
            "name": "Favorites",
            "objects": """
            [map[id:1 type:series] map[id:1 type:series] map[id:2 type:series] map[id:3 type:series]]
            """
        ]]

        XCTAssertThrowsError(
            try TVTimeListParser.parseGDPR(
                records,
                lists: &lists,
                membershipAccumulator: &membershipAccumulator
            )
        ) { error in
            XCTAssertEqual(error as? LibraryImportSafetyError, .tooManyTVTimeListMemberships)
        }

        let list = try XCTUnwrap(lists["tvtime:gdpr:4661766f7269746573"])
        XCTAssertEqual(list.memberships.map(\.entityIdentity), [
            "series:source:1",
            "series:source:2"
        ])
        XCTAssertEqual(list.memberships.map(\.order), [0, 2])
        XCTAssertEqual(membershipAccumulator.count, 2)
        XCTAssertEqual(membershipAccumulator.identityIndex[list.id]?.count, 2)
    }

    func testGDPRObjectSubfieldsRemainNormallyBounded() throws {
        var lists: [MediaList.ID: TVTimeList] = [:]
        var membershipAccumulator = TVTimeListMembershipAccumulator()

        XCTAssertThrowsError(
            try TVTimeListParser.parseGDPR(
                [["name": "Favorites", "objects": "[map[id:12345 type:series]]"]],
                lists: &lists,
                membershipAccumulator: &membershipAccumulator,
                maximumObjectFieldSize: 4
            )
        ) { error in
            XCTAssertEqual(error as? LibraryImportSafetyError, .fieldTooLarge)
        }

        XCTAssertTrue(lists.isEmpty)
        XCTAssertEqual(membershipAccumulator.count, 0)
    }

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
