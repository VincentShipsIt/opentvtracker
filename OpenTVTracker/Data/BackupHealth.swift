import Foundation

enum BackupHealthState: Equatable, Sendable {
    case neverExported
    case current(lastExportedAt: Date)
    case due(lastExportedAt: Date)

    var label: String {
        switch self {
        case .neverExported:
            "No complete backup"
        case .current:
            "Backup current"
        case .due:
            "Backup due"
        }
    }

    var systemImage: String {
        switch self {
        case .neverExported:
            "exclamationmark.triangle.fill"
        case .current:
            "checkmark.circle.fill"
        case .due:
            "clock.fill"
        }
    }

    var reminder: String {
        switch self {
        case .neverExported:
            "Export complete JSON now so your library can be restored without an account or support request."
        case .current(let lastExportedAt):
            "Last complete backup \(lastExportedAt.formatted(.relative(presentation: .named))). This screen will show it as due after 30 days."
        case .due(let lastExportedAt):
            "Last complete backup \(lastExportedAt.formatted(.relative(presentation: .named))). Export a fresh JSON copy to protect recent changes."
        }
    }
}

enum BackupHealth {
    static let lastSuccessfulExportTimestampKey = "opentv.backup.last-successful-json-export"
    static let reminderInterval: TimeInterval = 30 * 24 * 60 * 60

    static func lastSuccessfulExportAt(from timestamp: Double) -> Date? {
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    static func state(
        lastSuccessfulExportAt: Date?,
        now: Date = .now
    ) -> BackupHealthState {
        guard let lastSuccessfulExportAt else { return .neverExported }
        let elapsed = max(now.timeIntervalSince(lastSuccessfulExportAt), 0)
        if elapsed >= reminderInterval {
            return .due(lastExportedAt: lastSuccessfulExportAt)
        }
        return .current(lastExportedAt: lastSuccessfulExportAt)
    }
}
