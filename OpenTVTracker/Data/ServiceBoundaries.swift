import Foundation

struct MediaSearchQuery: Hashable, Sendable {
    var text: String
    var kind: MediaKind?
    var page: Int
    var region: StreamingRegion
    var contentLanguage: ContentLanguage = .english
}

struct CommunityReviewPage: Hashable, Sendable {
    let page: Int
    let totalPages: Int
    let results: [CommunityReview]
}

enum ExternalCatalogSource: String, Codable, Sendable {
    case tvdb
}

struct ExternalCatalogReference: Hashable, Sendable {
    let source: ExternalCatalogSource
    let sourceID: Int
    let kind: MediaKind
}

protocol CatalogProviding: Sendable {
    func search(_ query: MediaSearchQuery) async throws -> [MediaTitle]
    func title(kind: MediaKind, catalogID: Int, region: StreamingRegion) async throws -> MediaTitle
    func title(
        kind: MediaKind,
        catalogID: Int,
        region: StreamingRegion,
        contentLanguage: ContentLanguage
    ) async throws -> MediaTitle
    func title(
        kind: MediaKind,
        catalogID: Int,
        region: StreamingRegion,
        contentLanguage: ContentLanguage,
        metadataSource: MetadataSource?
    ) async throws -> MediaTitle
    func reviews(kind: MediaKind, catalogID: Int, page: Int) async throws -> CommunityReviewPage
    func resolve(
        _ reference: ExternalCatalogReference,
        region: StreamingRegion
    ) async throws -> MediaTitle?
}

extension CatalogProviding {
    func title(
        kind: MediaKind,
        catalogID: Int,
        region: StreamingRegion,
        contentLanguage _: ContentLanguage
    ) async throws -> MediaTitle {
        try await title(kind: kind, catalogID: catalogID, region: region)
    }

    func title(
        kind: MediaKind,
        catalogID: Int,
        region: StreamingRegion,
        contentLanguage: ContentLanguage,
        metadataSource _: MetadataSource?
    ) async throws -> MediaTitle {
        try await title(
            kind: kind,
            catalogID: catalogID,
            region: region,
            contentLanguage: contentLanguage
        )
    }

    func reviews(kind _: MediaKind, catalogID _: Int, page: Int) async throws -> CommunityReviewPage {
        CommunityReviewPage(page: max(page, 1), totalPages: 1, results: [])
    }

    func resolve(
        _: ExternalCatalogReference,
        region _: StreamingRegion
    ) async throws -> MediaTitle? {
        nil
    }
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

protocol PartnerActivityNotifying: Sendable {
    func requestAuthorization() async
    func notify(
        about activities: [SharedActivity],
        in space: SharedSpace
    ) async
}

struct NoopPartnerActivityNotifier: PartnerActivityNotifying {
    func requestAuthorization() async {}

    func notify(
        about _: [SharedActivity],
        in _: SharedSpace
    ) async {}
}

enum PartnerSharingAvailability: Hashable, Sendable {
    case available
    case iCloudAccountRequired
    case notConfigured
}

struct PartnerInvitationLink: Identifiable, Hashable, Codable, Sendable {
    var id: String { url.absoluteString }
    let url: URL
    let createdAt: Date
}

protocol PartnerSharingProviding: Sendable {
    func availability() async -> PartnerSharingAvailability
    func inviteURL(for spaceID: SharedSpace.ID) async throws -> URL
    func invitationLinks(for spaceID: SharedSpace.ID) async throws -> [PartnerInvitationLink]
    func revoke(spaceID: SharedSpace.ID) async throws
    func leave(space: SharedSpace) async throws
}

enum PartnerSharingError: LocalizedError, Equatable {
    case notConfigured
    case accountRequired
    case iCloudStorageFull
    case shareUnavailable
    case acceptanceUnavailable
    case revokeUnavailable
    case leaveUnavailable

    var errorDescription: String? {
        switch self {
        case .notConfigured: "CloudKit sharing is not configured for this build."
        case .accountRequired: "Sign in to iCloud on this iPhone to invite your partner."
        case .iCloudStorageFull:
            "iCloud reported that this invitation exceeded the account's storage quota. Check iCloud storage in Settings, then try again."
        case .shareUnavailable: "OpenTV could not create the private invitation. Try again."
        case .acceptanceUnavailable: "OpenTV could not accept the private invitation. Try again."
        case .revokeUnavailable: "OpenTV could not revoke the private invitation. Try again."
        case .leaveUnavailable: "OpenTV could not leave the shared space. Try again."
        }
    }
}
