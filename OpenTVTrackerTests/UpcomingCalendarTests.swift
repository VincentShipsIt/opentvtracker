import XCTest
@testable import OpenTVTracker

final class UpcomingCalendarEngineTests: XCTestCase {
    func testClassifiesPremieresReturningSeasonsFinalesAndOrdinaryEpisodes() throws {
        let calendar = Self.calendar()
        let start = try Self.date(2026, 7, 20, calendar: calendar)
        let end = try Self.date(2026, 7, 26, calendar: calendar)
        var title = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" }))
        title.seasons = try Self.scheduledSeasons(calendar: calendar)

        let items = UpcomingCalendarEngine.items(
            from: [title],
            in: start...end,
            includedStates: [.watching],
            providerIDs: nil,
            calendar: calendar
        )

        XCTAssertEqual(
            items.map(\.kind),
            [.seriesPremiere, .seasonFinale, .returningSeason, .episode, .seasonFinale]
        )
        XCTAssertEqual(items.map(\.episodeID), ["s1e1", "s1e2", "s2e1", "s2e2", "s2e3"])
    }

    func testFiltersByTrackedStateAndSelectedProvider() throws {
        let calendar = Self.calendar()
        let releaseDate = try Self.date(2026, 7, 21, calendar: calendar)
        var movie = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "past-lives" }))
        movie.releaseDate = releaseDate
        movie.personalWatchlist = true

        let matching = UpcomingCalendarEngine.items(
            from: [movie],
            in: releaseDate...releaseDate,
            includedStates: [.planned],
            providerIDs: [.primeVideo],
            calendar: calendar
        )
        XCTAssertEqual(matching.map(\.kind), [.movieRelease])

        let wrongState = UpcomingCalendarEngine.items(
            from: [movie],
            in: releaseDate...releaseDate,
            includedStates: [.watching],
            providerIDs: [.primeVideo],
            calendar: calendar
        )
        XCTAssertTrue(wrongState.isEmpty)

        let wrongProvider = UpcomingCalendarEngine.items(
            from: [movie],
            in: releaseDate...releaseDate,
            includedStates: [.planned],
            providerIDs: [.netflix],
            calendar: calendar
        )
        XCTAssertTrue(wrongProvider.isEmpty)

        movie.personalWatchlist = false
        let notTracked = UpcomingCalendarEngine.items(
            from: [movie],
            in: releaseDate...releaseDate,
            includedStates: [.planned],
            providerIDs: nil,
            calendar: calendar
        )
        XCTAssertTrue(notTracked.isEmpty)
    }

    func testUsesNextEpisodeDateWhenEpisodeMetadataIsMissing() throws {
        let calendar = Self.calendar()
        let airDate = try Self.date(2026, 7, 22, calendar: calendar)
        var title = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" }))
        title.seasons = nil
        title.nextEpisodeAirDate = airDate

        let items = UpcomingCalendarEngine.items(
            from: [title],
            in: airDate...airDate,
            includedStates: [.watching],
            providerIDs: nil,
            calendar: calendar
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.kind, .episode)
        XCTAssertNil(items.first?.episodeID)
    }

    func testDayFilteringUsesTheUsersTimeZone() throws {
        var calendar = Self.calendar()
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 2 * 60 * 60))
        let localDay = try Self.date(2026, 7, 21, calendar: calendar)
        let utcCalendar = Self.calendar()
        let lateUTC = try Self.date(2026, 7, 20, calendar: utcCalendar)
            .addingTimeInterval((23 * 60 * 60) + (30 * 60))
        var title = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" }))
        title.seasons = nil
        title.nextEpisodeAirDate = lateUTC

        let items = UpcomingCalendarEngine.items(
            from: [title],
            in: localDay...localDay,
            includedStates: [.watching],
            providerIDs: nil,
            calendar: calendar
        )

        XCTAssertEqual(items.count, 1)
    }

    func testAllDayReleaseKeepsItsSourceDayAcrossTimeZones() throws {
        var calendar = Self.calendar()
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let sourceCalendar = Self.calendar()
        let sourceDay = try Self.date(2026, 7, 21, calendar: sourceCalendar)
        let localDay = try Self.date(2026, 7, 21, calendar: calendar)
        var title = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" }))
        title.seasons = nil
        title.nextEpisodeAirDate = sourceDay
        title.nextEpisodeAirDateIsAllDay = true

        let items = UpcomingCalendarEngine.items(
            from: [title],
            in: localDay...localDay,
            includedStates: [.watching],
            providerIDs: nil,
            calendar: calendar
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.date, localDay)
        XCTAssertEqual(items.first?.isAllDay, true)
    }

    func testPartialSeasonDoesNotInventPremiereOrFinaleLabels() throws {
        let calendar = Self.calendar()
        let airDate = try Self.date(2026, 7, 21, calendar: calendar)
        var title = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" }))
        title.seasons = [
            SeasonSummary(
                id: "partial-season-5",
                number: 5,
                title: "Season 5",
                episodes: [
                    EpisodeSummary(
                        id: "s5e3",
                        number: 3,
                        title: "Known episode",
                        airDate: airDate,
                        runtimeMinutes: 50
                    )
                ]
            )
        ]

        let items = UpcomingCalendarEngine.items(
            from: [title],
            in: airDate...airDate,
            includedStates: [.watching],
            providerIDs: nil,
            calendar: calendar
        )

        XCTAssertEqual(items.map(\.kind), [.episode])
    }

    func testTimedEpisodeRespectsDSTDayBoundary() throws {
        var calendar = Self.calendar()
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Malta"))
        let localDay = try Self.date(2026, 3, 29, calendar: calendar)
        let nextLocalDay = try Self.date(2026, 3, 30, calendar: calendar)
        let timedRelease = nextLocalDay.addingTimeInterval(30 * 60)
        var title = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" }))
        title.seasons = nil
        title.nextEpisodeAirDate = timedRelease
        title.nextEpisodeAirDateIsAllDay = false

        let items = UpcomingCalendarEngine.items(
            from: [title],
            in: localDay...localDay,
            includedStates: [.watching],
            providerIDs: nil,
            calendar: calendar
        )

        XCTAssertTrue(items.isEmpty)
    }

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    private static func scheduledSeasons(calendar: Calendar) throws -> [SeasonSummary] {
        [try seasonOne(calendar: calendar), try seasonTwo(calendar: calendar)]
    }

    private static func seasonOne(calendar: Calendar) throws -> SeasonSummary {
        SeasonSummary(
            id: "season-1",
            number: 1,
            title: "Season 1",
            episodes: [
                EpisodeSummary(
                    id: "s1e1",
                    number: 1,
                    title: "Premiere",
                    airDate: try date(2026, 7, 20, calendar: calendar),
                    runtimeMinutes: 50
                ),
                EpisodeSummary(
                    id: "s1e2",
                    number: 2,
                    title: "Finale",
                    airDate: try date(2026, 7, 21, calendar: calendar),
                    runtimeMinutes: 50,
                    releaseType: .finale
                )
            ]
        )
    }

    private static func seasonTwo(calendar: Calendar) throws -> SeasonSummary {
        SeasonSummary(
            id: "season-2",
            number: 2,
            title: "Season 2",
            episodes: [
                EpisodeSummary(
                    id: "s2e1",
                    number: 1,
                    title: "Return",
                    airDate: try date(2026, 7, 22, calendar: calendar),
                    runtimeMinutes: 50
                ),
                EpisodeSummary(
                    id: "s2e2",
                    number: 2,
                    title: "Ordinary",
                    airDate: try date(2026, 7, 23, calendar: calendar),
                    runtimeMinutes: 50
                ),
                EpisodeSummary(
                    id: "s2e3",
                    number: 3,
                    title: "Finale",
                    airDate: try date(2026, 7, 24, calendar: calendar),
                    runtimeMinutes: 50,
                    releaseType: .finale
                )
            ]
        )
    }
}

extension UpcomingCalendarEngineTests {
    func testExplicitFinaleWinsForSingleEpisodeSeason() throws {
        let calendar = Self.calendar()
        let airDate = try Self.date(2026, 7, 21, calendar: calendar)
        var title = try XCTUnwrap(
            LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" })
        )
        title.seasons = [
            SeasonSummary(
                id: "single-episode-season",
                number: 1,
                title: "Season 1",
                episodes: [
                    EpisodeSummary(
                        id: "only-episode",
                        number: 1,
                        title: "Finale",
                        airDate: airDate,
                        runtimeMinutes: 50,
                        releaseType: .finale
                    )
                ]
            )
        ]

        let items = UpcomingCalendarEngine.items(
            from: [title],
            in: airDate...airDate,
            includedStates: [.watching],
            providerIDs: nil,
            calendar: calendar
        )

        XCTAssertEqual(items.map(\.kind), [.seasonFinale])
    }
}

@MainActor
final class UpcomingCalendarRefreshTests: XCTestCase {
    func testRefreshLoadsScheduleDetailsWithoutChangingTrackingState() async throws {
        var savedTitle = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" }))
        savedTitle.seasons = nil
        var refreshedTitle = savedTitle
        refreshedTitle.state = .planned
        refreshedTitle.seasons = [
            SeasonSummary(
                id: "season-3",
                number: 3,
                title: "Season 3",
                episodes: [
                    EpisodeSummary(
                        id: "s3e1",
                        number: 1,
                        title: "Return",
                        airDate: .now.addingTimeInterval(86_400),
                        runtimeMinutes: 52
                    )
                ]
            )
        ]
        let snapshot = LibrarySnapshot(titles: [savedTitle], sharedSpace: .emptyForCalendarTests)
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: LocalCatalogService(titles: [refreshedTitle]),
            seed: snapshot
        )

        await model.refreshUpcomingCalendar(force: true)

        let result = try XCTUnwrap(model.mediaTitle(withID: savedTitle.id))
        XCTAssertEqual(result.state, .watching)
        XCTAssertEqual(result.seasons?.first?.id, "season-3")
        XCTAssertNotNil(model.upcomingCalendarLastRefreshedAt)
        XCTAssertNil(model.upcomingCalendarRefreshError)
    }

    func testRefreshFailureKeepsSavedMetadataAndExposesOfflineState() async throws {
        var title = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" }))
        title.nextEpisodeAirDate = .now.addingTimeInterval(86_400)
        let snapshot = LibrarySnapshot(titles: [title], sharedSpace: .emptyForCalendarTests)
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: FailingCalendarCatalogService(),
            seed: snapshot
        )

        await model.refreshUpcomingCalendar(force: true)

        XCTAssertEqual(model.mediaTitle(withID: title.id)?.nextEpisodeAirDate, title.nextEpisodeAirDate)
        XCTAssertNil(model.upcomingCalendarLastRefreshedAt)
        XCTAssertNotNil(model.upcomingCalendarLastAttemptedAt)
        XCTAssertNotNil(model.upcomingCalendarRefreshError)
    }
}

private struct FailingCalendarCatalogService: CatalogProviding {
    func search(_: MediaSearchQuery) async throws -> [MediaTitle] {
        throw CatalogServiceError.unavailable
    }

    func title(kind _: MediaKind, catalogID _: Int, region _: StreamingRegion) async throws -> MediaTitle {
        throw CatalogServiceError.unavailable
    }
}

private extension SharedSpace {
    static let emptyForCalendarTests = SharedSpace(
        id: "calendar-tests",
        name: "Calendar tests",
        members: [SpaceMember(id: "local-user", name: "You", initials: "YOU", isCurrentUser: true)],
        titleIDs: [],
        activity: [],
        isCloudSharingEnabled: false
    )
}
