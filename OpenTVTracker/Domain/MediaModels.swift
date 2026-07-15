import Foundation

enum MediaKind: String, Codable, CaseIterable, Sendable {
    case movie
    case series

    var label: String {
        switch self {
        case .movie: "Movie"
        case .series: "Series"
        }
    }

    var symbol: String {
        switch self {
        case .movie: "film"
        case .series: "tv"
        }
    }
}

enum WatchState: String, Codable, CaseIterable, Sendable {
    case watching
    case planned
    case paused
    case completed

    var label: String {
        switch self {
        case .watching: "Watching"
        case .planned: "Watchlist"
        case .paused: "Paused"
        case .completed: "Completed"
        }
    }
}

enum Mood: String, Codable, CaseIterable, Identifiable, Sendable {
    case any
    case cozy
    case funny
    case intense
    case thoughtful

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: "Anything"
        case .cozy: "Cozy"
        case .funny: "Funny"
        case .intense: "Intense"
        case .thoughtful: "Thoughtful"
        }
    }

    var symbol: String {
        switch self {
        case .any: "sparkles"
        case .cozy: "mug.fill"
        case .funny: "face.smiling"
        case .intense: "bolt.fill"
        case .thoughtful: "brain.head.profile"
        }
    }
}

struct EpisodeProgress: Codable, Hashable, Sendable {
    var season: Int
    var episode: Int
    var totalEpisodes: Int

    var label: String { "S\(season) · E\(episode)" }

    var fraction: Double {
        guard totalEpisodes > 0 else { return 0 }
        return min(Double(episode) / Double(totalEpisodes), 1)
    }
}

struct EpisodeSummary: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let number: Int
    let title: String
    let airDate: Date?
    let runtimeMinutes: Int?
}

struct SeasonSummary: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let number: Int
    let title: String
    let episodes: [EpisodeSummary]
}

struct StreamingProvider: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let symbol: String
    var brandHex: String?

    static let supportedSubscriptions: [StreamingProvider] = [
        .netflix,
        .primeVideo,
        .appleTV,
        .disneyPlus,
        .max,
        .mubi,
        .paramount
    ]
}

struct CommunityReview: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let author: String
    let excerpt: String
    let rating: Double?
    let source: String
    let containsSpoilers: Bool
}

// Optional additions keep version-one archives decodable while the schema evolves.
// swiftlint:disable implicit_optional_initialization
struct MediaTitle: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let catalogID: Int
    var title: String
    var year: Int
    var kind: MediaKind
    var synopsis: String
    var genres: [String]
    var runtimeMinutes: Int
    var state: WatchState
    var progress: EpisodeProgress?
    var rating: Double
    var nextReleaseDescription: String?
    var recommendationReason: String?
    var mood: Mood
    var palette: PosterPalette
    var providers: [StreamingProvider]
    var reviews: [CommunityReview]
    var posterURL: URL?
    var backdropURL: URL?
    var trailerURL: URL?
    var userRating: Double? = nil
    var notes: String? = nil
    var rewatchCount: Int? = nil
    var lastWatchedAt: Date? = nil
    var nextEpisodeAirDate: Date? = nil
    var releaseDate: Date? = nil
    var isDismissed: Bool? = nil
    var isDisliked: Bool? = nil
    var seasons: [SeasonSummary]? = nil

    var progressLabel: String {
        switch kind {
        case .movie:
            state == .completed ? "Watched" : state.label
        case .series:
            progress?.label ?? state.label
        }
    }

    var completedRewatches: Int { rewatchCount ?? 0 }

    var isRecommendationEligible: Bool {
        state != .completed && isDismissed != true && isDisliked != true
    }
}

struct PosterPalette: Codable, Hashable, Sendable {
    let primaryHex: String
    let secondaryHex: String
}

struct SpaceMember: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let initials: String
    let isCurrentUser: Bool
}

struct SharedActivity: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let memberID: String
    let description: String
    let relativeDate: String
    let symbol: String
}

enum SharedMembershipState: String, Codable, Sendable {
    case local
    case pending
    case accepted
    case revoked
    case expired
    case left
}

enum WatchEventKind: String, Codable, Sendable {
    case watched
    case correction
    case rewatch
    case watchedTogether
}

struct SharedWatchEvent: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let titleID: MediaTitle.ID
    let memberID: SpaceMember.ID
    let kind: WatchEventKind
    let season: Int?
    let episode: Int?
    let occurredAt: Date
    let supersedesEventID: String?
}

struct MemberTasteProfile: Codable, Hashable, Identifiable, Sendable {
    let id: SpaceMember.ID
    var preferredGenres: [String]
    var preferredMoods: [Mood]
    var maximumRuntimeMinutes: Int?
}

struct SharedReaction: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let activityID: SharedActivity.ID
    let memberID: SpaceMember.ID
    let symbol: String
    let occurredAt: Date
}

struct SharedNote: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let titleID: MediaTitle.ID
    let memberID: SpaceMember.ID
    let text: String
    let createdAt: Date
}

struct SharedSpace: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var name: String
    var members: [SpaceMember]
    var titleIDs: [MediaTitle.ID]
    var activity: [SharedActivity]
    var isCloudSharingEnabled: Bool
    var membershipState: SharedMembershipState? = nil
    var watchEvents: [SharedWatchEvent]? = nil
    var tasteProfiles: [MemberTasteProfile]? = nil
    var reactions: [SharedReaction]? = nil
    var notes: [SharedNote]? = nil
    var cloudZoneName: String? = nil
    var cloudOwnerName: String? = nil
    var isCurrentUserShareOwner: Bool? = nil

    var resolvedMembershipState: SharedMembershipState {
        membershipState ?? (isCloudSharingEnabled ? .accepted : .local)
    }
}
// swiftlint:enable implicit_optional_initialization

struct LibrarySnapshot: Codable, Hashable, Sendable {
    var schemaVersion: Int?
    var titles: [MediaTitle]
    var sharedSpace: SharedSpace
    var selectedProviderIDs: Set<StreamingProvider.ID>?
    var allowsAIReranking: Bool?

    init(
        titles: [MediaTitle],
        sharedSpace: SharedSpace,
        selectedProviderIDs: Set<StreamingProvider.ID>? = nil,
        allowsAIReranking: Bool = false,
        schemaVersion: Int = 2
    ) {
        self.schemaVersion = schemaVersion
        self.titles = titles
        self.sharedSpace = sharedSpace
        self.selectedProviderIDs = selectedProviderIDs
        self.allowsAIReranking = allowsAIReranking
    }
}
