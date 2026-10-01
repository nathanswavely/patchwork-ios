// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import Patchwork

/// The noticeboard's rules as values (web ADR 081): who is in the room, what
/// a row says, what the server will refuse before it is asked, and exactly
/// what each write sends.
final class NoticeboardTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
    private func json(_ body: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(body), as: UTF8.self)
    }

    // MARK: Decoding

    func testTheBoardDecodesWithTheReadersRights() throws {
        let page = try decoder().decode(NoticePage.self, from: Data("""
        {"items":[{"id":"n2","node_id":"p1","author_id":"u1","title":"Kiln","body":"Out **of** action","image_url":"",
          "image_alt":"","replies_open":false,"members_told":true,"created_at":"2026-09-30T14:03:22.123Z",
          "updated_at":"2026-09-30T14:03:22.123Z","author_username":"rowan","author_display_name":"Rowan Hale","reply_count":2}],
         "next_cursor":"n2","may_post":true,"replies_default":false,"notice_posting":"admins"}
        """.utf8))
        XCTAssertEqual(page.items.count, 1)
        let notice = try XCTUnwrap(page.items.first)
        XCTAssertEqual(notice.title, "Kiln")
        XCTAssertEqual(notice.author, "Rowan Hale")
        XCTAssertFalse(notice.repliesOpen)
        XCTAssertTrue(notice.membersTold)
        XCTAssertEqual(notice.replyCount, 2)
        XCTAssertNil(notice.image, "an empty address is no image")
        XCTAssertNotNil(PatchworkEvent.parseDate(notice.createdAt), "the server's milliseconds are read")
        XCTAssertEqual(page.nextCursor, "n2")
        XCTAssertTrue(page.mayPost)
        XCTAssertFalse(page.repliesDefault)
        XCTAssertEqual(page.noticePosting, "admins")
    }

    /// A quilt a version behind, or an empty board: nothing is refused for
    /// what it leaves out, and the defaults are the server's own.
    func testAThinAnswerIsStillRead() throws {
        let page = try decoder().decode(NoticePage.self, from: Data(#"{"items":[{"id":"n1"}]}"#.utf8))
        XCTAssertEqual(page.items.first?.id, "n1")
        XCTAssertEqual(page.items.first?.repliesOpen, true)
        XCTAssertEqual(page.nextCursor, "")
        XCTAssertFalse(page.mayPost)
        XCTAssertTrue(page.repliesDefault)
        XCTAssertEqual(page.noticePosting, "members")
        let empty = try decoder().decode(NoticePage.self, from: Data(#"{"items":[],"next_cursor":""}"#.utf8))
        XCTAssertTrue(empty.items.isEmpty)
    }

    /// Only the detail read carries the two rights and the patch's slug.
    func testTheDetailEnvelopeCarriesTheRights() throws {
        let envelope = try decoder().decode(NoticeEnvelope.self, from: Data("""
        {"notice":{"id":"n1","title":"Fabric","author_id":"me","image_url":"https://example.org/a.jpg","image_alt":"Boxes"},
         "node_slug":"common-thread","may_edit":true,"may_manage":true}
        """.utf8))
        XCTAssertEqual(envelope.nodeSlug, "common-thread")
        XCTAssertTrue(envelope.mayEdit)
        XCTAssertTrue(envelope.mayManage)
        XCTAssertEqual(envelope.notice.image?.absoluteString, "https://example.org/a.jpg")
        let bare = try decoder().decode(NoticeEnvelope.self, from: Data(#"{"notice":{"id":"n1"}}"#.utf8))
        XCTAssertFalse(bare.mayEdit)
        XCTAssertFalse(bare.mayManage)
    }

    func testRepliesDecodeOldestFirstAsServed() throws {
        let page = try decoder().decode(ReplyPage.self, from: Data("""
        {"items":[{"id":"r1","notice_id":"n1","author_id":"u1","body":"First","created_at":"2026-09-30T14:03:22.123Z",
          "updated_at":"2026-09-30T14:03:22.123Z","author_username":"","author_display_name":"Deleted account"},
          {"id":"r2","notice_id":"n1","author_id":"u2","body":"Second","author_username":"imani","author_display_name":""}],
         "next_cursor":""}
        """.utf8))
        XCTAssertEqual(page.items.map(\.id), ["r1", "r2"])
        XCTAssertEqual(page.items[0].author, "Deleted account")
        XCTAssertEqual(page.items[1].author, "imani", "a username stands in for a missing display name")
        XCTAssertEqual(page.nextCursor, "")
    }

    /// An image is only ever https with a host; anything else is no image.
    func testOnlyAnHttpsImageIsAnImage() {
        XCTAssertNotNil(Notice(id: "n", imageUrl: "https://example.org/flyer.png").image)
        XCTAssertNil(Notice(id: "n", imageUrl: "http://example.org/flyer.png").image)
        XCTAssertNil(Notice(id: "n", imageUrl: "flyer.png").image)
        XCTAssertNil(Notice(id: "n", imageUrl: "").image)
    }

    // MARK: The room

    /// Members and admins, and nobody else — a follower and a pending
    /// request included. A quilt admin with no role here has no standing.
    func testTheRoomIsMembersAndAdmins() {
        XCTAssertTrue(Noticeboard.inRoom(.active(.member)))
        XCTAssertTrue(Noticeboard.inRoom(.active(.admin)))
        XCTAssertFalse(Noticeboard.inRoom(.active(.follower)))
        XCTAssertFalse(Noticeboard.inRoom(.pending))
        XCTAssertFalse(Noticeboard.inRoom(nil))
    }

    func testTheHintSaysWhoReadsAndWhoPosts() {
        XCTAssertEqual(Noticeboard.hint(posting: "members"), "Read by this patch’s admins and members, and nobody else.")
        XCTAssertEqual(Noticeboard.hint(posting: "admins"),
                       "Read by this patch’s admins and members, and nobody else. Its admins put up the notices.")
    }

    // MARK: The words on a row

    func testARowSaysWhatItsRepliesAreDoing() {
        XCTAssertEqual(Noticeboard.repliesLabel(Notice(id: "n", repliesOpen: true, replyCount: 0)), "0 replies")
        XCTAssertEqual(Noticeboard.repliesLabel(Notice(id: "n", repliesOpen: true, replyCount: 1)), "1 reply")
        XCTAssertEqual(Noticeboard.repliesLabel(Notice(id: "n", repliesOpen: true, replyCount: 7)), "7 replies")
        XCTAssertEqual(Noticeboard.repliesLabel(Notice(id: "n", repliesOpen: false, replyCount: 0)), "replies off")
        XCTAssertEqual(Noticeboard.repliesLabel(Notice(id: "n", repliesOpen: false, replyCount: 3)), "replies off · 3 kept")
    }

    func testTheRepliesHeading() {
        XCTAssertEqual(Noticeboard.repliesHeading(0), "No replies")
        XCTAssertEqual(Noticeboard.repliesHeading(1), "1 reply")
        XCTAssertEqual(Noticeboard.repliesHeading(12), "12 replies")
    }

    /// The notice's own count stands until the last page is in, so a long
    /// thread is not reported as its first twenty.
    func testTheReplyTotalDoesNotUnderstateALongThread() {
        let notice = Notice(id: "n", replyCount: 45)
        XCTAssertEqual(Noticeboard.replyTotal(notice: notice, loaded: 20, allLoaded: false), 45)
        XCTAssertEqual(Noticeboard.replyTotal(notice: notice, loaded: 46, allLoaded: false), 46)
        XCTAssertEqual(Noticeboard.replyTotal(notice: notice, loaded: 44, allLoaded: true), 44, "the rows are the truth once all are in")
    }

    func testANameOrWhatIsLeftOfOne() {
        XCTAssertEqual(Noticeboard.author(displayName: "Rowan Hale", username: "rowan"), "Rowan Hale")
        XCTAssertEqual(Noticeboard.author(displayName: "  ", username: "rowan"), "rowan")
        XCTAssertEqual(Noticeboard.author(displayName: "", username: ""), "Deleted account")
    }

    // MARK: Paging

    /// A reply posted here is appended at once; the next page, whose cursor
    /// is the last row loaded, then hands the same reply back.
    func testAPageIsJoinedWithoutASecondCopy() {
        let loaded = [NoticeReply(id: "r1"), NoticeReply(id: "r2"), NoticeReply(id: "r9")]
        let next = [NoticeReply(id: "r3"), NoticeReply(id: "r9")]
        XCTAssertEqual(Noticeboard.appending(next, to: loaded).map(\.id), ["r1", "r2", "r9", "r3"])
    }

    func testThePageQuery() {
        XCTAssertEqual(PatchworkAPI.pageQuery(after: nil), [URLQueryItem(name: "limit", value: "20")])
        XCTAssertEqual(PatchworkAPI.pageQuery(after: ""), [URLQueryItem(name: "limit", value: "20")])
        XCTAssertEqual(PatchworkAPI.pageQuery(after: "019f-n"),
                       [URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "after", value: "019f-n")])
    }

    // MARK: Rights

    /// A reply is removed by its author or a patch admin. The notice's
    /// author has no say over other people's replies, and nor does a member.
    func testWhoRemovesAReply() {
        let reply = NoticeReply(id: "r", authorId: "u2")
        XCTAssertTrue(Noticeboard.canRemove(reply, me: "u2", standing: .active(.member)))
        XCTAssertTrue(Noticeboard.canRemove(reply, me: "u1", standing: .active(.admin)))
        XCTAssertFalse(Noticeboard.canRemove(reply, me: "u1", standing: .active(.member)))
        XCTAssertFalse(Noticeboard.canRemove(reply, me: nil, standing: .active(.admin)))
    }

    func testReportingIsForSomebodyElsesWords() {
        XCTAssertTrue(Noticeboard.canReport(authorId: "u2", me: "u1"))
        XCTAssertFalse(Noticeboard.canReport(authorId: "u1", me: "u1"))
        XCTAssertFalse(Noticeboard.canReport(authorId: "u2", me: nil))
    }

    // MARK: The server's checks

    /// `validateNotice`, in its order and its words.
    func testANoticeIsCheckedInTheServersOrder() {
        XCTAssertEqual(Noticeboard.problem(NoticeDraft(title: "   ")), "a notice needs a title")
        XCTAssertEqual(Noticeboard.problem(NoticeDraft(title: String(repeating: "a", count: 141))), "keep the title under 140 characters")
        XCTAssertNil(Noticeboard.problem(NoticeDraft(title: String(repeating: "a", count: 140))))
        XCTAssertEqual(Noticeboard.problem(NoticeDraft(title: "T", body: String(repeating: "b", count: 20_001))), "that notice is too long")
        XCTAssertNil(Noticeboard.problem(NoticeDraft(title: "T", body: "")), "a notice may be a title alone")
        XCTAssertEqual(Noticeboard.problem(NoticeDraft(title: "T", imageURL: "http://example.org/a.png", imageAlt: "A")),
                       "the image address has to start with https://")
        XCTAssertEqual(Noticeboard.problem(NoticeDraft(title: "T", imageURL: "https://example.org/a.png")),
                       "add a short description of the image, so it still says something if it fails to load")
        XCTAssertNil(Noticeboard.problem(NoticeDraft(title: "T", imageURL: "https://example.org/a.png", imageAlt: "A flyer")))
        // The title is checked first, whatever else is wrong.
        XCTAssertEqual(Noticeboard.problem(NoticeDraft(title: "", imageURL: "nope")), "a notice needs a title")
    }

    /// The limits are bytes, as Go counts them: thirty-six emoji are 144.
    func testLengthsAreBytes() {
        XCTAssertEqual(Noticeboard.problem(NoticeDraft(title: String(repeating: "🧵", count: 36))), "keep the title under 140 characters")
        XCTAssertNil(Noticeboard.problem(NoticeDraft(title: String(repeating: "🧵", count: 35))))
    }

    func testAReplyNeedsABodyUnderTheLimit() {
        XCTAssertEqual(Noticeboard.replyProblem("  \n "), "a reply needs a body under 5000 characters")
        XCTAssertEqual(Noticeboard.replyProblem(String(repeating: "r", count: 5_001)), "a reply needs a body under 5000 characters")
        XCTAssertNil(Noticeboard.replyProblem(String(repeating: "r", count: 5_000)))
    }

    // MARK: What a write sends

    func testPuttingUpSendsEveryFieldTrimmed() throws {
        let draft = NoticeDraft(title: "  Kiln  ", body: " Out of action\n", imageURL: " https://example.org/k.png ",
                                imageAlt: " The kiln ", repliesOpen: false, tellMembers: true)
        XCTAssertEqual(try json(NoticeBody(draft)),
                       #"{"body":"Out of action","image_alt":"The kiln","image_url":"https:\/\/example.org\/k.png","replies_open":false,"tell_members":true,"title":"Kiln"}"#)
    }

    /// A description typed and then orphaned by clearing the address does
    /// not travel: the field is hidden, and what it held is not sent.
    func testADescriptionWithNoImageIsNotSent() throws {
        let draft = NoticeDraft(title: "Kiln", imageURL: "  ", imageAlt: "The kiln")
        XCTAssertEqual(NoticeBody(draft).imageAlt, "")
        XCTAssertEqual(NoticeBody(draft).imageUrl, "")
    }

    /// An edit is the four things an author may rewrite. `replies_open` is
    /// a different right and never rides along, or an admin's switch on
    /// somebody else's notice would be refused as an edit.
    func testAnEditAndTheSwitchAreSeparateRequests() throws {
        let edit = try json(NoticeEditBody(NoticeDraft(editing: Notice(id: "n", title: "Kiln", body: "Fixed", repliesOpen: false))))
        XCTAssertEqual(edit, #"{"body":"Fixed","image_alt":"","image_url":"","title":"Kiln"}"#)
        XCTAssertFalse(edit.contains("replies_open"))
        XCTAssertFalse(edit.contains("tell_members"))
        XCTAssertEqual(try json(RepliesSwitchBody(repliesOpen: false)), #"{"replies_open":false}"#)
    }

    func testAReportNamesItsKind() throws {
        XCTAssertEqual(try json(ReportBody(entityType: .reply, entityId: "r1", reason: "Spam or scam", details: "")),
                       #"{"details":"","entity_id":"r1","entity_type":"reply","reason":"Spam or scam"}"#)
        XCTAssertEqual(Noticeboard.reportReasons.first, "Harassment or intimidation")
        XCTAssertEqual(Noticeboard.reportReasons.count, 7)
        XCTAssertTrue(Noticeboard.reportDestination.contains("this patch’s admins"), "not the quilt's panel")
    }

    func testWhatIsBeingReportedIsNamed() {
        XCTAssertEqual(ReportTarget(kind: .notice, id: "n", subject: "Kiln").named, "“Kiln”")
        XCTAssertEqual(ReportTarget(kind: .notice, id: "n", subject: " ").named, "this notice")
        XCTAssertEqual(ReportTarget(kind: .reply, id: "r", subject: "").named, "this reply")
        XCTAssertEqual(ReportTarget(kind: .reply, id: "r", subject: "").heading, "Report this reply")
    }

    // MARK: What a write says afterwards

    func testTheSentencesAfterAnAct() {
        XCTAssertEqual(Noticeboard.putUpLine(toldMembers: false), "Notice put up")
        XCTAssertEqual(Noticeboard.putUpLine(toldMembers: true), "Notice put up and members told")
        XCTAssertEqual(Noticeboard.repliesSwitchLine(open: true), "Replies are on")
        XCTAssertEqual(Noticeboard.repliesSwitchLine(open: false), "Replies are off. Existing replies stay.")
        XCTAssertNil(Noticeboard.takeDownMessage(replies: 0))
        XCTAssertEqual(Noticeboard.takeDownMessage(replies: 1), "Its 1 reply goes with it.")
        XCTAssertEqual(Noticeboard.takeDownMessage(replies: 4), "Its 4 replies go with it.")
    }

    // MARK: Line breaks

    /// A notice is typed into a box, and the web renders it with
    /// `breaks: true`: a single return is a line of its own. A document
    /// keeps markdown's own rule, where it is a space.
    func testASingleReturnIsALineInANotice() {
        let typed = "12 Example Street\nSide door\n\nFrom six."
        XCTAssertEqual(Markdown.blocks(typed, hardBreaks: true), [.paragraph("12 Example Street\nSide door"), .paragraph("From six.")])
        XCTAssertEqual(Markdown.blocks(typed), [.paragraph("12 Example Street Side door"), .paragraph("From six.")])
        XCTAssertEqual(String(Markdown.inline("12 Example Street\nSide door").characters), "12 Example Street\nSide door",
                       "the inline run keeps the break it is handed")
    }
}
