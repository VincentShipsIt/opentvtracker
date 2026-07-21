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

enum MetadataSource: String, Codable, Sendable {
    case tmdb = "TMDB"
    case tvmaze = "TVmaze"

    var displayName: String { rawValue }
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

struct MediaProgressSummary: Hashable, Sendable {
    let label: String
    let fraction: Double

    init(label: String, fraction: Double) {
        self.label = label
        self.fraction = min(max(fraction, 0), 1)
    }
}

struct EpisodeSummary: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let number: Int
    let title: String
    let airDate: Date?
    let runtimeMinutes: Int?
    var overview: String?
    var stillURL: URL?
    var rating: Double?
    var releaseType: EpisodeReleaseType?
    var airDateIsAllDay: Bool?
}

enum EpisodeReleaseType: String, Codable, Hashable, Sendable {
    case standard
    case midSeason = "mid_season"
    case finale
}

struct SeasonSummary: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let number: Int
    let title: String
    let episodes: [EpisodeSummary]
}

enum StreamingProviderID: String, Codable, CaseIterable, Sendable {
    case netflix
    case primeVideo = "prime-video"
    case appleTV = "apple-tv"
    case disneyPlus = "disney-plus"
    case max
    case mubi
    case paramount
}

struct StreamingProvider: Codable, Hashable, Identifiable, Sendable {
    let id: StreamingProviderID
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

extension StreamingProvider {
    static let netflix = StreamingProvider(id: .netflix, name: "Netflix", symbol: "n.square.fill", brandHex: "E50914")
    static let primeVideo = StreamingProvider(id: .primeVideo, name: "Prime Video", symbol: "play.rectangle.fill", brandHex: "00A8E1")
    static let appleTV = StreamingProvider(id: .appleTV, name: "Apple TV+", symbol: "apple.logo", brandHex: "1C1C1E")
    static let disneyPlus = StreamingProvider(id: .disneyPlus, name: "Disney+", symbol: "sparkles.tv", brandHex: "113CCF")
    static let max = StreamingProvider(id: .max, name: "Max", symbol: "play.tv", brandHex: "5822B4")
    static let mubi = StreamingProvider(id: .mubi, name: "MUBI", symbol: "m.circle", brandHex: "1976D2")
    static let paramount = StreamingProvider(id: .paramount, name: "Paramount+", symbol: "mountain.2", brandHex: "0064FF")
}

struct CommunityReview: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let author: String
    let excerpt: String
    let rating: Double?
    let source: String
    let containsSpoilers: Bool
    var username: String?
    var avatarURL: URL?
    var sourceURL: URL?
    var createdAt: Date?
    var updatedAt: Date?
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
    var nextEpisodeAirDateIsAllDay: Bool? = nil
    var releaseDate: Date? = nil
    var isDismissed: Bool? = nil
    var isDisliked: Bool? = nil
    var personalWatchlist: Bool? = nil
    var seasons: [SeasonSummary]? = nil
    var metadataSource: MetadataSource? = nil
    var sourceURL: URL? = nil
    var watchedEpisodeIDs: Set<EpisodeSummary.ID>? = nil
    var seriesLifecycle: SeriesLifecycle? = nil
    var isUpNextPinned: Bool? = nil
    var upNextSnoozedUntil: Date? = nil
    var upNextManualOrder: Int? = nil

    var progressLabel: String {
        switch kind {
        case .movie:
            state == .completed ? "Watched" : state.label
        case .series:
            progress?.label ?? state.label
        }
    }

    var completedRewatches: Int { rewatchCount ?? 0 }

    var isOnPersonalWatchlist: Bool {
        personalWatchlist ?? (state == .planned)
    }

    var isRecommendationEligible: Bool {
        !state.isCurrentViewingComplete
            && state != .dropped
            && isDismissed != true
            && isDisliked != true
    }

    var resolvedSeriesLifecycle: SeriesLifecycle {
        seriesLifecycle ?? .unknown
    }

    var finishedWatchState: WatchState {
        guard kind == .series else { return .completed }
        switch resolvedSeriesLifecycle {
        case .continuing:
            return .caughtUp
        case .ended:
            return .completed
        case .unknown:
            return nextEpisodeAirDate == nil ? .completed : .caughtUp
        }
    }

    func isSnoozed(at date: Date) -> Bool {
        upNextSnoozedUntil.map { $0 > date } ?? false
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
    var titleID: MediaTitle.ID? = nil
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
    var titleMetadata: [MediaTitle]? = nil

    var resolvedMembershipState: SharedMembershipState {
        membershipState ?? (isCloudSharingEnabled ? .accepted : .local)
    }
}
// swiftlint:enable implicit_optional_initialization

struct ImportResolutionAlias: Codable, Hashable, Sendable {
    let kind: MediaKind
    let catalogID: Int
}

struct LibrarySnapshot: Codable, Hashable, Sendable {
    var schemaVersion: Int?
    var titles: [MediaTitle]
    var sharedSpace: SharedSpace
    var selectedProviderIDs: Set<StreamingProvider.ID>?
    var allowsAIReranking: Bool?
    var streamingRegionCode: String?
    var reminderSettings: ReminderSettings?
    var importResolutionAliases: [String: ImportResolutionAlias]?
    var hasCompletedFirstRun: Bool?

    init(
        titles: [MediaTitle],
        sharedSpace: SharedSpace,
        selectedProviderIDs: Set<StreamingProvider.ID>? = nil,
        allowsAIReranking: Bool = false,
        streamingRegionCode: String? = nil,
        reminderSettings: ReminderSettings = ReminderSettings(),
        importResolutionAliases: [String: ImportResolutionAlias]? = nil,
        hasCompletedFirstRun: Bool? = nil,
        schemaVersion: Int = 6
    ) {
        self.schemaVersion = schemaVersion
        self.titles = titles
        self.sharedSpace = sharedSpace
        self.selectedProviderIDs = selectedProviderIDs
        self.allowsAIReranking = allowsAIReranking
        self.streamingRegionCode = streamingRegionCode
        self.reminderSettings = reminderSettings
        self.importResolutionAliases = importResolutionAliases
        self.hasCompletedFirstRun = hasCompletedFirstRun
    }
}

extension LibrarySnapshot {
    static let empty = LibrarySnapshot(
        titles: [],
        sharedSpace: SharedSpace(
            id: "primary-partner-space",
            name: "Our space",
            members: [
                SpaceMember(id: "local-user", name: "You", initials: "YOU", isCurrentUser: true)
            ],
            titleIDs: [],
            activity: [],
            isCloudSharingEnabled: false,
            membershipState: .local,
            watchEvents: [],
            tasteProfiles: [],
            reactions: [],
            notes: [],
            isCurrentUserShareOwner: true
        )
    )
}
