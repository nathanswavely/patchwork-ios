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
        XCTAssertTrue(app.navigationBars["Sample quilt"].waitForExistence(timeout: 10))
        capture(app, "02 Quilt")
        XCTAssertTrue(app.buttons["quiltTile-common-thread"].waitForExistence(timeout: 10))
        app.buttons["quiltTile-common-thread"].pinch(withScale: 1.3, velocity: 1)
        XCTAssertFalse(app.navigationBars["Patch"].exists, "Pinching must not open a patch")
        capture(app, "02a After pinch")
        let tile = app.buttons["quiltTile-common-thread"]
        let originalFrame = tile.frame
        tile.tap()
        XCTAssertTrue(app.navigationBars["Patch"].waitForExistence(timeout: 5))
        capture(app, "03 Docked profile at rest")
        app.buttons["Done"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertEqual(tile.frame.minX, originalFrame.minX, accuracy: 1)
        XCTAssertEqual(tile.frame.width, originalFrame.width, accuracy: 1)

        // The filter sheet narrows the quilt live; Clear lives in the sheet.
        app.buttons["Filter"].tap()
        XCTAssertTrue(app.buttons["music"].waitForExistence(timeout: 5))
        app.buttons["music"].tap()
        XCTAssertFalse(app.buttons["quiltTile-common-thread"].waitForExistence(timeout: 2))
        capture(app, "02b Filtered quilt")
        app.buttons["Clear"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 5))

        // Typing in the top bar's field finds; only the one row narrows.
        app.buttons["Search"].firstMatch.tap()
        let field = app.textFields["searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Listening")
        XCTAssertTrue(app.buttons["searchPatch"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["showMatches"].tap()
        XCTAssertTrue(app.buttons["quiltTile-listening-room"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["quiltTile-common-thread"].exists)
        capture(app, "02c Search chip")
        app.buttons["Filter"].tap()
        XCTAssertTrue(app.buttons["Clear"].waitForExistence(timeout: 5))
        app.buttons["Clear"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 5))

        app.segmentedControls.buttons["Map"].tap()
        capture(app, "02d Map")
        app.segmentedControls.buttons["List"].tap()
        capture(app, "02e List")
        app.buttons["patchRow"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Patch"].waitForExistence(timeout: 10))
        app.swipeUp()
        capture(app, "03a Docked profile pulled up")
        app.buttons["Upcoming events"].tap()
        XCTAssertTrue(app.buttons["eventRow"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["eventRow"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Saturday open studio"].exists)
        capture(app, "04 Event detail")
        app.buttons["Done"].tap()

        // Discover asks, then answers with patches; a row docks the profile.
        app.buttons["Discover"].firstMatch.tap()
        XCTAssertTrue(app.buttons["music"].waitForExistence(timeout: 10))
        capture(app, "05 Discover asks")
        app.buttons["music"].tap()
        app.buttons["Show me patches"].tap()
        XCTAssertTrue(app.buttons["discoverRow"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "05a Discover answers")
        app.buttons["discoverRow"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Patch"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        app.buttons["Events"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Events"].waitForExistence(timeout: 10))
        app.buttons["Account"].tap()
        app.buttons["Switch quilt"].tap()
        XCTAssertTrue(app.navigationBars["Choose a quilt"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Neighbor quilt"].exists, "Connected quilts are doorways in the switcher")
    }

    /// The events calendar: the date filter narrows it to one day and says
    /// so when nothing is left, and an event's detail offers the calendar
    /// without asking for it until it is chosen.
    func testEventsDateFilterAndCalendarAffordance() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview"]
        app.launch()
        app.buttons["quiltChoice"].firstMatch.tap()
        let explore = app.buttons["exploreQuilt"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        explore.tap()
        XCTAssertTrue(app.navigationBars["Sample quilt"].waitForExistence(timeout: 10))

        app.buttons["Events"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Events"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["eventRow"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Fall mending circle"].exists, "the whole calendar reads soonest first")
        capture(app, "10 Events list")

        // One preset, applied: only tonight's event survives it.
        app.buttons["dateFilter"].tap()
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 5))
        app.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["Saturday open studio"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Fall mending circle"].exists, "a later day is outside today")
        capture(app, "10a Events filtered to today")

        // Tomorrow has nothing on it, and the range says that rather than
        // claiming the calendar is empty.
        app.buttons["dateFilter"].tap()
        XCTAssertTrue(app.buttons["Tomorrow"].waitForExistence(timeout: 5))
        app.buttons["Tomorrow"].tap()
        XCTAssertTrue(app.staticTexts["No events in this range"].waitForExistence(timeout: 10))
        capture(app, "10b Empty date range")

        app.buttons["dateFilter"].tap()
        XCTAssertTrue(app.buttons["Any date"].waitForExistence(timeout: 5))
        app.buttons["Any date"].tap()
        XCTAssertTrue(app.buttons["eventRow"].firstMatch.waitForExistence(timeout: 10))

        app.buttons["eventRow"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["eventHost"].exists, "the host patch is a door")
        capture(app, "11 Event detail")
        // The flyer, the map and the actions sit below the fold, and a List
        // builds its rows as they come into view.
        XCTAssertTrue(scroll(app, to: app.buttons["Open in Maps"]), "coordinates earn a map")

        // The calendar affordance is offered and commits to nothing: opening
        // it asks for no permission, and the test stops at the offer rather
        // than at the system prompt behind it.
        let calendar = app.buttons["addToCalendarMenu"]
        XCTAssertTrue(scroll(app, to: calendar), "an active event offers its calendar")
        calendar.tap()
        capture(app, "11a Add to calendar")
    }

    func testLargeTextAndDarkAppearance() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "--dark-preview"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Choose a quilt"].waitForExistence(timeout: 10))
        capture(app, "06 Large text quilt selection")
        app.swipeUp()
        app.buttons["quiltChoice"].firstMatch.tap()
        let explore = app.buttons["exploreQuilt"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        capture(app, "07 Large text confirmation")
        explore.tap()
        XCTAssertTrue(app.navigationBars["Sample quilt"].waitForExistence(timeout: 10))
        capture(app, "08 Large text quilt")
        app.segmentedControls.buttons["List"].tap()
        app.buttons["patchRow"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Patch"].waitForExistence(timeout: 10))
        capture(app, "09 Large text patch")
    }

    /// Scrolls until an element exists and is on screen, or gives up.
    private func scroll(_ app: XCUIApplication, to element: XCUIElement, swipes: Int = 8) -> Bool {
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
