import XCTest
@testable import OpenTVTracker

final class ReminderPlannerBoundsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testPlannerCapsTheGlobalRequestCount() {
        let titles = (0..<20).map { eligibleSeries(id: "series-\($0)", hourOffset: $0 * 3) }
        var settings = ReminderSettings()
        settings.isEnabled = true
        settings.automaticallyRemindTrackedTitles = true

        let plans = ReminderPlanner.plans(
            titles: titles,
            selectedProviderIDs: [],
            settings: settings,
            now: now
        )

        XCTAssertEqual(plans.count, 56)
        XCTAssertEqual(plans.map(\.fireDate), plans.map(\.fireDate).sorted())
    }

    func testUntrackedCatalogSeriesIsNotReminderEligible() {
        var title = eligibleSeries()
        title.state = .planned
        title.personalWatchlist = false
        var settings = ReminderSettings()
        settings.isEnabled = true
        settings.enabledTitleIDs = [title.id]

        XCTAssertFalse(title.isReminderEligible)
        XCTAssertTrue(ReminderPlanner.plans(
            titles: [title],
            selectedProviderIDs: [],
            settings: settings,
            now: now
        ).isEmpty)
    }

    func testExplicitMovieReminderIgnoresAutomaticProviderFilterAndUsesLeadTime() throws {
        var movie = try XCTUnwrap(LibrarySnapshot.sample.titles.first { $0.kind == .movie })
        movie.personalWatchlist = true
        movie.providers = [.netflix]
        movie.releaseDate = now.addingTimeInterval(7_200)
        var settings = ReminderSettings()
        settings.isEnabled = true
        settings.providerAvailabilityEnabled = false
        settings.enabledTitleIDs = [movie.id]
        settings.titleLeadTimes[movie.id] = .oneHour

        let plan = try XCTUnwrap(ReminderPlanner.plans(
            titles: [movie],
            selectedProviderIDs: [.appleTV],
            settings: settings,
            now: now
        ).first)

        XCTAssertEqual(plan.kind, .providerAvailability)
        XCTAssertEqual(plan.fireDate, now.addingTimeInterval(3_600))
    }

    @MainActor
    func testLoadFailureDoesNotReconcilePendingReminders() async {
        let scheduler = ReconcileCountingReminderScheduler()
        let model = AppModel(
            store: FailingReminderLibraryStore(),
            reminderScheduler: scheduler,
            seed: .sample
        )

        await model.load()
        let count = await scheduler.reconcileCount()

        XCTAssertEqual(count, 0)
    }

    private func eligibleSeries(id: String = "severance", hourOffset: Int = 0) -> MediaTitle {
        var title = MediaTitle(
            id: id,
            catalogID: hourOffset,
            title: id,
            year: 2026,
            kind: .series,
            synopsis: "",
            genres: [],
            runtimeMinutes: 50,
            state: .watching,
            progress: nil,
            rating: 0,
            nextReleaseDescription: nil,
            recommendationReason: nil,
            mood: .any,
            palette: PosterPalette(primaryHex: "000000", secondaryHex: "000000"),
            providers: [],
            reviews: []
        )
        title.personalWatchlist = true
        title.watchedEpisodeIDs = []
        title.seasons = [
            SeasonSummary(
                id: "season",
                number: 1,
                title: "Season",
                episodes: (1...3).map { number in
                    EpisodeSummary(
                        id: "episode-\(number)",
                        number: number,
                        title: "Episode \(number)",
                        airDate: now.addingTimeInterval(Double(hourOffset + number) * 7_200),
                        runtimeMinutes: 50
                    )
                }
            )
        ]
        return title
    }
}

private struct FailingReminderLibraryStore: LibraryPersisting {
    struct LoadFailure: Error {}

    func load() async throws -> LibrarySnapshot? {
        throw LoadFailure()
    }

    func save(_: LibrarySnapshot) async throws {}
}

private actor ReconcileCountingReminderScheduler: ReminderScheduling {
    private var reconciliations = 0

    func requestAuthorization() async -> ReminderAuthorization {
        .authorized
    }

    func capability() async -> ReminderCapability {
        ReminderCapability(authorization: .authorized, backgroundRefreshAvailable: true)
    }

    func reconcile(
        titles _: [MediaTitle],
        selectedProviderIDs _: Set<StreamingProvider.ID>,
        settings _: ReminderSettings,
        now _: Date
    ) async throws {
        reconciliations += 1
    }

    func reconcileCount() -> Int {
        reconciliations
    }
}
