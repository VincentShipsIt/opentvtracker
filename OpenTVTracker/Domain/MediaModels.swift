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

struct StreamingProvider: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let symbol: String
}

struct CommunityReview: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let author: String
    let excerpt: String
    let rating: Double?
    let source: String
    let containsSpoilers: Bool
}

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

    var progressLabel: String {
        switch kind {
        case .movie:
            state == .completed ? "Watched" : state.label
        case .series:
            progress?.label ?? state.label
        }
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

struct SharedSpace: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var name: String
    var members: [SpaceMember]
    var titleIDs: [MediaTitle.ID]
    var activity: [SharedActivity]
    var isCloudSharingEnabled: Bool
}

struct LibrarySnapshot: Codable, Hashable, Sendable {
    var titles: [MediaTitle]
    var sharedSpace: SharedSpace
}
