// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// A first account's two beats (web SignupComplete.svelte and Welcome.svelte):
// the line under the username step that says what creating an account
// agrees to, and the one screen afterwards that restates the heart of that
// agreement, says who runs this quilt, and hands the reader to Discover.

// MARK: - The agreement line

/// "By creating an account you agree to the User Agreement and Privacy
/// Policy." Each name opens the quilt's own document, natively, over the
/// sign-in sheet — the reader is in the middle of something and comes back
/// to it.
struct AgreementLine: View {
    @State private var reading: LegalView.Doc?
    var body: some View {
        Text(Self.sentence)
            .font(Font.pw.footnote)
            .foregroundStyle(Color.pwTextMuted)
            .tint(Color.pwText)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                guard let doc = Self.doc(for: url) else { return .discarded }
                reading = doc
                return .handled
            })
            .accessibilityIdentifier("agreementLine")
            .sheet(item: $reading) { doc in
                NavigationStack {
                    LegalView(doc: doc)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { reading = nil } } }
                }
            }
    }

    /// The two names as in-prose links: underlined ink, never a coloured
    /// phrase (DESIGN.md "Colors").
    static var sentence: AttributedString {
        var text = AttributedString("By creating an account you agree to the ")
        var terms = AttributedString("User Agreement")
        terms.link = URL(string: "patchwork-legal:terms")
        terms.underlineStyle = .single
        var privacy = AttributedString("Privacy Policy")
        privacy.link = URL(string: "patchwork-legal:privacy")
        privacy.underlineStyle = .single
        text += terms
        text += AttributedString(" and ")
        text += privacy
        text += AttributedString(".")
        return text
    }

    static func doc(for url: URL) -> LegalView.Doc? {
        guard url.scheme == "patchwork-legal" else { return nil }
        return LegalView.Doc(rawValue: url.absoluteString.replacingOccurrences(of: "patchwork-legal:", with: ""))
    }
}

extension LegalView.Doc: Identifiable { var id: String { rawValue } }

// MARK: - When the Welcome is shown

/// The web's rule (App.svelte): a signed-in reader who holds no membership
/// is shown the Welcome until they dismiss it — which, for anybody arriving
/// from the username step, is right after the account was made. Here it is
/// asked once, when a sign-in from the sheet lands, and the dismissal is
/// remembered per quilt and per account, as the web keys it per user.
enum WelcomeRule {
    static func shouldWelcome(memberships: [Membership], dismissed: Bool) -> Bool {
        memberships.isEmpty && !dismissed
    }

    static func key(quilt: Quilt, userID: String) -> String { "welcome-dismissed:\(quilt.id):\(userID)" }

    /// Offline fixtures keep the dismissal in memory, so one UI test's
    /// answer is never the next launch's.
    private static var previewDismissed = Set<String>()
    private static var previewing: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--preview")
        #else
        false
        #endif
    }
    static func dismissed(quilt: Quilt, userID: String, defaults: UserDefaults = .standard) -> Bool {
        let key = key(quilt: quilt, userID: userID)
        return previewing ? previewDismissed.contains(key) : defaults.bool(forKey: key)
    }
    static func dismiss(quilt: Quilt, userID: String, defaults: UserDefaults = .standard) {
        let key = key(quilt: quilt, userID: userID)
        if previewing { previewDismissed.insert(key) } else { defaults.set(true, forKey: key) }
    }

    /// The Label's line, as the web's panel writes it: up to three stewards
    /// by name, "+N" past that, and the monthly cost where there is one.
    static func stewardLine(_ label: QuiltLabel) -> String? {
        let stewards = label.stewards ?? []
        guard !stewards.isEmpty else { return nil }
        let names = stewards.prefix(3).map { ($0.displayName?.isEmpty == false ? $0.displayName! : "@" + $0.username) }
        let who: String
        if stewards.count > 3 { who = names.joined(separator: ", ") + " +\(stewards.count - 3)" }
        else if names.count > 2 { who = names.joined(separator: ", ") }
        else { who = names.joined(separator: " and ") }
        var line = "This quilt is stewarded by \(who)"
        if let total = label.totalMonthlyMinor, total > 0 {
            line += " and costs about \(QuiltLabel.money(total, label.currency))/month to run"
        }
        return line + "."
    }

    /// The first line of the Label's prose that is not a heading, cut at 140.
    static func proseLine(_ prose: String?) -> String? {
        let line = (prose ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") } ?? ""
        guard !line.isEmpty else { return nil }
        return line.count > 140 ? String(line.prefix(140)).trimmingCharacters(in: .whitespaces) + "…" : line
    }

    /// The four points, in the web's words.
    static let expectations = [
        "Treat every person with dignity and respect",
        "Participate in good faith",
        "Support the communities you join",
        "Report harmful behavior instead of ignoring it",
    ]
}

// MARK: - The Welcome

/// One screen, over the whole app, the way the web's sits in its threshold
/// shell: the reader has just been let in, and this is the door.
struct WelcomeView: View {
    let quiltName: String
    let buildYourQuilt: () -> Void
    let exploreOnMyOwn: () -> Void
    @EnvironmentObject private var session: QuiltSession
    @State private var label: QuiltLabel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Welcome to \(quiltName)")
                        .font(Font.pw.display).foregroundStyle(Color.pwText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("welcomeHeading")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Each patch here is a group. Follow the ones you care about and your corner of the quilt takes shape.")
                            .font(Font.pw.body).foregroundStyle(Color.pwText)
                            .fixedSize(horizontal: false, vertical: true)
                        NavigationLink { AboutQuiltView() } label: {
                            Text("What is Patchwork?").font(Font.pw.subheadline).inkRow(fills: false)
                        }
                    }
                    if let label, label.published == true { labelPanel(label) }
                    expected
                    VStack(spacing: 12) {
                        Button(action: buildYourQuilt) {
                            Text("Build your quilt").font(Font.pw.headline)
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .foregroundStyle(Color.white)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.pwAccent)
                        .controlSize(.large)
                        .accessibilityIdentifier("welcomeBuild")
                        Button(action: exploreOnMyOwn) {
                            Text("I'll explore on my own").font(Font.pw.subheadline).foregroundStyle(Color.pwText)
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("welcomeSkip")
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.pwGround.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { label = try? await session.api.get("label") }
    }

    /// The Label's onboarding panel (web ADR 023): who answers for this
    /// quilt and roughly what it costs, beside the agreement. Absent where
    /// no Label is published.
    private func labelPanel(_ label: QuiltLabel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let line = WelcomeRule.stewardLine(label) {
                Text(line).font(Font.pw.subheadline).foregroundStyle(Color.pwText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("welcomeLabel")
            }
            if let quote = WelcomeRule.proseLine(label.prose) {
                Text("\u{201C}\(quote)\u{201D}").font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            NavigationLink { LabelView() } label: {
                Text("Read the Label").font(Font.pw.subheadlineMedium).inkRow(fills: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var expected: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's expected here").font(Font.pw.title3).foregroundStyle(Color.pwText)
                .accessibilityAddTraits(.isHeader)
            // One sentence that wraps as a sentence, the agreement's name in
            // it a link to the agreement itself.
            Text(agreementSentence)
                .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted).tint(Color.pwText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(WelcomeRule.expectations, id: \.self) { point in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Color.pwTextMuted).accessibilityHidden(true)
                        Text(point).foregroundStyle(Color.pwText).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(Font.pw.body)
                }
            }
            .accessibilityIdentifier("welcomeExpectations")
            NavigationLink { LiningView() } label: {
                Text("Every patch starts from the lining, the shared baseline behind these.")
                    .font(Font.pw.subheadline).multilineTextAlignment(.leading).inkRow(fills: false)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard AgreementLine.doc(for: url) != nil else { return .discarded }
            readingTerms = true
            return .handled
        })
        .navigationDestination(isPresented: $readingTerms) { LegalView(doc: .terms) }
    }
    @State private var readingTerms = false

    private var agreementSentence: AttributedString {
        var text = AttributedString("The heart of the ")
        var link = AttributedString("agreement")
        link.link = URL(string: "patchwork-legal:terms")
        link.underlineStyle = .single
        text += link
        text += AttributedString(" you accepted when you created your account:")
        return text
    }
}
