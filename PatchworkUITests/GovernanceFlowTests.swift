// SPDX-License-Identifier: MPL-2.0

import XCTest

/// Voting, an election's ballot and the discussion, end to end over the
/// fixtures. `--preview-member` signs the fixture reader in as a member of
/// Common Thread, where the proposals are; the reader still follows the
/// Listening Room, whose patch keeps followers out of its proposals.
final class GovernanceFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// The governance home says a vote is owed and opens the open list; the
    /// proposal's three buttons cast and change the vote, the filled one
    /// moves, and the counts move with it.
    func testVoteAndChangeTheVote() {
        let app = launch(member: true)
        openGovernance(app, tile: "quiltTile-common-thread")
        let owed = app.buttons["needsYourVote"]
        XCTAssertTrue(owed.waitForExistence(timeout: 10), "a member who owes a ballot is told so first")
        XCTAssertTrue(owed.label.contains("1 proposal needs your vote"))
        capture(app, "60 Governance with a vote owed")
        owed.tap()
        XCTAssertTrue(app.navigationBars["Proposals"].waitForExistence(timeout: 10))
        let row = proposalRow(app, "Add a Tuesday evening session")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("left"), "an open row says how long it has")
        capture(app, "61 Open proposals")
        row.tap()

        let approve = app.buttons["voteApprove"]
        XCTAssertTrue(approve.waitForExistence(timeout: 10))
        XCTAssertTrue(wait(app.staticTexts["proposalBanner"], label: "Cast your vote below."), "the banner points at the buttons")
        let counts = app.staticTexts["voteCounts"]
        XCTAssertEqual(counts.label, "4 approve · 1 reject · 0 abstain")
        capture(app, "62 A proposal with its buttons")

        approve.tap()
        XCTAssertTrue(wait(app.buttons["voteApprove"], label: "Approved"), "the filled button says what happened")
        XCTAssertTrue(wait(counts, label: "5 approve · 1 reject"))
        capture(app, "63 After a vote")

        app.buttons["voteReject"].tap()
        XCTAssertTrue(wait(app.buttons["voteReject"], label: "Rejected"), "tapping another changes the vote, with no confirmation")
        XCTAssertTrue(wait(app.buttons["voteApprove"], labelIs: "Approve"), "and the one that was filled goes back to its present tense")
        XCTAssertTrue(wait(counts, label: "4 approve · 2 reject"))

        let voters = app.buttons["showVoters"]
        XCTAssertTrue(scroll(app, to: voters))
        voters.tap()
        XCTAssertTrue(app.descendants(matching: .any)["voterRow"].firstMatch.waitForExistence(timeout: 5))
        let uncounted = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "voterRow", "not counted")).firstMatch
        XCTAssertTrue(scroll(app, to: uncounted), "a ballot from somebody who left is shown and not counted")

        // The card's buttons scroll away and the bar at the foot takes over.
        let bar = app.descendants(matching: .any)["voteBar"]
        for _ in 0..<6 where !bar.exists { app.swipeUp() }
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "the bar stands in for the buttons once they are off screen")
        XCTAssertTrue(app.buttons["bar-voteReject"].exists, "with the three buttons in it")
        capture(app, "64 The bottom bar")
    }

    /// Approval voting: tick a second candidate, save the whole set, and the
    /// slate says so; then stand in the election still taking names, and
    /// withdraw.
    func testElectionBallotAndStanding() {
        let app = launch(member: true)
        openGovernance(app, tile: "quiltTile-common-thread")
        openProposals(app)
        let row = proposalRow(app, "Studio council election")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        XCTAssertTrue(app.staticTexts["electionTurnout"].waitForExistence(timeout: 10))
        let tick = app.descendants(matching: .any)["ballotTick-cand-theo"]
        XCTAssertTrue(scroll(app, to: tick), "the box is the vote control")
        XCTAssertTrue(app.staticTexts["approvals-cand-theo"].label.contains("1 approval"))
        tick.tap()
        let save = app.buttons["ballotSave"]
        XCTAssertTrue(scroll(app, to: save))
        XCTAssertTrue(save.label.contains("Update my ballot"), "the reader's ballot is already in, seeded from the server")
        XCTAssertTrue(save.isEnabled)
        capture(app, "65 The election ballot")
        save.tap()
        XCTAssertTrue(wait(app.staticTexts["approvals-cand-theo"], label: "2 approvals"), "the whole set was sent and counted")
        XCTAssertTrue(app.staticTexts["ballotIn"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ballotIn"].label.contains("Your ballot is in."))
        capture(app, "66 Your ballot is in")

        // The contest still taking names, reached from the governance home.
        app.navigationBars["Proposal"].buttons["BackButton"].tap()
        XCTAssertTrue(app.navigationBars["Proposals"].waitForExistence(timeout: 5))
        app.navigationBars["Proposals"].buttons["BackButton"].tap()
        let nominating = app.buttons["electionNominating"]
        XCTAssertTrue(scroll(app, to: nominating, up: true), "the home offers the contest taking names")
        nominating.tap()
        let stand = app.buttons["standForElection"]
        XCTAssertTrue(scroll(app, to: stand))
        let statement = app.textFields["candidateStatement"]
        statement.tap()
        statement.typeText("I can do the sums.")
        stand.tap()
        XCTAssertTrue(app.staticTexts["You are standing in this election."].waitForExistence(timeout: 10))
        capture(app, "67 Standing")
        app.buttons["withdrawCandidacy"].tap()
        XCTAssertTrue(app.buttons["standForElection"].waitForExistence(timeout: 10), "and the name can be taken back while nominations are open")
    }

    /// The discussion: a comment posted appears in the thread, and a reaction
    /// moves its chip's count.
    func testCommentAndReact() {
        let app = launch(member: true)
        openGovernance(app, tile: "quiltTile-common-thread")
        openProposals(app)
        let row = proposalRow(app, "Add a Tuesday evening session")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["voteApprove"].waitForExistence(timeout: 10))

        let heading = app.staticTexts["discussionHeading"]
        XCTAssertTrue(scroll(app, to: heading))
        XCTAssertEqual(heading.label, "Discussion (3)", "items and their replies")

        let thumbs = app.buttons.matching(identifier: "reaction-\u{1F44D}").firstMatch
        XCTAssertTrue(scroll(app, to: thumbs))
        XCTAssertTrue(thumbs.label.contains("Thumbs up, 1"))
        thumbs.tap()
        XCTAssertTrue(wait(app.buttons.matching(identifier: "reaction-\u{1F44D}").firstMatch, label: "Thumbs up, 2"), "a reaction moves the count")

        let field = app.textFields["commentField"]
        XCTAssertTrue(scroll(app, to: field))
        field.tap()
        field.typeText("Count me in for the first Tuesday.")
        app.buttons["commentPost"].tap()
        XCTAssertTrue(app.staticTexts["Count me in for the first Tuesday."].waitForExistence(timeout: 10), "the comment is in the thread")
        capture(app, "68 The discussion")
    }

    /// Signed out: the vote is readable, the buttons are not there, and the
    /// one door is the sign-in sheet. Nothing about commenting is offered.
    func testSignedOutSeesNoButtonsAndOneDoor() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro"]
        app.launch()
        openSampleQuilt(app)
        openGovernance(app, tile: "quiltTile-common-thread")
        XCTAssertFalse(app.buttons["needsYourVote"].exists)
        openProposals(app)
        let row = proposalRow(app, "Add a Tuesday evening session")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.staticTexts["voteCounts"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["voteApprove"].exists, "no buttons without a session")
        let door = app.buttons["signInToVote"]
        XCTAssertTrue(scroll(app, to: door))
        capture(app, "69 Signed out")
        XCTAssertFalse(app.textFields["commentField"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["voteBar"].exists)
        door.tap()
        XCTAssertTrue(app.textFields["signInEmail"].waitForExistence(timeout: 5), "the door is the sign-in sheet")
    }

    /// A follower of a patch that keeps followers out of its proposals reads
    /// the vote and the thread, is told membership is what votes, and is
    /// offered no composer and no reaction to press.
    func testAFollowerReadsButDoesNotTakePart() {
        let app = launch(member: false)
        openGovernance(app, tile: "quiltTile-listening-room")
        openProposals(app)
        let row = proposalRow(app, "Move the listening night to Thursdays")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.staticTexts["voteCounts"].waitForExistence(timeout: 10))
        XCTAssertTrue(scroll(app, to: app.staticTexts["becomeAMember"]), "a follower is told what votes here")
        XCTAssertFalse(app.buttons["voteApprove"].exists)
        let thumbs = app.buttons.matching(identifier: "reaction-\u{1F44D}").firstMatch
        XCTAssertTrue(scroll(app, to: thumbs))
        XCTAssertFalse(thumbs.isEnabled, "a chip somebody used is shown, and cannot be pressed")
        XCTAssertFalse(app.buttons.matching(identifier: "reaction-\u{1F44E}").firstMatch.exists, "unused chips are not shown")
        XCTAssertFalse(app.textFields["commentField"].exists, "the patch keeps followers out, so no composer")
        capture(app, "70 A follower")
    }

    // MARK: Helpers

    private func launch(member: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro"] + (member ? ["--preview-member"] : [])
        app.launch()
        openSampleQuilt(app)
        signIn(app)
        return app
    }

    private func openGovernance(_ app: XCUIApplication, tile: String) {
        let patch = app.buttons[tile]
        XCTAssertTrue(patch.waitForExistence(timeout: 10))
        patch.tap()
        XCTAssertTrue(app.buttons["closePatch"].waitForExistence(timeout: 10))
        app.swipeUp()
        let governance = app.buttons["glimpseDoor-Governance"]
        XCTAssertTrue(scroll(app, to: governance))
        governance.tap()
        XCTAssertTrue(app.navigationBars["Governance"].waitForExistence(timeout: 10))
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
        // Clear of the foot of the screen, too: a List reports a row as
        // hittable while it is half under the home indicator.
        let clear = { element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 40 }
        for _ in 0..<swipes {
            if clear() { return true }
            if up { app.swipeDown() } else { app.swipeUp() }
        }
        return clear()
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

    private func wait(_ element: XCUIElement, labelIs label: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
