// SPDX-License-Identifier: MPL-2.0

import AuthenticationServices
import SwiftUI
import UIKit

// Passkeys (web ADR 2026-09-20 "An instance vouches for an app"). A passkey
// belongs to a domain, and iOS lets an app use one only where the app says
// it is associated with that domain *and* the domain says it trusts the app:
// the app carries `webcredentials:<domain>` in its entitlements, and the
// quilt's admin lists this app's Team ID and bundle id under Administration
// → Settings → Apps, which the server renders as its
// apple-app-site-association file. A quilt reached by address, which is any
// quilt this client can open, has neither, so passkeys are offered only on
// the domains below and nowhere else; everywhere else the emailed code signs
// in and a recovery code confirms, exactly as before.
//
// The criteria for adding a domain are the README's (ADR obligation): the
// quilt's admin asks, lists this app, and the domain is added here and in
// the entitlements in one release.

// MARK: - Where

enum PasskeyDomains {
    /// Keep in step with `com.apple.developer.associated-domains` in
    /// `Patchwork.entitlements` (generated from project.yml); a unit test
    /// reads the file and checks.
    static let all: [String] = ["lancasterpatchwork.org"]

    static func supports(_ base: URL) -> Bool {
        guard let host = base.host()?.lowercased() else { return false }
        return all.contains(host)
    }
}

// MARK: - The wire

extension Data {
    /// Base64url without padding, the only spelling the server's parser
    /// takes for a credential's `id` (go-webauthn reads it with
    /// `RawURLEncoding`), and so the spelling used for every field.
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL: String) {
        var text = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        self.init(base64Encoded: text)
    }
}

/// `login/begin` and `step-up/begin`: a challenge, the relying party, and —
/// for step-up only — the person's own credentials.
struct PasskeyRequestOptions: Decodable {
    struct PublicKey: Decodable {
        let challenge: String
        let rpId: String?
        let allowCredentials: [Descriptor]?
    }
    struct Descriptor: Decodable { let id: String }
    let publicKey: PublicKey
}

/// `register/begin`: the relying party, who this is for, and a challenge.
struct PasskeyCreationOptions: Decodable {
    struct PublicKey: Decodable {
        struct RelyingParty: Decodable { let id: String? }
        struct Holder: Decodable { let id: String; let name: String }
        let rp: RelyingParty
        let user: Holder
        let challenge: String
    }
    let publicKey: PublicKey
}

/// What `login/finish` and `step-up/finish` read: the assertion, as the
/// web's `webauthn.js` serialises it, every binary field base64url.
struct PasskeyAssertionBody: Encodable, Equatable {
    struct Response: Encodable, Equatable {
        let clientDataJSON: String
        let authenticatorData: String
        let signature: String
        let userHandle: String
    }
    let id: String
    let rawId: String
    var type = "public-key"
    let response: Response

    init(credentialID: Data, clientDataJSON: Data, authenticatorData: Data, signature: Data, userID: Data) {
        id = credentialID.base64URL
        rawId = id
        response = Response(clientDataJSON: clientDataJSON.base64URL, authenticatorData: authenticatorData.base64URL,
                            signature: signature.base64URL, userHandle: userID.base64URL)
    }
}

/// What `register/finish` reads: the attestation, and the name the passkey
/// is listed under in Security (a sibling the parser ignores and the
/// handler keeps).
struct PasskeyRegistrationBody: Encodable, Equatable {
    struct Response: Encodable, Equatable {
        let clientDataJSON: String
        let attestationObject: String
    }
    let id: String
    let rawId: String
    var type = "public-key"
    var authenticatorAttachment = "platform"
    let response: Response
    let name: String

    init(credentialID: Data, clientDataJSON: Data, attestationObject: Data, name: String) {
        id = credentialID.base64URL
        rawId = id
        response = Response(clientDataJSON: clientDataJSON.base64URL, attestationObject: attestationObject.base64URL)
        self.name = name
    }

    /// Encoded as spelled: never through the snake-case encoder.
    func json() throws -> Data { try JSONEncoder().encode(self) }
}

extension PasskeyAssertionBody {
    func json() throws -> Data { try JSONEncoder().encode(self) }
}

/// One of the person's passkeys, as Security lists them (`GET auth/credentials`).
struct PasskeyCredential: Decodable, Identifiable, Equatable {
    let id: String
    let name: String?
    let createdAt: String?
    var title: String { (name?.isEmpty == false) ? name! : "Passkey" }
}

// MARK: - The words

enum Passkeys {
    enum Act { case signIn, enroll, stepUp }

    /// What a failed ceremony says, or nothing where the person simply
    /// closed the prompt — that was an answer, not a fault. The sentences
    /// are the web's (`passkeyErrorMessage`), with "this site" made "this
    /// quilt" and "an email link below" made the app's own email sign-in.
    static func sentence(_ error: Error, for act: Act) -> String? {
        if let auth = error as? ASAuthorizationError {
            switch auth.code {
            case .canceled: return nil
            default:
                switch act {
                case .enroll: return "Passkey setup was cancelled or didn’t finish. You can try again."
                case .stepUp: return "Passkey check was cancelled or didn’t finish. You can try again, or confirm with a recovery code."
                case .signIn: return "No passkey for this quilt was found on this device, or the prompt was dismissed. Sign in with your email or a recovery code instead, then add a passkey in Settings → Security."
                }
            }
        }
        if let refusal = error as? APIError {
            if refusal.httpStatus == 429 { return "Too many attempts. Wait a couple of minutes, then try again." }
            if case .message = refusal, refusal.httpStatus != 400 { return SignInModel.sentence(error) }
        }
        switch act {
        case .enroll: return "The quilt didn’t accept that passkey. You can try again."
        case .stepUp: return "That passkey didn’t confirm it. Try again, or use a recovery code."
        case .signIn: return "That passkey didn’t sign you in here. Sign in with your email or a recovery code instead."
        }
    }

    /// What a new passkey is called until the person renames it: the kind
    /// of device it lives on, the way the web guesses from the browser.
    static var defaultName: String { UIDevice.current.model }
}

// MARK: - The ceremony

/// One system passkey prompt, awaited. The controller is held for as long as
/// the prompt is up (its delegate is weak), and the answer is handed back on
/// the main actor, where the prompt was asked for.
@MainActor final class PasskeyCeremony: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var controller: ASAuthorizationController?
    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated { finish(.success(authorization)) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }

    private func finish(_ result: Result<ASAuthorization, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }
}

// MARK: - The calls

extension PatchworkAPI {
    /// The relying party the begin answer names, or this quilt's own host.
    private func relyingParty(_ named: String?) -> String { named ?? base.host() ?? "" }

    /// Username-less sign-in (`BeginDiscoverableLogin`): the system offers
    /// whichever passkey this device holds for the quilt, and the server
    /// finds the person from the passkey's user handle. Ends on the same
    /// session cookie an emailed code sets.
    @MainActor func signInWithPasskey() async throws -> User {
        let begin = try await postJSON("auth/webauthn/login/begin", json: nil)
        let options = try JSONDecoder().decode(PasskeyRequestOptions.self, from: begin)
        guard let challenge = Data(base64URL: options.publicKey.challenge) else { throw APIError.response }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingParty(options.publicKey.rpId))
        let authorization = try await PasskeyCeremony().perform(provider.createCredentialAssertionRequest(challenge: challenge))
        guard let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else { throw APIError.response }
        let body = PasskeyAssertionBody(credentialID: assertion.credentialID, clientDataJSON: assertion.rawClientDataJSON,
                                        authenticatorData: assertion.rawAuthenticatorData, signature: assertion.signature,
                                        userID: assertion.userID)
        let finish = try await postJSON("auth/webauthn/login/finish", json: try body.json())
        guard let user = try Self.decodeAnswer(SignInResponse.self, from: finish).user else { throw APIError.response }
        return user
    }

    /// Step-up with a passkey: the person's own credentials only, and on
    /// success the same five-minute window a recovery code opens.
    @MainActor func stepUpWithPasskey() async throws {
        let begin = try await postJSON("auth/step-up/begin", json: nil)
        let options = try JSONDecoder().decode(PasskeyRequestOptions.self, from: begin)
        guard let challenge = Data(base64URL: options.publicKey.challenge) else { throw APIError.response }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingParty(options.publicKey.rpId))
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        request.allowedCredentials = (options.publicKey.allowCredentials ?? []).compactMap { descriptor in
            Data(base64URL: descriptor.id).map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0) }
        }
        let authorization = try await PasskeyCeremony().perform(request)
        guard let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else { throw APIError.response }
        let body = PasskeyAssertionBody(credentialID: assertion.credentialID, clientDataJSON: assertion.rawClientDataJSON,
                                        authenticatorData: assertion.rawAuthenticatorData, signature: assertion.signature,
                                        userID: assertion.userID)
        _ = try await postJSON("auth/step-up/finish", json: try body.json())
    }

    /// Adds a passkey to the signed-in account, named for this device.
    @MainActor func addPasskey(name: String = Passkeys.defaultName) async throws {
        let begin = try await postJSON("auth/webauthn/register/begin", json: nil)
        let options = try JSONDecoder().decode(PasskeyCreationOptions.self, from: begin)
        guard let challenge = Data(base64URL: options.publicKey.challenge),
              let userID = Data(base64URL: options.publicKey.user.id) else { throw APIError.response }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingParty(options.publicKey.rp.id))
        let request = provider.createCredentialRegistrationRequest(challenge: challenge, name: options.publicKey.user.name, userID: userID)
        let authorization = try await PasskeyCeremony().perform(request)
        guard let registration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
              let attestation = registration.rawAttestationObject else { throw APIError.response }
        let body = PasskeyRegistrationBody(credentialID: registration.credentialID, clientDataJSON: registration.rawClientDataJSON,
                                           attestationObject: attestation, name: name)
        _ = try await postJSON("auth/webauthn/register/finish", json: try body.json())
    }

    func passkeys() async throws -> [PasskeyCredential] { try await get("auth/credentials") }

    func renamePasskey(_ id: String, to name: String) async throws {
        try await sendVoid("PATCH", "auth/credentials/\(id)", body: ["name": name.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    /// Removing a passkey also signs out every other device (the server's
    /// rule): a lost phone's passkey goes, and so do its sessions.
    func removePasskey(_ id: String) async throws { try await deleteVoid("auth/credentials/\(id)") }
}
