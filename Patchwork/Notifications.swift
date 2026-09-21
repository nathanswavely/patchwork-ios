// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// The web's bell and its notifications page, native.
///
/// A notification follows an obligation rather than an event (web ADR 093):
/// the quilt only tells a reader about something it expects them to do
/// something about, which is why this is a short list with a badge rather
/// than a feed. Nothing here exists for a signed-out reader — the bell is not
/// drawn, the count is zero, and no authenticated read is made.
///
/// The file holds the whole slice: the row the server sends, the categories
/// the list can be narrowed by, the badge's arithmetic, the icon table, the
/// relative wording, where a link goes, and the sheet that draws all of it.
/// The first five are values with no window in them, so every decision the
/// list makes is checked in `PatchworkTests/NotificationsTests.swift` without
/// one.

// MARK: - What the server sends

/// One row of `GET notifications`. Named for the app rather than bare,
/// because `Notification` is Foundation's and a shadowed type in a SwiftUI
/// file is a trap laid for whoever reads it next — the same reason an event
/// is a `PatchworkEvent`.
struct PatchworkNotification: Decodable, Identifiable, Hashable {
    let id: String
    let userId: String?
    /// A dotted type — `proposal.voting_opened`, `event.reminder`. Only the
    /// prefix is read, and an unknown one is drawn rather than dropped.
    let type: String
    let title: String
    let body: String?
    /// A site-relative path the server chose (`internal/weblink`). It may be
    /// empty: an account warning has nowhere to send anybody.
    let link: String?
    /// Absent — not null — while the row is unread. That absence is the whole
    /// of what "unread" means in this contract.
    let readAt: String?
    let createdAt: String?

    var isUnread: Bool { (readAt ?? "").isEmpty }
    var target: String { (link ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    var symbol: String { NotificationIcon.symbol(for: type) }

    /// The same row, read. Marking read is a local fact the moment the server
    /// answers; the poll is only reconciliation.
    func read(at stamp: String) -> PatchworkNotification {
        PatchworkNotification(id: id, userId: userId, type: type, title: title, body: body,
                              link: link, readAt: stamp, createdAt: createdAt)
    }
}

struct NotificationPage: Decodable {
    let items: [PatchworkNotification]?
    let nextCursor: String?
}

/// `GET notifications/count`.
struct UnreadCount: Decodable { let unread: Int? }

// MARK: - The chips

/// The web's own filters, in the web's own order. `All` is the absence of the
/// parameter rather than a value of it, because the server rejects a category
/// it does not know rather than answering with an empty list — a mistyped
/// filter must not read as "you have nothing".
enum NotificationCategory: String, CaseIterable, Identifiable, Hashable {
    case all, proposals, governance, membership, events, moderation

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .proposals: return "Proposals"
        case .governance: return "Governance"
        case .membership: return "Membership"
        case .events: return "Events"
        case .moderation: return "Moderation"
        }
    }
    /// What rides the query, or nothing at all.
    var query: String? { self == .all ? nil : rawValue }
}

// MARK: - The badge's arithmetic

/// What the count does, as a value.
///
/// The web learned this the hard way (issue #55): a badge that only moved on
/// the sixty-second poll sat there after a notification had been read, which
/// reads as broken. So reading one is a local subtraction, clearing is a local
/// zero, and the poll only ever reconciles.
enum UnreadTally {
    /// The server's own number, which is the authority whenever it arrives.
    static func reconciled(_ served: Int) -> Int { max(0, served) }
    /// One row — or several — went from unread to read. Floors at zero: a
    /// client that has been counting down locally must not go negative when
    /// the server's number was already stale.
    static func read(_ current: Int, _ count: Int = 1) -> Int { max(0, current - count) }
    /// A dismissed row takes the badge with it only if it was unread. A read
    /// row never counted, so removing it must not move anything.
    static func dismissed(_ current: Int, wasUnread: Bool) -> Int { wasUnread ? read(current) : current }
    /// Mark-all-read and clear-all both empty the whole table server-side,
    /// not the page in view, so the count goes to zero rather than down by
    /// the number of rows currently drawn.
    static let cleared = 0
    /// What the bell wears. Three digits in a 16pt capsule is not a number
    /// anybody reads, so past ninety-nine it stops counting and says so.
    static func badge(_ count: Int) -> String { count > 99 ? "99+" : String(count) }
}

// MARK: - The icon table

/// The web's `NotifIcon` table, prefix for prefix, in SF Symbols.
///
/// Order matters the way it does there: the first prefix that matches wins,
/// and anything unmatched is a bell rather than nothing — a type this client
/// has never heard of is still a notification.
enum NotificationIcon {
    static let table: [(prefix: String, symbol: String)] = [
        ("proposal.", "doc.text"),
        ("governance.", "scroll"),
        ("membership.", "person.2"),
        ("event.", "mappin"),
        ("admin.", "wrench.and.screwdriver"),
        ("comment.", "bubble.left"),
        ("notice.", "bubble.left"),
        // Cross-quilt: a followed remote patch said something (web ADR 024).
        ("remote.", "heart"),
        // What a moderator did about you, or about something you reported.
        // These used to wear the default bell, which made a warning look like
        // any other line in the list.
        ("account.", "shield"),
        ("report.", "shield"),
    ]
    static func symbol(for type: String) -> String {
        table.first { type.hasPrefix($0.prefix) }?.symbol ?? "bell"
    }
}

// MARK: - The clock

/// The web's `timeAgo`, word for word, ending in the app's own short day.
///
/// This column mixes relative and absolute already; it should not also mix
/// two spellings of a date, so past a month it hands over to `ProfileDate`,
/// which is what every other date in this app is written by.
enum NotificationTime {
    static func ago(_ iso: String?, now: Date = Date()) -> String {
        guard let iso, !iso.isEmpty, let then = PatchworkEvent.parseDate(iso) else { return "" }
        let minutes = Int(floor(now.timeIntervalSince(then) / 60))
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 30 { return "\(days)d ago" }
        return ProfileDate.day(iso) ?? ""
    }
}

// MARK: - Where a link goes

/// Which screen a notification's link names, as a pure function.
///
/// The server builds these paths in `internal/weblink` against the website's
/// route table, and this client has to answer the same question about them
/// without a router. Most of them have a native screen; the ones that do not
/// — setup, the noticeboard, the submission form, a quilt's admin pages — are
/// not stubbed here, they are exits to the website, which is the same rule
/// the rest of this app follows about surfaces it has not built.
enum NotificationLink {
    enum Destination: Equatable, Hashable {
        /// Dock the patch's profile, which closes the sheet first.
        case patch(slug: String)
        case calendar(slug: String)
        case members(slug: String)
        case governance(slug: String)
        case proposal(slug: String, id: String)
        case document(slug: String, id: String)
        case event(id: String)
        case remotePatch(host: String, slug: String)
        /// Not a native surface. The path travels whole, query and all.
        case website(path: String)
    }

    static func route(_ path: String) -> Destination {
        let raw = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = bare(raw).split(separator: "/").map(String.init)
        switch parts.first {
        case "patches":
            guard parts.count >= 2, !parts[1].isEmpty else { break }
            let slug = parts[1]
            switch parts.count {
            case 2: return .patch(slug: slug)
            case 3:
                switch parts[2] {
                case "events": return .calendar(slug: slug)
                case "members": return .members(slug: slug)
                case "governance": return .governance(slug: slug)
                default: break
                }
            case 4 where parts[2] == "governance":
                // The live server spells a proposal `/governance/{id}` and a
                // charter `/governance/docs/{id}`; a four-part path whose
                // third segment is neither of the two names below is
                // therefore a proposal's id and nothing else.
                if parts[3] != "docs" && parts[3] != "proposals" { return .proposal(slug: slug, id: parts[3]) }
            case 5 where parts[2] == "governance":
                if parts[3] == "proposals" { return .proposal(slug: slug, id: parts[4]) }
                if parts[3] == "docs" { return .document(slug: slug, id: parts[4]) }
            default: break
            }
        case "events":
            if parts.count == 2, !parts[1].isEmpty { return .event(id: parts[1]) }
        case "quilts":
            // A patch on a neighbour quilt, read-only on their soil (ADR 024).
            if parts.count == 4, parts[2] == "patches", !parts[1].isEmpty, !parts[3].isEmpty {
                return .remotePatch(host: parts[1], slug: parts[3])
            }
        default: break
        }
        return .website(path: raw)
    }

    /// The same site-relative path split the way `webURL(_:query:)` wants it:
    /// a path with no leading slash, and the query as items, because
    /// `appendingPathComponent` would escape a `?` into the path itself and
    /// hand the reader a 404 with a question mark in it.
    static func exit(_ path: String) -> (path: String, query: [URLQueryItem]) {
        let raw = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = raw.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let query = parts.count > 1 ? URLComponents(string: "?" + parts[1])?.queryItems ?? [] : []
        return (bare(String(parts.first ?? "")), query)
    }

    /// The path with its query and its leading and trailing slashes gone.
    private static func bare(_ path: String) -> String {
        let withoutQuery = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return String(withoutQuery).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

// MARK: - The calls

extension PatchworkAPI {
    /// Built apart from the request, like every other query this client sends,
    /// so what a chip actually asks for can be checked without a network.
    static func notificationsQuery(category: NotificationCategory, unreadOnly: Bool,
                                   after: String? = nil, limit: Int = 20) -> [URLQueryItem] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let after, !after.isEmpty { query.append(URLQueryItem(name: "after", value: after)) }
        if unreadOnly { query.append(URLQueryItem(name: "unread", value: "true")) }
        if let value = category.query { query.append(URLQueryItem(name: "category", value: value)) }
        return query
    }
    func notifications(category: NotificationCategory, unreadOnly: Bool, after: String? = nil) async throws -> NotificationPage {
        try await get("notifications", query: Self.notificationsQuery(category: category, unreadOnly: unreadOnly, after: after))
    }
    func unreadNotifications() async throws -> Int {
        let count: UnreadCount = try await get("notifications/count")
        return count.unread ?? 0
    }
    func markNotificationRead(_ id: String) async throws { try await patchVoid("notifications/\(id)/read") }
    func markAllNotificationsRead() async throws { try await postVoid("notifications/read-all") }
    func dismissNotification(_ id: String) async throws { try await deleteVoid("notifications/\(id)") }
    /// Everything, server-side — not the page in view.
    func clearNotifications() async throws { try await deleteVoid("notifications") }
}

// MARK: - The bell

/// The bell in the discovery bar, beside the account it belongs to. It is
/// drawn only where there is an account: a signed-out reader has no
/// notifications, no count, and nothing to press.
struct NotificationBell: View {
    @EnvironmentObject private var session: QuiltSession
    @Binding var presented: Bool
    var body: some View {
        Button { presented = true } label: {
            // The badge is hung on a frame that has already been given room
            // for it, and the balance is put back with the opposite padding
            // afterwards. The Filter button's own badge is offset out past
            // its glyph, which works at the bar's leading edge and does not
            // here: the bell shares a capsule with the account menu, and an
            // overhanging badge was clipped square down its right-hand side.
            // The padding is unconditional so the bell does not shift when
            // the count arrives.
            Image(systemName: session.unread > 0 ? "bell.fill" : "bell")
                .padding(.top, 6)
                .padding(.trailing, 7)
                .overlay(alignment: .topTrailing) {
                    if session.unread > 0 {
                        Text(UnreadTally.badge(session.unread))
                            .font(Font.pw.caption2Semibold).foregroundStyle(Color(.systemBackground))
                            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                            .background(Color.pwAccent, in: Capsule())
                    }
                }
                .padding(.bottom, 6)
                .padding(.leading, 7)
        }
        .accessibilityLabel("Notifications, \(session.unread) unread")
        .accessibilityIdentifier("notificationBell")
    }
}

// MARK: - The sheet

/// The web's notifications page as a sheet: chips across the top, a stack of
/// cards on the app's ground, and every native destination pushed inside this
/// stack rather than behind it.
struct NotificationsSheet: View {
    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var rows: [PatchworkNotification] = []
    @State private var category = NotificationCategory.all
    @State private var unreadOnly = false
    @State private var cursor = ""
    @State private var loading = false
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var opening: String?
    @State private var confirmingClear = false
    @State private var route: [NotificationRoute] = []

    var body: some View {
        NavigationStack(path: $route) {
            VStack(spacing: 0) {
                chips
                list
            }
            .background(Color.pwGround.ignoresSafeArea())
            .navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { Task { await markAllRead() } } label: { Label("Mark all read", systemImage: "checkmark.circle") }
                            .disabled(!rows.contains { $0.isUnread })
                            .accessibilityIdentifier("notificationsMarkAllRead")
                        Button(role: .destructive) { confirmingClear = true } label: { Label("Clear all", systemImage: "trash") }
                            .disabled(rows.isEmpty)
                            .accessibilityIdentifier("notificationsClearAll")
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Manage notifications")
                    .accessibilityIdentifier("notificationsMenu")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Clear all notifications?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Delete them all", role: .destructive) { Task { await clearAll() } }
                Button("Keep them", role: .cancel) {}
            } message: {
                Text("This removes every notification on this quilt, not only the ones listed here.")
            }
            .navigationDestination(for: NotificationRoute.self) { destination($0) }
            .task { if !loaded { await load() } }
        }
    }

    // MARK: The chips

    /// They wrap rather than scroll sideways, the way the web's do and the
    /// way the filter sheet's do: seven chips on a phone do not fit a line,
    /// and the one that was pushed off the end was "Unread only" — the only
    /// chip on the row that is not a category and the one most likely to be
    /// wanted.
    private var chips: some View {
        FlowLayout(spacing: 8) {
            ForEach(NotificationCategory.allCases) { entry in
                Chip(title: entry.title, active: category == entry) {
                    guard category != entry else { return }
                    category = entry
                    Task { await load() }
                }
                .accessibilityIdentifier("notificationCategory-\(entry.rawValue)")
            }
            // Not a category — a second axis over whichever one is on.
            Chip(title: "Unread only", active: unreadOnly) {
                unreadOnly.toggle()
                Task { await load() }
            }
            .accessibilityIdentifier("notificationUnreadOnly")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.pwGround)
    }

    // MARK: The list

    private var list: some View {
        List {
            if let error {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { Task { await load() } }
                        .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .modifier(NotificationCardChrome())
                .plainRow()
            }
            ForEach(rows) { row in
                NotificationRow(row: row, opening: opening == row.id) { Task { await open(row) } }
                    .plainRow()
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { Task { await dismissRow(row) } } label: {
                            Label("Dismiss", systemImage: "xmark")
                        }
                    }
                    // The same act by another road, for a reader who does not
                    // swipe and for VoiceOver's rotor.
                    .contextMenu {
                        Button(role: .destructive) { Task { await dismissRow(row) } } label: {
                            Label("Dismiss", systemImage: "xmark")
                        }
                    }
            }
            if !cursor.isEmpty {
                Button("Load more") { Task { await loadMore() } }
                    .font(Font.pw.subheadlineMedium).inkAction("arrow.down.circle")
                    .disabled(busy)
                    .accessibilityIdentifier("notificationsLoadMore")
                    .padding(.vertical, 6)
                    .plainRow()
            }
            if loading && rows.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 24).plainRow()
            } else if loaded && rows.isEmpty && error == nil {
                empty.plainRow()
            }
        }
        .listStyle(.plain)
        .groundedList()
        .refreshable { await load() }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing here yet.")
                .font(Font.pw.title2).foregroundStyle(Color.pwText)
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.emptyLine(category: category, unreadOnly: unreadOnly))
                .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .modifier(NotificationCardChrome())
        .accessibilityIdentifier("notificationsEmpty")
    }

    /// The muted line under the empty state, which has to say which absence
    /// it is reporting: "nothing at all" and "nothing under this chip" are
    /// different facts, and a reader who has narrowed the list should not be
    /// told they are caught up on everything.
    static func emptyLine(category: NotificationCategory, unreadOnly: Bool) -> String {
        switch (category, unreadOnly) {
        case (.all, false): return "When a patch needs you for something, it will say so here."
        case (.all, true): return "Everything here has been read."
        case (let narrowed, false): return "Nothing under \(narrowed.title)."
        case (let narrowed, true): return "Nothing unread under \(narrowed.title)."
        }
    }

    // MARK: Reading the list

    private func load() async {
        loading = true
        error = nil
        defer { loading = false; loaded = true }
        do {
            let page = try await session.api.notifications(category: category, unreadOnly: unreadOnly)
            rows = page.items ?? []
            cursor = page.nextCursor ?? ""
        } catch APIError.unauthenticated {
            session.signedOut()
            dismiss()
        } catch {
            if !Task.isCancelled {
                rows = []
                cursor = ""
                self.error = error.localizedDescription
            }
        }
    }

    private func loadMore() async {
        guard !cursor.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let page = try await session.api.notifications(category: category, unreadOnly: unreadOnly, after: cursor)
            // Paging by id, so a row that arrived twice is still one row.
            let known = Set(rows.map(\.id))
            rows += (page.items ?? []).filter { !known.contains($0.id) }
            cursor = page.nextCursor ?? ""
        } catch APIError.unauthenticated {
            session.signedOut()
            dismiss()
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    // MARK: The acts

    /// Tapping a row: read it, then go where it points. Reading is the local
    /// fact the badge moves on; a server that refuses it does not stop the
    /// reader getting to the thing the row is about.
    private func open(_ row: PatchworkNotification) async {
        guard opening == nil else { return }
        opening = row.id
        defer { opening = nil }
        if row.isUnread { await markRead(row) }
        guard !row.target.isEmpty else { return }
        await go(NotificationLink.route(row.target))
    }

    private func markRead(_ row: PatchworkNotification) async {
        do {
            try await session.api.markNotificationRead(row.id)
            if let index = rows.firstIndex(where: { $0.id == row.id }) {
                rows[index] = rows[index].read(at: ISO8601DateFormatter().string(from: Date()))
            }
            session.noteRead()
        } catch APIError.unauthenticated {
            session.signedOut()
            dismiss()
        } catch {
            // A row that could not be marked read is still a row that can be
            // opened. The poll will put the badge right.
        }
    }

    private func markAllRead() async {
        do {
            try await session.api.markAllNotificationsRead()
            let stamp = ISO8601DateFormatter().string(from: Date())
            rows = rows.map { $0.isUnread ? $0.read(at: stamp) : $0 }
            session.clearUnread()
            // "Unread only" with everything read is an empty list by
            // definition, so ask again rather than draw rows the filter no
            // longer admits.
            if unreadOnly { await load() }
        } catch APIError.unauthenticated {
            session.signedOut()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func dismissRow(_ row: PatchworkNotification) async {
        let wasUnread = row.isUnread
        do {
            try await session.api.dismissNotification(row.id)
            rows.removeAll { $0.id == row.id }
            session.noteDismissed(wasUnread: wasUnread)
        } catch APIError.unauthenticated {
            session.signedOut()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func clearAll() async {
        do {
            try await session.api.clearNotifications()
            rows = []
            cursor = ""
            session.clearUnread()
        } catch APIError.unauthenticated {
            session.signedOut()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Going where a row points

    /// A native destination needs the thing itself, not its id, because every
    /// detail screen in this app takes what it already knows and reads the
    /// rest back. So the object is fetched first and the push carries it; a
    /// fetch that fails says so rather than silently opening a browser.
    private func go(_ destination: NotificationLink.Destination) async {
        switch destination {
        case .patch(let slug):
            // Docking is the shell's, not this stack's: the sheet closes and
            // the profile arrives over whatever opened it.
            dismiss()
            await session.open(slug: slug)
        case .calendar(let slug):
            if let patch = await patch(slug) { route.append(.calendar(patch)) }
        case .members(let slug):
            route.append(.members(slug))
        case .governance(let slug):
            if let patch = await patch(slug) { route.append(.governance(patch)) }
        case .proposal(_, let id):
            if let proposal: Proposal = await fetch("proposals/\(id)") { route.append(.proposal(proposal)) }
        case .document(_, let id):
            if let document: GovernanceDocument = await fetch("governance/\(id)") { route.append(.document(document)) }
        case .event(let id):
            if let event: PatchworkEvent = await fetch("events/\(id)") { route.append(.event(event)) }
        case .remotePatch(let host, let slug):
            route.append(.remote(host: host, slug: slug))
        case .website(let path):
            // Not a surface this client has built. It is an exit, and it is
            // drawn as one: the reader leaves for the website rather than
            // being handed a stub of a page that does not exist here.
            let exit = NotificationLink.exit(path)
            openURL(session.api.webURL(exit.path, query: exit.query))
        }
    }

    private func patch(_ slug: String) async -> Patch? {
        if let known = session.patches.first(where: { $0.slug == slug }) { return known }
        let response: PatchResponse? = await fetch("nodes/\(slug)")
        return response?.node
    }

    private func fetch<T: Decodable>(_ path: String) async -> T? {
        do { return try await session.api.get(path) }
        catch APIError.unauthenticated { session.signedOut(); dismiss(); return nil }
        catch {
            self.error = "That could not be opened just now. Try again."
            return nil
        }
    }

    @ViewBuilder private func destination(_ route: NotificationRoute) -> some View {
        switch route {
        case .calendar(let patch): PatchCalendar(quilt: session.quilt, patch: patch)
        case .members(let slug): PatchMemberList(quilt: session.quilt, slug: slug)
        case .governance(let patch): PatchGovernanceHome(quilt: session.quilt, patch: patch)
        case .proposal(let proposal): ProposalDetailView(quilt: session.quilt, initial: proposal)
        case .document(let document): GovernanceDocumentDetail(quilt: session.quilt, initial: document)
        case .event(let event): EventDetail(quilt: session.quilt, initial: event)
        case .remote(let host, let slug): RemotePatchView(host: host, slug: slug)
        }
    }
}

/// What a push inside the sheet carries. Every case holds the thing itself
/// rather than an id, because that is what the screens take.
enum NotificationRoute: Hashable {
    case calendar(Patch)
    case members(String)
    case governance(Patch)
    case proposal(Proposal)
    case document(GovernanceDocument)
    case event(PatchworkEvent)
    case remote(host: String, slug: String)
}

/// One row: the type's mark, what happened, and when — with the unread dot in
/// the one tint, because unread is the only thing on this screen that is
/// about to be acted on.
private struct NotificationRow: View {
    let row: PatchworkNotification
    var opening = false
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: row.symbol)
                    .font(Font.pw.headline)
                    .foregroundStyle(Color.pwTextMuted)
                    .frame(width: 22, alignment: .center)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let body = row.body, !body.isEmpty {
                        Text(body)
                            .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(NotificationTime.ago(row.createdAt))
                        .font(Font.pw.caption2).foregroundStyle(Color.pwTextMuted)
                        .lineLimit(1)
                    if opening {
                        ProgressView().controlSize(.mini)
                    } else if row.isUnread {
                        Circle().fill(Color.pwAccent).frame(width: 8, height: 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(NotificationCardChrome())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("notificationRow-\(row.id)")
        .accessibilityValue(row.isUnread ? "Unread" : "")
    }
}

/// The house card: the surface a step off the ground and the hairline it is
/// cut out with, at the site's own radius.
private struct NotificationCardChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.pwSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.pwBorder, lineWidth: 1))
    }
}
