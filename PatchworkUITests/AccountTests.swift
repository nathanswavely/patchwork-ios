// SPDX-License-Identifier: MPL-2.0

import XCTest

/// The account's own settings, end to end over the fixtures: a saved name,
/// the one launch that opens on My Quilt, deletion through the Confirm sheet,
/// and signing in with a recovery code instead of an email.
final class AccountTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Settings from the account menu: the name saved on Profile is the name
    /// the menu then wears, and Start on My Quilt changes the next launch —
    /// not this one — and is honoured by it.
    func testSettingsSaveANameAndStartTheNextLaunchOnMyQuilt() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro"]
        app.launch()
        openSampleQuilt(app)
        signIn(app)

        openSettings(app)
        capture(app, "40 Settings index")
        app.buttons["settingsProfile"].tap()
        let name = app.textFields["profileDisplayName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["profileSave"].isEnabled, "nothing changed, nothing to save")
        replaceText(in: name, with: "Sam Reader")
        app.buttons["profileSave"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["profileSaved"].waitForExistence(timeout: 10), "the quilt took it")
        capture(app, "41 Profile saved")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()

        app.buttons["Account"].tap()
        XCTAssertTrue(named(app, "Sam Reader").waitForExistence(timeout: 5), "the menu wears the saved name")
        let settings = app.buttons["accountSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        app.buttons["settingsLanding"].tap()
        let start = app.switches["startOnMyQuilt"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertEqual(start.value as? String, "0")
        flip(start)
        XCTAssertTrue(wait(start, value: "1"), "saved on toggle, no Save button")
        capture(app, "42 Start on My Quilt")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Quilt"].waitForExistence(timeout: 5),
                      "the preference changes the next launch; this one stays on the whole quilt")

        // A cold launch, resuming the same fixture session: it opens on My Quilt.
        app.terminate()
        app.launchArguments = ["--preview", "--skip-intro", "--preview-resume"]
        app.launch()
        openSampleQuilt(app)
        XCTAssertTrue(app.tabBars.buttons["My Quilt"].waitForExistence(timeout: 10), "the launch honours the preference")
        XCTAssertTrue(app.buttons["quiltTile-listening-room"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["quiltTile-common-thread"].exists, "and draws My Quilt")
        capture(app, "43 Launched on My Quilt")

        // And back, so the next resuming launch starts where every other does.
        openSettings(app)
        app.buttons["settingsLanding"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertEqual(start.value as? String, "1")
        flip(start)
        XCTAssertTrue(wait(start, value: "0"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["My Quilt"].exists, "switching it off does not re-assert anything either")
    }

    /// Deletion, end to end: the typed username arms the button, a
    /// confirmation stands before the call, the quilt asks for a fresh proof,
    /// a fixture recovery code gives it, and the reader is left on the quilt,
    /// signed out, told so once.
    func testDeleteAccountThroughTheConfirmSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro"]
        app.launch()
        openSampleQuilt(app)
        signIn(app)
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 10))

        openSettings(app)
        app.buttons["settingsDelete"].tap()
        let delete = app.buttons["deleteAccount"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertFalse(delete.isEnabled, "nothing typed, nothing armed")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Deleted account")).firstMatch.exists,
                      "the page says what stays")
        capture(app, "44 Delete account")

        let field = app.textFields["deleteConfirmField"]
        field.tap()
        field.typeText("samplereade")
        XCTAssertFalse(delete.isEnabled, "only an exact match arms it")
        field.typeText("r\n")
        XCTAssertTrue(delete.isEnabled)
        delete.tap()

        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Delete my account", "deleteAccount")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "a confirmation stands before the call")
        confirm.tap()

        // The quilt asks for presence; the fixture reader's codes predate the session.
        let code = app.textFields["stepUpCode"]
        XCTAssertTrue(code.waitForExistence(timeout: 10), "the Confirm sheet asks for a recovery code")
        XCTAssertTrue(app.staticTexts["stepUpEnterCode"].exists)
        XCTAssertFalse(app.buttons["stepUpConfirm"].isEnabled, "twelve characters or nothing")
        capture(app, "45 Confirm it’s you")
        code.tap()
        code.typeText("ZZZZ-ZZZZ-ZZZZ")
        app.buttons["stepUpConfirm"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["stepUpError"].waitForExistence(timeout: 5), "a wrong code is said, not swallowed")
        capture(app, "45a A wrong code")
        replaceText(in: code, with: "ABCD-EFGH-JKM2")
        app.buttons["stepUpConfirm"].tap()

        let farewell = app.alerts["Your account has been deleted."]
        XCTAssertTrue(farewell.waitForExistence(timeout: 10), "said once, on the quilt")
        capture(app, "46 Deleted")
        farewell.buttons["OK"].tap()
        XCTAssertFalse(app.tabBars.buttons["Dashboard"].exists, "no account, no Dashboard")
        app.buttons["Account"].tap()
        XCTAssertTrue(app.buttons["Sign in"].waitForExistence(timeout: 5), "browsing the whole quilt, signed out")
        XCTAssertFalse(app.buttons["accountSettings"].exists)
    }

    /// The quiet second way in: a username and a code the reader kept. It
    /// lands exactly where a code sign-in does, and the code is spent.
    func testSignInWithARecoveryCode() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro"]
        app.launch()
        openSampleQuilt(app)

        app.buttons["Account"].tap()
        XCTAssertTrue(app.buttons["Sign in"].waitForExistence(timeout: 5))
        app.buttons["Sign in"].tap()
        let other = app.buttons["signInUseRecovery"]
        XCTAssertTrue(other.waitForExistence(timeout: 5), "offered quietly under the email step")
        other.tap()

        let username = app.textFields["signInRecoveryUsername"]
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        username.tap()
        username.typeText("samplereader")
        let code = app.textFields["signInRecoveryCode"]
        code.tap()
        code.typeText("zzzz-zzzz-zzzz")
        app.buttons["signInRecover"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["signInError"].waitForExistence(timeout: 5), "one sentence for a wrong pair")
        capture(app, "47 Recovery sign-in refused")
        replaceText(in: code, with: "NPQR-STUV-WXY3")
        app.buttons["signInRecover"].tap()

        XCTAssertFalse(app.textFields["signInRecoveryCode"].waitForExistence(timeout: 5), "signed in, the sheet is done")
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 10), "an account brings its own tab")
        app.buttons["Account"].tap()
        XCTAssertTrue(named(app, "samplereader").waitForExistence(timeout: 5), "the menu says who you are")

        // The code is spent, and this device is the one marked.
        app.buttons["accountSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["settingsSecurity"].tap()
        let status = app.staticTexts["recoveryCodesStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(wait(status, label: "9 of 10 remaining"))
        XCTAssertTrue(app.descendants(matching: .any)["sessionThisDevice"].waitForExistence(timeout: 10))
        capture(app, "48 Security")
    }

    // MARK: Helpers

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

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["Account"].tap()
        let settings = app.buttons["accountSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "an account brings its settings, under its own menu")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        let typed = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typed.count))
        field.typeText(text)
    }

    /// A list row's switch is the whole row; the thumb is at its trailing end.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    private func wait(_ element: XCUIElement, value: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func wait(_ element: XCUIElement, label: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func named(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
