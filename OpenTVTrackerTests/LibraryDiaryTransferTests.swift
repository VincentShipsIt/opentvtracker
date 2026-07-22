import XCTest
@testable import OpenTVTracker

final class LibraryDiaryTransferTests: XCTestCase {
    func testLegacyImportKeepsExistingEpisodeHistoryAndRemapsDiaryIdentity() throws {
        let imported = try legacySnapshotWithRemappedDiary()
        let destination = try destinationSnapshotForLegacyImport()

        let preview = try LibraryTransferService.previewImport(
            LibraryArchiveCodec.encode(imported, prettyPrinted: false),
            into: destination
        )

        let title = try XCTUnwrap(preview.snapshot.titles.first(where: { $0.id == "severance" }))
        XCTAssertEqual(title.watchedEpisodeIDs, ["existing-watch"])
        XCTAssertEqual(preview.snapshot.diaryEntries?.first?.titleID, "severance")
        XCTAssertEqual(preview.snapshot.diaryEntries?.first?.episodeID, "destination-episode")
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
        XCTAssertEqual(preview.watchEventCount, 1)
        XCTAssertEqual(preview.snapshot.diaryEntries, [Self.diaryCSVEntry])

        let repeated = try LibraryTransferService.previewImport(data, into: preview.snapshot)
        XCTAssertEqual(repeated.watchEventCount, 0)
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

    static let diaryEntry = ViewingDiaryEntry(
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

    private func legacySnapshotWithRemappedDiary() throws -> LibrarySnapshot {
        var snapshot = LibrarySnapshot.sample
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        var title = try replacingID(of: snapshot.titles[index], with: "legacy-severance")
        title.watchedEpisodeIDs = nil
        title.seasons = [Self.legacySeason]
        snapshot.titles[index] = title
        snapshot.diaryEntries = [
            ViewingDiaryEntry(
                id: "legacy-diary",
                titleID: title.id,
                scope: .episode,
                seasonNumber: 1,
                episodeID: "legacy-episode",
                episodeNumber: 1,
                watchedAt: .now,
                rating: nil,
                note: nil,
                isRewatch: false,
                createdAt: .now,
                updatedAt: .now
            )
        ]
        return snapshot
    }

    private func destinationSnapshotForLegacyImport() throws -> LibrarySnapshot {
        var snapshot = LibrarySnapshot.sample
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[index].watchedEpisodeIDs = ["existing-watch"]
        snapshot.titles[index].seasons = [
            SeasonSummary(
                id: "destination-season",
                number: 1,
                title: "Season 1",
                episodes: [
                    EpisodeSummary(
                        id: "destination-episode",
                        number: 1,
                        title: "Episode 1",
                        airDate: nil,
                        runtimeMinutes: 50
                    )
                ]
            )
        ]
        return snapshot
    }

    private func replacingID(of title: MediaTitle, with id: String) throws -> MediaTitle {
        let encoded = try JSONEncoder().encode(title)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["id"] = id
        return try JSONDecoder().decode(
            MediaTitle.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private static let legacySeason = SeasonSummary(
        id: "legacy-season",
        number: 1,
        title: "Season 1",
        episodes: [
            EpisodeSummary(
                id: "legacy-episode",
                number: 1,
                title: "Episode 1",
                airDate: nil,
                runtimeMinutes: 50
            )
        ]
    )
}
