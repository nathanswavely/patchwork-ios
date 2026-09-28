// SPDX-License-Identifier: MPL-2.0

import XCTest

/// Posting an event and suggesting one, end to end over the fixtures. The
/// fixture reader follows the Listening Room (which takes suggestions) and is
/// a member of the Repair Cafe, so the one door says "Suggest an event" and
/// the other "New event" — before either form is opened.
final class EventPostingFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// A follower is a visitor: the Listening Room's calendar offers a
    /// suggestion, the form says it will be reviewed and offers no tier, and
    /// what comes back is the web's card rather than an event page.
    func testAFollowerSuggestsAnEventAndIsToldItWillBeReviewed() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro"]
        app.launch()
        openSampleQuilt(app)
        signIn(app)

        openCalendar(app, tile: "quiltTile-listening-room")
        let door = calendarDoor(app)
        XCTAssertTrue(door.waitForExistence(timeout: 10), "a patch that takes suggestions has a door on its calendar")
        XCTAssertTrue(wait(door, label: "Suggest an event"), "and it says what posting will do before the form is filled")
        capture(app, "50 Suggest an event on the calendar")
        door.tap()

        let heading = app.staticTexts["eventFormHeading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, "Suggest an event")
        XCTAssertTrue(app.staticTexts["eventFormSentence"].label.contains("It will be reviewed before it appears."))
        XCTAssertFalse(app.segmentedControls["eventTier"].exists, "a suggestion is public, so no tier is offered")
        XCTAssertFalse(app.buttons["eventFormSubmit"].isEnabled, "a title or nothing")
        capture(app, "51 The suggestion form")

        let title = app.textFields["eventTitle"]
        title.tap()
        title.typeText("Touring trio, one night only")
        app.buttons["eventFormSubmit"].tap()

        let card = app.descendants(matching: .any)["eventSubmittedHeading"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the server held it, and the form says so")
        XCTAssertTrue(app.staticTexts["eventSubmittedSentence"].label.contains("The patch admins will look at it."))
        capture(app, "52 Submitted for review")
        app.buttons["eventSubmittedDone"].tap()

        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout: 5), "Done is the calendar again")
        XCTAssertFalse(app.staticTexts["Touring trio, one night only"].exists, "a pending suggestion is on no list")
    }

    /// A member posts directly: "New event", a tier within the patch's
    /// ceiling, and the event's own page on the way out — then Back is the
    /// calendar with the new night in Upcoming.
    func testAMemberPostsAnEventThatLandsOnTheCalendar() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro"]
        app.launch()
        openSampleQuilt(app)
        signIn(app)

        let dashboard = app.tabBars.buttons["Dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
        dashboard.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "dashboardRow", "Repair Cafe")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the patch the reader is a member of")
        row.tap()
        XCTAssertTrue(app.buttons["closePatch"].waitForExistence(timeout: 10))
        app.swipeUp()
        let events = app.buttons["glimpseDoor-Events"]
        XCTAssertTrue(events.waitForExistence(timeout: 10))
        XCTAssertTrue(wait(app.buttons["eventDoor"], label: "New event"), "the glimpse carries the door under its events")
        capture(app, "53 New event in the glimpse")
        events.tap()
        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Nothing coming up."].waitForExistence(timeout: 10))

        let door = calendarDoor(app)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        XCTAssertTrue(wait(door, label: "New event"))
        door.tap()

        let heading = app.staticTexts["eventFormHeading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, "New event")
        let tier = app.segmentedControls["eventTier"]
        XCTAssertTrue(tier.exists, "posting directly chooses who it is for")
        XCTAssertTrue(tier.buttons["Members only"].exists)
        XCTAssertFalse(tier.buttons["Followers"].exists, "not offered where the patch keeps events from followers")
        XCTAssertTrue(app.staticTexts["eventTierCeiling"].exists, "and one line says the patch set it")
        capture(app, "54 The new event form")

        let title = app.textFields["eventTitle"]
        title.tap()
        title.typeText("Fix-it night")
        // The times sit below the fold, written on the patch's clock; the
        // default start is the next whole hour, which is already valid.
        app.swipeUp()
        XCTAssertTrue(app.switches["eventHasEnd"].waitForExistence(timeout: 5))
        capture(app, "54a The times")
        app.buttons["eventFormSubmit"].tap()

        XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 10), "a post opens its own page")
        XCTAssertTrue(app.staticTexts["Fix-it night"].waitForExistence(timeout: 5))
        capture(app, "55 The posted event")
        app.navigationBars["Event"].buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout: 5))
        let posted = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "calendarRow", "Fix-it night")).firstMatch
        XCTAssertTrue(posted.waitForExistence(timeout: 10), "and it is in Upcoming")
        capture(app, "56 Upcoming, with the new night")
    }

    /// Signed out, the door is still there where a stranger would be taken,
    /// and it is the native sign-in sheet — the way the heart on a card is.
    func testSignedOutTheDoorOpensSignIn() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro"]
        app.launch()
        openSampleQuilt(app)

        openCalendar(app, tile: "quiltTile-listening-room")
        let door = calendarDoor(app)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        XCTAssertTrue(wait(door, label: "Suggest an event"))
        capture(app, "57 Suggest an event, signed out")
        door.tap()
        XCTAssertTrue(app.textFields["signInEmail"].waitForExistence(timeout: 5), "the door is the sign-in sheet")
        XCTAssertFalse(app.staticTexts["eventFormHeading"].exists, "and not a form nobody could send")
        app.buttons["Cancel"].tap()
    }

    // MARK: Helpers

    private func openCalendar(_ app: XCUIApplication, tile: String) {
        let patch = app.buttons[tile]
        XCTAssertTrue(patch.waitForExistence(timeout: 10))
        patch.tap()
        XCTAssertTrue(app.buttons["closePatch"].waitForExistence(timeout: 10))
        app.swipeUp()
        let events = app.buttons["glimpseDoor-Events"]
        XCTAssertTrue(events.waitForExistence(timeout: 10))
        events.tap()
        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout: 10))
    }

    /// The calendar's own door, in its bottom bar. The glimpse's row is off
    /// the accessibility tree once the calendar is pushed over it, so the
    /// identifier names one button.
    private func calendarDoor(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "eventDoor").firstMatch
    }

    private func openSampleQuilt(_ app: XCUIApplication) {
        app.buttons["quiltChoice"].firstMatch.tap()
        let explore = app.buttons["exploreQuilt"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        explore.tap()
        XCTAssertTrue(app.navigationBars["Sample quilt"].waitForExistence(timeout: 10))
    }

    /// The sample reader, signed in by the code the fixtures answer to.
    private func signIn(_ app: XCUIApplication) {
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
        XCTAssertFalse(app.textFields["signInCode"].waitForExistence(timeout: 5))
    }

    private func wait(_ element: XCUIElement, label: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
