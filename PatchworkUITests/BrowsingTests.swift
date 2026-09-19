// SPDX-License-Identifier: MPL-2.0

import XCTest

final class BrowsingTests: XCTestCase {
    func testExplicitSelectionAndInvalidAddress() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Choose a quilt"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["exploreQuilt"].exists)
        let address = app.textFields["Quilt address"]
        address.tap()
        address.typeText("http://example.org")
        app.buttons["Find quilt"].tap()
        XCTAssertTrue(app.staticTexts["connectionError"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["exploreQuilt"].exists)
    }

    func testBrowsePatchEventAndSwitchQuilt() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview"]
        app.launch()
        capture(app, "01 Choose a quilt")
        app.buttons["quiltChoice"].firstMatch.tap()
        let explore = app.buttons["exploreQuilt"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        explore.tap()
        XCTAssertTrue(app.navigationBars["Patches"].waitForExistence(timeout: 10))
        capture(app, "02 Patches")
        app.buttons["patchRow"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Patch"].waitForExistence(timeout: 10))
        capture(app, "03 Patch profile")
        app.buttons["Upcoming events"].tap()
        XCTAssertTrue(app.buttons["eventRow"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["eventRow"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Saturday open studio"].exists)
        capture(app, "04 Event detail")
        app.tabBars.buttons["Events"].tap()
        XCTAssertTrue(app.navigationBars["Events"].waitForExistence(timeout: 10))
        app.buttons["Switch quilt"].tap()
        XCTAssertTrue(app.navigationBars["Choose a quilt"].waitForExistence(timeout: 10))
    }
    func testLargeTextAndDarkAppearance() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "--dark-preview"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Choose a quilt"].waitForExistence(timeout: 10))
        capture(app, "05 Large text quilt selection")
        app.swipeUp()
        app.buttons["quiltChoice"].firstMatch.tap()
        let explore = app.buttons["exploreQuilt"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        capture(app, "06 Large text confirmation")
        explore.tap()
        XCTAssertTrue(app.navigationBars["Patches"].waitForExistence(timeout: 10))
        app.buttons["patchRow"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Patch"].waitForExistence(timeout: 10))
        capture(app, "07 Large text patch")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
