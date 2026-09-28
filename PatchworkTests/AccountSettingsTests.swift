// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// The account's settings, checked as values: what a save sends, the one
/// launch that may open on My Quilt, the Confirm sheet's three states, the
/// recovery code as the server reads it, the four ways a code fails, and a
/// refusal that carries a code and a list.
final class AccountSettingsTests: XCTestCase {
    private func user(displayName: String? = "Sample Reader", bio: String? = "Hello.", links: [PatchLink]? = nil,
                      startOnMyQuilt: Bool? = nil) -> User {
        User(id: "u1", username: "samplereader", displayName: displayName, bio: bio, avatarUrl: nil, role: "member", email: nil,
             links: links, startOnMyQuilt: startOnMyQuilt)
    }

    private func encoded(_ changes: AccountChanges) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(changes)) as? [String: Any])
    }

    // MARK: What a save sends

    func testAnUntouchedDraftSendsNothing() {
        let me = user(links: [PatchLink(url: "https://example.org", label: "Site")])
        XCTAssertNil(ProfileDraft(user: me).changes(from: me), "Save has nothing to say")
        var draft = ProfileDraft(user: me)
        draft.displayName = "  Sample Reader  "
        XCTAssertNil(draft.changes(from: me), "whitespace around the same name is the same name")
    }

    func testOnlyTheChangedFieldTravels() throws {
        let me = user()
        var draft = ProfileDraft(user: me)
        draft.displayName = "Sam Reader"
        let changes = try XCTUnwrap(draft.changes(from: me))
        let body = try encoded(changes)
        XCTAssertEqual(body as NSDictionary, ["display_name": "Sam Reader"] as NSDictionary,
                       "the bio and links nobody touched are left out, not sent back as they were")
    }

    func testLinksWithNoAddressAreDroppedAndTheRestTrimmed() throws {
        let me = user(links: [])
        var draft = ProfileDraft(user: me)
        draft.links = [
            .init(label: " Studio ", url: " https://studio.example.org "),
            .init(label: "Nowhere", url: "   "),
            .init(label: "", url: ""),
        ]
        let changes = try XCTUnwrap(draft.changes(from: me))
        XCTAssertEqual(changes.links, [PatchLink(url: "https://studio.example.org", label: "Studio")])
        let body = try encoded(changes)
        XCTAssertEqual(Set(body.keys), ["links"])
        let links = try XCTUnwrap(body["links"] as? [[String: String]])
        XCTAssertEqual(links, [["url": "https://studio.example.org", "label": "Studio"]])
    }

    func testAddingOnlyAnEmptyLinkRowChangesNothing() {
        let me = user(links: [PatchLink(url: "https://example.org", label: "Site")])
        var draft = ProfileDraft(user: me)
        draft.links.append(.init())
        XCTAssertNil(draft.changes(from: me), "an empty row is dropped on save, so there is nothing to save")
    }

    func testClearingABioIsAChange() throws {
        let me = user(bio: "Hello.")
        var draft = ProfileDraft(user: me)
        draft.bio = ""
        let body = try encoded(XCTUnwrap(draft.changes(from: me)))
        XCTAssertEqual(body["bio"] as? String, "", "an emptied field is sent empty, which the server reads as cleared")
    }

    func testTheSwitchesSendOneFieldEach() throws {
        XCTAssertEqual(try encoded(AccountChanges(startOnMyQuilt: true)) as NSDictionary, ["start_on_my_quilt": true] as NSDictionary)
        XCTAssertEqual(try encoded(AccountChanges(hideAmendedLinings: false)) as NSDictionary, ["hide_amended_linings": false] as NSDictionary)
    }

    func testTheAccountDecodesItsPreferences() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let json = #"{"id":"u1","username":"samplereader","links":[{"url":"https://a.example","label":"A"}],"start_on_my_quilt":true,"hide_amended_linings":false}"#
        let me = try XCTUnwrap(decoder.decode(SignInResponse.self, from: Data(json.utf8)).user)
        XCTAssertEqual(me.links, [PatchLink(url: "https://a.example", label: "A")])
        XCTAssertEqual(me.startOnMyQuilt, true)
        XCTAssertEqual(me.hideAmendedLinings, false)
        let bare = try XCTUnwrap(decoder.decode(SignInResponse.self, from: Data(#"{"id":"u1","username":"x"}"#.utf8)).user)
        XCTAssertNil(bare.startOnMyQuilt, "a sign-in answer carries none of them, and is still a user")
    }

    // MARK: Start on My Quilt, once per launch

    func testThePreferenceFiresOnceAtTheFirstAccountRead() {
        var lens = LaunchLens()
        XCTAssertEqual(lens.accountRead(user(startOnMyQuilt: true)), .my)
        XCTAssertNil(lens.accountRead(user(startOnMyQuilt: true)), "and never re-asserts in the same session")
    }

    func testAnAccountWithoutThePreferenceSettlesTheLaunchToo() {
        var lens = LaunchLens()
        XCTAssertNil(lens.accountRead(user(startOnMyQuilt: false)))
        // Switching it on later in the same launch changes the next launch, not this one.
        XCTAssertNil(lens.accountRead(user(startOnMyQuilt: true)))
    }

    func testASignedOutLaunchSettlesAndALaterSignInDoesNotFire() {
        var lens = LaunchLens()
        XCTAssertNil(lens.accountRead(nil), "nobody is signed in at the cold load")
        XCTAssertNil(lens.accountRead(user(startOnMyQuilt: true)), "a sign-in afterwards is not a cold load")

        var fresh = LaunchLens()
        fresh.signedInMidSession()
        XCTAssertNil(fresh.accountRead(user(startOnMyQuilt: true)), "the sheet's sign-in settles it even before any read")
    }

    // MARK: The Confirm sheet's three states

    func testCodesThisSessionCanUseAreAskedFor() {
        let status = StepUpStatus(recoveryReady: 7)
        XCTAssertEqual(StepUp.decide(status: status, codes: RecoveryCodeStatus(total: 10, remaining: 7)), .enterCode(ready: 7))
        XCTAssertEqual(StepUp.decide(status: status, codes: nil), .enterCode(ready: 7), "the ready count decides on its own")
    }

    func testCodesNewerThanTheSignInSendThePersonToSignInAgain() {
        let status = StepUpStatus(recoveryReady: 0)
        XCTAssertEqual(StepUp.decide(status: status, codes: RecoveryCodeStatus(total: 10, remaining: 10)), .signInAgain)
    }

    func testNoCodesAtAllOffersToMakeThem() {
        let status = StepUpStatus(recoveryReady: 0)
        XCTAssertEqual(StepUp.decide(status: status, codes: RecoveryCodeStatus(total: 0, remaining: 0)), .makeCodes)
        XCTAssertEqual(StepUp.decide(status: status, codes: RecoveryCodeStatus(total: 10, remaining: 0)), .makeCodes,
                       "a spent set cannot sign anybody back in")
        XCTAssertEqual(StepUp.decide(status: StepUpStatus(recoveryReady: nil), codes: nil), .makeCodes)
    }

    // MARK: The code as the server reads it

    func testARecoveryCodeIsNormalisedTheServersWay() {
        XCTAssertEqual(RecoveryCode.normalize("abcd-efgh-jkm2"), "abcdefghjkm2")
        XCTAssertEqual(RecoveryCode.normalize("  ABCD-EFGH-JKM2 \n"), "abcdefghjkm2", "trimmed and lowercased")
        XCTAssertEqual(RecoveryCode.normalize("abcd efgh jkm2"), "abcdefghjkm2", "spaces go the way hyphens do")
        XCTAssertEqual(RecoveryCode.normalize("ab-cdef-ghjk-m2"), "abcdefghjkm2", "hyphens anywhere")
        XCTAssertTrue(RecoveryCode.isComplete("ABCD-EFGH-JKM2"))
        XCTAssertFalse(RecoveryCode.isComplete("abcd-efgh-jkm"))
        XCTAssertFalse(RecoveryCode.isComplete("abcd-efgh-jkm23"))
        XCTAssertEqual(RecoveryCode.alphabet.count, 31)
        for code in PreviewData.recoveryCodes {
            XCTAssertTrue(RecoveryCode.normalize(code).allSatisfy { RecoveryCode.alphabet.contains($0) }, code)
            XCTAssertTrue(RecoveryCode.isComplete(code), code)
        }
    }

    // MARK: Four failures, four sentences

    func testEachWayACodeFailsSaysSomethingDifferent() {
        let sentences = [
            StepUp.failureSentence(code: "no_recovery_codes", status: 400),
            StepUp.failureSentence(code: "recovery_codes_too_new", status: 400),
            StepUp.failureSentence(code: "invalid_code", status: 400),
            StepUp.failureSentence(code: nil, status: 429),
        ]
        XCTAssertEqual(Set(sentences).count, 4, "ADR 099: each asks something different of the person")
        XCTAssertTrue(sentences[1].contains("Sign out"), "too new says what to do about it")
        XCTAssertTrue(sentences[3].contains("Wait"), "the rate limit asks for time, not another code")
        XCTAssertEqual(StepUp.failureSentence(code: nil, status: 400), sentences[2], "an unnamed refusal reads as a wrong code")
    }

    func testRunningLowIsSaidAtTwoAndBelow() {
        XCTAssertNil(StepUp.runningLow(remaining: 3))
        XCTAssertNotNil(StepUp.runningLow(remaining: 2))
        XCTAssertTrue(StepUp.runningLow(remaining: 1)?.contains("1 recovery code left") == true)
        XCTAssertTrue(StepUp.runningLow(remaining: 0)?.contains("last") == true)
    }

    // MARK: A refusal with a name

    func testARefusalKeepsItsCodeAndItsSentence() {
        let body = #"{"error":"Confirm with your passkey to continue.","code":"sudo_required"}"#
        let error = APIError.from(status: 403, data: Data(body.utf8))
        XCTAssertEqual(error, .refused(Refusal(error: "Confirm with your passkey to continue.", code: "sudo_required"), status: 403))
        XCTAssertEqual(error.code, "sudo_required")
        XCTAssertEqual(error.httpStatus, 403)
        XCTAssertEqual(error.errorDescription, "Confirm with your passkey to continue.")
        XCTAssertTrue(StepUp.needsStepUp(error))
        XCTAssertTrue(StepUp.needsStepUp(APIError.from(status: 403, data: Data(#"{"error":"x","code":"passkey_required"}"#.utf8))))
    }

    func testTheSoleAdminRefusalCarriesItsPatches() {
        let body = #"{"error":"hand these patches to somebody else first — you are their only admin","code":"sole_admin","patches":[{"slug":"common-thread","name":"Common Thread Studio"},{"slug":"listening-room","name":"The Listening Room"}]}"#
        let error = APIError.from(status: 409, data: Data(body.utf8))
        guard case .refused(let refusal, let status) = error else { return XCTFail("expected a refusal, got \(error)") }
        XCTAssertEqual(status, 409)
        XCTAssertEqual(refusal.code, "sole_admin")
        XCTAssertEqual(refusal.patches?.map(\.slug), ["common-thread", "listening-room"])
        XCTAssertEqual(refusal.patches?.first?.name, "Common Thread Studio")
        XCTAssertFalse(StepUp.needsStepUp(error), "a refusal that is not about presence opens no sheet")
    }

    func testABodyWithoutACodeIsStillJustASentence() {
        let error = APIError.from(status: 400, data: Data(#"{"error":"type your username exactly to confirm"}"#.utf8))
        XCTAssertEqual(error, .message("type your username exactly to confirm", status: 400))
        XCTAssertNil(error.code)
        XCTAssertEqual(APIError.from(status: 400, data: Data(#"{"error":"x","code":""}"#.utf8)), .message("x", status: 400),
                       "an empty code names nothing")
        XCTAssertEqual(APIError.from(status: 401, data: Data(#"{"error":"x","code":"sudo_required"}"#.utf8)), .unauthenticated)
    }

    // MARK: The files and the session list

    func testTheFileIsNamedAsTheQuiltNamedIt() {
        XCTAssertEqual(Download.filename(fromDisposition: #"attachment; filename="patchwork-samplereader.json""#), "patchwork-samplereader.json")
        XCTAssertEqual(Download.filename(fromDisposition: "attachment; filename=seamrip.zip"), "seamrip.zip")
        XCTAssertEqual(Download.filename(fromDisposition: #"attachment; filename="../../etc/passwd""#), "passwd", "a path is never a place to write")
        XCTAssertNil(Download.filename(fromDisposition: "inline"))
        XCTAssertEqual(Download(data: Data(), headers: ["content-disposition": "attachment; filename=a.json"]).filename, "a.json")
        XCTAssertNil(Download(data: Data(), headers: [:]).filename)
    }

    func testSessionTimesReadInBothOfTheServersSpellings() throws {
        let sqlite = try XCTUnwrap(AccountDate.parse("2026-09-27 10:00:00"))
        let iso = try XCTUnwrap(AccountDate.parse("2026-09-27T10:00:00Z"))
        XCTAssertEqual(sqlite, iso)
        XCTAssertNotNil(AccountDate.parse("2026-09-27T10:00:00.123Z"))
        XCTAssertNil(AccountDate.parse(""))
        let row = AccountSession(id: "s", label: "iPhone", createdAt: "2026-09-20T10:00:00Z", lastUsedAt: "2026-09-27T10:00:00Z", current: true)
        let line = AccountDate.sessionLine(row, now: iso.addingTimeInterval(3 * 3600))
        XCTAssertTrue(line.hasPrefix("Active 3h ago · Signed in"), line)
    }

    /// The device names itself to the quilt, so the Security page's session
    /// list can say "iPhone" rather than "Unknown device" for this app.
    func testTheUserAgentNamesTheDeviceTheWayTheServerReadsIt() {
        XCTAssertEqual(PatchworkAPI.userAgent(model: "iPhone", version: "1.0"), "Patchwork/1.0 (iPhone)")
        XCTAssertEqual(PatchworkAPI.userAgent(model: "iPad", version: nil), "Patchwork/dev (iPad)")
        XCTAssertEqual(PatchworkAPI.userAgent(model: "iPhone", version: " "), "Patchwork/dev (iPhone)")
    }
}
