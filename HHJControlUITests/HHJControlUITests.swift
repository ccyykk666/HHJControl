import XCTest

@MainActor
final class HHJControlUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state"]
        app.launchEnvironment["UITEST_SEARCH_FIXTURE"] = "1"
        app.launch()
    }

    func testSearchIsTrailingAndResultReturnsToLocation() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        XCTAssertEqual(tabBar.buttons.count, 4)
        let search = tabBar.buttons.element(boundBy: 3)
        XCTAssertEqual(search.label, "搜索")
        search.tap()
        let result = app.buttons["search.fixture.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.staticTexts["测试地点"].waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["定位"].isSelected)
    }

    func testAltitudeOutsideRangeShowsValidationError() {
        app.tabBars.buttons["高级"].tap()
        let editor = app.buttons["手动设置"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        let altitude = app.textFields["coordinate.altitude"]
        XCTAssertTrue(altitude.waitForExistence(timeout: 5))
        altitude.tap()
        altitude.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "9000.1")
        app.buttons["coordinate.apply"].tap()
        XCTAssertTrue(app.staticTexts["海拔必须在 -500 到 9000 米之间"].waitForExistence(timeout: 5))
    }

    func testFavoriteAppearsWithoutAutomaticallySending() {
        let favorite = app.buttons["location.favorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        favorite.tap()
        XCTAssertTrue(app.alerts["HHJControl"].waitForExistence(timeout: 5))
        app.alerts["HHJControl"].buttons["好"].tap()
        app.tabBars.buttons["收藏"].tap()
        XCTAssertTrue(app.staticTexts["23.129100, 113.264400 · 69.8 m"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["location.send"].exists)
    }
}
