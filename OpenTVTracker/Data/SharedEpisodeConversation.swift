import Foundation
import UserNotifications

struct SharedReactionAsset: Hashable, Identifiable, Sendable {
    let id: String
    let kind: SharedReactionAssetKind
    let label: String
    let displayValue: String
    let resourceName: String?
}

enum SharedReactionAssetPolicy {
    static let emojiAssets = [
        SharedReactionAsset(
            id: "love",
            kind: .emoji,
            label: "Love",
            displayValue: "❤️",
            resourceName: nil
        ),
        SharedReactionAsset(
            id: "wow",
            kind: .emoji,
            label: "Wow",
            displayValue: "😮",
            resourceName: nil
        ),
        SharedReactionAsset(
            id: "laugh",
            kind: .emoji,
            label: "Funny",
            displayValue: "😂",
            resourceName: nil
        ),
        SharedReactionAsset(
            id: "cry",
            kind: .emoji,
            label: "Emotional",
            displayValue: "😭",
            resourceName: nil
        ),
        SharedReactionAsset(
            id: "fire",
            kind: .emoji,
            label: "Fire",
            displayValue: "🔥",
            resourceName: nil
        )
    ]

    static let gifAssets = [
        SharedReactionAsset(
            id: "mind-blown",
            kind: .gif,
            label: "Mind blown",
            displayValue: "Mind blown",
            resourceName: "reaction-mind-blown"
        ),
        SharedReactionAsset(
            id: "applause",
            kind: .gif,
            label: "Applause",
            displayValue: "Applause",
            resourceName: "reaction-applause"
        ),
        SharedReactionAsset(
            id: "happy-dance",
            kind: .gif,
            label: "Happy dance",
            displayValue: "Happy dance",
            resourceName: "reaction-happy-dance"
        )
    ]

    static let allAssets = emojiAssets + gifAssets

    static func asset(kind: SharedReactionAssetKind, id: String) -> SharedReactionAsset? {
        allAssets.first { $0.kind == kind && $0.id == id }
    }

    static func asset(for reaction: SharedReaction) -> SharedReactionAsset? {
        if let kind = reaction.assetKind,
           let id = reaction.assetID {
            return asset(kind: kind, id: id)
        }

        return switch reaction.symbol {
        case "heart.fill", "❤️": asset(kind: .emoji, id: "love")
        case "hand.thumbsup.fill", "🔥": asset(kind: .emoji, id: "fire")
        case "face.smiling.fill", "😂": asset(kind: .emoji, id: "laugh")
        case "😮": asset(kind: .emoji, id: "wow")
        case "😭": asset(kind: .emoji, id: "cry")
        default: nil
        }
    }
}

struct SharedConversationState: Equatable, Sendable {
    let reactions: [SharedReaction]
    let notes: [SharedNote]
    let deletions: [SharedConversationDeletion]
}

enum SharedConversationReconciler {
    static func reconcile(remote: SharedSpace, local: SharedSpace) -> SharedConversationState {
        let deletions = latestValues(
            remote: remote.conversationDeletions ?? [],
            local: local.conversationDeletions ?? [],
            date: \.deletedAt
        )
        let deletionByID = Dictionary(uniqueKeysWithValues: deletions.map { ($0.id, $0) })

        let reactions = latestValues(
            remote: remote.reactions ?? [],
            local: local.reactions ?? [],
            date: \.occurredAt
        )
        .filter { reaction in
            guard let deletion = deletionByID["reaction:\(reaction.id)"] else { return true }
            return reaction.occurredAt > deletion.deletedAt
        }

        let notes = mergeByID(
            remote: remote.notes ?? [],
            local: local.notes ?? []
        )
        .filter { note in
            guard let deletion = deletionByID["note:\(note.id)"] else { return true }
            return note.createdAt > deletion.deletedAt
        }

        return SharedConversationState(
            reactions: reactions.sorted { $0.occurredAt < $1.occurredAt },
            notes: notes.sorted { $0.createdAt < $1.createdAt },
            deletions: deletions.sorted { $0.deletedAt < $1.deletedAt }
        )
    }

    private static func latestValues<Value: Identifiable>(
        remote: [Value],
        local: [Value],
        date: KeyPath<Value, Date>
    ) -> [Value] where Value.ID: Hashable {
        var valuesByID: [Value.ID: Value] = [:]
        for value in remote + local {
            if let existing = valuesByID[value.id],
               existing[keyPath: date] > value[keyPath: date] {
                continue
            }
            valuesByID[value.id] = value
        }
        return Array(valuesByID.values)
    }

    private static func mergeByID<Value: Identifiable>(
        remote: [Value],
        local: [Value]
    ) -> [Value] where Value.ID: Hashable {
        var seen = Set<Value.ID>()
        return (remote + local).filter { seen.insert($0.id).inserted }
    }
}

enum SharedConversationNotificationEvent: Hashable, Identifiable, Sendable {
    case note(SharedNote)
    case reaction(SharedReaction)

    var id: String {
        switch self {
        case .note(let note): "note:\(note.id)"
        case .reaction(let reaction): "reaction:\(reaction.id):\(reaction.occurredAt.timeIntervalSince1970)"
        }
    }

    var memberID: SpaceMember.ID {
        switch self {
        case .note(let note): note.memberID
        case .reaction(let reaction): reaction.memberID
        }
    }

    var watchEventID: SharedWatchEvent.ID? {
        switch self {
        case .note(let note): note.watchEventID
        case .reaction(let reaction): reaction.watchEventID
        }
    }

    var occurredAt: Date {
        switch self {
        case .note(let note): note.createdAt
        case .reaction(let reaction): reaction.occurredAt
        }
    }

    var kindLabel: String {
        switch self {
        case .note: "note"
        case .reaction: "reaction"
        }
    }
}

struct SharedConversationNotification: Hashable, Identifiable, Sendable {
    let id: String
    let memberName: String
    let body: String
    let watchEventID: SharedWatchEvent.ID
    let titleID: MediaTitle.ID
}

enum SharedConversationNotificationPlanner {
    private static let maximumAge: TimeInterval = 24 * 60 * 60
    private static let maximumFutureClockSkew: TimeInterval = 5 * 60
    private static let maximumNotificationsPerSync = 3

    static func notifications(
        for events: [SharedConversationNotificationEvent],
        in space: SharedSpace,
        excluding seenEventIDs: Set<String>,
        now: Date
    ) -> [SharedConversationNotification] {
        guard space.isCloudSharingEnabled,
              space.resolvedMembershipState == .accepted,
              let currentMemberID = space.members.first(where: \.isCurrentUser)?.id else {
            return []
        }

        let membersByID = space.members.reduce(into: [SpaceMember.ID: SpaceMember]()) {
            $0[$1.id] = $1
        }
        let watchEventsByID = (space.watchEvents ?? []).reduce(
            into: [SharedWatchEvent.ID: SharedWatchEvent]()
        ) {
            $0[$1.id] = $1
        }

        return events
            .filter { event in
                guard !seenEventIDs.contains(event.id),
                      event.memberID != currentMemberID,
                      membersByID[event.memberID] != nil,
                      let watchEventID = event.watchEventID,
                      watchEventsByID[watchEventID] != nil else {
                    return false
                }
                let age = now.timeIntervalSince(event.occurredAt)
                return age <= maximumAge && age >= -maximumFutureClockSkew
            }
            .sorted { $0.occurredAt < $1.occurredAt }
            .suffix(maximumNotificationsPerSync)
            .compactMap { event in
                guard let watchEventID = event.watchEventID,
                      let watchEvent = watchEventsByID[watchEventID] else {
                    return nil
                }
                return SharedConversationNotification(
                    id: event.id,
                    memberName: membersByID[event.memberID]?.name ?? "Your partner",
                    body: "A new private \(event.kindLabel) is waiting after you watch.",
                    watchEventID: watchEventID,
                    titleID: watchEvent.titleID
                )
            }
    }
}

protocol SharedConversationNotifying: Sendable {
    func requestAuthorization() async -> Bool
    func notify(
        about events: [SharedConversationNotificationEvent],
        in space: SharedSpace
    ) async
}

actor SharedConversationNotificationService: SharedConversationNotifying {
    private static let seenEventIDsKey = "opentv.shared-conversation.seen-event-ids"

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.center = center
        self.defaults = defaults
        self.now = now
    }

    func requestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        if Self.isAuthorized(settings.authorizationStatus) {
            return true
        }
        guard settings.authorizationStatus == .notDetermined else { return false }
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
            return false
        }
        return Self.isAuthorized((await center.notificationSettings()).authorizationStatus)
    }

    func notify(
        about events: [SharedConversationNotificationEvent],
        in space: SharedSpace
    ) async {
        guard !events.isEmpty else { return }

        var seenEventIDs = Set(defaults.stringArray(forKey: Self.seenEventIDsKey) ?? [])
        let notifications = SharedConversationNotificationPlanner.notifications(
            for: events,
            in: space,
            excluding: seenEventIDs,
            now: now()
        )

        seenEventIDs.formUnion(events.map(\.id))
        defaults.set(Array(seenEventIDs.sorted().suffix(500)), forKey: Self.seenEventIDsKey)

        let settings = await center.notificationSettings()
        guard Self.isAuthorized(settings.authorizationStatus) else { return }

        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = "\(notification.memberName) added to your episode thread"
            content.body = notification.body
            content.sound = .default
            content.interruptionLevel = .active
            content.userInfo = [
                "titleID": notification.titleID,
                "watchEventID": notification.watchEventID
            ]

            let request = UNNotificationRequest(
                identifier: "shared-conversation-\(notification.id)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }
}
