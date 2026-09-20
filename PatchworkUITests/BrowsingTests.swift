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
        // Each glimpse heading is the door into that room (web ADR 042).
        app.buttons["glimpseDoor-Events"].tap()
        XCTAssertTrue(app.buttons["calendarRow"].firstMatch.waitForExistence(timeout: 10))
        capture(app, "04 Patch calendar")
        app.buttons["calendarRow"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Saturday open studio"].exists)
        capture(app, "04a Event detail")
        app.buttons["Done"].tap()

        // The profile's depth: state worn in the head, and the two rooms the
        // glimpses open onto. Taken on the quilt's own tile, because this is
        // the fixture patch that publishes both a roster and a record.
        app.segmentedControls.buttons["Quilt"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        XCTAssertTrue(app.navigationBars["Patch"].waitForExistence(timeout: 10))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Amended lining"].waitForExistence(timeout: 10), "A patch that amended the lining wears the fact")
        XCTAssertTrue(app.staticTexts["About"].exists, "About leads the glimpses")
        capture(app, "03b Glimpses")

        // A public patch's calendar offers the feeds; nothing here signs in.
        app.buttons["glimpseDoor-Events"].tap()
        XCTAssertTrue(app.buttons["subscribeToCalendar"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Patch"].firstMatch.tap()

        let members = app.buttons["glimpseDoor-Members"]
        XCTAssertTrue(members.waitForExistence(timeout: 10))
        members.tap()
        XCTAssertTrue(app.staticTexts["Rowan Hale"].waitForExistence(timeout: 10), "A member row names the person")
        XCTAssertTrue(app.staticTexts["Role: admin"].exists, "and the role they hold")
        capture(app, "03c Members")
        app.navigationBars.buttons["Patch"].firstMatch.tap()

        let governance = app.buttons["glimpseDoor-Governance"]
        XCTAssertTrue(governance.waitForExistence(timeout: 10))
        governance.tap()
        XCTAssertTrue(app.buttons["governanceDocuments"].waitForExistence(timeout: 10))
        capture(app, "03d Governance")
        app.buttons["governanceDocuments"].tap()
        XCTAssertTrue(app.buttons["documentRow"].firstMatch.waitForExistence(timeout: 10))
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
    /// The quilt's information stack, and the Display settings a reader with
    /// no account can still make. Both hang off the account menu.
    func testQuiltInfoStackAndDisplaySettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview"]
        app.launch()
        app.buttons["quiltChoice"].firstMatch.tap()
        let explore = app.buttons["exploreQuilt"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        explore.tap()
        XCTAssertTrue(app.navigationBars["Sample quilt"].waitForExistence(timeout: 10))

        // About this quilt is a stack, not one sheet: the Label is a push away.
        app.buttons["Account"].tap()
        app.buttons["About this quilt"].tap()
        XCTAssertTrue(app.buttons["infoLabel"].waitForExistence(timeout: 10))
        capture(app, "10 Quilt info stack")
        app.buttons["infoLabel"].tap()
        XCTAssertTrue(app.staticTexts["How Sample quilt is run"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Sample Steward"].exists, "a solo steward leads with the person")
        capture(app, "11 The Label")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["infoPrivacy"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        // The footer strip at the end of List mode reaches the same pages.
        app.segmentedControls.buttons["List"].tap()
        let footer = app.buttons["footer-infoLabel"]
        var swipes = 0
        while !footer.isHittable && swipes < 10 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(footer.isHittable, "the list ends in one quiet row of links")
        capture(app, "11a Footer row")
        footer.tap()
        XCTAssertTrue(app.staticTexts["How Sample quilt is run"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        app.segmentedControls.buttons["Quilt"].tap()

        // Display needs no account. Muted recuts the quilt in place.
        XCTAssertTrue(app.buttons["quiltTile-common-thread"].waitForExistence(timeout: 10))
        app.buttons["Account"].tap()
        app.buttons["Display"].tap()
        let colors = app.segmentedControls["colorsPicker"]
        XCTAssertTrue(colors.waitForExistence(timeout: 10))
        capture(app, "12 Display settings")
        colors.buttons["Muted"].tap()
        XCTAssertTrue(colors.buttons["Muted"].isSelected)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["quiltTile-common-thread"].waitForExistence(timeout: 10))
        capture(app, "13 Muted quilt")

        // Put it back, so the choice does not leak into the next launch.
        app.buttons["Account"].tap()
        app.buttons["Display"].tap()
        XCTAssertTrue(colors.waitForExistence(timeout: 10))
        colors.buttons["Default"].tap()
        app.buttons["Done"].tap()
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

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
