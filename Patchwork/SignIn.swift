// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// Signing in, as a value.
///
/// The flow is three steps and the server decides which of them a person
/// walks: an address, the six digits it was emailed, and — only for an address
/// with no account yet — a username. Every transition is a method on this
/// struct rather than a line inside a view, so the whole thing can be driven
/// and checked with no window open. The views below only draw a step and hand
/// back events.
struct SignInFlow: Equatable {
    /// Where the person is. The associated values are what the next step needs
    /// and nothing else: the address to say "we sent a code to …", the signup
    /// token the quilt handed back, the user the quilt ended up naming.
    enum Step: Equatable {
        case email
        case code(email: String)
        case username(token: String, email: String)
        case done(User)
    }

    /// What happened, said in the flow's own words rather than the network's.
    enum Event: Equatable {
        /// `auth/magic-link` accepted the address (it accepts every real one).
        case codeSent(email: String)
        /// `auth/magic-link/verify` named a user.
        case verified(User)
        /// `auth/magic-link/verify` said the address has no account yet.
        case usernameRequired(token: String)
        /// `auth/signup` made the account.
        case created(User)
        /// A refusal, in the sentence the person is shown. It never moves the
        /// step: a wrong code leaves the code in front of them to correct.
        case rejected(String)
        /// "Use a different email" — the one way back.
        case useDifferentEmail
    }

    private(set) var step: Step = .email
    /// The fields. They outlive their step on purpose: going back to the
    /// address step keeps the address that was typed.
    var email = ""
    /// Exactly what was typed. The digits are picked out of it when the code
    /// is sent and when the button asks whether it is complete, rather than by
    /// rewriting the field under the person's cursor: a `TextField` draws the
    /// keystroke before it re-reads its binding, so a setter that edits the
    /// text shows them one thing and holds another.
    var code = ""
    var username = ""
    var displayName = ""
    /// The inline sentence under the step's field, if any.
    private(set) var error: String?
    /// A request is out. The primary button waits rather than repeating.
    var busy = false
    /// The username hint stays muted until the person leaves the field or
    /// submits — a rule typed into halfway is not yet a mistake.
    var usernameTouched = false

    // MARK: Transitions

    mutating func apply(_ event: Event) {
        switch event {
        case .codeSent(let email):
            guard step == .email else { return }
            self.email = email
            code = ""
            error = nil
            step = .code(email: email)
        case .verified(let user):
            guard case .code = step else { return }
            error = nil
            step = .done(user)
        case .usernameRequired(let token):
            guard case .code(let email) = step, !token.isEmpty else { return }
            error = nil
            usernameTouched = false
            step = .username(token: token, email: email)
        case .created(let user):
            guard case .username = step else { return }
            error = nil
            step = .done(user)
        case .rejected(let message):
            error = message
        case .useDifferentEmail:
            guard case .code = step else { return }
            code = ""
            error = nil
            step = .email
        }
        busy = false
    }

    /// Asking again from the code step: the error goes, the step does not.
    mutating func clearError() { error = nil }

    // MARK: What each step will accept

    /// Deliberately loose. The quilt is the authority on what an address is —
    /// it answers 400 with a sentence — so this only stops an empty submit and
    /// the obvious typo, rather than inventing a second rule the server does
    /// not have.
    var canSendCode: Bool {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 2, !value.hasPrefix("@"), !value.hasSuffix("@") else { return false }
        return value.contains("@") && !value.contains(" ")
    }
    var canVerify: Bool { Self.isCompleteCode(code) }
    var canCreateAccount: Bool { !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The code as it is sent: people read six digits aloud in twos and threes
    /// and type the spaces back in. The server takes them out anyway; this
    /// takes them out first so the count below means something.
    static func normalize(code: String) -> String { String(code.filter(\.isNumber)) }
    /// Six digits, no more: a seventh is a typo, and the button says so by
    /// staying unpressable rather than sending the first six.
    static func isCompleteCode(_ code: String) -> Bool { normalize(code: code).count == 6 }

    /// The server's rule, mirrored so a hint can be shown while typing:
    /// `^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$` — 3 to 30 characters, lowercase
    /// letters, numbers and hyphens, and never a hyphen at either end. The
    /// quilt still has the last word; this only saves a round trip.
    static let usernamePattern = "^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$"
    static let usernameRule = "Three to thirty characters: lowercase letters, numbers and hyphens, with a letter or number at each end."
    static func isValidUsername(_ value: String) -> Bool {
        // The whole string, not a line of it: ICU's `$` also matches before a
        // trailing newline, and "abc\n" is not a username.
        guard let range = value.range(of: usernamePattern, options: .regularExpression) else { return false }
        return range == value.startIndex..<value.endIndex
    }
    /// The sentence a username earns when it breaks the rule.
    static let usernameProblem = "That username won’t work. " + usernameRule
}

/// The flow with a quilt behind it: the same value, plus the three posts.
@MainActor final class SignInModel: ObservableObject {
    @Published var flow = SignInFlow()
    private let api: PatchworkAPI
    init(api: PatchworkAPI) { self.api = api }

    var step: SignInFlow.Step { flow.step }

    func sendCode() async {
        let email = flow.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flow.busy else { return }
        flow.busy = true
        flow.clearError()
        do {
            try await api.requestCode(email: email)
            flow.apply(.codeSent(email: email))
        } catch {
            flow.apply(.rejected(Self.sentence(error)))
        }
    }

    /// A second code for the same address. The server rate-limits this, and a
    /// refusal to send one more is not the reader's problem — the code they
    /// already have still works — so it is swallowed rather than shown.
    func resendCode() async {
        guard case .code(let email) = flow.step, !flow.busy else { return }
        flow.busy = true
        flow.clearError()
        try? await api.requestCode(email: email)
        flow.busy = false
    }

    func verify() async {
        guard case .code(let email) = flow.step, flow.canVerify, !flow.busy else { return }
        flow.busy = true
        flow.clearError()
        do {
            switch try await api.verify(email: email, code: flow.code) {
            case .signedIn(let user): flow.apply(.verified(user))
            case .usernameRequired(let token): flow.apply(.usernameRequired(token: token))
            }
        } catch {
            flow.apply(.rejected(Self.codeSentence(error)))
        }
    }

    func createAccount() async {
        guard case .username(let token, _) = flow.step, !flow.busy else { return }
        let username = flow.username.trimmingCharacters(in: .whitespacesAndNewlines)
        flow.usernameTouched = true
        guard SignInFlow.isValidUsername(username) else {
            flow.apply(.rejected(SignInFlow.usernameProblem))
            return
        }
        flow.busy = true
        flow.clearError()
        do {
            let user = try await api.signUp(token: token, username: username, displayName: flow.displayName.trimmingCharacters(in: .whitespacesAndNewlines))
            flow.apply(.created(user))
        } catch {
            flow.apply(.rejected(Self.sentence(error)))
        }
    }

    /// The quilt's sentence where it wrote one, and a plain one where it did not.
    static func sentence(_ error: Error) -> String {
        if case APIError.message(let message, _) = error { return message }
        if error is APIError { return error.localizedDescription }
        return "The quilt could not be reached. Check your connection and try again."
    }
    /// The one refusal worded here rather than by the server: `verify` answers
    /// every failure with the same "invalid or expired code", which is true
    /// but says nothing about what to do next.
    static func codeSentence(_ error: Error) -> String {
        if case APIError.message = error { return "That code did not work. Check the digits, or send a new one." }
        if case APIError.status(400) = error { return "That code did not work. Check the digits, or send a new one." }
        return sentence(error)
    }
}

/// Sign-in as a sheet: a stack of three plain steps, each one a sentence, a
/// field and one thing to press.
struct SignInSheet: View {
    let quiltName: String
    let onSignedIn: (User) -> Void
    @StateObject private var model: SignInModel
    @Environment(\.dismiss) private var dismiss
    /// Leaving the username field is what turns its hint into a correction.
    @FocusState private var usernameFocused: Bool

    init(api: PatchworkAPI, quiltName: String, onSignedIn: @escaping (User) -> Void) {
        self.quiltName = quiltName
        self.onSignedIn = onSignedIn
        _model = StateObject(wrappedValue: SignInModel(api: api))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch model.step {
                    case .email: emailStep
                    case .code(let email): codeStep(email: email)
                    case .username: usernameStep
                    case .done: ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.pwGround.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onChange(of: model.flow.step) { _, now in
            // The account menu is the confirmation; there is no "you're in" page.
            if case .done(let user) = now { onSignedIn(user); dismiss() }
        }
    }

    // MARK: Steps

    private var emailStep: some View {
        Group {
            heading("Sign in to \(quiltName)")
            Text("Enter the email you use here. \(quiltName) will send you a six-digit code.")
                .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
            // Verbatim, and the label is what VoiceOver reads: a placeholder
            // built from a string literal is parsed as Markdown, and SwiftUI
            // turns anything shaped like an address into a blue link — in a
            // field whose whole job is to hold an address.
            TextField(text: $model.flow.email, prompt: Text(verbatim: "you@example.org")) { Text("Email address") }
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit { send() }
                .fieldStyle()
                .accessibilityIdentifier("signInEmail")
            inlineError
            primary("Send code", identifier: "signInSendCode", enabled: model.flow.canSendCode, action: send)
        }
    }

    private func codeStep(email: String) -> some View {
        Group {
            heading("Check your email")
            Text("We sent a code to \(email). Enter it here; it also works as a link on the web.")
                .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
            TextField("123456", text: $model.flow.code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .fieldStyle()
                .accessibilityIdentifier("signInCode")
                // Editing is an answer to the refusal; the refusal goes.
                .onChange(of: model.flow.code) { _, _ in model.flow.clearError() }
            inlineError
            primary("Continue", identifier: "signInContinue", enabled: model.flow.canVerify) {
                Task { await model.verify() }
            }
            HStack(spacing: 20) {
                Button { Task { await model.resendCode() } } label: {
                    Text("Send a new code").font(Font.pw.subheadline).inkAction("arrow.clockwise")
                }
                .buttonStyle(.plain).accessibilityIdentifier("signInResend")
                Button { model.flow.apply(.useDifferentEmail) } label: {
                    Text("Use a different email").font(Font.pw.subheadline).inkAction("arrow.uturn.backward")
                }
                .buttonStyle(.plain).accessibilityIdentifier("signInDifferentEmail")
            }
            .padding(.top, 2)
        }
    }

    private var usernameStep: some View {
        Group {
            heading("Choose your username")
            Text(SignInFlow.usernameRule).font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
            TextField("yourname", text: $model.flow.username)
                .keyboardType(.asciiCapable)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .fieldStyle()
                .accessibilityIdentifier("signInUsername")
                .focused($usernameFocused)
                .onChange(of: model.flow.username) { _, _ in model.flow.clearError() }
                .onSubmit { model.flow.usernameTouched = true }
                .onChange(of: usernameFocused) { was, now in if was, !now { model.flow.usernameTouched = true } }
            // While they are still typing it is a hint; once they have left
            // the field or pressed the button, the same fact is a mistake.
            if !model.flow.username.isEmpty, !SignInFlow.isValidUsername(model.flow.username.trimmingCharacters(in: .whitespacesAndNewlines)), model.flow.error == nil {
                Text(model.flow.usernameTouched ? SignInFlow.usernameProblem : "Lowercase letters, numbers and hyphens.")
                    .font(Font.pw.footnote)
                    .foregroundStyle(model.flow.usernameTouched ? Color.pwText : Color.pwTextMuted)
                    .accessibilityIdentifier(model.flow.usernameTouched ? "signInUsernameError" : "signInUsernameHint")
            }
            // The refusal belongs under the field it is about — a sentence at
            // the foot of the step, below the optional display name, reads as
            // being about the button.
            inlineError
            VStack(alignment: .leading, spacing: 6) {
                Text("Display name (optional)").font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                TextField("How you want to be listed", text: $model.flow.displayName)
                    .textContentType(.name)
                    .fieldStyle()
                    .accessibilityIdentifier("signInDisplayName")
            }
            .padding(.top, 4)
            primary("Create account", identifier: "signInCreate", enabled: model.flow.canCreateAccount) {
                Task { await model.createAccount() }
            }
        }
    }

    // MARK: Parts

    /// A step saying its own name: the one display-face moment in the sheet.
    private func heading(_ text: String) -> some View {
        Text(text)
            .font(Font.pw.displayTitle2)
            .foregroundStyle(Color.pwText)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var inlineError: some View {
        if let error = model.flow.error {
            Label { Text(error).font(Font.pw.footnote) } icon: {
                Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
            }
            .foregroundStyle(Color.pwText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("signInError")
        }
    }

    private func primary(_ title: String, identifier: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if model.flow.busy { ProgressView() } else { Text(title).font(Font.pw.headline) }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.pwAccent)
        .controlSize(.large)
        .disabled(!enabled || model.flow.busy)
        .accessibilityIdentifier(identifier)
        .padding(.top, 4)
    }

    private func send() { Task { await model.sendCode() } }
}
