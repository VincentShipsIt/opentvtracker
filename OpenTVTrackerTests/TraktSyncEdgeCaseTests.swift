import XCTest
@testable import OpenTVTracker

private struct TraktDatePayload: Decodable {
    let watchedAt: Date

    enum CodingKeys: String, CodingKey {
        case watchedAt = "watched_at"
    }
}

final class TraktSyncEdgeCaseTests: XCTestCase {
    override func tearDown() {
        TestURLProtocol.handler = nil
        super.tearDown()
    }

    func testFractionalTraktTimestampDecodes() throws {
        let data = Data(#"{"watched_at":"2026-07-17T08:09:10.123Z"}"#.utf8)
        let payload = try TraktAPIClient.decoder.decode(TraktDatePayload.self, from: data)

        XCTAssertEqual(
            payload.watchedAt.timeIntervalSince1970,
            1_784_275_750.123,
            accuracy: 0.001
        )
    }

    func testFractionalLocalRatingRoundTripsWithoutLosingPrecision() throws {
        var snapshot = LibrarySnapshot.sample
        let media = TraktMediaKey(kind: .series, tmdbID: 95_396)
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[index].userRating = 8.5

        let plan = TraktSyncEngine.plan(
            local: snapshot,
            remote: TraktRemoteSnapshot(
                activityAt: .now,
                history: [],
                ratings: [],
                watchlist: [],
                lists: []
            )
        )

        XCTAssertEqual(plan.snapshot.titles[index].userRating, 8.5)
        XCTAssertEqual(plan.outbound.ratingsToAdd, [
            TraktRatingBaseline(media: media, rating: 9)
        ])
    }

    func testUnsupportedZeroRatingIsPreservedAndNotUploaded() throws {
        var snapshot = LibrarySnapshot.sample
        let media = TraktMediaKey(kind: .series, tmdbID: 95_396)
        let index = try XCTUnwrap(snapshot.titles.firstIndex(where: { $0.id == "severance" }))
        snapshot.titles[index].userRating = 0

        let plan = TraktSyncEngine.plan(
            local: snapshot,
            remote: TraktRemoteSnapshot(
                activityAt: .now,
                history: [],
                ratings: [
                    TraktRatingItem(media: media, rating: 8, ratedAt: .now)
                ],
                watchlist: [],
                lists: []
            )
        )

        XCTAssertEqual(plan.snapshot.titles[index].userRating, 0)
        XCTAssertTrue(plan.outbound.ratingsToAdd.isEmpty)
        XCTAssertTrue(plan.outbound.ratingsToRemove.isEmpty)
    }

    func testUnknownRemoteEpisodeCreatesPlaceholderAndAdvancesProgress() throws {
        let media = TraktMediaKey(kind: .series, tmdbID: 1_234)
        let remoteTitle = TraktRemoteTitle(
            media: media,
            title: "Remote Show",
            year: 2026,
            overview: nil,
            runtimeMinutes: 45,
            rating: nil,
            genres: []
        )
        let plan = TraktSyncEngine.plan(
            local: .empty,
            remote: TraktRemoteSnapshot(
                activityAt: .now,
                history: [
                    TraktHistoryItem(
                        id: 1,
                        media: media,
                        season: 2,
                        episode: 3,
                        watchedAt: .now
                    )
                ],
                ratings: [],
                watchlist: [],
                lists: [],
                titles: [remoteTitle]
            )
        )
        let title = try XCTUnwrap(plan.snapshot.titles.first)

        XCTAssertEqual(title.progress?.season, 2)
        XCTAssertEqual(title.progress?.episode, 3)
        XCTAssertEqual(title.seasons?.first?.episodes.first?.title, "Episode 3")
        XCTAssertEqual(title.watchedEpisodeIDs, ["trakt:1234:s2e3"])
    }

    func testRemoteAcceptedHistoryIsNotPostedAgainAfterResponseLoss() throws {
        var snapshot = LibrarySnapshot.empty
        var movie = try XCTUnwrap(
            LibrarySnapshot.sample.titles.first(where: { $0.id == "arrival" })
        )
        let watchedAt = Date(timeIntervalSince1970: 100)
        movie.lastWatchedAt = watchedAt
        snapshot.titles = [movie]
        snapshot.sharedSpace.watchEvents = [
            SharedWatchEvent(
                id: "event-1",
                titleID: movie.id,
                memberID: "local-user",
                kind: .watched,
                season: nil,
                episode: nil,
                occurredAt: watchedAt,
                supersedesEventID: nil
            )
        ]

        let plan = TraktSyncEngine.plan(
            local: snapshot,
            remote: TraktRemoteSnapshot(
                activityAt: .now,
                history: [
                    TraktHistoryItem(
                        id: 42,
                        media: TraktMediaKey(kind: .movie, tmdbID: movie.catalogID),
                        season: nil,
                        episode: nil,
                        watchedAt: watchedAt
                    )
                ],
                ratings: [],
                watchlist: [],
                lists: []
            )
        )

        XCTAssertTrue(plan.outbound.history.isEmpty)
        XCTAssertEqual(plan.snapshot.traktSyncState?.uploadedHistoryEventIDs, ["event-1"])
    }

    func testOfflineRefreshKeepsStoredCredential() async throws {
        let credentials = MemorySecureCredentialStore()
        let token = TraktOAuthToken(
            accessToken: "expired-access-token",
            tokenType: "bearer",
            expiresIn: 1,
            refreshToken: "still-valid-refresh-token",
            scope: "public",
            createdAt: 1
        )
        try credentials.set(
            JSONEncoder().encode(token),
            for: TraktAPIClient.tokenAccount
        )
        TestURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let client = TraktAPIClient(
            configuration: TraktConfiguration(
                clientID: "client-id",
                clientSecret: "client-secret"
            ),
            credentials: credentials,
            session: TestURLProtocol.session(),
            now: { Date(timeIntervalSince1970: 2_000_000_000) }
        )

        let isAuthorized = await client.isAuthorized()

        XCTAssertFalse(isAuthorized)
        XCTAssertNotNil(try credentials.data(for: TraktAPIClient.tokenAccount))
    }

    func testInvalidGrantRefreshRemovesStoredCredential() async throws {
        let credentials = MemorySecureCredentialStore()
        let token = TraktOAuthToken(
            accessToken: "expired-access-token",
            tokenType: "bearer",
            expiresIn: 1,
            refreshToken: "revoked-refresh-token",
            scope: "public",
            createdAt: 1
        )
        try credentials.set(JSONEncoder().encode(token), for: TraktAPIClient.tokenAccount)
        TestURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(#"{"error":"invalid_grant"}"#.utf8)
            )
        }
        let client = TraktAPIClient(
            configuration: TraktConfiguration(
                clientID: "client-id",
                clientSecret: "client-secret"
            ),
            credentials: credentials,
            session: TestURLProtocol.session(),
            now: { Date(timeIntervalSince1970: 2_000_000_000) }
        )

        let isAuthorized = await client.isAuthorized()

        XCTAssertFalse(isAuthorized)
        XCTAssertNil(try credentials.data(for: TraktAPIClient.tokenAccount))
    }
}
