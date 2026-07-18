import XCTest
@testable import OpenTVTracker

final class ReminderPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testPlannerDoesNothingUntilRemindersAreExplicitlyEnabled() {
        let title = series(airDate: now.addingTimeInterval(7_200))

        let plans = ReminderPlanner.plans(
            titles: [title],
            selectedProviderIDs: [.appleTV],
            settings: ReminderSettings(),
            now: now
        )

        XCTAssertTrue(plans.isEmpty)
    }

    func testEpisodePlanUsesOverrideAndSpoilerSafeCopy() throws {
        let title = series(airDate: now.addingTimeInterval(7_200))
        var settings = ReminderSettings()
        settings.isEnabled = true
        settings.automaticallyRemindTrackedTitles = true
        settings.defaultLeadTime = .oneDay
        settings.titleLeadTimes[title.id] = .fifteenMinutes

        let plan = try XCTUnwrap(ReminderPlanner.plans(
            titles: [title],
            selectedProviderIDs: [.appleTV],
            settings: settings,
            now: now
        ).first)

        XCTAssertEqual(plan.kind, .episode)
        XCTAssertEqual(plan.fireDate, now.addingTimeInterval(6_300))
        XCTAssertFalse(plan.title.contains("Secret episode title"))
        XCTAssertFalse(plan.body.contains("Secret episode title"))
        XCTAssertFalse(plan.body.contains("Secret story"))
    }

    func testFirstEpisodeOfLaterSeasonUsesReturningSeasonCopy() throws {
        let title = series(
            seasonNumber: 2,
            episodeNumber: 1,
            airDate: now.addingTimeInterval(86_400)
        )
        var settings = ReminderSettings()
        settings.isEnabled = true
        settings.automaticallyRemindTrackedTitles = true

        let plan = try XCTUnwrap(ReminderPlanner.plans(
            titles: [title],
            selectedProviderIDs: [],
            settings: settings,
            now: now
        ).first)

        XCTAssertEqual(plan.kind, .returningSeason)
        XCTAssertTrue(plan.title.contains("returning"))
        XCTAssertFalse(plan.body.contains("Season 2"))
    }

    func testMutedAndWatchedTitlesAreNotScheduled() {
        let muted = series(airDate: now.addingTimeInterval(7_200))
        var completed = series(
            sampleID: "fallout",
            airDate: now.addingTimeInterval(10_800)
        )
        completed.state = .completed
        var settings = ReminderSettings()
        settings.isEnabled = true
        settings.automaticallyRemindTrackedTitles = true
        settings.mutedTitleIDs.insert(muted.id)

        let plans = ReminderPlanner.plans(
            titles: [muted, completed],
            selectedProviderIDs: [],
            settings: settings,
            now: now
        )

        XCTAssertTrue(plans.isEmpty)
    }

    func testProviderAvailabilityRequiresSelectedProvider() throws {
        var movie = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.kind == .movie }))
        movie.state = .planned
        movie.personalWatchlist = true
        movie.providers = [.appleTV]
        movie.releaseDate = now.addingTimeInterval(172_800)
        var settings = ReminderSettings()
        settings.isEnabled = true
        settings.automaticallyRemindTrackedTitles = true
        settings.defaultLeadTime = .oneDay

        let excluded = ReminderPlanner.plans(
            titles: [movie],
            selectedProviderIDs: [.netflix],
            settings: settings,
            now: now
        )
        let included = ReminderPlanner.plans(
            titles: [movie],
            selectedProviderIDs: [.appleTV],
            settings: settings,
            now: now
        )

        XCTAssertTrue(excluded.isEmpty)
        XCTAssertEqual(included.first?.kind, .providerAvailability)
        XCTAssertEqual(included.first?.fireDate, now.addingTimeInterval(172_800))
    }

    func testWidgetSnapshotContainsUpcomingPublicLabelsWithoutPrivateNotes() throws {
        var title = series(airDate: now.addingTimeInterval(7_200))
        title.notes = "Private viewing note"

        let snapshot = WidgetSnapshotFactory.make(upNext: [title], titles: [title], now: now)
        let encoded = try JSONEncoder().encode(snapshot)
        let payload = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertEqual(snapshot.upNext?.title, title.title)
        XCTAssertEqual(snapshot.upcoming.first?.detail, "New episode")
        XCTAssertFalse(payload.contains("Private viewing note"))
        XCTAssertFalse(payload.contains("Secret episode title"))
    }

    func testExplicitTitleReminderDoesNotIncludeRestOfLibrary() {
        let enabled = series(airDate: now.addingTimeInterval(7_200))
        let excluded = series(
            sampleID: "fallout",
            airDate: now.addingTimeInterval(10_800)
        )
        var settings = ReminderSettings()
        settings.isEnabled = true
        settings.enabledTitleIDs = [enabled.id]

        let plans = ReminderPlanner.plans(
            titles: [enabled, excluded],
            selectedProviderIDs: [],
            settings: settings,
            now: now
        )

        XCTAssertEqual(Set(plans.map(\.titleID)), [enabled.id])
    }

    func testWidgetSnapshotContentIgnoresGenerationTime() {
        let first = WidgetSnapshotFactory.make(upNext: [], titles: [], now: now)
        let second = WidgetSnapshotFactory.make(
            upNext: [],
            titles: [],
            now: now.addingTimeInterval(60)
        )

        XCTAssertTrue(first.hasSameContent(as: second))
    }

    func testReconcileRemovesOnlyReminderRequestsAndSchedulesPlans() async throws {
        let center = ReminderNotificationCenterSpy(
            authorization: .authorized,
            pendingIdentifiers: ["opentv.reminder.old", "partner-activity-keep"]
        )
        let service = LocalNotificationReminderService(notificationCenter: center)
        let title = series(airDate: now.addingTimeInterval(7_200))
        var settings = ReminderSettings()
        settings.isEnabled = true
        settings.enabledTitleIDs = [title.id]

        try await service.reconcile(
            titles: [title],
            selectedProviderIDs: [],
            settings: settings,
            now: now
        )

        let removed = await center.removedIdentifiers()
        let added = await center.addedRequests()
        XCTAssertEqual(removed, ["opentv.reminder.old"])
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.titleID, title.id)
    }

    func testPlannerCapsEachSeriesAtThreeEpisodes() {
        var title = series(airDate: now.addingTimeInterval(7_200))
        title.seasons = [
            SeasonSummary(
                id: "season",
                number: 1,
                title: "Season",
                episodes: (1...10).map { episode in
                    EpisodeSummary(
                        id: "episode-\(episode)",
                        number: episode,
                        title: "Episode \(episode)",
                        airDate: now.addingTimeInterval(Double(episode) * 7_200),
                        runtimeMinutes: 50
                    )
                }
            )
        ]
        var settings = ReminderSettings()
        settings.isEnabled = true
        settings.enabledTitleIDs = [title.id]

        let plans = ReminderPlanner.plans(
            titles: [title],
            selectedProviderIDs: [],
            settings: settings,
            now: now
        )

        XCTAssertEqual(plans.count, 3)
    }

    private func series(
        sampleID: String = "severance",
        seasonNumber: Int = 1,
        episodeNumber: Int = 2,
        airDate: Date
    ) -> MediaTitle {
        var title = LibrarySnapshot.sample.titles.first(where: { $0.id == sampleID })!
        title.state = .watching
        title.personalWatchlist = true
        title.watchedEpisodeIDs = []
        title.seasons = [
            SeasonSummary(
                id: "season-\(seasonNumber)",
                number: seasonNumber,
                title: "Season \(seasonNumber)",
                episodes: [
                    EpisodeSummary(
                        id: "episode-\(seasonNumber)-\(episodeNumber)",
                        number: episodeNumber,
                        title: "Secret episode title",
                        airDate: airDate,
                        runtimeMinutes: 50,
                        overview: "Secret story"
                    )
                ]
            )
        ]
        title.nextEpisodeAirDate = airDate
        return title
    }
}

private actor ReminderNotificationCenterSpy: ReminderNotificationCenterProviding {
    private var currentAuthorization: ReminderAuthorization
    private let existingIdentifiers: [String]
    private var removed: [String] = []
    private var added: [ReminderNotificationRequest] = []

    init(
        authorization: ReminderAuthorization,
        pendingIdentifiers: [String]
    ) {
        currentAuthorization = authorization
        existingIdentifiers = pendingIdentifiers
    }

    func authorization() async -> ReminderAuthorization {
        currentAuthorization
    }

    func requestAuthorization() async -> ReminderAuthorization {
        currentAuthorization = .authorized
        return currentAuthorization
    }

    func pendingIdentifiers() async -> [String] {
        existingIdentifiers
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async {
        removed = identifiers
    }

    func add(_ request: ReminderNotificationRequest) async throws {
        added.append(request)
    }

    func removedIdentifiers() -> [String] {
        removed
    }

    func addedRequests() -> [ReminderNotificationRequest] {
        added
    }
}
