// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// The controls the `Relationship` value decides on: the profile head's
/// standing, the heart on a card, the small sheet a join opens, and the one
/// door a signed-out reader is offered in place of all of them.
///
/// Nothing here fakes a state. Every act waits for the server, asks the
/// membership index again, and draws whatever came back — a card shows a
/// spinner while the call is out rather than a filled heart it hopes to earn.

// MARK: - The way in

/// The native sign-in sheet, wherever a signed-out reader meets something
/// only an account can do. It replaces the three website doors this app used
/// to open: following now happens here.
struct SignInGate: ViewModifier {
    @EnvironmentObject private var session: QuiltSession
    @Binding var presented: Bool
    func body(content: Content) -> some View {
        content.sheet(isPresented: $presented) {
            SignInSheet(api: session.api, quiltName: session.instance?.name ?? session.quilt.name) { user in
                session.signedIn(user)
            }
        }
    }
}

extension View {
    func signInGate(_ presented: Binding<Bool>) -> some View { modifier(SignInGate(presented: presented)) }
}

/// The one sentence a signed-out reader is shown where a control would be.
/// It is an act, not a link out of the app any more, so it wears `inkAction`.
struct SignInAction: View {
    let text: String
    @State private var signIn = false
    var body: some View {
        Button { signIn = true } label: {
            Text(text).font(Font.pw.footnote).multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .inkAction("person.badge.key")
        .accessibilityIdentifier("signInToFollow")
        .signInGate($signIn)
    }
}

// MARK: - The profile head

/// Follow, Join, or the standing already held — in the head, under the counts.
/// The tint fills these because they are controls (DESIGN.md "Colors"); a
/// standing is not a control but a fact, so it wears ink in a capsule and the
/// menu behind it holds the one exit.
/// What an act came back with, for a head that shows the control in one
/// place and the sentence in another.
struct RelationshipFeedback: Equatable {
    let text: String
    let refused: Bool
}

struct RelationshipControl: View {
    /// Where the control sits. Inline it is a row on the surface, in the
    /// app's ink and accent. On the cover it rides the patch's own design
    /// in Liquid Glass, the way the web's acts ride the cover's corner, and
    /// hands its sentence out through `feedback` so nothing has to be read
    /// off the cloth.
    enum Placement { case inline, cover }

    @EnvironmentObject private var session: QuiltSession
    let patch: Patch
    /// Whether the quilt said this reader is banned from this patch, which
    /// rides the `nodes/{slug}` envelope rather than the node.
    var banned = false
    var placement: Placement = .inline
    var feedback: Binding<RelationshipFeedback?>? = nil
    /// Read the node back after an act: `follower_count` and `member_count`
    /// are the server's numbers and the head prints them.
    var reload: () async -> Void = {}

    @State private var busy = false
    @State private var note: String?
    @State private var refused = false
    @State private var joining = false
    private var onCover: Bool { placement == .cover }

    private var standing: Standing? { session.standing(for: patch.slug) ?? Standing.from(node: patch) }
    private var relationship: Relationship {
        banned ? .none : Relationship.resolve(node: patch, standing: standing)
    }

    var body: some View {
        // Signed out there is no control at all: the sentence at the foot of
        // the profile is the whole offer.
        if session.me != nil {
            VStack(alignment: .leading, spacing: 6) {
                control
                if let note, !onCover {
                    Label {
                        Text(note).font(Font.pw.footnote).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: refused ? "exclamationmark.circle" : "checkmark.circle").font(Font.pw.footnote)
                    }
                    .foregroundStyle(refused ? Color.pwText : Color.pwTextMuted)
                    .accessibilityIdentifier("relationshipNote")
                }
            }
            .padding(.top, 2)
            .sheet(isPresented: $joining) {
                // The sheet waits for the server rather than closing on the
                // tap: whichever of the two answers comes back is the one the
                // head is wearing by the time the sheet is gone.
                JoinSheet(patch: patch, join: joinOffer ?? .now) { message in
                    await perform { try await session.join(patch.slug, message: message) }
                }
            }
        }
    }

    private var joinOffer: Relationship.Join? {
        if case .offering(let offer) = relationship { return offer.join }
        return nil
    }

    @ViewBuilder private var control: some View {
        switch relationship {
        case .none:
            EmptyView()
        case .holding(let role):
            mark(role.mark, symbol: role.symbol) {
                Button(role: .destructive) {
                    act { role == .follower ? try await session.unfollow(patch.slug) : try await session.leave(patch.slug) }
                } label: {
                    Label(role.exit, systemImage: role == .follower ? "heart.slash" : "rectangle.portrait.and.arrow.right")
                }
                .accessibilityIdentifier(role == .follower ? "unfollow" : "leave")
            }
        case .requested:
            mark("Membership requested", symbol: "clock") {
                Button(role: .destructive) {
                    act { try await session.withdraw(patch.slug) }
                } label: {
                    Label("Withdraw request", systemImage: "arrow.uturn.backward")
                }
                .accessibilityIdentifier("withdrawRequest")
            }
        case .offering(let offer):
            HStack(spacing: 10) {
                // Follow leads where it is the only offer and steps back where
                // Join is beside it: one filled control at a time, which is
                // what makes the filled one mean anything.
                if offer.follow {
                    Button { act { try await session.follow(patch.slug) } } label: { buttonFace("Follow", symbol: "heart") }
                        .modifier(ActButton(prominent: offer.join == nil, onCover: onCover))
                        .disabled(busy)
                        .accessibilityIdentifier("relationshipFollow")
                }
                if let join = offer.join {
                    Button { joining = true } label: { buttonFace(join.title, symbol: "person.badge.plus") }
                        .modifier(ActButton(prominent: true, onCover: onCover))
                        .disabled(busy)
                        .accessibilityIdentifier("relationshipJoin")
                }
            }
        }
    }

    /// A standing is a fact worn in ink, with the exit behind it. The menu is
    /// the control; the capsule is what it is a control over.
    private func mark<Content: View>(_ title: String, symbol: String, @ViewBuilder exit: () -> Content) -> some View {
        Menu {
            exit()
        } label: {
            HStack(spacing: 6) {
                if busy { ProgressView().controlSize(.mini) } else { Image(systemName: symbol).font(Font.pw.footnoteSemibold) }
                Text(title).font(Font.pw.subheadlineSemibold)
                Image(systemName: "chevron.down").font(Font.pw.caption2Semibold).opacity(0.7)
            }
            .foregroundStyle(onCover ? Color.white : Color.pwText)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .modifier(MarkChrome(onCover: onCover))
        }
        .disabled(busy)
        .accessibilityIdentifier("relationshipControl")
        .accessibilityLabel(title)
    }

    @ViewBuilder private func buttonFace(_ title: String, symbol: String) -> some View {
        if busy {
            ProgressView().frame(minWidth: 72)
        } else {
            Label(title, systemImage: symbol).font(Font.pw.subheadlineSemibold)
        }
    }

    /// One place an act is run from: the sentence the server answered with is
    /// what the reader is shown, and the node is read back so the counts line
    /// is the quilt's again rather than this client's arithmetic.
    private func act(_ run: @escaping () async throws -> String) {
        Task { await perform(run) }
    }

    private func perform(_ run: () async throws -> String) async {
        guard !busy else { return }
        busy = true
        note = nil
        do {
            let status = try await run()
            refused = false
            note = Self.sentence(for: status)
        } catch {
            refused = true
            note = SignInModel.sentence(error)
        }
        busy = false
        feedback?.wrappedValue = note.map { RelationshipFeedback(text: $0, refused: refused) }
        await reload()
    }

    /// What the act turned out to be. `ok` is a leave, an unfollow or a
    /// withdrawal — the act itself was the feedback and the mark is already
    /// gone, so there is nothing left to say.
    static func sentence(for status: String) -> String? {
        switch status {
        case "ok": return nil
        case "pending", "active": return Relationship.joinOutcome(status: status)
        default: return nil
        }
    }
}

// MARK: - The join sheet

/// A small sheet with one optional message. The web asks for one because a
/// patch that approves members reads it; a patch that admits everybody gets
/// it anyway, which is the web's behaviour and costs nothing.
struct JoinSheet: View {
    let patch: Patch
    let join: Relationship.Join
    let submit: (String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var busy = false
    private let limit = 500

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(join == .request ? "Ask to join \(patch.name)" : "Join \(patch.name)")
                        .font(Font.pw.displayTitle2)
                        .foregroundStyle(Color.pwText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(join == .request
                         ? "This patch approves new members. Say a little about why you'd like to join, if you like — its admins will read it."
                         : "This patch admits anyone who asks. You can say hello if you like.")
                        .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Message (optional)", text: $message, axis: .vertical)
                            .lineLimit(3...6)
                            .fieldStyle()
                            .accessibilityIdentifier("joinMessage")
                            .onChange(of: message) { _, now in
                                if now.count > limit { message = String(now.prefix(limit)) }
                            }
                        Text("\(message.count)/\(limit)")
                            .font(Font.pw.caption)
                            .foregroundStyle(Color.pwTextMuted)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.pwGround.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            // The act rides the foot of the sheet rather than the end of its
            // scroll: this is a sheet with a keyboard in it, and a primary
            // button inside the scroll is a primary button behind the
            // keyboard — which is exactly where it went on one OS version.
            .safeAreaInset(edge: .bottom) {
                Button {
                    busy = true
                    Task {
                        await submit(message)
                        busy = false
                        dismiss()
                    }
                } label: {
                    Group {
                        if busy { ProgressView() } else { Text(join.title).font(Font.pw.headline) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.pwAccent)
                .controlSize(.large)
                .disabled(busy)
                .accessibilityIdentifier("joinSubmit")
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - The heart on a card

/// The web's `.card-corner`, which was a link to the website and is now a
/// control with a state the server gave it.
///
/// Five states and no sixth: signed out it opens the sheet; a stranger is
/// offered the outline heart; a follower gets the filled one and a confirm
/// behind it; a member or an admin gets their role's mark and no act, because
/// leaving a patch is not a thing to do by accident from a list; and a pending
/// request is not a card's business at all. While a call is out the chip holds
/// a spinner — the heart must not fill before the quilt has answered.
struct FollowChip: View {
    @EnvironmentObject private var session: QuiltSession
    let patch: Patch

    @State private var busy = false
    @State private var signIn = false
    @State private var confirming = false
    /// The moment after a follow lands: the heart fills and beats once, so the
    /// tap has an answer of its own rather than only a changed outline.
    @State private var landed = false

    private var standing: Standing? { session.standing(for: patch.slug) ?? Standing.from(node: patch) }
    private var relationship: Relationship { Relationship.resolve(node: patch, standing: standing) }

    var body: some View {
        content
            .signInGate($signIn)
            .confirmationDialog("Unfollow \(patch.name)?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Unfollow", role: .destructive) { act { try await session.unfollow(patch.slug) } }
                Button("Cancel", role: .cancel) {}
            }
    }

    @ViewBuilder private var content: some View {
        switch relationship {
        case .none, .requested:
            EmptyView()
        case .holding(let role):
            switch role {
            case .follower:
                button(symbol: "heart.fill", label: "Following \(patch.name)", hint: "Unfollows this patch.") { confirming = true }
            case .member, .admin:
                // A fact, not an act: the card says what you are to this patch
                // and the profile is where leaving it lives.
                chip { Image(systemName: role.symbol).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwText) }
                    .accessibilityLabel("\(role.mark) of \(patch.name)")
                    .accessibilityIdentifier("followChip-\(patch.slug)")
            }
        case .offering(let offer):
            if offer.follow {
                if session.me == nil {
                    button(symbol: "heart", label: "Follow \(patch.name)", hint: "Opens sign in.") { signIn = true }
                } else {
                    button(symbol: landed ? "heart.fill" : "heart", label: "Follow \(patch.name)", hint: "Follows this patch.") {
                        act { try await session.follow(patch.slug) }
                    }
                }
            }
        }
    }

    private func button(symbol: String, label: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            chip {
                if busy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: symbol)
                        .font(Font.pw.footnoteSemibold)
                        .foregroundStyle(Color.pwAccent)
                        .scaleEffect(landed ? 1.25 : 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(busy ? "Working…" : label)
        .accessibilityHint(hint)
        .accessibilityIdentifier("followChip-\(patch.slug)")
    }

    /// The web's glass corner, at the 44pt target the platform asks for.
    private func chip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 30, height: 30)
            .background(.regularMaterial, in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private func act(_ run: @escaping () async throws -> String) {
        guard !busy else { return }
        busy = true
        Task {
            let followed = (try? await run()) != nil
            busy = false
            guard followed else { return }
            withAnimation(.spring(response: 0.3)) { landed = true }
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation { landed = false }
        }
    }
}


/// A Follow or Join button's clothes. Inline, the app's accent (filled for
/// the one that leads, bordered for the one beside it). On the cover, Liquid
/// Glass over the patch's own cloth — the glass is what lets a control sit
/// on a busy design without a band behind it — with the accent only on the
/// one that leads; where the system has no glass, a material stands in.
private struct ActButton: ViewModifier {
    let prominent: Bool
    let onCover: Bool
    func body(content: Content) -> some View {
        if onCover {
            if #available(iOS 26, *) {
                if prominent { content.buttonStyle(.glassProminent).tint(Color.pwAccent) }
                else { content.buttonStyle(.glass).foregroundStyle(.white) }
            } else {
                if prominent { content.buttonStyle(.borderedProminent).tint(Color.pwAccent) }
                else { content.buttonStyle(.bordered).tint(.white).foregroundStyle(.white) }
            }
        } else {
            if prominent { content.buttonStyle(.borderedProminent).tint(Color.pwAccent) }
            else { content.buttonStyle(.bordered).tint(Color.pwAccent) }
        }
    }
}

/// The standing mark's capsule: a hairline of thread inline, glass on the cover.
private struct MarkChrome: ViewModifier {
    let onCover: Bool
    func body(content: Content) -> some View {
        if onCover {
            if #available(iOS 26, *) {
                content.glassEffect(.regular, in: Capsule())
            } else {
                content.background(.regularMaterial, in: Capsule())
            }
        } else {
            content.overlay(Capsule().strokeBorder(Color.pwBorder, lineWidth: 1))
        }
    }
}
