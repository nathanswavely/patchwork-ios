// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// The people in a patch, as a patch publishes them (web ADR 006, ADR 095).
///
/// A signed-out reader is always outside the room, so the patch's own
/// `public_member_list` setting decides on its own: `everyone` lists members
/// and admins, `admins` lists only the admins and says so once above the list,
/// and `nobody` lists nobody. The counts stay public at every rung — the quilt
/// sizes this patch's tile by them — so the withheld state states the number
/// and says the list is not published. It never says there are no members.
///
/// For the patch's own admin the room is also where its membership is kept
/// (web `PatchSettingsMembers.svelte`): doors to the requests waiting, to
/// inviting somebody, and to the people removed, and Remove on each row
/// but their own — on the swipe and the long press, as Mail and Contacts
/// keep a row's acts. Role changes stay on the website.
struct PatchMemberList: View {
    @EnvironmentObject private var session: QuiltSession
    let quilt: Quilt
    let slug: String
    var close: (() -> Void)? = nil
    @State private var roster = MemberRoster()
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    /// The admin's three counts: the queue, the invitations out, and the
    /// people removed.
    @State private var pendingCount = 0
    @State private var invitedCount = 0
    @State private var removedCount = 0
    @State private var removing: PatchMember?
    @State private var outcome: AdminOutcome?
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    private var onSessionQuilt: Bool { quilt.url == session.quilt.url }
    private var standing: Standing? { onSessionQuilt ? session.standing(for: slug) : nil }
    private var runs: Bool { PatchAdmin.runs(standing) }
    var body: some View {
        List {
            // One Group so every section's rows take the card surface: the
            // modifier does not reach them from the List itself.
            Group {
            if runs { adminSection }
            if let outcome { Section { AdminOutcomeLine(outcome: outcome, id: "membersOutcome") } }
            if loaded && !roster.withheld {
                Section {
                    ForEach(roster.members) { member in
                        memberRow(member)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) { removeAct(member) }
                            .contextMenu { removeAct(member) }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 3) {
                        // The counts are the server's, never the loaded
                        // array's: the listing is paged, and counting what
                        // arrived would report the page size as the patch's
                        // size. On a patch where somebody has hidden their
                        // membership the count sits above a shorter list on
                        // purpose.
                        Text(roster.countLine).font(Font.pw.footnoteSemibold)
                        if roster.adminsOnly {
                            // Said once, above the list: three rows under a
                            // count of forty otherwise reads as a bug.
                            Text("Only this patch’s admins are listed publicly.").font(Font.pw.caption)
                        }
                    }
                    .foregroundStyle(Color.pwTextMuted).textCase(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let cursor = roster.cursor, !cursor.isEmpty {
                    Button("Load more") { Task { await load(after: cursor) } }
                        .font(Font.pw.subheadlineMedium).inkAction("arrow.down.circle").disabled(loading)
                }
            }
            if loading { ProgressView("Loading members…") }
            if let error {
                Section {
                    Text(error).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    Button("Try again") { Task { await load() } }
                        .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
                }
            }
            Section {
                // Joining and following live in the patch's own head, where
                // the counts they change are. An admin keeps the membership
                // here, all but its roles, which are the website's.
                WebsiteOnlyNote(text: runs ? PatchAdmin.roleNote : "Following and joining are on this patch’s own page.")
            }
            }.listRows()
        }
        .groundedList()
        .navigationTitle(roster.title).navigationBarTitleDisplayMode(.inline)
        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
        .overlay {
            if loaded && !loading && error == nil && (roster.withheld || roster.members.isEmpty) {
                ContentUnavailableView {
                    Label(roster.emptyTitle, systemImage: roster.withheld ? "eye.slash" : "person.2")
                } description: {
                    VStack(spacing: 6) {
                        Text(roster.emptyMessage).font(Font.pw.body)
                        if roster.withheld { Text(roster.countLine).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted) }
                    }
                }
            }
        }
        .confirmationDialog("Are you sure?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { member in
            Button("Remove", role: .destructive) { Task { await remove(member) } }
                .accessibilityIdentifier("confirmAct")
            Button("Cancel", role: .cancel) {}
        } message: { member in
            Text(PatchAdmin.MemberAct.remove.consequence(member.name))
        }
        .task { if !loaded { await load() } }
        .refreshable { await load() }
        // A request answered, an invitation sent or somebody reinstated from
        // a room pushed over this one: the roster and the counts read again.
        .onChange(of: session.adminRevision) { _, _ in Task { await load() } }
    }

    @ViewBuilder private func memberRow(_ member: PatchMember) -> some View {
        // Somebody with a username opens their profile; a row without one
        // stays a name.
        if let handle = People.door(member.username) {
            NavigationLink { PersonProfile(quilt: quilt, username: handle, close: close) } label: {
                PersonRow(name: member.name, initial: member.initial, avatar: member.avatar, role: member.role)
            }
            .accessibilityIdentifier("memberRow")
        } else {
            PersonRow(name: member.name, initial: member.initial, avatar: member.avatar, role: member.role)
                .accessibilityIdentifier("memberRow")
        }
    }

    /// Remove, where this reader may: never their own row. Not a destructive
    /// role, which would have the list animate the row away before the
    /// confirmation has been answered.
    @ViewBuilder private func removeAct(_ member: PatchMember) -> some View {
        if runs && PatchAdmin.mayRemove(member, me: session.me?.id) {
            Button { removing = member } label: { Label("Remove", systemImage: "person.fill.xmark") }
                .tint(.red)
                .accessibilityIdentifier("memberRemove-\(member.username ?? member.id)")
        }
    }

    /// The three rooms an admin keeps, each with its count.
    private var adminSection: some View {
        Section {
            NavigationLink { JoinRequestsView(slug: slug, close: close) } label: {
                adminDoor("Pending requests", symbol: "person.crop.circle.badge.questionmark", count: pendingCount)
            }
            .accessibilityIdentifier("membersRequests")
            NavigationLink { InviteMembersView(slug: slug, close: close) } label: {
                adminDoor("Invite a member", symbol: "envelope", count: invitedCount, unit: "invited")
            }
            .accessibilityIdentifier("membersInvite")
            if removedCount > 0 {
                NavigationLink { RemovedMembersView(slug: slug, close: close) } label: {
                    adminDoor("Removed members", symbol: "person.fill.xmark", count: removedCount)
                }
                .accessibilityIdentifier("membersRemoved")
            }
        }
    }

    private func adminDoor(_ title: String, symbol: String, count: Int, unit: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
                .frame(width: 22).accessibilityHidden(true)
            Text(title).font(Font.pw.body).foregroundStyle(Color.pwText)
            Spacer(minLength: 8)
            if count > 0 {
                Text(unit.map { "\(count) \($0)" } ?? String(count))
                    .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
            }
        }
    }

    /// Off the roster at once, back with the quilt's sentence on a refusal —
    /// "cannot ban the last admin" among them.
    private func remove(_ member: PatchMember) async {
        guard let userId = member.userId, let index = roster.members.firstIndex(of: member) else { return }
        withAnimation { roster.members.remove(at: index); roster.memberCount = max(0, roster.memberCount - 1) }
        outcome = nil
        let act = PatchAdmin.MemberAct.remove
        do {
            try await session.api.setMember(slug: slug, userId: userId, act)
            removedCount += 1
            outcome = AdminOutcome(text: act.done)
            UIAccessibility.post(notification: .announcement, argument: act.done)
            session.adminChanged()
        } catch {
            if case APIError.unauthenticated = error { session.signedOut() }
            withAnimation { roster.members.insert(member, at: min(index, roster.members.count)); roster.memberCount += 1 }
            outcome = AdminOutcome(text: ProposalDetailView.sentence(error, fallback: act.failed), refused: true)
        }
    }
    private func load(after: String? = nil) async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false; loaded = true }
        do {
            let page: MemberPage = try await api.get("nodes/\(slug)/members", query: query(after: after))
            if after == nil { roster = MemberRoster(page: page, inRoom: Noticeboard.inRoom(standing)) } else { roster.append(page) }
            if after == nil && runs {
                invitedCount = page.invited?.count ?? 0
                async let pending = try? api.memberTotal(slug: slug, status: "pending")
                async let banned = try? api.memberTotal(slug: slug, status: "banned")
                let (p, b) = await (pending, banned)
                pendingCount = p ?? pendingCount
                removedCount = b ?? removedCount
            }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func query(after: String?) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: "50")]
        if let after, !after.isEmpty { items.append(URLQueryItem(name: "after", value: after)) }
        return items
    }
}
