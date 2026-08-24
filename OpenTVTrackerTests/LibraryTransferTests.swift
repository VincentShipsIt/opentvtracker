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
        let sampleTitle = try XCTUnwrap(LibrarySnapshot.sample.titles.first)
        let (imported, catalog) = Self.legacyTrackingFixture(from: sampleTitle)

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

    func testCSVImportBoundsHostileTrackingNumbersAndRejectsNonfiniteRatings() throws {
        let original = try XCTUnwrap(
            LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" })
        )
        let maximum = String(Int.max)
        let csv = """
        catalog_id,title,rating,rewatches,season,episode,total_episodes,up_next_manual_order
        95396,Severance,1e309,\(maximum),\(maximum),\(maximum),-1,\(maximum)
        """

        let preview = try LibraryTransferService.previewImport(
            try XCTUnwrap(csv.data(using: .utf8)),
            into: .sample
        )
        let imported = try XCTUnwrap(
            preview.snapshot.titles.first(where: { $0.id == "severance" })
        )

        XCTAssertEqual(imported.userRating, original.userRating)
        XCTAssertEqual(imported.rewatchCount, LibraryImportLimits.maximumImportedRewatchCount)
        XCTAssertEqual(imported.upNextManualOrder, LibraryImportLimits.maximumImportedOrderingValue)
        XCTAssertEqual(
            imported.progress,
            EpisodeProgress(
                season: LibraryImportLimits.maximumImportedProgressValue,
                episode: 1,
                totalEpisodes: 1
            )
        )
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

private extension LibraryTransferTests {
    static func legacyTrackingFixture(
        from sampleTitle: MediaTitle
    ) -> (imported: MediaTitle, catalog: MediaTitle) {
        var imported = sampleTitle
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
        return (imported, catalog)
    }
}
