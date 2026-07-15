import XCTest
@testable import OpenTVTracker

final class ViewingAnalyticsTests: XCTestCase {
    func testPersonalSummaryUsesCurrentMemberAndRemovesCorrectedEvent() {
        var snapshot = emptyTrackingSnapshot()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        snapshot.sharedSpace.watchEvents = [
            event(id: "movie", titleID: "past-lives", memberID: "local-user", kind: .watched, date: now),
            event(id: "corrected", titleID: "severance", memberID: "local-user", kind: .watched, date: now),
            event(
                id: "correction",
                titleID: "severance",
                memberID: "local-user",
                kind: .correction,
                date: now,
                supersedesEventID: "corrected"
            ),
            event(id: "partner", titleID: "past-lives", memberID: "partner", kind: .watched, date: now),
            event(
                id: "together-you",
                titleID: "severance",
                memberID: "local-user",
                kind: .watchedTogether,
                episode: 1,
                date: now
            ),
            event(
                id: "together-partner",
                titleID: "severance",
                memberID: "partner",
                kind: .watchedTogether,
                episode: 1,
                date: now.addingTimeInterval(1)
            )
        ]

        let summary = ViewingAnalyticsEngine.summarize(snapshot: snapshot, scope: .personal)

        XCTAssertEqual(summary.totalMinutes, 158)
        XCTAssertEqual(summary.titleCount, 2)
        XCTAssertEqual(summary.movieCount, 1)
        XCTAssertEqual(summary.seriesCount, 1)
        XCTAssertEqual(summary.episodeCount, 1)
        XCTAssertEqual(summary.playCount, 2)
        XCTAssertFalse(summary.includesEstimates)
    }

    func testTogetherSummaryDeduplicatesMemberEventsForOneSession() {
        var snapshot = emptyTrackingSnapshot()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        snapshot.sharedSpace.watchEvents = [
            event(
                id: "you",
                titleID: "severance",
                memberID: "local-user",
                kind: .watchedTogether,
                episode: 1,
                date: now
            ),
            event(
                id: "partner",
                titleID: "severance",
                memberID: "partner",
                kind: .watchedTogether,
                episode: 1,
                date: now.addingTimeInterval(1)
            )
        ]

        let summary = ViewingAnalyticsEngine.summarize(snapshot: snapshot, scope: .together)

        XCTAssertEqual(summary.totalMinutes, 52)
        XCTAssertEqual(summary.playCount, 1)
        XCTAssertEqual(summary.episodeCount, 1)
        XCTAssertEqual(summary.memberBreakdown.map(\.label), ["Partner", "You"])
        XCTAssertTrue(summary.memberBreakdown.allSatisfy { $0.minutes == 52 })
    }

    func testTogetherSummaryKeepsDifferentEpisodesMarkedCloseTogether() {
        var snapshot = emptyTrackingSnapshot()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        snapshot.sharedSpace.watchEvents = [
            event(
                id: "episode-one",
                titleID: "severance",
                memberID: "local-user",
                kind: .watchedTogether,
                episode: 1,
                date: now
            ),
            event(
                id: "episode-two",
                titleID: "severance",
                memberID: "local-user",
                kind: .watchedTogether,
                episode: 2,
                date: now.addingTimeInterval(2)
            )
        ]

        let summary = ViewingAnalyticsEngine.summarize(snapshot: snapshot, scope: .together)

        XCTAssertEqual(summary.playCount, 2)
        XCTAssertEqual(summary.totalMinutes, 104)
    }

    func testImportedProgressIsEstimatedWithoutInventingTogetherHistory() throws {
        var snapshot = emptyTrackingSnapshot()
        let movieIndex = try XCTUnwrap(snapshot.titles.firstIndex { $0.id == "past-lives" })
        snapshot.titles[movieIndex].state = .completed
        snapshot.titles[movieIndex].rewatchCount = 2
        let seriesIndex = try XCTUnwrap(snapshot.titles.firstIndex { $0.id == "severance" })
        snapshot.titles[seriesIndex].state = .watching
        snapshot.titles[seriesIndex].progress = EpisodeProgress(season: 1, episode: 3, totalEpisodes: 10)

        let personal = ViewingAnalyticsEngine.summarize(snapshot: snapshot, scope: .personal)
        let together = ViewingAnalyticsEngine.summarize(snapshot: snapshot, scope: .together)

        XCTAssertEqual(personal.totalMinutes, 474)
        XCTAssertEqual(personal.playCount, 6)
        XCTAssertEqual(personal.episodeCount, 3)
        XCTAssertTrue(personal.includesEstimates)
        XCTAssertTrue(together.isEmpty)
        XCTAssertFalse(together.includesEstimates)
    }

    func testShareTextFitsAnXPost() {
        let summary = ViewingAnalyticsEngine.summarize(snapshot: emptyTrackingSnapshot(), scope: .personal)

        XCTAssertLessThanOrEqual(summary.shareText.count, 280)
    }
}

private extension ViewingAnalyticsTests {
    func emptyTrackingSnapshot() -> LibrarySnapshot {
        var snapshot = LibrarySnapshot.sample
        snapshot.titles = snapshot.titles.map { title in
            var title = title
            title.state = .planned
            title.rewatchCount = 0
            title.lastWatchedAt = nil
            if var progress = title.progress {
                progress.episode = 0
                title.progress = progress
            }
            return title
        }
        snapshot.sharedSpace.members = [
            SpaceMember(id: "local-user", name: "You", initials: "YOU", isCurrentUser: true),
            SpaceMember(id: "partner", name: "Partner", initials: "P", isCurrentUser: false)
        ]
        snapshot.sharedSpace.watchEvents = []
        return snapshot
    }

    func event(
        id: String,
        titleID: MediaTitle.ID,
        memberID: SpaceMember.ID,
        kind: WatchEventKind,
        season: Int? = 1,
        episode: Int? = nil,
        date: Date,
        supersedesEventID: String? = nil
    ) -> SharedWatchEvent {
        SharedWatchEvent(
            id: id,
            titleID: titleID,
            memberID: memberID,
            kind: kind,
            season: season,
            episode: episode,
            occurredAt: date,
            supersedesEventID: supersedesEventID
        )
    }
}
