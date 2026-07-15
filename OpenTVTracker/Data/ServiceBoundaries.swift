import Foundation

struct MediaSearchQuery: Hashable, Sendable {
    var text: String
    var kind: MediaKind?
    var page: Int
}

protocol CatalogProviding: Sendable {
    func search(_ query: MediaSearchQuery) async throws -> [MediaTitle]
    func title(kind: MediaKind, catalogID: Int) async throws -> MediaTitle
}

struct RecommendationContext: Hashable, Sendable {
    var mood: Mood
    var maximumRuntimeMinutes: Int?
    var sharedSpaceID: SharedSpace.ID?
    var allowsRemoteReranking = false
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
