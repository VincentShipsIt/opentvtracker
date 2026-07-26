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

    /// Every shelf is one tap away, in ownership order. The picker used to show four
    /// shelves and hide Caught Up and Dropped behind an ellipsis menu, so this asserted a
    /// primary/secondary split; the split is gone and the whole list is what has to hold.
    func testEveryShelfStaysReachableAndOrdered() {
        XCTAssertEqual(
            LibraryShelf.allCases,
            [.keepWatching, .watchlist, .paused, .completed, .caughtUp, .dropped]
        )
        XCTAssertEqual(
            LibraryShelf.allCases.map(\.label),
            ["Keep Watching", "Watchlist", "Paused", "Completed", "Caught Up", "Dropped"]
        )
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

    func testEmptyStatusShelvesReturnToKeepWatching() {
        for shelf in [LibraryShelf.paused, .caughtUp, .dropped] {
            XCTAssertEqual(shelf.emptyActionShelf, .keepWatching)
        }
        XCTAssertNil(LibraryShelf.watchlist.emptyActionShelf)
    }
}
