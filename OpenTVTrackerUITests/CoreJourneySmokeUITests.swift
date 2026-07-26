import XCTest

final class CoreJourneySmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDownWithError() throws {
        if testRun?.hasSucceeded == false, let app {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "failure-screenshot"
            screenshot.lifetime = .keepAlways
            add(screenshot)

            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "failure-ui-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app = nil
    }

    func testFirstRunCompletesIntoPopulatedToday() {
        launch(with: "-ui-testing-first-run")

        assertExists(app.staticTexts["Choose your services"])
        tapContinue()
        assertExists(app.staticTexts["Seed your Today screen"])
        tapContinue()
        assertExists(app.staticTexts["Watch together, privately"])
        tapContinue()

        assertExists(app.buttons["home.up-next-title"])
        assertExists(app.staticTexts["Test Show"])
    }

    func testSearchOpensDetailsAndInAppTrailerFallback() {
        launchCoreJourneys()
        app.tabBars.buttons["Discover"].tap()

        let searchField = app.searchFields.firstMatch
        assertExists(searchField)
        searchField.tap()
        searchField.typeText("Test Show")

        let result = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Test Show")
        ).firstMatch
        assertExists(result)
        result.tap()

        let trailer = app.buttons["Watch trailer"]
        if !trailer.waitForExistence(timeout: 1) {
            let redesignedTrailer = app.buttons["Trailer"]
            scrollToElement(redesignedTrailer)
            redesignedTrailer.tap()
        } else {
            scrollToElement(trailer)
            trailer.tap()
        }

        assertExists(app.navigationBars["Test Show trailer"])
        assertExists(app.staticTexts["Trailer could not play"])
        assertExists(app.descendants(matching: .any)["Open trailer on YouTube"])
    }

    func testEpisodeTrackingAppearsInPrivateDiary() {
        launchCoreJourneys()
        openFirstEpisode()

        let markWatched = app.buttons["episode.mark-watched"]
        assertExists(markWatched)
        markWatched.tap()
        assertExists(app.buttons["Mark episode unwatched"])

        app.tabBars.buttons["Library"].tap()
        openViewingDiary()

        let diaryEntry = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "diary.entry.")
        ).firstMatch
        assertExists(diaryEntry)
        XCTAssertTrue(
            diaryEntry.label.contains("Test Show")
                && diaryEntry.label.contains("S1 E1")
                && diaryEntry.label.contains("Episode 1")
        )
    }

    func testPrivatePartnerJourneyOpensEpisodeConversation() {
        launchCoreJourneys()
        XCTAssertFalse(app.tabBars.buttons["Together"].exists)
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        swipeToSharedSpace()

        assertExists(app.staticTexts["Test couch"])
        app.tabBars.buttons["Library"].tap()
        assertExists(app.buttons["together.viewing-analytics"])
        app.tabBars.buttons["Today"].tap()

        let manageSharing = app.buttons["together.manage-sharing"]
        assertExists(manageSharing)
        manageSharing.tap()
        assertExists(app.navigationBars["Connect partner"])
        assertExists(app.staticTexts["Invitation-only iCloud share"])
        app.buttons["Done"].tap()

        let sharedTitle = app.buttons["together.shared-title.ui-test-show"]
        assertExists(sharedTitle)
        sharedTitle.tap()
        openFirstEpisodeFromDetails()

        let markTogether = app.buttons["Mark watched together"]
        scrollToElement(markTogether)
        assertExists(app.staticTexts["Private episode thread"])
        assertExists(markTogether)
        markTogether.tap()
        assertExists(app.textFields["Add a private note"])
    }

    /// Guards the return leg specifically. Only the outbound swipe was covered, so a
    /// regression that anchored the return gesture where a finger could not physically
    /// reach it disabled the swipe entirely and still left CI green.
    func testSpaceSwipeCarriesBackToPersonal() {
        launchCoreJourneys()

        swipeToSharedSpace()
        assertExists(app.staticTexts["Test couch"])

        swipeToPersonalSpace()
        assertExists(app.buttons["home.up-next-title"])
        assertDisappears(app.staticTexts["Test couch"])
    }

    /// The case the two swipe tests above are built to avoid, and therefore the case that
    /// shipped broken: a sideways flick across a carousel swapped the whole room out. Both
    /// of them drag at `dy: 0.22` to stay clear of the shelves, so the one place the space
    /// gesture has to *lose* was the one place nothing looked.
    ///
    /// Checking that the space stayed put is only half a test. A drag that landed on nothing
    /// at all would leave the space alone too, so this also requires the shelf to have
    /// scrolled: the gesture must reach the carousel and be kept by it.
    func testDragStartingInAShelfScrollsItAndKeepsTheSpace() {
        launchCoreJourneys()

        // The carousel, not the section around it — and it is what gets scrolled into view,
        // too. The section is hittable as soon as its heading clears the fold while the
        // posters are still below it, so scrolling to the section left the gesture landing
        // offscreen. The section also holds that heading, where the space switch is entitled
        // to win, so swiping the section would measure the wrong gesture either way.
        let shelf = app.descendants(matching: .any)["today.start-watching"]
        let carousel = shelf.scrollViews.firstMatch
        assertExists(carousel)
        scrollToElement(carousel)

        let firstPoster = carousel.buttons.firstMatch
        assertExists(firstPoster)
        let restingX = firstPoster.frame.minX

        // A full swipe across the carousel, so this travels far past the space switch's own
        // `max(80, width * 0.2)` threshold. It is not passing because the drag was too small
        // to commit — it is passing because the shelf claimed it.
        carousel.swipeLeft()

        assertNeverAppears(app.staticTexts["Test couch"])
        XCTAssertLessThan(
            firstPoster.frame.minX,
            restingX - 40,
            "Expected the drag to scroll the shelf it started on"
        )
    }

    private func launchCoreJourneys() {
        launch(with: "-ui-testing-core-journeys")
        assertExists(app.buttons["home.up-next-title"])
    }

    private func launch(with argument: String) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [argument]
        app.launch()
    }

    private func tapContinue() {
        let button = app.buttons["first-run.continue"]
        assertExists(button)
        button.tap()
    }

    /// The space switch is directional now, matching the transition edges: dragging left
    /// carries you into the shared space, dragging right carries you back. Both helpers
    /// start well inside the screen — the gesture is no longer anchored to an edge, and
    /// starting on one would hand the drag to the system's interactive pop instead.
    private func swipeToSharedSpace() {
        dragAcrossSpaces(from: 0.8, to: 0.2)
    }

    private func swipeToPersonalSpace() {
        dragAcrossSpaces(from: 0.2, to: 0.8)
    }

    private func dragAcrossSpaces(from startX: CGFloat, to endX: CGFloat) {
        // Vertically above the shelves. A drag that begins on a horizontal carousel is
        // claimed by that carousel and deliberately does not switch spaces.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.22))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: 0.22))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func openFirstEpisode() {
        app.buttons["home.up-next-title"].tap()
        openFirstEpisodeFromDetails()
    }

    private func openFirstEpisodeFromDetails() {
        let season = app.buttons["season.1"]
        scrollToElement(season)
        season.tap()

        let episode = app.buttons["episode.1"]
        assertExists(episode)
        episode.tap()
    }

    /// Library has no segmented control any more: the section switch is an inline picker
    /// inside a single toolbar menu, so reaching History is open-then-choose.
    private func openViewingDiary() {
        let sectionMenu = app.buttons["library.section-menu"]
        assertExists(sectionMenu)
        sectionMenu.tap()

        let history = app.buttons["History"]
        assertExists(history)
        history.tap()

        let diary = app.buttons["library.viewing-diary"]
        scrollToElement(diary)
        diary.tap()
    }

    private func scrollToElement(_ element: XCUIElement) {
        for _ in 0..<10 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Expected \(element) to become hittable")
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

    /// The negative counterpart to `assertExists`, and it has to poll for the same
    /// reason that one does. A removal transition keeps the outgoing view mounted —
    /// and therefore still queryable — for the length of the animation, so a bare
    /// `exists` check taken the instant the incoming view appears can still see it.
    private func assertDisappears(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone], timeout: timeout),
            .completed,
            "Expected \(element) to go away",
            file: file,
            line: line
        )
    }

    /// Distinct from `assertDisappears`: that one waits for something on screen to leave,
    /// which a never-present element satisfies instantly. This spends the timeout proving
    /// nothing arrived — the only way to assert that a gesture did *not* switch spaces.
    private func assertNeverAppears(
        _ element: XCUIElement,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            element.waitForExistence(timeout: timeout),
            "Expected \(element) never to appear",
            file: file,
            line: line
        )
    }
}
