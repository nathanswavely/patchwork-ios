// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// The tab that only exists once there is an account to dash. It is the
/// reader's own patches, in the web's order — what needs them, what is coming
/// up, what they run, what they belong to, what they follow, and what they
/// have asked for and not been answered about.
///
/// "Attention needed" is the web's summary of what is asked of the reader
/// (`Dashboard.svelte`): requests to join and suggested events on the
/// patches they run, and proposals waiting on their vote — each a door to
/// where it is answered, and the section is drawn only when one exists. The
/// web folds a count of upcoming events into the same summary; here they are
/// a section of their own under it, because a concert is not a task.
///
/// Everything on it is cards on the app's ground, not a settings list: these
/// are patches, and a patch is the one thing in this app that is a card.
struct Dashboard: View {
    @EnvironmentObject private var session: QuiltSession
    /// The door out of the empty state, which belongs to the shell.
    var openDiscover: () -> Void = {}

    @State private var events: [PatchworkEvent] = []
    @State private var moreEvents = false
    @State private var requests: [String: Int] = [:]
    /// Suggested events waiting on a patch the reader runs. The web's
    /// Dashboard does not count these; the list is unpaged, so it costs one
    /// read, and somebody is waiting on the answer.
    @State private var suggested: [String: Int] = [:]
    @State private var proposals: [String: Badge] = [:]
    /// Open proposals on each patch that still wait on this reader's ballot
    /// — the server's `awaiting_your_vote`, the same count the governance
    /// room says "needs your vote" about.
    @State private var votes: [String: Int] = [:]
    @State private var loaded = false
    /// The Dashboard's own door to the sheet the bell opens. Its own state
    /// rather than the session's, because the discovery toolbar is on four
    /// surfaces at once and one shared flag would ask all four to present it.
    @State private var notifications = false

    /// An open-proposal count that may be a floor rather than a total.
    struct Badge: Equatable {
        var count: Int
        var more: Bool
        var label: String { DashboardGrouping.countLabel(count: count, more: more) }
    }

    private var sections: DashboardGrouping.Sections { DashboardGrouping.group(session.memberships) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let me = session.me {
                    Text("Welcome back, \(me.title).")
                        .font(Font.pw.displayTitle2)
                        .foregroundStyle(Color.pwText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("dashboardWelcome")
                }
                // What is waiting to be read leads everything, because it is
                // the one thing on this screen somebody is being asked about.
                if session.unread > 0 { unreadRow }
                if !asks.isEmpty { attention }
                if !events.isEmpty { upcoming }
                if sections.isEmpty {
                    if loaded { empty } else { ProgressView().frame(maxWidth: .infinity).padding(.top, 24) }
                } else {
                    group("Managing", rows: sections.managing)
                    group("Member of", rows: sections.member)
                    group("Following", rows: sections.following)
                    group("Requested", rows: sections.requested)
                }
                QuiltInfoFooter().padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.pwGround.ignoresSafeArea())
        .navigationTitle("Dashboard").navigationBarTitleDisplayMode(.inline)
        .modifier(DiscoveryToolbar())
        .sheet(isPresented: $notifications, onDismiss: { session.sheetDismissed() }) { NotificationsSheet() }
        .refreshable { await load() }
        .task { await load() }
        // An event edited or deleted from a page pushed over this one.
        .onChange(of: session.eventRevision) { _, _ in Task { await load() } }
        // A request answered or a suggestion reviewed from a queue pushed
        // over this one: the counts beside the patch are the quilt's again.
        .onChange(of: session.adminRevision) { _, _ in Task { await load() } }
    }

    // MARK: What is unread

    /// One row, and only while there is something in it. The same sheet the
    /// bell opens: a reader who is already on the Dashboard should not have
    /// to go back up to the bar to read what it is telling them about.
    private var unreadRow: some View {
        Button { notifications = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "bell.fill").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
                    .accessibilityHidden(true)
                Text("\(session.unread) unread notification\(session.unread == 1 ? "" : "s")")
                    .font(Font.pw.subheadlineSemibold).inkRow()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.pwSurface)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.pwBorder, lineWidth: 1))
        .accessibilityIdentifier("dashboardUnread")
    }

    // MARK: Attention needed

    /// One thing somebody is waiting on the reader for, on one patch.
    struct Ask: Identifiable, Equatable {
        enum Kind: String { case requests, suggestions, votes }
        let kind: Kind
        let slug: String
        let name: String
        let count: Int
        var id: String { "\(kind.rawValue)-\(slug)" }
        var label: String {
            switch kind {
            case .requests: return PatchAdmin.requestsLabel(count)
            case .suggestions: return PatchAdmin.suggestionsLabel(count)
            case .votes: return PatchGovernanceHome.needsVoteLine(count)
            }
        }
        var symbol: String {
            switch kind {
            case .requests: return "person.crop.circle.badge.questionmark"
            case .suggestions: return "calendar.badge.exclamationmark"
            case .votes: return "checkmark.circle"
            }
        }
    }

    /// The asks in the web's order — requests, then votes — with the
    /// suggestions between them, beside the requests they are kin to; each
    /// kind A to Z by patch, as the groups below read.
    private var asks: [Ask] {
        let rows = sections.managing + sections.member
        func asks(_ kind: Ask.Kind, _ counts: [String: Int], in rows: [Membership]) -> [Ask] {
            rows.compactMap { row in
                guard let count = counts[row.slug], count > 0 else { return nil }
                return Ask(kind: kind, slug: row.slug, name: row.name, count: count)
            }
        }
        return asks(.requests, requests, in: sections.managing)
            + asks(.suggestions, suggested, in: sections.managing)
            + asks(.votes, votes, in: rows)
    }

    private var attention: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Attention needed")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(asks) { ask in
                    NavigationLink { destination(ask) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: ask.symbol).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
                                .frame(width: 20).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ask.label).font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwText)
                                Text(ask.name).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                            }
                            .inkRow()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("dashboard\(ask.kind.rawValue.capitalized)-\(ask.slug)")
                    if ask.id != asks.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 12)
            .background(Color.pwSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.pwBorder, lineWidth: 1))
        }
    }

    /// Each ask opens where it is answered: the queue, or the patch's
    /// governance room, where the open proposals are.
    @ViewBuilder private func destination(_ ask: Ask) -> some View {
        switch ask.kind {
        case .requests: JoinRequestsView(slug: ask.slug)
        case .suggestions: SuggestedEventsView(slug: ask.slug)
        case .votes: GovernanceBySlug(slug: ask.slug)
        }
    }

    // MARK: Coming up

    /// What is about to happen on the patches this reader is in: a list to
    /// read, not a list of tasks, so it carries no urgency and comes after
    /// what does.
    private var upcoming: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Upcoming events on your patches")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(events.prefix(3)) { event in
                    NavigationLink { EventDetail(quilt: session.quilt, initial: event) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.shortDateLabel).font(Font.pw.captionSemibold).foregroundStyle(Color.pwTextMuted)
                            Text(event.title).font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwText)
                                .fixedSize(horizontal: false, vertical: true)
                            if let name = event.nodeName, !name.isEmpty {
                                Text(name).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dashboardUpcoming")
                    if event.id != events.prefix(3).last?.id { Divider() }
                }
                if events.count > 3 {
                    Divider()
                    NavigationLink {
                        DashboardEvents(events: events, more: moreEvents)
                    } label: {
                        Text("See all \(events.count)\(moreEvents ? "+" : "")").font(Font.pw.subheadline).inkRow()
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("dashboardAllUpcoming")
                }
            }
            .padding(.horizontal, 12)
            .background(Color.pwSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.pwBorder, lineWidth: 1))
        }
    }

    // MARK: The four groups

    @ViewBuilder private func group(_ title: String, rows: [Membership]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                heading(title)
                ForEach(rows) { row in
                    // The exit sits beside the card rather than inside it: a
                    // card is one door, and a second control within it would
                    // be a button inside a button.
                    VStack(alignment: .leading, spacing: 6) {
                        patchRow(row)
                        if row.standing == .pending {
                            Button { Task { _ = try? await session.withdraw(row.slug) } } label: {
                                Text("Withdraw request").font(Font.pw.subheadline)
                            }
                            .buttonStyle(.plain)
                            .inkAction("arrow.uturn.backward")
                            .accessibilityIdentifier("dashboardWithdraw-\(row.slug)")
                        }
                    }
                }
            }
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(Font.pw.headline)
            .foregroundStyle(Color.pwText)
            .accessibilityIdentifier("dashboardSection-\(title)")
    }

    /// One membership as a patch. The quilt's own tree is asked for the patch
    /// first, so the row wears the cloth the canvas draws; a patch the tree
    /// does not carry — a private one, or one on a quilt too big to hold —
    /// gets its name and its own description instead of an invented tile.
    @ViewBuilder private func patchRow(_ row: Membership) -> some View {
        let slug = row.slug
        if let patch = session.patches.first(where: { $0.slug == slug }) {
            CompactPatchCard(patch: patch,
                             tagMotifs: session.tagMotifs,
                             colorMode: session.colorMode,
                             identifier: "dashboardRow",
                             open: { Task { await session.open(slug: slug) } }) {
                badges(row)
            }
        } else {
            Button { Task { await session.open(slug: slug) } } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name).font(Font.pw.cardTitle).foregroundStyle(Color.pwText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let description = row.nodeDescription, !description.isEmpty {
                        Text(description).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted).lineLimit(2)
                    }
                    badges(row)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.pwSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.pwBorder, lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("dashboardRow")
        }
    }

    /// What this patch is waiting on the reader for. Words in ink, never a
    /// colour: the one tint means "you can press this", and a badge is a fact.
    @ViewBuilder private func badges(_ row: Membership) -> some View {
        if let open = proposals[row.slug], open.count > 0 {
            HStack(spacing: 6) {
                badge("\(open.label) open", symbol: "checklist")
            }
            .padding(.top, 2)
        }
    }

    private func badge(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(Font.pw.caption2Semibold)
            .foregroundStyle(Color.pwText)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(Color.pwBorder, lineWidth: 1))
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You haven’t joined any patches yet.")
                .font(Font.pw.title2).foregroundStyle(Color.pwText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Following a patch keeps its evenings in one place. Reading never needed an account; this is what one adds.")
                .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button { openDiscover() } label: {
                Text("Find patches to follow").font(Font.pw.subheadlineMedium)
            }
            .buttonStyle(.plain)
            .inkAction("safari")
            .accessibilityIdentifier("dashboardDiscover")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.pwSurface)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.pwBorder, lineWidth: 1))
    }

    // MARK: What it costs

    /// One read about the reader, then one small read per patch for each badge
    /// — every one of those best effort, because a badge that cannot be
    /// counted is a badge that is simply not drawn. Nothing here blocks the
    /// rows, which the membership index already has.
    private func load() async {
        await session.refreshMemberships()
        await session.refreshUnread()
        let page = try? await session.api.myEvents(from: Date())
        events = page?.items ?? []
        moreEvents = (page?.nextCursor?.isEmpty == false)
        let rows = DashboardGrouping.group(session.memberships)
        var pending: [String: Int] = [:]
        for row in rows.managing {
            let query = [URLQueryItem(name: "status", value: "pending"), URLQueryItem(name: "limit", value: "1")]
            if let members: MemberPage = try? await session.api.get("nodes/\(row.slug)/members", query: query),
               let count = members.memberCount, count > 0 {
                pending[row.slug] = count
            }
        }
        requests = pending
        var waiting: [String: Int] = [:]
        for row in rows.managing {
            if let items = try? await session.api.eventSubmissions(slug: row.slug), !items.isEmpty {
                waiting[row.slug] = items.count
            }
        }
        suggested = waiting
        var open: [String: Badge] = [:]
        var owed: [String: Int] = [:]
        for row in rows.managing + rows.member {
            let query = [URLQueryItem(name: "status", value: "open"), URLQueryItem(name: "limit", value: "20")]
            if let page: ProposalPage = try? await session.api.get("nodes/\(row.slug)/proposals", query: query) {
                let items = page.items ?? []
                if !items.isEmpty {
                    open[row.slug] = Badge(count: items.count, more: page.nextCursor?.isEmpty == false)
                }
                if let count = page.awaitingYourVote, count > 0 { owed[row.slug] = count }
            }
        }
        proposals = open
        votes = owed
        loaded = true
    }
}

/// The whole of `events?scope=my`, where three was not enough.
struct DashboardEvents: View {
    @EnvironmentObject private var session: QuiltSession
    let events: [PatchworkEvent]
    var more = false
    var body: some View {
        List {
            Group {
                Section {
                    ForEach(events) { event in
                        NavigationLink { EventDetail(quilt: session.quilt, initial: event) } label: { EventRow(event: event) }
                            .accessibilityIdentifier("eventRow")
                    }
                } footer: {
                    if more { Text("The next twenty. Older ones are on each patch’s own calendar.") }
                }
            }
            .listRows()
        }
        .groundedList()
        .navigationTitle("On your patches").navigationBarTitleDisplayMode(.inline)
    }
}

/// How the index is read as four lists, as a value: the grouping is the whole
/// of what the Dashboard decides, so it is checked without a window.
enum DashboardGrouping {
    struct Sections: Equatable {
        var managing: [Membership] = []
        var member: [Membership] = []
        var following: [Membership] = []
        var requested: [Membership] = []
        var isEmpty: Bool { managing.isEmpty && member.isEmpty && following.isEmpty && requested.isEmpty }
    }

    /// Active rows by the role they hold, pending rows on their own. A row
    /// that is neither active nor pending is not served and is not drawn.
    /// Each list reads A to Z, because a dashboard is a place to find a patch
    /// again rather than a feed.
    static func group(_ rows: [Membership]) -> Sections {
        var sections = Sections()
        for row in rows {
            switch row.standing {
            case .active(.admin): sections.managing.append(row)
            case .active(.member): sections.member.append(row)
            case .active(.follower): sections.following.append(row)
            case .pending: sections.requested.append(row)
            case nil: continue
            }
        }
        func byName(_ list: [Membership]) -> [Membership] {
            list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        sections.managing = byName(sections.managing)
        sections.member = byName(sections.member)
        sections.following = byName(sections.following)
        sections.requested = byName(sections.requested)
        return sections
    }

    /// A page of twenty with a cursor behind it is not twenty; it is at least
    /// twenty, and the badge says so rather than printing a number it would
    /// have to be wrong about.
    static func countLabel(count: Int, more: Bool) -> String { more ? "\(count)+" : String(count) }
}

/// A patch's governance room reached from somewhere that holds only its
/// slug — the Dashboard's ask for a vote. The tree is asked first, and
/// `nodes/{slug}` only for a patch it does not carry.
struct GovernanceBySlug: View {
    @EnvironmentObject private var session: QuiltSession
    let slug: String
    @State private var patch: Patch?
    @State private var failed = false
    var body: some View {
        Group {
            if let patch {
                PatchGovernanceHome(quilt: session.quilt, patch: patch)
            } else if failed {
                ContentUnavailableView("That could not be opened just now.", systemImage: "exclamationmark.circle")
            } else {
                ProgressView()
            }
        }
        .task {
            guard patch == nil else { return }
            if let known = session.patches.first(where: { $0.slug == slug }) ?? session.wholeQuilt.first(where: { $0.slug == slug }) {
                patch = known
            } else if let answer: PatchResponse = try? await session.api.get("nodes/\(slug)") {
                patch = answer.node
            } else {
                failed = true
            }
        }
    }
}
