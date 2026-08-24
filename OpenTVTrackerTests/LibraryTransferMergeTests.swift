import XCTest
@testable import OpenTVTracker

extension LibraryTransferTests {
    func testJSONImportDiscardsResolutionAliasesWithoutRetainedTitles() throws {
        var snapshot = LibrarySnapshot.sample
        snapshot.importResolutionAliases = [
            "series:legacy:missing": ImportResolutionAlias(kind: .series, catalogID: 999_999)
        ]

        let preview = try LibraryTransferService.previewImport(
            LibraryTransferService.exportJSON(snapshot),
            into: .sample
        )

        XCTAssertNil(preview.snapshot.importResolutionAliases?["series:legacy:missing"])
    }

    func testJSONImportRejectsUnsupportedFutureSchema() throws {
        let exported = try LibraryTransferService.exportJSON(.sample)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: exported) as? [String: Any]
        )
        object["schemaVersion"] = LibraryArchiveEnvelope.currentSchemaVersion + 1
        let futureArchive = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(
            try LibraryTransferService.previewImport(futureArchive, into: .empty)
        ) { error in
            guard let archiveError = error as? LibraryArchiveError,
                  case .unsupportedSchema(let version) = archiveError else {
                return XCTFail("Expected an unsupported schema error, got \(error)")
            }
            XCTAssertEqual(version, LibraryArchiveEnvelope.currentSchemaVersion + 1)
        }
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

    func testLegacyJSONImportMigratesContinuingSeriesToCaughtUp() throws {
        var snapshot = LibrarySnapshot.sample
        snapshot.schemaVersion = 4
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[index].state = .completed
        snapshot.titles[index].seriesLifecycle = .continuing

        let data = try LibraryTransferService.exportJSON(snapshot)
        let preview = try LibraryTransferService.previewImport(data, into: .sample)

        XCTAssertEqual(
            preview.snapshot.titles.first(where: { $0.id == "severance" })?.state,
            .caughtUp
        )
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

    func testCSVImportIndexesLargeLibraryForRepeatedAndUnmatchedRows() throws {
        let titleCount = 5_000
        let rowCount = 5_000
        var current = LibrarySnapshot.empty
        current.titles = (0..<titleCount).map { offset in
            Self.importTitle(
                id: "csv-title-\(offset)",
                catalogID: offset + 1,
                title: "CSV Title \(offset)",
                year: 2_000 + offset % 25,
                kind: offset.isMultiple(of: 2) ? .movie : .series
            )
        }
        var rows = ["catalog_id,kind,state"]
        rows.reserveCapacity(rowCount + 1)
        for offset in 0..<rowCount {
            rows.append(
                offset.isMultiple(of: 2)
                    ? "\(titleCount),series,paused"
                    : "900000000,series,completed"
            )
        }
        let data = Data(rows.joined(separator: "\n").utf8)

        let preview = try LibraryTransferService.previewImport(data, into: current)

        XCTAssertEqual(preview.matchedCount, 1)
        XCTAssertEqual(preview.duplicateCount, rowCount / 2 - 1)
        XCTAssertEqual(preview.skippedCount, rowCount / 2)
        XCTAssertEqual(preview.snapshot.titles.last?.id, "csv-title-\(titleCount - 1)")
        XCTAssertEqual(preview.snapshot.titles.last?.state, .paused)
    }

    func testCompactJSONImportMergesTwentyThousandUniqueTitlesAliasesAndLists() throws {
        let titleCount = 20_000
        var imported = LibrarySnapshot.empty
        imported.titles = (0..<titleCount).map { offset in
            var title = Self.importTitle(
                id: "bulk-title-\(offset)",
                catalogID: offset + 1,
                title: "Bulk Title \(offset)",
                year: 2_000 + offset % 25,
                kind: offset.isMultiple(of: 2) ? .movie : .series
            )
            if offset == titleCount - 1 {
                title.state = .paused
                title.userRating = 9.5
                title.notes = "Private final-title note"
                title.personalWatchlist = true
            }
            return title
        }
        imported.importResolutionAliases = Dictionary(
            uniqueKeysWithValues: imported.titles.map { title in
                ("bulk-alias-\(title.id)", ImportResolutionAlias(title: title))
            }
        )
        imported.lists = imported.titles.map { title in
            MediaList(
                id: "bulk-list-\(title.id)",
                name: "List for \(title.title)",
                titleIDs: [title.id],
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        }
        let compactJSON = try LibraryArchiveCodec.encode(imported, prettyPrinted: false)

        let preview = try LibraryTransferService.previewImport(compactJSON, into: .empty)

        XCTAssertEqual(preview.addedCount, titleCount)
        XCTAssertEqual(preview.matchedCount, 0)
        XCTAssertEqual(preview.duplicateCount, 0)
        XCTAssertEqual(preview.snapshot.titles.count, titleCount)
        XCTAssertEqual(preview.snapshot.importResolutionAliases?.count, titleCount)
        XCTAssertEqual(preview.snapshot.lists?.count, titleCount)
        let finalTitle = try XCTUnwrap(preview.snapshot.titles.last)
        XCTAssertEqual(finalTitle.id, "bulk-title-\(titleCount - 1)")
        XCTAssertEqual(finalTitle.state, .paused)
        XCTAssertEqual(finalTitle.userRating, 9.5)
        XCTAssertEqual(finalTitle.notes, "Private final-title note")
        XCTAssertTrue(finalTitle.isOnPersonalWatchlist)
        XCTAssertEqual(preview.snapshot.lists?.last?.titleIDs, [finalTitle.id])
    }

    func testJSONImportPreservesFirstMatchAcrossCatalogAndLegacyTitleIdentities() throws {
        let (current, imported) = Self.firstMatchFixture()

        let preview = try LibraryTransferService.previewImport(
            LibraryArchiveCodec.encode(imported, prettyPrinted: false),
            into: current
        )

        XCTAssertEqual(preview.matchedCount, 2)
        XCTAssertEqual(preview.addedCount, 0)
        XCTAssertEqual(preview.snapshot.titles.count, current.titles.count)
        XCTAssertEqual(
            preview.snapshot.titles.first(where: { $0.id == "legacy-first" })?.notes,
            "Matched the earlier uncataloged title"
        )
        XCTAssertNil(
            preview.snapshot.titles.first(where: { $0.id == "catalog-second" })?.notes
        )
        XCTAssertEqual(
            preview.snapshot.titles.first(where: { $0.id == "positive-title-match" })?.userRating,
            8.5
        )
    }

    private static func importTitle(
        id: String,
        catalogID: Int,
        title: String,
        year: Int,
        kind: MediaKind
    ) -> MediaTitle {
        MediaTitle(
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
    }

    private static func firstMatchFixture() -> (
        current: LibrarySnapshot,
        imported: LibrarySnapshot
    ) {
        var current = LibrarySnapshot.empty
        current.titles = [
            Self.importTitle(
                id: "legacy-first",
                catalogID: 0,
                title: "Dual Match",
                year: 2024,
                kind: .series
            ),
            Self.importTitle(
                id: "catalog-second",
                catalogID: 42,
                title: "Different Catalog Title",
                year: 2024,
                kind: .series
            ),
            Self.importTitle(
                id: "positive-title-match",
                catalogID: 77,
                title: "Legacy Import Match",
                year: 2023,
                kind: .movie
            )
        ]
        var positiveImport = Self.importTitle(
            id: "foreign-positive",
            catalogID: 42,
            title: "Dual Match",
            year: 2024,
            kind: .series
        )
        positiveImport.notes = "Matched the earlier uncataloged title"
        var legacyImport = Self.importTitle(
            id: "foreign-legacy",
            catalogID: 0,
            title: "Legacy Import Match",
            year: 2023,
            kind: .movie
        )
        legacyImport.userRating = 8.5
        var imported = LibrarySnapshot.empty
        imported.titles = [positiveImport, legacyImport]
        return (current, imported)
    }
}
