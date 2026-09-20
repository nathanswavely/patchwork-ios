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
/// Nothing here votes, proposes, stands or claims. Those need an account,
/// this client has none, and a disabled button pretending otherwise would be
/// the one thing the profile must not do.
struct PatchGovernanceHome: View {
    let quilt: Quilt
    let patch: Patch
    var close: (() -> Void)? = nil
    @State private var overview: GovernanceOverview?
    @State private var loading = true
    @State private var error: String?
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    /// The patch's own setting decides for a signed-out reader; the server
    /// states the same fact back on the overview, and either is enough.
    private var recordWithheld: Bool {
        patch.publicGovernanceRecord == "nobody" || overview?.proposalsWithheld == true
    }
    var body: some View {
        List {
            if let overview {
                if let election = overview.election, election.phase == "nominating" {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nominations are open for \(election.seats ?? 0) seat\((election.seats ?? 0) == 1 ? "" : "s")")
                                .font(Font.pw.headline)
                            Text(candidateLine(election)).font(Font.pw.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 2)
                    }
                }
                if !overview.decisionNarrative.isEmpty {
                    Section("How decisions are made") {
                        Text(overview.decisionNarrative).fixedSize(horizontal: false, vertical: true)
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
                            .foregroundStyle(.secondary)
                    } else if let admins = overview.admins, !admins.isEmpty {
                        ForEach(admins) { admin in
                            PersonRow(
                                name: admin.name, initial: admin.initial, avatar: admin.avatar,
                                detail: ProfileDate.monthYear(admin.joinedAt).map { "Member since \($0)" }
                            )
                        }
                    } else {
                        Text("Nobody holds the admin role here yet.").foregroundStyle(.secondary)
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
                            .font(Font.pw.subheadline).foregroundStyle(.secondary)
                    } else {
                        NavigationLink {
                            PatchProposalList(quilt: quilt, slug: patch.slug, close: close)
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
                    Text(error).foregroundStyle(.secondary)
                    Button("Try again") { Task { await load() } }
                }
            }
            Section {
                WebsiteOnlyNote(text: "Proposing, voting, and standing for a seat happen on this quilt’s website.")
            }
        }
        .navigationTitle("Governance").navigationBarTitleDisplayMode(.inline)
        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
        .task { if overview == nil { await load() } }
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text(seat.holder).foregroundStyle(seat.isVacant ? Color.secondary : Color.primary)
                        Text(seat.fate).font(Font.pw.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(.vertical, 2)
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
struct GovernanceDocumentList: View {
    let quilt: Quilt
    let slug: String
    var close: (() -> Void)? = nil
    @State private var documents: [GovernanceDocument] = []
    @State private var publishedOnly = false
    @State private var loading = true
    @State private var loaded = false
    @State private var error: String?
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    var body: some View {
        List {
            ForEach(documents) { document in
                NavigationLink { GovernanceDocumentDetail(quilt: quilt, initial: document, close: close) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title).font(Font.pw.headline)
                        HStack(spacing: 8) {
                            if let version = document.version { Text("v\(version)") }
                            if let updated = ProfileDate.day(document.updatedAt) { Text("Updated \(updated)") }
                            if document.kind == "lining" { Text("The lining") }
                        }.font(Font.pw.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }.accessibilityIdentifier("documentRow")
            }
            if loading { ProgressView("Loading documents…") }
            if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Try again") { Task { await load() } }
                }
            }
            if publishedOnly && !documents.isEmpty {
                Section { Text("Members-only documents are not listed here.").font(Font.pw.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Documents").navigationBarTitleDisplayMode(.inline)
        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
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

struct GovernanceDocumentDetail: View {
    let quilt: Quilt
    let initial: GovernanceDocument
    var close: (() -> Void)? = nil
    @State private var detail: GovernanceDocument?
    @State private var error: String?
    private var document: GovernanceDocument { detail ?? initial }
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    var body: some View {
        List {
            Section {
                Text(document.title).font(Font.pw.title2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if let version = document.version { Text("v\(version)") }
                    if let updated = ProfileDate.day(document.updatedAt) { Text("Updated \(updated)") }
                }.font(Font.pw.caption).foregroundStyle(.secondary)
                if document.kind == "lining" {
                    Text("The shared baseline every patch on this quilt starts with.")
                        .font(Font.pw.footnote).foregroundStyle(.secondary)
                }
            }
            if let body = document.body, !body.isEmpty {
                Section { DocumentBody(text: body) }
            } else if error == nil {
                Section { ProgressView("Loading document…") }
            }
            if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Try again") { Task { await load() } }
                }
            }
        }
        .navigationTitle("Document").navigationBarTitleDisplayMode(.inline)
        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
        .task { await load() }
    }
    private func load() async {
        error = nil
        do { detail = try await api.get("governance/\(initial.id)") }
        catch { if !Task.isCancelled && (initial.body ?? "").isEmpty { self.error = error.localizedDescription } }
    }
}

/// What a patch has proposed, filtered by outcome rather than by the status
/// column: a lapse and an unsettled contest both carry the schema's
/// `rejected`, so "Not decided" is the drawer they belong in (web ADR 097).
struct PatchProposalList: View {
    let quilt: Quilt
    let slug: String
    var close: (() -> Void)? = nil
    @State private var proposals: [Proposal] = []
    @State private var filter = "open"
    @State private var loading = true
    @State private var loaded = false
    @State private var withheld = false
    @State private var error: String?
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    static let filters: [(value: String, label: String)] = [
        ("open", "Open"), ("approved", "Approved"), ("rejected", "Rejected"),
        ("not_decided", "Not decided"), ("all", "All"),
    ]
    var body: some View {
        List {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Self.filters, id: \.value) { Text($0.label).tag($0.value) }
                }.pickerStyle(.menu)
            }
            ForEach(proposals) { proposal in
                NavigationLink { ProposalDetailView(quilt: quilt, initial: proposal, close: close) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(proposal.title).font(Font.pw.headline)
                        HStack(spacing: 8) {
                            if let author = proposal.authorName, !author.isEmpty {
                                Text("\(proposal.isDirectChange ? "applied by" : "by") \(author)")
                            }
                            if let created = ProfileDate.day(proposal.createdAt) { Text(created) }
                        }.font(Font.pw.caption).foregroundStyle(.secondary)
                        OutcomeBadge(proposal: proposal)
                    }.padding(.vertical, 4)
                }.accessibilityIdentifier("proposalRow")
            }
            if loading { ProgressView("Loading proposals…") }
            if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Try again") { Task { await load() } }
                }
            }
        }
        .navigationTitle("Proposals").navigationBarTitleDisplayMode(.inline)
        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
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

struct ProposalDetailView: View {
    let quilt: Quilt
    let initial: Proposal
    var close: (() -> Void)? = nil
    @State private var detail: Proposal?
    @State private var error: String?
    private var proposal: Proposal { detail ?? initial }
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    var body: some View {
        List {
            Section {
                Text(proposal.title).font(Font.pw.title2).fixedSize(horizontal: false, vertical: true)
                OutcomeBadge(proposal: proposal)
                if let author = proposal.authorName, !author.isEmpty {
                    Text("\(proposal.isDirectChange ? "Applied by" : "Proposed by") \(author)")
                        .font(Font.pw.subheadline).foregroundStyle(.secondary)
                }
                if let created = ProfileDate.day(proposal.createdAt) {
                    Text(created).font(Font.pw.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                if let target = proposal.targetDoc, !target.isEmpty {
                    Label("\(proposal.isDirectChange ? "Change" : "Amendment") to \(target)", systemImage: "doc.text")
                }
                if let type = proposal.proposalType, !type.isEmpty, type != "other" {
                    Label(type.capitalized, systemImage: "tag")
                }
                if proposal.outcomeIsOpen, let ends = ProfileDate.day(proposal.votingEndsAt) {
                    Label("Voting ends \(ends)", systemImage: "clock")
                }
                if proposal.ballots > 0 {
                    Label("\(proposal.approveCount ?? 0) for · \(proposal.rejectCount ?? 0) against", systemImage: "chart.bar")
                }
            }
            if let body = proposal.body, !body.isEmpty {
                Section("What it proposes") { DocumentBody(text: body) }
            }
            if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Try again") { Task { await load() } }
                }
            }
            Section {
                WebsiteOnlyNote(text: "Voting and commenting on a proposal happen on this quilt’s website.")
            }
        }
        .navigationTitle("Proposal").navigationBarTitleDisplayMode(.inline)
        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
        .task { await load() }
    }
    private func load() async {
        error = nil
        do { detail = try await api.get("proposals/\(initial.id)") }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
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
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.kindLabel).font(Font.pw.captionSemibold).foregroundStyle(.secondary)
                        Spacer()
                        if let day = ProfileDate.day(entry.at) { Text(day).font(Font.pw.caption).foregroundStyle(.secondary) }
                    }
                    Text(entry.title).font(Font.pw.headline).fixedSize(horizontal: false, vertical: true)
                    Text(entry.outcomeLine).font(Font.pw.subheadline)
                        .foregroundStyle(entry.settled ? Color.primary : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let summary = entry.summary, !summary.isEmpty {
                        Text(summary).font(Font.pw.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("recordRow")
            }
            if loading { ProgressView("Loading the record…") }
            if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Try again") { Task { await load() } }
                }
            }
        }
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
