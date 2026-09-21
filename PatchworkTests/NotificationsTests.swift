// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// Everything the notifications list decides, decided without a window.
///
/// The five values under test are the whole of the slice's judgement: where a
/// link goes, which mark a type earns, how long ago something was, what the
/// badge does when a row is read or dismissed, and what a chip actually asks
/// the quilt for. The sheet draws them and nothing more.
final class NotificationsTests: XCTestCase {

    // MARK: - Where a link goes

    func testEveryLinkShapeTheServerBuildsLandsOnItsOwnScreen() {
        XCTAssertEqual(NotificationLink.route("/patches/common-thread"), .patch(slug: "common-thread"))
        XCTAssertEqual(NotificationLink.route("/patches/common-thread/events"), .calendar(slug: "common-thread"))
        XCTAssertEqual(NotificationLink.route("/patches/common-thread/members"), .members(slug: "common-thread"))
        XCTAssertEqual(NotificationLink.route("/patches/common-thread/governance"), .governance(slug: "common-thread"))
        XCTAssertEqual(NotificationLink.route("/patches/common-thread/governance/proposals/demo-proposal"),
                       .proposal(slug: "common-thread", id: "demo-proposal"))
        XCTAssertEqual(NotificationLink.route("/patches/common-thread/governance/docs/demo-doc"),
                       .document(slug: "common-thread", id: "demo-doc"))
        XCTAssertEqual(NotificationLink.route("/events/demo-event"), .event(id: "demo-event"))
        XCTAssertEqual(NotificationLink.route("/quilts/neighbor.example.org/patches/paper-mill"),
                       .remotePatch(host: "neighbor.example.org", slug: "paper-mill"))
    }

    /// The members tab carries its filter in the query, and a query never
    /// decides which screen a path names.
    func testThePendingFilterRidesAlongAndStillOpensTheMembers() {
        XCTAssertEqual(NotificationLink.route("/patches/common-thread/members?status=pending"),
                       .members(slug: "common-thread"))
    }

    /// `weblink.Proposal` spells a proposal `/governance/{id}` with no word in
    /// front of the id, and `weblink.GovernanceDoc` is the one that adds a
    /// segment. A four-part governance path is therefore a proposal, and
    /// reading it as anything else would send every vote notification on a
    /// live quilt out to the website.
    func testTheBareGovernanceIdIsAProposalAndNotADocument() {
        XCTAssertEqual(NotificationLink.route("/patches/common-thread/governance/019f-pr"),
                       .proposal(slug: "common-thread", id: "019f-pr"))
        XCTAssertNotEqual(NotificationLink.route("/patches/common-thread/governance/docs/019f-doc"),
                          .proposal(slug: "common-thread", id: "019f-doc"))
    }

    /// The surfaces this client has not built are exits, not stubs — the same
    /// rule the rest of the app follows about the website's own pages.
    func testWhatThisClientDoesNotDrawIsAnExitToTheWebsite() {
        for path in ["/patches/common-thread/setup",
                     "/patches/common-thread/noticeboard/019f-n",
                     "/patches/common-thread/settings/sources",
                     "/submit",
                     "/sources",
                     "/admin/reports",
                     "/patches",
                     ""] {
            XCTAssertEqual(NotificationLink.route(path), .website(path: path), "\(path) is not a native screen")
        }
    }

    /// An exit has to arrive with its query intact and without a slash the
    /// path builder would double: `appendingPathComponent` escapes a `?` into
    /// the path and hands the reader a 404 with a question mark in it.
    func testAnExitKeepsItsQueryAndLosesItsLeadingSlash() {
        let plain = NotificationLink.exit("/patches/common-thread/noticeboard/x")
        XCTAssertEqual(plain.path, "patches/common-thread/noticeboard/x")
        XCTAssertTrue(plain.query.isEmpty)
        let filtered = NotificationLink.exit("/patches/common-thread/members?status=pending")
        XCTAssertEqual(filtered.path, "patches/common-thread/members")
        XCTAssertEqual(filtered.query.first?.name, "status")
        XCTAssertEqual(filtered.query.first?.value, "pending")
    }

    // MARK: - The marks

    func testEachTypePrefixWearsTheWebsOwnMark() {
        XCTAssertEqual(NotificationIcon.symbol(for: "proposal.voting_opened"), "doc.text")
        XCTAssertEqual(NotificationIcon.symbol(for: "governance.document_amended"), "scroll")
        XCTAssertEqual(NotificationIcon.symbol(for: "membership.request_approved"), "person.2")
        XCTAssertEqual(NotificationIcon.symbol(for: "event.reminder"), "mappin")
        XCTAssertEqual(NotificationIcon.symbol(for: "admin.claimed"), "wrench.and.screwdriver")
        XCTAssertEqual(NotificationIcon.symbol(for: "comment.replied"), "bubble.left")
        XCTAssertEqual(NotificationIcon.symbol(for: "notice.posted"), "bubble.left")
        XCTAssertEqual(NotificationIcon.symbol(for: "remote.posted"), "heart")
        XCTAssertEqual(NotificationIcon.symbol(for: "account.warned"), "shield")
        XCTAssertEqual(NotificationIcon.symbol(for: "report.resolved"), "shield")
    }

    /// A type this build has never heard of is still a notification.
    func testAnUnknownTypeIsABellRatherThanNothing() {
        XCTAssertEqual(NotificationIcon.symbol(for: "quilt.rearranged"), "bell")
        XCTAssertEqual(NotificationIcon.symbol(for: ""), "bell")
        // A prefix is a prefix: the dot is part of it, so a type that merely
        // starts with the same letters does not borrow the mark.
        XCTAssertEqual(NotificationIcon.symbol(for: "proposals-digest"), "bell")
    }

    // MARK: - The clock

    private func iso(_ now: Date, minutesAgo: Double) -> String {
        ISO8601DateFormatter().string(from: now.addingTimeInterval(-minutesAgo * 60))
    }

    func testTheRelativeColumnIsWordedExactlyAsTheWebWordsIt() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func ago(_ minutes: Double) -> String { NotificationTime.ago(iso(now, minutesAgo: minutes), now: now) }
        XCTAssertEqual(ago(0), "just now")
        XCTAssertEqual(ago(0.9), "just now", "under a minute has not happened a minute ago")
        XCTAssertEqual(ago(1), "1m ago")
        XCTAssertEqual(ago(5), "5m ago")
        XCTAssertEqual(ago(59), "59m ago")
        XCTAssertEqual(ago(60), "1h ago")
        XCTAssertEqual(ago(180), "3h ago")
        XCTAssertEqual(ago(60 * 24 - 1), "23h ago")
        XCTAssertEqual(ago(60 * 24), "1d ago")
        XCTAssertEqual(ago(60 * 24 * 2), "2d ago")
        XCTAssertEqual(ago(60 * 24 * 30 - 1), "29d ago")
    }

    /// Past a month it hands over to the app's own short day, rather than
    /// printing a third spelling of a date in a column that already mixes two.
    func testPastAMonthItIsTheAppsOwnShortDay() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let stamp = iso(now, minutesAgo: 60 * 24 * 40)
        XCTAssertEqual(NotificationTime.ago(stamp, now: now), ProfileDate.day(stamp))
        XCTAssertNotEqual(NotificationTime.ago(stamp, now: now), "")
    }

    func testANotificationWithNoTimestampSaysNothingRatherThanGuessing() {
        XCTAssertEqual(NotificationTime.ago(nil), "")
        XCTAssertEqual(NotificationTime.ago(""), "")
        XCTAssertEqual(NotificationTime.ago("not a date"), "")
    }

    // MARK: - The badge's arithmetic

    func testReadingOneTakesTheBadgeDownAndTheFloorIsZero() {
        XCTAssertEqual(UnreadTally.read(3), 2)
        XCTAssertEqual(UnreadTally.read(1), 0)
        XCTAssertEqual(UnreadTally.read(0), 0, "a client counting down locally must not go negative")
        XCTAssertEqual(UnreadTally.read(2, 5), 0)
    }

    func testMarkAllReadAndClearAllBothGoToZeroRatherThanDownByTheRowsDrawn() {
        // Both empty the whole table server-side, not the page in view.
        XCTAssertEqual(UnreadTally.cleared, 0)
    }

    func testDismissingAReadRowDoesNotMoveTheBadge() {
        XCTAssertEqual(UnreadTally.dismissed(4, wasUnread: false), 4, "a read row never counted")
        XCTAssertEqual(UnreadTally.dismissed(4, wasUnread: true), 3)
        XCTAssertEqual(UnreadTally.dismissed(0, wasUnread: true), 0)
    }

    func testThePollIsReconciliationAndTheServersNumberWins() {
        XCTAssertEqual(UnreadTally.reconciled(7), 7)
        XCTAssertEqual(UnreadTally.reconciled(0), 0)
        XCTAssertEqual(UnreadTally.reconciled(-3), 0, "a number below zero is not a count")
    }

    func testPastNinetyNineTheBadgeStopsCounting() {
        XCTAssertEqual(UnreadTally.badge(0), "0")
        XCTAssertEqual(UnreadTally.badge(9), "9")
        XCTAssertEqual(UnreadTally.badge(99), "99")
        XCTAssertEqual(UnreadTally.badge(100), "99+", "three digits in a 16pt capsule is not a number anybody reads")
    }

    // MARK: - The chips

    func testTheChipsAreTheWebsOwnFiltersInTheWebsOwnOrder() {
        XCTAssertEqual(NotificationCategory.allCases.map(\.title),
                       ["All", "Proposals", "Governance", "Membership", "Events", "Moderation"])
    }

    func testAChipBecomesTheQueryTheServerNames() {
        XCTAssertNil(NotificationCategory.all.query, "All is the absence of the parameter, not a value of it")
        XCTAssertEqual(NotificationCategory.proposals.query, "proposals")
        XCTAssertEqual(NotificationCategory.governance.query, "governance")
        XCTAssertEqual(NotificationCategory.membership.query, "membership")
        XCTAssertEqual(NotificationCategory.events.query, "events")
        XCTAssertEqual(NotificationCategory.moderation.query, "moderation")
    }

    func testWhatAChipAndTheUnreadToggleActuallyAsk() {
        let plain = PatchworkAPI.notificationsQuery(category: .all, unreadOnly: false)
        XCTAssertEqual(plain.first { $0.name == "limit" }?.value, "20")
        XCTAssertNil(plain.first { $0.name == "category" }, "All asks for no category at all")
        XCTAssertNil(plain.first { $0.name == "unread" })

        let narrowed = PatchworkAPI.notificationsQuery(category: .events, unreadOnly: true, after: "notif-3")
        XCTAssertEqual(narrowed.first { $0.name == "category" }?.value, "events")
        XCTAssertEqual(narrowed.first { $0.name == "unread" }?.value, "true")
        XCTAssertEqual(narrowed.first { $0.name == "after" }?.value, "notif-3")

        XCTAssertNil(PatchworkAPI.notificationsQuery(category: .all, unreadOnly: false, after: "").first { $0.name == "after" },
                     "an empty cursor is not a cursor")
    }

    /// The empty state has to say which absence it is reporting: a reader who
    /// has narrowed the list must not be told they are caught up on all of it.
    func testTheEmptyStateNamesTheFilterItIsEmptyUnder() {
        XCTAssertEqual(NotificationsSheet.emptyLine(category: .all, unreadOnly: false),
                       "When a patch needs you for something, it will say so here.")
        XCTAssertEqual(NotificationsSheet.emptyLine(category: .all, unreadOnly: true), "Everything here has been read.")
        XCTAssertEqual(NotificationsSheet.emptyLine(category: .proposals, unreadOnly: false), "Nothing under Proposals.")
        XCTAssertEqual(NotificationsSheet.emptyLine(category: .events, unreadOnly: true), "Nothing unread under Events.")
    }

    // MARK: - Decoding a row

    private func row(_ json: String) throws -> PatchworkNotification {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PatchworkNotification.self, from: Data(json.utf8))
    }

    /// Unread is the *absence* of `read_at`, not a null and not a flag. The
    /// server sends no such key at all until the row has been read.
    func testARowWithNoReadAtIsUnread() throws {
        let unread = try row("""
        {"id":"n1","user_id":"u1","type":"event.reminder","title":"Tomorrow","body":"At six.",
        "link":"/events/demo-event","created_at":"2026-09-20T18:00:00Z"}
        """)
        XCTAssertTrue(unread.isUnread)
        XCTAssertNil(unread.readAt)
        XCTAssertEqual(unread.target, "/events/demo-event")
        XCTAssertEqual(unread.symbol, "mappin")
    }

    func testARowWithAReadAtIsRead() throws {
        let read = try row("""
        {"id":"n2","user_id":"u1","type":"proposal.voting_opened","title":"Vote","body":"",
        "link":"","read_at":"2026-09-21T09:00:00Z","created_at":"2026-09-20T18:00:00Z"}
        """)
        XCTAssertFalse(read.isUnread)
        XCTAssertEqual(read.readAt, "2026-09-21T09:00:00Z")
        XCTAssertEqual(read.target, "", "a warning has nowhere to send anybody, and an empty link says so")
    }

    /// The whole page, envelope and all — and the cursor the "Load more" row
    /// is drawn from.
    func testThePageCarriesItsCursor() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let page = try decoder.decode(NotificationPage.self, from: Data("""
        {"items":[{"id":"n1","user_id":"u1","type":"bell.x","title":"T","body":"B","link":"","created_at":"2026-09-20T18:00:00Z"}],
        "next_cursor":"n1"}
        """.utf8))
        XCTAssertEqual(page.items?.count, 1)
        XCTAssertEqual(page.nextCursor, "n1")
        let count = try decoder.decode(UnreadCount.self, from: Data(#"{"unread":4}"#.utf8))
        XCTAssertEqual(count.unread, 4)
    }

    /// Marking read is a local fact the moment the server answers, so the row
    /// that was drawn unread is redrawn read without another round trip.
    func testAReadRowIsTheSameRowWithAStamp() throws {
        let unread = try row("""
        {"id":"n1","user_id":"u1","type":"event.reminder","title":"Tomorrow","body":"At six.",
        "link":"/events/demo-event","created_at":"2026-09-20T18:00:00Z"}
        """)
        let read = unread.read(at: "2026-09-21T10:00:00Z")
        XCTAssertEqual(read.id, unread.id)
        XCTAssertEqual(read.title, unread.title)
        XCTAssertEqual(read.link, unread.link)
        XCTAssertFalse(read.isUnread)
    }
}
