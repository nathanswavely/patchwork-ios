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

    // MARK: - Creating a patch

    /// The fork, the form with a confirmed point and a tag, and the new
    /// patch docked with its creator as its admin.
    func testCreateAPatchAndLandOnItAsItsAdmin() {
        let app = launch()
        signIn(app)
        openAddPatch(app)
        let run = app.buttons["forkRun"]
        XCTAssertTrue(run.waitForExistence(timeout: 5), "the fork comes first")
        XCTAssertTrue(app.buttons["forkSuggest"].exists)
        capture(app, "G3 Is this your patch to run?")
        run.tap()

        XCTAssertTrue(app.staticTexts["patchFormHeading"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["policy-invite_only"].isSelected, "invite only is preselected")
        let name = app.textFields["patchName"]
        name.tap()
        name.typeText("Night Market\n")
        let address = app.textFields["patchAddress"]
        address.tap()
        address.typeText("12 Example Street\n")
        let suggestion = app.descendants(matching: .any)["placeSuggestion"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10), "leaving the address proposes a point")
        XCTAssertFalse(app.descendants(matching: .any)["placedOnMap"].exists, "and proposing is not placing")
        capture(app, "G4 A suggested point")
        let use = app.buttons["savePlacement"]
        XCTAssertEqual(use.label, "Use this spot")
        use.tap()
        XCTAssertTrue(app.descendants(matching: .any)["placedOnMap"].waitForExistence(timeout: 5), "confirmed, it is on the map")

        let craft = app.buttons["tagChoice-craft"]
        XCTAssertTrue(scroll(app, to: craft))
        craft.tap()
        XCTAssertTrue(app.buttons["pickedTag-craft"].waitForExistence(timeout: 5))
        let minimal = app.buttons["template-minimal"]
        XCTAssertTrue(scroll(app, to: minimal))
        XCTAssertTrue(minimal.isSelected, "Minimal is the default template")
        capture(app, "G5 The form, filled")
        app.buttons["patchFormSubmit"].tap()

        XCTAssertTrue(app.scrollViews["patchProfile"].waitForExistence(timeout: 10), "the new patch docks")
        XCTAssertTrue(app.staticTexts["Night Market"].waitForExistence(timeout: 5))
        XCTAssertTrue(wait(app.descendants(matching: .any)["relationshipNote"], label: "Patch created"))
        XCTAssertTrue(wait(app.buttons["relationshipControl"], label: "Admin"), "its creator is its admin")
        capture(app, "G6 The new patch, docked")
    }

    // MARK: - Suggesting a patch

    /// A name the quilt already holds is refused with a door to the patch it
    /// collided with; a new one waits for an admin.
    func testSuggestAPatchAndMeetTheOneThatExists() {
        let app = launch()
        signIn(app)
        openAddPatch(app)
        app.buttons["forkSuggest"].tap()
        XCTAssertTrue(app.staticTexts["suggestHeading"].waitForExistence(timeout: 5))
        XCTAssertTrue(wait(app.staticTexts["suggestReviewNote"], label: "An instance admin reviews suggestions"), "the fixture reader is not trusted")
        let name = app.textFields["suggestName"]
        name.tap()
        name.typeText("Common Thread")
        app.buttons["suggestSubmit"].tap()
        let error = app.descendants(matching: .any)["suggestError"]
        XCTAssertTrue(wait(error, label: "A patch with a similar name already exists."))
        let door = app.buttons["openExistingPatch"]
        XCTAssertTrue(door.waitForExistence(timeout: 5), "the patch it collided with is a door")
        capture(app, "G7 A name the quilt already holds")
        door.tap()
        XCTAssertTrue(app.scrollViews["patchProfile"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Common Thread Studio"].waitForExistence(timeout: 5), "and it opens the patch that exists")
        app.buttons["closePatch"].tap()

        openAddPatch(app)
        app.buttons["forkSuggest"].tap()
        let again = app.textFields["suggestName"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap()
        again.typeText("Gallery Row")
        app.buttons["suggestSubmit"].tap()
        XCTAssertTrue(wait(app.staticTexts["suggestWaiting"], label: "An admin will review it"), "a suggestion waits for review")
        capture(app, "G8 Suggested")
        app.buttons["suggestDone"].tap()
        XCTAssertFalse(app.staticTexts["suggestWaiting"].waitForExistence(timeout: 2))
    }

    // MARK: - Helpers

    func openAddPatch(_ app: XCUIApplication) {
        app.buttons["Account"].tap()
        let add = app.buttons["accountAddPatch"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
    }

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
