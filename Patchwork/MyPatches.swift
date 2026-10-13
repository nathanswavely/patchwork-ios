// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// My Patches: the web's `UserSettingsPatches.svelte`. Every relationship the
// reader holds, grouped the way the Dashboard groups them, and the two things
// a member owns about their own membership — whether it is public, and what
// the patch can reach them by. Joining, leaving, withdrawing and unfollowing
// are the membership index's own acts (`QuiltSession`), not new calls.

// MARK: - What the page reads beyond the index

/// One claim the reader holds, from `GET users/me/claims` (web ADR 039). Not
/// a membership: an approved claimant holds none until setup activates the
/// patch, which is why a claim needs a section of its own to be seen at all.
struct PatchClaim: Decodable, Identifiable, Hashable {
    let id: String
    let method: String?
    /// `pending` or `approved`. Nothing else is served.
    let status: String?
    let createdAt: String?
    /// Present once a claim is approved: when the setup window closes.
    let setupExpiresAt: String?
    let nodeSlug: String?
    let nodeName: String?

    var slug: String { nodeSlug ?? "" }
    var name: String { (nodeName?.isEmpty == false) ? nodeName! : slug }
    var ready: Bool { status == "approved" }
}

struct ClaimList: Decodable {
    let items: [PatchClaim]
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([PatchClaim].self, forKey: .items) ?? []
    }
    private enum CodingKeys: String, CodingKey { case items }
}

/// `PATCH users/me/memberships/{node_id}`. The server refuses a body without
/// `visible`, so it is not optional here.
struct MembershipVisibility: Codable, Equatable {
    var nodeId: String? = nil
    let visible: Bool
}

extension PatchworkAPI {
    /// One switch, both directions (web ADR 006): hidden from the reader's
    /// profile *and* from the patch's public member list.
    @discardableResult func setMembershipVisible(nodeID: String, visible: Bool) async throws -> Bool {
        let answer: MembershipVisibility = try await patch("users/me/memberships/\(nodeID)", body: MembershipVisibility(visible: visible))
        return answer.visible
    }
    /// Patches the reader runs that nobody can open (web ADR 034). Asked for
    /// by name, never mixed into the index every other surface reads: an
    /// admin row for a patch that 404s would draw doors onto the refusal.
    func archivedMemberships() async throws -> [Membership] {
        let archived = URLQueryItem(name: "status", value: "archived")
        return try await MembershipPage.all { try await get("me/nodes", query: $0 + [archived]) }
    }
    func claims() async throws -> [PatchClaim] {
        let list: ClaimList = try await get("users/me/claims")
        return list.items
    }
}

/// The page's rules and sentences, as values.
enum MyPatchesRules {
    /// The member rung a follower is offered, where it can succeed (web ADR
    /// 042): an unclaimed patch takes followers only and an invite-only one
    /// does its own asking. The words are this page's, not the profile's.
    static func rung(_ row: Membership) -> Relationship.Join? {
        if row.nodeStatus == "unclaimed" || row.membershipPolicy == "invite_only" { return nil }
        return row.membershipPolicy == "approval_required" ? .request : .now
    }
    static func rungTitle(_ join: Relationship.Join) -> String { join == .request ? "Send request" : "Become a member" }

    /// Why a follower has no rung, worn as a fact beside the row.
    static func stateNote(_ row: Membership) -> (label: String, detail: String)? {
        if row.nodeStatus == "unclaimed" { return ("Unclaimed", "No one runs this patch yet. You can follow it, but not join.") }
        if row.membershipPolicy == "invite_only" { return ("Invite only", "This patch adds members by invitation. An admin has to invite you.") }
        return nil
    }

    /// The web's two tooltips, as the switch's footer.
    static func visibilitySentence(_ visible: Bool) -> String {
        visible
            ? "Shown on your profile and the patch’s public member list. Switch it off to hide it from both."
            : "Hidden from your profile and the patch’s public member list. Its admins and members still see you."
    }
    static func visibilityOutcome(_ visible: Bool) -> String {
        visible ? "Membership visible to the public" : "Membership hidden from the public"
    }

    /// "Public · Reachable by 2", the row's summary of the two switches.
    static func summary(_ row: Membership) -> String {
        "\(row.visible == false ? "Hidden" : "Public") · \(ContactWording.reach(row.contactItemsShared ?? 0))"
    }

    static func day(_ value: String?) -> String? {
        AccountDate.parse(value)?.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - The page

struct MyPatchesSettings: View {
    let onExit: (SettingsExit) -> Void
    @EnvironmentObject private var session: QuiltSession
    @State private var archived: [Membership] = []
    @State private var claims: [PatchClaim] = []
    @State private var card: [ContactItem]?
    @State private var loaded = false
    @State private var note: String?
    @State private var refused = false
    @State private var busy: String?
    @State private var joining: Membership?
    @State private var confirming: Membership?

    private var sections: DashboardGrouping.Sections { DashboardGrouping.group(session.memberships) }
    private var cardEmpty: Bool { card?.isEmpty == true }

    var body: some View {
        List {
            Group {
                if let note {
                    Section {
                        Label(note, systemImage: refused ? "exclamationmark.circle" : "checkmark")
                            .font(Font.pw.footnote)
                            .foregroundStyle(refused ? Color.pwText : Color.pwTextMuted)
                            .accessibilityIdentifier("myPatchesNote")
                    }
                }
                if !claims.isEmpty { claimsSection }
                if !archived.isEmpty { archivedSection }
                if loaded, sections.isEmpty, claims.isEmpty, archived.isEmpty {
                    Section {
                        Text("You haven’t joined any patches yet.")
                            .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                            .accessibilityIdentifier("myPatchesEmpty")
                    }
                }
                if cardEmpty, !(sections.managing.isEmpty && sections.member.isEmpty) {
                    Section {
                        Text("Your contact card is empty. Add the ways you are willing to be reached, then give them to patches one at a time here.")
                            .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                        NavigationLink { ContactCardSettings() } label: { Text("Contact card").font(Font.pw.body) }
                            .accessibilityIdentifier("myPatchesContactCard")
                    }
                }
                roomSection("Managing", rows: sections.managing)
                roomSection("Member of", rows: sections.member)
                if !sections.requested.isEmpty {
                    Section {
                        ForEach(sections.requested) { requestedRow($0) }
                    } header: { settingsHeading("Requested") }
                }
                if !sections.following.isEmpty {
                    Section {
                        ForEach(sections.following) { followingRow($0) }
                    } header: { settingsHeading("Following") }
                }
            }
            .listRows()
        }
        .groundedList()
        .navigationTitle("My Patches")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if !loaded { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $joining) { row in
            JoinSheet(name: row.name, join: MyPatchesRules.rung(row) ?? .now) { message in
                await perform(row) {
                    let status = try await session.join(row.slug, message: message)
                    return Relationship.joinOutcome(status: status)
                }
            }
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { row in
            let pending = row.standing == .pending
            Button(pending ? "Withdraw request" : (row.standing == .active(.follower) ? "Unfollow" : "Leave"), role: .destructive) {
                Task { await exit(row) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var confirmTitle: String {
        guard let row = confirming else { return "" }
        switch row.standing {
        case .pending: return "Withdraw your request to \(row.name)?"
        case .active(.follower): return "Unfollow \(row.name)?"
        default: return "Leave \(row.name)?"
        }
    }

    // MARK: Sections

    private var claimsSection: some View {
        Section {
            ForEach(claims) { claim in
                VStack(alignment: .leading, spacing: 6) {
                    Text(claim.name).font(Font.pw.body).foregroundStyle(Color.pwText)
                    HStack(spacing: 6) {
                        pill(claim.ready ? "Ready to set up" : "Claim under review")
                        if let line = claimLine(claim) {
                            Text(line).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                        }
                    }
                    // Claiming and setting up are the website's: the app has
                    // no claim flow, so the one act here is a door to it.
                    Link(destination: session.api.webURL("patches/\(claim.slug)/\(claim.ready ? "setup" : "claim")")) {
                        Text(claim.ready ? "Set up patch" : "View claim").font(Font.pw.subheadline)
                    }
                    .exitLink()
                    .accessibilityIdentifier("myPatchesClaim-\(claim.slug)")
                }
                .padding(.vertical, 2)
            }
        } header: {
            settingsHeading("Claiming")
        } footer: {
            settingsFootnote("Claiming a patch and setting it up happen on this quilt’s website. Until setup is done, the patch still reads as unclaimed to everyone else.")
        }
    }

    private func claimLine(_ claim: PatchClaim) -> String? {
        if claim.ready, let day = MyPatchesRules.day(claim.setupExpiresAt) { return "Expires \(day)" }
        return MyPatchesRules.day(claim.createdAt).map { "Claimed \($0)" }
    }

    private var archivedSection: some View {
        Section {
            ForEach(archived) { row in
                // No door: every route refuses an archived patch, so one here
                // would open onto the refusal this section explains.
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name).font(Font.pw.body).foregroundStyle(Color.pwText)
                    HStack(spacing: 6) {
                        pill("Archived")
                        // The address, because an archived patch is often a
                        // duplicate of one still running under the same name.
                        Text(verbatim: "/\(row.slug)").font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                        if let day = MyPatchesRules.day(row.joinedAt) {
                            Text("Joined \(day)").font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                        }
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("myPatchesArchived-\(row.slug)")
            }
        } header: {
            settingsHeading("Archived")
        } footer: {
            settingsFootnote("You run these and nobody can open them. Restoring a patch is an instance admin’s to do.")
        }
    }

    /// Managing and Member of: each patch a door to its own page, where the
    /// two switches live, with what they are set to said on the row.
    @ViewBuilder private func roomSection(_ title: String, rows: [Membership]) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    NavigationLink { MyPatchDetail(slug: row.slug, onExit: onExit) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.name).font(Font.pw.body).foregroundStyle(Color.pwText)
                            Text(MyPatchesRules.summary(row))
                                .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                                .accessibilityIdentifier("myPatchSummary-\(row.slug)")
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityIdentifier("myPatch-\(row.slug)")
                }
            } header: { settingsHeading(title) }
        }
    }

    private func requestedRow(_ row: Membership) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            nameDoor(row)
            HStack(spacing: 6) {
                pill("Awaiting approval")
                if let day = MyPatchesRules.day(row.joinedAt) {
                    Text("Asked \(day)").font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                }
            }
            // No contact control: a request is not standing in the room yet,
            // so there is nothing to share into.
            Button { confirming = row } label: {
                Text("Withdraw").font(Font.pw.subheadline).inkAction("arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .disabled(busy != nil)
            .accessibilityIdentifier("myPatchesWithdraw-\(row.slug)")
        }
        .padding(.vertical, 2)
    }

    private func followingRow(_ row: Membership) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            nameDoor(row)
            HStack(spacing: 6) {
                pill("Following")
                if let state = MyPatchesRules.stateNote(row) {
                    pill(state.label, dashed: true).accessibilityHint(state.detail)
                }
                if let day = MyPatchesRules.day(row.joinedAt) {
                    Text(day).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                }
            }
            if let state = MyPatchesRules.stateNote(row) {
                Text(state.detail).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
            }
            HStack(spacing: 12) {
                if let join = MyPatchesRules.rung(row) {
                    Button { joining = row } label: {
                        if busy == row.slug { ProgressView() } else { Text(MyPatchesRules.rungTitle(join)).font(Font.pw.subheadlineSemibold).foregroundStyle(.white) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.pwAccent)
                    .controlSize(.small)
                    .disabled(busy != nil)
                    .accessibilityIdentifier("myPatchesJoin-\(row.slug)")
                }
                Button { confirming = row } label: {
                    Text("Unfollow").font(Font.pw.subheadline).foregroundStyle(Color.pwText)
                }
                .buttonStyle(.borderless)
                .disabled(busy != nil)
                .accessibilityIdentifier("myPatchesUnfollow-\(row.slug)")
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 2)
    }

    /// The patch's name as a door: Settings closes and the patch docks.
    private func nameDoor(_ row: Membership) -> some View {
        Button { onExit(.dock(row.slug)) } label: {
            Text(row.name).font(Font.pw.body).inkRow(fills: false)
        }
        .buttonStyle(.borderless)
        .accessibilityHint("Opens the patch.")
    }

    private func pill(_ text: String, dashed: Bool = false) -> some View {
        Text(text)
            .font(Font.pw.caption2Semibold).foregroundStyle(Color.pwTextMuted)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Color.pwBorder, style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 2] : [])))
    }

    // MARK: Acts

    private func load() async {
        await session.refreshMemberships()
        // Each of these is best effort: a section that cannot be read is a
        // section that is not drawn, and the index above it still is.
        async let archivedRows = try? session.api.archivedMemberships()
        async let claimRows = try? session.api.claims()
        async let cardItems = try? session.api.contactItems()
        archived = await archivedRows ?? []
        claims = await claimRows ?? []
        card = await cardItems
        loaded = true
    }

    /// Two verbs, two routes (web ADR 088): a request is withdrawn, a
    /// relationship is left. Routing on the row's standing is what makes a
    /// stale page safe — a request approved since the page loaded is refused
    /// by `withdraw` rather than quietly resigned.
    private func exit(_ row: Membership) async {
        await perform(row) {
            switch row.standing {
            case .pending:
                try await session.withdraw(row.slug)
                return "Request withdrawn"
            case .active(.follower):
                try await session.unfollow(row.slug)
                return "Unfollowed patch"
            default:
                try await session.leave(row.slug)
                return "Left patch"
            }
        }
    }

    private func perform(_ row: Membership, _ act: () async throws -> String) async {
        busy = row.slug
        defer { busy = nil }
        do {
            note = try await act()
            refused = false
        } catch APIError.unauthenticated {
            // The session has already gone; the sheet follows it.
        } catch {
            note = sentenceCased(SignInModel.sentence(error))
            refused = true
        }
    }
}

// MARK: - One patch

/// A patch the reader is in: whether the membership is public, and what the
/// patch can reach them by. Leaving is here too for a member; an admin
/// leaves through the patch's own governance, as on the web.
struct MyPatchDetail: View {
    let slug: String
    let onExit: (SettingsExit) -> Void
    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    @State private var visible = true
    @State private var savingVisible = false
    @State private var card: [ContactItem]?
    @State private var sharing = false
    @State private var note: String?
    @State private var failure: String?
    @State private var confirmingLeave = false
    @State private var leaving = false

    private var row: Membership? { session.memberships.first { $0.slug == slug } }
    private var name: String { row?.name ?? slug }
    private var cardEmpty: Bool { card?.isEmpty == true }

    var body: some View {
        List {
            Group {
                if let row {
                    Section {
                        Button { onExit(.dock(slug)) } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Open \(row.name)").font(Font.pw.body).foregroundStyle(Color.pwText)
                                    Text(standingLine(row)).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold)).foregroundStyle(Color.pwTextMuted)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("myPatchOpen")
                    }
                    Section {
                        Toggle(isOn: Binding(get: { visible }, set: { value in visible = value; Task { await saveVisible(value) } })) {
                            Text("Public").font(Font.pw.body)
                        }
                        .tint(Color.pwAccent)
                        .disabled(savingVisible || row.nodeId == nil)
                        .accessibilityIdentifier("membershipVisible")
                    } header: {
                        settingsHeading("Visibility")
                    } footer: {
                        settingsFootnote(MyPatchesRules.visibilitySentence(visible))
                            .accessibilityIdentifier("membershipVisibleFooter")
                    }
                    Section {
                        Button { sharing = true } label: {
                            HStack {
                                Text(ContactWording.reach(row.contactItemsShared ?? 0)).font(Font.pw.body)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.pwTextMuted)
                            }
                            .foregroundStyle(cardEmpty ? Color.pwTextMuted : Color.pwText)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(cardEmpty || card == nil)
                        .accessibilityIdentifier("contactSharing")
                        if cardEmpty {
                            NavigationLink { ContactCardSettings() } label: { Text("Contact card").font(Font.pw.body) }
                                .accessibilityIdentifier("myPatchContactCard")
                        }
                    } header: {
                        settingsHeading("Contact")
                    } footer: {
                        settingsFootnote(cardEmpty
                                         ? "Add something to your contact card first."
                                         : "Choose which of your contact items this patch’s admins and members can read. Its followers never can.")
                    }
                    if let failure {
                        Section { Text(failure).font(Font.pw.footnote).foregroundStyle(Color.pwText).accessibilityIdentifier("myPatchError") }
                    } else if let note {
                        Section {
                            Label(note, systemImage: "checkmark").font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                                .accessibilityIdentifier("myPatchNote")
                        }
                    }
                    if row.standing == .active(.member) {
                        Section {
                            Button(role: .destructive) { confirmingLeave = true } label: {
                                if leaving { ProgressView() } else {
                                    Text("Leave \(row.name)").font(Font.pw.body).foregroundStyle(Color(.systemRed))
                                }
                            }
                            .disabled(leaving)
                            .accessibilityIdentifier("myPatchLeave")
                        }
                    }
                }
            }
            .listRows()
        }
        .groundedList()
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if let row { visible = row.visible ?? true } }
        .task { card = try? await session.api.contactItems() }
        .sheet(isPresented: $sharing) {
            ContactSharingSheet(slug: slug, name: name) { count in
                note = ContactWording.shareOutcome(patch: name, count: count)
                failure = nil
            }
            .environmentObject(session)
        }
        .confirmationDialog("Leave \(name)?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { Task { await leave() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anything from your contact card you gave it stops being shared with it.")
        }
    }

    private func standingLine(_ row: Membership) -> String {
        var parts = [row.standing.flatMap { if case .active(let role) = $0 { return role.mark } else { return nil } } ?? "Member"]
        if let day = MyPatchesRules.day(row.joinedAt) { parts.append("Joined \(day)") }
        return parts.joined(separator: " · ")
    }

    /// Saved the moment it moves, put back on a refusal.
    private func saveVisible(_ value: Bool) async {
        guard let nodeID = row?.nodeId else { return }
        savingVisible = true
        failure = nil
        defer { savingVisible = false }
        do {
            visible = try await session.api.setMembershipVisible(nodeID: nodeID, visible: value)
            note = MyPatchesRules.visibilityOutcome(visible)
            await session.refreshMemberships()
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            visible = !value
            failure = sentenceCased(SignInModel.sentence(error))
        }
    }

    private func leave() async {
        leaving = true
        defer { leaving = false }
        do {
            try await session.leave(slug)
            dismiss()
        } catch APIError.unauthenticated {
            // Signed out; Settings closes on its own.
        } catch {
            failure = sentenceCased(SignInModel.sentence(error))
        }
    }
}

// MARK: - What a patch can reach you by

/// The web's picker as a sheet: the card's items, ticked where this patch can
/// read them, and nothing changes until Save. The whole set is sent at once.
struct ContactSharingSheet: View {
    let slug: String
    let name: String
    let saved: (Int) -> Void
    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    @State private var shares: ContactShares?
    @State private var chosen = Set<String>()
    @State private var busy = false
    @State private var failure: String?

    private var changed: Bool { shares.map { $0.sharedIDs != chosen } ?? false }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    if let shares {
                        Section {
                            ForEach(shares.items) { item in
                                Button { toggle(item.id) } label: {
                                    HStack {
                                        ContactItemLine(item: item)
                                        Spacer(minLength: 8)
                                        if chosen.contains(item.id) {
                                            Image(systemName: "checkmark").font(Font.pw.bodyBold).foregroundStyle(Color.pwAccent)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(busy || !shares.canShare)
                                .accessibilityAddTraits(chosen.contains(item.id) ? .isSelected : [])
                                .accessibilityIdentifier("shareItem")
                            }
                        } header: {
                            settingsHeading("What \(name) can reach you by")
                        } footer: {
                            settingsFootnote(shares.canShare
                                             ? "Its admins and members see whatever you tick here, including anyone who joins later. Its followers never can."
                                             : "Only this patch’s members and admins can share contact details with it.")
                        }
                    } else if failure == nil {
                        Section { ProgressView().frame(maxWidth: .infinity) }
                    }
                    if let failure {
                        Section { Text(failure).font(Font.pw.footnote).foregroundStyle(Color.pwText).accessibilityIdentifier("shareError") }
                    }
                }
                .listRows()
            }
            .groundedList()
            .navigationTitle("Contact sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!changed || shares?.canShare != true)
                            .accessibilityIdentifier("shareSave")
                    }
                }
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggle(_ id: String) {
        if chosen.contains(id) { chosen.remove(id) } else { chosen.insert(id) }
    }

    private func load() async {
        do {
            let answer = try await session.api.contactShares(slug: slug)
            shares = answer
            chosen = answer.sharedIDs
        } catch APIError.unauthenticated {
            session.signedOut()
            dismiss()
        } catch {
            failure = sentenceCased(SignInModel.sentence(error))
        }
    }

    private func save() async {
        guard let shares else { return }
        busy = true
        failure = nil
        defer { busy = false }
        // In the card's own order, so the set reads the same every time.
        let ids = shares.items.map(\.id).filter { chosen.contains($0) }
        do {
            try await session.api.setContactShares(slug: slug, itemIDs: ids)
            await session.refreshMemberships()
            saved(ids.count)
            dismiss()
        } catch APIError.unauthenticated {
            session.signedOut()
            dismiss()
        } catch {
            failure = sentenceCased(SignInModel.sentence(error))
        }
    }
}
