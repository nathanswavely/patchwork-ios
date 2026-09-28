// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import UIKit

// Step-up (web ADR 017, ADR 099): an act that cannot be undone asks for a
// fresh proof that the person is at the keyboard, not only the session they
// already hold. The server says so with a 403 whose `code` is
// `sudo_required` or `passkey_required`; the proof this client can offer is
// a recovery code, which opens the same five-minute window a passkey opens
// on the web. Passkeys are not offered here at all — this build has none —
// so nothing on these screens mentions them.

// MARK: - The code itself

/// A recovery code as the server reads it (`internal/auth/recovery.go`).
enum RecoveryCode {
    /// The paper-safe alphabet: no 0/o and no 1/l/i, so a code copied onto
    /// paper and typed back cannot be misread.
    static let alphabet = "abcdefghjkmnpqrstuvwxyz23456789"
    /// Twelve characters, printed `xxxx-xxxx-xxxx`.
    static let length = 12

    /// The server's `NormalizeRecoveryCode`, mirrored: trim, lowercase, and
    /// drop the hyphens and spaces, so a code written down in capitals or
    /// with its hyphens in other places is still the same code. The server
    /// normalises again; this copy is what lets the button know whether
    /// twelve characters have been typed.
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    /// Twelve characters once normalised. Which characters is the server's
    /// question: a code typed with a letter outside the alphabet is simply
    /// not one of theirs, and the server says so in its own sentence.
    static func isComplete(_ raw: String) -> Bool { normalize(raw).count == length }
}

// MARK: - The contract

/// `GET auth/step-up`: what this session could confirm with right now.
struct StepUpStatus: Decodable, Equatable {
    let hasPasskey: Bool?
    /// A window is already open on this session.
    let active: Bool?
    let windowSecs: Int?
    /// Unused codes issued *before* this session began — the only ones that
    /// can confirm anything (ADR 099). Codes made during this sign-in are
    /// not counted.
    let recoveryReady: Int?
    init(hasPasskey: Bool? = false, active: Bool? = false, windowSecs: Int? = 300, recoveryReady: Int?) {
        self.hasPasskey = hasPasskey; self.active = active; self.windowSecs = windowSecs; self.recoveryReady = recoveryReady
    }
}

/// `GET auth/recovery-codes`: counts only. The codes are shown once, when made.
struct RecoveryCodeStatus: Decodable, Equatable {
    let total: Int
    let remaining: Int
    var summary: String {
        total == 0 ? "No recovery codes yet" : "\(remaining) of \(total) remaining"
    }
}

/// `POST auth/recovery-codes`: the one answer that ever carries the codes.
private struct RecoveryBatch: Decodable { let codes: [String] }

/// `POST auth/step-up/recovery`, answered 200.
struct StepUpGrant: Decodable, Equatable {
    let active: Bool?
    let expiresAt: String?
    let codesRemaining: Int?
    let usedRecoveryCode: Bool?
}

extension PatchworkAPI {
    func stepUpStatus() async throws -> StepUpStatus { try await get("auth/step-up") }
    /// Burn one code to open the window. 400 names which of three things
    /// went wrong (`no_recovery_codes`, `recovery_codes_too_new`,
    /// `invalid_code`) and 429 is the rate limit.
    func stepUp(recoveryCode: String) async throws -> StepUpGrant {
        try await post("auth/step-up/recovery", body: ["code": RecoveryCode.normalize(recoveryCode)])
    }
    func recoveryCodeStatus() async throws -> RecoveryCodeStatus { try await get("auth/recovery-codes") }
    /// A fresh batch of ten, replacing every earlier one, used or not.
    func generateRecoveryCodes() async throws -> [String] {
        let batch: RecoveryBatch = try await post("auth/recovery-codes", body: NoBody())
        return batch.codes
    }
    /// Sign in with a username and a code instead of an email (web ADR 020).
    /// The server answers every failure with the same sentence on purpose,
    /// so a stranger cannot learn which usernames exist; the window is open
    /// on arrival (ADR 099), because redeeming a code is itself the proof.
    func signIn(username: String, recoveryCode: String) async throws -> User {
        let response: SignInResponse = try await post("auth/recovery", body: [
            "username": username.trimmingCharacters(in: .whitespacesAndNewlines),
            "code": RecoveryCode.normalize(recoveryCode),
        ])
        guard let user = response.user else { throw APIError.response }
        return user
    }
}

// MARK: - The decisions, as values

enum StepUp {
    /// The two refusals that mean "prove it's you, then ask again".
    static let refusalCodes: Set<String> = ["sudo_required", "passkey_required"]

    static func needsStepUp(_ error: Error) -> Bool {
        guard let code = (error as? APIError)?.code else { return false }
        return refusalCodes.contains(code)
    }

    /// What the Confirm sheet shows: exactly one of three things.
    enum Confirm: Equatable {
        /// There are codes this session can confirm with.
        case enterCode(ready: Int)
        /// There are codes, but every one of them was made during this
        /// sign-in, which proves nothing: sign out and back in with one.
        case signInAgain
        /// There are no codes to use at all.
        case makeCodes
    }

    /// `recovery_ready` decides first, because it is the server's own count
    /// of what would be taken. Without a ready code, what the account still
    /// holds decides between signing in again and making a set. "Holds" is
    /// unused codes rather than codes ever made: a batch that has all been
    /// spent cannot sign anybody back in.
    static func decide(status: StepUpStatus, codes: RecoveryCodeStatus?) -> Confirm {
        let ready = status.recoveryReady ?? 0
        if ready > 0 { return .enterCode(ready: ready) }
        if let codes, codes.remaining > 0 { return .signInAgain }
        return .makeCodes
    }

    /// The four ways a code can fail, each its own sentence, because each
    /// asks something different of the person (ADR 099): try another code,
    /// wait, sign in again, or make a set. One shrug for all four would leave
    /// somebody retyping a code that will never work.
    static func failureSentence(code: String?, status: Int?) -> String {
        if status == 429 || code == "rate_limited" {
            return "Too many attempts. Wait a couple of minutes, then try again."
        }
        switch code {
        case "no_recovery_codes":
            return "This account has no unused recovery codes, so there is nothing to confirm with. Make a new set, then sign out and back in with one of them."
        case "recovery_codes_too_new":
            return "Every code you hold was made during this sign-in, so none of them can confirm it yet. Sign out, then sign back in with one of them: you arrive confirmed."
        default:
            return "That code isn’t one of yours, or it has already been used. Each code works once; try another from your set."
        }
    }

    /// Said after a code has been spent, while two or fewer are left: at
    /// zero there is no way to confirm anything until a new set is made, and
    /// a new set costs a sign-out before it counts.
    static func runningLow(remaining: Int) -> String? {
        guard remaining <= 2 else { return nil }
        if remaining == 0 {
            return "That was your last recovery code. Make a new set in Security before you need to confirm anything again."
        }
        return "\(remaining) recovery \(remaining == 1 ? "code" : "codes") left. Make a new set in Security before they run out."
    }
}

// MARK: - The gate

/// Run an act; if the quilt asks for step-up, present the Confirm sheet and,
/// once it reports the window open, run the act once more. Only once: a
/// second refusal means something is wrong, and asking again would be a loop.
///
/// The sheet is presented by `.stepUpSheet(_:api:)` on whichever screen owns
/// the gate, and it answers after it has gone — `onDismiss` resumes the
/// waiting act — so whatever the act does next (dismiss Settings, sign out)
/// never races a sheet still on its way down.
@MainActor final class StepUpGate: ObservableObject {
    struct Prompt: Identifiable { let id = UUID() }
    enum Outcome: Equatable { case confirmed, cancelled, signOut }
    /// The person chose to sign out from the sheet (the too-new path). The
    /// act's owner decides what that means for its own screens.
    struct SignOutRequested: Error {}

    @Published var prompt: Prompt?
    private var waiting: CheckedContinuation<Outcome, Never>?
    private var outcome = Outcome.cancelled

    func run<T>(_ act: () async throws -> T) async throws -> T {
        do { return try await act() }
        catch {
            guard StepUp.needsStepUp(error) else { throw error }
            switch await ask() {
            case .confirmed: return try await act()
            case .cancelled: throw error
            case .signOut: throw SignOutRequested()
            }
        }
    }

    private func ask() async -> Outcome {
        // A second caller while a sheet is up: the first is answered "no"
        // rather than left waiting on a sheet nobody will close for it.
        waiting?.resume(returning: .cancelled)
        waiting = nil
        outcome = .cancelled
        return await withCheckedContinuation { continuation in
            waiting = continuation
            prompt = Prompt()
        }
    }

    /// The sheet's answer. It takes effect once the sheet has gone.
    func finish(_ outcome: Outcome) {
        self.outcome = outcome
        prompt = nil
    }

    fileprivate func dismissed() {
        let pending = waiting
        waiting = nil
        pending?.resume(returning: outcome)
        outcome = .cancelled
    }
}

private struct StepUpPresenter: ViewModifier {
    @ObservedObject var gate: StepUpGate
    let api: PatchworkAPI
    func body(content: Content) -> some View {
        content.sheet(item: $gate.prompt, onDismiss: { gate.dismissed() }) { _ in
            StepUpSheet(api: api) { gate.finish($0) }
        }
    }
}

extension View {
    /// Present the gate's Confirm sheet over this screen.
    func stepUpSheet(_ gate: StepUpGate, api: PatchworkAPI) -> some View {
        modifier(StepUpPresenter(gate: gate, api: api))
    }
}

// MARK: - The Confirm sheet

/// "Confirm it's you." It reads what this session could confirm with first,
/// and then shows exactly one of three things (`StepUp.decide`).
struct StepUpSheet: View {
    let api: PatchworkAPI
    let onFinish: (StepUpGate.Outcome) -> Void

    private enum Phase: Equatable {
        case loading
        case failed(String)
        case deciding(StepUp.Confirm)
        /// Confirmed, with a line worth stopping for: the codes are running out.
        case confirmedLow(String)
    }
    @State private var phase = Phase.loading
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    /// The server's reason for the last failure, which decides the door
    /// offered under the sentence.
    @State private var failureCode: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch phase {
                    case .loading:
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    case .failed(let message):
                        heading("Confirm it’s you")
                        Text(message).font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                        Button { Task { await load() } } label: { Text("Try again").font(Font.pw.subheadline).inkAction("arrow.clockwise") }
                            .buttonStyle(.plain)
                    case .deciding(.enterCode(let ready)): enterCode(ready: ready)
                    case .deciding(.signInAgain): signInAgain
                    case .deciding(.makeCodes): makeCodes
                    case .confirmedLow(let line):
                        heading("Confirmed")
                        Text(line).font(Font.pw.body).foregroundStyle(Color.pwText)
                            .accessibilityIdentifier("stepUpLow")
                        primary("Continue", identifier: "stepUpContinue", enabled: true) { onFinish(.confirmed) }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.pwGround.ignoresSafeArea())
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onFinish(.cancelled) } } }
        }
        .task { await load() }
        .interactiveDismissDisabled(busy)
    }

    // MARK: The three states

    private func enterCode(ready: Int) -> some View {
        Group {
            heading("Confirm it’s you")
            Text("This can’t be undone, so the quilt asks for a fresh proof that it’s you, not only the session you’re signed in with.")
                .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
            Text("Enter one of your recovery codes to confirm. Each code works once.")
                .font(Font.pw.body).foregroundStyle(Color.pwText)
                .accessibilityIdentifier("stepUpEnterCode")
            TextField(text: $code, prompt: Text(verbatim: "xxxx-xxxx-xxxx")) { Text("Recovery code") }
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .textContentType(.oneTimeCode)
                .submitLabel(.done)
                .onSubmit { confirm() }
                .focused($focused)
                .fieldStyle()
                .accessibilityIdentifier("stepUpCode")
                .onChange(of: code) { _, _ in error = nil; failureCode = nil }
            if let error {
                Label { Text(error).font(Font.pw.footnote) } icon: {
                    Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
                }
                .foregroundStyle(Color.pwText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("stepUpError")
                // The two failures that no other code will fix get the door
                // to what will, under the sentence that explains it.
                if failureCode == "recovery_codes_too_new" { signOutButton }
                if failureCode == "no_recovery_codes" { makeCodesLink }
            }
            primary("Confirm", identifier: "stepUpConfirm", enabled: RecoveryCode.isComplete(code)) { confirm() }
            Text(ready == 1 ? "One of your codes can confirm this." : "\(ready) of your codes can confirm this.")
                .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
        }
        .onAppear { focused = true }
    }

    private var signInAgain: some View {
        Group {
            heading("Sign in again to confirm")
            Text("Your recovery codes are newer than this sign-in, so they cannot confirm it yet. Sign out, then sign back in with one of them: you arrive confirmed.")
                .font(Font.pw.body).foregroundStyle(Color.pwText)
                .accessibilityIdentifier("stepUpSignInAgain")
            Text("The rest of the set works from then on. A code made by the session asking to use it would prove nothing, which is why the first one costs a sign-out.")
                .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
            primary("Sign out", identifier: "stepUpSignOut", enabled: true) { onFinish(.signOut) }
        }
    }

    private var makeCodes: some View {
        Group {
            heading("You need a recovery code")
            Text("This needs a recovery code, and you have none yet.")
                .font(Font.pw.body).foregroundStyle(Color.pwText)
                .accessibilityIdentifier("stepUpNoCodes")
            Text("Make a set, keep it somewhere other than this phone, then sign out and sign back in with one of them: you arrive confirmed.")
                .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
            NavigationLink {
                RecoveryCodesPage(api: api) { onFinish(.signOut) }
            } label: {
                Text("Make recovery codes").font(Font.pw.headline).foregroundStyle(Color.white).frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.pwAccent)
            .controlSize(.large)
            .accessibilityIdentifier("stepUpMakeCodes")
        }
    }

    private var signOutButton: some View {
        Button { onFinish(.signOut) } label: { Text("Sign out").font(Font.pw.subheadline).inkAction("rectangle.portrait.and.arrow.right") }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stepUpSignOut")
    }

    private var makeCodesLink: some View {
        NavigationLink { RecoveryCodesPage(api: api) { onFinish(.signOut) } } label: {
            Text("Make recovery codes").font(Font.pw.subheadline)
        }
        .inkRow(fills: false)
    }

    // MARK: Parts

    private func heading(_ text: String) -> some View {
        Text(text).font(Font.pw.displayTitle2).foregroundStyle(Color.pwText).fixedSize(horizontal: false, vertical: true)
    }

    private func primary(_ title: String, identifier: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if busy { ProgressView().tint(.white) } else { Text(title).font(Font.pw.headline) }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            // The app's root sets ink on everything; a filled control's label
            // is the design's white (DESIGN.md, primary-action).
            .foregroundStyle(Color.white)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.pwAccent)
        .controlSize(.large)
        .disabled(!enabled || busy)
        .accessibilityIdentifier(identifier)
        .padding(.top, 4)
    }

    // MARK: Calls

    private func load() async {
        phase = .loading
        do {
            let status = try await api.stepUpStatus()
            // Already open (a recovery sign-in opens it on arrival): there is
            // nothing to ask, and asking would spend a code for nothing.
            if status.active == true { onFinish(.confirmed); return }
            let codes = (status.recoveryReady ?? 0) > 0 ? nil : try? await api.recoveryCodeStatus()
            phase = .deciding(StepUp.decide(status: status, codes: codes))
        } catch {
            phase = .failed(SignInModel.sentence(error))
        }
    }

    private func confirm() {
        guard RecoveryCode.isComplete(code), !busy else { return }
        busy = true
        error = nil
        failureCode = nil
        Task {
            defer { busy = false }
            do {
                let grant = try await api.stepUp(recoveryCode: code)
                if let line = StepUp.runningLow(remaining: grant.codesRemaining ?? 0) {
                    phase = .confirmedLow(line)
                } else {
                    onFinish(.confirmed)
                }
            } catch {
                let refusal = error as? APIError
                failureCode = refusal?.code
                self.error = StepUp.failureSentence(code: refusal?.code, status: refusal?.httpStatus)
            }
        }
    }
}

// MARK: - Recovery codes, made and shown

/// The Confirm sheet's "no codes" door: the same section Security holds, and,
/// once a set exists, the one instruction that makes it count.
struct RecoveryCodesPage: View {
    let api: PatchworkAPI
    let onSignOut: () -> Void
    var body: some View {
        List {
            Group { RecoveryCodesSection(api: api, onSignOut: onSignOut) }.listRows()
        }
        .groundedList()
        .navigationTitle("Recovery codes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Recovery codes: how many are left, a way to make a new set, and the set
/// itself — shown once, the moment it is made, because the server never
/// hands it over again.
struct RecoveryCodesSection: View {
    let api: PatchworkAPI
    /// Where making codes is a step towards confirming something (the
    /// Confirm sheet), the sign-out that makes them count is offered right
    /// under them.
    var onSignOut: (() -> Void)? = nil
    @State private var status: RecoveryCodeStatus?
    @State private var fresh: [String] = []
    @State private var busy = false
    @State private var failure: String?
    @State private var replacing = false
    @State private var sharing = false
    @State private var copied = false

    var body: some View {
        Section {
            if !fresh.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("These replace any earlier set, and this is the only time they are shown.")
                        .font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwText)
                        .accessibilityIdentifier("recoveryCodesShownOnce")
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(fresh, id: \.self) { code in
                            Text(verbatim: code)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(Color.pwText)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("recoveryCode")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("recoveryCodesList")
                }
                .padding(.vertical, 4)
                // The acts wrap below the codes rather than squeezing beside them.
                HStack(spacing: 12) {
                    Button { copy() } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(Font.pw.subheadlineMedium).frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("recoveryCodesCopy")
                    Button { sharing = true } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(Font.pw.subheadlineMedium).frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("recoveryCodesShare")
                }
                .foregroundStyle(Color.pwText)
                if let onSignOut {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Now sign out, then sign back in with one of these codes: you arrive confirmed, and the rest of the set can confirm from then on.")
                            .font(Font.pw.subheadline).foregroundStyle(Color.pwText)
                        Button { onSignOut() } label: {
                            Text("Sign out").font(Font.pw.headline).foregroundStyle(Color.white).frame(maxWidth: .infinity, minHeight: 28)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.pwAccent)
                        .accessibilityIdentifier("recoveryCodesSignOut")
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack {
                Text(status?.summary ?? " ")
                    .font(Font.pw.body)
                    .foregroundStyle(status?.total == 0 ? Color.pwTextMuted : Color.pwText)
                    .accessibilityIdentifier("recoveryCodesStatus")
                Spacer(minLength: 0)
                if status == nil, failure == nil { ProgressView() }
            }
            .task { await load() }
            Button {
                if (status?.total ?? 0) > 0 && fresh.isEmpty { replacing = true } else { Task { await generate() } }
            } label: {
                HStack(spacing: 8) {
                    Text((status?.total ?? 0) > 0 || !fresh.isEmpty ? "Generate new codes" : "Generate recovery codes")
                        .font(Font.pw.body)
                        .foregroundStyle(Color.pwText)
                    Spacer(minLength: 0)
                    if busy { ProgressView() }
                }
            }
            .disabled(busy)
            .accessibilityIdentifier("recoveryCodesGenerate")
            .confirmationDialog("Replace your recovery codes?", isPresented: $replacing, titleVisibility: .visible) {
                Button("Replace my codes", role: .destructive) { Task { await generate() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A new set replaces the old one. Anything already written down stops working.")
            }
            if let failure {
                Text(failure).font(Font.pw.footnote).foregroundStyle(Color.pwText)
            }
        } header: {
            Text("Recovery codes").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
        } footer: {
            Text("A recovery code signs you in without email, and confirms things that can’t be undone. Each code works once.")
                .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted).textCase(nil)
        }
        .sheet(isPresented: $sharing) {
            ShareSheet(items: [fresh.joined(separator: "\n")]).presentationDetents([.medium, .large])
        }
    }

    private func load() async {
        do { status = try await api.recoveryCodeStatus(); failure = nil }
        catch { failure = SignInModel.sentence(error) }
    }

    private func generate() async {
        busy = true
        failure = nil
        copied = false
        defer { busy = false }
        do {
            fresh = try await api.generateRecoveryCodes()
            await load()
        } catch {
            failure = SignInModel.sentence(error)
        }
    }

    private func copy() {
        UIPasteboard.general.string = fresh.joined(separator: "\n")
        copied = true
    }
}

/// The system share sheet for anything that is not a file on disk — the
/// codes, as text.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
