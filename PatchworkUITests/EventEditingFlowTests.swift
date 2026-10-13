// SPDX-License-Identifier: MPL-2.0

import XCTest

/// Editing and deleting your own event, end to end over the fixtures. The
/// sample reader is a member of the Repair Cafe, and its calendar holds two
/// events that name them as creator: "Toaster triage", which they posted,
/// and "Bike tune-up clinic", which arrived from the patch's calendar feed
/// and so is nobody's to edit here.
final class EventEditingFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Edit: the form opens filled and on the event's clock, says plainly
    /// that the old "repeats" word is not something it can change, and
    /// sends what changed — a longer title and a location cleared, which
    /// the web's form cannot do. The detail and the calendar both say so.
    func testEditYourEventsTitleAndClearItsLocation() {
        let app = launchSignedIn()
        openRepairCafeCalendar(app)
        openEvent(app, "Toaster triage")

        XCTAssertTrue(app.staticTexts["Repair Cafe back room"].exists, "the location before the edit")
        let edit = app.buttons["eventEdit"]
        XCTAssertTrue(scroll(app, to: edit), "the reader's own event offers Edit")
        XCTAssertTrue(app.buttons["eventDelete"].exists)
        XCTAssertTrue(wait(app.buttons["eventDelete"], label: "Delete"), "a published event is deleted, not withdrawn")
        capture(app, "60 Your event's acts")
        edit.tap()

        let heading = app.staticTexts["eventFormHeading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, "Edit event")
        XCTAssertTrue(app.descendants(matching: .any)["eventFormRecurrence"].exists, "an old repeat is said, and offered nothing")
        XCTAssertTrue(app.segmentedControls["eventTier"].exists, "a member editing their own event chooses its tier")
        let save = app.buttons["eventFormSubmit"]
        XCTAssertTrue(wait(save, label: "Save changes"))
        XCTAssertFalse(save.isEnabled, "nothing to save until something changes")
        capture(app, "61 The edit form")

        let title = app.textFields["eventTitle"]
        XCTAssertEqual(title.value as? String, "Toaster triage", "filled from the event")
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        title.typeText(" and kettles")
        let location = app.textFields["eventLocation"]
        XCTAssertEqual(location.value as? String, "Repair Cafe back room")
        location.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        location.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30))
        XCTAssertTrue(save.isEnabled)
        capture(app, "62 Edited")
        save.tap()

        XCTAssertTrue(app.descendants(matching: .any)["eventStatus"].waitForExistence(timeout: 10), "the web's toast, as a line")
        XCTAssertTrue(app.staticTexts["Toaster triage and kettles"].waitForExistence(timeout: 5), "the detail shows the edit")
        XCTAssertFalse(app.staticTexts["Repair Cafe back room"].exists, "and the location is gone")
        capture(app, "63 The edited event")

        app.navigationBars["Event"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout: 5))
        XCTAssertTrue(calendarRow(app, "Toaster triage and kettles").waitForExistence(timeout: 10), "the calendar reads it again")
        XCTAssertFalse(app.staticTexts["Repair Cafe back room"].exists)
        capture(app, "64 The calendar after the edit")
    }

    /// Delete: confirmed, then gone — from the page, which leaves, and
    /// from the calendar and the Events tab behind it.
    func testDeleteYourEventAndItIsGone() {
        let app = launchSignedIn()
        openRepairCafeCalendar(app)
        openEvent(app, "Toaster triage")

        let delete = app.buttons["eventDelete"]
        XCTAssertTrue(scroll(app, to: delete))
        delete.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Delete", "eventDelete")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "a destructive act asks first")
        XCTAssertTrue(app.staticTexts["Delete this event?"].exists)
        capture(app, "65 Delete, confirmed")
        confirm.tap()

        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout: 10), "the page about nothing leaves")
        XCTAssertTrue(calendarRow(app, "Bike tune-up clinic").waitForExistence(timeout: 10))
        XCTAssertTrue(gone(calendarRow(app, "Toaster triage")), "and the calendar no longer holds it")
        capture(app, "66 The calendar after the delete")

        app.navigationBars["Calendar"].buttons["Done"].tap()
        XCTAssertTrue(gone(app.navigationBars["Calendar"]))
        app.tabBars.buttons["Events"].tap()
        XCTAssertTrue(app.navigationBars["Events"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Fall mending circle"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Toaster triage"].exists, "nor does the quilt's calendar")
    }

    /// An event from the patch's calendar feed is changed in that calendar:
    /// no Edit and no Delete, even for the creator it names.
    func testAnImportedEventOffersNoEdit() {
        let app = launchSignedIn()
        openRepairCafeCalendar(app)
        openEvent(app, "Bike tune-up clinic")

        let website = app.buttons["Open on quilt website"]
        XCTAssertTrue(scroll(app, to: website), "the foot of the page")
        XCTAssertFalse(app.buttons["eventEdit"].exists, "the source is authoritative")
        XCTAssertFalse(app.buttons["eventDelete"].exists, "and its skip-list is the feed's managers' call")
        capture(app, "67 An imported event")
    }

    // MARK: Helpers

    private func launchSignedIn() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro"]
        app.launch()
        app.buttons["quiltChoice"].firstMatch.tap()
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
        XCTAssertFalse(app.textFields["signInCode"].waitForExistence(timeout: 5))
        return app
    }

    /// The Repair Cafe, from the Dashboard, raised by its sheet, and into
    /// the whole calendar.
    private func openRepairCafeCalendar(_ app: XCUIApplication) {
        let dashboard = app.tabBars.buttons["Dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
        dashboard.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "dashboardRow", "Repair Cafe")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        pullUp(app)
        let events = app.buttons["glimpseDoor-Events"]
        XCTAssertTrue(events.waitForExistence(timeout: 10))
        events.tap()
        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout: 10))
    }

    private func openEvent(_ app: XCUIApplication, _ title: String) {
        let row = calendarRow(app, title)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
    }

    private func calendarRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "calendarRow", title)).firstMatch
    }

    private func pullUp(_ app: XCUIApplication) {
        let profile = app.scrollViews["patchProfile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        let pulled = { profile.frame.minY < app.frame.height / 4 }
        for _ in 0..<3 where !pulled() {
            profile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
        }
        XCTAssertTrue(pulled(), "the profile pulls up to its full height")
    }

    private func scroll(_ app: XCUIApplication, to element: XCUIElement, swipes: Int = 8) -> Bool {
        // Clear of the foot of the screen, too: a List reports a row as
        // hittable while it is half under the home indicator.
        let clear = { element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 40 }
        for _ in 0..<swipes {
            if clear() { return true }
            app.swipeUp()
        }
        return clear()
    }

    private func gone(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
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
