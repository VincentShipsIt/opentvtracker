import Foundation

enum ReminderLeadTime: Int, Codable, CaseIterable, Identifiable, Sendable {
    case atRelease = 0
    case fifteenMinutes = 15
    case oneHour = 60
    case oneDay = 1_440

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .atRelease: "When it is available"
        case .fifteenMinutes: "15 minutes before"
        case .oneHour: "1 hour before"
        case .oneDay: "1 day before"
        }
    }
}

struct ReminderSettings: Codable, Hashable, Sendable {
    var isEnabled = false
    var automaticallyRemindTrackedTitles = false
    var defaultLeadTime: ReminderLeadTime = .oneHour
    var enabledTitleIDs: Set<MediaTitle.ID> = []
    var titleLeadTimes: [MediaTitle.ID: ReminderLeadTime] = [:]
    var mutedTitleIDs: Set<MediaTitle.ID> = []
    var providerAvailabilityEnabled = true

    func leadTime(for titleID: MediaTitle.ID) -> ReminderLeadTime {
        titleLeadTimes[titleID] ?? defaultLeadTime
    }

    func includes(_ titleID: MediaTitle.ID) -> Bool {
        isEnabled
            && !mutedTitleIDs.contains(titleID)
            && (automaticallyRemindTrackedTitles || enabledTitleIDs.contains(titleID))
    }
}
