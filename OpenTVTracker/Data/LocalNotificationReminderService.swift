import Foundation
import UIKit
import UserNotifications

struct ReminderPlan: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable {
        case episode
        case returningSeason
        case providerAvailability
    }

    let id: String
    let titleID: MediaTitle.ID
    let kind: Kind
    let title: String
    let body: String
    let fireDate: Date
}

struct ReminderNotificationRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let threadIdentifier: String
    let titleID: MediaTitle.ID
    let kind: ReminderPlan.Kind
    let fireDate: Date
}

protocol ReminderNotificationCenterProviding: Sendable {
    func authorization() async -> ReminderAuthorization
    func requestAuthorization() async -> ReminderAuthorization
    func pendingIdentifiers() async -> [String]
    func removePendingRequests(withIdentifiers identifiers: [String]) async
    func add(_ request: ReminderNotificationRequest) async throws
}

struct SystemReminderNotificationCenter: ReminderNotificationCenterProviding, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()

    func authorization() async -> ReminderAuthorization {
        ReminderAuthorization(await center.notificationSettings().authorizationStatus)
    }

    func requestAuthorization() async -> ReminderAuthorization {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return .denied }
        return await authorization()
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ request: ReminderNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.threadIdentifier = request.threadIdentifier
        content.userInfo = ["titleID": request.titleID, "kind": request.kind.rawValue]
        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: request.fireDate
        )
        components.timeZone = Calendar.current.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        ))
    }
}

enum ReminderPlanner {
    static func plans(
        titles: [MediaTitle],
        selectedProviderIDs: Set<StreamingProvider.ID>,
        settings: ReminderSettings,
        now: Date,
        limit: Int = 56
    ) -> [ReminderPlan] {
        guard settings.isEnabled else { return [] }

        return titles
            .flatMap { title in
                plans(
                    for: title,
                    selectedProviderIDs: selectedProviderIDs,
                    settings: settings,
                    now: now
                )
            }
            .sorted { lhs, rhs in
                if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
                return lhs.id < rhs.id
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func plans(
        for title: MediaTitle,
        selectedProviderIDs: Set<StreamingProvider.ID>,
        settings: ReminderSettings,
        now: Date
    ) -> [ReminderPlan] {
        guard settings.includes(title.id), title.state != .completed else { return [] }

        let leadTime = settings.leadTime(for: title.id)
        let episodePlans = episodePlans(for: title, leadTime: leadTime, now: now)
        if !episodePlans.isEmpty { return episodePlans }

        if let fallback = nextEpisodeFallback(for: title, leadTime: leadTime, now: now) {
            return [fallback]
        }
        if let providerPlan = providerAvailabilityPlan(
            for: title,
            selectedProviderIDs: selectedProviderIDs,
            settings: settings,
            now: now
        ) {
            return [providerPlan]
        }
        return []
    }

    private static func episodePlans(
        for title: MediaTitle,
        leadTime: ReminderLeadTime,
        now: Date
    ) -> [ReminderPlan] {
        guard title.kind == .series,
              title.state == .watching || title.isOnPersonalWatchlist,
              let seasons = title.seasons else {
            return []
        }

        let watchedIDs = title.watchedEpisodeIDs ?? []
        return seasons
            .filter { $0.number > 0 }
            .flatMap { season in
                season.episodes.compactMap { episode in
                    guard !watchedIDs.contains(episode.id),
                          let airDate = episode.airDate else {
                        return nil
                    }
                    let fireDate = airDate.addingTimeInterval(-Double(leadTime.rawValue * 60))
                    guard fireDate > now else { return nil }
                    let isReturningSeason = episode.number == 1 && season.number > 1
                    return ReminderPlan(
                        id: identifier(titleID: title.id, eventID: episode.id),
                        titleID: title.id,
                        kind: isReturningSeason ? .returningSeason : .episode,
                        title: isReturningSeason ? "\(title.title) is returning" : "\(title.title) has a new episode",
                        body: isReturningSeason
                            ? "A new season is available. OpenTV keeps episode details hidden."
                            : "A new episode is available. OpenTV keeps its title and story hidden.",
                        fireDate: fireDate
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
                return lhs.id < rhs.id
            }
            .prefix(3)
            .map { $0 }
    }

    private static func nextEpisodeFallback(
        for title: MediaTitle,
        leadTime: ReminderLeadTime,
        now: Date
    ) -> ReminderPlan? {
        guard title.kind == .series,
              title.state == .watching || title.isOnPersonalWatchlist,
              let airDate = title.nextEpisodeAirDate else {
            return nil
        }
        let fireDate = airDate.addingTimeInterval(-Double(leadTime.rawValue * 60))
        guard fireDate > now else { return nil }
        return ReminderPlan(
            id: identifier(titleID: title.id, eventID: "next-episode"),
            titleID: title.id,
            kind: .episode,
            title: "\(title.title) has something new",
            body: "A new episode is available. OpenTV keeps its title and story hidden.",
            fireDate: fireDate
        )
    }

    private static func providerAvailabilityPlan(
        for title: MediaTitle,
        selectedProviderIDs: Set<StreamingProvider.ID>,
        settings: ReminderSettings,
        now: Date
    ) -> ReminderPlan? {
        guard settings.providerAvailabilityEnabled,
              title.kind == .movie,
              title.isOnPersonalWatchlist,
              !selectedProviderIDs.isDisjoint(with: Set(title.providers.map(\.id))),
              let releaseDate = title.releaseDate else {
            return nil
        }
        let fireDate = releaseDate
        guard fireDate > now else { return nil }
        return ReminderPlan(
            id: identifier(titleID: title.id, eventID: "provider-availability"),
            titleID: title.id,
            kind: .providerAvailability,
            title: "\(title.title) may now be available",
            body: "Check the streaming services selected in OpenTV.",
            fireDate: fireDate
        )
    }

    private static func identifier(titleID: String, eventID: String) -> String {
        "opentv.reminder.\(titleID)|\(eventID)"
    }
}

actor LocalNotificationReminderService: ReminderScheduling {
    private let notificationCenter: any ReminderNotificationCenterProviding

    init(
        notificationCenter: any ReminderNotificationCenterProviding = SystemReminderNotificationCenter()
    ) {
        self.notificationCenter = notificationCenter
    }

    func requestAuthorization() async -> ReminderAuthorization {
        let current = await notificationCenter.authorization()
        guard current == .notDetermined else { return current }
        return await notificationCenter.requestAuthorization()
    }

    func capability() async -> ReminderCapability {
        let authorization = await notificationCenter.authorization()
        let backgroundRefreshAvailable = await MainActor.run {
            UIApplication.shared.backgroundRefreshStatus == .available
        }
        return ReminderCapability(
            authorization: authorization,
            backgroundRefreshAvailable: backgroundRefreshAvailable
        )
    }

    func reconcile(
        titles: [MediaTitle],
        selectedProviderIDs: Set<StreamingProvider.ID>,
        settings: ReminderSettings,
        now: Date
    ) async throws {
        let reminderIDs = await notificationCenter.pendingIdentifiers()
            .filter { $0.hasPrefix("opentv.reminder.") }
        await notificationCenter.removePendingRequests(withIdentifiers: reminderIDs)

        let authorization = await notificationCenter.authorization()
        guard settings.isEnabled, authorization.allowsScheduling else { return }

        var failureCount = 0
        for plan in ReminderPlanner.plans(
            titles: titles,
            selectedProviderIDs: selectedProviderIDs,
            settings: settings,
            now: now
        ) {
            do {
                try await notificationCenter.add(ReminderNotificationRequest(
                    identifier: plan.id,
                    title: plan.title,
                    body: plan.body,
                    threadIdentifier: "opentv.\(plan.titleID)",
                    titleID: plan.titleID,
                    kind: plan.kind,
                    fireDate: plan.fireDate
                ))
            } catch {
                failureCount += 1
            }
        }
        if failureCount > 0 {
            throw ReminderSchedulingError.partialFailure(failureCount)
        }
    }
}

private extension ReminderAuthorization {
    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized: self = .authorized
        case .provisional: self = .provisional
        case .ephemeral: self = .ephemeral
        @unknown default: self = .denied
        }
    }
}

enum ReminderSchedulingError: Error {
    case partialFailure(Int)
}
