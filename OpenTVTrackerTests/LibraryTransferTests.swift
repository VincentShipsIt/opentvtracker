import XCTest
@testable import OpenTVTracker

final class LibraryTransferTests: XCTestCase {
    func testLegacyActivityWithoutTitleIDStillDecodes() throws {
        let data = Data(
            #"{"id":"activity","memberID":"member","description":"watched Silo","relativeDate":"Now","symbol":"checkmark"}"#.utf8
        )

        let activity = try JSONDecoder().decode(SharedActivity.self, from: data)

        XCTAssertNil(activity.titleID)
    }

    func testLegacyProviderIDDecodesIntoTypedIdentity() throws {
        let data = Data(
            #"{"id":"apple-tv","name":"Apple TV+","symbol":"apple.logo","brandHex":"1C1C1E"}"#.utf8
        )

        let provider = try JSONDecoder().decode(StreamingProvider.self, from: data)

        XCTAssertEqual(provider.id, .appleTV)
    }

    func testUnknownProviderIDIsRejectedAtTheNetworkBoundary() throws {
        let data = Data(#"{"id":"made-up-service","name":"Unknown","symbol":"tv"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(StreamingProvider.self, from: data))
    }

    func testJSONExportRoundTripsTrackingMetadata() throws {
        var snapshot = LibrarySnapshot.sample
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[index].userRating = 9.5
        snapshot.titles[index].notes = "Watch the elevator details."
        snapshot.titles[index].rewatchCount = 2
        snapshot.titles[index].personalWatchlist = true

        let data = try LibraryTransferService.exportJSON(snapshot)
        let preview = try LibraryTransferService.previewImport(data, into: .sample)

        let imported = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "severance" }))
        XCTAssertEqual(imported.userRating, 9.5)
        XCTAssertEqual(imported.notes, "Watch the elevator details.")
        XCTAssertEqual(imported.completedRewatches, 2)
        XCTAssertTrue(imported.isOnPersonalWatchlist)
        XCTAssertEqual(preview.matchedCount, snapshot.titles.count)
    }

    func testCSVImportRestoresPersonalWatchlistWithoutChangingState() throws {
        let csv = """
        catalog_id,title,year,state,personal_watchlist
        95396,Severance,2022,watching,true
        """

        let preview = try LibraryTransferService.previewImport(
            try XCTUnwrap(csv.data(using: .utf8)),
            into: .sample
        )

        let severance = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "severance" }))
        XCTAssertEqual(severance.state, .watching)
        XCTAssertTrue(severance.isOnPersonalWatchlist)
    }

    func testCSVImportIsIdempotentAndReportsDuplicates() throws {
        let csv = """
        catalog_id,title,year,state,rating
        95396,Severance,2022,paused,9
        95396,Severance,2022,completed,10
        """

        let preview = try LibraryTransferService.previewImport(
            try XCTUnwrap(csv.data(using: .utf8)),
            into: .sample
        )

        let severance = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "severance" }))
        XCTAssertEqual(severance.state, .paused)
        XCTAssertEqual(severance.userRating, 9)
        XCTAssertEqual(preview.matchedCount, 1)
        XCTAssertEqual(preview.duplicateCount, 1)
    }

    func testSwiftDataStorePersistsVersionedSnapshot() async throws {
        let store = try SwiftDataLibraryStore(isStoredInMemoryOnly: true)
        var snapshot = LibrarySnapshot.sample
        snapshot.selectedProviderIDs = [StreamingProvider.appleTV.id]

        try await store.save(snapshot)
        let loaded = try await store.load()

        XCTAssertEqual(loaded?.selectedProviderIDs, [StreamingProvider.appleTV.id])
        XCTAssertEqual(loaded?.schemaVersion, LibraryArchiveEnvelope.currentSchemaVersion)
    }

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
