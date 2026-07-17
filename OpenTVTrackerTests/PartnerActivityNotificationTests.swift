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
