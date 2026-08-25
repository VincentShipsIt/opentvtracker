import XCTest

/// Fourteen deterministic evidence cases. The dispatch workflow runs this suite
/// once on a small iPhone and once on an iPad, yielding the required 7 x 2 x 2
/// matrix without hiding device coverage inside mutable simulator preferences.
final class AccessibilityEvidenceUITests: AccessibilityEvidenceUITestCase {
    func testFirstRunAtDefaultDynamicType() {
        verifyFirstRun(mode: .standard)
    }

    func testFirstRunAtAX5() {
        verifyFirstRun(mode: .ax5)
    }

    func testTodayAtDefaultDynamicType() {
        verifyToday(mode: .standard)
    }

    func testTodayAtAX5() {
        verifyToday(mode: .ax5)
    }

    func testDiscoverSearchAtDefaultDynamicType() {
        verifyDiscoverSearch(mode: .standard)
    }

    func testDiscoverSearchAtAX5() {
        verifyDiscoverSearch(mode: .ax5)
    }

    func testSharedAtDefaultDynamicType() {
        verifyShared(mode: .standard)
    }

    func testSharedAtAX5() {
        verifyShared(mode: .ax5)
    }

    func testLibraryAtDefaultDynamicType() {
        verifyLibrary(mode: .standard)
    }

    func testLibraryAtAX5() {
        verifyLibrary(mode: .ax5)
    }

    func testMediaDetailsAtDefaultDynamicType() {
        verifyMediaDetails(mode: .standard)
    }

    func testMediaDetailsAtAX5() {
        verifyMediaDetails(mode: .ax5)
    }

    func testDiscoveryAssistantAtDefaultDynamicType() {
        verifyDiscoveryAssistant(mode: .standard)
    }

    func testDiscoveryAssistantAtAX5() {
        verifyDiscoveryAssistant(mode: .ax5)
    }

    private func verifyFirstRun(mode: AccessibilityEvidenceDynamicType) {
        launchEvidenceCase(flow: "first-run", mode: mode, seed: .firstRun)

        let continueButton = app.buttons["first-run.continue"]
        assertKeyActionIsReachableAndClear(continueButton)
        continueButton.tap()
        assertKeyActionIsReachableAndClear(continueButton)
        continueButton.tap()

        assertExists(app.staticTexts["Watch together, privately"])
        assertKeyActionIsReachableAndClear(continueButton)
    }

    private func verifyToday(mode: AccessibilityEvidenceDynamicType) {
        launchCoreJourneys(flow: "today", mode: mode)
        assertKeyActionIsReachableAndClear(
            app.buttons["today.hero-mark-watched"],
            scrollContainer: app.scrollViews["today.scroll"]
        )
    }

    private func verifyDiscoverSearch(mode: AccessibilityEvidenceDynamicType) {
        launchCoreJourneys(flow: "discover-search", mode: mode)
        selectRootTab(named: "Discover")

        let searchField = app.searchFields.firstMatch
        assertExists(searchField)
        searchField.tap()
        searchField.typeText("Test Show")

        let keyboardSubmit = app.keyboards.buttons.matching(
            NSPredicate(format: "label IN %@", ["Search", "search", "Return", "return"])
        ).firstMatch
        if keyboardSubmit.waitForExistence(timeout: 2) {
            keyboardSubmit.tap()
        }

        let markWatched = app.buttons["discover.search-result.ui-test-show.mark-watched"]
        assertKeyActionIsReachableAndClear(markWatched)
    }

    private func verifyShared(mode: AccessibilityEvidenceDynamicType) {
        launchCoreJourneys(flow: "shared", mode: mode)
        let spaceToggle = app.buttons["space-mode-toggle"]
        assertExists(spaceToggle)
        spaceToggle.tap()

        assertExists(app.staticTexts["Test couch"])
        assertKeyActionIsReachableAndClear(
            app.buttons["together.manage-sharing"],
            maximumScrolls: 32,
            scrollContainer: app.scrollViews["together.scroll"]
        )
    }

    private func verifyLibrary(mode: AccessibilityEvidenceDynamicType) {
        launchCoreJourneys(flow: "library", mode: mode)
        selectRootTab(named: "Library")
        assertExists(app.descendants(matching: .any)["library.root"])

        let pausedShelf = app.buttons["library.shelf.paused"]
        let shelfScroller = app.scrollViews["library.root"]
        for _ in 0..<4 {
            let frame = pausedShelf.frame
            if pausedShelf.exists,
               frame.minX >= app.frame.minX,
               frame.maxX <= app.frame.maxX {
                break
            }
            if frame.minX < app.frame.minX {
                shelfScroller.swipeRight()
            } else {
                shelfScroller.swipeLeft()
            }
        }
        assertKeyActionIsReachableAndClear(pausedShelf)
    }

    private func verifyMediaDetails(mode: AccessibilityEvidenceDynamicType) {
        launchCoreJourneys(flow: "media-details", mode: mode)
        let title = app.buttons["home.up-next-title"]
        assertExists(title)
        for _ in 0..<4 where !title.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(title.isHittable, "Expected seeded media title to open details")
        title.tap()

        assertExists(app.navigationBars["Test Show"])
        assertKeyActionIsReachableAndClear(app.buttons["details.primary-action"])
    }

    private func verifyDiscoveryAssistant(mode: AccessibilityEvidenceDynamicType) {
        launchCoreJourneys(flow: "discovery-assistant", mode: mode)
        selectRootTab(named: "Discover")

        let askOpenTV = app.buttons["discover.ask-opentv"]
        assertExists(askOpenTV)
        askOpenTV.tap()
        assertExists(app.navigationBars["Ask OpenTV"])
        let assistantScroll = app.scrollViews["assistant.results-scroll"]
        assertExists(assistantScroll)

        if app.frame.width < 600 {
            submitAssistantRequestOnPhone(in: assistantScroll)
        } else {
            submitAssistantRequestOnIPad(in: assistantScroll)
        }

        let responseSummary = app.descendants(matching: .any)["assistant.response-summary"]
        assertEvidenceIsVisibleAndClear(responseSummary)
        XCTAssertTrue(
            responseSummary.label.contains("picks available")
                || responseSummary.label.hasPrefix("No exact match is available"),
            "Expected the submitted assistant response summary to describe the result"
        )
    }

    private func submitAssistantRequestOnPhone(in assistantScroll: XCUIElement) {
        let prompt = app.textFields["What should we watch?"]
        assertExists(prompt)
        prompt.tap()
        prompt.typeText("A funny show under 60 minutes")

        let findPicks = app.buttons["assistant.find-picks"]
        assertKeyActionIsReachableAndClear(findPicks, scrollContainer: assistantScroll)
        XCTAssertGreaterThanOrEqual(
            findPicks.frame.width,
            44,
            "Expected Find picks to preserve a 44-point minimum width"
        )
        XCTAssertGreaterThanOrEqual(
            findPicks.frame.height,
            44,
            "Expected Find picks to preserve a 44-point minimum height"
        )
        findPicks.tap()
    }

    private func submitAssistantRequestOnIPad(in assistantScroll: XCUIElement) {
        // iPad uses a production suggestion that wraps to one shelf page at
        // AX5. It runs the same real submission path as the composer.
        let suggestionScroller = app.scrollViews["assistant.suggestions"]
        assertKeyActionIsReachableAndClear(
            suggestionScroller,
            scrollContainer: assistantScroll
        )
        let suggestion = app.buttons["assistant.suggestion.A tense sci-fi series"]
        for _ in 0..<12 where !suggestion.exists {
            dragHorizontally(in: suggestionScroller, normalizedDelta: -0.3)
        }
        assertExists(suggestion)
        center(suggestion, in: suggestionScroller)
        assertKeyActionIsReachableAndClear(
            suggestion,
            maximumScrolls: 0,
            scrollContainer: suggestionScroller
        )
        suggestion.tap()
    }

    private func center(_ element: XCUIElement, in scrollView: XCUIElement) {
        for _ in 0..<12 {
            let frame = element.frame
            let viewport = scrollView.frame
            if frame.minX >= viewport.minX,
               frame.maxX <= viewport.maxX {
                break
            }
            let targetMinX = viewport.minX + (viewport.width - frame.width) / 2
            let normalizedDelta = max(
                -0.35,
                min(0.35, (targetMinX - frame.minX) / viewport.width)
            )
            dragHorizontally(in: scrollView, normalizedDelta: normalizedDelta)
        }
    }

    private func dragHorizontally(
        in scrollView: XCUIElement,
        normalizedDelta: CGFloat
    ) {
        let startX = 0.5
        let endX = 0.5 + normalizedDelta
        scrollView.coordinate(
            withNormalizedOffset: CGVector(dx: startX, dy: 0.5)
        ).press(
            forDuration: 0.1,
            thenDragTo: scrollView.coordinate(
                withNormalizedOffset: CGVector(dx: endX, dy: 0.5)
            ),
            withVelocity: .slow,
            thenHoldForDuration: 0.1
        )
    }

    private func launchCoreJourneys(
        flow: String,
        mode: AccessibilityEvidenceDynamicType
    ) {
        launchEvidenceCase(flow: flow, mode: mode, seed: .coreJourneys)
        assertExists(app.buttons["home.up-next-title"])
    }
}
