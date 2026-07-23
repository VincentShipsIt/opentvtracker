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
