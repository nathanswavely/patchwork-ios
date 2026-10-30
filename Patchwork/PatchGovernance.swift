// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// How a patch governs itself, read from outside it.
///
/// Four rooms behind one door: the overview (how decisions are made, who
/// leads, and the council's chairs), the documents it has published, the
/// proposals it has raised, and the record of what it settled. Proposals and
/// the record are a patch's own disclosure — `public_governance_record`
/// — and where that is `nobody` the two rooms are absent rather than empty,
/// because an empty room would report a patch that deliberates in private as
/// a patch that has never decided anything.
///
/// Voting, standing and discussing happen on a proposal's own screen, which
/// the rows here lead to; a member who owes a ballot is told so at the top,
/// as a door into the open proposals. A member or an admin raises a proposal
/// from the bar at the foot, here and in the proposals room; the form is
/// what the patch's rules make it (`ProposalPosting`). The rules have their
/// own door under how decisions are made (`RulesChangeSheet`), a document
/// its own on the document (`DocumentAmendmentSheet`), and an admin writes
/// a new one from the documents room. What stays the website's is named
/// once, to the patch's admins.
struct PatchGovernanceHome: View {
    @EnvironmentObject private var session: QuiltSession
    let quilt: Quilt
    let patch: Patch
    var close: (() -> Void)? = nil
    @State private var overview: GovernanceOverview?
    @State private var loading = true
    @State private var error: String?
    @State private var composing = false
    @State private var changingRules = false
    /// A proposal the form made, waiting for the form to leave before it is
    /// opened; and the one opened.
    @State private var made: Proposal?
    @State private var opened: Proposal?
    /// Something was proposed or withdrawn while another screen was up: the
    /// counts here are out of date.
    @State private var stale = false
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    /// Only on the quilt the reader is signed in to: no act crosses quilts.
    private var signedIn: Bool { quilt.url == session.quilt.url && session.me != nil }
    private var standing: Standing? { session.standing(for: patch.slug) }
    private var door: String? { ProposalPosting.door(signedIn: signedIn, standing: standing, rules: overview?.rules) }
    private var rulesDoor: RulesChange.Door? { RulesChange.door(signedIn: signedIn, standing: standing, rules: overview?.rules) }
    /// The patch's own setting decides until the overview answers; then the
    /// overview does, because it is answered for this reader — a member of
    /// a patch that keeps its record to the room is in the room, and must
    /// not be told its own proposals are not public.
    private var recordWithheld: Bool {
        if let overview { return overview.proposalsWithheld == true }
        return patch.publicGovernanceRecord == "nobody"
    }
    var body: some View {
        List {
            // One Group so every section's rows take the card surface: the
            // modifier does not reach them from the List itself.
            Group {
            if let overview {
                if let needs = overview.needsVote, needs > 0, !recordWithheld {
                    Section {
                        NavigationLink {
                            proposalList
                        } label: {
                            Label(Self.needsVoteLine(needs), systemImage: "checkmark.circle")
                                .font(Font.pw.headline).foregroundStyle(Color.pwText)
                        }
                        .accessibilityIdentifier("needsYourVote")
                    }
                }
                if let election = overview.election, election.phase == "nominating" {
                    Section {
                        NavigationLink {
                            ProposalDetailView(quilt: quilt, initial: Proposal(id: election.id, title: ""), close: close) { stale = true }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Nominations are open for \(VoteRules.seatsLabel(election.seats ?? 0))")
                                    .font(Font.pw.headline).foregroundStyle(Color.pwText)
                                Text(candidateLine(election)).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                            }.padding(.vertical, 2)
                        }
                        .accessibilityIdentifier("electionNominating")
                    }
                }
                if !overview.decisionNarrative.isEmpty || rulesDoor != nil {
                    Section("How decisions are made") {
                        if !overview.decisionNarrative.isEmpty {
                            Text(overview.decisionNarrative).fixedSize(horizontal: false, vertical: true)
                        }
                        // The way into the rules sits under what they say,
                        // as on the web's overview.
                        switch rulesDoor {
                        case .open(let label):
                            Button { changingRules = true } label: {
                                Text(label).font(Font.pw.subheadlineMedium).inkAction("slider.horizontal.3").tapTarget()
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("rulesDoor")
                        case .note(let line):
                            Text(line).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                                .accessibilityIdentifier("rulesDoorNote")
                        case nil:
                            EmptyView()
                        }
                    }
                }
                Section("Leadership: \(overview.leadershipLabel)") {
                    if !overview.showsCouncil, !overview.leadershipNarrative.isEmpty {
                        Text(overview.leadershipNarrative).fixedSize(horizontal: false, vertical: true)
                    }
                    // Withheld is tested before the list's length, or a patch
                    // that has taken its roster down is reported as leaderless.
                    if overview.adminsWithheld == true {
                        Label("This patch does not list its admins publicly.", systemImage: "eye.slash")
                            .foregroundStyle(Color.pwTextMuted)
                    } else if let admins = overview.admins, !admins.isEmpty {
                        ForEach(admins) { admin in
                            let row = PersonRow(
                                name: admin.name, initial: admin.initial, avatar: admin.avatar,
                                detail: ProfileDate.monthYear(admin.joinedAt).map { "Member since \($0)" }
                            )
                            if let handle = People.door(admin.username) {
                                NavigationLink { PersonProfile(quilt: quilt, username: handle, close: close) } label: { row }
                                    .accessibilityIdentifier("governanceAdmin")
                            } else {
                                row
                            }
                        }
                    } else {
                        Text("Nobody holds the admin role here yet.").foregroundStyle(Color.pwTextMuted)
                    }
                }
                if overview.showsCouncil { council(overview) }
                Section("Rooms") {
                    NavigationLink {
                        GovernanceDocumentList(quilt: quilt, slug: patch.slug, close: close)
                    } label: {
                        Label("Documents", systemImage: "doc.text")
                            .badge(overview.documentCount ?? 0)
                    }.accessibilityIdentifier("governanceDocuments")
                    if recordWithheld {
                        Label("Proposals and decisions here are not public.", systemImage: "lock")
                            .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    } else {
                        NavigationLink {
                            proposalList
                        } label: {
                            Label("Proposals", systemImage: "checkmark.bubble")
                                .badge(overview.openProposals ?? 0)
                        }.accessibilityIdentifier("governanceProposals")
                        NavigationLink {
                            GovernanceRecordList(quilt: quilt, slug: patch.slug, close: close)
                        } label: {
                            Label("Record", systemImage: "clock.arrow.circlepath")
                        }.accessibilityIdentifier("governanceRecord")
                    }
                }
            }
            if loading { ProgressView("Loading governance…") }
            if let error {
                Section {
                    Text(error).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    Button("Try again") { Task { await load() } }
                        .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
                }
            }
            if standing == .active(.admin) && overview != nil {
                Section {
                    WebsiteOnlyNote(text: Self.websiteNote)
                }
            }
            }.listRows()
        }
        .groundedList()
        .navigationTitle("Governance").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let door {
                ToolbarItem(placement: .bottomBar) { ProposalDoorButton(label: door) { composing = true } }
            }
            if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
        }
        // The new proposal opens once the form has gone, pushed onto this
        // room's own stack, so Back is the room with it already counted.
        .sheet(isPresented: $composing, onDismiss: { if let made { opened = made; self.made = nil } }) {
            ProposalFormSheet(slug: patch.slug, rules: overview?.rules, seats: overview?.seats ?? [],
                              nextContestOpens: overview?.nextContestOpens, isPatchAdmin: standing == .active(.admin)) { proposal in
                made = proposal
                stale = true
            }
        }
        .sheet(isPresented: $changingRules, onDismiss: { if let made { opened = made; self.made = nil } }) {
            RulesChangeSheet(slug: patch.slug, isPatchAdmin: standing == .active(.admin)) { proposal in
                made = proposal
                stale = true
            }
        }
        .navigationDestination(item: $opened) { ProposalDetailView(quilt: quilt, initial: $0, close: close) { stale = true } }
        .task { if overview == nil { await load() } }
        .onAppear { if stale { stale = false; Task { await load() } } }
    }
    /// The proposals room, handed the rules this room already holds, so its
    /// own door opens the same form.
    private var proposalList: some View {
        PatchProposalList(quilt: quilt, slug: patch.slug, rules: overview?.rules, seats: overview?.seats ?? [],
                          nextContestOpens: overview?.nextContestOpens, close: close) { stale = true }
    }
    /// What an admin of the patch still does on the website: rare desk
    /// work, each a deliberate act on the whole patch's record.
    static let websiteNote = "Publishing a document or making it members only, recording a text a meeting adopted, and adding a council seat happen on this quilt’s website."
    /// "1 proposal needs your vote", "3 proposals need your vote".
    static func needsVoteLine(_ count: Int) -> String {
        count == 1 ? "1 proposal needs your vote" : "\(count) proposals need your vote"
    }
    private func candidateLine(_ election: GovernanceElection) -> String {
        var line = (election.candidates ?? 0) == 0 ? "Nobody has stood yet." : "\(election.candidates ?? 0) standing."
        if let closing = ProfileDate.day(election.nominationsCloseAt) { line += " Closing \(closing)." }
        return line
    }
    @ViewBuilder private func council(_ overview: GovernanceOverview) -> some View {
        let seats = overview.seats ?? []
        Section {
            if seats.isEmpty {
                Text("This council has no seats yet. Until a seat exists there is nothing to elect and nothing to nominate anyone into.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(seatSummary(seats)).fixedSize(horizontal: false, vertical: true)
                ForEach(seats) { seat in
                    let chair = VStack(alignment: .leading, spacing: 3) {
                        Text(seat.holder).foregroundStyle(seat.isVacant ? Color.pwTextMuted : Color.pwText)
                        Text(seat.fate).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(.vertical, 2)
                    // A held chair opens its holder. A vacant one has nobody
                    // in it, and a withheld one is held by somebody this
                    // reader is not shown — so neither is a door.
                    if !seat.isVacant, seat.holderWithheld != true, let handle = People.door(seat.username) {
                        NavigationLink { PersonProfile(quilt: quilt, username: handle, close: close) } label: { chair }
                            .accessibilityIdentifier("councilSeat")
                    } else {
                        chair
                    }
                }
            }
        } header: { Text("The council") } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let ends = ProfileDate.day(overview.nextTermEnd) { Text("Next term ends \(ends).") }
                if let opens = ProfileDate.day(overview.nextContestOpens) { Text("Next contest opens \(opens).") }
            }
        }
    }
    private func seatSummary(_ seats: [GovernanceSeat]) -> String {
        let vacant = seats.filter(\.isVacant).count
        let held = seats.count - vacant
        let seatWord = seats.count == 1 ? "seat" : "seats"
        if vacant == 0 { return "\(seats.count) \(seatWord) on the council, all held." }
        return "\(seats.count) \(seatWord) on the council, \(held) held and \(vacant) vacant."
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { overview = try await api.get("nodes/\(patch.slug)/governance/overview") }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

/// The documents a patch has published (web ADR 036). A listing that held
/// only published documents says so, so an empty one can tell "this patch has
/// published nothing" from "you are not being shown what it has" — without
/// disclosing whether anything is being withheld.
///
/// Every published document is listed here, the lining included, even where
/// it is still the shared baseline: this is the room, and the count the door
/// wears is the server's. Only the profile's *glimpse* drops a pristine
/// lining, because a row that is byte-identical on every patch on the quilt
/// says nothing in a preview.
///
/// A patch's admin writes a new document from the bar at the foot, as the
/// web's New Document button; it opens on its own screen once saved.
struct GovernanceDocumentList: View {
    @EnvironmentObject private var session: QuiltSession
    let quilt: Quilt
    let slug: String
    var close: (() -> Void)? = nil
    @State private var documents: [GovernanceDocument] = []
    @State private var writing = false
    @State private var made: GovernanceDocument?
    @State private var opened: GovernanceDocument?
    private var mayCreate: Bool {
        NewDocument.mayCreate(signedIn: quilt.url == session.quilt.url && session.me != nil, standing: session.standing(for: slug))
    }
    @State private var publishedOnly = false
    @State private var loading = true
    @State private var loaded = false
    @State private var error: String?
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    var body: some View {
        List {
            // One Group so every section's rows take the card surface: the
            // modifier does not reach them from the List itself.
            Group {
            ForEach(documents) { document in
                NavigationLink { GovernanceDocumentDetail(quilt: quilt, initial: document, close: close) { Task { await load() } } } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title).font(Font.pw.headline).foregroundStyle(Color.pwText)
                        HStack(spacing: 8) {
                            if let version = document.version { Text("v\(version)") }
                            if let updated = ProfileDate.day(document.updatedAt) { Text("Updated \(updated)") }
                            if document.kind == "lining" { Text("The lining") }
                            else if document.visibility == "members" { Text("Members only") }
                        }.font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    }.padding(.vertical, 4)
                }.accessibilityIdentifier("documentRow")
            }
            if loading { ProgressView("Loading documents…") }
            if let error {
                Section {
                    Text(error).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    Button("Try again") { Task { await load() } }
                        .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
                }
            }
            if publishedOnly && !documents.isEmpty {
                Section { Text("Members-only documents are not listed here.").font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted) }
            }
            }.listRows()
        }
        .groundedList()
        .navigationTitle("Documents").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mayCreate {
                ToolbarItem(placement: .bottomBar) {
                    ProposalDoorButton(label: "New document") { writing = true }
                        .accessibilityIdentifier("newDocumentDoor")
                }
            }
            if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
        }
        .sheet(isPresented: $writing, onDismiss: { if let made { opened = made; self.made = nil } }) {
            NewDocumentSheet(slug: slug) { document in
                made = document
                Task { await load() }
            }
        }
        .navigationDestination(item: $opened) { GovernanceDocumentDetail(quilt: quilt, initial: $0, close: close) { Task { await load() } } }
        .overlay {
            if loaded && !loading && error == nil && documents.isEmpty {
                ContentUnavailableView(
                    publishedOnly ? "Nothing published yet" : "No governance documents yet",
                    systemImage: "doc.text",
                    description: Text(publishedOnly
                        ? "Members-only documents are not listed here."
                        : "This patch has not written any governance documents.")
                )
            }
        }
        .task { if !loaded { await load() } }
        .refreshable { await load() }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false; loaded = true }
        do {
            let page: GovernanceDocumentPage = try await api.get("nodes/\(slug)/governance")
            publishedOnly = page.publishedOnly ?? false
            documents = page.items ?? []
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

/// One document, its history, and — for a member or an admin — the door to
/// changing it (`DocumentAmendmentSheet`). The door waits for the patch's
/// rules, because they decide what the change will be, and is worded as
/// the outcome: an admin of a patch whose admins decide changes it, anybody
/// else proposes a change.
struct GovernanceDocumentDetail: View {
    @EnvironmentObject private var session: QuiltSession
    let quilt: Quilt
    let initial: GovernanceDocument
    var close: (() -> Void)? = nil
    /// The rooms behind this screen are out of date: a change was made.
    var changed: () -> Void = {}
    @State private var detail: GovernanceDocument?
    @State private var error: String?
    @State private var rules: GovernanceRules?
    @State private var amending = false
    @State private var made: Proposal?
    @State private var opened: Proposal?
    private var document: GovernanceDocument { detail ?? initial }
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    private var signedIn: Bool { quilt.url == session.quilt.url && session.me != nil }
    /// The patch, by the document's own `node_id`: a document is opened from
    /// a room, a glimpse and a notification alike, and only the payload
    /// names its patch on all three.
    private var slug: String? {
        guard let node = document.nodeId, !node.isEmpty else { return nil }
        if let slug = session.memberships.first(where: { $0.nodeId == node })?.nodeSlug, !slug.isEmpty { return slug }
        return (session.wholeQuilt + session.patches).first { $0.id == node }?.slug
    }
    private var standing: Standing? { slug.flatMap { session.standing(for: $0) } }
    private var door: String? {
        guard detail != nil else { return nil }
        return DocumentAmending.door(signedIn: signedIn, standing: standing, rules: rules)
    }
    var body: some View {
        List {
            // One Group so every section's rows take the card surface: the
            // modifier does not reach them from the List itself.
            Group {
            Section {
                Text(document.title).font(Font.pw.title2).foregroundStyle(Color.pwText).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if let version = document.version { Text("v\(version)") }
                    if let updated = ProfileDate.day(document.updatedAt) { Text("Updated \(updated)") }
                    if document.visibility == "members", document.kind != "lining" { Text("Members only") }
                }.font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                if document.kind == "lining" {
                    Text("The shared baseline every patch on this quilt starts with.")
                        .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                }
                NavigationLink {
                    GovernanceVersionHistory(quilt: quilt, document: document, close: close)
                } label: {
                    Label(DocumentHistory.doorLabel(document.version), systemImage: "clock.arrow.circlepath")
                        .font(Font.pw.subheadline)
                }
                .accessibilityIdentifier("documentHistory")
            }
            if let body = document.body, !body.isEmpty {
                Section { DocumentBody(text: body) }
            } else if error == nil {
                Section { ProgressView("Loading document…") }
            }
            if let error {
                Section {
                    Text(error).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    Button("Try again") { Task { await load() } }
                        .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
                }
            }
            }.listRows()
        }
        .groundedList()
        .navigationTitle("Document").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let door {
                ToolbarItem(placement: .bottomBar) {
                    ProposalDoorButton(label: door) { amending = true }
                        .accessibilityIdentifier("documentChangeDoor")
                }
            }
            if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
        }
        .sheet(isPresented: $amending, onDismiss: { if let made { opened = made; self.made = nil } }) {
            if let slug {
                DocumentAmendmentSheet(slug: slug, document: document, rules: rules,
                                       isPatchAdmin: standing == .active(.admin)) { proposal in
                    made = proposal
                    changed()
                    // A direct change has already rewritten the document.
                    Task { await load() }
                }
            }
        }
        .navigationDestination(item: $opened) { ProposalDetailView(quilt: quilt, initial: $0, close: close) { changed(); Task { await load() } } }
        .task { await load() }
    }
    private func load() async {
        error = nil
        do { detail = try await api.get("governance/\(initial.id)") }
        catch { if !Task.isCancelled && (initial.body ?? "").isEmpty { self.error = error.localizedDescription } }
        await loadRules()
    }
    /// The overview's rules, asked for only where the door could be drawn.
    private func loadRules() async {
        guard signedIn, let slug, ProposalPosting.mayPropose(signedIn: signedIn, standing: standing) else { return }
        if let overview: GovernanceOverview = try? await api.get("nodes/\(slug)/governance/overview") { rules = overview.rules }
    }
}

/// What a patch has proposed, filtered by outcome rather than by the status
/// column: a lapse and an unsettled contest both carry the schema's
/// `rejected`, so "Not decided" is the drawer they belong in (web ADR 097).
struct PatchProposalList: View {
    @EnvironmentObject private var session: QuiltSession
    let quilt: Quilt
    let slug: String
    /// The patch's rules, from the governance overview: what the door's
    /// form will be. Without them there is no door.
    var rules: GovernanceRules? = nil
    var seats: [GovernanceSeat] = []
    var nextContestOpens: String? = nil
    var close: (() -> Void)? = nil
    /// Something here changed: whoever counts these is out of date.
    var changed: () -> Void = {}
    @State private var proposals: [Proposal] = []
    @State private var composing = false
    @State private var made: Proposal?
    @State private var opened: Proposal?
    @State private var stale = false
    @State private var filter = "open"
    @State private var loading = true
    @State private var loaded = false
    @State private var withheld = false
    @State private var error: String?
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    private var signedIn: Bool { quilt.url == session.quilt.url && session.me != nil }
    private var standing: Standing? { session.standing(for: slug) }
    private var door: String? { ProposalPosting.door(signedIn: signedIn, standing: standing, rules: rules) }
    static let filters: [(value: String, label: String)] = [
        ("open", "Open"), ("approved", "Approved"), ("rejected", "Rejected"),
        ("not_decided", "Not decided"), ("all", "All"),
    ]
    var body: some View {
        List {
            // One Group so every section's rows take the card surface: the
            // modifier does not reach them from the List itself.
            Group {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Self.filters, id: \.value) { Text($0.label).tag($0.value) }
                }.pickerStyle(.menu)
            }
            ForEach(proposals) { proposal in
                NavigationLink { ProposalDetailView(quilt: quilt, initial: proposal, close: close) { stale = true; changed() } } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(proposal.title).font(Font.pw.headline).foregroundStyle(Color.pwText)
                        HStack(spacing: 8) {
                            if let author = proposal.authorName, !author.isEmpty {
                                Text("\(proposal.isDirectChange ? "applied by" : "by") \(author)")
                            }
                            if let created = ProfileDate.day(proposal.createdAt) { Text(created) }
                        }.font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                        HStack(spacing: 8) {
                            OutcomeBadge(proposal: proposal)
                            if let line = Self.rowLine(proposal) {
                                Text(line).font(Font.pw.captionSemibold).foregroundStyle(Color.pwTextMuted)
                                    .accessibilityIdentifier("proposalTimeLeft")
                            }
                        }
                        if (proposal.approveCount ?? 0) + (proposal.rejectCount ?? 0) > 0 {
                            MiniTally(approve: proposal.approveCount ?? 0, reject: proposal.rejectCount ?? 0)
                        }
                    }.padding(.vertical, 4)
                }.accessibilityIdentifier("proposalRow")
            }
            if loading { ProgressView("Loading proposals…") }
            if let error {
                Section {
                    Text(error).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    Button("Try again") { Task { await load() } }
                        .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
                }
            }
            // Where a member finds the door, a follower is told what opens
            // it (web `ProposalList`); joining lives on the profile.
            if signedIn && standing == .active(.follower) && !withheld {
                Section {
                    Text(ProposalPosting.followerLine)
                        .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                        .accessibilityIdentifier("proposalFollowerLine")
                }
            }
            }.listRows()
        }
        .groundedList()
        .navigationTitle("Proposals").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let door, !withheld {
                ToolbarItem(placement: .bottomBar) { ProposalDoorButton(label: door) { composing = true } }
            }
            if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
        }
        .sheet(isPresented: $composing, onDismiss: { if let made { opened = made; self.made = nil } }) {
            ProposalFormSheet(slug: slug, rules: rules, seats: seats, nextContestOpens: nextContestOpens,
                              isPatchAdmin: standing == .active(.admin)) { proposal in
                made = proposal
                changed()
                // Open is where a new proposal is, unless it was applied.
                Task { await load() }
            }
        }
        .navigationDestination(item: $opened) { ProposalDetailView(quilt: quilt, initial: $0, close: close) { stale = true; changed() } }
        .onAppear { if stale { stale = false; Task { await load() } } }
        .overlay {
            if loaded && !loading && error == nil && proposals.isEmpty {
                ContentUnavailableView(
                    withheld ? "Not public" : "Nothing here",
                    systemImage: withheld ? "lock" : "checkmark.bubble",
                    description: Text(emptyMessage)
                )
            }
        }
        .onChange(of: filter) { _, _ in Task { await load() } }
        .task { if !loaded { await load() } }
        .refreshable { await load() }
    }
    /// What a row says about where the proposal is (web `ProposalList`):
    /// what it waits for, the time it has left, or the word for how it
    /// ended. An open proposal with no clock and a direct change say
    /// nothing more.
    static func rowLine(_ proposal: Proposal, now: Date = Date()) -> String? {
        if proposal.state == "awaiting_admin" { return "waiting on the maintainer" }
        if proposal.status == "open" {
            return VoteRules.timeLeftRow(VoteRules.timeLeft(proposal.votingEndsAt, now: now))
        }
        if proposal.isDirectChange { return nil }
        return proposal.outcome.isEmpty ? nil : proposal.outcome
    }
    private var emptyMessage: String {
        if withheld { return "Proposals and decisions here are not public." }
        switch filter {
        case "not_decided": return "Nothing here has lapsed or settled nothing."
        case "all": return "This patch has raised no proposals."
        default:
            let label = Self.filters.first { $0.value == filter }?.label.lowercased() ?? filter
            return "No \(label) proposals."
        }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false; loaded = true }
        do {
            var query: [URLQueryItem] = []
            if filter != "all" { query.append(URLQueryItem(name: "status", value: filter)) }
            let page: ProposalPage = try await api.get("nodes/\(slug)/proposals", query: query)
            withheld = page.publicGovernanceRecord == "nobody"
            proposals = page.items ?? []
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

/// A row's approve-against-reject bar, the web list's `vote-bar`, with the
/// two counts under it. Abstentions are not in it: a row asks which way it
/// is leaning.
struct MiniTally: View {
    let approve: Int
    let reject: Int
    var body: some View {
        let share = Double(approve) / Double(max(1, approve + reject))
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.red.opacity(0.75))
                    Capsule().fill(Color.green).frame(width: geometry.size.width * share)
                }
            }
            .frame(width: 120, height: 5)
            HStack {
                Text("\(approve)")
                Spacer()
                Text("\(reject)")
            }
            .frame(width: 120)
            .font(Font.pw.caption2Semibold).foregroundStyle(Color.pwTextMuted)
        }
        .accessibilityElement()
        .accessibilityLabel("\(approve) approve, \(reject) reject")
    }
}

/// Every decision this patch has reached, and every one it failed to, newest
/// first (web ADR 055). Only settled things appear: an open proposal is an
/// argument in progress, and putting it here would make the record a to-do
/// list.
struct GovernanceRecordList: View {
    let quilt: Quilt
    let slug: String
    var close: (() -> Void)? = nil
    @State private var entries: [GovernanceRecordEntry] = []
    @State private var withheld = false
    @State private var loading = true
    @State private var loaded = false
    @State private var error: String?
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    var body: some View {
        List {
            // One Group so every section's rows take the card surface: the
            // modifier does not reach them from the List itself.
            Group {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.kindLabel).font(Font.pw.captionSemibold).foregroundStyle(Color.pwTextMuted)
                        Spacer()
                        if let day = ProfileDate.day(entry.at) { Text(day).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted) }
                    }
                    Text(entry.title).font(Font.pw.headline).foregroundStyle(Color.pwText).fixedSize(horizontal: false, vertical: true)
                    Text(entry.outcomeLine).font(Font.pw.subheadline)
                        .foregroundStyle(entry.settled ? Color.pwText : Color.pwTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let summary = entry.summary, !summary.isEmpty {
                        Text(summary).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("recordRow")
            }
            if loading { ProgressView("Loading the record…") }
            if let error {
                Section {
                    Text(error).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    Button("Try again") { Task { await load() } }
                        .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
                }
            }
            }.listRows()
        }
        .groundedList()
        .navigationTitle("Record").navigationBarTitleDisplayMode(.inline)
        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
        .overlay {
            if loaded && !loading && error == nil && entries.isEmpty {
                ContentUnavailableView(
                    withheld ? "Not public" : "Nothing settled yet",
                    systemImage: withheld ? "lock" : "clock.arrow.circlepath",
                    description: Text(withheld
                        ? "Proposals and decisions here are not public."
                        : "Proposals show up here once they close.")
                )
            }
        }
        .task { if !loaded { await load() } }
        .refreshable { await load() }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false; loaded = true }
        do {
            let page: GovernanceRecordPage = try await api.get("nodes/\(slug)/governance/record")
            withheld = page.publicGovernanceRecord == "nobody"
            entries = page.items ?? []
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
