import Foundation
import UserNotifications

actor PartnerActivityNotificationService: PartnerActivityNotifying {
    private static let seenActivityIDsKey = "opentv.partner-notifications.seen-activity-ids"

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

    func requestAuthorization() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func notify(
        about activities: [SharedActivity],
        in space: SharedSpace
    ) async {
        guard !activities.isEmpty else { return }

        var seenActivityIDs = Set(defaults.stringArray(forKey: Self.seenActivityIDsKey) ?? [])
        let notifications = PartnerActivityNotificationPlanner.notifications(
            for: activities,
            in: space,
            excluding: seenActivityIDs,
            now: now()
        )

        seenActivityIDs.formUnion(activities.map(\.id))
        let retainedActivityIDs = Array(Array(seenActivityIDs).sorted().suffix(500))
        defaults.set(retainedActivityIDs, forKey: Self.seenActivityIDsKey)

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else {
            return
        }

        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = "\(notification.memberName) watched with you"
            content.body = notification.activityDescription
            content.sound = .default
            content.interruptionLevel = .active
            if let titleID = notification.titleID {
                content.userInfo["titleID"] = titleID
            }

            let request = UNNotificationRequest(
                identifier: "partner-activity-\(notification.id)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }
}

struct PartnerActivityNotification: Hashable, Sendable {
    let id: SharedActivity.ID
    let memberName: String
    let activityDescription: String
    let titleID: MediaTitle.ID?
}

enum PartnerActivityNotificationPlanner {
    private static let maximumAge: TimeInterval = 24 * 60 * 60
    private static let maximumFutureClockSkew: TimeInterval = 5 * 60
    private static let maximumNotificationsPerSync = 3

    static func notifications(
        for activities: [SharedActivity],
        in space: SharedSpace,
        excluding seenActivityIDs: Set<SharedActivity.ID>,
        now: Date
    ) -> [PartnerActivityNotification] {
        guard let currentMemberID = space.members.first(where: \.isCurrentUser)?.id else { return [] }
        let membersByID = Dictionary(uniqueKeysWithValues: space.members.map { ($0.id, $0) })

        return activities
            .filter { activity in
                guard activity.kind == .watchedTogether,
                      activity.memberID != currentMemberID,
                      !seenActivityIDs.contains(activity.id),
                      let occurredAt = activity.occurredAt else {
                    return false
                }
                let age = now.timeIntervalSince(occurredAt)
                return age <= maximumAge && age >= -maximumFutureClockSkew
            }
            .sorted {
                ($0.occurredAt ?? .distantPast) < ($1.occurredAt ?? .distantPast)
            }
            .suffix(maximumNotificationsPerSync)
            .map { activity in
                PartnerActivityNotification(
                    id: activity.id,
                    memberName: membersByID[activity.memberID]?.name ?? "Your partner",
                    activityDescription: activity.description.prefix(1).uppercased()
                        + String(activity.description.dropFirst()),
                    titleID: activity.titleID
                )
            }
    }
}
