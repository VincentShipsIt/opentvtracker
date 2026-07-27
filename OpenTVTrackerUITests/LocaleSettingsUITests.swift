import XCTest

final class LocaleSettingsUITests: XCTestCase {
    func testContentLanguageCanFollowTheDeviceOrUseAnOverride() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-core-journeys"]
        app.launch()

        XCTAssertTrue(app.buttons["home.up-next-title"].waitForExistence(timeout: 5))
        app.buttons["today.settings"].tap()

        let contentLanguage = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Content language")
        ).firstMatch
        XCTAssertTrue(contentLanguage.waitForExistence(timeout: 5))
        contentLanguage.tap()

        XCTAssertTrue(app.navigationBars["Content language"].waitForExistence(timeout: 5))
        let automatic = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@",
                "Automatic",
                "EN"
            )
        ).firstMatch
        XCTAssertTrue(automatic.waitForExistence(timeout: 5))

        let search = app.searchFields["Language or code"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("French")

        let french = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@",
                "French",
                "FR"
            )
        ).firstMatch
        XCTAssertTrue(french.waitForExistence(timeout: 5))
    }
}
