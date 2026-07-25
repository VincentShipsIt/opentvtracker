import XCTest
@testable import OpenTVTracker

final class PartnerActivityConcurrencyTests: XCTestCase {
    func testConcurrentReconciliationDoesNotRedeliverInFlightActivity() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let center = PartnerNotificationCenterSpy(
            authorization: .authorized,
            deliveryDelay: .milliseconds(50)
        )
        let suiteName = "partner-notifications-concurrent-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PartnerActivityNotificationService(
            notificationCenter: center,
            defaults: defaults,
            now: { now }
        )
        let activity = PartnerActivityNotificationTests.activity(
            id: "deliver-once-concurrently",
            memberID: "partner",
            kind: .watchedTogether,
            occurredAt: now
        )
        let space = PartnerActivityNotificationTests.space(activities: [activity])

        async let first: Void = service.notify(about: space.activity, in: space)
        async let second: Void = service.notify(about: space.activity, in: space)
        _ = await (first, second)

        let requests = await center.successfulRequests()
        XCTAssertEqual(requests.map(\.identifier), ["partner-activity-deliver-once-concurrently"])
    }

    func testConcurrentDifferentDeliveriesPreserveBothSeenIDs() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let center = PartnerNotificationCenterSpy(
            authorization: .authorized,
            deliveryDelay: .milliseconds(50)
        )
        let suiteName = "partner-notifications-seen-merge-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let service = PartnerActivityNotificationService(
            notificationCenter: center,
            defaults: defaults,
            now: { now }
        )
        let firstActivity = PartnerActivityNotificationTests.activity(
            id: "concurrent-first",
            memberID: "partner",
            kind: .watchedTogether,
            occurredAt: now
        )
        let secondActivity = PartnerActivityNotificationTests.activity(
            id: "concurrent-second",
            memberID: "partner",
            kind: .watchedTogether,
            occurredAt: now
        )
        let space = PartnerActivityNotificationTests.space(
            activities: [firstActivity, secondActivity]
        )

        async let first: Void = service.notify(about: [firstActivity], in: space)
        async let second: Void = service.notify(about: [secondActivity], in: space)
        _ = await (first, second)
        await service.notify(about: space.activity, in: space)

        let requests = await center.successfulRequests()
        XCTAssertEqual(
            Set(requests.map(\.identifier)),
            [
                "partner-activity-concurrent-first",
                "partner-activity-concurrent-second"
            ]
        )
        XCTAssertEqual(requests.count, 2)
    }
}
