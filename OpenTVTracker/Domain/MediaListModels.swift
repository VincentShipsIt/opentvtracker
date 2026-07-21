import Foundation

struct MediaList: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var name: String
    var titleIDs: [MediaTitle.ID]
    var updatedAt: Date
}

struct SharedMediaList: Codable, Hashable, Identifiable, Sendable {
    let id: MediaList.ID
    var name: String
    var titleIDs: [MediaTitle.ID]
    let ownerMemberID: SpaceMember.ID
    var updatedAt: Date
    var deletedAt: Date?

    var isDeleted: Bool { deletedAt != nil }

    init(
        id: MediaList.ID,
        name: String,
        titleIDs: [MediaTitle.ID],
        ownerMemberID: SpaceMember.ID,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.titleIDs = titleIDs
        self.ownerMemberID = ownerMemberID
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
