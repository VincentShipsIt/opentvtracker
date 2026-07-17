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
            leadTime: leadTime,
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
        leadTime: ReminderLeadTime,
        now: Date
    ) -> ReminderPlan? {
        guard settings.providerAvailabilityEnabled,
              title.kind == .movie,
              title.isOnPersonalWatchlist,
              !selectedProviderIDs.isDisjoint(with: Set(title.providers.map(\.id))),
              let releaseDate = title.releaseDate else {
            return nil
        }
        let fireDate = releaseDate.addingTimeInterval(-Double(leadTime.rawValue * 60))
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
    func requestAuthorization() async -> ReminderAuthorization {
        let center = UNUserNotificationCenter.current()
        let current = Self.authorization(from: await center.notificationSettings().authorizationStatus)
        guard current == .notDetermined else { return current }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return .denied }
        return Self.authorization(from: await center.notificationSettings().authorizationStatus)
    }

    func capability() async -> ReminderCapability {
        let authorization = Self.authorization(
            from: await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        )
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
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let reminderIDs = pending.map(\.identifier).filter { $0.hasPrefix("opentv.reminder.") }
        center.removePendingNotificationRequests(withIdentifiers: reminderIDs)

        let authorization = Self.authorization(from: await center.notificationSettings().authorizationStatus)
        guard settings.isEnabled, authorization.allowsScheduling else { return }

        var failureCount = 0
        for plan in ReminderPlanner.plans(
            titles: titles,
            selectedProviderIDs: selectedProviderIDs,
            settings: settings,
            now: now
        ) {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.threadIdentifier = "opentv.\(plan.titleID)"
            content.userInfo = ["titleID": plan.titleID, "kind": plan.kind.rawValue]
            var components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: plan.fireDate
            )
            components.timeZone = Calendar.current.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            do {
                try await center.add(UNNotificationRequest(
                    identifier: plan.id,
                    content: content,
                    trigger: trigger
                ))
            } catch {
                failureCount += 1
            }
        }
        if failureCount > 0 {
            throw ReminderSchedulingError.partialFailure(failureCount)
        }
    }

    private static func authorization(from status: UNAuthorizationStatus) -> ReminderAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .provisional
        case .ephemeral: .ephemeral
        @unknown default: .denied
        }
    }
}

enum ReminderSchedulingError: Error {
    case partialFailure(Int)
}
