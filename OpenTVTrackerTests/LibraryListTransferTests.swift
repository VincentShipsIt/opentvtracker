import XCTest
@testable import OpenTVTracker

final class LibraryListTransferTests: XCTestCase {
    func testJSONExportRoundTripsCustomLists() throws {
        var snapshot = LibrarySnapshot.sample
        snapshot.lists = [
            MediaList(
                id: "comfort",
                name: "Comfort",
                titleIDs: ["past-lives", "severance"],
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ]

        let data = try LibraryTransferService.exportJSON(snapshot)
        let preview = try LibraryTransferService.previewImport(data, into: .sample)

        XCTAssertEqual(preview.snapshot.lists, snapshot.lists)
        XCTAssertEqual(preview.listCount, 1)
        XCTAssertEqual(preview.listMembershipCount, 2)
    }

    func testJSONImportRemapsListMembershipToMatchingLocalTitleID() throws {
        var imported = LibrarySnapshot.sample
        imported.lists = [
            MediaList(id: "work", name: "Work", titleIDs: ["severance"], updatedAt: .now)
        ]
        let data = try LibraryTransferService.exportJSON(imported)
        var envelope = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var snapshot = try XCTUnwrap(envelope["snapshot"] as? [String: Any])
        var titles = try XCTUnwrap(snapshot["titles"] as? [[String: Any]])
        let titleIndex = try XCTUnwrap(titles.firstIndex { $0["id"] as? String == "severance" })
        titles[titleIndex]["id"] = "foreign-severance"
        snapshot["titles"] = titles
        var lists = try XCTUnwrap(snapshot["lists"] as? [[String: Any]])
        lists[0]["titleIDs"] = ["foreign-severance"]
        snapshot["lists"] = lists
        envelope["snapshot"] = snapshot

        let foreignData = try JSONSerialization.data(withJSONObject: envelope)
        let preview = try LibraryTransferService.previewImport(foreignData, into: .sample)

        XCTAssertEqual(preview.snapshot.lists?.first?.titleIDs, ["severance"])
    }

    func testOlderJSONImportPreservesNewerSameIDListMembers() throws {
        var current = LibrarySnapshot.sample
        current.lists = [
            MediaList(
                id: "comfort",
                name: "Comfort now",
                titleIDs: ["severance", "past-lives"],
                updatedAt: Date(timeIntervalSince1970: 2_000_000_000)
            )
        ]
        var imported = LibrarySnapshot.sample
        imported.lists = [
            MediaList(
                id: "comfort",
                name: "Old comfort",
                titleIDs: ["severance"],
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ]

        let data = try LibraryTransferService.exportJSON(imported)
        let preview = try LibraryTransferService.previewImport(data, into: current)
        let list = try XCTUnwrap(preview.snapshot.lists?.first)

        XCTAssertEqual(list.name, "Comfort now")
        XCTAssertEqual(list.titleIDs, ["severance", "past-lives"])
    }

    func testListsCSVRoundTripsStableIDsAndOrdering() throws {
        var snapshot = LibrarySnapshot.sample
        snapshot.lists = [
            MediaList(
                id: "cinema",
                name: "Cinema",
                titleIDs: ["past-lives", "severance"],
                updatedAt: .now
            )
        ]

        let data = LibraryTransferService.exportListsCSV(snapshot)
        let preview = try LibraryTransferService.previewImport(data, into: .sample)
        let imported = try XCTUnwrap(preview.snapshot.lists?.first(where: { $0.id == "cinema" }))

        XCTAssertEqual(imported.name, "Cinema")
        XCTAssertEqual(imported.titleIDs, ["past-lives", "severance"])
        XCTAssertEqual(preview.sourceName, "OpenTV lists")
    }

    func testListsCSVMatchesStableTitleIDWithoutMetadataColumns() throws {
        let csv = """
        list_id,list_name,item_position,title_id
        cinema,Cinema,0,severance
        """

        let preview = try LibraryTransferService.previewImport(
            try XCTUnwrap(csv.data(using: .utf8)),
            into: .sample
        )

        XCTAssertEqual(preview.snapshot.lists?.first?.titleIDs, ["severance"])
        XCTAssertEqual(preview.matchedCount, 1)
    }

    func testListsCSVPreservesExistingMembersWhenOneRowCannotResolve() throws {
        var current = LibrarySnapshot.sample
        current.lists = [
            MediaList(
                id: "cinema",
                name: "Cinema",
                titleIDs: ["past-lives", "severance"],
                updatedAt: .now
            )
        ]
        let csv = """
        list_id,list_name,item_position,title_id,catalog_id,title,year,kind
        cinema,Cinema,0,past-lives,666277,Past Lives,2023,movie
        cinema,Cinema,1,missing,999999,Unavailable,2026,series
        """

        let preview = try LibraryTransferService.previewImport(
            try XCTUnwrap(csv.data(using: .utf8)),
            into: current
        )

        XCTAssertEqual(preview.snapshot.lists?.first?.titleIDs, ["past-lives", "severance"])
        XCTAssertEqual(preview.skippedCount, 1)
    }

    func testTitleMatchIndexPreservesFirstMatchAndFallbackSemantics() {
        let titles = [
            Self.title(id: "first", catalogID: 42, title: "First", source: .tmdb),
            Self.title(id: "movie", catalogID: 42, title: "Movie", kind: .movie, source: .tmdb),
            Self.title(id: "alternate", catalogID: 42, title: "Alternate", source: .tvmaze),
            Self.title(
                id: "fallback",
                catalogID: 0,
                title: "Résumé",
                year: 2023,
                kind: .movie
            )
        ]
        let index = LibraryTitleMatchIndex(titles: titles)

        XCTAssertEqual(index.matchingIndex(["catalog_id": "42"]), 0)
        XCTAssertEqual(index.matchingIndex(["catalog_id": "42", "kind": "movie"]), 1)
        XCTAssertEqual(
            index.matchingIndex([
                "catalog_id": "42", "kind": "series", "metadata_source": "tvmaze"
            ]),
            2
        )
        XCTAssertEqual(
            index.matchingIndex([
                "title_id": "missing", "catalog_id": "42", "kind": "series"
            ]),
            0
        )
        XCTAssertEqual(
            index.matchingIndex(["title": "resume", "year": "2023", "kind": "movie"]),
            3
        )
        XCTAssertNil(index.matchingIndex(["catalog_id": "999", "title": "Résumé"]))
    }

    func testListsCSVIndexesLargeLibraryForRepeatedAndUnmatchedRows() throws {
        let titleCount = 5_000
        let rowCount = 5_000
        var current = LibrarySnapshot.empty
        current.titles = (0..<titleCount).map { offset in
            Self.title(
                id: "list-csv-title-\(offset)",
                catalogID: offset + 1,
                title: "List CSV Title \(offset)"
            )
        }
        var rows = [
            "list_id,list_name,list_position,item_position,catalog_id,kind"
        ]
        rows.reserveCapacity(rowCount + 1)
        for offset in 0..<rowCount {
            let catalogID = offset.isMultiple(of: 2) ? titleCount : 900_000_000
            rows.append("bulk-\(offset),Bulk \(offset),\(offset),0,\(catalogID),series")
        }
        let data = Data(rows.joined(separator: "\n").utf8)

        let preview = try LibraryTransferService.previewImport(data, into: current)

        XCTAssertEqual(preview.matchedCount, rowCount / 2)
        XCTAssertEqual(preview.skippedCount, rowCount / 2)
        XCTAssertEqual(preview.listCount, rowCount)
        XCTAssertEqual(preview.listMembershipCount, rowCount / 2)
        XCTAssertEqual(
            preview.snapshot.lists?.first?.titleIDs,
            ["list-csv-title-\(titleCount - 1)"]
        )
        XCTAssertTrue(preview.snapshot.lists?.last?.titleIDs.isEmpty == true)
    }

    func testMergingDuplicateJSONListIDsMaintainsGrowingMembershipIndex() {
        let membershipCount = 5_000
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let imported = (0..<membershipCount).map { offset in
            MediaList(
                id: "growing-list",
                name: "Growing list",
                titleIDs: ["membership-\(offset)"],
                updatedAt: timestamp
            )
        }

        let merged = LibraryTransferService.mergingLists(imported, into: [])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].titleIDs.count, membershipCount)
        XCTAssertEqual(merged[0].titleIDs.first, "membership-0")
        XCTAssertEqual(merged[0].titleIDs.last, "membership-\(membershipCount - 1)")
    }

    private static func title(
        id: String,
        catalogID: Int,
        title: String,
        year: Int = 2026,
        kind: MediaKind = .series,
        source: MetadataSource? = nil
    ) -> MediaTitle {
        var result = MediaTitle(
            id: id,
            catalogID: catalogID,
            title: title,
            year: year,
            kind: kind,
            synopsis: "",
            genres: [],
            runtimeMinutes: 0,
            state: .planned,
            progress: nil,
            rating: 0,
            nextReleaseDescription: nil,
            recommendationReason: nil,
            mood: .any,
            palette: PosterPalette(primaryHex: "000000", secondaryHex: "000000"),
            providers: [],
            reviews: []
        )
        result.metadataSource = source
        return result
    }
}
