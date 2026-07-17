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
        snapshot.diaryEntries = [Self.diaryEntry]

        let data = try LibraryTransferService.exportJSON(snapshot)
        let preview = try LibraryTransferService.previewImport(data, into: .sample)

        let imported = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "severance" }))
        XCTAssertEqual(imported.userRating, 9.5)
        XCTAssertEqual(imported.notes, "Watch the elevator details.")
        XCTAssertEqual(imported.completedRewatches, 2)
        XCTAssertTrue(imported.isOnPersonalWatchlist)
        XCTAssertEqual(preview.snapshot.diaryEntries, [Self.diaryEntry])
        XCTAssertEqual(preview.matchedCount, snapshot.titles.count)
    }

    func testDiaryCSVExportAndImportPreservesAllPrivateFields() throws {
        var snapshot = LibrarySnapshot.sample
        snapshot.diaryEntries = [Self.diaryCSVEntry]

        let data = LibraryTransferService.exportDiaryCSV(snapshot)
        var destination = LibrarySnapshot.sample
        destination.diaryEntries = []
        let preview = try LibraryTransferService.previewImport(data, into: destination)

        XCTAssertEqual(preview.sourceName, "OpenTV diary")
        XCTAssertEqual(preview.addedCount, 1)
        XCTAssertEqual(preview.snapshot.diaryEntries, [Self.diaryCSVEntry])
    }

    func testLegacyJSONImportBackfillsDiaryFromWatchEvents() throws {
        var imported = LibrarySnapshot.sample
        imported.diaryEntries = nil
        imported.sharedSpace.watchEvents = [
            SharedWatchEvent(
                id: "legacy-json-watch",
                titleID: "severance",
                memberID: "vincent",
                kind: .watched,
                season: nil,
                episode: nil,
                occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                supersedesEventID: nil
            )
        ]
        let data = try LibraryArchiveCodec.encode(imported, prettyPrinted: false)
        var destination = LibrarySnapshot.sample
        destination.diaryEntries = []

        let preview = try LibraryTransferService.previewImport(data, into: destination)

        XCTAssertEqual(preview.snapshot.diaryEntries?.map(\.id), ["diary:legacy-json-watch"])
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

    private static let diaryEntry = ViewingDiaryEntry(
        id: "diary-entry",
        titleID: "severance",
        scope: .episode,
        seasonNumber: 1,
        episodeID: "severance-s1e1",
        episodeNumber: 1,
        watchedAt: Date(timeIntervalSince1970: 1_700_000_000),
        rating: 9,
        note: "That hallway, \"scene\".\nUnforgettable.",
        isRewatch: true,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
    )

    private static let diaryCSVEntry = ViewingDiaryEntry(
        id: "diary-entry",
        titleID: "severance",
        scope: .episode,
        seasonNumber: 1,
        episodeID: "severance-s1e1",
        episodeNumber: 1,
        watchedAt: Date(timeIntervalSince1970: 1_700_000_000),
        rating: 9,
        note: "That hallway, \"scene\".\nUnforgettable.",
        isRewatch: true,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000.125),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
    )
}
