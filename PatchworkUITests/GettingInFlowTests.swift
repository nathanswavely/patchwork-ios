// SPDX-License-Identifier: MPL-2.0

import XCTest

/// Getting in, end to end over the fixtures: answering an invitation from
/// its notification, creating a patch, suggesting one, claiming one and
/// setting it up, and a first account's agreement line and Welcome.
/// `--preview-invited` has the Food Share's admins ask the fixture reader in.
final class GettingInFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    // MARK: - Invitations

    /// The notification docks the patch, the head offers Accept and Decline
    /// where Follow would be, and accepting makes the reader a member.
    func testAcceptAnInvitationFromItsNotification() {
        let app = launch(["--preview-invited"])
        signIn(app)
        let account = app.buttons["Account"]
        XCTAssertTrue(wait(account, label: "3 unread"), "the invitation is one more unread row")
        account.tap()
        app.buttons["notificationBell"].tap()
        let row = app.buttons["notificationRow-notif-7"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("You're invited to join Food Share"))
        row.tap()

        let label = app.staticTexts["invitedLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 10), "the profile docks with the invitation's answers in its head")
        XCTAssertEqual(label.label, "You've been invited to join")
        XCTAssertTrue(app.buttons["declineInvitation"].exists)
        XCTAssertFalse(app.buttons["relationshipFollow"].exists, "an invited reader is not offered Follow instead")
        capture(app, "G1 An invitation on the profile")
        app.buttons["acceptInvitation"].tap()

        XCTAssertTrue(wait(app.descendants(matching: .any)["relationshipNote"], label: "You are now a member"))
        let standing = app.buttons["relationshipControl"]
        XCTAssertTrue(wait(standing, label: "Member"), "the head wears the membership the quilt now holds")
        XCTAssertFalse(app.buttons["acceptInvitation"].exists)
        capture(app, "G2 A member by invitation")
    }

    /// Declining takes the answers away and leaves the patch as it was.
    func testDeclineAnInvitation() {
        let app = launch(["--preview-invited"])
        signIn(app)
        openPatch(app, named: "Food Share")
        let decline = app.buttons["declineInvitation"]
        XCTAssertTrue(decline.waitForExistence(timeout: 10))
        decline.tap()
        XCTAssertTrue(wait(app.descendants(matching: .any)["relationshipNote"], label: "Invitation declined"))
        XCTAssertFalse(app.buttons["acceptInvitation"].exists)
        XCTAssertTrue(app.buttons["relationshipFollow"].waitForExistence(timeout: 5), "and the patch offers what it offers anybody")
    }

    // MARK: - Helpers

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro"] + extra
        app.launch()
        app.buttons["quiltChoice"].firstMatch.tap()
        let explore = app.buttons["exploreQuilt"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        explore.tap()
        XCTAssertTrue(app.navigationBars["Sample quilt"].waitForExistence(timeout: 10))
        return app
    }

    func signIn(_ app: XCUIApplication, code: String = "123456") {
        app.buttons["Account"].tap()
        let start = app.buttons["Sign in"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let email = app.textFields["signInEmail"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("reader@example.org")
        app.buttons["signInSendCode"].tap()
        let field = app.textFields["signInCode"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(code)
        app.buttons["signInContinue"].tap()
        if code == "123456" {
            XCTAssertTrue(wait(app.buttons["Account"], label: "unread"), "signed in")
        }
    }

    /// By the top bar's field, which finds a patch wherever the canvas has
    /// put its tile.
    func openPatch(_ app: XCUIApplication, named name: String) {
        app.buttons["Search"].firstMatch.tap()
        let field = app.textFields["searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(name)
        let found = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "searchPatch", name)).firstMatch
        XCTAssertTrue(found.waitForExistence(timeout: 5))
        found.tap()
        XCTAssertTrue(app.scrollViews["patchProfile"].waitForExistence(timeout: 10))
    }

    func pullUp(_ app: XCUIApplication) {
        let profile = app.scrollViews["patchProfile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        let pulled = { profile.frame.minY < app.frame.height / 4 }
        for _ in 0..<3 where !pulled() {
            profile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
        }
        XCTAssertTrue(pulled(), "the profile pulls up to its full height")
    }

    func scroll(_ app: XCUIApplication, to element: XCUIElement, swipes: Int = 10) -> Bool {
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    func wait(_ element: XCUIElement, label: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    func named(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
