// SPDX-License-Identifier: MPL-2.0

import XCTest

/// A patch's admin at work, end to end over the fixtures. `--preview-admin`
/// makes the fixture reader an admin of the Film Club, which holds three
/// requests to join (two with a note), two suggested events, one invitation
/// out, one person removed, and members to remove.
final class PatchAdminFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Approve one request and reject another from the Dashboard's ask, see
    /// the ask drop, then reach the queue again from the request's
    /// notification.
    func testAnAdminAnswersRequestsAndTheDashboardAskDrops() {
        let app = launch()
        openDashboard(app)
        let ask = app.buttons["dashboardRequests-extra-7"]
        XCTAssertTrue(ask.waitForExistence(timeout: 10), "the requests are asked of the admin")
        XCTAssertTrue(ask.label.contains("3 pending member requests"), ask.label)
        XCTAssertTrue(app.staticTexts["dashboardSection-Attention needed"].exists)
        capture(app, "100 Attention needed")
        ask.tap()

        XCTAssertTrue(app.navigationBars["Pending requests"].waitForExistence(timeout: 10))
        let note = app.staticTexts["joinMessage-priya"]
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertTrue(note.label.contains("I run the projector"), "the intro is quoted under the request")
        XCTAssertTrue(said(app, "3 requests waiting"))
        capture(app, "101 Pending requests")

        app.buttons["joinApprove-priya"].tap()
        confirm(app, "Approve")
        XCTAssertTrue(said(app, "Member approved"))
        XCTAssertFalse(app.buttons["joinApprove-priya"].exists, "off the queue at once")

        app.buttons["joinReject-tom"].tap()
        confirm(app, "Reject")
        XCTAssertTrue(said(app, "Request rejected"))
        XCTAssertTrue(said(app, "1 request waiting"))
        XCTAssertTrue(app.buttons["joinApprove-bea"].exists, "the one left waits")
        capture(app, "102 One left")

        app.navigationBars["Pending requests"].buttons.element(boundBy: 0).tap()
        let dropped = app.buttons["dashboardRequests-extra-7"]
        XCTAssertTrue(dropped.waitForExistence(timeout: 10))
        XCTAssertTrue(wait(dropped, label: "1 pending member request"), "the Dashboard reads the queue again")

        // The request's notification opens the same queue, for an admin.
        let unread = app.buttons["dashboardUnread"]
        XCTAssertTrue(scroll(app, to: unread, up: true))
        unread.tap()
        let row = app.buttons["notificationRow-notif-8"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.navigationBars["Pending requests"].waitForExistence(timeout: 10), "not the public roster")
        XCTAssertTrue(app.buttons["joinApprove-bea"].waitForExistence(timeout: 10))
    }

    /// Decline one suggestion with a note and approve the other, on the
    /// patch's calendar, where the approved one then appears.
    func testAnAdminReviewsSuggestionsOnTheCalendar() {
        let app = launch()
        openDashboard(app)
        let ask = app.buttons["dashboardSuggestions-extra-7"]
        XCTAssertTrue(ask.waitForExistence(timeout: 10))
        XCTAssertTrue(ask.label.contains("2 suggested events"), ask.label)
        openClub(app)
        let events = app.buttons["glimpseDoor-Events"]
        XCTAssertTrue(scroll(app, to: events))
        events.tap()
        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["suggestedEventsHeading"].waitForExistence(timeout: 10), "the queue heads the calendar")
        XCTAssertFalse(calendarRow(app, "Silent film night").exists, "a suggestion is not on the calendar")
        capture(app, "103 Suggested events")

        app.buttons["suggestionDecline-suggest-docs"].tap()
        XCTAssertTrue(app.staticTexts["declineHeading"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "deletes the suggestion")).firstMatch.exists,
                      "the sheet says what declining does")
        let note = app.textFields["declineNote"]
        note.tap()
        note.typeText("We already have a documentary night that week.")
        capture(app, "104 Declining with a note")
        app.buttons["declineConfirm"].tap()
        XCTAssertTrue(said(app, "Suggestion declined"))
        XCTAssertFalse(app.buttons["suggestionDecline-suggest-docs"].exists)

        app.buttons["suggestionApprove-suggest-silent"].tap()
        XCTAssertTrue(said(app, "Event approved"))
        XCTAssertFalse(app.staticTexts["suggestedEventsHeading"].exists, "the queue is empty")
        XCTAssertTrue(calendarRow(app, "Silent film night").waitForExistence(timeout: 10), "and the night is on the calendar")
        capture(app, "105 Approved onto the calendar")
    }

    /// Invite by username — refused in the server's words, then sent — and
    /// take the invitation back.
    func testAnAdminInvitesAndRescinds() {
        let app = launch()
        openMembers(app)
        let door = app.buttons["membersInvite"]
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        XCTAssertTrue(door.label.contains("1 invited"), door.label)
        door.tap()
        XCTAssertTrue(app.navigationBars["Invite a member"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["inviteRescind-ivy"].waitForExistence(timeout: 10), "the invitation already out")

        let field = app.textFields["inviteUsername"]
        field.tap()
        field.typeText("@lena")
        app.buttons["inviteSend"].tap()
        XCTAssertTrue(said(app, "Already in this patch"))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        field.typeText("noor")
        app.buttons["inviteSend"].tap()
        XCTAssertTrue(said(app, "Invitation sent"))
        let noor = app.buttons["inviteRescind-noor"]
        XCTAssertTrue(noor.waitForExistence(timeout: 10), "the new invitation is listed")
        capture(app, "106 Invited")

        noor.tap()
        confirm(app, "Rescind")
        XCTAssertTrue(said(app, "Invitation rescinded"))
        XCTAssertFalse(app.buttons["inviteRescind-noor"].exists)
        XCTAssertTrue(app.buttons["inviteRescind-ivy"].exists)
    }

    /// Remove a member from the roster's swipe and reinstate them from the
    /// removed list.
    func testAnAdminRemovesAndReinstates() {
        let app = launch()
        openMembers(app)
        XCTAssertFalse(app.buttons["membersRemoved"].label.isEmpty)
        // Never offered on yourself is `PatchAdminTests`' to check: a row
        // with no acts takes a swipe or a long press as a tap and opens the
        // profile, so there is nothing here to look for.
        XCTAssertTrue(memberRow(app, "Sample Reader").waitForExistence(timeout: 10))
        let lena = memberRow(app, "Lena Fox")
        XCTAssertTrue(lena.waitForExistence(timeout: 10))
        lena.swipeLeft()
        let remove = app.buttons["Remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "can’t rejoin unless an admin reinstates them")).firstMatch
            .waitForExistence(timeout: 5), "the confirmation says what removing does")
        capture(app, "107 Removing")
        confirm(app, "Remove")
        XCTAssertTrue(said(app, "Member removed"))
        XCTAssertFalse(memberRow(app, "Lena Fox").exists)

        let removed = app.buttons["membersRemoved"]
        XCTAssertTrue(wait(removed, label: "2"))
        removed.tap()
        XCTAssertTrue(app.navigationBars["Removed members"].waitForExistence(timeout: 10))
        let reinstate = app.buttons["reinstate-lena"]
        XCTAssertTrue(reinstate.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["reinstate-max"].exists)
        reinstate.tap()
        confirm(app, "Reinstate")
        XCTAssertTrue(said(app, "Member reinstated"))
        XCTAssertFalse(app.buttons["reinstate-lena"].exists)
        capture(app, "108 Reinstated")
    }

    // MARK: Helpers

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro", "--preview-admin"]
        app.launch()
        let explore = app.buttons["exploreQuilt"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        explore.tap()
        XCTAssertTrue(app.navigationBars["Sample quilt"].waitForExistence(timeout: 10))
        signIn(app)
        return app
    }

    private func openDashboard(_ app: XCUIApplication) {
        let dashboard = app.tabBars.buttons["Dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
        dashboard.tap()
    }

    private func openClub(_ app: XCUIApplication) {
        let club = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "dashboardRow", "Film Club")).firstMatch
        XCTAssertTrue(scroll(app, to: club))
        club.tap()
        XCTAssertTrue(app.buttons["closePatch"].waitForExistence(timeout: 10))
        pullUp(app)
    }

    private func openMembers(_ app: XCUIApplication) {
        openDashboard(app)
        openClub(app)
        let members = app.buttons["glimpseDoor-Members"]
        XCTAssertTrue(scroll(app, to: members))
        members.tap()
        XCTAssertTrue(app.navigationBars["Members"].waitForExistence(timeout: 10))
    }

    /// Answers the web's "Are you sure?" with the act's own word — the
    /// dialog's button, never the row's button wearing the same word.
    private func confirm(_ app: XCUIApplication, _ word: String) {
        XCTAssertTrue(app.staticTexts["Are you sure?"].waitForExistence(timeout: 5))
        let rows = ["join", "reinstate", "invite", "member", "suggestion"]
        let button = app.buttons.matching(NSPredicate(format: "label == %@", word)).allElementsBoundByIndex.last { element in
            element.isHittable && !rows.contains { element.identifier.hasPrefix($0) }
        }
        XCTAssertNotNil(button, "the confirmation offers \(word)")
        button?.tap()
    }

    /// A line the screen says, wherever it sits.
    private func said(_ app: XCUIApplication, _ text: String, timeout: TimeInterval = 10) -> Bool {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.waitForExistence(timeout: timeout)
    }

    private func memberRow(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "memberRow", name)).firstMatch
    }

    private func calendarRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "calendarRow", title)).firstMatch
    }

    /// Drags the sheet itself up, as `GovernanceFlowTests` explains:
    /// `app.swipeUp()` misses a docked profile on a tall phone.
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

    private func scroll(_ app: XCUIApplication, to element: XCUIElement, up: Bool = false, swipes: Int = 8) -> Bool {
        let clear = { element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 40 }
        for _ in 0..<swipes {
            if clear() { return true }
            if up { app.swipeDown() } else { app.swipeUp() }
        }
        return clear()
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
