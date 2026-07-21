import Foundation

struct MediaSearchQuery: Hashable, Sendable {
    var text: String
    var kind: MediaKind?
    var page: Int
    var region: StreamingRegion
}

protocol CatalogProviding: Sendable {
    func search(_ query: MediaSearchQuery) async throws -> [MediaTitle]
    func title(kind: MediaKind, catalogID: Int, region: StreamingRegion) async throws -> MediaTitle
}

struct RecommendationContext: Hashable, Sendable {
    var mood: Mood
    var maximumRuntimeMinutes: Int?
    var sharedSpaceID: SharedSpace.ID?
    var allowsRemoteReranking = false
    var viewingProfile: RecommendationViewingProfile?
}

struct RecommendationGenreAffinity: Codable, Hashable, Sendable {
    let genre: String
    let watchedMinutes: Int
}

struct RecommendationTitleEngagement: Codable, Hashable, Sendable {
    let title: String
    let genres: [String]
    let watchedEpisodeCount: Int
    let completionFraction: Double
    let userRating: Double?
    let lastWatchedAt: Date?
}

struct RecommendationViewingProfile: Codable, Hashable, Sendable {
    let watchedMinutes: Int
    let watchedEpisodeCount: Int
    let watchedTitleCount: Int
    let topGenres: [RecommendationGenreAffinity]
    let recentTitles: [RecommendationTitleEngagement]
}

struct Recommendation: Hashable, Identifiable, Sendable {
    let id: String
    let title: MediaTitle
    let reason: String
    let score: Double
}

protocol RecommendationProviding: Sendable {
    func recommendations(
        from snapshot: LibrarySnapshot,
        context: RecommendationContext
    ) async throws -> [Recommendation]
}

enum ReminderAuthorization: String, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    var allowsScheduling: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: true
        case .notDetermined, .denied: false
        }
    }
}

struct ReminderCapability: Equatable, Sendable {
    let authorization: ReminderAuthorization
    let backgroundRefreshAvailable: Bool

    static let unknown = ReminderCapability(
        authorization: .notDetermined,
        backgroundRefreshAvailable: false
    )
}

protocol ReminderScheduling: Sendable {
    func requestAuthorization() async -> ReminderAuthorization
    func capability() async -> ReminderCapability
    func reconcile(
        titles: [MediaTitle],
        selectedProviderIDs: Set<StreamingProvider.ID>,
        settings: ReminderSettings,
        now: Date
    ) async throws
}

struct NoopReminderScheduler: ReminderScheduling {
    func requestAuthorization() async -> ReminderAuthorization {
        .denied
    }

    func capability() async -> ReminderCapability {
        .unknown
    }

    func reconcile(
        titles _: [MediaTitle],
        selectedProviderIDs _: Set<StreamingProvider.ID>,
        settings _: ReminderSettings,
        now _: Date
    ) async throws {}
}

enum PartnerSharingAvailability: Hashable, Sendable {
    case available
    case iCloudAccountRequired
    case notConfigured
}

protocol PartnerSharingProviding: Sendable {
    func availability() async -> PartnerSharingAvailability
    func inviteURL(for spaceID: SharedSpace.ID) async throws -> URL
    func revoke(spaceID: SharedSpace.ID) async throws
    func leave(space: SharedSpace) async throws
}

enum PartnerSharingError: LocalizedError {
    case notConfigured
    case accountRequired
    case shareUnavailable

    var errorDescription: String? {
        switch self {
        case .notConfigured: "CloudKit sharing is not configured for this build."
        case .accountRequired: "Sign in to iCloud on this iPhone to invite your partner."
        case .shareUnavailable: "OpenTV could not create the private invitation. Try again."
        }
    }
}
