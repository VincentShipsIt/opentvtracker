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
}

struct FoundationPartnerSharingService: PartnerSharingProviding {
    func availability() async -> PartnerSharingAvailability {
        .notConfigured
    }

    func inviteURL(for spaceID: SharedSpace.ID) async throws -> URL {
        throw PartnerSharingError.notConfigured
    }
}

enum PartnerSharingError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        "Private iCloud invitations are planned for the Together milestone."
    }
}
