// SPDX-License-Identifier: MPL-2.0

import XCTest

/// The settings half of People, end to end over the fixtures: a membership
/// hidden and shown again, a contact item added and given to a patch, and a
/// notification preference that is still what it was set to after leaving.
final class PeopleSettingsFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// My Patches → the Repair Cafe → Public off: the switch says Hidden, the
    /// footer says who still sees the reader, and the row says so on the way
    /// back. Then on again.
    func testHideAMembershipAndShowItAgain() {
        let app = launchSignedIn()
        openSettings(app)
        app.buttons["settingsPatches"].tap()
        XCTAssertTrue(app.navigationBars["My Patches"].waitForExistence(timeout: 5))
        let room = app.buttons["myPatch-extra-6"]
        XCTAssertTrue(room.waitForExistence(timeout: 10), "the Repair Cafe, under Member of")
        XCTAssertTrue(app.buttons["myPatchesUnfollow-listening-room"].exists, "the followed patch, with its own acts")
        XCTAssertTrue(app.descendants(matching: .any)["myPatchesArchived-repair-cafe-2"].exists, "the archived duplicate, by address")
        XCTAssertTrue(app.descendants(matching: .any)["myPatchesClaim-extra-3"].exists, "the claim, with its door to the website")
        capture(app, "60 My Patches")
        room.tap()

        let visible = app.switches["membershipVisible"]
        XCTAssertTrue(visible.waitForExistence(timeout: 5))
        XCTAssertEqual(visible.value as? String, "1", "public until hidden")
        flip(visible)
        XCTAssertTrue(wait(visible, value: "0"))
        XCTAssertTrue(named(app, "Its admins and members still see you").waitForExistence(timeout: 5),
                      "the footer says who still sees the reader")
        capture(app, "61 A hidden membership")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let summary = app.staticTexts["myPatchSummary-extra-6"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(wait(summary, label: "Hidden"), "the row reads what the quilt now holds")

        room.tap()
        XCTAssertTrue(visible.waitForExistence(timeout: 5))
        XCTAssertEqual(visible.value as? String, "0", "read back from the quilt, not remembered by the page")
        flip(visible)
        XCTAssertTrue(wait(visible, value: "1"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(wait(summary, label: "Public"))
    }

    /// Profile → Contact card → a phone number; then My Patches → the Repair
    /// Cafe → Not reachable → tick it → Save: Reachable by 1.
    func testAddAContactItemAndShareItWithAPatch() {
        let app = launchSignedIn()
        openSettings(app)
        app.buttons["settingsProfile"].tap()
        let door = app.buttons["profileContactCard"]
        XCTAssertTrue(door.waitForExistence(timeout: 5))
        door.tap()
        XCTAssertTrue(app.staticTexts["contactCardEmpty"].waitForExistence(timeout: 5), "the card starts empty")

        app.buttons["contactAdd"].tap()
        let value = app.textFields["contactValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["contactSave"].isEnabled, "an item needs a value")
        value.tap()
        value.typeText("+1 717 555 0100")
        let label = app.textFields["contactLabel"]
        label.tap()
        label.typeText("mobile")
        capture(app, "62 A new contact item")
        app.buttons["contactSave"].tap()

        let item = app.buttons["contactItem"]
        XCTAssertTrue(item.waitForExistence(timeout: 10), "on the card")
        XCTAssertTrue(wait(item, label: "Not shared with any patch"), "born shared with nothing")
        XCTAssertTrue(app.descendants(matching: .any)["contactNote"].exists)
        capture(app, "63 The contact card")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["settingsPatches"].tap()
        let room = app.buttons["myPatch-extra-6"]
        XCTAssertTrue(room.waitForExistence(timeout: 10))
        room.tap()

        let sharing = app.buttons["contactSharing"]
        XCTAssertTrue(sharing.waitForExistence(timeout: 5))
        XCTAssertTrue(wait(sharing, label: "Not reachable"))
        XCTAssertTrue(sharing.isEnabled, "the card has something on it now")
        sharing.tap()
        let choice = app.buttons["shareItem"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["shareSave"].isEnabled, "nothing changed yet")
        choice.tap()
        capture(app, "64 Choosing what a patch can reach you by")
        app.buttons["shareSave"].tap()

        XCTAssertTrue(wait(sharing, label: "Reachable by 1"), "the patch reads one item now")
        XCTAssertTrue(named(app, "can reach you by 1 item").waitForExistence(timeout: 5))
        capture(app, "65 Reachable by 1")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(wait(app.staticTexts["myPatchSummary-extra-6"], label: "Reachable by 1"))
    }

    /// Settings → Notifications: email for new proposals, on; out and back
    /// in, still on. The same page also opens from the bell's menu.
    func testFlipANotificationPreferenceAndItPersists() {
        let app = launchSignedIn()
        openSettings(app)
        app.buttons["settingsNotifications"].tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
        let email = app.switches["preference-proposal.new-email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        XCTAssertEqual(email.value as? String, "0", "email is off by default for a normal-priority type")
        XCTAssertEqual(app.switches["preference-proposal.new-in_app"].value as? String, "1")
        capture(app, "66 Notification preferences")
        flip(email)
        XCTAssertTrue(wait(email, value: "1"))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["settingsNotifications"].tap()
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        XCTAssertEqual(email.value as? String, "1", "the quilt kept it")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()

        // The bell's door to the same page.
        app.buttons["Account"].tap()
        let bell = app.buttons["notificationBell"]
        XCTAssertTrue(bell.waitForExistence(timeout: 5))
        bell.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 10))
        app.buttons["notificationsMenu"].tap()
        let door = app.buttons["Notification settings"]
        XCTAssertTrue(door.waitForExistence(timeout: 5))
        door.tap()
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        XCTAssertEqual(email.value as? String, "1")
    }

    // MARK: Helpers

    private func launchSignedIn() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro"]
        app.launch()
        let explore = app.buttons["exploreQuilt"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        explore.tap()
        XCTAssertTrue(app.navigationBars["Sample quilt"].waitForExistence(timeout: 10))
        app.buttons["Account"].tap()
        let start = app.buttons["Sign in"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let email = app.textFields["signInEmail"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("reader@example.org")
        app.buttons["signInSendCode"].tap()
        let code = app.textFields["signInCode"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.tap()
        code.typeText("123456")
        app.buttons["signInContinue"].tap()
        // Gone once the quilt has answered: waited for, not glanced at, so a
        // slow machine is not a failed sign-in.
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: code)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 20), .completed, "signed in")
        return app
    }

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["Account"].tap()
        let settings = app.buttons["accountSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    /// A list row's switch is the whole row; the thumb is at its trailing end.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    private func wait(_ element: XCUIElement, value: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func wait(_ element: XCUIElement, label: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func named(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
