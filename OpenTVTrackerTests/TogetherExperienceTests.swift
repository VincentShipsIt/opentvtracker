import XCTest
@testable import OpenTVTracker

@MainActor
final class TogetherExperienceTests: XCTestCase {
    func testConnectionPhaseTracksMembershipLifecycle() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .empty)

        XCTAssertEqual(model.togetherConnectionPhase, .unconnected)

        model.sharedSpace.membershipState = .pending
        XCTAssertEqual(model.togetherConnectionPhase, .waitingForPartner)

        model.sharedSpace.membershipState = .accepted
        XCTAssertEqual(model.togetherConnectionPhase, .connected)

        model.sharedSpace.membershipState = .revoked
        XCTAssertEqual(model.togetherConnectionPhase, .revoked)

        model.sharedSpace.membershipState = .expired
        XCTAssertEqual(model.togetherConnectionPhase, .expired)

        model.sharedSpace.membershipState = .left
        XCTAssertEqual(model.togetherConnectionPhase, .left)
    }

    func testMemberProgressIsScopedAndIgnoresSupersededEvents() throws {
        var snapshot = LibrarySnapshot.sample
        let titleIndex = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[titleIndex].seasons = Self.episodeTrackingSeasons
        snapshot.sharedSpace.watchEvents = Self.memberWatchEvents
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)
        let title = try XCTUnwrap(model.mediaTitle(withID: "severance"))

        let currentUser = model.togetherMemberProgressSummary(for: title, memberID: "vincent")
        let partner = model.togetherMemberProgressSummary(for: title, memberID: "partner")

        XCTAssertEqual(currentUser.label, "1 of 4 episodes")
        XCTAssertEqual(currentUser.fraction, 0.25, accuracy: 0.001)
        XCTAssertEqual(partner.label, "2 of 4 episodes")
        XCTAssertEqual(partner.fraction, 0.5, accuracy: 0.001)
    }

    private static let memberWatchEvents = [
        watchEvent(id: "vincent-1", memberID: "vincent", season: 1, episode: 1, timestamp: 1),
        watchEvent(id: "vincent-2", memberID: "vincent", season: 1, episode: 2, timestamp: 2),
        SharedWatchEvent(
            id: "vincent-correction",
            titleID: "severance",
            memberID: "vincent",
            kind: .correction,
            season: 1,
            episode: 2,
            occurredAt: Date(timeIntervalSince1970: 3),
            supersedesEventID: "vincent-2"
        ),
        watchEvent(id: "partner-1", memberID: "partner", season: 1, episode: 1, timestamp: 4),
        watchEvent(id: "partner-2", memberID: "partner", season: 2, episode: 1, timestamp: 5)
    ]

    private static let episodeTrackingSeasons = [
        SeasonSummary(
            id: "season-1",
            number: 1,
            title: "Season 1",
            episodes: [
                EpisodeSummary(id: "s1e1", number: 1, title: "Episode 1", airDate: nil, runtimeMinutes: 50),
                EpisodeSummary(id: "s1e2", number: 2, title: "Episode 2", airDate: nil, runtimeMinutes: 52)
            ]
        ),
        SeasonSummary(
            id: "season-2",
            number: 2,
            title: "Season 2",
            episodes: [
                EpisodeSummary(id: "s2e1", number: 1, title: "Episode 1", airDate: nil, runtimeMinutes: 48),
                EpisodeSummary(id: "s2e2", number: 2, title: "Episode 2", airDate: nil, runtimeMinutes: 54)
            ]
        )
    ]

    private static func watchEvent(
        id: String,
        memberID: String,
        season: Int,
        episode: Int,
        timestamp: TimeInterval
    ) -> SharedWatchEvent {
        SharedWatchEvent(
            id: id,
            titleID: "severance",
            memberID: memberID,
            kind: .watched,
            season: season,
            episode: episode,
            occurredAt: Date(timeIntervalSince1970: timestamp),
            supersedesEventID: nil
        )
    }
}
