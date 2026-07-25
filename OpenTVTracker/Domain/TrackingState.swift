import Foundation

/// Counted nouns, pluralized by automatic grammar agreement rather than by a hardcoded
/// English ternary. Twelve call sites each wrote their own `count == 1 ? "x" : "xs"`,
/// which bakes English plural rules into view code and breaks the moment the app is
/// translated. `inflect: true` hands the rule to the localization engine instead.
enum CountLabel {
    /// "1 episode" / "6 episodes".
    static func episodes(_ count: Int) -> String {
        inflected(AttributedString(localized: "^[\(count) episode](inflect: true)"))
    }

    /// "1 title" / "6 titles".
    static func titles(_ count: Int) -> String {
        inflected(AttributedString(localized: "^[\(count) title](inflect: true)"))
    }

    /// "1 more title" / "6 more titles". The count and the noun are split by "more", so
    /// this needs its own inflected phrase rather than a prefix bolted onto `titles(_:)`.
    static func moreTitles(_ count: Int) -> String {
        inflected(AttributedString(localized: "^[\(count) more title](inflect: true)"))
    }

    /// "1 service" / "6 services".
    static func services(_ count: Int) -> String {
        inflected(AttributedString(localized: "^[\(count) service](inflect: true)"))
    }

    /// "1 list" / "6 lists".
    static func lists(_ count: Int) -> String {
        inflected(AttributedString(localized: "^[\(count) list](inflect: true)"))
    }

    /// "1 minute" / "6 minutes".
    static func minutes(_ count: Int) -> String {
        inflected(AttributedString(localized: "^[\(count) minute](inflect: true)"))
    }

    /// Returns a plain `String` so accessibility labels, share text and `Text` can all
    /// share one source — `Text` re-inflects an `AttributedString`, the others cannot.
    private static func inflected(_ value: AttributedString) -> String {
        String(value.characters)
    }
}

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
