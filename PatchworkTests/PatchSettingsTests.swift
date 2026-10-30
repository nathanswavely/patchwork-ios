// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// The rest of a patch admin's tools as values: the report queue's decoding,
/// acts and words, the noticeboard's two settings, which role changes are
/// offered under which rules, and exactly what an edit of the patch sends.
final class PatchSettingsTests: XCTestCase {
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
    private func patch(_ body: String) throws -> Patch {
        try decoder().decode(Patch.self, from: Data(body.utf8))
    }

    // MARK: The report queue

    func testAReportDecodesWithWhatItIsAboutQuoted() throws {
        let body = """
        {"items":[{"id":"r1","reporter_id":"u-juno","entity_type":"reply","entity_id":"rep-9","reason":"Spam or scam",
        "details":"Third time.","status":"pending","resolution_note":"","created_at":"2026-10-16T10:00:00Z",
        "updated_at":"2026-10-16T10:00:00Z","node_id":"n7","reporter_name":"Juno Park",
        "target":"Buy my DVDs","notice_id":"n-4","gone":false},
        {"id":"r2","entity_type":"notice","entity_id":"n-0","reason":"Something else","status":"pending","gone":true}],
        "next_cursor":"r2"}
        """
        let page = try decoder().decode(NoticeReportPage.self, from: Data(body.utf8))
        XCTAssertEqual(page.items.count, 2)
        let reply = page.items[0]
        XCTAssertEqual(reply.thing, "reply")
        XCTAssertEqual(reply.noticeId, "n-4", "a reported reply opens the notice it sits under")
        XCTAssertEqual(reply.target, "Buy my DVDs")
        XCTAssertEqual(reply.reporterName, "Juno Park")
        XCTAssertFalse(reply.gone)
        XCTAssertTrue(page.items[1].gone)
        XCTAssertEqual(page.items[1].details, "", "an absent field is empty, not a failure")
        XCTAssertEqual(page.nextCursor, "r2")
        let now = PatchworkEvent.parseDate("2026-10-16T13:00:00Z")!
        XCTAssertTrue(NoticeReports.head(reply, now: now).hasPrefix("Reply · "))
        XCTAssertTrue(NoticeReports.head(reply, now: now).hasSuffix("reported by Juno Park"))
    }

    func testSomethingAlreadyTakenDownCanOnlyBeDismissed() {
        XCTAssertEqual(NoticeReports.actions(for: NoticeReport(id: "r", gone: false)), [.dismiss, .remove, .closeReplies])
        XCTAssertEqual(NoticeReports.actions(for: NoticeReport(id: "r", gone: true)), [.dismiss], "the web offers nothing else")
    }

    func testTheActSendsTheServersWordAndATrimmedNote() throws {
        XCTAssertEqual(try json(NoticeReports.body(.closeReplies, note: "  cooling off  ")),
                       #"{"action":"close_replies","resolution_note":"cooling off"}"#)
        XCTAssertEqual(try json(NoticeReports.body(.dismiss)), #"{"action":"dismiss","resolution_note":""}"#,
                       "the note travels empty, as the web sends it")
        XCTAssertEqual(try json(NoticeReports.body(.remove)), #"{"action":"remove","resolution_note":""}"#)
        let query = NoticeReports.query(.resolved, after: "r9")
        XCTAssertEqual(query.map(\.name), ["status", "limit", "after"])
        XCTAssertEqual(query.first?.value, "resolved")
    }

    func testTheQueueIsSaidInTheWebsWords() {
        XCTAssertEqual(NoticeReports.Action.dismiss.title("notice"), "Dismiss, leave it up")
        XCTAssertEqual(NoticeReports.Action.remove.title("reply"), "Remove the reply")
        XCTAssertEqual(NoticeReports.Action.closeReplies.title("reply"), "Switch replies off on the notice")
        XCTAssertEqual(NoticeReports.Status.dismissed.empty, "No dismissed reports.")
        XCTAssertEqual(NoticeReports.askLabel(1, more: false), "1 report to review")
        XCTAssertEqual(NoticeReports.askLabel(3, more: false), "3 reports to review")
        XCTAssertEqual(NoticeReports.askLabel(20, more: true), "20+ reports to review", "a paged queue has no total")
        XCTAssertTrue(NoticeReports.Action.remove.destructive)
        XCTAssertFalse(NoticeReports.Action.closeReplies.destructive)
    }

    func testTheSettingsLinkOpensTheQueue() {
        XCTAssertEqual(NotificationLink.route("/patches/film-club/settings/noticeboard"), .noticeReports(slug: "film-club"))
        XCTAssertEqual(NotificationLink.route("/patches/film-club/settings/sources"), .website(path: "/patches/film-club/settings/sources"))
    }

    // MARK: The noticeboard's settings

    func testEachSettingSavesItselfAlone() throws {
        XCTAssertEqual(try json(NoticeboardSettings.body(posting: .admins)), #"{"notice_posting":"admins"}"#)
        XCTAssertEqual(try json(NoticeboardSettings.body(repliesDefault: false)), #"{"notice_replies_default":false}"#)
        XCTAssertEqual(NoticeboardSettings.saved(posting: .admins), "Only admins put up notices now")
        XCTAssertEqual(NoticeboardSettings.saved(posting: .members), "Members can put up notices")
        XCTAssertEqual(NoticeboardSettings.saved(repliesDefault: false), "New notices start with replies off")
        XCTAssertEqual(NoticeboardSettings.Posting.admins.title, "Admins only")
    }

    // MARK: Roles

    private let member = PatchMember(id: "m2", userId: "u2", username: "lena", displayName: "Lena", avatarUrl: nil, role: "member", status: "active")
    private let admin = PatchMember(id: "m3", userId: "u3", username: "juno", displayName: nil, avatarUrl: nil, role: "admin")
    private let follower = PatchMember(id: "m4", userId: "u4", username: "rue", displayName: nil, avatarUrl: nil, role: "follower")
    private let invited = PatchMember(id: "m5", userId: "u5", username: "ivy", displayName: nil, avatarUrl: nil, role: "member", status: "invited")

    func testPromotionIsOfferedOnlyWhereTheServerWouldHonourIt() {
        let maintainer = GovernanceRules(leadershipModel: "maintainer", leadershipVenue: "patchwork")
        XCTAssertTrue(RoleChange.promotionAllowed(maintainer))
        XCTAssertFalse(RoleChange.promotionAllowed(GovernanceRules(leadershipModel: "meritocratic")), "ratifies admins by proposal")
        XCTAssertFalse(RoleChange.promotionAllowed(GovernanceRules(leadershipModel: "elected")), "elects its council")
        XCTAssertFalse(RoleChange.promotionAllowed(GovernanceRules(leadershipModel: "maintainer", leadershipVenue: "elsewhere")),
                       "chooses its admins elsewhere")
        XCTAssertFalse(RoleChange.promotionAllowed(nil), "rules that could not be read offer nothing")
    }

    func testTheActsOnARowFollowItsRoleAndTheRules() {
        let maintainer = GovernanceRules(leadershipModel: "maintainer")
        let elected = GovernanceRules(leadershipModel: "elected")
        XCTAssertEqual(RoleChange.offered(member, runs: true, rules: maintainer), [.promote])
        XCTAssertEqual(RoleChange.offered(member, runs: true, rules: elected), [])
        XCTAssertEqual(RoleChange.offered(admin, runs: true, rules: elected), [.demote], "demotion is untouched by the rules")
        XCTAssertEqual(RoleChange.offered(follower, runs: true, rules: maintainer), [], "a follower joins; they are not promoted")
        XCTAssertEqual(RoleChange.offered(invited, runs: true, rules: maintainer), [], "they have not accepted yet")
        XCTAssertEqual(RoleChange.offered(member, runs: false, rules: maintainer), [], "only the patch's admin")
    }

    func testARoleChangeSendsOnlyTheRole() throws {
        XCTAssertEqual(try json(RoleChange.promote.body), #"{"role":"admin"}"#)
        XCTAssertEqual(try json(RoleChange.demote.body), #"{"role":"member"}"#)
        XCTAssertEqual(member.withRole("admin").role, "admin")
        XCTAssertEqual(member.withRole("admin").userId, "u2")
        XCTAssertTrue(RoleChange.demote.consequence("You", isMe: true).hasPrefix("You stop being an admin"))
        XCTAssertTrue(RoleChange.promote.consequence("Lena", isMe: false).contains("aren’t notified"))
    }

    func testTheNoteSaysWhyAdminsAreNotMadeHere() throws {
        let overview = { (rules: String, seats: String, opens: String) throws -> GovernanceOverview in
            try self.decoder().decode(GovernanceOverview.self, from: Data(#"{"rules":\#(rules),"seats":\#(seats),"next_contest_opens":"\#(opens)"}"#.utf8))
        }
        XCTAssertTrue(RoleChange.note(try overview(#"{"leadership_model":"meritocratic"}"#, "[]", "")).contains("ratifies admins by proposal"))
        XCTAssertTrue(RoleChange.note(try overview(#"{"leadership_model":"maintainer","leadership_venue":"elsewhere"}"#, "[]", ""))
            .contains("chooses its admins elsewhere"))
        XCTAssertTrue(RoleChange.note(try overview(#"{"leadership_model":"elected"}"#, #"[{"id":"s1","vacant":true}]"#, ""))
            .contains("1 seat is vacant"))
        XCTAssertTrue(RoleChange.note(try overview(#"{"leadership_model":"elected"}"#, #"[{"id":"s1","vacant":false}]"#, ""))
            .contains("no election is scheduled"))
        XCTAssertFalse(RoleChange.note(try overview(#"{"leadership_model":"maintainer"}"#, "[]", "")).contains("not made here"))
    }

    // MARK: Editing the patch

    private let filmClub = """
    {"id":"extra-7","name":"Film Club","slug":"extra-7","description":"Screenings.","tags":["music"],
    "address":"1 Main St","latitude":40.0,"longitude":-76.3,"website":"https://film.example.org",
    "links":[{"url":"https://a.example.org","label":"A"}],"visibility":"public","timezone":"America/New_York",
    "accept_event_suggestions":true,"image_url":"","image_alt":"",
    "appearance":{"palette":"anthem","block":"ohioStar","rotation":90}}
    """

    func testNothingChangedIsNothingSent() throws {
        let original = PatchDraft(editing: try patch(filmClub))
        XCTAssertTrue(original.changes(from: original).isEmpty)
        XCTAssertEqual(try json(original.changes(from: original)), "{}")
        XCTAssertEqual(original.visibility, "public")
        XCTAssertTrue(original.acceptSuggestions)
        XCTAssertEqual(original.timezone, "America/New_York")
        XCTAssertEqual(original.links.count, 1)
    }

    func testOnlyTheChangedFieldsTravel() throws {
        let original = PatchDraft(editing: try patch(filmClub))
        var draft = original
        draft.name = "  Film Society "
        draft.description = ""
        draft.acceptSuggestions = false
        XCTAssertEqual(try json(draft.changes(from: original)),
                       #"{"accept_event_suggestions":false,"description":"","name":"Film Society"}"#,
                       "a cleared description is sent empty, which is how the server clears it")
    }

    func testAPointTakenOffTheMapIsSentAsNull() throws {
        let original = PatchDraft(editing: try patch(filmClub))
        var draft = original
        draft.point = nil
        XCTAssertEqual(try json(draft.changes(from: original)), #"{"latitude":null,"longitude":null}"#)
        draft.point = MapPoint(latitude: 40.5, longitude: -76.5)
        XCTAssertEqual(try json(draft.changes(from: original)), #"{"latitude":40.5,"longitude":-76.5}"#)
    }

    func testTheTileTravelsOnlyWhenChangedAndNeverOverADraftedOne() throws {
        let original = PatchDraft(editing: try patch(filmClub))
        var draft = original
        draft.rotate()
        let body = draft.changes(from: original)
        XCTAssertEqual(body.appearance?.rotation, 180)
        XCTAssertEqual(body.appearance?.palette, "anthem")
        XCTAssertNil(draft.changes(from: original, appearanceLocked: true).appearance, "a drafted block is the website's")
        let drafted = try patch(#"{"id":"x","name":"X","slug":"x","appearance":{"block":{"grid":3,"colors":{"0,1":[1]}},"rotation":0}}"#)
        XCTAssertTrue(PatchEditing.appearanceLocked(drafted.appearance))
        let bundled = try patch(##"{"id":"y","name":"Y","slug":"y","appearance":{"block":"ohioStar","bundle":["#111111","#222222"]}}"##)
        XCTAssertTrue(PatchEditing.appearanceLocked(bundled.appearance))
        XCTAssertFalse(PatchEditing.appearanceLocked(try patch(filmClub).appearance))
        XCTAssertFalse(PatchEditing.appearanceLocked(nil), "an unset tile is the form's to choose")
    }

    func testTagsTheImagePairAndLinksTravelWhole() throws {
        let original = PatchDraft(editing: try patch(filmClub))
        var draft = original
        draft.suggestTags = ["cinema"]
        XCTAssertEqual(try json(draft.changes(from: original)), #"{"suggest_tags":["cinema"],"tags":["music"]}"#,
                       "a suggestion carries the whole set, as the web sends it")
        draft = original
        draft.imageURL = "https://img.example.org/a.jpg"
        XCTAssertEqual(try json(draft.changes(from: original)), #"{"image_alt":"","image_url":"https:\/\/img.example.org\/a.jpg"}"#)
        XCTAssertEqual(draft.editProblem(), "Add a short description of the image, so it still says something if it fails to load")
        draft.imageAlt = "The marquee"
        XCTAssertNil(draft.editProblem())
        draft = original
        draft.links.append(PatchLink(url: " https://b.example.org ", label: ""))
        draft.links.append(PatchLink(url: "  ", label: "nothing"))
        XCTAssertEqual(draft.changes(from: original).links, [PatchLink(url: "https://a.example.org", label: "A"),
                                                             PatchLink(url: "https://b.example.org", label: "")])
    }

    func testAZoneIsAPlaceAndAMoveAsksAboutTheEvents() throws {
        XCTAssertNil(PatchEditing.zoneProblem(""), "empty follows the quilt")
        XCTAssertNil(PatchEditing.zoneProblem("Europe/Berlin"))
        XCTAssertNotNil(PatchEditing.zoneProblem("EST"), "a fixed offset is not a place")
        XCTAssertNotNil(PatchEditing.zoneProblem("Mars/Olympus"))
        let original = PatchDraft(editing: try patch(filmClub))
        var draft = original
        draft.timezone = "Europe/Berlin"
        var body = draft.changes(from: original)
        body.timezoneEvents = "keep_clock"
        XCTAssertEqual(try json(body), #"{"timezone":"Europe\/Berlin","timezone_events":"keep_clock"}"#)
        let sentence = "4 events follow this patch's timezone and would read as a different time."
        XCTAssertEqual(PatchEditing.zoneEventCount(sentence), 4)
        XCTAssertEqual(PatchEditing.keepClockTitle(1), "Keep the listed time")
        XCTAssertEqual(PatchEditing.keepInstantTitle(4), "Leave the events where they are")
    }
}
