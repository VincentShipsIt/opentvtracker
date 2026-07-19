import Foundation
import WidgetKit

extension AppModel {
    func setRemindersEnabled(_ enabled: Bool) async {
        if enabled {
            let authorization = await reminderScheduler.requestAuthorization()
            reminderCapability = await reminderScheduler.capability()
            guard authorization.allowsScheduling else {
                reminderSettings.isEnabled = false
                reminderError = "Notifications are off for OpenTV. Enable them in System Settings to use reminders."
                return
            }
        }

        reminderSettings.isEnabled = enabled
        reminderError = nil
        persist()
        if !enabled {
            refreshRemindersSoon()
        }
    }

    func enableReminder(for titleID: MediaTitle.ID, leadTime: ReminderLeadTime) async {
        let currentCapability = await reminderScheduler.capability()
        if !currentCapability.authorization.allowsScheduling {
            let authorization = await reminderScheduler.requestAuthorization()
            reminderCapability = await reminderScheduler.capability()
            guard authorization.allowsScheduling else {
                reminderError = "Notifications are off for OpenTV. Enable them in System Settings to use reminders."
                return
            }
        }

        reminderSettings.isEnabled = true
        reminderSettings.enabledTitleIDs.insert(titleID)
        reminderSettings.mutedTitleIDs.remove(titleID)
        reminderSettings.titleLeadTimes[titleID] = leadTime
        reminderError = nil
        persist()
    }

    func disableReminder(for titleID: MediaTitle.ID) {
        reminderSettings.enabledTitleIDs.remove(titleID)
        reminderSettings.mutedTitleIDs.insert(titleID)
        if !reminderSettings.automaticallyRemindTrackedTitles,
           reminderSettings.enabledTitleIDs.isEmpty {
            reminderSettings.isEnabled = false
        }
        persist()
        if !reminderSettings.isEnabled {
            refreshRemindersSoon()
        }
    }

    func setAutomaticTrackedTitleRemindersEnabled(_ enabled: Bool) async {
        if enabled {
            let authorization = await reminderScheduler.requestAuthorization()
            reminderCapability = await reminderScheduler.capability()
            guard authorization.allowsScheduling else {
                reminderError = "Notifications are off for OpenTV. Enable them in System Settings to use reminders."
                return
            }
            reminderSettings.isEnabled = true
        }
        reminderSettings.automaticallyRemindTrackedTitles = enabled
        if !enabled, reminderSettings.enabledTitleIDs.isEmpty {
            reminderSettings.isEnabled = false
        }
        reminderError = nil
        persist()
        if !reminderSettings.isEnabled {
            refreshRemindersSoon()
        }
    }

    func setDefaultReminderLeadTime(_ leadTime: ReminderLeadTime) {
        reminderSettings.defaultLeadTime = leadTime
        persist()
    }

    func setProviderAvailabilityRemindersEnabled(_ enabled: Bool) {
        reminderSettings.providerAvailabilityEnabled = enabled
        persist()
    }

    func isReminderEnabled(for titleID: MediaTitle.ID) -> Bool {
        reminderSettings.includes(titleID)
    }

    func reminderLeadTime(for titleID: MediaTitle.ID) -> ReminderLeadTime {
        reminderSettings.leadTime(for: titleID)
    }

    func refreshReminderCapability() async {
        reminderCapability = await reminderScheduler.capability()
    }

    func refreshReminders() async {
        do {
            try await reminderScheduler.reconcile(
                titles: titles,
                selectedProviderIDs: selectedProviderIDs,
                settings: reminderSettings,
                now: .now
            )
            reminderError = nil
        } catch {
            reminderError = "OpenTV could not refresh reminders. It will try again when the app becomes active."
        }
    }

    func refreshRemindersSoon() {
        reminderTask?.cancel()
        reminderTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                await refreshReminders()
            } catch is CancellationError {
                return
            } catch {
                reminderError = "OpenTV could not refresh reminders. It will try again when the app becomes active."
            }
        }
    }

    func publishWidgetSnapshot() {
        let snapshot = WidgetSnapshotFactory.make(upNext: upNext, titles: titles, now: .now)
        do {
            if let existing = OpenTVWidgetSnapshotStore.load(),
               existing.hasSameContent(as: snapshot) {
                return
            }
            try OpenTVWidgetSnapshotStore.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Widgets are supplemental. The app remains fully functional without the shared container.
        }
    }
}

enum WidgetSnapshotFactory {
    static func make(
        upNext: [MediaTitle],
        titles: [MediaTitle],
        now: Date
    ) -> OpenTVWidgetSnapshot {
        let nextItem = upNext.first.map { title in
            OpenTVWidgetItem(
                id: title.id,
                title: title.title,
                detail: title.progressLabel,
                date: title.nextEpisodeAirDate ?? title.releaseDate,
                symbol: title.kind.symbol
            )
        }
        let upcoming = titles
            .compactMap { upcomingItem(for: $0, now: now) }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return (lhs.date ?? .distantFuture) < (rhs.date ?? .distantFuture) }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            .prefix(12)
            .map { $0 }
        return OpenTVWidgetSnapshot(generatedAt: now, upNext: nextItem, upcoming: upcoming)
    }

    private static func upcomingItem(for title: MediaTitle, now: Date) -> OpenTVWidgetItem? {
        guard title.isReminderEligible else { return nil }

        if title.kind == .series,
           let date = nextUnwatchedEpisodeDate(for: title, now: now) ?? title.nextEpisodeAirDate,
           date > now {
            return OpenTVWidgetItem(
                id: "\(title.id).episode",
                title: title.title,
                detail: "New episode",
                date: date,
                symbol: "calendar.badge.clock"
            )
        }

        if title.kind == .movie,
           let date = title.releaseDate,
           date > now {
            return OpenTVWidgetItem(
                id: "\(title.id).release",
                title: title.title,
                detail: "Upcoming release",
                date: date,
                symbol: "film"
            )
        }
        return nil
    }

    private static func nextUnwatchedEpisodeDate(for title: MediaTitle, now: Date) -> Date? {
        let watchedIDs = title.watchedEpisodeIDs ?? []
        return title.seasons?
            .filter { $0.number > 0 }
            .flatMap(\.episodes)
            .filter { !watchedIDs.contains($0.id) && ($0.airDate ?? .distantPast) > now }
            .compactMap(\.airDate)
            .min()
    }
}
