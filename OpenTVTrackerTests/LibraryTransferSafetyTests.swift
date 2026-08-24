import XCTest
@testable import OpenTVTracker

extension LibraryTransferTests {
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
        let csv = "catalog_id,title,notes\n95396,Severance,\(overlongField)\n"
        let data = Data(csv.utf8)

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
        let sample = LibrarySnapshot.sample
        let sampleTitle = try XCTUnwrap(sample.titles.first(where: { $0.id == "severance" }))
        let sampleReview = try XCTUnwrap(sampleTitle.reviews.first)
        let (snapshot, title) = LibraryTransferRemoteMetadataFixtures.unsafeSnapshot(
            snapshot: sample, title: sampleTitle, review: sampleReview
        )

        let preview = try LibraryTransferService.previewImport(
            LibraryTransferService.exportJSON(snapshot), into: .empty)
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

    func testJSONImportBoundsHostileNumericMetadata() throws {
        var snapshot = LibrarySnapshot.sample
        var title = try XCTUnwrap(snapshot.titles.first(where: { $0.id == "severance" }))
        title.runtimeMinutes = Int.max
        title.rewatchCount = Int.max
        title.upNextManualOrder = Int.max
        title.progress = EpisodeProgress(season: Int.max, episode: Int.max, totalEpisodes: -1)
        let episode = EpisodeSummary(
            id: "hostile-episode",
            number: Int.max,
            title: "Hostile episode",
            airDate: nil,
            runtimeMinutes: Int.max
        )
        title.seasons = [
            SeasonSummary(
                id: "hostile-season",
                number: Int.max,
                title: "Hostile season",
                episodes: [episode]
            )
        ]
        snapshot.titles = [title]

        let preview = try LibraryTransferService.previewImport(
            LibraryTransferService.exportJSON(snapshot),
            into: .empty
        )
        let restored = try XCTUnwrap(preview.snapshot.titles.first)
        let restoredSeason = try XCTUnwrap(restored.seasons?.first)
        let restoredEpisode = try XCTUnwrap(restoredSeason.episodes.first)

        XCTAssertEqual(restored.runtimeMinutes, LibraryImportLimits.maximumImportedRuntimeMinutes)
        XCTAssertEqual(restored.rewatchCount, LibraryImportLimits.maximumImportedRewatchCount)
        XCTAssertEqual(restored.upNextManualOrder, LibraryImportLimits.maximumImportedOrderingValue)
        XCTAssertEqual(
            restored.progress,
            EpisodeProgress(
                season: LibraryImportLimits.maximumImportedProgressValue,
                episode: 1,
                totalEpisodes: 1
            )
        )
        XCTAssertEqual(restoredSeason.number, LibraryImportLimits.maximumImportedProgressValue)
        XCTAssertEqual(restoredEpisode.number, LibraryImportLimits.maximumImportedProgressValue)
        XCTAssertEqual(
            restoredEpisode.runtimeMinutes,
            LibraryImportLimits.maximumImportedRuntimeMinutes
        )
    }

    func testJSONImportNormalizesTrustedMetadataAndStripsRedirectQueries() throws {
        let sample = LibrarySnapshot.sample
        let sampleTitle = try XCTUnwrap(sample.titles.first(where: { $0.id == "severance" }))
        let sampleReview = try XCTUnwrap(sampleTitle.reviews.first)
        let snapshot = LibraryTransferRemoteMetadataFixtures.trustedSnapshot(
            snapshot: sample,
            title: sampleTitle,
            review: sampleReview
        )

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
