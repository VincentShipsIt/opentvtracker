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
