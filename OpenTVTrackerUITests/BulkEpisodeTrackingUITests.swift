import XCTest

final class BulkEpisodeTrackingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-bulk-watch"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Test Show"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testMarkFullSeasonWatchedAfterConfirmation() {
        openSeason()

        let markAll = app.buttons["season.mark-all-watched"]
        XCTAssertTrue(markAll.waitForExistence(timeout: 3))
        markAll.tap()

        let confirm = app.buttons["Mark season watched"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        confirm.tap()

        XCTAssertTrue(app.staticTexts["6 watched"].waitForExistence(timeout: 2))
        attachScreenshot(named: "season-watched")
    }

    func testEpisodeSixOffersAndAppliesPreviousEpisodes() {
        openSeason()

        let episodeSix = app.buttons["episode.6"]
        scrollToElement(episodeSix)
        episodeSix.tap()

        let markWatched = app.buttons["episode.mark-watched"]
        XCTAssertTrue(markWatched.waitForExistence(timeout: 2))
        markWatched.tap()

        let markThrough = app.buttons["Episodes 1–6"]
        XCTAssertTrue(markThrough.waitForExistence(timeout: 2))
        attachScreenshot(named: "episode-six-confirmation")
        markThrough.tap()

        XCTAssertTrue(app.buttons["Mark episode unwatched"].waitForExistence(timeout: 2))
    }

    func testRootUsesExactlyThreeNativeTabs() {
        let tabBar = app.tabBars.firstMatch

        XCTAssertTrue(tabBar.waitForExistence(timeout: 2))
        XCTAssertEqual(tabBar.buttons.count, 3)
        XCTAssertTrue(tabBar.buttons["Today"].exists)
        XCTAssertTrue(tabBar.buttons["Discover"].exists)
        XCTAssertTrue(tabBar.buttons["Library"].exists)
        XCTAssertFalse(tabBar.buttons["Together"].exists)
        XCTAssertFalse(tabBar.buttons["Profile"].exists)
        XCTAssertFalse(tabBar.buttons["AI"].exists)
    }

    func testSwitchingTabsPreservesTodayNavigation() {
        let upNextTitle = app.buttons["home.up-next-title"]
        XCTAssertTrue(upNextTitle.waitForExistence(timeout: 2))
        upNextTitle.tap()
        XCTAssertTrue(app.buttons["season.1"].waitForExistence(timeout: 2))

        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["library.settings"].waitForExistence(timeout: 2))

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["season.1"].waitForExistence(timeout: 2))
    }

    private func openSeason() {
        let upNextTitle = app.buttons["home.up-next-title"]
        XCTAssertTrue(upNextTitle.waitForExistence(timeout: 2))
        upNextTitle.tap()
        let season = app.buttons["season.1"]
        scrollToElement(season)
        season.tap()
        XCTAssertTrue(app.staticTexts["0 watched"].waitForExistence(timeout: 3))
    }

    private func scrollToElement(_ element: XCUIElement) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension CoreJourneySmokeUITests {
    func testActivityOpensFromDetailInOneTap() {
        launchCoreJourneys()
        app.buttons["home.up-next-title"].tap()

        let primary = app.buttons["details.primary-action"]
        assertExists(primary)
        XCTAssertTrue(
            primary.label.localizedCaseInsensitiveContains("Mark next watched"),
            "Expected the primary action to stay Mark next watched while episodes remain"
        )

        let activity = app.buttons["details.activity-action"]
        scrollToElement(activity)
        activity.tap()

        assertExists(app.navigationBars["Activity"])
        assertExists(app.descendants(matching: .any)["tracking.status"])
        assertExists(app.descendants(matching: .any)["tracking.rating"])
        assertExists(app.descendants(matching: .any)["tracking.note"])

        app.buttons["Done"].tap()
        let more = app.buttons["More actions for Test Show"]
        scrollToElement(more)
        more.tap()
        XCTAssertFalse(
            app.buttons["Activity and private note"].waitForExistence(timeout: 1),
            "Expected Activity to be one tap, not duplicated in More"
        )
    }

    func testSettingsOpensViewingDiaryWithoutLibrarySectionMenu() {
        launchCoreJourneys()
        app.buttons["today.settings"].tap()

        assertExists(app.descendants(matching: .any)["settings.space-switch"])
        let spaceSwitch = app.descendants(matching: .any)["settings.space-switch"]
        XCTAssertTrue(spaceSwitch.label.localizedCaseInsensitiveContains("Shake"))
        XCTAssertTrue(spaceSwitch.label.localizedCaseInsensitiveContains("people icon"))

        let diary = app.buttons["settings.viewing-diary"]
        assertExists(diary)
        diary.tap()

        assertExists(app.navigationBars["Viewing diary"])
        XCTAssertFalse(app.buttons["library.section-menu"].exists)
    }

    func testLibraryHistoryUsesHistoryNavigationTitle() {
        launchCoreJourneys()
        app.tabBars.buttons["Library"].tap()

        let sectionMenu = app.buttons["library.section-menu"]
        assertExists(sectionMenu)
        assertNavigationTitle("Library")

        sectionMenu.tap()
        let history = app.buttons["History"]
        assertExists(history)
        history.tap()

        assertExists(app.buttons["library.section-menu"])
        assertNavigationTitle("History")
    }

    func testNonHeroQueueCardMarksProgressIntoPrivateDiary() {
        launchCoreJourneys()

        let queueMenu = app.buttons["today.queue-actions.ui-test-queue-show"]
        scrollToElement(queueMenu)
        queueMenu.tap()

        let markByID = app.buttons["today.queue-mark-watched"]
        if markByID.waitForExistence(timeout: 2) {
            markByID.tap()
        } else {
            let markByLabel = app.buttons["Mark next episode watched"]
            assertExists(markByLabel)
            markByLabel.tap()
        }

        app.buttons["today.settings"].tap()
        let diary = app.buttons["settings.viewing-diary"]
        assertExists(diary)
        diary.tap()

        let diaryEntry = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "diary.entry.",
                "Queue Show"
            )
        ).firstMatch
        assertExists(diaryEntry)
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
}
