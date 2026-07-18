import XCTest
@testable import OpenTVTracker

final class PartnerActivityNotificationTests: XCTestCase {
    func testPlansNotificationForRecentPartnerWatchedTogetherActivity() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let space = Self.space(
            activities: [
                Self.activity(
                    id: "partner-watch",
                    memberID: "partner",
                    kind: .watchedTogether,
                    occurredAt: now.addingTimeInterval(-30)
                )
            ]
        )

        let notification = try XCTUnwrap(PartnerActivityNotificationPlanner.notifications(
            for: space.activity,
            in: space,
            excluding: [],
            now: now
        ).first)

        XCTAssertEqual(notification.id, "partner-watch")
        XCTAssertEqual(notification.memberName, "Partner")
        XCTAssertEqual(notification.activityDescription, "Watched Severance S1 E1 together")
        XCTAssertEqual(notification.titleID, "severance")
    }

    func testIgnoresOwnPersonalSeenAndStaleActivity() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let activities = [
            Self.activity(
                id: "own-watch",
                memberID: "you",
                kind: .watchedTogether,
                occurredAt: now
            ),
            Self.activity(
                id: "personal-watch",
                memberID: "partner",
                kind: .general,
                occurredAt: now
            ),
            Self.activity(
                id: "seen-watch",
                memberID: "partner",
                kind: .watchedTogether,
                occurredAt: now
            ),
            Self.activity(
                id: "stale-watch",
                memberID: "partner",
                kind: .watchedTogether,
                occurredAt: now.addingTimeInterval(-(25 * 60 * 60))
            )
        ]
        let space = Self.space(activities: activities)

        let notifications = PartnerActivityNotificationPlanner.notifications(
            for: activities,
            in: space,
            excluding: ["seen-watch"],
            now: now
        )

        XCTAssertTrue(notifications.isEmpty)
    }

    func testLegacyActivityDecodesWithoutNotificationMetadata() throws {
        let data = Data(
            """
            {
              "id": "legacy",
              "memberID": "partner",
              "description": "watched Severance",
              "relativeDate": "Yesterday",
              "symbol": "checkmark",
              "titleID": "severance"
            }
            """.utf8
        )

        let activity = try JSONDecoder().decode(SharedActivity.self, from: data)

        XCTAssertNil(activity.kind)
        XCTAssertNil(activity.occurredAt)
    }

    func testUnauthorizedDeliveryDoesNotConsumeActivity() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let center = PartnerNotificationCenterSpy(authorization: .denied)
        let suiteName = "partner-notifications-unauthorized-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = PartnerActivityNotificationService(
            notificationCenter: center,
            defaults: defaults,
            now: { now }
        )
        let activity = Self.activity(
            id: "deliver-after-authorization",
            memberID: "partner",
            kind: .watchedTogether,
            occurredAt: now
        )
        let space = Self.space(activities: [activity])

        await service.notify(about: [activity], in: space)
        await center.setAuthorization(.authorized)
        await service.notify(about: [activity], in: space)

        let requests = await center.successfulRequests()
        XCTAssertEqual(requests.map(\.identifier), ["partner-activity-deliver-after-authorization"])
    }

    func testDeliveredActivityIsNotRepeatedWhenFullRemoteHistoryIsReconciled() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let center = PartnerNotificationCenterSpy(authorization: .authorized)
        let suiteName = "partner-notifications-repeat-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = PartnerActivityNotificationService(
            notificationCenter: center,
            defaults: defaults,
            now: { now }
        )
        let activity = Self.activity(
            id: "deliver-once",
            memberID: "partner",
            kind: .watchedTogether,
            occurredAt: now
        )
        let space = Self.space(activities: [activity])

        await service.notify(about: space.activity, in: space)
        await service.notify(about: space.activity, in: space)

        let requests = await center.successfulRequests()
        XCTAssertEqual(requests.map(\.identifier), ["partner-activity-deliver-once"])
    }

    func testFailedDeliveryDoesNotConsumeActivity() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let center = PartnerNotificationCenterSpy(authorization: .authorized, shouldFail: true)
        let suiteName = "partner-notifications-failure-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = PartnerActivityNotificationService(
            notificationCenter: center,
            defaults: defaults,
            now: { now }
        )
        let activity = Self.activity(
            id: "retry-after-failure",
            memberID: "partner",
            kind: .watchedTogether,
            occurredAt: now
        )
        let space = Self.space(activities: [activity])

        await service.notify(about: [activity], in: space)
        await center.setShouldFail(false)
        await service.notify(about: [activity], in: space)

        let requests = await center.successfulRequests()
        XCTAssertEqual(requests.map(\.identifier), ["partner-activity-retry-after-failure"])
    }

    func testPlannerKeepsThreeNewestAndRejectsFutureClockSkew() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let activities = (1...5).map { index in
            Self.activity(
                id: "activity-\(index)",
                memberID: "partner",
                kind: .watchedTogether,
                occurredAt: now.addingTimeInterval(Double(index))
            )
        } + [
            Self.activity(
                id: "future",
                memberID: "partner",
                kind: .watchedTogether,
                occurredAt: now.addingTimeInterval(301)
            )
        ]

        let notifications = PartnerActivityNotificationPlanner.notifications(
            for: activities,
            in: Self.space(activities: activities),
            excluding: [],
            now: now
        )

        XCTAssertEqual(notifications.map(\.id), ["activity-3", "activity-4", "activity-5"])
    }

    func testSeenStateEvictsOldestInsertion() {
        let existing = (0..<500).map { "activity-\($0)" }

        let retained = PartnerActivitySeenState.appending(["newest"], to: existing)

        XCTAssertEqual(retained.count, 500)
        XCTAssertEqual(retained.first, "activity-1")
        XCTAssertEqual(retained.last, "newest")
    }

    func testSelfReferentialRemoteNameFallsBackToPartnerCopy() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let activity = Self.activity(
            id: "owner-watch",
            memberID: "local-user",
            kind: .watchedTogether,
            occurredAt: now
        )
        let space = SharedSpace(
            id: "space",
            name: "Our space",
            members: [
                SpaceMember(id: "local-user", name: "You", initials: "YOU", isCurrentUser: false),
                SpaceMember(id: "partner", name: "Partner", initials: "P", isCurrentUser: true)
            ],
            titleIDs: ["severance"],
            activity: [activity],
            isCloudSharingEnabled: true,
            membershipState: .accepted
        )

        let notification = try XCTUnwrap(PartnerActivityNotificationPlanner.notifications(
            for: [activity],
            in: space,
            excluding: [],
            now: now
        ).first)

        XCTAssertEqual(notification.memberName, "Your partner")
    }

    private static func space(activities: [SharedActivity]) -> SharedSpace {
        SharedSpace(
            id: "space",
            name: "Our space",
            members: [
                SpaceMember(id: "you", name: "You", initials: "YOU", isCurrentUser: true),
                SpaceMember(id: "partner", name: "Partner", initials: "P", isCurrentUser: false)
            ],
            titleIDs: ["severance"],
            activity: activities,
            isCloudSharingEnabled: true,
            membershipState: .accepted
        )
    }

    private static func activity(
        id: String,
        memberID: String,
        kind: SharedActivityKind,
        occurredAt: Date
    ) -> SharedActivity {
        SharedActivity(
            id: id,
            memberID: memberID,
            description: "watched Severance S1 E1 together",
            relativeDate: "Now",
            symbol: "checkmark",
            titleID: "severance",
            kind: kind,
            occurredAt: occurredAt
        )
    }
}

@MainActor
final class PartnerActivityNotifierInjectionTests: XCTestCase {
    func testSeededModelUsesNoopPartnerNotifierByDefault() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)

        XCTAssertTrue(model.partnerActivityNotifier is NoopPartnerActivityNotifier)
    }
}

private actor PartnerNotificationCenterSpy: PartnerNotificationCenterProviding {
    private var currentAuthorization: ReminderAuthorization
    private var shouldFail: Bool
    private var deliveredRequests: [PartnerActivityNotificationRequest] = []

    init(
        authorization: ReminderAuthorization,
        shouldFail: Bool = false
    ) {
        currentAuthorization = authorization
        self.shouldFail = shouldFail
    }

    func authorization() async -> ReminderAuthorization {
        currentAuthorization
    }

    func requestAuthorization() async {
        currentAuthorization = .authorized
    }

    func add(_ request: PartnerActivityNotificationRequest) async throws {
        if shouldFail {
            throw PartnerNotificationCenterSpyError.deliveryFailed
        }
        deliveredRequests.append(request)
    }

    func setAuthorization(_ authorization: ReminderAuthorization) {
        currentAuthorization = authorization
    }

    func setShouldFail(_ shouldFail: Bool) {
        self.shouldFail = shouldFail
    }

    func successfulRequests() -> [PartnerActivityNotificationRequest] {
        deliveredRequests
    }
}

private enum PartnerNotificationCenterSpyError: Error {
    case deliveryFailed
}
