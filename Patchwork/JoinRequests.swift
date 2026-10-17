// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// The three membership rooms a patch's admin keeps (web
// `PatchSettingsMembers.svelte`): the requests to join, the invitations,
// and the people removed. Each act is drawn as done the moment it is
// confirmed and put back, with the server's own sentence, if the quilt
// refuses it — the web waits and toasts; a phone row that sits there while
// the network decides reads as a tap that missed.

/// What the last act came to, said in a line at the head of the screen in
/// place of the web's toast.
struct AdminOutcome: Equatable {
    let text: String
    var refused = false
}

struct AdminOutcomeLine: View {
    let outcome: AdminOutcome
    let id: String
    var body: some View {
        Label {
            Text(outcome.text).font(Font.pw.footnote).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: outcome.refused ? "exclamationmark.circle" : "checkmark.circle").font(Font.pw.footnote)
        }
        .foregroundStyle(outcome.refused ? Color.pwText : Color.pwTextMuted)
        .accessibilityIdentifier(id)
    }
}

/// A person at the head of an admin's row: the avatar, the name as a door to
/// their profile where there is a username to open, and one line under it.
struct AdminPersonHead: View {
    let name: String
    let username: String?
    let avatar: URL?
    var detail: String? = nil
    let open: (String) -> Void
    var body: some View {
        HStack(spacing: 12) {
            AvatarMark(initial: String(name.first ?? "?").uppercased(), avatar: avatar)
            VStack(alignment: .leading, spacing: 2) {
                PersonName(name: name, username: username, font: Font.pw.body, open: open)
                if let detail { Text(detail).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted) }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Things that sit side by side — a person and the act beside them, or two
/// acts — until the text is at the accessibility sizes, where on one line
/// they broke the name and the acts' words mid-word; then one under the
/// other.
struct ActsRow<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout { content }
    }
}

/// A confirmation waiting to be answered: the act, on whom.
private struct PendingAct: Identifiable {
    let act: PatchAdmin.MemberAct
    let member: PatchMember
    var id: String { member.id }
}

private extension View {
    /// The web's two-tap `ConfirmAction` as the platform's own question:
    /// "Are you sure?", the act's own word, and what it does that the button
    /// cannot say.
    func confirmingAct(_ pending: Binding<PendingAct?>, perform: @escaping (PendingAct) -> Void) -> some View {
        confirmationDialog("Are you sure?",
                           isPresented: Binding(get: { pending.wrappedValue != nil }, set: { if !$0 { pending.wrappedValue = nil } }),
                           titleVisibility: .visible, presenting: pending.wrappedValue) { asked in
            Button(asked.act.title, role: asked.act.destructive ? .destructive : nil) { perform(asked) }
                .accessibilityIdentifier("confirmAct")
            Button("Cancel", role: .cancel) {}
        } message: { asked in
            Text(asked.act.consequence(asked.member.name))
        }
    }
}

// MARK: - Requests to join

/// The pending queue, oldest request first, paged by the server's cursor.
///
/// Gated here as well as at every door: the server answers a non-admin's
/// `status=pending` with the active list rather than a refusal, so a screen
/// that trusted its caller would draw members as requests.
struct JoinRequestsView: View {
    @EnvironmentObject private var session: QuiltSession
    let slug: String
    var close: (() -> Void)? = nil

    @State private var requests: [PatchMember] = []
    @State private var total = 0
    @State private var cursor = ""
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    @State private var outcome: AdminOutcome?
    @State private var confirming: PendingAct?
    @State private var person: String?

    private var runs: Bool { PatchAdmin.runs(session.standing(for: slug)) }
    private var name: String { session.memberships.first { $0.slug == slug }?.name ?? slug }

    var body: some View {
        List {
            Group {
                if !runs {
                    Section { WebsiteOnlyNote(text: "Only this patch’s admins answer its requests.") }
                } else {
                    if let outcome { Section { AdminOutcomeLine(outcome: outcome, id: "joinRequestsOutcome") } }
                    if !requests.isEmpty {
                        Section {
                            ForEach(requests) { row($0) }
                            if !cursor.isEmpty {
                                Button { Task { await load(after: cursor) } } label: {
                                    Text("Load more").font(Font.pw.subheadlineMedium).inkAction("arrow.down.circle")
                                }
                                .buttonStyle(.borderless)
                                .disabled(loading)
                                .accessibilityIdentifier("joinRequestsMore")
                            }
                        } header: {
                            // The server's count of the whole queue, never the
                            // page's: a queue of forty is not the twenty loaded.
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).font(Font.pw.footnoteSemibold)
                                Text(PatchAdmin.queueCount(total)).font(Font.pw.caption)
                                    .accessibilityIdentifier("joinRequestsCount")
                            }
                            .foregroundStyle(Color.pwTextMuted).textCase(nil)
                        }
                    }
                    if let error {
                        Section {
                            Text(error).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                            Button("Try again") { Task { await load() } }
                                .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
                        }
                    }
                }
            }
            .listRows()
        }
        .groundedList()
        .navigationTitle("Pending requests").navigationBarTitleDisplayMode(.inline)
        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
        .overlay {
            if runs && loaded && !loading && error == nil && requests.isEmpty {
                ContentUnavailableView("No pending requests.", systemImage: "person.crop.circle.badge.checkmark")
                    .accessibilityIdentifier("joinRequestsEmpty")
            } else if runs && !loaded {
                ProgressView()
            }
        }
        .confirmingAct($confirming) { asked in Task { await perform(asked.act, on: asked.member) } }
        .personDestination($person, quilt: session.quilt, close: close)
        .task { if !loaded { await load() } }
        .refreshable { await load() }
    }

    private func row(_ member: PatchMember) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AdminPersonHead(name: member.name, username: member.username, avatar: member.avatar,
                            detail: PatchAdmin.asked(member.joinedAt)) { person = $0 }
            if let message = PatchAdmin.quoted(member.joinMessage) {
                // The join sheet's intro (web ADR 040), quoted and never
                // editable here.
                Text(message).font(Font.pw.subheadline).italic().foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Their note: \(message)")
                    .accessibilityIdentifier("joinMessage-\(member.username ?? member.id)")
            }
            ActsRow(spacing: 16) {
                // A regular button around a 30pt label: 44pt to press, which
                // a small one is not.
                Button { confirming = PendingAct(act: .approve, member: member) } label: {
                    Text("Approve").font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwOnAccent).frame(minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.pwAccent)
                .accessibilityLabel("Approve \(member.name)")
                .accessibilityIdentifier("joinApprove-\(member.username ?? member.id)")
                Button { confirming = PendingAct(act: .reject, member: member) } label: {
                    Text("Reject").font(Font.pw.subheadline).foregroundStyle(Color.pwText).tapTarget()
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reject \(member.name)")
                .accessibilityIdentifier("joinReject-\(member.username ?? member.id)")
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
    }

    private func load(after: String? = nil) async {
        guard runs, !loading else { loaded = true; return }
        loading = true; error = nil
        defer { loading = false; loaded = true }
        do {
            let page = try await session.api.members(slug: slug, status: "pending", after: after)
            let rows = page.items ?? []
            if after == nil { requests = rows } else {
                let known = Set(requests.map(\.id))
                requests += rows.filter { !known.contains($0.id) }
            }
            total = page.memberCount ?? requests.count
            cursor = page.nextCursor ?? ""
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    /// Off the list at once; back where it was, with the quilt's sentence,
    /// if the quilt says no.
    private func perform(_ act: PatchAdmin.MemberAct, on member: PatchMember) async {
        guard let userId = member.userId, let index = requests.firstIndex(of: member) else { return }
        withAnimation { requests.remove(at: index); total = max(0, total - 1) }
        outcome = nil
        do {
            try await session.api.setMember(slug: slug, userId: userId, act)
            outcome = AdminOutcome(text: act.done)
            UIAccessibility.post(notification: .announcement, argument: act.done)
            session.adminChanged()
        } catch {
            if case APIError.unauthenticated = error { session.signedOut() }
            withAnimation { requests.insert(member, at: min(index, requests.count)); total += 1 }
            outcome = AdminOutcome(text: ProposalDetailView.sentence(error, fallback: act.failed), refused: true)
        }
    }
}

// MARK: - Inviting

/// "Invite a member" (web ADR 098): one field and the list of who has been
/// asked and has not answered. It is the only way into an invite-only patch.
struct InviteMembersView: View {
    @EnvironmentObject private var session: QuiltSession
    let slug: String
    var close: (() -> Void)? = nil

    @State private var username = ""
    @State private var inviting = false
    @State private var invited: [InvitedPerson] = []
    @State private var loaded = false
    @State private var outcome: AdminOutcome?
    @State private var rescinding: InvitedPerson?
    @State private var person: String?
    @FocusState private var typing: Bool

    private var runs: Bool { PatchAdmin.runs(session.standing(for: slug)) }

    var body: some View {
        List {
            Group {
                if !runs {
                    Section { WebsiteOnlyNote(text: "Only this patch’s admins invite people into it.") }
                } else {
                    Section {
                        // The button goes under the field at the
                        // accessibility sizes, where the two cannot share a
                        // line.
                        ActsRow(spacing: 10) {
                            TextField("Username", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.username)
                                .submitLabel(.send)
                                .focused($typing)
                                .onSubmit { Task { await invite() } }
                                .disabled(inviting)
                                .accessibilityLabel("Username to invite")
                                .accessibilityIdentifier("inviteUsername")
                            Button { Task { await invite() } } label: {
                                if inviting { ProgressView() } else {
                                    Text("Invite").font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwOnAccent).frame(minHeight: 30)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.pwAccent)
                            .disabled(inviting || PatchAdmin.inviteBody(username) == nil)
                            .accessibilityIdentifier("inviteSend")
                        }
                    } header: {
                        Text("Invite a member").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted).textCase(nil)
                    } footer: {
                        Text(PatchAdmin.inviteHelp).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    }
                    if let outcome { Section { AdminOutcomeLine(outcome: outcome, id: "inviteOutcome") } }
                    if !invited.isEmpty {
                        Section {
                            ForEach(invited) { row($0) }
                        } header: {
                            Text("Invited").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted).textCase(nil)
                        }
                    }
                }
            }
            .listRows()
        }
        .groundedList()
        .navigationTitle("Invite a member").navigationBarTitleDisplayMode(.inline)
        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog("Are you sure?",
                            isPresented: Binding(get: { rescinding != nil }, set: { if !$0 { rescinding = nil } }),
                            titleVisibility: .visible, presenting: rescinding) { asked in
            Button("Rescind", role: .destructive) { Task { await rescind(asked) } }
                .accessibilityIdentifier("confirmAct")
            Button("Cancel", role: .cancel) {}
        } message: { asked in
            Text("\(asked.name)’s invitation is taken back. They aren’t told.")
        }
        .personDestination($person, quilt: session.quilt, close: close)
        .task { if !loaded { await load() } }
        .refreshable { await load() }
    }

    private func row(_ person: InvitedPerson) -> some View {
        ActsRow {
            AdminPersonHead(name: person.name, username: person.username, avatar: person.avatar,
                            detail: PatchAdmin.invitedLine(person.invitedAt)) { self.person = $0 }
            Button { rescinding = person } label: {
                Text("Rescind").font(Font.pw.subheadline).foregroundStyle(Color.pwText).tapTarget()
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Rescind \(person.name)’s invitation")
            .accessibilityIdentifier("inviteRescind-\(person.username ?? person.userId)")
        }
        .padding(.vertical, 2)
    }

    /// The invited list rides on the members listing, for the patch's own
    /// admins; a page of one is enough to read it.
    private func load() async {
        defer { loaded = true }
        guard runs else { return }
        do {
            let page: MemberPage = try await session.api.get("nodes/\(slug)/members", query: [URLQueryItem(name: "limit", value: "1")])
            invited = page.invited ?? []
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {}
    }

    private func invite() async {
        guard !inviting, let body = PatchAdmin.inviteBody(username) else { return }
        inviting = true
        outcome = nil
        defer { inviting = false }
        do {
            try await session.api.invite(slug: slug, body: body)
            username = ""
            outcome = AdminOutcome(text: "Invitation sent")
            UIAccessibility.post(notification: .announcement, argument: "Invitation sent")
            session.adminChanged()
            await load()
        } catch {
            if case APIError.unauthenticated = error { session.signedOut() }
            outcome = AdminOutcome(text: ProposalDetailView.sentence(error, fallback: "Could not invite"), refused: true)
        }
    }

    private func rescind(_ person: InvitedPerson) async {
        guard let index = invited.firstIndex(of: person) else { return }
        withAnimation { _ = invited.remove(at: index) }
        outcome = nil
        do {
            try await session.api.rescindInvitation(slug: slug, userId: person.userId)
            outcome = AdminOutcome(text: "Invitation rescinded")
            UIAccessibility.post(notification: .announcement, argument: "Invitation rescinded")
            session.adminChanged()
        } catch {
            if case APIError.unauthenticated = error { session.signedOut() }
            withAnimation { invited.insert(person, at: min(index, invited.count)) }
            outcome = AdminOutcome(text: ProposalDetailView.sentence(error, fallback: "Could not rescind invitation"), refused: true)
        }
    }
}

// MARK: - Removed members

/// The web's "Removed Members": everyone this patch has removed, with
/// Reinstate. Reinstating does not make anybody a member again — it lets
/// them ask — so the row leaves this list and joins no other.
struct RemovedMembersView: View {
    @EnvironmentObject private var session: QuiltSession
    let slug: String
    var close: (() -> Void)? = nil

    @State private var removed: [PatchMember] = []
    @State private var total = 0
    @State private var cursor = ""
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    @State private var outcome: AdminOutcome?
    @State private var confirming: PendingAct?
    @State private var person: String?

    private var runs: Bool { PatchAdmin.runs(session.standing(for: slug)) }

    var body: some View {
        List {
            Group {
                if !runs {
                    Section { WebsiteOnlyNote(text: "Only this patch’s admins see who it has removed.") }
                } else {
                    if let outcome { Section { AdminOutcomeLine(outcome: outcome, id: "removedOutcome") } }
                    if !removed.isEmpty {
                        Section {
                            ForEach(removed) { member in
                                ActsRow {
                                    AdminPersonHead(name: member.name, username: member.username, avatar: member.avatar,
                                                    detail: "Removed") { person = $0 }
                                    Button { confirming = PendingAct(act: .reinstate, member: member) } label: {
                                        Text("Reinstate").font(Font.pw.subheadline).foregroundStyle(Color.pwText).tapTarget()
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Reinstate \(member.name)")
                                    .accessibilityIdentifier("reinstate-\(member.username ?? member.id)")
                                }
                                .padding(.vertical, 2)
                            }
                            if !cursor.isEmpty {
                                Button { Task { await load(after: cursor) } } label: {
                                    Text("Load more").font(Font.pw.subheadlineMedium).inkAction("arrow.down.circle")
                                }
                                .buttonStyle(.borderless)
                                .disabled(loading)
                            }
                        } header: {
                            Text("Removed members (\(total))").font(Font.pw.footnoteSemibold)
                                .foregroundStyle(Color.pwTextMuted).textCase(nil)
                        }
                    }
                    if let error {
                        Section {
                            Text(error).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                            Button("Try again") { Task { await load() } }
                                .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
                        }
                    }
                }
            }
            .listRows()
        }
        .groundedList()
        .navigationTitle("Removed members").navigationBarTitleDisplayMode(.inline)
        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
        .overlay {
            if runs && loaded && !loading && error == nil && removed.isEmpty {
                ContentUnavailableView("No removed members.", systemImage: "person.2")
            }
        }
        .confirmingAct($confirming) { asked in Task { await reinstate(asked.member) } }
        .personDestination($person, quilt: session.quilt, close: close)
        .task { if !loaded { await load() } }
        .refreshable { await load() }
    }

    private func load(after: String? = nil) async {
        guard runs, !loading else { loaded = true; return }
        loading = true; error = nil
        defer { loading = false; loaded = true }
        do {
            let page = try await session.api.members(slug: slug, status: "banned", after: after)
            let rows = page.items ?? []
            if after == nil { removed = rows } else {
                let known = Set(removed.map(\.id))
                removed += rows.filter { !known.contains($0.id) }
            }
            total = page.memberCount ?? removed.count
            cursor = page.nextCursor ?? ""
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func reinstate(_ member: PatchMember) async {
        guard let userId = member.userId, let index = removed.firstIndex(of: member) else { return }
        withAnimation { removed.remove(at: index); total = max(0, total - 1) }
        outcome = nil
        let act = PatchAdmin.MemberAct.reinstate
        do {
            try await session.api.setMember(slug: slug, userId: userId, act)
            outcome = AdminOutcome(text: act.done)
            UIAccessibility.post(notification: .announcement, argument: act.done)
            session.adminChanged()
        } catch {
            if case APIError.unauthenticated = error { session.signedOut() }
            withAnimation { removed.insert(member, at: min(index, removed.count)); total += 1 }
            outcome = AdminOutcome(text: ProposalDetailView.sentence(error, fallback: act.failed), refused: true)
        }
    }
}
