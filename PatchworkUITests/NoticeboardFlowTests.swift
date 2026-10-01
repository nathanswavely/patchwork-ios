// SPDX-License-Identifier: MPL-2.0
import XCTest

/// The noticeboard, end to end over the fixtures: the door only a member is
/// shown, the board, a notice put up and answered, its replies switched off
/// and the notice taken down; a board whose admins put up the notices,
/// reached from the bell; a report; and the patch where the reader is only
/// a follower, which shows no door at all.
final class NoticeboardFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// A member of Common Thread: reads the board, puts up a notice that
    /// tells members, replies to it, switches its replies off, and takes it
    /// down again.
    func testAMemberPutsUpANoticeAndTakesItDown() {
        let app = launch(member: true)
        openProfile(app, tile: "quiltTile-common-thread")
        let door = app.buttons["glimpseDoor-Noticeboard"]
        XCTAssertTrue(scroll(app, to: door), "a member is shown the door")
        XCTAssertTrue(app.buttons.matching(identifier: "noticeChip").firstMatch.waitForExistence(timeout: 10),
                      "and the newest notices under it")
        capture(app, "71 The noticeboard glimpse")
        door.tap()
        XCTAssertTrue(app.navigationBars["Noticeboard"].waitForExistence(timeout: 10))
        let hint = app.staticTexts["noticeboardHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 10))
        XCTAssertEqual(hint.label, "Read by this patch’s admins and members, and nobody else.")
        let kiln = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "noticeRow", "The kiln is out of action")).firstMatch
        XCTAssertTrue(kiln.waitForExistence(timeout: 10))
        XCTAssertTrue(kiln.label.contains("members told"))
        XCTAssertTrue(kiln.label.contains("2 replies"))
        let keys = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "noticeRow", "Keys for Tuesday evenings")).firstMatch
        XCTAssertTrue(keys.label.contains("replies off · 1 kept"), "a closed notice says what it kept")
        capture(app, "72 The board")

        let putUp = app.buttons["putUpNotice"]
        XCTAssertTrue(putUp.waitForExistence(timeout: 5), "members put up notices here")
        putUp.tap()
        let title = app.textFields["noticeTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        // The switches first, while there is no keyboard: with one up, the
        // middle of the screen is the bar at the sheet's foot, and a swipe
        // that starts on a button scrolls nothing.
        let tell = app.switches["noticeTellMembers"]
        XCTAssertTrue(scroll(app, to: tell))
        XCTAssertEqual(tell.value as? String, "0", "quiet by default")
        XCTAssertEqual(app.switches["noticeTakeReplies"].value as? String, "1", "replies start where the patch starts them")
        flip(tell)
        XCTAssertEqual(tell.value as? String, "1")
        XCTAssertTrue(scroll(app, to: title, up: true))
        title.tap()
        title.typeText("Loom needs a new belt")
        let body = app.textFields["noticeBody"]
        body.tap()
        body.typeText("Ordering one this week.")
        capture(app, "73 Putting up a notice")
        app.buttons["noticeFormSubmit"].tap()

        // The form leaves and the notice itself arrives, saying what happened.
        let heading = app.staticTexts["noticeTitleText"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertEqual(heading.label, "Loom needs a new belt")
        XCTAssertTrue(wait(app.staticTexts["noticeStatus"], label: "Notice put up and members told"))
        XCTAssertTrue(app.buttons["noticeEdit"].exists, "the author may edit")
        XCTAssertFalse(app.buttons["noticeReport"].exists, "and is not offered a report of their own notice")

        let field = app.textFields["noticeReplyField"]
        XCTAssertTrue(scroll(app, to: field))
        XCTAssertEqual(app.staticTexts["repliesHeading"].label, "No replies")
        field.tap()
        field.typeText("I have a spare belt.")
        app.buttons["noticeReplyPost"].tap()
        XCTAssertTrue(app.staticTexts["I have a spare belt."].waitForExistence(timeout: 10), "the reply is under the notice")
        XCTAssertTrue(wait(app.staticTexts["repliesHeading"], label: "1 reply"))
        capture(app, "74 A notice with a reply")

        let switchReplies = app.buttons["noticeRepliesSwitch"]
        XCTAssertTrue(scroll(app, to: switchReplies, up: true))
        XCTAssertTrue(switchReplies.label.contains("Switch replies off"))
        switchReplies.tap()
        XCTAssertTrue(wait(app.buttons["noticeRepliesSwitch"], label: "Switch replies on"), "the switch says what it will do next")
        XCTAssertTrue(wait(app.staticTexts["noticeStatus"], label: "Replies are off. Existing replies stay."))
        XCTAssertFalse(app.textFields["noticeReplyField"].exists, "no box to reply in once replies are off")
        XCTAssertTrue(app.staticTexts["I have a spare belt."].exists || scroll(app, to: app.staticTexts["I have a spare belt."]),
                      "and the reply that was there stays")
        capture(app, "75 Replies switched off")

        let takeDown = app.buttons["noticeTakeDown"]
        XCTAssertTrue(scroll(app, to: takeDown, up: true))
        takeDown.tap()
        let confirm = app.buttons["Take it down"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Noticeboard"].waitForExistence(timeout: 10), "taking it down leads back to the board")
        XCTAssertTrue(kiln.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "noticeRow", "Loom needs a new belt")).firstMatch.exists,
                       "and the notice is gone from it")
    }

    /// The Repair Cafe's admins put up its notices. Its member is told of
    /// one by the bell, opens it there, reports it, and finds a board with
    /// a line saying who posts and no door to post with.
    func testTheBellOpensANoticeOnABoardItsAdminsWrite() {
        let app = launch(member: false)
        app.buttons["Account"].tap()
        let bell = app.buttons["notificationBell"]
        XCTAssertTrue(bell.waitForExistence(timeout: 5))
        bell.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 10))
        let row = app.buttons["notificationRow-notif-2"]
        XCTAssertTrue(scroll(app, to: row))
        row.tap()
        XCTAssertTrue(app.navigationBars["Notice"].waitForExistence(timeout: 10), "a notice opens natively, inside the sheet")
        let heading = app.staticTexts["noticeTitleText"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertEqual(heading.label, "Soldering irons are back")
        XCTAssertFalse(app.buttons["noticeEdit"].exists)
        XCTAssertFalse(app.buttons["noticeTakeDown"].exists, "a member manages nobody else's notice")
        capture(app, "76 A notice opened from the bell")

        let report = app.buttons["noticeReport"]
        XCTAssertTrue(scroll(app, to: report))
        report.tap()
        XCTAssertTrue(app.staticTexts["reportHeading"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["reportHeading"].label, "Report this notice")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "this patch’s admins")).firstMatch.exists,
                      "the sheet says who will read the report")
        capture(app, "77 Reporting a notice")
        app.buttons["reportSubmit"].tap()
        XCTAssertTrue(app.staticTexts["reportSentHeading"].waitForExistence(timeout: 10))
        app.buttons["reportDone"].tap()
        XCTAssertTrue(heading.waitForExistence(timeout: 10))

        app.navigationBars["Notice"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        let dashboard = app.tabBars.buttons["Dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
        dashboard.tap()
        let cafe = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "dashboardRow", "Repair Cafe")).firstMatch
        XCTAssertTrue(cafe.waitForExistence(timeout: 10))
        cafe.tap()
        XCTAssertTrue(app.buttons["closePatch"].waitForExistence(timeout: 10))
        app.swipeUp()
        let door = app.buttons["glimpseDoor-Noticeboard"]
        XCTAssertTrue(scroll(app, to: door))
        door.tap()
        XCTAssertTrue(app.navigationBars["Noticeboard"].waitForExistence(timeout: 10))
        let hint = app.staticTexts["noticeboardHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 10))
        XCTAssertTrue(hint.label.hasSuffix("Its admins put up the notices."))
        XCTAssertFalse(app.buttons["putUpNotice"].exists, "no door to post with where admins post")
        capture(app, "78 A board its admins write")
    }

    /// A follower is not in the room, and is shown no door — not a locked
    /// one, since the quilt will not say whether there is a board at all.
    func testAFollowerIsShownNoDoor() {
        let app = launch(member: false)
        openProfile(app, tile: "quiltTile-listening-room")
        XCTAssertTrue(scroll(app, to: app.buttons["glimpseDoor-Governance"]), "the rooms a follower may read are there")
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertFalse(app.buttons["glimpseDoor-Noticeboard"].exists)
        capture(app, "79 No noticeboard for a follower")
    }

    // MARK: Getting there

    private func launch(member: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro"] + (member ? ["--preview-member"] : [])
        app.launch()
        openSampleQuilt(app)
        signIn(app)
        return app
    }

    private func openProfile(_ app: XCUIApplication, tile: String) {
        let patch = app.buttons[tile]
        XCTAssertTrue(patch.waitForExistence(timeout: 10))
        patch.tap()
        XCTAssertTrue(app.buttons["closePatch"].waitForExistence(timeout: 10))
        app.swipeUp()
    }

    private func scroll(_ app: XCUIApplication, to element: XCUIElement, up: Bool = false, swipes: Int = 8) -> Bool {
        // Clear of the foot of the screen, too: a List reports a row as
        // hittable while it is half under the home indicator.
        let clear = { element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 40 }
        for _ in 0..<swipes {
            if clear() { return true }
            if up { app.swipeDown() } else { app.swipeUp() }
        }
        return clear()
    }

    /// A switch is flipped by its thumb: a tap on the row's middle lands on
    /// the label, which does nothing.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
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
