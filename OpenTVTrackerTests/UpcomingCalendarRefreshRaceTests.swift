import XCTest
@testable import OpenTVTracker

@MainActor
final class UpcomingCalendarRefreshRaceTests: XCTestCase {
    func testRegionChangeQueuesRefreshAndRejectsStaleResults() async throws {
        var savedTitle = try XCTUnwrap(
            LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" })
        )
        savedTitle.seasons = nil
        let usTitle = Self.title(savedTitle, seasonID: "us-season")
        let gbTitle = Self.title(savedTitle, seasonID: "gb-season")
        let service = ControlledCalendarCatalogService(titlesByRegion: [
            "US": usTitle,
            "GB": gbTitle
        ])
        let snapshot = LibrarySnapshot(
            titles: [savedTitle],
            sharedSpace: .emptyForCalendarRaceTests,
            streamingRegionCode: "US"
        )
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: service,
            seed: snapshot
        )

        let initialRefresh = Task { await model.refreshUpcomingCalendar(force: true) }
        await service.waitUntilRequested(regionCode: "US")

        model.setStreamingRegionOverride(try XCTUnwrap(StreamingRegion(code: "GB")))
        await service.release(regionCode: "US")
        await service.waitUntilRequested(regionCode: "GB")
        await service.release(regionCode: "GB")
        await initialRefresh.value

        XCTAssertEqual(model.streamingRegion.code, "GB")
        XCTAssertEqual(model.mediaTitle(withID: savedTitle.id)?.seasons?.first?.id, "gb-season")
        XCTAssertNil(model.upcomingCalendarRefreshError)
    }

    func testCancellationDoesNotThrottleTheNextRefresh() async throws {
        let title = try XCTUnwrap(
            LibrarySnapshot.sample.titles.first(where: { $0.id == "severance" })
        )
        let snapshot = LibrarySnapshot(
            titles: [title],
            sharedSpace: .emptyForCalendarRaceTests
        )
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: CancelingCalendarCatalogService(),
            seed: snapshot
        )

        await model.refreshUpcomingCalendar(force: true)

        XCTAssertNil(model.upcomingCalendarLastAttemptedAt)
        XCTAssertNil(model.upcomingCalendarRefreshError)
    }

    func testTVMazeOnlyCatalogSkipsUnsupportedMovieRefreshes() async throws {
        var movie = try XCTUnwrap(
            LibrarySnapshot.sample.titles.first(where: { $0.kind == .movie })
        )
        movie.personalWatchlist = true
        let snapshot = LibrarySnapshot(
            titles: [movie],
            sharedSpace: .emptyForCalendarRaceTests
        )
        let model = AppModel(
            store: MemoryLibraryStore(),
            catalogService: TVMazeCatalogService(),
            seed: snapshot
        )

        await model.refreshUpcomingCalendar(force: true)

        XCTAssertNil(model.upcomingCalendarRefreshError)
        XCTAssertNil(model.upcomingCalendarLastRefreshedAt)
    }

    private static func title(_ title: MediaTitle, seasonID: String) -> MediaTitle {
        var result = title
        result.seasons = [
            SeasonSummary(
                id: seasonID,
                number: 1,
                title: "Season 1",
                episodes: []
            )
        ]
        return result
    }
}

private actor ControlledCalendarCatalogService: CatalogProviding {
    let titlesByRegion: [String: MediaTitle]
    private var requestedRegionCodes: Set<String> = []
    private var releasedRegionCodes: Set<String> = []

    init(titlesByRegion: [String: MediaTitle]) {
        self.titlesByRegion = titlesByRegion
    }

    func search(_: MediaSearchQuery) async throws -> [MediaTitle] {
        []
    }

    func title(
        kind _: MediaKind,
        catalogID _: Int,
        region: StreamingRegion
    ) async throws -> MediaTitle {
        requestedRegionCodes.insert(region.code)
        while !releasedRegionCodes.contains(region.code) {
            try Task.checkCancellation()
            await Task.yield()
        }
        guard let title = titlesByRegion[region.code] else {
            throw CatalogServiceError.notFound
        }
        return title
    }

    func waitUntilRequested(regionCode: String) async {
        while !requestedRegionCodes.contains(regionCode) {
            await Task.yield()
        }
    }

    func release(regionCode: String) {
        releasedRegionCodes.insert(regionCode)
    }
}

private struct CancelingCalendarCatalogService: CatalogProviding {
    func search(_: MediaSearchQuery) async throws -> [MediaTitle] {
        []
    }

    func title(
        kind _: MediaKind,
        catalogID _: Int,
        region _: StreamingRegion
    ) async throws -> MediaTitle {
        throw CancellationError()
    }
}

private extension SharedSpace {
    static let emptyForCalendarRaceTests = SharedSpace(
        id: "calendar-race-tests",
        name: "Calendar race tests",
        members: [
            SpaceMember(id: "local-user", name: "You", initials: "YOU", isCurrentUser: true)
        ],
        titleIDs: [],
        activity: [],
        isCloudSharingEnabled: false
    )
}
