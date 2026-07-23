import XCTest
@testable import OpenTVTracker

final class MediaDetailActionsTests: XCTestCase {
    func testIncompleteStatesAdvanceProgress() {
        for state in [WatchState.planned, .watching, .paused, .dropped] {
            XCTAssertEqual(MediaDetailPrimaryAction(state: state), .advanceProgress)
        }
    }

    func testCurrentViewingCompleteStatesEditActivity() {
        for state in [WatchState.caughtUp, .completed] {
            XCTAssertEqual(MediaDetailPrimaryAction(state: state), .editActivity)
        }
    }
}
