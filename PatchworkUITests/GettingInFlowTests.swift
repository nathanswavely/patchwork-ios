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
        // On a shorter phone the map's buttons arrive under the form's
        // pinned Create Patch bar, which would take the tap. The form is
        // dragged from its upper fields: a swipe through the middle lands
        // on the map and pans it instead.
        let bar = app.buttons["patchFormSubmit"]
        for _ in 0..<4 where use.frame.maxY > bar.frame.minY - 8 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
        }
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

    // MARK: - Claiming

    /// Claim the Evening Choir by email: the link is the browser's, coming
    /// back picks the approval up, and setup lands on the live patch with
    /// the reader as its admin.
    func testClaimByEmailAndSetItUp() {
        let app = launch()
        signIn(app)
        openPatch(app, named: "Evening Choir")
        let door = app.buttons["claimDoor"]
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        XCTAssertTrue(door.label.contains("If it's yours, claim it"))
        door.tap()

        let email = app.buttons["claimMethod-email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10), "the methods the listing takes")
        XCTAssertTrue(app.buttons["claimMethod-admin"].isEnabled)
        XCTAssertFalse(app.buttons["claimSubmit"].isEnabled, "nothing is preselected")
        email.tap()
        let address = app.textFields["claimEmail"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        address.typeText("songs@eveningchoir.example.org")
        capture(app, "G9 Claiming by email")
        app.buttons["claimSubmit"].tap()

        XCTAssertTrue(wait(app.staticTexts["claimEmailSent"], label: "songs@eveningchoir.example.org"))
        XCTAssertTrue(app.descendants(matching: .any)["claimBrowserNote"].exists, "the browser's part is said plainly")
        XCTAssertTrue(app.buttons["claimResend"].exists)
        XCTAssertTrue(app.buttons["claimWithdraw"].exists)
        capture(app, "G10 The link is in the email")

        // The emailed link is opened in the browser; offline, leaving the
        // app stands in for that, and coming back is when it is read.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(app.staticTexts["claimApprovedHeading"].waitForExistence(timeout: 15), "the approval is picked up on return")
        capture(app, "G11 Approved")
        app.buttons["claimSetUp"].tap()

        XCTAssertTrue(wait(app.staticTexts["patchFormHeading"], label: "Set up your patch"))
        XCTAssertTrue(app.staticTexts["setupSlug"].exists, "the patch's existing address")
        XCTAssertTrue(app.staticTexts["setupExpires"].exists)
        let seeded = app.staticTexts["policySeeded"]
        XCTAssertTrue(scroll(app, to: seeded))
        XCTAssertTrue(seeded.label.contains("Set by the Minimal template"))
        let casual = app.buttons["template-casual"]
        XCTAssertTrue(scroll(app, to: casual))
        casual.tap()
        XCTAssertTrue(app.buttons["policy-open"].isSelected, "the policy follows the template until it is answered")
        capture(app, "G12 Setting it up")
        app.buttons["patchFormSubmit"].tap()

        XCTAssertTrue(wait(app.descendants(matching: .any)["relationshipNote"], label: "This patch is yours", timeout: 15))
        XCTAssertTrue(wait(app.buttons["relationshipControl"], label: "Admin"))
        XCTAssertFalse(app.staticTexts["unclaimedNotice"].exists, "it is nobody's listing any more")
        capture(app, "G13 The patch is yours")
    }

    // MARK: - A first account

    /// The username step says what creating an account agrees to, and both
    /// documents open over it; the new account is welcomed once, and not
    /// again after the Welcome has been answered.
    func testANewAccountSeesTheAgreementAndTheWelcomeOnce() {
        let app = launch()
        signIn(app, code: "654321")
        let username = app.textFields["signInUsername"]
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        let line = app.staticTexts["agreementLine"]
        XCTAssertTrue(line.exists, "the agreement line sits under the act it is about")
        XCTAssertTrue(line.label.contains("By creating an account you agree to the User Agreement and Privacy Policy."))
        capture(app, "G14 The agreement line")
        let terms = app.links["User Agreement"]
        XCTAssertTrue(terms.waitForExistence(timeout: 5))
        terms.tap()
        XCTAssertTrue(app.navigationBars["User Agreement"].waitForExistence(timeout: 10), "the quilt's own document, natively")
        app.navigationBars["User Agreement"].buttons["Done"].tap()
        XCTAssertTrue(username.waitForExistence(timeout: 5), "and back to the step it interrupted")

        username.tap()
        username.typeText("new-reader")
        app.buttons["signInCreate"].tap()
        let heading = app.staticTexts["welcomeHeading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "a new account is welcomed")
        XCTAssertEqual(heading.label, "Welcome to Sample quilt")
        XCTAssertTrue(wait(app.staticTexts["welcomeLabel"], label: "This quilt is stewarded by Sample Steward"), "the Label's panel")
        XCTAssertTrue(app.staticTexts["What's expected here"].exists)
        XCTAssertTrue(app.staticTexts["Report harmful behavior instead of ignoring it"].exists)
        capture(app, "G15 Welcome")
        app.buttons["welcomeBuild"].tap()
        XCTAssertFalse(heading.waitForExistence(timeout: 2))
        XCTAssertTrue(app.tabBars.buttons["Discover"].isSelected, "Build your quilt hands on to Discover")

        // Out and back in as the same account: the Welcome was answered.
        app.buttons["Account"].tap()
        app.buttons["Sign out"].tap()
        signIn(app, code: "654321")
        let again = app.textFields["signInUsername"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap()
        again.typeText("new-reader")
        app.buttons["signInCreate"].tap()
        XCTAssertFalse(again.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["welcomeHeading"].waitForExistence(timeout: 4), "once is once")
    }

    // MARK: - Account invite links

    /// Signed out, a pasted link is checked against this quilt and the
    /// server, then makes an account, which is welcomed; signed in, there is
    /// no door to a second account.
    func testRedeemAnAccountInviteLink() {
        let app = launch()
        app.buttons["Account"].tap()
        let door = app.buttons["accountInvite"]
        XCTAssertTrue(door.waitForExistence(timeout: 5))
        door.tap()
        let link = app.textFields["inviteLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        link.typeText("https://other.example.org/invite/demo-invite")
        app.buttons["inviteContinue"].tap()
        XCTAssertTrue(wait(app.descendants(matching: .any)["inviteError"], label: "This link is for other.example.org"))

        paste(app, "https://quilt.example.org/invite/used-invite")
        XCTAssertTrue(wait(app.descendants(matching: .any)["inviteDead"], label: "This invite didn't work"))

        paste(app, "https://quilt.example.org/invite/demo-invite")
        let username = app.textFields["inviteUsername"]
        XCTAssertTrue(username.waitForExistence(timeout: 5), "a live link asks for a username")
        XCTAssertTrue(app.staticTexts["agreementLine"].exists)
        username.tap()
        username.typeText("invited-reader")
        let email = app.textFields["inviteEmail"]
        XCTAssertTrue(email.exists, "this quilt sends mail, so the address is the way back in")
        email.tap()
        email.typeText("invited@example.org")
        capture(app, "G16 An invite link")
        app.buttons["inviteCreate"].tap()

        let welcome = app.staticTexts["welcomeHeading"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 10), "the new account is welcomed")
        app.buttons["welcomeSkip"].tap()
        XCTAssertFalse(welcome.waitForExistence(timeout: 2))
        app.buttons["Account"].tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 5), "signed in as the new account")
        XCTAssertFalse(app.buttons["accountInvite"].exists, "and there is no door to a second account")
    }

    /// A fresh sheet for each link: a field's caret lands where it is
    /// tapped, so typing over what is there is not a reliable clear.
    func paste(_ app: XCUIApplication, _ text: String) {
        app.buttons["Cancel"].tap()
        app.buttons["Account"].tap()
        let door = app.buttons["accountInvite"]
        XCTAssertTrue(door.waitForExistence(timeout: 5))
        door.tap()
        let link = app.textFields["inviteLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        link.typeText(text)
        app.buttons["inviteContinue"].tap()
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
