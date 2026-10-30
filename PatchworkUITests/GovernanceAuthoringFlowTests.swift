// SPDX-License-Identifier: MPL-2.0

import XCTest

/// Deciding, nominating, amending a document, changing the rules and
/// writing a new document, end to end over the fixtures. `--preview-admin`
/// makes the fixture reader an admin of the Film Club, whose admins decide;
/// `--preview-nominator` an admin of Market Friends, which ratifies its
/// admins by vote; `--preview-member` a member of Common Thread, which votes
/// by majority.
final class GovernanceAuthoringFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// The maintainer asks the members about a member's request, then
    /// approves it with the advice in front of them.
    func testTheMaintainerAsksTheMembersThenApproves() {
        let app = launch(["--preview-admin"])
        openFromDashboard(app, "Film Club")
        openProposals(app)
        let row = proposalRow(app, "Subtitles at every screening")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let banner = app.staticTexts["proposalBanner"]
        XCTAssertTrue(wait(banner, label: "Waiting on the maintainer"))
        XCTAssertTrue(app.buttons["decideApprove"].waitForExistence(timeout: 10), "the maintainer's two verbs")
        XCTAssertTrue(app.buttons["decideDecline"].exists)
        let ask = app.buttons["decideAskMembers"]
        XCTAssertTrue(ask.exists, "and asking first, once")
        capture(app, "A1 Waiting on the maintainer")
        ask.tap()
        let confirmAsk = dialogButton(app, "Ask the members", besides: "decideAskMembers")
        XCTAssertTrue(confirmAsk.waitForExistence(timeout: 5), "asked before it is done")
        confirmAsk.tap()
        XCTAssertTrue(wait(banner, label: "Advisory vote."), "the vote advises")
        XCTAssertFalse(app.buttons["decideAskMembers"].exists, "the members can be asked once")

        app.buttons["decideApprove"].tap()
        let confirmApprove = dialogButton(app, "Approve", besides: "decideApprove")
        XCTAssertTrue(confirmApprove.waitForExistence(timeout: 5))
        capture(app, "A2 Approving")
        confirmApprove.tap()
        XCTAssertTrue(wait(banner, label: "The maintainer approved this. It is in effect."))
        XCTAssertFalse(app.buttons["decideApprove"].exists, "nothing left to decide")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Proposed by Lena Fox")).firstMatch.exists,
                      "the request stays its author's, not a change they applied")
    }

    /// An admin of a patch that ratifies its admins nominates a member.
    func testAnAdminNominatesAMember() {
        let app = launch(["--preview-nominator"])
        openFromDashboard(app, "Market Friends")
        let door = app.buttons["proposalDoor"]
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()
        let type = app.segmentedControls["proposalType"]
        XCTAssertTrue(type.waitForExistence(timeout: 5))
        type.buttons["Membership"].tap()
        let picker = app.buttons["nomineePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "the roster's members to choose from")
        picker.tap()
        let hana = app.buttons["Hana Sato"].firstMatch
        XCTAssertTrue(hana.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Ines Duarte"].exists, "an admin already holds the role")
        hana.tap()
        let title = app.textFields["proposalTitle"]
        title.tap()
        title.typeText("Hana for admin")
        capture(app, "A3 A nomination")
        let submit = app.buttons["proposalFormSubmit"]
        XCTAssertEqual(submit.label, "Submit proposal")
        submit.tap()
        XCTAssertTrue(app.navigationBars["Proposal"].waitForExistence(timeout: 10))
        XCTAssertTrue(wait(app.staticTexts["proposalBanner"], label: "Voting is open."), "the community ratifies")
        XCTAssertTrue(app.staticTexts["proposalNominee"].label.contains("Hana Sato"))
    }

    /// A member reads a document's history, then proposes a change to it,
    /// seeing what changed before sending it.
    func testAMemberProposesAChangeToADocument() {
        let app = launch(["--preview-member"])
        openGovernance(app, tile: "quiltTile-common-thread")
        let rooms = app.buttons["governanceDocuments"]
        XCTAssertTrue(scroll(app, to: rooms))
        rooms.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "documentRow", "How we decide")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let history = app.buttons["documentHistory"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        XCTAssertTrue(history.label.localizedCaseInsensitiveContains("3 versions"))
        history.tap()
        let version = app.buttons["versionRow"].firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 10))
        version.tap()
        XCTAssertTrue(app.staticTexts["versionDiff"].waitForExistence(timeout: 10), "the version's change against the one before")
        capture(app, "A4 A document's history")
        app.navigationBars["History"].buttons.element(boundBy: 0).tap()

        let door = app.buttons["documentChangeDoor"]
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        XCTAssertTrue(door.label.localizedCaseInsensitiveContains("propose change"))
        door.tap()
        let text = app.textViews["amendText"].exists ? app.textViews["amendText"] : app.textFields["amendText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["amendSummary"].label, "No changes yet")
        text.tap()
        text.typeText(" Keys live in the blue tin.")
        let summary = app.staticTexts["amendSummary"]
        XCTAssertTrue(wait(summary, label: "added"), "the change is counted as it is made")
        app.buttons["amendShowChanges"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["lineDiff"].waitForExistence(timeout: 5))
        capture(app, "A5 Proposing a change to a document")
        let submit = app.buttons["amendSubmit"]
        XCTAssertEqual(submit.label, "Submit proposal")
        submit.tap()
        XCTAssertTrue(app.navigationBars["Proposal"].waitForExistence(timeout: 10))
        XCTAssertTrue(wait(app.staticTexts["proposalBanner"], label: "Voting is open."))
        let changes = app.staticTexts["proposalChangesSummary"]
        XCTAssertTrue(scroll(app, to: changes), "the proposal says what it changes")
    }

    /// A member proposes a rules change and sees it current → proposed.
    func testAMemberProposesARulesChange() {
        let app = launch(["--preview-member"])
        openGovernance(app, tile: "quiltTile-common-thread")
        let door = app.buttons["rulesDoor"]
        XCTAssertTrue(scroll(app, to: door))
        XCTAssertTrue(door.label.localizedCaseInsensitiveContains("propose a change to these rules"))
        door.tap()
        XCTAssertTrue(app.staticTexts["rulesHeading"].waitForExistence(timeout: 10))
        let method = app.buttons["rulesDecisionMethod"].exists
            ? app.buttons["rulesDecisionMethod"]
            : app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Decision Method")).firstMatch
        XCTAssertTrue(method.waitForExistence(timeout: 10))
        method.tap()
        let supermajority = app.buttons["Supermajority (2/3)"].firstMatch
        XCTAssertTrue(supermajority.waitForExistence(timeout: 5))
        supermajority.tap()
        let row = app.descendants(matching: .any)["rulesDiffRow-decision_method"]
        XCTAssertTrue(scroll(app, to: row), "what moved, current to proposed")
        XCTAssertTrue(row.label.contains("Majority vote") && row.label.contains("Supermajority (2/3)"))
        let consequence = app.staticTexts["rulesConsequence"]
        XCTAssertTrue(scroll(app, to: consequence))
        XCTAssertTrue(consequence.label.contains("opens a vote"), "what pressing it does, before it is pressed")
        capture(app, "A6 Proposing a rules change")
        let submit = app.buttons["rulesSubmit"]
        XCTAssertEqual(submit.label, "Submit proposal")
        submit.tap()
        XCTAssertTrue(app.navigationBars["Proposal"].waitForExistence(timeout: 10))
        XCTAssertTrue(wait(app.staticTexts["proposalBanner"], label: "Voting is open."))
        XCTAssertTrue(scroll(app, to: app.descendants(matching: .any)["rulesDiffRow-decision_method"]), "the proposal lists the change")
    }

    /// An admin writes a new document from a template; it starts members only.
    func testAnAdminWritesANewDocument() {
        let app = launch(["--preview-admin"])
        openFromDashboard(app, "Film Club")
        let rooms = app.buttons["governanceDocuments"]
        XCTAssertTrue(scroll(app, to: rooms))
        rooms.tap()
        let door = app.buttons["newDocumentDoor"]
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()
        XCTAssertTrue(app.staticTexts["newDocumentHeading"].waitForExistence(timeout: 5))
        app.buttons["newDocumentTemplate"].tap()
        let conduct = app.buttons["Code of Conduct"].firstMatch
        XCTAssertTrue(conduct.waitForExistence(timeout: 5))
        conduct.tap()
        XCTAssertEqual(app.textFields["newDocumentTitle"].value as? String, "Code of Conduct", "the template fills the title")
        capture(app, "A7 A new document")
        app.buttons["newDocumentSave"].tap()
        XCTAssertTrue(app.navigationBars["Document"].waitForExistence(timeout: 10), "it opens on its own screen")
        XCTAssertTrue(app.staticTexts["Code of Conduct"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Members only"].exists, "a charter is published deliberately")
    }

    // MARK: Helpers

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro"] + extra
        app.launch()
        let explore = app.buttons["exploreQuilt"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        explore.tap()
        XCTAssertTrue(app.navigationBars["Sample quilt"].waitForExistence(timeout: 10))
        signIn(app)
        return app
    }

    /// A patch the reader runs, from the Dashboard, into its Governance room.
    private func openFromDashboard(_ app: XCUIApplication, _ name: String) {
        let dashboard = app.tabBars.buttons["Dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
        dashboard.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "dashboardRow", name)).firstMatch
        XCTAssertTrue(scroll(app, to: row), "\(name) is on the Dashboard")
        row.tap()
        XCTAssertTrue(app.buttons["closePatch"].waitForExistence(timeout: 10))
        pullUp(app)
        let governance = app.buttons["glimpseDoor-Governance"]
        XCTAssertTrue(scroll(app, to: governance))
        governance.tap()
        XCTAssertTrue(app.navigationBars["Governance"].waitForExistence(timeout: 10))
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

    /// A confirmation's button: the dialog draws its buttons twice, and the
    /// act that opened it wears the same word — as, once an advisory vote is
    /// open, do the vote's own Approve buttons.
    private func dialogButton(_ app: XCUIApplication, _ label: String, besides identifier: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "label ==[c] %@ AND identifier != %@ AND NOT (identifier BEGINSWITH 'vote') AND NOT (identifier BEGINSWITH 'bar-')",
            label, identifier)).firstMatch
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
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS[c] %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
