import Foundation

extension AppModel {
    func appendWatchEvent(
        title: MediaTitle,
        kind: WatchEventKind,
        memberID: SpaceMember.ID? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        supersedesEventID: String? = nil
    ) {
        let resolvedMemberID = memberID ?? sharedSpace.members.first(where: \.isCurrentUser)?.id ?? "local-user"
        let event = SharedWatchEvent(
            id: UUID().uuidString,
            titleID: title.id,
            memberID: resolvedMemberID,
            kind: kind,
            season: season ?? title.progress?.season,
            episode: episode ?? title.progress?.episode,
            occurredAt: .now,
            supersedesEventID: supersedesEventID
        )
        var events = sharedSpace.watchEvents ?? []
        events.append(event)
        sharedSpace.watchEvents = events
    }
}
