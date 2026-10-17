// SPDX-License-Identifier: MPL-2.0

import XCTest

/// The rest of a patch admin's tools, end to end over the fixtures.
/// `--preview-admin` makes the fixture reader an admin of the Film Club,
/// whose board holds three reports waiting (one about a notice, one about a
/// reply, one about a notice already gone), and whose rules make it a
/// maintainer's, so a promotion is honoured there.
final class PatchSettingsFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// From the Dashboard's ask: switch replies off over a reported reply,
    /// remove a reported notice behind its second confirmation, and find the
    /// first one under Resolved with its note.
    func testAnAdminReviewsReportsFromTheDashboard() {
        let app = launch()
        openDashboard(app)
        let ask = app.buttons["dashboardReports-extra-7"]
        XCTAssertTrue(ask.waitForExistence(timeout: 10), "the reports are asked of the admin")
        XCTAssertTrue(ask.label.contains("3 reports to review"), ask.label)
        ask.tap()

        XCTAssertTrue(app.navigationBars["Reports"].waitForExistence(timeout: 10))
        XCTAssertTrue(said(app, "reported by Lena Fox"))
        XCTAssertTrue(said(app, "Already taken down."), "a report about something gone says so")
        capture(app, "110 Reports")

        let reply = app.buttons["reportReview-report-f2"]
        XCTAssertTrue(reply.waitForExistence(timeout: 10))
        reply.tap()
        XCTAssertTrue(app.staticTexts["reviewReportHeading"].waitForExistence(timeout: 5))
        app.buttons["reportAction-close_replies"].tap()
        let note = app.textFields["reportNote"]
        note.tap()
        note.typeText("Cooling off for a week.")
        capture(app, "111 Reviewing a report")
        app.buttons["reportConfirm"].tap()
        XCTAssertTrue(said(app, "Report reviewed"))
        XCTAssertFalse(app.buttons["reportReview-report-f2"].exists, "off the queue at once")

        app.buttons["reportReview-report-f1"].tap()
        XCTAssertTrue(app.staticTexts["reviewReportHeading"].waitForExistence(timeout: 5))
        app.buttons["reportAction-remove"].tap()
        app.buttons["reportConfirm"].tap()
        let removal = app.buttons["Yes, remove it"]
        XCTAssertTrue(removal.waitForExistence(timeout: 5), "removing asks once more")
        removal.tap()
        XCTAssertTrue(said(app, "Report reviewed"))
        XCTAssertFalse(app.buttons["reportReview-report-f1"].exists)

        app.segmentedControls.buttons["Resolved"].tap()
        XCTAssertTrue(said(app, "Note: Cooling off for a week."), "the reviewed report keeps its note")
        capture(app, "112 Resolved")
    }

    /// From the board's own door: only admins put up notices, and the
    /// board's line says so.
    func testAnAdminChangesWhoPutsUpNotices() {
        let app = launch()
        openDashboard(app)
        openClub(app)
        let board = app.buttons["glimpseDoor-Noticeboard"]
        XCTAssertTrue(scroll(app, to: board))
        board.tap()
        XCTAssertTrue(app.navigationBars["Noticeboard"].waitForExistence(timeout: 10))
        let settings = app.buttons["noticeboardSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "the board's admin has its settings")
        XCTAssertTrue(app.buttons["noticeboardReports"].exists)
        settings.tap()

        XCTAssertTrue(app.navigationBars["Noticeboard settings"].waitForExistence(timeout: 10))
        app.segmentedControls.buttons["Admins only"].tap()
        XCTAssertTrue(said(app, "Only admins put up notices now"))
        capture(app, "113 Noticeboard settings")
        app.navigationBars["Noticeboard settings"].buttons.element(boundBy: 0).tap()
        let hint = app.staticTexts["noticeboardHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 10))
        XCTAssertTrue(wait(hint, label: "Its admins put up the notices."), "the board reads the setting again")
    }

    /// Promote a member from the row's swipe, then make them a member again
    /// from its long press.
    func testAnAdminPromotesAMemberAndMakesThemAMemberAgain() {
        let app = launch()
        openDashboard(app)
        openClub(app)
        let members = app.buttons["glimpseDoor-Members"]
        XCTAssertTrue(scroll(app, to: members))
        members.tap()
        XCTAssertTrue(app.navigationBars["Members"].waitForExistence(timeout: 10))
        let lena = memberRow(app, "Lena Fox")
        XCTAssertTrue(lena.waitForExistence(timeout: 10))
        XCTAssertTrue(lena.label.contains("Member"), lena.label)
        lena.swipeLeft()
        let promote = app.buttons["Promote to admin"]
        XCTAssertTrue(promote.waitForExistence(timeout: 5), "the club's rules let an admin make one")
        promote.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "aren’t notified")).firstMatch
            .waitForExistence(timeout: 5), "the confirmation says what the role carries")
        capture(app, "114 Promoting")
        confirm(app, "Promote to admin")
        XCTAssertTrue(said(app, "Role updated"))
        XCTAssertTrue(wait(memberRow(app, "Lena Fox"), label: "Admin"))

        memberRow(app, "Lena Fox").press(forDuration: 1.0)
        let demote = app.buttons["Make member"]
        XCTAssertTrue(demote.waitForExistence(timeout: 5))
        demote.tap()
        confirm(app, "Make member")
        XCTAssertTrue(said(app, "Role updated"))
        XCTAssertTrue(wait(memberRow(app, "Lena Fox"), label: "Member"))
        capture(app, "115 A member again")
    }

    /// Edit patch from the cover's ⋯: rename it and stop taking suggestions,
    /// and land back on the profile with the new name.
    func testAnAdminEditsThePatch() {
        let app = launch()
        openDashboard(app)
        openClub(app)
        openEditForm(app)
        let name = app.textFields["patchName"]
        XCTAssertEqual(name.value as? String, "Film Club", "the form is filled from the patch")
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "Society\n")
        let suggestions = app.switches["acceptSuggestions"]
        XCTAssertTrue(scroll(app, to: suggestions))
        XCTAssertEqual(suggestions.value as? String, "1", "the club takes suggestions")
        // The switch itself sits at the row's trailing edge.
        suggestions.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(suggestions.value as? String, "0")
        XCTAssertTrue(app.descendants(matching: .any)["openPatchSettings"].exists, "the rest is the website's")
        capture(app, "116 Editing the patch")
        app.buttons["patchFormSubmit"].tap()

        XCTAssertTrue(app.staticTexts["Film Society"].waitForExistence(timeout: 10), "the profile reads the patch again")
        XCTAssertTrue(wait(app.descendants(matching: .any)["relationshipNote"], label: "Changes saved"))
        capture(app, "117 Saved")
    }

    /// The map picker, opened low in the form, is scrolled into view above
    /// the pinned Save bar, so its button takes the tap without any help.
    func testTheMapPickerScrollsIntoViewAboveTheSaveBar() {
        let app = launch()
        openDashboard(app)
        openClub(app)
        openEditForm(app)
        let put = app.buttons["putOnMap"]
        XCTAssertTrue(scroll(app, to: put))
        put.tap()
        let save = app.buttons["savePlacement"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let bar = app.buttons["patchFormSubmit"]
        let clear = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in save.frame.maxY <= bar.frame.minY }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [clear], timeout: 5), .completed, "the picker's buttons sit above the bar")
        capture(app, "118 The picker in view")
        save.tap()
        XCTAssertTrue(app.descendants(matching: .any)["placedOnMap"].waitForExistence(timeout: 5))
    }

    // MARK: Helpers

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro", "--preview-admin"]
        app.launch()
        app.buttons["quiltChoice"].firstMatch.tap()
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

    private func openEditForm(_ app: XCUIApplication) {
        let more = app.buttons["profileOverflow"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        let edit = app.buttons["editPatch"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "the patch's admin can edit it")
        edit.tap()
        XCTAssertTrue(wait(app.staticTexts["patchFormHeading"], label: "Edit patch"))
    }

    /// Answers "Are you sure?" with the act's own word — the dialog's
    /// button, never the row's button wearing the same word.
    private func confirm(_ app: XCUIApplication, _ word: String) {
        XCTAssertTrue(app.staticTexts["Are you sure?"].waitForExistence(timeout: 5))
        let button = app.buttons.matching(NSPredicate(format: "label == %@", word)).allElementsBoundByIndex.last { element in
            element.isHittable && !element.identifier.hasPrefix("member")
        }
        XCTAssertNotNil(button, "the confirmation offers \(word)")
        button?.tap()
    }

    private func said(_ app: XCUIApplication, _ text: String, timeout: TimeInterval = 10) -> Bool {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.waitForExistence(timeout: timeout)
    }

    private func memberRow(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "memberRow", name)).firstMatch
    }

    /// Drags the sheet itself up: `app.swipeUp()` misses a docked profile
    /// on a tall phone (see `GovernanceFlowTests`).
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
        let clear = { element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 120 }
        for _ in 0..<swipes {
            if clear() { return true }
            if up { app.swipeDown() } else { app.swipeUp() }
        }
        return clear()
    }

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
