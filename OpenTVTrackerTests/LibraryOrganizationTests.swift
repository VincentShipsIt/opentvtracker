import XCTest
@testable import OpenTVTracker

@MainActor
final class LibraryOrganizationTests: XCTestCase {
    func testCurrentMemberFallsBackToPrivateLocalIdentity() {
        var snapshot = LibrarySnapshot.sample
        snapshot.sharedSpace.members = []
        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        XCTAssertEqual(model.currentMember.id, "local-user")
        XCTAssertEqual(model.currentMember.name, "You")
        XCTAssertTrue(model.currentMember.isCurrentUser)
    }

    func testPrimaryOwnershipShelvesStayVisibleAndOrdered() {
        XCTAssertEqual(
            LibraryShelf.primary,
            [.keepWatching, .watchlist, .paused, .completed]
        )
        XCTAssertEqual(
            LibraryShelf.primary.map(\.label),
            ["Keep Watching", "Watchlist", "Paused", "Completed"]
        )
        XCTAssertEqual(LibraryShelf.secondary, [.caughtUp, .dropped])
    }

    func testLibraryIncludesTitlesOnlyInTheirSelectedShelf() throws {
        var title = try XCTUnwrap(LibrarySnapshot.sample.titles.first)

        title.state = .watching
        XCTAssertTrue(LibraryShelf.keepWatching.includes(title))
        XCTAssertFalse(LibraryShelf.completed.includes(title))

        title.state = .paused
        XCTAssertTrue(LibraryShelf.paused.includes(title))
        XCTAssertFalse(LibraryShelf.keepWatching.includes(title))

        title.state = .completed
        XCTAssertTrue(LibraryShelf.completed.includes(title))

        title.state = .caughtUp
        XCTAssertTrue(LibraryShelf.caughtUp.includes(title))

        title.state = .dropped
        XCTAssertTrue(LibraryShelf.dropped.includes(title))
    }

    func testWatchlistUsesExplicitMembershipInsteadOfTrackingState() throws {
        var title = try XCTUnwrap(LibrarySnapshot.sample.titles.first)
        title.state = .watching
        title.personalWatchlist = true
        XCTAssertTrue(LibraryShelf.watchlist.includes(title))

        title.state = .planned
        title.personalWatchlist = false
        XCTAssertFalse(LibraryShelf.watchlist.includes(title))
    }

    func testHistoryIsAFirstClassLibrarySection() {
        XCTAssertEqual(LibrarySection.allCases, [.titles, .lists, .history])
    }

    func testEmptySecondaryShelvesReturnToKeepWatching() {
        for shelf in LibraryShelf.secondary {
            XCTAssertEqual(shelf.emptyActionShelf, .keepWatching)
        }
        XCTAssertNil(LibraryShelf.watchlist.emptyActionShelf)
    }
}
