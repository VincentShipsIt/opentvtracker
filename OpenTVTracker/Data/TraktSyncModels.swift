import Foundation

struct TraktMediaKey: Codable, Hashable, Sendable {
    let kind: MediaKind
    let tmdbID: Int
}

struct TraktRatingBaseline: Codable, Hashable, Sendable {
    let media: TraktMediaKey
    let rating: Int
}

struct TraktListMembership: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let privacy: String
    let items: Set<TraktMediaKey>
}

struct TraktSyncState: Codable, Hashable, Sendable {
    var lastSyncedAt: Date?
    var lastRemoteActivityAt: Date?
    var uploadedHistoryEventIDs: Set<String>
    var syncedWatchlist: Set<TraktMediaKey>
    var syncedRatings: [TraktRatingBaseline]
    var importedLists: [TraktListMembership]
    var lastError: String?

    static let empty = TraktSyncState(
        lastSyncedAt: nil,
        lastRemoteActivityAt: nil,
        uploadedHistoryEventIDs: [],
        syncedWatchlist: [],
        syncedRatings: [],
        importedLists: [],
        lastError: nil
    )
}

struct TraktDeviceAuthorization: Hashable, Identifiable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresAt: Date
    let intervalSeconds: Int

    var id: String { deviceCode }

    var activationURL: URL {
        verificationURL.appending(path: userCode)
    }
}

struct TraktSyncSummary: Hashable, Sendable {
    let importedHistoryCount: Int
    let importedRatingCount: Int
    let importedWatchlistCount: Int
    let importedListCount: Int
    let uploadedChangeCount: Int

    var description: String {
        let importedCount = importedHistoryCount + importedRatingCount + importedWatchlistCount
        return "\(importedCount) imported · \(uploadedChangeCount) uploaded · \(importedListCount) lists preserved"
    }
}

struct TraktSyncResult: Sendable {
    let snapshot: LibrarySnapshot
    let summary: TraktSyncSummary
}

protocol TraktSyncProviding: Sendable {
    func isAuthorized() async -> Bool
    func beginAuthorization() async throws -> TraktDeviceAuthorization
    func completeAuthorization(_ authorization: TraktDeviceAuthorization) async throws
    func disconnect() async throws
    func sync(_ snapshot: LibrarySnapshot) async throws -> TraktSyncResult
}

enum TraktSyncError: LocalizedError {
    case notConfigured
    case notAuthorized
    case authorizationExpired
    case authorizationDenied
    case invalidAuthorization
    case rateLimited
    case providerUnavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Trakt is not configured for this build."
        case .notAuthorized:
            "Connect a Trakt account before syncing."
        case .authorizationExpired:
            "The Trakt activation code expired. Start again for a new code."
        case .authorizationDenied:
            "Trakt authorization was denied."
        case .invalidAuthorization:
            "Trakt could not authorize this activation code."
        case .rateLimited:
            "Trakt asked OpenTV to slow down. Try syncing again shortly."
        case .providerUnavailable:
            "Trakt is temporarily unavailable. Your local library was not changed."
        case .invalidResponse:
            "Trakt returned data OpenTV could not safely apply."
        }
    }
}

struct TraktRemoteSnapshot: Sendable {
    var activityAt: Date?
    var history: [TraktHistoryItem]
    var ratings: [TraktRatingItem]
    var watchlist: Set<TraktMediaKey>
    var lists: [TraktListMembership]
    var titles: [TraktRemoteTitle]

    init(
        activityAt: Date?,
        history: [TraktHistoryItem],
        ratings: [TraktRatingItem],
        watchlist: Set<TraktMediaKey>,
        lists: [TraktListMembership],
        titles: [TraktRemoteTitle] = []
    ) {
        self.activityAt = activityAt
        self.history = history
        self.ratings = ratings
        self.watchlist = watchlist
        self.lists = lists
        self.titles = titles
    }

    static let empty = TraktRemoteSnapshot(
        activityAt: nil,
        history: [],
        ratings: [],
        watchlist: [],
        lists: [],
        titles: []
    )
}

struct TraktRemoteTitle: Hashable, Sendable {
    let media: TraktMediaKey
    let title: String
    let year: Int
    let overview: String?
    let runtimeMinutes: Int?
    let rating: Double?
    let genres: [String]

    var mediaTitle: MediaTitle {
        MediaTitle(
            id: "\(media.kind.rawValue)-\(media.tmdbID)",
            catalogID: media.tmdbID,
            title: title,
            year: year,
            kind: media.kind,
            synopsis: overview ?? "Imported from Trakt. Refresh catalog details when online.",
            genres: genres,
            runtimeMinutes: runtimeMinutes ?? 0,
            state: .planned,
            progress: nil,
            rating: rating ?? 0,
            nextReleaseDescription: nil,
            recommendationReason: nil,
            mood: .any,
            palette: PosterPalette(primaryHex: "3D4E81", secondaryHex: "161A2C"),
            providers: [],
            reviews: [],
            personalWatchlist: false,
            metadataSource: .tmdb,
            sourceURL: URL(string: "https://trakt.tv/search/tmdb/\(media.tmdbID)?id_type=\(media.kind == .movie ? "movie" : "show")")
        )
    }
}

struct TraktHistoryItem: Hashable, Sendable {
    let id: Int64
    let media: TraktMediaKey
    let season: Int?
    let episode: Int?
    let watchedAt: Date
}

struct TraktRatingItem: Hashable, Sendable {
    let media: TraktMediaKey
    let rating: Int
    let ratedAt: Date
}

struct TraktHistoryMutation: Hashable, Sendable {
    let eventID: String
    let media: TraktMediaKey
    let season: Int?
    let episode: Int?
    let watchedAt: Date
}

struct TraktOutboundChanges: Sendable {
    let history: [TraktHistoryMutation]
    let ratingsToAdd: [TraktRatingBaseline]
    let ratingsToRemove: Set<TraktMediaKey>
    let watchlistToAdd: Set<TraktMediaKey>
    let watchlistToRemove: Set<TraktMediaKey>

    var count: Int {
        history.count
            + ratingsToAdd.count
            + ratingsToRemove.count
            + watchlistToAdd.count
            + watchlistToRemove.count
    }
}

struct TraktSyncPlan: Sendable {
    let snapshot: LibrarySnapshot
    let outbound: TraktOutboundChanges
    let importedHistoryCount: Int
    let importedRatingCount: Int
    let importedWatchlistCount: Int
    let importedListCount: Int
}

struct UnconfiguredTraktSyncService: TraktSyncProviding {
    func isAuthorized() async -> Bool { false }

    func beginAuthorization() async throws -> TraktDeviceAuthorization {
        throw TraktSyncError.notConfigured
    }

    func completeAuthorization(_ authorization: TraktDeviceAuthorization) async throws {
        _ = authorization
        throw TraktSyncError.notConfigured
    }

    func disconnect() async throws {}

    func sync(_ snapshot: LibrarySnapshot) async throws -> TraktSyncResult {
        _ = snapshot
        throw TraktSyncError.notConfigured
    }
}
