// SPDX-License-Identifier: MPL-2.0
import XCTest

/// A person's profile, end to end over the fixtures: reached from a patch's
/// members room, read whole — the patches they run and belong to, and the
/// card they share with a patch the reader is in — and left by one of their
/// patches; reported; your own, reached from a notice you put up; an empty
/// one; and a member whose account the quilt no longer answers for.
final class PeopleFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// The studio's members room → Rowan → his profile, with his card
    /// (the reader is in the Repair Cafe, where he shares it) → the Repair
    /// Cafe, docked in the studio's place.
    func testAMembersProfileOpensOneOfTheirPatches() {
        let app = launch(member: false)
        openPerson(app, named: "Rowan Hale")

        let name = app.staticTexts["personName"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertEqual(name.label, "Rowan Hale")
        XCTAssertTrue(app.staticTexts["personHandle"].label.hasPrefix("@rowan · here since "), "the handle and the month they arrived")
        XCTAssertTrue(app.staticTexts["personBio"].exists)
        XCTAssertTrue(app.staticTexts["Reach Rowan Hale"].exists, "a reader in a patch he shares with is shown his card")
        XCTAssertTrue(app.staticTexts["Shared with people they organize with. You can see this because you are in a patch they gave it to."].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "contactRow").count, 4)
        XCTAssertTrue(app.buttons["personReport"].exists, "somebody else's profile can be reported")
        XCTAssertFalse(app.buttons["personEdit"].exists)
        capture(app, "81 A person's profile")

        let runs = app.buttons["personPatch-common-thread"]
        XCTAssertTrue(scroll(app, to: runs))
        XCTAssertTrue(app.staticTexts["Runs"].exists)
        XCTAssertTrue(runs.label.contains("Common Thread Studio"))
        XCTAssertTrue(app.links["rowan.example.org"].exists || app.buttons["rowan.example.org"].exists,
                      "a link with no label is named by its host")
        let repairCafe = app.buttons["personPatch-extra-6"]
        XCTAssertTrue(scroll(app, to: repairCafe))
        XCTAssertTrue(app.staticTexts["Member of"].exists)
        capture(app, "82 Runs and Member of")

        repairCafe.tap()
        XCTAssertTrue(app.staticTexts["Repair Cafe"].waitForExistence(timeout: 10), "the patch docks in the studio's place")
        XCTAssertTrue(app.buttons["closePatch"].exists)
        XCTAssertFalse(app.staticTexts["personName"].exists)
    }

    /// A member whose card goes only to the studio, which this reader is
    /// not in: no card, no heading for one — and a report, which goes to
    /// the quilt's admins.
    func testReportingAPerson() {
        let app = launch(member: false)
        openPerson(app, named: "Imani Osei")
        XCTAssertTrue(app.staticTexts["personName"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Reach Imani Osei"].exists, "a card nobody shared with this reader is not even headed")

        app.buttons["personReport"].tap()
        let heading = app.staticTexts["reportHeading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertEqual(heading.label, "Report this person")
        XCTAssertTrue(app.staticTexts["Reports go to the instance admins, who review them against the community lining. You’re reporting Imani Osei."].exists)
        capture(app, "83 Reporting a person")
        app.buttons["reportSubmit"].tap()
        XCTAssertTrue(app.staticTexts["reportSentHeading"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["An admin will review it."].exists)
        app.buttons["reportDone"].tap()
        XCTAssertTrue(app.staticTexts["personName"].waitForExistence(timeout: 10))
    }

    /// Theo hid his membership, so there is nothing on his profile; Wren's
    /// account is suspended, and the quilt answers for her as for a name
    /// nobody holds.
    func testAnEmptyProfileAndOneTheQuiltWillNotShow() {
        let app = launch(member: false)
        openPerson(app, named: "theo")
        let empty = app.staticTexts["personEmpty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertEqual(empty.label, "Nothing here yet.")
        XCTAssertFalse(app.staticTexts["personHiddenHint"].exists, "the hint about hidden memberships is the person's own")
        capture(app, "84 Nothing here yet")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let wren = memberRow(app, "Wren Adler")
        XCTAssertTrue(wren.waitForExistence(timeout: 10))
        wren.tap()
        XCTAssertTrue(app.staticTexts["Person not found"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["User not found"].exists, "in the server's own words")
        capture(app, "85 Person not found")
    }

    /// The reader's own profile, reached from the notice they put up: Edit
    /// profile rather than Report, and the patches they keep visible — the
    /// studio and the Repair Cafe, never the Listening Room they only follow.
    func testYourOwnProfileFromYourNotice() {
        let app = launch(member: true)
        let patch = app.buttons["quiltTile-common-thread"]
        XCTAssertTrue(patch.waitForExistence(timeout: 10))
        patch.tap()
        XCTAssertTrue(app.buttons["closePatch"].waitForExistence(timeout: 10))
        app.swipeUp()
        let door = app.buttons["glimpseDoor-Noticeboard"]
        XCTAssertTrue(scroll(app, to: door))
        door.tap()
        let mine = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "noticeRow", "Spare fabric")).firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 10))
        mine.tap()
        let author = app.buttons["personDoor-samplereader"]
        XCTAssertTrue(author.waitForExistence(timeout: 10), "the notice's author is a door")
        author.tap()

        XCTAssertTrue(app.staticTexts["personName"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["personName"].label, "Sample Reader")
        XCTAssertTrue(app.buttons["personEdit"].exists, "your own profile is edited, not reported")
        XCTAssertFalse(app.buttons["personReport"].exists)
        XCTAssertTrue(scroll(app, to: app.buttons["personPatch-extra-6"]))
        XCTAssertTrue(app.buttons["personPatch-common-thread"].exists)
        XCTAssertFalse(app.buttons["personPatch-listening-room"].exists, "following is not on a profile")
        capture(app, "86 Your own profile")

        XCTAssertTrue(scroll(app, to: app.buttons["personEdit"], up: true))
        app.buttons["personEdit"].tap()
        XCTAssertTrue(app.textFields["profileDisplayName"].waitForExistence(timeout: 10), "Edit profile is Settings' own page")
    }

    /// The Label's steward, from the quilt's information sheet: the sheet
    /// gives way when one of their patches is opened.
    func testAStewardFromTheLabel() {
        let app = launch(member: false)
        app.buttons["Account"].tap()
        app.buttons["About this quilt"].tap()
        let label = app.buttons["infoLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        label.tap()
        // The page's own identifier reaches every element on it, so the
        // card is found by what it says.
        let steward = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "@samplesteward")).firstMatch
        XCTAssertTrue(steward.waitForExistence(timeout: 10))
        steward.tap()
        XCTAssertTrue(app.staticTexts["personName"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["personName"].label, "Sample Steward")
        let garden = app.buttons["personPatch-extra-0"]
        XCTAssertTrue(scroll(app, to: garden))
        garden.tap()
        XCTAssertTrue(app.staticTexts["Community Garden"].waitForExistence(timeout: 10), "the patch docks over the quilt")
        XCTAssertTrue(app.buttons["closePatch"].exists)
    }

    // MARK: Helpers

    /// The studio's members room, and somebody in it.
    private func openPerson(_ app: XCUIApplication, named name: String) {
        let patch = app.buttons["quiltTile-common-thread"]
        XCTAssertTrue(patch.waitForExistence(timeout: 10))
        patch.tap()
        XCTAssertTrue(app.buttons["closePatch"].waitForExistence(timeout: 10))
        app.swipeUp()
        let door = app.buttons["glimpseDoor-Members"]
        XCTAssertTrue(scroll(app, to: door))
        door.tap()
        XCTAssertTrue(app.navigationBars["Members"].waitForExistence(timeout: 10))
        let row = memberRow(app, name)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
    }

    private func memberRow(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "memberRow", name)).firstMatch
    }

    private func launch(member: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro"] + (member ? ["--preview-member"] : [])
        app.launch()
        app.buttons["quiltChoice"].firstMatch.tap()
        let explore = app.buttons["exploreQuilt"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        explore.tap()
        XCTAssertTrue(app.navigationBars["Sample quilt"].waitForExistence(timeout: 10))
        signIn(app)
        return app
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

    private func scroll(_ app: XCUIApplication, to element: XCUIElement, up: Bool = false, swipes: Int = 8) -> Bool {
        let clear = { element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 40 }
        for _ in 0..<swipes {
            if clear() { return true }
            if up { app.swipeDown() } else { app.swipeUp() }
        }
        return clear()
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
