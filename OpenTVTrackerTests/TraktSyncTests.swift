import XCTest
@testable import OpenTVTracker

final class TraktSyncTests: XCTestCase {
    override func tearDown() {
        TestURLProtocol.handler = nil
        super.tearDown()
    }

    func testDeviceAuthorizationUsesRequiredHeadersAndStoresTokensInKeychain() async throws {
        let credentials = MemorySecureCredentialStore()
        TestURLProtocol.handler = authorizedTraktHandler
        let client = makeAuthorizedTraktClient(credentials: credentials)

        let authorization = try await client.beginAuthorization()
        XCTAssertEqual(authorization.userCode, "ABCD1234")
        XCTAssertEqual(authorization.activationURL.absoluteString, "https://trakt.tv/activate/ABCD1234")

        try await client.completeAuthorization(authorization)

        XCTAssertEqual(credentials.writtenAccounts, [TraktAPIClient.tokenAccount])
        let isAuthorized = await client.isAuthorized()
        XCTAssertTrue(isAuthorized)
    }

    func testRemoteEpisodeHistoryNeverMovesLocalProgressBackward() throws {
        var snapshot = Self.episodeSnapshot
        let remote = TraktRemoteSnapshot(
            activityAt: Date(timeIntervalSince1970: 200),
            history: [
                TraktHistoryItem(
                    id: 10,
                    media: TraktMediaKey(kind: .series, tmdbID: 95_396),
                    season: 1,
                    episode: 1,
                    watchedAt: Date(timeIntervalSince1970: 100)
                )
            ],
            ratings: [],
            watchlist: [],
            lists: []
        )

        let plan = TraktSyncEngine.plan(local: snapshot, remote: remote)
        let title = try XCTUnwrap(plan.snapshot.titles.first(where: { $0.id == "severance" }))

        XCTAssertEqual(title.watchedEpisodeIDs, ["s1e1", "s1e2"])
        XCTAssertEqual(title.progress?.episode, 2)
        snapshot = plan.snapshot
        XCTAssertEqual(snapshot.traktSyncState?.lastRemoteActivityAt, remote.activityAt)
    }

    func testSimultaneousRatingConflictKeepsLocalValue() throws {
        var snapshot = LibrarySnapshot.sample
        let media = TraktMediaKey(kind: .series, tmdbID: 95_396)
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[index].userRating = 9
        snapshot.traktSyncState = TraktSyncState(
            lastSyncedAt: Date(timeIntervalSince1970: 100),
            lastRemoteActivityAt: Date(timeIntervalSince1970: 100),
            uploadedHistoryEventIDs: [],
            syncedWatchlist: [],
            syncedRatings: [TraktRatingBaseline(media: media, rating: 8)],
            importedLists: [],
            lastError: nil
        )
        let remote = TraktRemoteSnapshot(
            activityAt: Date(timeIntervalSince1970: 200),
            history: [],
            ratings: [
                TraktRatingItem(
                    media: media,
                    rating: 7,
                    ratedAt: Date(timeIntervalSince1970: 200)
                )
            ],
            watchlist: [],
            lists: []
        )

        let plan = TraktSyncEngine.plan(local: snapshot, remote: remote)
        let title = try XCTUnwrap(plan.snapshot.titles.first(where: { $0.id == "severance" }))

        XCTAssertEqual(title.userRating, 9)
        XCTAssertEqual(plan.outbound.ratingsToAdd, [TraktRatingBaseline(media: media, rating: 9)])
    }

    func testRemoteWatchlistRemovalAppliesWhenLocalSideDidNotChange() throws {
        var snapshot = LibrarySnapshot.sample
        let media = TraktMediaKey(kind: .movie, tmdbID: 666_277)
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "past-lives" }))
        snapshot.titles[index].personalWatchlist = true
        snapshot.traktSyncState = TraktSyncState(
            lastSyncedAt: Date(timeIntervalSince1970: 100),
            lastRemoteActivityAt: Date(timeIntervalSince1970: 100),
            uploadedHistoryEventIDs: [],
            syncedWatchlist: [media],
            syncedRatings: [],
            importedLists: [],
            lastError: nil
        )

        let plan = TraktSyncEngine.plan(
            local: snapshot,
            remote: TraktRemoteSnapshot(
                activityAt: Date(timeIntervalSince1970: 200),
                history: [],
                ratings: [],
                watchlist: [],
                lists: []
            )
        )
        let title = try XCTUnwrap(plan.snapshot.titles.first(where: { $0.id == "past-lives" }))

        XCTAssertFalse(title.isOnPersonalWatchlist)
        XCTAssertTrue(plan.outbound.watchlistToRemove.isEmpty)
    }

    func testUploadedHistoryEventIsNotCountedOrSentAgain() {
        var snapshot = LibrarySnapshot.empty
        var movie = LibrarySnapshot.sample.titles.first(where: { $0.id == "arrival" })!
        movie.lastWatchedAt = Date(timeIntervalSince1970: 100)
        snapshot.titles = [movie]
        snapshot.sharedSpace.watchEvents = [
            SharedWatchEvent(
                id: "event-1",
                titleID: movie.id,
                memberID: "local-user",
                kind: .watched,
                season: nil,
                episode: nil,
                occurredAt: Date(timeIntervalSince1970: 100),
                supersedesEventID: nil
            )
        ]
        snapshot.traktSyncState = TraktSyncState(
            lastSyncedAt: Date(timeIntervalSince1970: 200),
            lastRemoteActivityAt: Date(timeIntervalSince1970: 200),
            uploadedHistoryEventIDs: ["event-1"],
            syncedWatchlist: [],
            syncedRatings: [],
            importedLists: [],
            lastError: nil
        )

        XCTAssertEqual(TraktSyncEngine.pendingChangeCount(in: snapshot), 0)
        let plan = TraktSyncEngine.plan(
            local: snapshot,
            remote: TraktRemoteSnapshot(
                activityAt: Date(timeIntervalSince1970: 200),
                history: [],
                ratings: [],
                watchlist: [],
                lists: []
            )
        )
        XCTAssertTrue(plan.outbound.history.isEmpty)
    }

    @MainActor
    func testProviderFailureLeavesLocalTitlesUntouchedAndRecordsRecoverableError() async {
        let seed = LibrarySnapshot.sample
        let model = AppModel(
            store: MemoryLibraryStore(),
            traktService: FailingTraktSyncService(),
            seed: seed
        )

        await model.syncTrakt()

        XCTAssertEqual(model.titles, seed.titles)
        XCTAssertEqual(model.traktSyncError, TraktSyncError.providerUnavailable.localizedDescription)
        XCTAssertEqual(model.traktSyncState.lastError, TraktSyncError.providerUnavailable.localizedDescription)
    }

    @MainActor
    func testCompletedSyncPreservesTitlesChangedWhileRequestWasInFlight() throws {
        let baseline = LibrarySnapshot.sample.titles
        var current = baseline
        var synced = baseline
        let index = try XCTUnwrap(baseline.firstIndex(where: { $0.id == "past-lives" }))
        current[index].notes = "Watch with Alex"
        synced[index].personalWatchlist = false

        let merged = AppModel.mergingTraktTitles(
            baseline: baseline,
            current: current,
            synced: synced
        )

        let title = try XCTUnwrap(merged.first(where: { $0.id == "past-lives" }))
        XCTAssertEqual(title.notes, "Watch with Alex")
        XCTAssertEqual(title.personalWatchlist, synced[index].personalWatchlist)
    }

    private static var episodeSnapshot: LibrarySnapshot {
        var snapshot = LibrarySnapshot.sample
        let index = snapshot.titles.firstIndex(where: { $0.id == "severance" })!
        snapshot.titles[index].seasons = [
            SeasonSummary(
                id: "season-1",
                number: 1,
                title: "Season 1",
                episodes: [
                    EpisodeSummary(
                        id: "s1e1",
                        number: 1,
                        title: "Episode 1",
                        airDate: nil,
                        runtimeMinutes: 50
                    ),
                    EpisodeSummary(
                        id: "s1e2",
                        number: 2,
                        title: "Episode 2",
                        airDate: nil,
                        runtimeMinutes: 51
                    ),
                    EpisodeSummary(
                        id: "s1e3",
                        number: 3,
                        title: "Episode 3",
                        airDate: nil,
                        runtimeMinutes: 52
                    )
                ]
            )
        ]
        snapshot.titles[index].watchedEpisodeIDs = ["s1e1", "s1e2"]
        snapshot.titles[index].progress = EpisodeProgress(season: 1, episode: 2, totalEpisodes: 3)
        return snapshot
    }

}

private func makeAuthorizedTraktClient(
    credentials: MemorySecureCredentialStore
) -> TraktAPIClient {
    TraktAPIClient(
        configuration: TraktConfiguration(
            clientID: "client-id",
            clientSecret: "client-secret"
        ),
        credentials: credentials,
        session: TestURLProtocol.session(),
        now: { Date(timeIntervalSince1970: 2_000_000_000) }
    )
}

private func authorizedTraktHandler(
    _ request: URLRequest
) throws -> (HTTPURLResponse, Data) {
    XCTAssertEqual(request.value(forHTTPHeaderField: "trakt-api-key"), "client-id")
    XCTAssertEqual(request.value(forHTTPHeaderField: "trakt-api-version"), "2")
    let body = try XCTUnwrap(TestURLProtocol.bodyData(for: request))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])

    switch request.url?.path {
    case "/oauth/device/code":
        XCTAssertEqual(json["client_id"], "client-id")
        return traktResponse(request, body: TraktSyncTests.deviceCodeResponse)
    case "/oauth/device/token":
        XCTAssertEqual(json["code"], "device-code")
        XCTAssertEqual(json["client_secret"], "client-secret")
        return traktResponse(request, body: TraktSyncTests.tokenResponse)
    default:
        throw URLError(.unsupportedURL)
    }
}

private func traktResponse(
    _ request: URLRequest,
    statusCode: Int = 200,
    body: String
) -> (HTTPURLResponse, Data) {
    (
        HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!,
        Data(body.utf8)
    )
}

private extension TraktSyncTests {
    static let deviceCodeResponse = """
    {
      "device_code": "device-code",
      "user_code": "ABCD1234",
      "verification_url": "https://trakt.tv/activate",
      "expires_in": 600,
      "interval": 5
    }
    """

    static let tokenResponse = """
    {
      "access_token": "access-token",
      "token_type": "bearer",
      "expires_in": 604800,
      "refresh_token": "refresh-token",
      "scope": "public",
      "created_at": 2000000000
    }
    """
}

private struct FailingTraktSyncService: TraktSyncProviding {
    func isAuthorized() async -> Bool { true }

    func beginAuthorization() async throws -> TraktDeviceAuthorization {
        throw TraktSyncError.providerUnavailable
    }

    func completeAuthorization(_ authorization: TraktDeviceAuthorization) async throws {
        _ = authorization
        throw TraktSyncError.providerUnavailable
    }

    func disconnect() async throws {}

    func sync(_ snapshot: LibrarySnapshot) async throws -> TraktSyncResult {
        _ = snapshot
        throw TraktSyncError.providerUnavailable
    }
}
