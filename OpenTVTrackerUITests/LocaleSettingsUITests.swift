import XCTest

final class LocaleSettingsUITests: XCTestCase {
    func testContentLanguageCanFollowTheDeviceOrUseAnOverride() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-core-journeys"]
        app.launch()

        XCTAssertTrue(app.buttons["home.up-next-title"].waitForExistence(timeout: 5))
        app.buttons["today.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let contentLanguage = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Content language")
        ).firstMatch
        scrollToHittable(contentLanguage, in: app)
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
                format: "label == %@",
                "French, FR"
            )
        ).firstMatch
        XCTAssertTrue(french.waitForExistence(timeout: 5))
        french.tap()

        XCTAssertTrue(contentLanguage.waitForExistence(timeout: 5))
        XCTAssertTrue(contentLanguage.label.contains("French"))

        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["today.settings"].waitForExistence(timeout: 5))
        app.buttons["today.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let restoredContentLanguage = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@",
                "Content language",
                "French"
            )
        ).firstMatch
        scrollToHittable(restoredContentLanguage, in: app)
        XCTAssertTrue(restoredContentLanguage.isHittable)
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists { break }
            nudgeSettingsScroll(in: app, upward: true)
        }
        XCTAssertTrue(element.exists, "Expected \(element) to exist after scrolling")
        let navigationBarBottom = app.navigationBars["Settings"].frame.maxY
        for _ in 0..<4 {
            if element.frame.minY >= navigationBarBottom { break }
            nudgeSettingsScroll(in: app, upward: false)
        }
        XCTAssertGreaterThanOrEqual(
            element.frame.minY,
            navigationBarBottom,
            "Expected \(element) to clear the Settings navigation bar"
        )
        for _ in 0..<8 {
            if element.isHittable { break }
            nudgeSettingsScroll(in: app, upward: true)
        }
        XCTAssertTrue(element.isHittable, "Expected \(element) to become hittable")
    }

    private func nudgeSettingsScroll(in app: XCUIApplication, upward: Bool) {
        let startY = upward ? 0.72 : 0.38
        let endY = upward ? 0.52 : 0.58
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}
