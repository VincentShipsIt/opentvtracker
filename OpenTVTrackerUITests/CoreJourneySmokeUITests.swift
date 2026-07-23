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
        app.tabBars.buttons["Together"].tap()

        assertExists(app.staticTexts["Test couch"])
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

    private func openViewingDiary() {
        let currentProfile = app.buttons["library.profile"]
        if currentProfile.waitForExistence(timeout: 1) {
            currentProfile.tap()
            let diary = app.buttons["profile.viewing-diary"]
            scrollToElement(diary)
            diary.tap()
            return
        }

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
}
