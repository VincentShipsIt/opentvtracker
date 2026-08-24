import XCTest

/// Focused small-phone regression for the Library shelf picker. The shared
/// evidence base retains a screenshot and semantic hierarchy for both cases.
final class LibraryShelfAccessibilityUITests: AccessibilityEvidenceUITestCase {
    private struct ShelfExpectation {
        let identifier: String
        let label: String
        let visibleLabel: String
    }

    private let shelves = [
        ShelfExpectation(
            identifier: "library.shelf.keepWatching",
            label: "Keep Watching, 2",
            visibleLabel: "Keep Watching"
        ),
        ShelfExpectation(
            identifier: "library.shelf.watchlist",
            label: "Watchlist, 2",
            visibleLabel: "Watchlist"
        ),
        ShelfExpectation(
            identifier: "library.shelf.paused",
            label: "Paused",
            visibleLabel: "Paused"
        ),
        ShelfExpectation(
            identifier: "library.shelf.completed",
            label: "Completed",
            visibleLabel: "Completed"
        ),
        ShelfExpectation(
            identifier: "library.shelf.caughtUp",
            label: "Caught Up",
            visibleLabel: "Caught Up"
        ),
        ShelfExpectation(
            identifier: "library.shelf.dropped",
            label: "Dropped",
            visibleLabel: "Dropped"
        )
    ]

    func testLibraryShelvesAtDefaultDynamicType() {
        verifyLibraryShelves(mode: .standard)
    }

    func testLibraryShelvesAtAX5() {
        verifyLibraryShelves(mode: .ax5)
    }

    private func verifyLibraryShelves(mode: AccessibilityEvidenceDynamicType) {
        launchEvidenceCase(
            flow: "library-shelves",
            mode: mode,
            seed: .coreJourneys
        )
        assertExists(app.buttons["home.up-next-title"])
        selectRootTab(named: "Library")

        let shelfScrollQuery = app.scrollViews.matching(
            NSPredicate(format: "label == %@", "Library shelves")
        )
        let shelfScroll = shelfScrollQuery.firstMatch
        assertExists(shelfScroll)
        XCTAssertEqual(
            shelfScroll.label,
            "Library shelves",
            "Expected the Library root scroll view to be the semantic shelf scope"
        )
        XCTAssertEqual(
            shelfScrollQuery.count,
            1,
            "Expected one exact semantic Library shelf scope"
        )

        let usesPagedNavigation = mode == .ax5
        verifyNavigation(shelves, in: shelfScroll, usesPagedNavigation: usesPagedNavigation)
        verifyNavigation(
            Array(shelves.reversed()),
            in: shelfScroll,
            usesPagedNavigation: usesPagedNavigation
        )

        if mode == .ax5 {
            assertAX5WrappingAndScrollSemantics(in: shelfScroll)
        }
    }

    private func verifyNavigation(
        _ expectations: [ShelfExpectation],
        in shelfScroll: XCUIElement,
        usesPagedNavigation: Bool
    ) {
        for expectation in expectations {
            let matches = shelfScroll.buttons.matching(identifier: expectation.identifier)
            XCTAssertEqual(
                matches.count,
                1,
                "Expected one exact button for \(expectation.identifier) inside the shelf scope"
            )
            let button = matches.firstMatch
            assertExists(button)
            center(button, in: shelfScroll, usesPagedNavigation: usesPagedNavigation)
            assertKeyActionIsReachableAndClear(
                button,
                maximumScrolls: 0,
                scrollContainer: shelfScroll
            )
            XCTAssertEqual(
                button.label,
                expectation.label,
                "Expected the complete shelf label to remain available"
            )
            XCTAssertGreaterThanOrEqual(
                button.frame.width,
                44,
                "Expected \(expectation.visibleLabel) to preserve a 44-point minimum width"
            )
            XCTAssertGreaterThanOrEqual(
                button.frame.height,
                44,
                "Expected \(expectation.visibleLabel) to preserve a 44-point minimum height"
            )

            button.tap()
            XCTAssertTrue(
                waitForSelection(of: button),
                "Expected \(expectation.visibleLabel) to become the selected shelf"
            )
        }
    }

    private func assertAX5WrappingAndScrollSemantics(in shelfScroll: XCUIElement) {
        let keepWatching = shelfScroll.buttons["library.shelf.keepWatching"]
        let watchlist = shelfScroll.buttons["library.shelf.watchlist"]
        center(keepWatching, in: shelfScroll, usesPagedNavigation: true)

        let keepWatchingText = keepWatching.staticTexts["Keep Watching"]
        let watchlistText = watchlist.staticTexts["Watchlist"]
        assertExists(keepWatchingText)
        assertExists(watchlistText)
        XCTAssertGreaterThan(
            keepWatchingText.frame.height,
            watchlistText.frame.height + 1,
            "Expected the multiword AX5 label to wrap instead of ellipsizing"
        )

        let horizontalScrollBar = shelfScroll.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Horizontal scroll bar")
        ).firstMatch
        assertExists(horizontalScrollBar)
        XCTAssertTrue(
            horizontalScrollBar.label.contains("pages"),
            "Expected semantic page evidence for VoiceOver horizontal navigation"
        )
    }

    private func center(
        _ element: XCUIElement,
        in scrollView: XCUIElement,
        usesPagedNavigation: Bool
    ) {
        for _ in 0..<16 {
            let frame = element.frame
            let viewport = scrollView.frame
            if frame.minX >= viewport.minX,
               frame.maxX <= viewport.maxX {
                break
            }

            if usesPagedNavigation, frame.minX < viewport.minX {
                scrollView.swipeRight()
            } else if usesPagedNavigation {
                scrollView.swipeLeft()
            } else {
                let targetMinX = viewport.minX + (viewport.width - frame.width) / 2
                let normalizedDelta = max(
                    -0.35,
                    min(0.35, (targetMinX - frame.minX) / viewport.width)
                )
                dragHorizontally(in: scrollView, normalizedDelta: normalizedDelta)
            }
        }
    }

    private func dragHorizontally(
        in scrollView: XCUIElement,
        normalizedDelta: CGFloat
    ) {
        scrollView.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).press(
            forDuration: 0.1,
            thenDragTo: scrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5 + normalizedDelta, dy: 0.5)
            ),
            withVelocity: .slow,
            thenHoldForDuration: 0.1
        )
    }

    private func waitForSelection(of element: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if element.isSelected { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return element.isSelected
    }
}
