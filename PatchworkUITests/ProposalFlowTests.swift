// SPDX-License-Identifier: MPL-2.0

import XCTest

/// Raising a proposal and withdrawing it, end to end over the fixtures.
/// `--preview-member` makes the fixture reader a member of Common Thread,
/// which votes by majority with a two-week window; `--preview-admin` makes
/// them an admin of the Film Club, whose admins decide; a plain sign-in
/// follows the Listening Room.
final class ProposalFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// A member proposes an Action, lands on its screen with the vote open,
    /// finds the governance room counting it, and withdraws it.
    func testAMemberProposesAndWithdraws() {
        let app = launch(["--preview-member"])
        openGovernance(app, tile: "quiltTile-common-thread")
        let owed = app.buttons["needsYourVote"]
        XCTAssertTrue(owed.waitForExistence(timeout: 10))
        XCTAssertTrue(owed.label.contains("1 proposal needs your vote"))

        let door = app.buttons["proposalDoor"]
        XCTAssertTrue(door.waitForExistence(timeout: 10), "a member finds the door in the bar")
        XCTAssertEqual(door.label, "New proposal")
        door.tap()
        let heading = app.staticTexts["proposalFormHeading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, "New proposal")
        let duration = app.buttons["proposalDuration"]
        XCTAssertTrue(duration.waitForExistence(timeout: 5))
        XCTAssertTrue(duration.label.contains("2 weeks"), "the window starts on the patch's own default, not 72 hours")

        let title = app.textFields["proposalTitle"]
        title.tap()
        title.typeText("Tape for the loom")
        let body = app.textFields["proposalBody"]
        body.tap()
        body.typeText("We keep running out of **masking** tape.")
        app.segmentedControls["proposalWritePreview"].buttons["Preview"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["proposalPreview"].waitForExistence(timeout: 5), "the preview draws the Markdown")
        capture(app, "90 A new proposal")
        let submit = app.buttons["proposalFormSubmit"]
        XCTAssertEqual(submit.label, "Submit proposal")
        submit.tap()

        XCTAssertTrue(app.navigationBars["Proposal"].waitForExistence(timeout: 10), "the new proposal opens on its own screen")
        let banner = app.staticTexts["proposalBanner"]
        XCTAssertTrue(wait(banner, label: "Voting is open. 14 days left."), "born voting, with the patch's window")
        XCTAssertTrue(app.buttons["voteApprove"].waitForExistence(timeout: 10), "and the vote is open to its author")
        XCTAssertTrue(app.buttons["proposalWithdraw"].exists, "the author may take it back")
        capture(app, "91 The new proposal, voting")

        app.navigationBars["Proposal"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Governance"].waitForExistence(timeout: 10))
        XCTAssertTrue(wait(app.buttons["needsYourVote"], label: "2 proposals need your vote"), "the room counts it")
        openProposals(app)
        let row = proposalRow(app, "Tape for the loom")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "and lists it")
        row.tap()

        let withdraw = app.buttons["proposalWithdraw"]
        XCTAssertTrue(withdraw.waitForExistence(timeout: 10))
        withdraw.tap()
        let confirm = app.buttons["Withdraw"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "the web's confirmation")
        XCTAssertTrue(app.staticTexts["Are you sure?"].exists)
        capture(app, "92 Withdrawing")
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Proposals"].waitForExistence(timeout: 10), "the screen leaves")
        XCTAssertTrue(proposalRow(app, "Add a Tuesday evening session").waitForExistence(timeout: 10))
        XCTAssertFalse(proposalRow(app, "Tape for the loom").exists, "and the open list no longer holds it")
    }

    /// An admin of a patch whose admins decide applies a change directly:
    /// the door, the form and the act never say propose or vote, no window
    /// is asked for, and the change is in effect on arrival.
    func testAnAdminAppliesAChangeDirectly() {
        let app = launch(["--preview-admin"])
        let dashboard = app.tabBars.buttons["Dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
        dashboard.tap()
        let club = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "dashboardRow", "Film Club")).firstMatch
        XCTAssertTrue(club.waitForExistence(timeout: 10))
        club.tap()
        XCTAssertTrue(app.buttons["closePatch"].waitForExistence(timeout: 10))
        pullUp(app)
        let governance = app.buttons["glimpseDoor-Governance"]
        XCTAssertTrue(scroll(app, to: governance))
        governance.tap()
        XCTAssertTrue(app.navigationBars["Governance"].waitForExistence(timeout: 10))

        let door = app.buttons["proposalDoor"]
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        XCTAssertEqual(door.label, "New change", "a direct change is not called a proposal")
        door.tap()
        let heading = app.staticTexts["proposalFormHeading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, "New change")
        let applyNow = app.buttons["proposalApplyNow"]
        XCTAssertTrue(applyNow.exists)
        XCTAssertTrue(applyNow.isSelected, "applying now is where an admin starts")
        XCTAssertFalse(app.buttons["proposalDuration"].exists, "no window for a change nobody votes on")
        let submit = app.buttons["proposalFormSubmit"]
        XCTAssertEqual(submit.label, "Apply change")
        for words in [heading.label, submit.label, door.label] {
            XCTAssertFalse(words.localizedCaseInsensitiveContains("vote"), words)
            XCTAssertFalse(words.localizedCaseInsensitiveContains("propos"), words)
        }

        let title = app.textFields["proposalTitle"]
        title.tap()
        title.typeText("Screen on the first Friday")
        capture(app, "93 A new change")
        submit.tap()

        XCTAssertTrue(app.navigationBars["Proposal"].waitForExistence(timeout: 10))
        XCTAssertTrue(wait(app.staticTexts["proposalBanner"], label: "This change is in effect."))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Applied by")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["voteCounts"].exists, "there was no vote")
        XCTAssertFalse(app.buttons["proposalWithdraw"].exists, "an applied change is not open")
        capture(app, "94 The change, in effect")
    }

    /// A follower is shown no door, on the governance room or in the
    /// proposals, and is told once what opens it.
    func testAFollowerIsShownNoDoor() {
        let app = launch([])
        openGovernance(app, tile: "quiltTile-listening-room")
        XCTAssertTrue(app.buttons["governanceProposals"].waitForExistence(timeout: 10), "the overview has answered")
        XCTAssertFalse(app.buttons["proposalDoor"].exists)
        openProposals(app)
        XCTAssertTrue(proposalRow(app, "Move the listening night to Thursdays").waitForExistence(timeout: 10))
        let line = app.staticTexts["proposalFollowerLine"]
        XCTAssertTrue(scroll(app, to: line))
        XCTAssertEqual(line.label, "Become a member to create proposals and vote.")
        XCTAssertFalse(app.buttons["proposalDoor"].exists, "following carries no authorship")
        capture(app, "95 No door for a follower")
    }

    // MARK: Helpers

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro"] + extra
        app.launch()
        app.buttons["quiltChoice"].firstMatch.tap()
        let explore = app.buttons["exploreQuilt"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        explore.tap()
        XCTAssertTrue(app.navigationBars["Sample quilt"].waitForExistence(timeout: 10))
        signIn(app)
        return app
    }

    private func openGovernance(_ app: XCUIApplication, tile: String) {
        let patch = app.buttons[tile]
        XCTAssertTrue(patch.waitForExistence(timeout: 10))
        patch.tap()
        XCTAssertTrue(app.buttons["closePatch"].waitForExistence(timeout: 10))
        pullUp(app)
        let governance = app.buttons["glimpseDoor-Governance"]
        XCTAssertTrue(scroll(app, to: governance))
        governance.tap()
        XCTAssertTrue(app.navigationBars["Governance"].waitForExistence(timeout: 10))
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

    private func openProposals(_ app: XCUIApplication) {
        let rooms = app.buttons["governanceProposals"]
        XCTAssertTrue(scroll(app, to: rooms))
        rooms.tap()
        XCTAssertTrue(app.navigationBars["Proposals"].waitForExistence(timeout: 10))
    }

    private func proposalRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "proposalRow", title)).firstMatch
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
