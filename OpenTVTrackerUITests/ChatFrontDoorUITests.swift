import XCTest

final class ChatFrontDoorUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-core-journeys"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testChatTabOffersTheComposer() {
        let chatTab = app.tabBars.buttons["Chat"]
        XCTAssertTrue(chatTab.waitForExistence(timeout: 10), "Expected a Chat tab in the tab bar")
        chatTab.tap()

        let composer = app.descendants(matching: .any)["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "Expected the chat composer on the Chat tab")
    }
}
