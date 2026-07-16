import Foundation

enum ImportMetricCategory: String, CaseIterable, Hashable, Identifiable, Sendable {
    case shows
    case episodes
    case movies
    case ratings
    case rewatches
    case watchlist

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shows: "Shows"
        case .episodes: "Episodes"
        case .movies: "Movies"
        case .ratings: "Ratings"
        case .rewatches: "Rewatches"
        case .watchlist: "Watchlist"
        }
    }
}

struct ImportCountComparison: Hashable, Identifiable, Sendable {
    let category: ImportMetricCategory
    let sourceCount: Int
    let importedCount: Int

    var id: ImportMetricCategory { category }
}

enum ImportResolutionReason: String, Hashable, Sendable {
    case missingTitle
    case noCatalogMatch
    case ambiguousCatalogMatch
    case catalogUnavailable

    var label: String {
        switch self {
        case .missingTitle: "Missing title"
        case .noCatalogMatch: "No catalog match"
        case .ambiguousCatalogMatch: "Several possible matches"
        case .catalogUnavailable: "Catalog unavailable"
        }
    }
}

struct ImportResolutionIssue: Hashable, Identifiable, Sendable {
    let id: String
    let sourceID: String?
    let title: String
    let year: Int?
    let kind: MediaKind
    let reason: ImportResolutionReason
    let detail: String

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let sourceID { return "\(kind.label) source ID \(sourceID)" }
        return "Unnamed \(kind.label.lowercased())"
    }
}

struct ImportWarning: Hashable, Identifiable, Sendable {
    let id: String
    let message: String
}
