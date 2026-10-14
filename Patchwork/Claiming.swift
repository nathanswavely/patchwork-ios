// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// Claiming a patch nobody runs yet (web `/patches/:slug/claim`,
// ClaimPatch.svelte; the server's claims.go; web ADRs 030, 039, 062). The
// methods are the ones the server offers for this listing, every one of
// them anchored on the domain an admin vetted. Proving it happens where the
// domain lives — a DNS record, a tag on a homepage, a handle, or a link in
// an email — and approval is not activation: it opens a fourteen-day window
// to set the patch up, which is the creation form filled from the listing.
//
// The emailed link opens in the browser and needs no session there; the app
// says so, and reads the claim again whenever it comes back to the front.

/// The five ways to prove a claim, with the web's words.
enum ClaimMethod: String, CaseIterable, Identifiable {
    case dns, metaTag = "meta_tag", did, email, admin
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dns: return "DNS Verification"
        case .metaTag: return "Website Meta Tag"
        case .did: return "atproto Handle"
        case .email: return "Email Verification"
        case .admin: return "Admin Review"
        }
    }
    var detail: String {
        switch self {
        case .dns: return "Add a TXT record to your domain"
        case .metaTag: return "Add a meta tag to your homepage"
        case .did: return "Prove the did:web identity behind your domain"
        case .email: return "Get a link at your organization email"
        case .admin: return "Submit evidence for manual review"
        }
    }
    /// The three whose proof the server can go and look at when asked.
    var verifiable: Bool { self == .dns || self == .metaTag || self == .did }

    /// Why a method is not offered, naming the missing prerequisite rather
    /// than a catch-all: email can be missing for want of a domain or for
    /// want of mail, and a combined sentence misleads whichever is fine.
    static func unavailableReason(_ method: ClaimMethod, domain: String) -> String {
        if domain.isEmpty { return "Requires a verified domain on this listing" }
        if method == .email { return "This quilt can't send email" }
        return "Unavailable on this listing"
    }
}

/// A claim as `claims/mine` and `POST …/claim` describe it.
struct PatchClaimDetail: Decodable, Equatable {
    let id: String
    let method: String?
    let evidence: String?
    /// `pending` or `approved`.
    let status: String?
    let email: String?
    let createdAt: String?
    let setupExpiresAt: String?
    let instructions: String?
    let recordValue: String?
    let metaContent: String?
    var kind: ClaimMethod? { method.flatMap(ClaimMethod.init(rawValue:)) }
    var approved: Bool { status == "approved" }
}

/// `GET nodes/{slug}/claims/mine`: the reader's open claim, if any, and what
/// the patch takes.
struct ClaimState: Decodable, Equatable {
    let claim: PatchClaimDetail?
    /// Keyed by method. The snake-case decoder rewrites keys too
    /// (`meta_tag` → `metaTag`), so both spellings are read.
    let methods: [String: Bool]?
    let verificationDomain: String?
    let nodeStatus: String?
    var domain: String { verificationDomain ?? "" }
    func offers(_ method: ClaimMethod) -> Bool {
        if method == .admin && methods == nil { return true }
        return methods?[method.rawValue] ?? methods?[method == .metaTag ? "metaTag" : method.rawValue] ?? false
    }
}

struct ClaimRequestBody: Encodable, Equatable {
    let method: String
    let evidence: String?
    let email: String?
    /// Only the field the method asks for travels, trimmed.
    init(method: ClaimMethod, evidence: String, email: String) {
        self.method = method.rawValue
        self.evidence = method == .admin ? evidence.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        self.email = method == .email ? email.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }
}

/// `POST claims/{id}/verify` answers 200 either way: approved, or still
/// pending with the server's sentence about what it could not find.
struct ClaimVerification: Decodable, Equatable {
    let status: String?
    let verified: Bool?
    let slug: String?
    let setupRequired: Bool?
    let error: String?
}

struct ClaimAck: Decodable { let status: String? }

enum ClaimRules {
    /// The submit waits for a method, and for an email to be one.
    static func canSubmit(_ method: ClaimMethod?, email: String) -> Bool {
        guard let method else { return false }
        return method != .email || email.contains("@")
    }
    static let browserNote = "The link opens in your browser, not here. Open it there, then come back: this page checks your claim again when you return."
    static let verifiedNote = "Claim verified. Finish setup to activate this patch."
}

extension PatchworkAPI {
    func claimState(slug: String) async throws -> ClaimState { try await get("nodes/\(slug)/claims/mine") }
    func requestClaim(slug: String, _ body: ClaimRequestBody) async throws -> PatchClaimDetail { try await post("nodes/\(slug)/claim", body: body) }
    func verifyClaim(_ id: String) async throws -> ClaimVerification { try await post("claims/\(id)/verify", body: NoBody()) }
    func resendClaimEmail(_ id: String) async throws { let _: ClaimAck = try await post("claims/\(id)/resend-email", body: NoBody()) }
    func withdrawClaim(_ id: String) async throws { let _: ClaimAck = try await post("claims/\(id)/withdraw", body: NoBody()) }
}

// MARK: - The claim page

struct ClaimPatchView: View {
    let slug: String
    let name: String
    /// Setup finished: the patch is the reader's. The presenter decides where
    /// they land — on the patch, docked fresh.
    let onSetUp: (String) -> Void

    @EnvironmentObject private var session: QuiltSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var state: ClaimState?
    @State private var listing: Patch?
    @State private var loadFailure: String?
    @State private var method: ClaimMethod?
    @State private var evidence = ""
    @State private var email = ""
    @State private var busy = false
    @State private var failure: String?
    @State private var note: String?
    @State private var settingUp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Claim \(name)")
                        .font(Font.pw.displayTitle2).foregroundStyle(Color.pwText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Prove you represent this organization to take ownership.")
                        .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                }
                if let note {
                    Label(note, systemImage: "checkmark.circle")
                        .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                        .accessibilityIdentifier("claimNote")
                }
                if let state {
                    if let claim = state.claim {
                        if claim.approved { approvedCard(claim) } else { openCard(claim, domain: state.domain) }
                    } else {
                        methodPicker(state)
                    }
                } else if let loadFailure {
                    Text(loadFailure).font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                    Button { Task { await load() } } label: { Text("Try again").font(Font.pw.subheadline) }
                        .buttonStyle(.plain).inkAction("arrow.clockwise")
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.pwGround.ignoresSafeArea())
        .navigationTitle("Claim")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task { await load() }
        // The emailed link is opened in the browser. Coming back is when the
        // answer may have changed, so that is when it is asked again.
        .onChange(of: scenePhase) { _, now in if now == .active { Task { await load() } } }
        .sheet(isPresented: $settingUp) {
            if let claim = state?.claim, let listing {
                NavigationStack {
                    PatchFormView(mode: .setup(claimID: claim.id, slug: slug, expiresAt: claim.setupExpiresAt),
                                  draft: PatchDraft(setup: listing), onFinished: onSetUp)
                }
                .onDisappear { Task { await load() } }
            }
        }
    }

    // MARK: Choosing a method

    @ViewBuilder private func methodPicker(_ state: ClaimState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ClaimMethod.allCases) { option in
                let available = state.offers(option)
                ChoiceCard(title: option.label,
                           detail: available ? option.detail : ClaimMethod.unavailableReason(option, domain: state.domain),
                           selected: method == option, identifier: "claimMethod-\(option.rawValue)") {
                    method = option
                    failure = nil
                }
                .disabled(!available)
                .opacity(available ? 1 : 0.55)
            }
        }
        if method == .admin {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tell us why you should own this patch").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
                TextField("I'm the owner of this venue / I run this organization / etc.", text: $evidence, axis: .vertical)
                    .lineLimit(4...8)
                    .fieldStyle()
                    .accessibilityIdentifier("claimEvidence")
            }
        }
        if method == .email {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your email at @\(state.domain)").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
                TextField(text: $email, prompt: Text(verbatim: "you@" + state.domain)) { Text("Email") }
                    .keyboardType(.emailAddress).textContentType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .fieldStyle()
                    .accessibilityIdentifier("claimEmail")
                Text("The address must be at the organization's verified domain.")
                    .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
            }
        }
        refusal
        primary("Submit Claim", identifier: "claimSubmit", enabled: ClaimRules.canSubmit(method, email: email)) {
            Task { await submit() }
        }
    }

    // MARK: An open claim

    @ViewBuilder private func openCard(_ claim: PatchClaimDetail, domain: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your claim is open").font(Font.pw.title3).foregroundStyle(Color.pwText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("claimOpenHeading")
                Spacer(minLength: 8)
                Text(claim.kind?.label ?? claim.method ?? "")
                    .font(Font.pw.caption2Semibold).foregroundStyle(Color.pwTextMuted)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(Color.pwBorder, lineWidth: 1))
            }
            switch claim.kind {
            case .dns:
                Text("Add a TXT record on \(domain):").font(Font.pw.body)
                CodeBlock(text: claim.recordValue ?? "")
                Text("DNS changes can take a few minutes to propagate.").font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
            case .metaTag:
                Text("Add this tag to the <head> of https://\(domain):").font(Font.pw.body)
                CodeBlock(text: "<meta name=\"patchwork-verify\" content=\"\(claim.metaContent ?? "")\">")
            case .did:
                Text("Point the atproto handle \(domain) at a did:web identity. Add a TXT record on _atproto.\(domain):").font(Font.pw.body)
                CodeBlock(text: "did=did:web:\(domain)")
                Text("Then make sure that DID document lists the handle back:").font(Font.pw.body)
                CodeBlock(text: "\"alsoKnownAs\": [\"at://\(domain)\"]")
                Text("A did:plc handle won't work here. Only did:web is accepted, because its document lives on your own domain rather than in a registry someone else runs.")
                    .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
            case .email:
                Text("We sent a verification link to \(claim.email ?? "your address"). Open it to finish claiming. The link expires 24 hours after it's sent.")
                    .font(Font.pw.body)
                    .accessibilityIdentifier("claimEmailSent")
                // Said plainly: the link is the browser's, and this page is
                // where the answer arrives afterwards.
                Label(ClaimRules.browserNote, systemImage: "safari")
                    .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                    .accessibilityIdentifier("claimBrowserNote")
            case .admin, nil:
                Text(claim.kind == .admin
                     ? "Your claim is with the quilt admins for review. You'll be notified when it's resolved."
                     : (claim.instructions ?? ""))
                    .font(Font.pw.body)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Color.pwText)
        .cardSurface()
        refusal
        if claim.kind?.verifiable == true {
            primary(busy ? "Checking..." : "Verify Now", identifier: "claimVerify", enabled: true) { Task { await verify(claim) } }
        } else if claim.kind == .email {
            primary(busy ? "Sending..." : "Resend Email", identifier: "claimResend", enabled: true) { Task { await resend(claim) } }
        }
        Button { Task { await withdraw(claim) } } label: { Text("Withdraw Claim").font(Font.pw.subheadline) }
            .buttonStyle(.plain)
            .inkAction("arrow.uturn.backward")
            .disabled(busy)
            .accessibilityIdentifier("claimWithdraw")
        Text("Withdrawing lets you start over with a different method.")
            .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
    }

    // MARK: Approved

    @ViewBuilder private func approvedCard(_ claim: PatchClaimDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claim approved").font(Font.pw.title3).foregroundStyle(Color.pwText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("claimApprovedHeading")
            Text("You're cleared to set up this patch. Setup is where it becomes active. Until then, it still reads as unclaimed to everyone else.")
                .font(Font.pw.body).foregroundStyle(Color.pwText)
                .fixedSize(horizontal: false, vertical: true)
            if let day = MyPatchesRules.day(claim.setupExpiresAt) {
                Text("Approval expires \(day).").font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
            }
        }
        .cardSurface()
        primary("Set up your patch", identifier: "claimSetUp", enabled: listing != nil) { settingUp = true }
    }

    // MARK: Parts

    @ViewBuilder private var refusal: some View {
        if let failure {
            Label { Text(failure).font(Font.pw.footnote) } icon: {
                Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
            }
            .foregroundStyle(Color.pwText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("claimError")
        }
    }

    private func primary(_ title: String, identifier: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if busy { ProgressView().tint(.white) } else { Text(title).font(Font.pw.headline) }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .foregroundStyle(enabled && !busy ? Color.white : Color.pwTextMuted)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.pwAccent)
        .controlSize(.large)
        .disabled(!enabled || busy)
        .accessibilityIdentifier(identifier)
    }

    // MARK: Acts

    private func load() async {
        do {
            async let claim = session.api.claimState(slug: slug)
            async let node: PatchResponse = session.api.get("nodes/\(slug)")
            state = try await claim
            listing = (try? await node)?.node
            loadFailure = nil
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            if state == nil { loadFailure = sentenceCased(SignInModel.sentence(error)) }
        }
    }

    private func run(_ act: () async throws -> String?) async {
        guard !busy else { return }
        busy = true
        failure = nil
        note = nil
        do {
            note = try await act()
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            failure = sentenceCased(ProposalDetailView.sentence(error, fallback: "Something went wrong."))
        }
        await load()
        busy = false
    }

    private func submit() async {
        guard let method else { return }
        await run {
            _ = try await session.api.requestClaim(slug: slug, ClaimRequestBody(method: method, evidence: evidence, email: email))
            return method == .admin ? "Claim submitted for review" : nil
        }
    }

    private func verify(_ claim: PatchClaimDetail) async {
        await run {
            let answer = try await session.api.verifyClaim(claim.id)
            if answer.verified == true { return ClaimRules.verifiedNote }
            // Still pending: the server's own sentence about what it could
            // not find, in the place a refusal goes.
            throw APIError.message(answer.error ?? "Verification failed. Please try again.", status: 200)
        }
    }

    private func resend(_ claim: PatchClaimDetail) async {
        await run {
            try await session.api.resendClaimEmail(claim.id)
            return "Verification email sent"
        }
    }

    private func withdraw(_ claim: PatchClaimDetail) async {
        await run {
            try await session.api.withdrawClaim(claim.id)
            method = nil
            evidence = ""
            email = ""
            return "Claim withdrawn"
        }
    }
}

/// A value somebody has to paste somewhere else: monospaced, selectable, and
/// a Copy beside it, because the registrar is in another app.
struct CodeBlock: View {
    let text: String
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: text)
                .font(.footnote.monospaced())
                .foregroundStyle(Color.pwText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.pwGround, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.pwBorder, lineWidth: 1))
            Button {
                UIPasteboard.general.string = text
                copied = true
            } label: { Text(copied ? "Copied" : "Copy").font(Font.pw.subheadline) }
                .buttonStyle(.plain)
                .inkAction(copied ? "checkmark" : "doc.on.doc")
        }
    }
}
