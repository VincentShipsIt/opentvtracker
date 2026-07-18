import Foundation
import UserNotifications

struct PartnerActivityNotificationRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let titleID: MediaTitle.ID?
}

protocol PartnerNotificationCenterProviding: Sendable {
    func authorization() async -> ReminderAuthorization
    func requestAuthorization() async
    func add(_ request: PartnerActivityNotificationRequest) async throws
}

struct SystemPartnerNotificationCenter: PartnerNotificationCenterProviding, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()

    func authorization() async -> ReminderAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .provisional
        case .ephemeral: .ephemeral
        @unknown default: .denied
        }
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func add(_ request: PartnerActivityNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.interruptionLevel = .active
        if let titleID = request.titleID {
            content.userInfo["titleID"] = titleID
        }
        try await center.add(UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: nil
        ))
    }
}

actor PartnerActivityNotificationService: PartnerActivityNotifying {
    private static let seenActivityIDsKey = "opentv.partner-notifications.seen-activity-ids"

    private let notificationCenter: any PartnerNotificationCenterProviding
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private var inFlightActivityIDs: Set<SharedActivity.ID> = []

    init(
        notificationCenter: any PartnerNotificationCenterProviding = SystemPartnerNotificationCenter(),
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.notificationCenter = notificationCenter
        self.defaults = defaults
        self.now = now
    }

    func requestAuthorization() async {
        guard await notificationCenter.authorization() == .notDetermined else { return }
        await notificationCenter.requestAuthorization()
    }

    func notify(
        about activities: [SharedActivity],
        in space: SharedSpace
    ) async {
        guard !activities.isEmpty else { return }

        let seenActivityIDs = defaults.stringArray(forKey: Self.seenActivityIDsKey) ?? []
        let notifications = PartnerActivityNotificationPlanner.notifications(
            for: activities,
            in: space,
            excluding: Set(seenActivityIDs).union(inFlightActivityIDs),
            now: now()
        )
        guard !notifications.isEmpty else { return }

        let plannedActivityIDs = Set(notifications.map(\.id))
        inFlightActivityIDs.formUnion(plannedActivityIDs)
        defer { inFlightActivityIDs.subtract(plannedActivityIDs) }
        guard (await notificationCenter.authorization()).allowsScheduling else { return }

        var deliveredActivityIDs: [SharedActivity.ID] = []
        for notification in notifications {
            do {
                try await notificationCenter.add(PartnerActivityNotificationRequest(
                    identifier: "partner-activity-\(notification.id)",
                    title: "\(notification.memberName) watched with you",
                    body: notification.activityDescription,
                    titleID: notification.titleID
                ))
                deliveredActivityIDs.append(notification.id)
            } catch {
                continue
            }
        }
        if !deliveredActivityIDs.isEmpty {
            defaults.set(
                PartnerActivitySeenState.appending(
                    deliveredActivityIDs,
                    to: seenActivityIDs
                ),
                forKey: Self.seenActivityIDsKey
            )
        }
    }
}

enum PartnerActivitySeenState {
    static func appending(
        _ newIDs: [SharedActivity.ID],
        to existingIDs: [SharedActivity.ID],
        limit: Int = 500
    ) -> [SharedActivity.ID] {
        let newIDSet = Set(newIDs)
        return Array((existingIDs.filter { !newIDSet.contains($0) } + newIDs).suffix(limit))
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
                let member = membersByID[activity.memberID]
                let memberName = member?.id == "local-user"
                    || member?.name.localizedCaseInsensitiveCompare("You") == .orderedSame
                    ? "Your partner"
                    : member?.name ?? "Your partner"
                return PartnerActivityNotification(
                    id: activity.id,
                    memberName: memberName,
                    activityDescription: activity.description.prefix(1).uppercased()
                        + String(activity.description.dropFirst()),
                    titleID: activity.titleID
                )
            }
    }
}
