import XCTest

@MainActor
final class TodayAccessibilityUITests: XCTestCase {
    private var app: XCUIApplication!

    func testTodayReflowsAndKeepsHeroActionsReachableAtAX5() {
        launchAtAX5()

        let tabBar = app.tabBars.firstMatch
        assertExists(tabBar)
        XCTAssertEqual(tabBar.buttons.count, 3)
        assertTodayViewportClearsBottomChrome(tabBar)
        assertGreetingReflows()
        assertToolbarActionsReachable()
        attachScreenshot(named: "today-ax5-initial-reflow")
        assertHeroActionsReachable(tabBar: tabBar)
        assertShelvesReflowVertically()
    }

    func testTodayPreservesHorizontalShelfAtDefaultDynamicType() {
        launchAtDefaultDynamicType()

        let shelf = app.descendants(matching: .any)["today.start-watching"]
        assertExists(shelf)
        let carousel = shelf.scrollViews.firstMatch
        assertExists(carousel)
        scrollToHittable(carousel)

        let firstPoster = carousel.buttons.firstMatch
        assertExists(firstPoster)
        XCTAssertLessThan(
            firstPoster.frame.width,
            app.frame.width * 0.6,
            "Expected the default-size shelf to retain compact horizontal poster cards"
        )
        let restingX = firstPoster.frame.minX
        carousel.swipeLeft()
        XCTAssertLessThan(
            firstPoster.frame.minX,
            restingX - 40,
            "Expected the default-size shelf to remain horizontally browsable"
        )
    }

    private func assertTodayViewportClearsBottomChrome(_ tabBar: XCUIElement) {
        let todayScrollView = app.scrollViews.firstMatch
        assertExists(todayScrollView)
        XCTAssertLessThanOrEqual(
            todayScrollView.frame.maxY,
            tabBar.frame.minY,
            "Expected Today's viewport to end above the floating bottom chrome at rest"
        )
    }

    private func assertGreetingReflows() {
        let greeting = app.staticTexts["today.greeting"]
        assertExists(greeting)
        XCTAssertTrue(
            greeting.label.hasPrefix("Good "),
            "Expected the full time-of-day greeting to remain available"
        )
        XCTAssertGreaterThan(
            greeting.frame.height,
            100,
            "Expected the AX5 greeting to wrap instead of truncating to one line"
        )
    }

    private func assertToolbarActionsReachable() {
        let todayActions = app.buttons["today.actions"]
        assertExists(todayActions)
        XCTAssertTrue(todayActions.isHittable)
        todayActions.tap()
        assertHittable(app.buttons["home.upcoming-calendar"])
        assertHittable(app.buttons["today.ask-opentv"])
        assertHittable(app.buttons["today.settings"])
        // An outside-edge tap dismisses the menu without triggering any underlying
        // Today content. The menu consumes that first tap before hit-testing the scroll view.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.25)).tap()
    }

    private func assertHeroActionsReachable(tabBar: XCUIElement) {
        let progress = app.progressIndicators["today.hero-progress"]
        assertExists(progress)
        scrollAboveBottomChrome(progress, tabBar: tabBar)

        let markNext = app.buttons["today.hero-mark-watched"]
        assertExists(markNext)
        scrollAboveBottomChrome(markNext, tabBar: tabBar)
        XCTAssertTrue(markNext.isHittable)
        attachScreenshot(named: "today-ax5-mark-next-clear")

        let queueActions = app.descendants(matching: .any)["today.queue-actions.ui-test-show"]
        assertExists(queueActions)
        scrollAboveBottomChrome(queueActions, tabBar: tabBar)
        XCTAssertTrue(queueActions.isHittable)
        attachScreenshot(named: "today-ax5-queue-actions-clear")

        queueActions.tap()
        assertHittable(app.buttons["Pin to top"])
        assertHittable(app.buttons["Snooze for one week"])
        scrollToHittable(app.buttons["Move lower"])
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.25)).tap()

        scrollAboveBottomChrome(markNext, tabBar: tabBar)
        markNext.tap()
        let advancedProgress = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "1 of 6 episodes"),
            object: progress
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [advancedProgress], timeout: 3),
            .completed,
            "Expected the reachable hero action to advance Today progress"
        )
    }

    private func assertShelvesReflowVertically() {
        let shelf = app.descendants(matching: .any)["today.start-watching"]
        scrollUntilExists(shelf)
        XCTAssertEqual(
            shelf.scrollViews.count,
            0,
            "Expected AX5 to replace the nested horizontal carousel with vertical rows"
        )

        let firstRow = app.descendants(matching: .any)["today.shelf-item.ui-test-catalog-1"]
        scrollToHittable(firstRow)
        XCTAssertGreaterThan(
            firstRow.frame.width,
            app.frame.width * 0.75,
            "Expected AX5 shelf rows to use the available device width instead of 144 points"
        )
        XCTAssertTrue(
            firstRow.label.contains("A Deliberately Long Catalog Pick for Accessibility Layout Verification"),
            "Expected the full shelf title to remain in the accessibility label"
        )
        XCTAssertFalse(firstRow.label.contains("…"), "Expected the AX5 shelf title not to truncate")
        let firstRowX = firstRow.frame.minX
        attachScreenshot(named: "today-ax5-vertical-shelf")

        let secondRow = app.descendants(matching: .any)["today.shelf-item.ui-test-catalog-2"]
        scrollUntilExists(secondRow)
        scrollToHittable(secondRow)
        XCTAssertEqual(
            secondRow.frame.minX,
            firstRowX,
            accuracy: 2,
            "Expected shelf items to align as vertical rows"
        )
    }

    private func launchAtAX5() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-core-journeys",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
    }

    private func launchAtDefaultDynamicType() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-core-journeys"]
        app.launch()
    }

    private func scrollAboveBottomChrome(_ element: XCUIElement, tabBar: XCUIElement) {
        let todayScrollView = app.scrollViews.firstMatch
        assertExists(todayScrollView)
        let unobscuredBottom = min(todayScrollView.frame.maxY, tabBar.frame.minY)

        for _ in 0..<12 {
            let elementFrame = element.frame
            if elementFrame.minY >= app.frame.minY,
               elementFrame.maxY < unobscuredBottom {
                break
            }
            nudgeScroll(
                in: todayScrollView,
                upward: elementFrame.minY >= app.frame.minY
            )
        }

        XCTAssertGreaterThanOrEqual(
            element.frame.minY,
            app.frame.minY,
            "Expected \(element) to remain on screen"
        )
        XCTAssertLessThan(
            element.frame.maxY,
            unobscuredBottom,
            "Expected \(element) to clear the floating bottom chrome"
        )
    }

    private func nudgeScroll(in scrollView: XCUIElement, upward: Bool) {
        let startY = upward ? 0.72 : 0.38
        let endY = upward ? 0.52 : 0.58
        let start = scrollView.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: startY)
        )
        let end = scrollView.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: endY)
        )
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollToHittable(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertExists(element, file: file, line: line)
        for _ in 0..<20 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(
            element.isHittable,
            "Expected \(element) to become hittable after scrolling",
            file: file,
            line: line
        )
    }

    private func scrollUntilExists(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<20 where !element.exists {
            app.swipeUp()
        }
        assertExists(element, timeout: 2, file: file, line: line)
    }

    private func assertHittable(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertExists(element, timeout: timeout, file: file, line: line)
        XCTAssertTrue(
            element.isHittable,
            "Expected \(element) to be hittable",
            file: file,
            line: line
        )
    }

    private func assertExists(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Expected \(element) to exist",
            file: file,
            line: line
        )
    }
}
