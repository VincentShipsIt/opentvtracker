import XCTest
@testable import OpenTVTracker

@MainActor
final class SharedEpisodeWatchDeduplicationTests: XCTestCase {
    func testPartnerEventDoesNotPreventEpisodeFromBeingMarkedLocally() throws {
        var snapshot = LibrarySnapshot.sample
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[index].seasons = [Self.season]
        snapshot.titles[index].watchedEpisodeIDs = []
        snapshot.sharedSpace.watchEvents = [
            SharedWatchEvent(
                id: "partner-watch",
                titleID: "severance",
                memberID: "partner",
                kind: .watchedTogether,
                season: 1,
                episode: 1,
                occurredAt: .now,
                supersedesEventID: nil
            )
        ]
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        model.markEpisodeWatchedTogether(
            titleID: "severance",
            season: Self.season,
            episode: Self.episode
        )

        XCTAssertEqual(model.mediaTitle(withID: "severance")?.watchedEpisodeIDs, Set([Self.episode.id]))
        let events = model.sharedSpace.watchEvents?.filter {
            $0.kind == .watchedTogether && $0.season == 1 && $0.episode == 1
        }
        XCTAssertEqual(Set(events?.map(\.memberID) ?? []), Set(["vincent", "partner"]))
    }

    private static let episode = EpisodeSummary(
        id: "s1e1",
        number: 1,
        title: "Episode 1",
        airDate: nil,
        runtimeMinutes: 50
    )
    private static let season = SeasonSummary(
        id: "season-1",
        number: 1,
        title: "Season 1",
        episodes: [episode]
    )
}
