import Foundation

struct TraktConfiguration: Sendable {
    let clientID: String
    let clientSecret: String
    let apiBaseURL: URL

    init(
        clientID: String,
        clientSecret: String,
        apiBaseURL: URL = URL(string: "https://api.trakt.tv")!
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.apiBaseURL = apiBaseURL
    }
}

enum TraktSyncServiceFactory {
    static func makeDefault() -> any TraktSyncProviding {
        guard let clientID = AppServiceConfiguration.traktClientID,
              let clientSecret = AppServiceConfiguration.traktClientSecret else {
            return UnconfiguredTraktSyncService()
        }
        return TraktAPIClient(configuration: TraktConfiguration(
            clientID: clientID,
            clientSecret: clientSecret
        ))
    }
}

actor TraktAPIClient: TraktSyncProviding {
    static let tokenAccount = "trakt.oauth-token"

    let configuration: TraktConfiguration
    let session: URLSession
    private let credentials: any SecureCredentialStoring
    private let now: @Sendable () -> Date

    init(
        configuration: TraktConfiguration,
        credentials: any SecureCredentialStoring = KeychainCredentialStore(),
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.configuration = configuration
        self.credentials = credentials
        self.session = session
        self.now = now
    }

    func isAuthorized() async -> Bool {
        (try? await validToken()) != nil
    }

    func beginAuthorization() async throws -> TraktDeviceAuthorization {
        let response: TraktDeviceCodeResponse = try await send(
            path: "/oauth/device/code",
            method: "POST",
            body: TraktDeviceCodeRequest(clientID: configuration.clientID),
            token: nil
        )
        guard let verificationURL = URL(string: response.verificationURL),
              verificationURL.scheme == "https",
              response.expiresIn > 0,
              response.interval > 0 else {
            throw TraktSyncError.invalidResponse
        }
        return TraktDeviceAuthorization(
            deviceCode: response.deviceCode,
            userCode: response.userCode,
            verificationURL: verificationURL,
            expiresAt: now().addingTimeInterval(TimeInterval(response.expiresIn)),
            intervalSeconds: response.interval
        )
    }

    func completeAuthorization(_ authorization: TraktDeviceAuthorization) async throws {
        var interval = authorization.intervalSeconds
        while now() < authorization.expiresAt {
            do {
                switch try await pollAuthorization(authorization.deviceCode) {
                case .authorized(let token):
                    try store(token)
                    return
                case .pending:
                    try await Task.sleep(for: .seconds(interval))
                case .slowDown:
                    interval += 5
                    try await Task.sleep(for: .seconds(interval))
                }
            } catch TraktSyncError.providerUnavailable {
                try await Task.sleep(for: .seconds(interval))
            }
        }
        throw TraktSyncError.authorizationExpired
    }

    func disconnect() async throws {
        defer { try? credentials.remove(account: Self.tokenAccount) }
        guard let token = try? storedToken() else { return }
        try? await sendWithoutResponse(
            path: "/oauth/revoke",
            method: "POST",
            body: TraktRevokeRequest(
                token: token.accessToken,
                clientID: configuration.clientID,
                clientSecret: configuration.clientSecret
            ),
            token: nil
        )
    }

    func sync(_ snapshot: LibrarySnapshot) async throws -> TraktSyncResult {
        let token = try await requiredToken()
        let activity: TraktLastActivityResponse = try await get(
            path: "/sync/last_activities",
            token: token.accessToken
        )
        let previousState = snapshot.traktSyncState ?? .empty
        let shouldPull = previousState.lastRemoteActivityAt == nil
            || activity.all > (previousState.lastRemoteActivityAt ?? .distantPast)
            || TraktSyncEngine.hasPendingHistory(in: snapshot)
        let remote: TraktRemoteSnapshot
        if shouldPull {
            remote = try await fetchRemoteSnapshot(
                activityAt: activity.all,
                token: token.accessToken
            )
        } else {
            remote = remoteBaseline(from: previousState, activityAt: activity.all)
        }

        let plan = TraktSyncEngine.plan(local: snapshot, remote: remote)
        try await push(plan.outbound, token: token.accessToken)

        var syncedSnapshot = plan.snapshot
        var syncedState = syncedSnapshot.traktSyncState ?? .empty
        syncedState.uploadedHistoryEventIDs.formUnion(plan.outbound.history.map(\.eventID))
        syncedState.lastSyncedAt = now()
        syncedState.lastError = nil
        syncedSnapshot.traktSyncState = syncedState

        return TraktSyncResult(
            snapshot: syncedSnapshot,
            summary: TraktSyncSummary(
                importedHistoryCount: plan.importedHistoryCount,
                importedRatingCount: plan.importedRatingCount,
                importedWatchlistCount: plan.importedWatchlistCount,
                importedListCount: plan.importedListCount,
                uploadedChangeCount: plan.outbound.count
            )
        )
    }
}

extension TraktAPIClient {
    private enum DevicePollResult {
        case authorized(TraktOAuthToken)
        case pending
        case slowDown
    }

    private func pollAuthorization(_ deviceCode: String) async throws -> DevicePollResult {
        let request = try makeRequest(
            path: "/oauth/device/token",
            method: "POST",
            body: TraktDeviceTokenRequest(
                code: deviceCode,
                clientID: configuration.clientID,
                clientSecret: configuration.clientSecret
            ),
            token: nil
        )
        let (data, response) = try await data(for: request)
        switch response.statusCode {
        case 200:
            return .authorized(try Self.decoder.decode(TraktOAuthToken.self, from: data))
        case 400:
            return .pending
        case 404, 409:
            throw TraktSyncError.invalidAuthorization
        case 410:
            throw TraktSyncError.authorizationExpired
        case 418:
            throw TraktSyncError.authorizationDenied
        case 429:
            return .slowDown
        case 500...599:
            throw TraktSyncError.providerUnavailable
        default:
            throw TraktSyncError.invalidResponse
        }
    }

    private func validToken() async throws -> TraktOAuthToken? {
        guard let token = try storedToken() else { return nil }
        if token.expiresAt > now().addingTimeInterval(60) {
            return token
        }
        return try await refresh(token)
    }

    private func requiredToken() async throws -> TraktOAuthToken {
        guard let token = try await validToken() else { throw TraktSyncError.notAuthorized }
        return token
    }

    private func refresh(_ token: TraktOAuthToken) async throws -> TraktOAuthToken {
        do {
            let request = try makeRequest(
                path: "/oauth/token",
                method: "POST",
                body: TraktRefreshRequest(
                    refreshToken: token.refreshToken,
                    clientID: configuration.clientID,
                    clientSecret: configuration.clientSecret,
                    grantType: "refresh_token"
                ),
                token: nil
            )
            let (data, response) = try await data(for: request)
            if response.statusCode == 400,
               (try? Self.decoder.decode(TraktOAuthErrorResponse.self, from: data))?.error == "invalid_grant" {
                try? credentials.remove(account: Self.tokenAccount)
                throw TraktSyncError.notAuthorized
            }
            try validate(response)
            let refreshed = try Self.decoder.decode(TraktOAuthToken.self, from: data)
            try store(refreshed)
            return refreshed
        } catch TraktSyncError.notAuthorized {
            try? credentials.remove(account: Self.tokenAccount)
            throw TraktSyncError.notAuthorized
        } catch {
            throw error
        }
    }

    private func storedToken() throws -> TraktOAuthToken? {
        guard let data = try credentials.data(for: Self.tokenAccount) else { return nil }
        return try? JSONDecoder().decode(TraktOAuthToken.self, from: data)
    }

    private func store(_ token: TraktOAuthToken) throws {
        try credentials.set(try JSONEncoder().encode(token), for: Self.tokenAccount)
    }
}

extension TraktAPIClient {
    private func fetchRemoteSnapshot(
        activityAt: Date,
        token: String
    ) async throws -> TraktRemoteSnapshot {
        let movieHistory: [TraktHistoryDTO] = try await getAll(
            path: "/sync/history/movies?extended=full",
            token: token
        )
        let episodeHistory: [TraktHistoryDTO] = try await getAll(
            path: "/sync/history/episodes?extended=full",
            token: token
        )
        let movieRatings: [TraktRatingDTO] = try await getAll(
            path: "/sync/ratings/movies?extended=full",
            token: token
        )
        let showRatings: [TraktRatingDTO] = try await getAll(
            path: "/sync/ratings/shows?extended=full",
            token: token
        )
        let movieWatchlist: [TraktListItemDTO] = try await getAll(
            path: "/sync/watchlist/movies/added/asc?extended=full",
            token: token
        )
        let showWatchlist: [TraktListItemDTO] = try await getAll(
            path: "/sync/watchlist/shows/added/asc?extended=full",
            token: token
        )
        let fetchedLists = try await fetchLists(token: token)
        let remoteTitles = deduplicatedTitles(
            (movieHistory + episodeHistory).compactMap(\.remoteTitle)
                + (movieRatings + showRatings).compactMap(\.remoteTitle)
                + (movieWatchlist + showWatchlist).compactMap(\.remoteTitle)
                + fetchedLists.titles
        )

        return TraktRemoteSnapshot(
            activityAt: activityAt,
            history: (movieHistory + episodeHistory).compactMap(\.historyItem),
            ratings: (movieRatings + showRatings).compactMap(\.ratingItem),
            watchlist: Set((movieWatchlist + showWatchlist).compactMap(\.mediaKey)),
            lists: fetchedLists.memberships,
            titles: remoteTitles
        )
    }

    private func fetchLists(
        token: String
    ) async throws -> (memberships: [TraktListMembership], titles: [TraktRemoteTitle]) {
        let lists: [TraktListDTO] = try await getAll(path: "/users/me/lists", token: token)
        var memberships: [TraktListMembership] = []
        var remoteTitles: [TraktRemoteTitle] = []
        for list in lists {
            let items: [TraktListItemDTO] = try await getAll(
                path: "/users/me/lists/\(list.ids.trakt)/items/movie,show"
                    + "?extended=full&sort_by=rank&sort_how=asc",
                token: token
            )
            remoteTitles.append(contentsOf: items.compactMap(\.remoteTitle))
            memberships.append(TraktListMembership(
                id: list.ids.trakt,
                name: list.name,
                privacy: list.privacy,
                items: Set(items.compactMap(\.mediaKey))
            ))
        }
        return (
            memberships.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            deduplicatedTitles(remoteTitles)
        )
    }

    private func deduplicatedTitles(_ titles: [TraktRemoteTitle]) -> [TraktRemoteTitle] {
        Array(Dictionary(titles.map { ($0.media, $0) }, uniquingKeysWith: { current, candidate in
            if current.overview == nil, candidate.overview != nil { return candidate }
            return current
        }).values)
    }

    private func remoteBaseline(
        from state: TraktSyncState,
        activityAt: Date
    ) -> TraktRemoteSnapshot {
        TraktRemoteSnapshot(
            activityAt: activityAt,
            history: [],
            ratings: state.syncedRatings.map {
                TraktRatingItem(media: $0.media, rating: $0.rating, ratedAt: .distantPast)
            },
            watchlist: state.syncedWatchlist,
            lists: state.importedLists,
            titles: []
        )
    }

    private func push(_ changes: TraktOutboundChanges, token: String) async throws {
        if !changes.ratingsToAdd.isEmpty {
            try await sendWithoutResponse(
                path: "/sync/ratings",
                method: "POST",
                body: TraktMutationPayload.ratings(changes.ratingsToAdd),
                token: token
            )
        }
        if !changes.ratingsToRemove.isEmpty {
            try await sendWithoutResponse(
                path: "/sync/ratings/remove",
                method: "POST",
                body: TraktMutationPayload.media(changes.ratingsToRemove),
                token: token
            )
        }
        if !changes.watchlistToAdd.isEmpty {
            try await sendWithoutResponse(
                path: "/sync/watchlist",
                method: "POST",
                body: TraktMutationPayload.media(changes.watchlistToAdd),
                token: token
            )
        }
        if !changes.watchlistToRemove.isEmpty {
            try await sendWithoutResponse(
                path: "/sync/watchlist/remove",
                method: "POST",
                body: TraktMutationPayload.media(changes.watchlistToRemove),
                token: token
            )
        }

        // History is intentionally last. The other sync endpoints are idempotent
        // upserts/removals, while Trakt requires clients to deduplicate plays.
        if !changes.history.isEmpty {
            try await sendWithoutResponse(
                path: "/sync/history",
                method: "POST",
                body: TraktMutationPayload.history(changes.history),
                token: token
            )
        }
    }
}
