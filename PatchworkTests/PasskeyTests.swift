// SPDX-License-Identifier: MPL-2.0

import AuthenticationServices
import XCTest
@testable import Patchwork

/// Passkeys can only be proved end to end on a quilt that lists this app,
/// so what is checked here is everything the server's parser and Apple's
/// association are strict about: the spelling of every field, base64url
/// without padding, which quilts are offered a passkey at all, and that
/// the list in code is the list in the entitlements.
final class PasskeyTests: XCTestCase {
    func testBase64URLIsUnpaddedAndURLSafe() {
        let bytes = Data([0xfb, 0xff, 0xbf, 0x00, 0x10])
        let text = bytes.base64URL
        XCTAssertFalse(text.contains("="), "the server reads a credential id with RawURLEncoding")
        XCTAssertFalse(text.contains("+"))
        XCTAssertFalse(text.contains("/"))
        XCTAssertEqual(Data(base64URL: text), bytes)
        XCTAssertEqual(Data(base64URL: "AQID"), Data([1, 2, 3]))
        XCTAssertEqual(Data(base64URL: "AQ"), Data([1]), "padding is put back before decoding")
    }

    func testAnAssertionIsSpelledAsTheWebSendsIt() throws {
        let body = PasskeyAssertionBody(credentialID: Data([1, 2]), clientDataJSON: Data([3]), authenticatorData: Data([4]),
                                        signature: Data([5]), userID: Data("u-1".utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body.json()) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["id", "rawId", "type", "response"], "never snake_case: raw_id is refused")
        XCTAssertEqual(object["id"] as? String, object["rawId"] as? String, "id must byte-equal rawId")
        XCTAssertEqual(object["type"] as? String, "public-key")
        let response = try XCTUnwrap(object["response"] as? [String: String])
        XCTAssertEqual(Set(response.keys), ["clientDataJSON", "authenticatorData", "signature", "userHandle"])
        XCTAssertEqual(response["userHandle"], Data("u-1".utf8).base64URL, "the server finds the person by it")
    }

    func testARegistrationCarriesItsNameAndAttachment() throws {
        let body = PasskeyRegistrationBody(credentialID: Data([9]), clientDataJSON: Data([8]), attestationObject: Data([7]), name: "iPhone")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body.json()) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["id", "rawId", "type", "authenticatorAttachment", "response", "name"])
        XCTAssertEqual(object["name"] as? String, "iPhone")
        XCTAssertEqual(object["authenticatorAttachment"] as? String, "platform")
        let response = try XCTUnwrap(object["response"] as? [String: String])
        XCTAssertEqual(Set(response.keys), ["clientDataJSON", "attestationObject"])
    }

    func testTheBeginAnswersDecode() throws {
        let login = #"{"publicKey":{"challenge":"Y2hhbGxlbmdl","timeout":300000,"rpId":"lancasterpatchwork.org","userVerification":"preferred"}}"#
        let request = try JSONDecoder().decode(PasskeyRequestOptions.self, from: Data(login.utf8))
        XCTAssertEqual(request.publicKey.rpId, "lancasterpatchwork.org")
        XCTAssertNil(request.publicKey.allowCredentials, "sign-in is username-less")
        XCTAssertEqual(Data(base64URL: request.publicKey.challenge), Data("challenge".utf8))

        let stepUp = #"{"publicKey":{"challenge":"AQ","rpId":"lancasterpatchwork.org","allowCredentials":[{"type":"public-key","id":"AQID","transports":["internal"]}]}}"#
        XCTAssertEqual(try JSONDecoder().decode(PasskeyRequestOptions.self, from: Data(stepUp.utf8)).publicKey.allowCredentials?.first?.id, "AQID")

        let create = #"{"publicKey":{"rp":{"name":"Lancaster Patchwork","id":"lancasterpatchwork.org"},"user":{"name":"rowan","displayName":"Rowan","id":"dS0x"},"challenge":"AQ","pubKeyCredParams":[{"type":"public-key","alg":-7}],"authenticatorSelection":{"residentKey":"required"}}}"#
        let creation = try JSONDecoder().decode(PasskeyCreationOptions.self, from: Data(create.utf8))
        XCTAssertEqual(creation.publicKey.user.name, "rowan")
        XCTAssertEqual(Data(base64URL: creation.publicKey.user.id), Data("u-1".utf8))
        XCTAssertEqual(creation.publicKey.rp.id, "lancasterpatchwork.org")
    }

    func testPasskeysAreOfferedOnlyOnAssociatedQuilts() {
        XCTAssertTrue(PasskeyDomains.supports(URL(string: "https://lancasterpatchwork.org")!))
        XCTAssertTrue(PasskeyDomains.supports(URL(string: "https://LancasterPatchwork.org")!))
        XCTAssertFalse(PasskeyDomains.supports(URL(string: "https://quilt.example.org")!), "a quilt reached by address has no association")
        XCTAssertFalse(PasskeyDomains.supports(URL(string: "https://localhost:8443")!))
        XCTAssertFalse(PasskeyDomains.supports(URL(string: "https://www.lancasterpatchwork.org")!), "the entitlement names one host exactly")
    }

    /// iOS gives an app no way to read its own entitlements, so the list in
    /// code is a copy. This keeps the copy honest.
    func testTheDomainListIsTheEntitlementsList() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Patchwork/Patchwork.entitlements")
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any])
        let domains = try XCTUnwrap(plist["com.apple.developer.associated-domains"] as? [String])
        let hosts = domains.compactMap { entry -> String? in
            guard entry.hasPrefix("webcredentials:") else { return nil }
            return String(entry.dropFirst("webcredentials:".count).split(separator: "?").first ?? "")
        }
        XCTAssertEqual(Set(hosts), Set(PasskeyDomains.all))
    }

    func testAPasskeySignsInFromTheAddressStepOnly() {
        let user = User(id: "u", username: "rowan", displayName: "Rowan", bio: nil, avatarUrl: nil, role: "member", email: nil)
        var flow = SignInFlow()
        flow.busy = true
        flow.apply(.passkeyAccepted(user))
        XCTAssertEqual(flow.step, .done(user))
        XCTAssertFalse(flow.busy)

        var codeStep = SignInFlow()
        codeStep.apply(.codeSent(email: "a@example.org"))
        codeStep.apply(.passkeyAccepted(user))
        XCTAssertEqual(codeStep.step, .code(email: "a@example.org"), "only the step that offers it accepts it")

        var dismissed = SignInFlow()
        dismissed.busy = true
        dismissed.apply(.passkeyDismissed)
        XCTAssertEqual(dismissed.step, .email)
        XCTAssertNil(dismissed.error, "closing the prompt is an answer, not a fault")
        XCTAssertFalse(dismissed.busy)
    }

    func testClosingThePromptSaysNothing() {
        XCTAssertNil(Passkeys.sentence(ASAuthorizationError(.canceled), for: .signIn))
        XCTAssertNotNil(Passkeys.sentence(ASAuthorizationError(.failed), for: .signIn))
        XCTAssertEqual(Passkeys.sentence(APIError.status(400), for: .stepUp),
                       "That passkey didn’t confirm it. Try again, or use a recovery code.")
    }
}
