// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// An account invite link (web `/invite/:token`, InviteLanding.svelte; web
// ADRs 001 and 071): a quilt's admin makes a signup link and sends it by
// hand, and whoever opens it makes an account on that quilt. It admits
// nobody to any patch. The app cannot be opened by the link — this client
// connects to any quilt by address, and associated domains are declared per
// domain ahead of time — so the link is pasted here instead.
//
// Unlike the web page, this one notices a session already on the quilt:
// redeeming the link makes a second account and replaces the first one's
// session, which is never what somebody already signed in meant to do.

/// Reading what was pasted.
enum InviteLink {
    enum Parsed: Equatable {
        case token(String)
        /// A link for a different quilt than the one open here.
        case otherQuilt(host: String)
        case notALink
    }

    /// `https://<host>/invite/<token>`, a trailing slash or query tolerated,
    /// or the bare token on its own. The host has to be this quilt's: a link
    /// is the quilt it was made on.
    static func parse(_ text: String, quiltHost: String) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .notALink }
        if !trimmed.contains("/") && !trimmed.contains(" ") && !trimmed.contains(".") {
            return .token(trimmed)
        }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate), let host = url.host()?.lowercased(), !host.isEmpty else { return .notALink }
        let parts = url.path().split(separator: "/").map(String.init)
        guard parts.count == 2, parts[0] == "invite", !parts[1].isEmpty else { return .notALink }
        guard host == quiltHost.lowercased() else { return .otherQuilt(host: host) }
        return .token(parts[1].removingPercentEncoding ?? parts[1])
    }

    static let notALinkSentence = "That isn't an invite link. It looks like https://\u{2026}/invite/\u{2026}"
    static func otherQuiltSentence(_ host: String) -> String {
        "This link is for \(host). Switch to that quilt first, then paste it there."
    }
    static func signedInSentence(_ handle: String) -> String {
        "You're already signed in to this quilt as \(handle). An invite link makes a new account, and signing in with it would replace this one's session. Sign out first if a second account is what you want."
    }
    /// The web's sentence for a link that will not open, whatever the
    /// server's reason.
    static let deadLinkTitle = "This invite didn't work"
    static let deadLinkSentence = "This invite link may have expired or already been used. Ask your community admin for a new one."
}

struct InviteValidation: Decodable { let valid: Bool? }

/// `POST auth/invite`. The email travels only where the quilt can send mail
/// (and is then required); without mail, recovery codes are the way back in.
struct InviteRedemption: Encodable, Equatable {
    let token: String
    let username: String
    let displayName: String?
    let email: String?
    init(token: String, username: String, displayName: String, email: String, emailEnabled: Bool) {
        self.token = token
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = name.isEmpty ? nil : name
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = emailEnabled && !address.isEmpty ? address : nil
    }
}

extension PatchworkAPI {
    func validateInvite(_ token: String) async throws {
        let escaped = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? token
        let _: InviteValidation = try await get("auth/invite/\(escaped)/validate")
    }
    func redeemInvite(_ body: InviteRedemption) async throws -> User { try await post("auth/invite", body: body) }
}

// MARK: - The sheet

struct InviteSheet: View {
    private enum Step: Equatable { case paste, account(token: String), codes([String]), done }

    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.paste
    @State private var link = ""
    @State private var username = ""
    @State private var displayName = ""
    @State private var email = ""
    @State private var busy = false
    @State private var failure: String?
    @State private var dead = false
    @State private var saved = false
    /// Who the new account is, held while its recovery codes are read.
    @State private var made: User?

    private var quiltName: String { session.instance?.name ?? session.quilt.name }
    private var emailEnabled: Bool { session.instance?.emailEnabled == true }

    /// The recovery codes are on screen: the one step that cannot be left
    /// until they are saved.
    private var holdingCodes: Bool { if case .codes = step { return true } else { return false } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let me = session.me, made == nil {
                        // The guard the web does not have.
                        heading("You're signed in")
                        Text(InviteLink.signedInSentence(me.handle))
                            .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("inviteSignedIn")
                    } else {
                        switch step {
                        case .paste: pasteStep
                        case .account: accountStep
                        case .codes(let codes): codesStep(codes)
                        case .done: ProgressView().frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.pwGround.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                // A condition with only one branch: an empty branch is an
                // `EmptyView` as toolbar content, which only iOS 27 accepts.
                if !holdingCodes {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                }
            }
        }
        // The codes are the only way back in on a quilt with no mail: the
        // sheet is not let go of until they are saved.
        .interactiveDismissDisabled(busy || holdingCodes)
    }

    // MARK: Steps

    @ViewBuilder private var pasteStep: some View {
        heading("Have an invite link?")
        Text("Paste the invite link \(quiltName) sent you. It makes an account here; it doesn't add you to any patch.")
            .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
            .fixedSize(horizontal: false, vertical: true)
        TextField(text: $link, prompt: Text(verbatim: "https://\(session.quilt.url.host() ?? "")/invite/…")) { Text("Invite link") }
            .keyboardType(.URL).textContentType(.URL)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .submitLabel(.go)
            .onSubmit { Task { await check() } }
            .onChange(of: link) { _, _ in failure = nil; dead = false }
            .fieldStyle()
            .accessibilityIdentifier("inviteLink")
        if dead {
            VStack(alignment: .leading, spacing: 4) {
                Text(InviteLink.deadLinkTitle).font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwText)
                Text(InviteLink.deadLinkSentence).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("inviteDead")
        }
        refusal
        primary("Continue", identifier: "inviteContinue", enabled: !link.trimmingCharacters(in: .whitespaces).isEmpty) {
            Task { await check() }
        }
    }

    @ViewBuilder private var accountStep: some View {
        heading("You're invited")
        Text("A patchwork user sent you this link. Pick a username to join.")
            .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
        field("Username", hint: "3-30 characters: lowercase letters, numbers, hyphens. This becomes your profile address and can't be changed later.") {
            TextField("yourname", text: $username)
                .keyboardType(.asciiCapable).textContentType(.username)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .fieldStyle()
                .accessibilityIdentifier("inviteUsername")
        }
        field("Display Name") {
            TextField("How you want to be listed", text: $displayName)
                .textContentType(.name)
                .fieldStyle()
                .accessibilityIdentifier("inviteDisplayName")
        }
        if emailEnabled {
            field("Email", hint: "How you sign in if you ever lose your passkey. We send sign-in links to it and nothing else.") {
                TextField(text: $email, prompt: Text(verbatim: "you@example.org")) { Text("Email") }
                    .keyboardType(.emailAddress).textContentType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .fieldStyle()
                    .accessibilityIdentifier("inviteEmail")
            }
        }
        refusal
        primary("Create Account", identifier: "inviteCreate", enabled: canCreate) { Task { await create() } }
        AgreementLine()
    }

    private var canCreate: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && (!emailEnabled || email.contains("@"))
    }

    /// No mail on this quilt: the codes are the floor (web ADR 071), shown
    /// once, and the sheet waits for the reader to say they kept them.
    @ViewBuilder private func codesStep(_ codes: [String]) -> some View {
        heading("You're in")
        Text("This quilt can't send email, so these recovery codes are how you get back into your account. Each works once. Keep them somewhere safe; they won't be shown again.")
            .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
            .fixedSize(horizontal: false, vertical: true)
        CodeBlock(text: codes.joined(separator: "\n"))
            .accessibilityIdentifier("inviteCodes")
        Toggle(isOn: $saved) { Text("I have saved these somewhere safe").font(Font.pw.body) }
            .tint(Color.pwAccent)
            .fieldStyle()
            .accessibilityIdentifier("inviteCodesSaved")
        primary("Take a look around", identifier: "inviteDone", enabled: saved) { finish() }
    }

    // MARK: Parts

    private func heading(_ text: String) -> some View {
        Text(text).font(Font.pw.displayTitle2).foregroundStyle(Color.pwText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func field<Content: View>(_ title: String, hint: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
            content()
            if let hint {
                Text(hint).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var refusal: some View {
        if let failure {
            Label { Text(failure).font(Font.pw.footnote) } icon: {
                Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
            }
            .foregroundStyle(Color.pwText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("inviteError")
        }
    }

    private func primary(_ title: String, identifier: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group { if busy { ProgressView().tint(.white) } else { Text(title).font(Font.pw.headline) } }
                .frame(maxWidth: .infinity, minHeight: 28)
                .foregroundStyle(enabled && !busy ? Color.white : Color.pwTextMuted)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.pwAccent)
        .controlSize(.large)
        .disabled(!enabled || busy)
        .accessibilityIdentifier(identifier)
        .padding(.top, 4)
    }

    // MARK: Acts

    private func check() async {
        failure = nil
        dead = false
        switch InviteLink.parse(link, quiltHost: session.quilt.url.host() ?? "") {
        case .notALink: failure = InviteLink.notALinkSentence
        case .otherQuilt(let host): failure = InviteLink.otherQuiltSentence(host)
        case .token(let token):
            busy = true
            defer { busy = false }
            do {
                try await session.api.validateInvite(token)
                withAnimation { step = .account(token: token) }
            } catch let error as APIError where error.httpStatus == 404 {
                dead = true
            } catch {
                failure = sentenceCased(SignInModel.sentence(error))
            }
        }
    }

    private func create() async {
        guard case .account(let token) = step else { return }
        failure = nil
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard SignInFlow.isValidUsername(name) else { failure = SignInFlow.usernameProblem; return }
        busy = true
        defer { busy = false }
        do {
            let user = try await session.api.redeemInvite(InviteRedemption(token: token, username: name, displayName: displayName,
                                                                           email: email, emailEnabled: emailEnabled))
            made = user
            if emailEnabled {
                finish()
            } else {
                // The new session is the one asking: the codes are its own.
                let codes = try await session.api.generateRecoveryCodes()
                withAnimation { step = .codes(codes) }
            }
        } catch {
            failure = sentenceCased(SignInModel.sentence(error))
        }
    }

    private func finish() {
        guard let made else { return }
        step = .done
        session.signedIn(made)
        dismiss()
    }
}
