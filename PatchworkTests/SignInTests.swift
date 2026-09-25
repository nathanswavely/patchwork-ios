// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// Signing in, checked as a value: the reducer walks every branch the server
/// can send it down with no window open, the two rules this client mirrors are
/// checked at their edges, and the two places a mistake would be quiet — an
/// error body read as a bare status, a cookie read across hosts — are checked
/// on their own.
final class SignInTests: XCTestCase {
    private let sampleUser = User(
        id: "u1", username: "samplereader", displayName: "Sample Reader",
        bio: nil, avatarUrl: nil, role: "member", email: nil
    )

    // MARK: The reducer

    func testTheWholeFlowFromAnAddressToAnAccount() {
        var flow = SignInFlow()
        XCTAssertEqual(flow.step, .email)
        flow.email = "reader@example.org"
        XCTAssertTrue(flow.canSendCode)

        flow.apply(.codeSent(email: "reader@example.org"))
        XCTAssertEqual(flow.step, .code(email: "reader@example.org"))
        XCTAssertNil(flow.error)

        flow.apply(.verified(sampleUser))
        XCTAssertEqual(flow.step, .done(sampleUser))
    }

    func testAnAddressWithNoAccountBranchesThroughTheUsernameStep() {
        var flow = SignInFlow()
        flow.apply(.codeSent(email: "new@example.org"))
        flow.apply(.usernameRequired(token: "signup-token"))
        XCTAssertEqual(flow.step, .username(token: "signup-token", email: "new@example.org"))
        // The address travels with the token: the step after it is still about
        // the person who answered the code.
        flow.username = "new-reader"
        flow.apply(.created(sampleUser))
        XCTAssertEqual(flow.step, .done(sampleUser))
    }

    func testAWrongCodeStaysOnTheCodeStepAndSaysWhy() {
        var flow = SignInFlow()
        flow.apply(.codeSent(email: "reader@example.org"))
        flow.code = "111111"
        flow.busy = true
        flow.apply(.rejected("That code did not work. Check the digits, or send a new one."))
        XCTAssertEqual(flow.step, .code(email: "reader@example.org"), "a refusal never moves the step")
        XCTAssertEqual(flow.error, "That code did not work. Check the digits, or send a new one.")
        XCTAssertFalse(flow.busy, "and the button is pressable again")
        XCTAssertEqual(flow.code, "111111", "the digits stay in front of the person to correct")
    }

    func testUseADifferentEmailGoesBackAndKeepsTheAddressToEdit() {
        var flow = SignInFlow()
        flow.email = "typo@example.org"
        flow.apply(.codeSent(email: "typo@example.org"))
        flow.code = "123456"
        flow.apply(.rejected("That code did not work."))
        flow.apply(.useDifferentEmail)
        XCTAssertEqual(flow.step, .email)
        XCTAssertEqual(flow.email, "typo@example.org")
        XCTAssertEqual(flow.code, "", "the old code does not follow the new address")
        XCTAssertNil(flow.error)
    }

    func testEventsOutOfTurnDoNothing() {
        var flow = SignInFlow()
        // No code has been asked for, so there is nothing to verify.
        flow.apply(.verified(sampleUser))
        flow.apply(.usernameRequired(token: "t"))
        flow.apply(.created(sampleUser))
        flow.apply(.useDifferentEmail)
        XCTAssertEqual(flow.step, .email)
        // And a signup handoff with no token is not a step.
        flow.apply(.codeSent(email: "reader@example.org"))
        flow.apply(.usernameRequired(token: ""))
        XCTAssertEqual(flow.step, .code(email: "reader@example.org"))
    }

    // MARK: The two rules this client mirrors

    func testTheCodeIsNormalisedAndSixDigitsAreRequired() {
        XCTAssertEqual(SignInFlow.normalize(code: "123 456"), "123456")
        XCTAssertEqual(SignInFlow.normalize(code: " 12 34 56 "), "123456")
        XCTAssertTrue(SignInFlow.isCompleteCode("123 456"))
        XCTAssertFalse(SignInFlow.isCompleteCode("12345"))
        XCTAssertFalse(SignInFlow.isCompleteCode("1234567"), "a seventh digit is a typo, not a code")
        XCTAssertFalse(SignInFlow.isCompleteCode(""))
        var flow = SignInFlow()
        flow.apply(.codeSent(email: "reader@example.org"))
        flow.code = "12 34 5"
        XCTAssertEqual(flow.code, "12 34 5", "the field keeps what was typed")
        XCTAssertFalse(flow.canVerify)
        flow.code = "12 34 56"
        XCTAssertTrue(flow.canVerify)
    }

    func testUsernameValidationMatchesTheServersRule() {
        for value in ["abc", "a-b", "new-reader", "a1b", "samplereader", String(repeating: "a", count: 30)] {
            XCTAssertTrue(SignInFlow.isValidUsername(value), value)
        }
        for value in ["", "a", "ab", "-abc", "abc-", "-", "Abc", "ABC", "a_b", "a b", "a.b", "ünicode",
                      String(repeating: "a", count: 31), "abc\n", "a\nbc"] {
            XCTAssertFalse(SignInFlow.isValidUsername(value), value)
        }
    }

    // MARK: What a refusal means

    func testAnErrorBodyIsReadAsTheServersSentenceAndABareStatusIsNot() {
        let sentence = APIError.from(status: 400, data: Data(#"{"error":"that username is taken"}"#.utf8))
        XCTAssertEqual(sentence, .message("that username is taken", status: 400))
        XCTAssertEqual(sentence.errorDescription, "that username is taken")

        XCTAssertEqual(APIError.from(status: 500, data: Data()), .status(500))
        XCTAssertEqual(APIError.from(status: 400, data: Data("not json".utf8)), .status(400))
        XCTAssertEqual(APIError.from(status: 400, data: Data(#"{"error":"  "}"#.utf8)), .status(400), "an empty sentence is no sentence")
        // 401 is a state, not a status to report.
        XCTAssertEqual(APIError.from(status: 401, data: Data(#"{"error":"nope"}"#.utf8)), .unauthenticated)
    }

    func testBothAnswersToVerifyDecodeFromTheSameShape() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let user = try decoder.decode(SignInResponse.self, from: Data(#"{"id":"u1","username":"samplereader","display_name":"Sample Reader","role":"member"}"#.utf8))
        XCTAssertEqual(try user.outcome(), .signedIn(sampleUser))
        XCTAssertEqual(user.user?.title, "Sample Reader")

        let handoff = try decoder.decode(SignInResponse.self, from: Data(#"{"status":"username_required","signup_token":"demo-signup"}"#.utf8))
        XCTAssertEqual(try handoff.outcome(), .usernameRequired(token: "demo-signup"))

        let bare = try decoder.decode(SignInResponse.self, from: Data(#"{"id":"u2","username":"theo"}"#.utf8))
        XCTAssertEqual(bare.user?.title, "@theo", "a person with no display name is their handle")
    }

    // MARK: The cookie

    func testTheSessionCheckIsScopedToOneQuiltsHost() throws {
        let storage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "signin-test-\(UUID().uuidString)")
        storage.removeCookies(since: .distantPast)
        let a = URL(string: "https://a.example")!
        let b = URL(string: "https://b.example")!
        XCTAssertFalse(PatchworkAPI.hasSession(for: a, in: storage))

        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .name: PatchworkAPI.sessionCookie, .value: "opaque",
            .domain: "a.example", .path: "/", .secure: "TRUE",
        ]))
        storage.setCookie(cookie)
        XCTAssertTrue(PatchworkAPI.hasSession(for: a, in: storage), "the quilt that set it sees it")
        XCTAssertFalse(PatchworkAPI.hasSession(for: b, in: storage), "and no other quilt does")

        // A cookie by another name on the same host is not a session.
        let other = try XCTUnwrap(HTTPCookie(properties: [
            .name: "theme", .value: "muted", .domain: "b.example", .path: "/", .secure: "TRUE",
        ]))
        storage.setCookie(other)
        XCTAssertFalse(PatchworkAPI.hasSession(for: b, in: storage))

        // Clearing one host's session leaves the other host's cookies alone.
        PatchworkAPI.clearSession(for: a, in: storage)
        XCTAssertFalse(PatchworkAPI.hasSession(for: a, in: storage))
        XCTAssertEqual(storage.cookies(for: b)?.count, 1)
        storage.removeCookies(since: .distantPast)
    }
}
