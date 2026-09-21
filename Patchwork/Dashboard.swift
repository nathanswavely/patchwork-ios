// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// The tab that only exists once there is an account to dash. It is the
/// reader's own patches, in the web's order — what needs them, what they run,
/// what they belong to, what they follow, and what they have asked for and
/// not been answered about.
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
    @State private var proposals: [String: Badge] = [:]
    @State private var loaded = false

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
                if !events.isEmpty { attention }
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
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: Attention needed

    /// What is about to happen on the patches this reader is in. It leads
    /// because it is the only thing here with a clock on it.
    private var attention: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Attention needed")
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
                    .accessibilityIdentifier("dashboardEvent")
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
                    .accessibilityIdentifier("dashboardAllEvents")
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
        let slug = row.slug
        let pending = requests[slug] ?? 0
        let open = proposals[slug]
        if pending > 0 || (open?.count ?? 0) > 0 {
            HStack(spacing: 6) {
                if pending > 0 { badge("\(pending) to approve", symbol: "person.crop.circle.badge.questionmark") }
                if let open, open.count > 0 { badge("\(open.label) open", symbol: "checklist") }
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
        var open: [String: Badge] = [:]
        for row in rows.managing + rows.member {
            let query = [URLQueryItem(name: "status", value: "open"), URLQueryItem(name: "limit", value: "20")]
            if let page: ProposalPage = try? await session.api.get("nodes/\(row.slug)/proposals", query: query) {
                let items = page.items ?? []
                if !items.isEmpty {
                    open[row.slug] = Badge(count: items.count, more: page.nextCursor?.isEmpty == false)
                }
            }
        }
        proposals = open
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
