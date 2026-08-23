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
        snapshot.diaryEntries = [LibraryDiaryTransferTests.diaryEntry]
        snapshot.titles[index].seriesLifecycle = .continuing
        snapshot.titles[index].isUpNextPinned = true
        snapshot.titles[index].upNextSnoozedUntil = Date(timeIntervalSince1970: 2_000_000_000)
        snapshot.titles[index].upNextManualOrder = 3
        snapshot.importResolutionAliases = [
            "series:source:42": ImportResolutionAlias(kind: .series, catalogID: 95_396)
        ]

        let data = try LibraryTransferService.exportJSON(snapshot)
        let preview = try LibraryTransferService.previewImport(data, into: .sample)

        let imported = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "severance" }))
        XCTAssertEqual(imported.userRating, 9.5)
        XCTAssertEqual(imported.notes, "Watch the elevator details.")
        XCTAssertEqual(imported.completedRewatches, 2)
        XCTAssertTrue(imported.isOnPersonalWatchlist)
        XCTAssertEqual(preview.snapshot.diaryEntries, [LibraryDiaryTransferTests.diaryEntry])
        XCTAssertEqual(imported.seriesLifecycle, .continuing)
        XCTAssertEqual(imported.isUpNextPinned, true)
        XCTAssertEqual(imported.upNextSnoozedUntil, Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertEqual(imported.upNextManualOrder, 3)
        XCTAssertEqual(
            preview.snapshot.importResolutionAliases?["series:source:42"],
            ImportResolutionAlias(kind: .series, catalogID: 95_396)
        )
        XCTAssertEqual(preview.matchedCount, snapshot.titles.count)
    }

    func testLegacyBackupMissingTrackingFieldsPreservesCatalogValues() throws {
        var imported = try XCTUnwrap(LibrarySnapshot.sample.titles.first)
        var catalog = imported
        imported.progress = nil
        imported.userRating = nil
        imported.notes = nil
        imported.rewatchCount = nil
        imported.lastWatchedAt = nil
        imported.isDismissed = nil
        imported.isDisliked = nil
        imported.personalWatchlist = nil
        imported.isUpNextPinned = nil
        imported.upNextSnoozedUntil = nil
        imported.upNextManualOrder = nil
        catalog.progress = EpisodeProgress(season: 2, episode: 1, totalEpisodes: 10)
        catalog.userRating = 9
        catalog.notes = "Keep"
        catalog.rewatchCount = 2
        catalog.lastWatchedAt = Date(timeIntervalSince1970: 100)
        catalog.isDismissed = true
        catalog.isDisliked = true
        catalog.personalWatchlist = true
        catalog.isUpNextPinned = true
        catalog.upNextSnoozedUntil = Date(timeIntervalSince1970: 200)
        catalog.upNextManualOrder = 4

        let merged = LibraryTransferService.mergingTracking(
            from: imported,
            into: catalog,
            fromSchemaVersion: LibraryArchiveEnvelope.currentSchemaVersion - 1
        )

        XCTAssertEqual(merged.progress, catalog.progress)
        XCTAssertEqual(merged.userRating, catalog.userRating)
        XCTAssertEqual(merged.notes, catalog.notes)
        XCTAssertEqual(merged.completedRewatches, catalog.completedRewatches)
        XCTAssertEqual(merged.lastWatchedAt, catalog.lastWatchedAt)
        XCTAssertEqual(merged.isDismissed, catalog.isDismissed)
        XCTAssertEqual(merged.isDisliked, catalog.isDisliked)
        XCTAssertEqual(merged.personalWatchlist, catalog.personalWatchlist)
        XCTAssertEqual(merged.isUpNextPinned, catalog.isUpNextPinned)
        XCTAssertEqual(merged.upNextSnoozedUntil, catalog.upNextSnoozedUntil)
        XCTAssertEqual(merged.upNextManualOrder, catalog.upNextManualOrder)
    }

    func testCSVImportRestoresExpandedStateAndQueueIntent() throws {
        let csv = """
        catalog_id,title,year,state,series_lifecycle,is_up_next_pinned,up_next_snoozed_until,up_next_manual_order
        95396,Severance,2022,caught_up,continuing,true,2033-05-18T03:33:20Z,7
        """

        let preview = try LibraryTransferService.previewImport(
            try XCTUnwrap(csv.data(using: .utf8)),
            into: .sample
        )

        let severance = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "severance" }))
        XCTAssertEqual(severance.state, .caughtUp)
        XCTAssertEqual(severance.seriesLifecycle, .continuing)
        XCTAssertEqual(severance.isUpNextPinned, true)
        XCTAssertEqual(severance.upNextSnoozedUntil, Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertEqual(severance.upNextManualOrder, 7)
    }

    func testCSVImportRejectsCaughtUpForMovies() throws {
        let csv = """
        catalog_id,title,year,state
        666277,Past Lives,2023,caught_up
        """

        let preview = try LibraryTransferService.previewImport(
            try XCTUnwrap(csv.data(using: .utf8)),
            into: .sample
        )

        XCTAssertEqual(
            preview.snapshot.titles.first(where: { $0.id == "past-lives" })?.state,
            .completed
        )
    }

    func testCompleteJSONExportPreservesCurrentLocalSnapshot() throws {
        var snapshot = LibrarySnapshot.sample
        snapshot.selectedProviderIDs = [StreamingProvider.appleTV.id]
        snapshot.allowsAIReranking = true
        snapshot.streamingRegionCode = "MT"
        snapshot.contentLanguageCode = "fr"
        snapshot.hasCompletedFirstRun = true

        let data = try LibraryTransferService.exportJSON(snapshot)
        let decoded = try LibraryArchiveCodec.decode(data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.hasCompletedFirstRun, true)
    }

    func testCompleteJSONImportRestoresCurrentLocalSnapshotIntoEmptyLibrary() throws {
        var snapshot = LibrarySnapshot.sample
        snapshot.selectedProviderIDs = [StreamingProvider.appleTV.id]
        snapshot.allowsAIReranking = true
        snapshot.streamingRegionCode = "MT"
        snapshot.contentLanguageCode = "fr"

        let data = try LibraryTransferService.exportJSON(snapshot)
        let preview = try LibraryTransferService.previewImport(data, into: .empty)

        XCTAssertNil(preview.snapshot.sharedSpace.reactions)
        XCTAssertNil(preview.snapshot.sharedSpace.notes)
        XCTAssertNil(preview.snapshot.sharedSpace.conversationDeletions)
        XCTAssertEqual(preview.snapshot, snapshot)
    }

    func testCompleteJSONImportMergesSharedHistoryWithoutDeletingNewerLocalData() throws {
        var backup = LibrarySnapshot.sample
        let archivedEvent = SharedWatchEvent(
            id: "archived-event",
            titleID: "severance",
            memberID: "vincent",
            kind: .watched,
            season: 1,
            episode: 1,
            occurredAt: Date(timeIntervalSince1970: 1_000),
            supersedesEventID: nil
        )
        backup.sharedSpace.watchEvents = [archivedEvent]

        var current = LibrarySnapshot.sample
        let currentEvent = SharedWatchEvent(
            id: "current-event",
            titleID: "severance",
            memberID: "vincent",
            kind: .watched,
            season: 1,
            episode: 2,
            occurredAt: Date(timeIntervalSince1970: 2_000),
            supersedesEventID: nil
        )
        current.sharedSpace.watchEvents = [currentEvent]

        let data = try LibraryTransferService.exportJSON(backup)
        let preview = try LibraryTransferService.previewImport(data, into: current)

        XCTAssertEqual(
            Set(preview.snapshot.sharedSpace.watchEvents?.map(\.id) ?? []),
            Set(["archived-event", "current-event"])
        )
        XCTAssertEqual(preview.watchEventCount, 1)
        XCTAssertEqual(preview.sourceName, "OpenTV backup")
    }

    func testCompleteJSONImportPreviewsRestoredAISetting() throws {
        var snapshot = LibrarySnapshot.sample
        snapshot.allowsAIReranking = true

        let data = try LibraryTransferService.exportJSON(snapshot)
        let preview = try LibraryTransferService.previewImport(data, into: .empty)

        XCTAssertEqual(preview.snapshot.allowsAIReranking, true)
        XCTAssertTrue(preview.importNotice?.contains("AI reranking will be enabled") == true)
    }

    func testLegacyJSONImportPreservesSettingsMissingFromBackup() throws {
        let exported = try LibraryTransferService.exportJSON(.sample)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: exported) as? [String: Any]
        )
        object["schemaVersion"] = 3
        var archivedSnapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])
        archivedSnapshot.removeValue(forKey: "allowsAIReranking")
        archivedSnapshot.removeValue(forKey: "streamingRegionCode")
        archivedSnapshot.removeValue(forKey: "contentLanguageCode")
        archivedSnapshot.removeValue(forKey: "contentLanguageSettingWasPresent")
        object["snapshot"] = archivedSnapshot
        let legacyArchive = try JSONSerialization.data(withJSONObject: object)

        var current = LibrarySnapshot.sample
        current.allowsAIReranking = true
        current.streamingRegionCode = "MT"
        current.contentLanguageCode = "fr"

        let preview = try LibraryTransferService.previewImport(legacyArchive, into: current)

        XCTAssertEqual(preview.snapshot.allowsAIReranking, true)
        XCTAssertEqual(preview.snapshot.streamingRegionCode, "MT")
        XCTAssertEqual(preview.snapshot.contentLanguageCode, "fr")
        XCTAssertTrue(preview.importNotice?.contains("Streaming region keeps its current setting") == true)
        XCTAssertTrue(preview.importNotice?.contains("Content language keeps its current setting") == true)
        XCTAssertTrue(
            preview.importNotice?.contains("AI reranking keeps its current enabled setting") == true
        )
    }

    func testCompleteJSONImportRestoresExplicitAutomaticContentLanguage() throws {
        var backup = LibrarySnapshot.sample
        backup.contentLanguageCode = nil

        var current = LibrarySnapshot.sample
        current.contentLanguageCode = "fr"

        let data = try LibraryTransferService.exportJSON(backup)
        let preview = try LibraryTransferService.previewImport(data, into: current)

        XCTAssertNil(preview.snapshot.contentLanguageCode)
        XCTAssertTrue(
            preview.importNotice?.contains("Content language restores from the backup.") == true
        )
    }

    func testJSONImportRestoresWatchedEpisodesForExistingCatalogTitle() throws {
        var snapshot = LibrarySnapshot.sample
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[index].watchedEpisodeIDs = ["severance-s1e1"]

        let data = try LibraryTransferService.exportJSON(snapshot)
        let preview = try LibraryTransferService.previewImport(data, into: .sample)
        let restored = try XCTUnwrap(
            preview.snapshot.titles.first(where: { $0.id == "severance" })
        )

        XCTAssertEqual(restored.watchedEpisodeIDs, Set(["severance-s1e1"]))
    }

}

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

}

extension LibraryTransferTests {
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

    func testJSONImportRejectsOversizedInMemoryPayloadBeforeDecode() {
        let data = Data(
            repeating: 0x7B,
            count: LibraryImportLimits.maximumLibraryFileSize + 1
        )

        XCTAssertThrowsError(
            try LibraryTransferService.previewImport(data, into: .empty)
        ) { error in
            XCTAssertEqual(error as? LibraryImportSafetyError, .fileTooLarge)
        }
    }

    func testCSVImportRejectsOversizedInMemoryPayloadBeforeDecode() {
        let data = Data(
            repeating: 0x61,
            count: LibraryImportLimits.maximumLibraryFileSize + 1
        )

        XCTAssertThrowsError(
            try LibraryTransferService.previewImport(data, into: .empty)
        ) { error in
            XCTAssertEqual(error as? LibraryImportSafetyError, .fileTooLarge)
        }
    }

    func testJSONImportRejectsOverlongEncodedField() throws {
        var snapshot = LibrarySnapshot.sample
        snapshot.titles[0].notes = String(
            repeating: "x",
            count: LibraryImportLimits.maximumFieldSize + 1
        )
        let data = try LibraryTransferService.exportJSON(snapshot)

        XCTAssertThrowsError(
            try LibraryTransferService.previewImport(data, into: .empty)
        ) { error in
            XCTAssertEqual(error as? LibraryImportSafetyError, .fieldTooLarge)
        }
    }

    func testCSVImportRejectsOverlongField() throws {
        let overlongField = String(
            repeating: "x",
            count: LibraryImportLimits.maximumFieldSize + 1
        )
        let data = try XCTUnwrap(
            "catalog_id,title,notes\n95396,Severance,\(overlongField)\n".data(using: .utf8)
        )

        XCTAssertThrowsError(
            try LibraryTransferService.previewImport(data, into: .sample)
        ) { error in
            XCTAssertEqual(error as? LibraryImportSafetyError, .fieldTooLarge)
        }
    }

    func testBoundedCSVParserRejectsRecordsBeyondConfiguredLimit() {
        let csv = "title\nFirst\nSecond\n"

        XCTAssertThrowsError(
            try BoundedCSVParser.rows(csv, maximumRecordCount: 1)
        ) { error in
            XCTAssertEqual(error as? LibraryImportSafetyError, .tooManyRecords)
        }
    }

    func testBoundedCSVParserCountsQuotedNewlineAsOneRecord() throws {
        let rows = try BoundedCSVParser.rows(
            "title,notes\nSeverance,\"first line\nsecond line\"\n",
            maximumRecordCount: 1
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1][1], "first line\nsecond line")
    }

    func testBoundedCSVParserRejectsMoreThanMaximumFields() {
        let header = Array(
            repeating: "field",
            count: LibraryImportLimits.maximumCSVFieldCount + 1
        ).joined(separator: ",")

        XCTAssertThrowsError(try BoundedCSVParser.rows(header)) { error in
            XCTAssertEqual(error as? LibraryImportSafetyError, .tooManyFields)
        }
    }

    func testFileReaderRejectsOversizedRegularFileAtResourcePreflight() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "opentv-oversized-import-\(UUID().uuidString).json")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path(), contents: nil))
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(LibraryImportLimits.maximumLibraryFileSize + 1))
        try handle.close()

        XCTAssertThrowsError(try LibraryImportFileReader.read(from: url)) { error in
            XCTAssertEqual(error as? LibraryImportSafetyError, .fileTooLarge)
        }
    }

    func testBoundedCSVParserRejectsValueCountExhaustion() {
        let csv = "first,second\nthird,fourth\n"

        XCTAssertThrowsError(
            try BoundedCSVParser.rows(csv, maximumValueCount: 3)
        ) { error in
            XCTAssertEqual(error as? LibraryImportSafetyError, .tooManyValues)
        }
    }

    func testBoundedCSVParserRejectsUnterminatedQuotedField() {
        let csv = "title\n\"unterminated"

        XCTAssertThrowsError(try BoundedCSVParser.rows(csv)) { error in
            XCTAssertEqual(error as? LibraryImportSafetyError, .malformedCSV)
        }
    }

    func testJSONPreflightRejectsExcessiveSeparatorCount() {
        let separatorCountPerContainer = LibraryImportLimits.maximumRecordCount - 1
        let containerCount = LibraryImportLimits.maximumJSONSeparatorCount
            / separatorCountPerContainer + 1
        let innerContainer = "[" + String(
            repeating: ",",
            count: separatorCountPerContainer
        ) + "]"
        let data = Data(
            ("[" + Array(repeating: innerContainer, count: containerCount)
                .joined(separator: ",") + "]").utf8
        )

        XCTAssertThrowsError(
            try LibraryJSONImportValidator.validateEncodedFields(in: data)
        ) { error in
            XCTAssertEqual(error as? LibraryImportSafetyError, .tooManyValues)
        }
    }

    func testJSONPreflightRejectsExcessiveCollectionRecordCount() {
        let data = Data(
            ("[" + String(
                repeating: "0,",
                count: LibraryImportLimits.maximumRecordCount
            ) + "0]").utf8
        )

        XCTAssertThrowsError(
            try LibraryJSONImportValidator.validateEncodedFields(in: data)
        ) { error in
            XCTAssertEqual(error as? LibraryImportSafetyError, .tooManyRecords)
        }
    }

    func testJSONPreflightRejectsExcessiveNestingDepth() {
        let nesting = LibraryImportLimits.maximumJSONDepth + 1
        let data = Data(
            (String(repeating: "[", count: nesting)
                + String(repeating: "]", count: nesting)).utf8
        )

        XCTAssertThrowsError(
            try LibraryJSONImportValidator.validateEncodedFields(in: data)
        ) { error in
            XCTAssertEqual(error as? LibraryImportSafetyError, .structureTooDeep)
        }
    }

    func testJSONCollectionValidatorRejectsCollectionBeyondImportLimit() {
        var snapshot = LibrarySnapshot.sample
        snapshot.titles[0].alternativeTitles = Array(
            repeating: "Alternate",
            count: LibraryImportLimits.maximumRecordCount + 1
        )

        XCTAssertThrowsError(
            try LibraryJSONImportValidator.validateCollections(in: snapshot)
        ) { error in
            XCTAssertEqual(error as? LibraryImportSafetyError, .tooManyRecords)
        }
    }

    func testJSONImportStripsUnsafeRemoteMetadataWithoutChangingPrivateState() throws {
        var snapshot = LibrarySnapshot.sample
        var title = try XCTUnwrap(snapshot.titles.first(where: { $0.id == "severance" }))
        title.state = .paused
        title.progress = EpisodeProgress(season: 1, episode: 1, totalEpisodes: 9)
        title.userRating = 9.25
        title.notes = "Private import note"
        title.rewatchCount = 3
        title.lastWatchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        title.isDismissed = true
        title.isDisliked = false
        title.personalWatchlist = true
        title.watchedEpisodeIDs = ["severance-s1e1"]
        title.seriesLifecycle = .continuing
        title.isUpNextPinned = true
        title.upNextSnoozedUntil = Date(timeIntervalSince1970: 1_800_000_000)
        title.upNextManualOrder = 4
        title.posterURL = URL(string: "https://secure.gravatar.com/avatar/poster-tracker")
        title.backdropURL = URL(string: "https://image.tmdb.org.attacker.invalid/backdrop.jpg")
        title.trailerURL = URL(string: "https://www.youtube.com.attacker.invalid/watch?v=unsafe")
        title.sourceURL = URL(string: "https://www.themoviedb.org@attacker.invalid/tv/95396")

        var review = try XCTUnwrap(title.reviews.first)
        review.avatarURL = URL(string: "https://secure.gravatar.com@attacker.invalid/avatar")
        review.sourceURL = URL(string: "https://trakt.tv/reviews/unsafe")
        title.reviews = [review]

        var episode = EpisodeSummary(
            id: "severance-s1e1",
            number: 1,
            title: "Good News About Hell",
            airDate: Date(timeIntervalSince1970: 1_645_142_400),
            runtimeMinutes: 57
        )
        episode.stillURL = URL(string: "http://static.tvmaze.com/uploads/still.jpg")
        var season = SeasonSummary(
            id: "severance-s1",
            number: 1,
            title: "Season 1",
            episodes: [episode]
        )
        season.artworkURL = URL(fileURLWithPath: "/private/season.jpg")
        title.seasons = [season]

        snapshot.titles = [title]
        snapshot.sharedSpace.titleIDs = [title.id]
        snapshot.sharedSpace.titleMetadata = [title]
        snapshot.diaryEntries = [LibraryDiaryTransferTests.diaryEntry]
        snapshot.lists = [
            MediaList(
                id: "private-list",
                name: "Private list",
                titleIDs: [title.id],
                updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        ]

        let preview = try LibraryTransferService.previewImport(
            LibraryTransferService.exportJSON(snapshot),
            into: .empty
        )
        let restored = try XCTUnwrap(preview.snapshot.titles.first)
        let sharedMetadata = try XCTUnwrap(preview.snapshot.sharedSpace.titleMetadata?.first)

        XCTAssertNil(restored.posterURL)
        XCTAssertNil(restored.backdropURL)
        XCTAssertNil(restored.trailerURL)
        XCTAssertNil(restored.sourceURL)
        XCTAssertNil(restored.reviews.first?.avatarURL)
        XCTAssertNil(restored.reviews.first?.sourceURL)
        XCTAssertNil(restored.seasons?.first?.artworkURL)
        XCTAssertNil(restored.seasons?.first?.episodes.first?.stillURL)
        XCTAssertNil(sharedMetadata.posterURL)
        XCTAssertNil(sharedMetadata.backdropURL)
        XCTAssertNil(sharedMetadata.trailerURL)
        XCTAssertNil(sharedMetadata.sourceURL)
        XCTAssertNil(sharedMetadata.reviews.first?.avatarURL)
        XCTAssertNil(sharedMetadata.reviews.first?.sourceURL)
        XCTAssertNil(sharedMetadata.seasons?.first?.artworkURL)
        XCTAssertNil(sharedMetadata.seasons?.first?.episodes.first?.stillURL)

        XCTAssertEqual(restored.state, title.state)
        XCTAssertEqual(restored.progress, title.progress)
        XCTAssertEqual(restored.userRating, title.userRating)
        XCTAssertEqual(restored.notes, title.notes)
        XCTAssertEqual(restored.rewatchCount, title.rewatchCount)
        XCTAssertEqual(restored.lastWatchedAt, title.lastWatchedAt)
        XCTAssertEqual(restored.isDismissed, title.isDismissed)
        XCTAssertEqual(restored.isDisliked, title.isDisliked)
        XCTAssertEqual(restored.personalWatchlist, title.personalWatchlist)
        XCTAssertEqual(restored.watchedEpisodeIDs, title.watchedEpisodeIDs)
        XCTAssertEqual(restored.seriesLifecycle, title.seriesLifecycle)
        XCTAssertEqual(restored.isUpNextPinned, title.isUpNextPinned)
        XCTAssertEqual(restored.upNextSnoozedUntil, title.upNextSnoozedUntil)
        XCTAssertEqual(restored.upNextManualOrder, title.upNextManualOrder)
        XCTAssertEqual(preview.snapshot.diaryEntries, snapshot.diaryEntries)
        XCTAssertEqual(preview.snapshot.lists, snapshot.lists)
        XCTAssertEqual(preview.snapshot.sharedSpace.watchEvents, snapshot.sharedSpace.watchEvents)
        XCTAssertEqual(preview.snapshot.sharedSpace.reactions, snapshot.sharedSpace.reactions)
        XCTAssertEqual(preview.snapshot.sharedSpace.notes, snapshot.sharedSpace.notes)
        XCTAssertEqual(
            preview.snapshot.sharedSpace.conversationDeletions,
            snapshot.sharedSpace.conversationDeletions
        )
        XCTAssertEqual(preview.snapshot.sharedSpace.sharedLists, snapshot.sharedSpace.sharedLists)
    }

    func testJSONImportNormalizesTrustedMetadataAndStripsRedirectQueries() throws {
        var snapshot = LibrarySnapshot.sample
        var title = try XCTUnwrap(snapshot.titles.first(where: { $0.id == "severance" }))
        title.posterURL = URL(
            string: "HTTPS://IMAGE.TMDB.ORG:443/t/p/w500/poster.jpg?language=en#fragment"
        )
        title.backdropURL = URL(
            string: "https://MEDIA.THEMOVIEDB.ORG:443/t/p/w780/backdrop.jpg#fragment"
        )
        title.trailerURL = URL(string: "https://YOUTU.BE:443/abcdefghijk#fragment")
        title.sourceURL = URL(
            string: "https://WWW.THEMOVIEDB.ORG:443/tv/95396?language=en#fragment"
        )

        var review = try XCTUnwrap(title.reviews.first)
        review.avatarURL = URL(
            string: "https://SECURE.GRAVATAR.COM:443/avatar/hash?s=64&d=https%3A%2F%2Ftracker.invalid%2Fpixel.png#fragment"
        )
        review.sourceURL = URL(
            string: "https://WWW.THEMOVIEDB.ORG:443/review/1#fragment"
        )
        title.reviews = [review]

        var episode = EpisodeSummary(
            id: "severance-s1e1",
            number: 1,
            title: "Good News About Hell",
            airDate: nil,
            runtimeMinutes: 57
        )
        episode.stillURL = URL(
            string: "https://IMAGE.TMDB.ORG:443/t/p/w300/still.jpg#fragment"
        )
        var season = SeasonSummary(
            id: "severance-s1",
            number: 1,
            title: "Season 1",
            episodes: [episode]
        )
        season.artworkURL = URL(
            string: "https://STATIC.TVMAZE.COM:443/uploads/images/original_untouched/season.jpg#fragment"
        )
        title.seasons = [season]

        snapshot.titles = [title]
        snapshot.sharedSpace.titleIDs = [title.id]
        snapshot.sharedSpace.titleMetadata = [title]

        let preview = try LibraryTransferService.previewImport(
            LibraryTransferService.exportJSON(snapshot),
            into: .empty
        )
        let restored = try XCTUnwrap(preview.snapshot.titles.first)
        let sharedMetadata = try XCTUnwrap(preview.snapshot.sharedSpace.titleMetadata?.first)

        XCTAssertEqual(
            restored.posterURL,
            URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg")
        )
        XCTAssertEqual(
            restored.backdropURL,
            URL(string: "https://media.themoviedb.org/t/p/w780/backdrop.jpg")
        )
        XCTAssertEqual(restored.trailerURL, URL(string: "https://youtu.be/abcdefghijk"))
        XCTAssertEqual(
            restored.sourceURL,
            URL(string: "https://www.themoviedb.org/tv/95396?language=en")
        )
        XCTAssertEqual(
            restored.reviews.first?.avatarURL,
            URL(string: "https://secure.gravatar.com/avatar/hash?s=64")
        )
        XCTAssertEqual(
            restored.reviews.first?.sourceURL,
            URL(string: "https://www.themoviedb.org/review/1")
        )
        XCTAssertEqual(
            restored.seasons?.first?.artworkURL,
            URL(string: "https://static.tvmaze.com/uploads/images/original_untouched/season.jpg")
        )
        XCTAssertEqual(
            restored.seasons?.first?.episodes.first?.stillURL,
            URL(string: "https://image.tmdb.org/t/p/w300/still.jpg")
        )
        XCTAssertEqual(sharedMetadata, restored)
    }
}
