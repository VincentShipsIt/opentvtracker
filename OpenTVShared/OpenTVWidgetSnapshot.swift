import Foundation

struct OpenTVWidgetItem: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let date: Date?
    let symbol: String
}

struct OpenTVWidgetSnapshot: Codable, Hashable, Sendable {
    let generatedAt: Date
    let upNext: OpenTVWidgetItem?
    let upcoming: [OpenTVWidgetItem]

    static var empty: OpenTVWidgetSnapshot {
        OpenTVWidgetSnapshot(
            generatedAt: .now,
            upNext: nil,
            upcoming: []
        )
    }
}

enum OpenTVWidgetSnapshotStore {
    static let appGroupIdentifier = "group.dev.opentvtracker.app"
    private static let snapshotKey = "OpenTVWidgetSnapshot.v1"

    static func save(_ snapshot: OpenTVWidgetSnapshot) throws {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            throw OpenTVWidgetSnapshotStoreError.appGroupUnavailable
        }
        defaults.set(try JSONEncoder().encode(snapshot), forKey: snapshotKey)
    }

    static func load() -> OpenTVWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(OpenTVWidgetSnapshot.self, from: data)
    }
}

enum OpenTVWidgetSnapshotStoreError: Error {
    case appGroupUnavailable
}
