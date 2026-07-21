import Foundation

// Optional additions keep version-one archives decodable while the schema evolves.
// swiftlint:disable implicit_optional_initialization
struct SharedReaction: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let activityID: SharedActivity.ID
    let memberID: SpaceMember.ID
    let symbol: String
    let occurredAt: Date
    var watchEventID: SharedWatchEvent.ID? = nil
    var titleID: MediaTitle.ID? = nil
    var season: Int? = nil
    var episode: Int? = nil
    var assetKind: SharedReactionAssetKind? = nil
    var assetID: String? = nil
}

struct SharedNote: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let titleID: MediaTitle.ID
    let memberID: SpaceMember.ID
    let text: String
    let createdAt: Date
    var watchEventID: SharedWatchEvent.ID? = nil
    var season: Int? = nil
    var episode: Int? = nil
}
// swiftlint:enable implicit_optional_initialization

enum SharedReactionAssetKind: String, Codable, Sendable {
    case emoji
    case gif
}

enum SharedConversationEntryKind: String, Codable, Sendable {
    case reaction
    case note
}

struct SharedConversationDeletion: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let entryID: String
    let entryKind: SharedConversationEntryKind
    let deletedAt: Date

    init(
        entryID: String,
        entryKind: SharedConversationEntryKind,
        deletedAt: Date = .now
    ) {
        id = "\(entryKind.rawValue):\(entryID)"
        self.entryID = entryID
        self.entryKind = entryKind
        self.deletedAt = deletedAt
    }
}
