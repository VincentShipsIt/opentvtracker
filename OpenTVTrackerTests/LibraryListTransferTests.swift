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
}
