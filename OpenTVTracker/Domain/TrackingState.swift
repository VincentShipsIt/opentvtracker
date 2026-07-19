import Foundation

enum SeriesLifecycle: String, Codable, Sendable {
    case continuing
    case ended
    case unknown
}

enum WatchState: String, Codable, CaseIterable, Sendable {
    case watching
    case caughtUp = "caught_up"
    case planned
    case paused
    case dropped
    case completed

    var label: String {
        switch self {
        case .watching: "Watching"
        case .caughtUp: "Caught Up"
        case .planned: "Watchlist"
        case .paused: "Paused"
        case .dropped: "Dropped"
        case .completed: "Completed"
        }
    }

    var symbol: String {
        switch self {
        case .watching: "play.circle.fill"
        case .caughtUp: "checkmark.seal.fill"
        case .planned: "bookmark.fill"
        case .paused: "pause.circle.fill"
        case .dropped: "xmark.circle.fill"
        case .completed: "checkmark.circle.fill"
        }
    }

    var contributesViewingHistory: Bool {
        switch self {
        case .watching, .caughtUp, .dropped, .completed: true
        case .planned, .paused: false
        }
    }

    var isCurrentViewingComplete: Bool {
        self == .caughtUp || self == .completed
    }

    static func available(for kind: MediaKind) -> [WatchState] {
        kind == .series
            ? allCases
            : allCases.filter { $0 != .caughtUp }
    }
}

extension MediaTitle {
    func migratedTrackingState(fromSchemaVersion schemaVersion: Int?) -> MediaTitle {
        guard (schemaVersion ?? 1) < 6,
              kind == .series,
              state == .completed,
              resolvedSeriesLifecycle == .continuing || nextEpisodeAirDate != nil else {
            return self
        }
        var result = self
        result.state = .caughtUp
        return result
    }
}
