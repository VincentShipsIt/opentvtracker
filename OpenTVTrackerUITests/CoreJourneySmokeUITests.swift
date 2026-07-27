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

    func testDiscoverBrowsesCatalogWithoutSearching() {
        launchCoreJourneys()
        app.tabBars.buttons["Discover"].tap()

        let heading = app.staticTexts["Browse everything"]
        scrollToElement(heading)
        let browser = app.descendants(matching: .any)["discover.catalog-browser"]
        assertExists(browser)
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
        switchToSharedSpace()

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

    /// Guards the return leg specifically. Only the outbound crossing was covered, so a
    /// regression that left the toolbar button pointing at the space it was already in
    /// stranded anyone who crossed over, and still left CI green.
    func testSpaceToggleCarriesBackToPersonal() {
        launchCoreJourneys()

        switchToSharedSpace()
        assertExists(app.staticTexts["Test couch"])

        switchToPersonalSpace()
        assertExists(app.buttons["home.up-next-title"])
        assertDisappears(app.staticTexts["Test couch"])
    }

    /// The shake that replaced the space swipe cannot be generated from XCUITest — the
    /// Simulator only offers it from its own Hardware menu — so the switch itself is
    /// exercised through the toolbar button above. What is testable here is the promise the
    /// shake makes by *not* sharing a vocabulary with anything on screen: no drag anywhere,
    /// on a shelf or across the middle of the room, may switch spaces any more.
    ///
    /// Checking that the space stayed put is only half a test. A drag that landed on nothing
    /// at all would leave the space alone too, so this also requires the shelf to have
    /// scrolled: the gesture must reach the carousel and be kept by it.
    func testNoSidewaysDragSwitchesSpaces() {
        launchCoreJourneys()

        // Across open screen, well above the shelves — where the old space swipe lived, and
        // where a leftover gesture would still be waiting.
        dragAcrossSpaces(from: 0.8, to: 0.2)
        assertNeverAppears(app.staticTexts["Test couch"])

        // The carousel, not the section around it — and it is what gets scrolled into view,
        // too. The section is hittable as soon as its heading clears the fold while the
        // posters are still below it, so scrolling to the section left the gesture landing
        // offscreen.
        let shelf = app.descendants(matching: .any)["today.start-watching"]
        let carousel = shelf.scrollViews.firstMatch
        assertExists(carousel)
        scrollToElement(carousel)

        let firstPoster = carousel.buttons.firstMatch
        assertExists(firstPoster)
        let restingX = firstPoster.frame.minX

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

    /// A shake is the switch in the hand, but XCUITest cannot generate one, so these drive
    /// the toolbar button that stands for the same action. That button is not a test-only
    /// affordance: it is what carries the switch for anyone who cannot shake the phone, and
    /// the only path VoiceOver has to it.
    private func switchToSharedSpace() {
        tapSpaceToggle()
    }

    private func switchToPersonalSpace() {
        tapSpaceToggle()
    }

    private func tapSpaceToggle() {
        let toggle = app.buttons["space-mode-toggle"]
        assertExists(toggle)
        toggle.tap()
    }

    /// A sideways drag across open screen. Nothing should answer it any more — it is kept
    /// as the negative guard for the gesture the shake replaced.
    private func dragAcrossSpaces(from startX: CGFloat, to endX: CGFloat) {
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
