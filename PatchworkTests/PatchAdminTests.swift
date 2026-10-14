// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// A patch admin's queues as values: who is shown them, what the server's
/// listings decode to, exactly what each act sends, the words each act is
/// said in, and where a request's notification goes.
final class PatchAdminTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
    private func json(_ body: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(body), as: UTF8.self)
    }
    private let newYork = TimeZone(identifier: "America/New_York")!

    // MARK: Gates

    func testOnlyAPatchAdminRunsIt() {
        XCTAssertTrue(PatchAdmin.runs(.active(.admin)))
        XCTAssertFalse(PatchAdmin.runs(.active(.member)), "the server hands a member the active list as if it were the queue")
        XCTAssertFalse(PatchAdmin.runs(.active(.follower)))
        XCTAssertFalse(PatchAdmin.runs(.pending))
        XCTAssertFalse(PatchAdmin.runs(nil), "a quilt admin with no role here is answered 404 on invitations")
    }

    func testSuggestionsAreReviewedByThePatchsAdminsOrTheQuilts() {
        XCTAssertTrue(PatchAdmin.reviews(standing: .active(.admin), isInstanceAdmin: false))
        XCTAssertTrue(PatchAdmin.reviews(standing: nil, isInstanceAdmin: true), "the web's canReview, and the server's rule")
        XCTAssertFalse(PatchAdmin.reviews(standing: .active(.member), isInstanceAdmin: false))
    }

    func testRemoveIsNeverOfferedOnYourselfOrOnARowTheServerWouldNotBan() {
        let member = PatchMember(id: "m2", userId: "u2", username: "lena", displayName: "Lena", avatarUrl: nil, role: "member")
        let admin = PatchMember(id: "m3", userId: "u3", username: "juno", displayName: nil, avatarUrl: nil, role: "admin", status: "active")
        let me = PatchMember(id: "m1", userId: "me", username: "me", displayName: nil, avatarUrl: nil, role: "admin")
        let follower = PatchMember(id: "m4", userId: "u4", username: "rue", displayName: nil, avatarUrl: nil, role: "follower")
        let banned = PatchMember(id: "m5", userId: "u5", username: "max", displayName: nil, avatarUrl: nil, role: "member", status: "banned")
        let nameless = PatchMember(id: "m6", userId: nil, username: nil, displayName: nil, avatarUrl: nil, role: "member")
        XCTAssertTrue(PatchAdmin.mayRemove(member, me: "me"))
        XCTAssertTrue(PatchAdmin.mayRemove(admin, me: "me"), "the last-admin floor is the server's to state")
        XCTAssertFalse(PatchAdmin.mayRemove(me, me: "me"), "cannot ban yourself")
        XCTAssertFalse(PatchAdmin.mayRemove(follower, me: "me"), "followers are not on the member roster")
        XCTAssertFalse(PatchAdmin.mayRemove(banned, me: "me"), "can only ban active members")
        XCTAssertFalse(PatchAdmin.mayRemove(nameless, me: "me"), "no id, no path")
    }

    // MARK: Decoding

    func testThePendingListingCarriesTheNoteAndTheMomentOfAsking() throws {
        let body = """
        {"items":[{"id":"mem-1","user_id":"u-priya","node_id":"n1","role":"member","status":"pending",
        "joined_at":"2026-10-11T18:00:00Z","username":"priya","display_name":"Priya Nair","avatar_url":"",
        "join_message":"I run the projector."},
        {"id":"mem-2","user_id":"u-bea","node_id":"n1","role":"member","status":"pending",
        "joined_at":"2026-10-13T09:00:00Z","username":"bea","display_name":"","avatar_url":""}],
        "next_cursor":"mem-2","member_count":3,"follower_count":0,"public_member_list":"nobody",
        "invited":[{"id":"mem-9","user_id":"u-ivy","username":"ivy","display_name":"Ivy Chen","avatar_url":"","invited_at":"2026-10-10T10:00:00Z"}]}
        """
        let page = try decoder().decode(MemberPage.self, from: Data(body.utf8))
        let items = page.items ?? []
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].joinMessage, "I run the projector.")
        XCTAssertEqual(items[0].status, "pending")
        XCTAssertEqual(items[0].joinedAt, "2026-10-11T18:00:00Z")
        XCTAssertNil(items[1].joinMessage, "omitted when empty")
        XCTAssertEqual(items[1].name, "bea")
        XCTAssertEqual(page.memberCount, 3, "the whole queue, not the page")
        XCTAssertEqual(page.nextCursor, "mem-2")
        XCTAssertEqual(page.invited?.first?.name, "Ivy Chen")
        XCTAssertEqual(page.invited?.first?.userId, "u-ivy")
    }

    func testAPublicListingStillDecodesWithNoneOfTheAdminsFields() throws {
        let body = #"{"items":[{"id":"m1","user_id":"u1","role":"admin","username":"rowan","display_name":"Rowan Hale"}],"next_cursor":"","member_count":12,"follower_count":34,"public_member_list":"everyone"}"#
        let page = try decoder().decode(MemberPage.self, from: Data(body.utf8))
        XCTAssertNil(page.invited)
        XCTAssertNil(page.items?.first?.joinMessage)
        XCTAssertNil(page.items?.first?.status)
    }

    func testAMemberOrAdminIsNeverShownAWithheldRoster() throws {
        let body = #"{"items":[{"id":"m1","user_id":"u1","role":"admin","username":"dee"}],"next_cursor":"","member_count":8,"follower_count":0,"public_member_list":"nobody"}"#
        let page = try decoder().decode(MemberPage.self, from: Data(body.utf8))
        XCTAssertTrue(MemberRoster(page: page).withheld, "a visitor")
        let inside = MemberRoster(page: page, inRoom: true)
        XCTAssertFalse(inside.withheld, "the server lists everyone to the room")
        XCTAssertEqual(inside.members.count, 1)
    }

    /// The submissions query reads no zone, image or page: they arrive blank.
    func testASuggestionDecodesWithoutItsZoneAndReadsInThePatchs() throws {
        let body = """
        {"items":[{"id":"ev-1","node_id":"n7","created_by":"u-kofi","title":"Silent film night",
        "description":"Live piano.","location":"Library basement","latitude":null,"longitude":null,
        "starts_at":"2026-10-18T23:00:00Z","ends_at":null,"timezone":"","recurrence":"","visibility":"public",
        "status":"pending_review","image_url":"","image_alt":"","event_url":"",
        "created_at":"2026-10-12T10:00:00Z","updated_at":"2026-10-12T10:00:00Z",
        "node_name":"Film Club","node_slug":"film-club","node_status":"active",
        "submitter_username":"kofi","submitter_display_name":"Kofi Adu"}]}
        """
        let page = try decoder().decode(SubmissionPage.self, from: Data(body.utf8))
        let submission = try XCTUnwrap(page.items?.first)
        XCTAssertEqual(submission.id, "ev-1")
        XCTAssertEqual(submission.event.timezone, "")
        XCTAssertNil(submission.event.endsAt)
        XCTAssertEqual(submission.submitter, "Kofi Adu")
        let now = PatchworkEvent.parseDate("2026-10-13T12:00:00Z")!
        XCTAssertEqual(PatchAdmin.submissionLine(submission.event, zone: newYork, now: now),
                       "Sun, Oct 18 · 7:00 PM · Library basement", "the patch's evening, not UTC's small hours")
        let zoned = submission.event.inZone(newYork)
        XCTAssertEqual(zoned.timezone, "America/New_York")
        XCTAssertEqual(zoned.title, submission.event.title)
    }

    func testASubmitterIsNamedTheWebsWay() throws {
        let both = EventSubmission(event: try event(), submitterUsername: "kofi", submitterDisplayName: " ")
        XCTAssertEqual(both.submitter, "kofi")
        let none = EventSubmission(event: try event(), submitterUsername: "", submitterDisplayName: nil)
        XCTAssertEqual(none.submitter, "unknown")
    }

    func testAnotherYearIsSaidAndAMissingPlaceIsLeftOut() throws {
        let next = try event(startsAt: "2027-01-09T00:30:00Z", location: "")
        let now = PatchworkEvent.parseDate("2026-10-13T12:00:00Z")!
        XCTAssertEqual(PatchAdmin.submissionLine(next, zone: newYork, now: now), "Fri, Jan 8, 2027 · 7:30 PM")
    }

    func testAZoneAlreadyStatedIsKept() throws {
        let zoned = try event(timezone: "Europe/London")
        XCTAssertEqual(zoned.inZone(newYork).timezone, "Europe/London")
    }

    // MARK: What is sent

    func testEachActSendsTheServersStatus() throws {
        XCTAssertEqual(try json(PatchAdmin.MemberAct.approve.body), #"{"status":"active"}"#)
        XCTAssertEqual(try json(PatchAdmin.MemberAct.reject.body), #"{"status":"left"}"#)
        XCTAssertEqual(try json(PatchAdmin.MemberAct.remove.body), #"{"status":"banned"}"#, "Remove is a ban")
        XCTAssertEqual(try json(PatchAdmin.MemberAct.reinstate.body), #"{"status":"left"}"#, "the same word as reject, on a banned row")
    }

    func testAReviewCarriesANoteOnlyWhenDecliningWithOne() throws {
        XCTAssertEqual(try json(PatchAdmin.reviewBody(approve: true, note: "ignored")), #"{"action":"approve"}"#)
        XCTAssertEqual(try json(PatchAdmin.reviewBody(approve: false)), #"{"action":"reject"}"#)
        XCTAssertEqual(try json(PatchAdmin.reviewBody(approve: false, note: "  \n ")), #"{"action":"reject"}"#)
        XCTAssertEqual(try json(PatchAdmin.reviewBody(approve: false, note: " Clashes with ours. ")),
                       #"{"action":"reject","note":"Clashes with ours."}"#)
    }

    func testAnInvitationSendsTheNameTrimmedAndNothingWhileEmpty() throws {
        XCTAssertEqual(try json(XCTUnwrap(PatchAdmin.inviteBody("  @noor "))), #"{"username":"@noor"}"#, "the server strips the @")
        XCTAssertNil(PatchAdmin.inviteBody("   "))
        XCTAssertNil(PatchAdmin.inviteBody("@"))
    }

    func testTheQueueIsAskedForByStatusAndPagedByCursor() {
        XCTAssertEqual(PatchAdmin.membersQuery(status: "pending"),
                       [URLQueryItem(name: "status", value: "pending"), URLQueryItem(name: "limit", value: "20")])
        XCTAssertEqual(PatchAdmin.membersQuery(status: "banned", after: "mem-20", limit: 1),
                       [URLQueryItem(name: "status", value: "banned"), URLQueryItem(name: "limit", value: "1"),
                        URLQueryItem(name: "after", value: "mem-20")])
        XCTAssertEqual(PatchAdmin.membersQuery(status: "pending", after: ""), PatchAdmin.membersQuery(status: "pending"))
    }

    // MARK: Words

    func testTheActsAreSaidInTheWebsWords() {
        XCTAssertEqual(PatchAdmin.MemberAct.approve.done, "Member approved")
        XCTAssertEqual(PatchAdmin.MemberAct.reject.done, "Request rejected")
        XCTAssertEqual(PatchAdmin.MemberAct.remove.done, "Member removed")
        XCTAssertEqual(PatchAdmin.MemberAct.reinstate.done, "Member reinstated")
        XCTAssertEqual(PatchAdmin.MemberAct.reject.failed, "Failed to reject member")
        XCTAssertTrue(PatchAdmin.MemberAct.reject.destructive)
        XCTAssertFalse(PatchAdmin.MemberAct.approve.destructive)
        XCTAssertTrue(PatchAdmin.MemberAct.reject.consequence("Tom").contains("isn’t told"), "the server notifies nobody of a rejection")
    }

    func testTheServersRefusalIsWhatIsShown() {
        let lastAdmin = APIError.message("cannot ban the last admin", status: 409)
        XCTAssertEqual(ProposalDetailView.sentence(lastAdmin, fallback: PatchAdmin.MemberAct.remove.failed), "Cannot ban the last admin")
        XCTAssertEqual(ProposalDetailView.sentence(APIError.status(500), fallback: PatchAdmin.MemberAct.remove.failed), "Failed to remove member")
    }

    func testCountsAndNotesReadAsSentences() {
        XCTAssertEqual(PatchAdmin.requestsLabel(3), "3 pending member requests")
        XCTAssertEqual(PatchAdmin.requestsLabel(1), "1 pending member request")
        XCTAssertEqual(PatchAdmin.suggestionsLabel(1), "1 suggested event")
        XCTAssertEqual(PatchAdmin.suggestionsLabel(2), "2 suggested events")
        XCTAssertEqual(PatchAdmin.queueCount(1), "1 request waiting")
        XCTAssertEqual(PatchAdmin.quoted("  Hello there "), "“Hello there”")
        XCTAssertNil(PatchAdmin.quoted("   "))
        let now = PatchworkEvent.parseDate("2026-10-13T12:00:00Z")!
        XCTAssertEqual(PatchAdmin.asked("2026-10-11T12:00:00Z", now: now), "Asked 2d ago")
        XCTAssertNil(PatchAdmin.asked(nil, now: now))
        XCTAssertEqual(PatchAdmin.invitedLine("2026-10-13T11:30:00Z", now: now), "Invited 30m ago")
    }

    // MARK: Where a request's notification goes

    func testARequestNotificationOpensTheQueueForAnAdminAndTheRosterForAnyoneElse() {
        let link = NotificationLink.route("/patches/film-club/members?status=pending")
        guard case .joinRequests(let slug) = link else { return XCTFail("\(link)") }
        XCTAssertEqual(PatchAdmin.requestsRoute(slug: slug, standing: .active(.admin)), .joinRequests("film-club"))
        XCTAssertEqual(PatchAdmin.requestsRoute(slug: slug, standing: .active(.member)), .members("film-club"))
        XCTAssertEqual(PatchAdmin.requestsRoute(slug: slug, standing: nil), .members("film-club"))
    }

    // MARK: Helpers

    private func event(startsAt: String = "2026-10-18T23:00:00Z", location: String = "Hall", timezone: String = "") throws -> PatchworkEvent {
        let body = #"{"id":"e","title":"T","starts_at":"\#(startsAt)","location":"\#(location)","timezone":"\#(timezone)"}"#
        return try decoder().decode(PatchworkEvent.self, from: Data(body.utf8))
    }
}
