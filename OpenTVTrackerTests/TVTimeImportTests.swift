import XCTest
import ZIPFoundation
@testable import OpenTVTracker

final class TVTimeImportTests: XCTestCase {
    func testDateParserPreservesInternetAndLegacyFormats() throws {
        let standard = try XCTUnwrap(TVTimeCSV.date(
            ["watched_at": "2025-02-14T20:30:00Z"],
            ["watched_at"]
        ))
        let fractional = try XCTUnwrap(TVTimeCSV.date(
            ["watched_at": "2025-02-14T20:30:00.125Z"],
            ["watched_at"]
        ))
        let legacy = try XCTUnwrap(TVTimeCSV.date(
            ["watched_at": "2025-02-14 20:30:00"],
            ["watched_at"]
        ))

        XCTAssertEqual(standard.timeIntervalSince1970, 1_739_565_000, accuracy: 0.001)
        XCTAssertEqual(fractional.timeIntervalSince1970, 1_739_565_000.125, accuracy: 0.001)
        XCTAssertEqual(legacy, standard)
    }

    func testHostileTVTimeNumbersAreRejectedOrBounded() throws {
        XCTAssertNil(TVTimeCSV.int(["value": "1e100"], ["value"]))
        XCTAssertNil(TVTimeCSV.double(["value": "1e309"], ["value"]))

        let maximum = String(Int.max)
        let archive = try TVTimeArchiveParser.parse(makeArchive([
            "tvtime-series-episodes-2026.csv": """
            series_tvdb_id,title,season,episode,is_watched,rewatch_count
            37,Hostile Series,\(maximum),\(maximum),true,\(maximum)
            """
        ]))
        let entity = try XCTUnwrap(archive.entities.first)
        let watch = try XCTUnwrap(entity.watches.first)

        XCTAssertEqual(watch.season, LibraryImportLimits.maximumImportedProgressValue)
        XCTAssertEqual(watch.episode, LibraryImportLimits.maximumImportedProgressValue)
        XCTAssertEqual(
            watch.importedRewatchCount,
            LibraryImportLimits.maximumImportedRewatchCount
        )
    }

    func testTVTimeZIPRestoresEpisodeHistoryRatingAndWatchDate() async throws {
        let archive = try makeArchive([
            "tracking-prod-records-v2.csv": """
            key,s_id,series_name,s_no,ep_no,created_at,is_followed,is_for_later,is_archived
            watch-episode-101,42,Severance,1,1,2025-02-14T20:30:00Z,,,
            user-series-102,43,Slow Horses,,,,true,true,true
            """,
            "tv_show_rate.csv": """
            tv_show_id,tv_show_name,rate
            42,Severance,5
            """
        ])
        let snapshot = snapshotWithSeveranceEpisodes()

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: LocalCatalogService(titles: snapshot.titles),
            region: .malta
        )

        let severance = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "severance" }))
        let slowHorses = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "slow-horses" }))
        XCTAssertEqual(severance.watchedEpisodeIDs, Set(["severance-s1e1"]))
        XCTAssertEqual(severance.userRating, 10)
        XCTAssertEqual(severance.state, .watching)
        XCTAssertFalse(severance.isOnPersonalWatchlist)
        XCTAssertEqual(slowHorses.state, .dropped)
        XCTAssertFalse(slowHorses.isOnPersonalWatchlist)
        XCTAssertEqual(preview.sourceName, "TV Time")
        XCTAssertEqual(preview.matchedCount, 2)
        XCTAssertEqual(preview.watchedEpisodeCount, 1)
        XCTAssertEqual(preview.watchEventCount, 1)
        XCTAssertEqual(preview.snapshot.sharedSpace.watchEvents?.first?.season, 1)
        XCTAssertEqual(preview.snapshot.sharedSpace.watchEvents?.first?.episode, 1)
        let diaryEntry = try XCTUnwrap(preview.snapshot.diaryEntries?.first)
        XCTAssertEqual(diaryEntry.episodeID, "severance-s1e1")
        XCTAssertEqual(diaryEntry.watchedAt, Date(timeIntervalSince1970: 1_739_565_000))
    }

    func testReimportDoesNotDuplicateDatedWatchEvents() async throws {
        let archive = try makeArchive([
            "tracking-prod-records-v2.csv": """
            key,s_id,series_name,s_no,ep_no,created_at
            watch-episode-101,42,Severance,1,1,2025-02-14T20:30:00Z
            """
        ])
        let snapshot = snapshotWithSeveranceEpisodes()
        let catalog = LocalCatalogService(titles: snapshot.titles)
        let first = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: catalog,
            region: .malta
        )

        let second = try await TVTimeImportService.previewImport(
            archive,
            into: first.snapshot,
            catalog: catalog,
            region: .malta
        )

        XCTAssertEqual(first.snapshot.sharedSpace.watchEvents?.count, 1)
        XCTAssertEqual(second.snapshot.sharedSpace.watchEvents?.count, 1)
        XCTAssertEqual(first.snapshot.diaryEntries?.count, 1)
        XCTAssertEqual(second.snapshot.diaryEntries?.count, 1)
        XCTAssertEqual(second.watchEventCount, 0)
    }

    func testDuplicateWatchRowsMergeRatingWithoutDuplicatingHistory() async throws {
        let archive = try makeArchive([
            "tracking-prod-records-v2.csv": """
            key,s_id,series_name,s_no,ep_no,created_at,episode_rating
            watch-episode-101,42,Severance,1,1,2025-02-14T20:30:00Z,
            watch-episode-101,42,Severance,1,1,2025-02-14T20:30:00Z,9
            """
        ])
        let snapshot = snapshotWithSeveranceEpisodes()

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: LocalCatalogService(titles: snapshot.titles),
            region: .malta
        )

        XCTAssertEqual(preview.snapshot.sharedSpace.watchEvents?.count, 1)
        XCTAssertEqual(preview.snapshot.diaryEntries?.count, 1)
        XCTAssertEqual(preview.snapshot.diaryEntries?.first?.rating, 9)
    }

    @MainActor
    func testReimportAfterVersionFourMigrationDoesNotDuplicateWatch() async throws {
        let archive = try makeArchive([
            "tracking-prod-records-v2.csv": """
            key,s_id,series_name,s_no,ep_no,created_at
            watch-episode-101,42,Severance,1,1,2025-02-14T20:30:00Z
            """
        ])
        var snapshot = snapshotWithSeveranceEpisodes()
        let eventID = "tvtime:severance:1:1:1739565000:watched"
        snapshot.sharedSpace.watchEvents = [
            SharedWatchEvent(
                id: eventID,
                titleID: "severance",
                memberID: "vincent",
                kind: .watched,
                season: 1,
                episode: 1,
                occurredAt: Date(timeIntervalSince1970: 1_739_565_000),
                supersedesEventID: nil
            )
        ]
        snapshot.diaryEntries = nil
        let migratedSnapshot = AppModel(store: MemoryLibraryStore(), seed: snapshot).snapshot
        let migratedEntryIDs = migratedSnapshot.diaryEntries?.map(\.id)
        XCTAssertEqual(migratedEntryIDs, ["diary:\(eventID)"])

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: migratedSnapshot,
            catalog: LocalCatalogService(titles: migratedSnapshot.titles),
            region: .malta
        )

        XCTAssertEqual(preview.snapshot.diaryEntries?.count, 1)
        XCTAssertEqual(preview.snapshot.diaryEntries?.map(\.id), migratedEntryIDs)
        XCTAssertEqual(preview.watchEventCount, 0)
    }

    func testNativeExportIgnoresUnwatchedEpisodesAndRestoresMovieRewatches() async throws {
        let archive = try makeArchive([
            "tvtime-series-episodes-2026.csv": """
            series_tvdb_id,title,season,episode,is_watched,watched_at,rewatch_count
            42,Severance,1,1,true,2025-02-14 20:30:00,3
            42,Severance,1,2,false,,0
            """,
            "tvtime-movies-2026.csv": """
            tvdb_id,title,year,watched_at,is_watched,rewatch_count
            99,Past Lives,2023,2025-03-01T21:00:00Z,true,2
            """
        ])
        let snapshot = snapshotWithSeveranceEpisodes()

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: LocalCatalogService(titles: snapshot.titles),
            region: .malta
        )

        let severance = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "severance" }))
        let movie = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "past-lives" }))
        XCTAssertEqual(severance.watchedEpisodeIDs, Set(["severance-s1e1"]))
        XCTAssertEqual(severance.completedRewatches, 3)
        XCTAssertEqual(movie.state, .completed)
        XCTAssertEqual(movie.completedRewatches, 2)
        XCTAssertEqual(preview.watchedEpisodeCount, 1)
        XCTAssertEqual(preview.watchEventCount, 2)
        XCTAssertEqual(
            preview.integrityCounts.first(where: { $0.category == .rewatches }),
            ImportCountComparison(category: .rewatches, sourceCount: 5, importedCount: 5)
        )
    }

    func testSeriesRewatchMetricSumsEpisodesWithoutInflatingTitleCount() async throws {
        let archive = try makeArchive([
            "tvtime-series-episodes-2026.csv": """
            series_tvdb_id,title,season,episode,is_watched,watched_at,rewatch_count
            42,Severance,1,1,true,2025-02-14 20:30:00,1
            42,Severance,1,2,true,2025-02-15 20:30:00,1
            """
        ])
        let snapshot = snapshotWithSeveranceEpisodes()

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: LocalCatalogService(titles: snapshot.titles),
            region: .malta
        )

        let severance = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "severance" }))
        XCTAssertEqual(severance.completedRewatches, 1)
        XCTAssertEqual(preview.watchedEpisodeCount, 2)
        XCTAssertEqual(
            preview.integrityCounts.first(where: { $0.category == .rewatches }),
            ImportCountComparison(category: .rewatches, sourceCount: 2, importedCount: 2)
        )
    }

    @MainActor
    func testCancelledResolutionSearchDoesNotSurfaceCatalogError() async throws {
        let session = TVTimeImportSession(
            archive: TVTimeArchive(
                entities: [],
                duplicateCount: 0,
                diagnostics: TVTimeImportDiagnostics()
            ),
            current: .empty,
            catalog: CancellingCatalog(),
            region: .malta
        )
        let coordinator = TVTimeImportCoordinator(session: session)

        do {
            _ = try await coordinator.search("Severance", kind: .series)
            XCTFail("Expected cancellation to propagate")
        } catch is CancellationError {
            XCTAssertNil(coordinator.errorMessage)
        }
    }
}

extension TVTimeImportTests {
    @MainActor
    func testConcurrentManualResolutionsAreSerialized() async throws {
        let candidates = Array(LibrarySnapshot.sample.titles.prefix(2))
        let first = try XCTUnwrap(candidates.first)
        let second = try XCTUnwrap(candidates.dropFirst().first)
        let catalog = ControlledResolutionCatalog(titles: candidates)
        let session = TVTimeImportSession(
            archive: TVTimeArchive(
                entities: [],
                duplicateCount: 0,
                diagnostics: TVTimeImportDiagnostics()
            ),
            current: .empty,
            catalog: catalog,
            region: .malta
        )
        let coordinator = TVTimeImportCoordinator(session: session)
        let firstIssue = Self.resolutionIssue(id: "first", title: first)
        let secondIssue = Self.resolutionIssue(id: "second", title: second)

        let firstResolution = Task {
            await coordinator.resolve(firstIssue, with: first)
        }
        await catalog.waitUntilRequested(catalogID: first.catalogID)
        let secondResolution = Task {
            await coordinator.resolve(secondIssue, with: second)
        }
        await Task.yield()

        let requestedSecondEarly = await catalog.hasRequested(catalogID: second.catalogID)
        XCTAssertFalse(requestedSecondEarly)

        await catalog.release(catalogID: first.catalogID)
        await catalog.waitUntilRequested(catalogID: second.catalogID)
        await catalog.release(catalogID: second.catalogID)
        await firstResolution.value
        await secondResolution.value

        let requestOrder = await catalog.requestedCatalogIDs
        XCTAssertEqual(requestOrder, [first.catalogID, second.catalogID])
        XCTAssertFalse(coordinator.isRefreshing)
    }

    func testLegacyExportRestoresEpochWatchDateAndMovieRating() async throws {
        let archive = try makeArchive([
            "tracking-prod-records.csv": """
            uuid,type,entity_type,movie_name,release_date,alpha_range_key,watch_date_range_key,created_at
            movie-1,watch,movie,Past Lives,2023-01-01,watch-alpha-past-lives,watch-date-1740862800,2025-03-01 21:00:00
            """,
            "ratings-live-votes.csv": """
            uuid,episode_id,movie_name,vote_key
            movie-1,0,Past Lives,stars-wording-scalev2-29
            """
        ])
        let snapshot = snapshotWithSeveranceEpisodes()

        let preview = try await TVTimeImportService.previewImport(
            archive,
            into: snapshot,
            catalog: LocalCatalogService(titles: snapshot.titles),
            region: .malta
        )

        let movie = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "past-lives" }))
        XCTAssertEqual(movie.state, .completed)
        XCTAssertEqual(movie.userRating, 8)
        XCTAssertEqual(movie.lastWatchedAt, Date(timeIntervalSince1970: 1_740_862_800))
        XCTAssertEqual(preview.watchEventCount, 1)
        XCTAssertEqual(preview.snapshot.diaryEntries?.first?.rating, 8)
    }

    func testZIPWithoutTVTimeTrackingDataIsRejected() async throws {
        let archive = try makeArchive(["profile.csv": "name\nVincent\n"])

        do {
            _ = try await TVTimeImportService.previewImport(
                archive,
                into: .sample,
                catalog: LocalCatalogService(titles: LibrarySnapshot.sample.titles),
                region: .malta
            )
            XCTFail("Expected unsupported TV Time data to be rejected")
        } catch let error as TVTimeImportError {
            XCTAssertEqual(error.errorDescription, "This ZIP does not contain recognizable TV Time tracking data.")
        }
    }

    func testZIPRejectsCaseInsensitiveDuplicateRecognizedFullPaths() throws {
        let archive = try makeArchive([
            (
                path: "Exports/TRACKING-PROD-RECORDS-V2.CSV",
                contents: "key,s_id,series_name,s_no,ep_no\nfirst,42,Severance,1,1\n"
            ),
            (
                path: "exports/tracking-prod-records-v2.csv",
                contents: "key,s_id,series_name,s_no,ep_no\nsecond,42,Severance,1,2\n"
            )
        ])

        XCTAssertThrowsError(try TVTimeZIPReader.recognizedFiles(in: archive)) { error in
            guard let importError = error as? TVTimeImportError,
                  case .duplicateRecognizedPath = importError else {
                return XCTFail("Expected duplicateRecognizedPath, got \(error)")
            }
        }
    }

    func testZIPRejectsUnicodeCaseFoldDuplicateRecognizedFullPaths() throws {
        let archive = try makeArchive([
            (
                path: "Σ/tracking-prod-records-v2.csv",
                contents: "key,s_id,series_name,s_no,ep_no\nfirst,42,Severance,1,1\n"
            ),
            (
                path: "ς/tracking-prod-records-v2.csv",
                contents: "key,s_id,series_name,s_no,ep_no\nsecond,42,Severance,1,2\n"
            )
        ])

        XCTAssertThrowsError(try TVTimeZIPReader.recognizedFiles(in: archive)) { error in
            guard let importError = error as? TVTimeImportError,
                  case .duplicateRecognizedPath = importError else {
                return XCTFail("Expected duplicateRecognizedPath, got \(error)")
            }
        }
    }

    func testZIPRejectsMultiScalarCaseFoldDuplicateRecognizedFullPaths() throws {
        let archive = try makeArchive([
            (
                path: "Straße/tracking-prod-records-v2.csv",
                contents: "key,s_id,series_name,s_no,ep_no\nfirst,42,Severance,1,1\n"
            ),
            (
                path: "STRASSE/tracking-prod-records-v2.csv",
                contents: "key,s_id,series_name,s_no,ep_no\nsecond,42,Severance,1,2\n"
            )
        ])

        XCTAssertThrowsError(try TVTimeZIPReader.recognizedFiles(in: archive)) { error in
            guard let importError = error as? TVTimeImportError,
                  case .duplicateRecognizedPath = importError else {
                return XCTFail("Expected duplicateRecognizedPath, got \(error)")
            }
        }
    }

    func testBoundedExtractionRejectsUnderreportedOutputBeforeAppendingPastLimit() throws {
        let exact = try TVTimeZIPReader.boundedExtraction(
            declaredSize: 1,
            maximumSize: 4
        ) { consumer in
            try consumer(Data([0, 1]))
            try consumer(Data([2, 3]))
        }
        XCTAssertEqual(exact, Data([0, 1, 2, 3]))

        var completedConsumerCalls = 0
        XCTAssertThrowsError(
            try TVTimeZIPReader.boundedExtraction(
                declaredSize: 1,
                maximumSize: 4
            ) { consumer in
                try consumer(Data([0, 1, 2]))
                completedConsumerCalls += 1
                try consumer(Data([3, 4]))
                completedConsumerCalls += 1
            }
        ) { error in
            guard let importError = error as? TVTimeImportError,
                  case .archiveTooLarge = importError else {
                return XCTFail("Expected archiveTooLarge, got \(error)")
            }
        }
        XCTAssertEqual(completedConsumerCalls, 1)
    }

    func testZIPRejectsExcessiveTotalEntryCount() throws {
        var files = [
            (
                path: "tracking-prod-records-v2.csv",
                contents: "key,s_id,series_name,s_no,ep_no\nfirst,42,Severance,1,1\n"
            )
        ]
        files.append(contentsOf: (0..<LibraryImportLimits.maximumZIPEntryCount).map { index in
            (path: "unrecognized/entry-\(index).txt", contents: "")
        })
        let archive = try makeArchive(files)

        XCTAssertThrowsError(try TVTimeZIPReader.recognizedFiles(in: archive)) { error in
            guard let importError = error as? TVTimeImportError,
                  case .tooManyArchiveEntries = importError else {
                return XCTFail("Expected tooManyArchiveEntries, got \(error)")
            }
        }
    }

    func testGDPRListAggregateFieldMayExceedNormalFieldLimit() throws {
        let objects = String(
            repeating: "x",
            count: LibraryImportLimits.maximumFieldSize + 1
        )
        let archive = try makeArchive([
            "lists-prod-lists.csv": "name,objects\nLarge list,\(objects)\n"
        ])

        let parsed = try TVTimeArchiveParser.parse(archive)

        XCTAssertEqual(parsed.lists.map(\.name), ["Large list"])
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
                    ),
                    EpisodeSummary(
                        id: "severance-s1e2",
                        number: 2,
                        title: "Half Loop",
                        airDate: Date(timeIntervalSince1970: 1_645_747_200),
                        runtimeMinutes: 53
                    )
                ]
            )
        ]
        snapshot.sharedSpace.watchEvents = []
        return snapshot
    }

    private static func resolutionIssue(
        id: String,
        title: MediaTitle
    ) -> ImportResolutionIssue {
        ImportResolutionIssue(
            id: id,
            sourceID: id,
            title: title.title,
            year: title.year,
            kind: title.kind,
            reason: .ambiguousCatalogMatch,
            detail: "Choose a title."
        )
    }

    private func makeArchive(_ files: [String: String]) throws -> Data {
        try makeArchive(
            files.sorted(by: { $0.key < $1.key }).map { path, contents in
                (path: path, contents: contents)
            }
        )
    }

    private func makeArchive(_ files: [(path: String, contents: String)]) throws -> Data {
        let archive = try Archive(accessMode: .create)
        for file in files {
            let data = Data(file.contents.utf8)
            try archive.addEntry(
                with: file.path,
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
