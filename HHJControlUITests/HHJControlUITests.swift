import XCTest

@MainActor
final class HHJControlUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state"]
        app.launch()
    }

    func testAltitudeOutsideRangeShowsValidationError() {
        app.tabBars.buttons["高级"].tap()
        let editor = app.buttons["手动设置"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        let altitude = app.textFields.element(boundBy: 2)
        XCTAssertTrue(altitude.waitForExistence(timeout: 5))
        altitude.tap()
        altitude.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "9000.1")
        app.buttons["checkmark"].tap()
        XCTAssertTrue(app.staticTexts["海拔必须在 -500 到 9000 米之间"].waitForExistence(timeout: 5))
    }

    func testFavoriteAppearsWithoutAutomaticallySending() {
        let favorite = app.buttons["star"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        favorite.tap()
        XCTAssertTrue(app.alerts["HHJControl"].waitForExistence(timeout: 5))
        app.alerts["HHJControl"].buttons["好"].tap()
        app.tabBars.buttons["收藏"].tap()
        XCTAssertTrue(app.staticTexts["23.129100, 113.264400 · 69.8 m"].waitForExistence(timeout: 5))
    }
}
