// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// Posting an event, or suggesting one, checked as values.
///
/// The posting right is the web's `eventPostingRight` (web
/// `patchWorkspace.js`), and the cases here are the web's own from
/// `patch-profile-window.test.js` and `event-posting-doors.test.js`, plus a
/// case for every branch they leave implicit. The door has to say what
/// posting will do before the form is filled, so a disagreement with the
/// server's `CreateEvent` is a door that lies.
final class EventPostingTests: XCTestCase {
    private typealias Right = EventPosting.Right

    // MARK: - The posting right, the web's cases

    func testNothingForTheSignedOutOrTheBanned() {
        XCTAssertEqual(EventPosting.right(signedIn: false), .none)
        XCTAssertEqual(EventPosting.right(signedIn: true, isBanned: true), .none)
        // Banned outranks every right a reader might otherwise hold.
        XCTAssertEqual(EventPosting.right(signedIn: true, isInstanceAdmin: true, isBanned: true), .none)
        XCTAssertEqual(EventPosting.right(signedIn: true, isMemberOrAdmin: true, isBanned: true), .none)
    }

    func testTheInstanceAdminAndTrustedContributorsPostDirectlyToAnUnclaimedPatch() {
        XCTAssertEqual(EventPosting.right(signedIn: true, isInstanceAdmin: true, isUnclaimed: true), .direct)
        XCTAssertEqual(EventPosting.right(signedIn: true, viewerTrusted: true, isUnclaimed: true), .direct)
    }

    func testEveryoneElseOnAnUnclaimedPatchGoesThroughReview() {
        XCTAssertEqual(EventPosting.right(signedIn: true, isUnclaimed: true), .suggest)
        // The patch's own switch is a claimed patch's; nobody runs this one.
        XCTAssertEqual(EventPosting.right(signedIn: true, isUnclaimed: true, acceptSuggestions: false), .suggest)
    }

    func testTheInstanceWideSubmissionsSwitch() {
        XCTAssertEqual(EventPosting.right(signedIn: true, isUnclaimed: true, submissionsEnabled: false), .none)
        XCTAssertEqual(EventPosting.right(signedIn: true, submissionsEnabled: false, acceptSuggestions: true), .none)
        // It gates suggestions, never a member's own post.
        XCTAssertEqual(EventPosting.right(signedIn: true, isMemberOrAdmin: true, submissionsEnabled: false), .direct)
        XCTAssertEqual(EventPosting.right(signedIn: true, viewerTrusted: true, isUnclaimed: true, submissionsEnabled: false), .direct)
    }

    func testMembersAndAdminsPostDirectlyToAnActivePatch() {
        XCTAssertEqual(EventPosting.right(signedIn: true, isMemberOrAdmin: true), .direct)
        XCTAssertEqual(EventPosting.right(signedIn: true, isInstanceAdmin: true), .direct)
    }

    /// Following is frictionless and grants no write rights: the server
    /// once counted a follower as a member and published their event.
    func testAFollowerIsAVisitorNotAMember() {
        XCTAssertFalse(EventPosting.isMemberOrAdmin(.active(.follower)))
        XCTAssertFalse(EventPosting.isMemberOrAdmin(.pending), "a request nobody has answered is not a membership")
        XCTAssertFalse(EventPosting.isMemberOrAdmin(nil))
        XCTAssertTrue(EventPosting.isMemberOrAdmin(.active(.member)))
        XCTAssertTrue(EventPosting.isMemberOrAdmin(.active(.admin)))

        let follower = EventPosting.isMemberOrAdmin(.active(.follower))
        XCTAssertEqual(EventPosting.right(signedIn: true, isMemberOrAdmin: follower, submissionsEnabled: true, acceptSuggestions: true), .suggest)
        XCTAssertEqual(EventPosting.right(signedIn: true, isMemberOrAdmin: follower, submissionsEnabled: true, acceptSuggestions: false), .none)
    }

    func testAStrangerMaySuggestOnlyWhereThePatchOptedIn() {
        XCTAssertEqual(EventPosting.right(signedIn: true, acceptSuggestions: true), .suggest)
        XCTAssertEqual(EventPosting.right(signedIn: true, acceptSuggestions: false), .none)
        XCTAssertEqual(EventPosting.right(signedIn: true), .none, "absent reads as no, as the web reads it")
    }

    /// Web ADR 090: a patch that has moved takes nothing from outside, and
    /// its own people still post, because the old home is still a record.
    func testAMovedPatchKeepsItsOwnAndRefusesStrangers() {
        XCTAssertEqual(EventPosting.right(signedIn: true, acceptSuggestions: true, hasMoved: true), .none)
        XCTAssertEqual(EventPosting.right(signedIn: true, isUnclaimed: true, hasMoved: true), .none)
        XCTAssertEqual(EventPosting.right(signedIn: true, viewerTrusted: true, isUnclaimed: true, hasMoved: true), .none,
                       "trust is not membership, and the web's rule reaches the move before it reaches trust")
        XCTAssertEqual(EventPosting.right(signedIn: true, isMemberOrAdmin: true, hasMoved: true), .direct)
        XCTAssertEqual(EventPosting.right(signedIn: true, isInstanceAdmin: true, hasMoved: true), .direct)
    }

    /// Trust reaches only unclaimed patches: on an active one a trusted
    /// contributor is a stranger like any other.
    func testTrustIsWorthNothingOnAClaimedPatch() {
        XCTAssertEqual(EventPosting.right(signedIn: true, viewerTrusted: true, acceptSuggestions: true), .suggest)
        XCTAssertEqual(EventPosting.right(signedIn: true, viewerTrusted: true, acceptSuggestions: false), .none)
    }

    func testTheDoorsWords() {
        XCTAssertEqual(Right.direct.doorLabel, "New event")
        XCTAssertEqual(Right.suggest.doorLabel, "Suggest an event")
        XCTAssertNil(Right.none.doorLabel)
    }

    // MARK: - The door

    private func door(signedIn: Bool = true, standing: Standing? = nil, unclaimed: Bool = false, accepts: Bool = false,
                      moved: Bool = false, submissions: Bool = true, admin: Bool = false, trusted: Bool = false,
                      banned: Bool = false) -> EventPosting.Door {
        EventPosting.door(signedIn: signedIn, isInstanceAdmin: admin, viewerTrusted: trusted, isUnclaimed: unclaimed,
                          standing: standing, isBanned: banned, submissionsEnabled: submissions,
                          acceptSuggestions: accepts, hasMoved: moved)
    }

    func testTheDoorForASignedInReader() {
        XCTAssertEqual(door(standing: .active(.member)), .form(.direct))
        XCTAssertEqual(door(standing: .active(.admin)), .form(.direct))
        XCTAssertEqual(door(standing: .active(.follower), accepts: true), .form(.suggest))
        XCTAssertEqual(door(standing: .active(.follower), accepts: false), .none)
        XCTAssertEqual(door(standing: .pending, accepts: true), .form(.suggest))
        XCTAssertEqual(door(admin: true), .form(.direct))
        XCTAssertEqual(door(unclaimed: true, trusted: true), .form(.direct))
        XCTAssertEqual(door(standing: .active(.member), banned: true), .none)
        XCTAssertEqual(door(standing: .active(.follower), accepts: true).label, "Suggest an event")
        XCTAssertEqual(door(standing: .active(.member)).label, "New event")
    }

    /// Signed out, the door is the sign-in sheet — but only where a
    /// stranger would be taken, so it never leads to a form that refuses.
    func testTheDoorForASignedOutReader() {
        XCTAssertEqual(door(signedIn: false, accepts: true), .signIn)
        XCTAssertEqual(door(signedIn: false, accepts: true).label, "Suggest an event")
        XCTAssertEqual(door(signedIn: false, unclaimed: true), .signIn)
        XCTAssertEqual(door(signedIn: false, accepts: false), .none)
        XCTAssertEqual(door(signedIn: false, accepts: true, moved: true), .none)
        XCTAssertEqual(door(signedIn: false, accepts: true, submissions: false), .none)
    }

    // MARK: - What a draft sends

    private let start = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21T14:13:20Z
    private func sent(_ body: EventBody) throws -> [String: Any] {
        let data = try JSONEncoder().encode(body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testABareSuggestionSendsOnlyWhatItHas() throws {
        var draft = EventDraft(start: start)
        draft.title = "  Open mic  "
        draft.description = "   "
        draft.tier = .members
        let body = try sent(draft.body(nodeId: "node-1", direct: false))
        XCTAssertEqual(body["node_id"] as? String, "node-1")
        XCTAssertEqual(body["title"] as? String, "Open mic", "trimmed")
        XCTAssertEqual(body["starts_at"] as? String, "2026-09-21T14:13:00.000Z", "an instant, to the minute, in the web's shape")
        XCTAssertEqual(Set(body.keys), ["node_id", "title", "starts_at"],
                       "empties, the end, the tier, a zone and recurrence are all absent")
    }

    func testADirectPostCarriesItsTierAndEverythingFilled() throws {
        var draft = EventDraft(start: start)
        draft.title = "Fix-it night"
        draft.description = " Bring the lamp. "
        draft.location = " 4 Mill Lane "
        draft.eventURL = " http://venue.example.org/fixit "
        draft.imageURL = " https://venue.example.org/flyer.jpg "
        draft.imageAlt = " A lamp, mid-repair "
        draft.hasEnd = true
        draft.endsAt = start.addingTimeInterval(3 * 3600)
        draft.tier = .followers
        let body = try sent(draft.body(nodeId: "node-1", direct: true))
        XCTAssertEqual(body["description"] as? String, "Bring the lamp.")
        XCTAssertEqual(body["location"] as? String, "4 Mill Lane")
        XCTAssertEqual(body["event_url"] as? String, "http://venue.example.org/fixit")
        XCTAssertEqual(body["image_url"] as? String, "https://venue.example.org/flyer.jpg")
        XCTAssertEqual(body["image_alt"] as? String, "A lamp, mid-repair")
        XCTAssertEqual(body["ends_at"] as? String, "2026-09-21T17:13:00.000Z")
        XCTAssertEqual(body["visibility"] as? String, "followers")
        XCTAssertNil(body["timezone"], "an event inherits its patch's zone")
        XCTAssertNil(body["recurrence"])
    }

    func testAPublicDirectPostStillSaysSo() throws {
        var draft = EventDraft(start: start)
        draft.title = "A"
        XCTAssertEqual(try sent(draft.body(nodeId: "n", direct: true))["visibility"] as? String, "public")
    }

    func testAnEndSwitchedOffIsNotSent() throws {
        var draft = EventDraft(start: start)
        draft.title = "A"
        draft.endsAt = start.addingTimeInterval(3600)
        XCTAssertNil(try sent(draft.body(nodeId: "n", direct: true))["ends_at"])
    }

    func testADescriptionWithNoPictureGoesNowhere() throws {
        var draft = EventDraft(start: start)
        draft.title = "A"
        draft.imageURL = "  "
        draft.imageAlt = "A flyer"
        let body = try sent(draft.body(nodeId: "n", direct: false))
        XCTAssertNil(body["image_url"])
        XCTAssertNil(body["image_alt"])
    }

    func testTheInstantDropsSecondsAndIsUTC() {
        let date = Date(timeIntervalSince1970: 1_790_000_059.9)
        XCTAssertEqual(EventPosting.instant(date), "2026-09-21T14:14:00.000Z")
    }

    // MARK: - The server's checks, in its words

    func testTheImageRuleMirrorsTheServer() {
        XCTAssertNil(EventPosting.imageProblem(url: "", alt: ""), "clearing is always allowed")
        XCTAssertNil(EventPosting.imageProblem(url: "  ", alt: "orphan"))
        XCTAssertNil(EventPosting.imageProblem(url: "https://a.example/f.jpg", alt: "A flyer"))
        XCTAssertEqual(EventPosting.imageProblem(url: "https://a.example/f.jpg", alt: " "),
                       "add a short description of the image, so it still says something if it fails to load")
        XCTAssertEqual(EventPosting.imageProblem(url: "http://a.example/f.jpg", alt: "A flyer"),
                       "the image address has to start with https://")
        XCTAssertEqual(EventPosting.imageProblem(url: "flyer.jpg", alt: "A flyer"), "that doesn't look like an image address")
        XCTAssertEqual(EventPosting.imageProblem(url: "https://a.example/" + String(repeating: "x", count: 2040), alt: "A"),
                       "that image address is too long")
        XCTAssertEqual(EventPosting.imageProblem(url: "https://a.example/f.jpg", alt: String(repeating: "é", count: 151)),
                       "keep the description under 300 characters", "bytes, as Go counts them")
        XCTAssertNil(EventPosting.imageProblem(url: "HTTPS://a.example/f.jpg", alt: "A"), "a scheme is not case-sensitive")
    }

    func testTheLinkRuleMirrorsTheServer() {
        XCTAssertNil(EventPosting.linkProblem(""))
        XCTAssertNil(EventPosting.linkProblem("https://tickets.example.org/show?id=4"))
        XCTAssertNil(EventPosting.linkProblem("http://venue.example.org"), "plain http is a link that works")
        let sentence = "that doesn't look like a link — it should start with https://"
        XCTAssertEqual(EventPosting.linkProblem("venue.example.org"), sentence)
        XCTAssertEqual(EventPosting.linkProblem("javascript:alert(1)"), sentence)
        XCTAssertEqual(EventPosting.linkProblem("ftp://files.example.org/x"), sentence)
        XCTAssertEqual(EventPosting.linkProblem("https://a.example/" + String(repeating: "x", count: 2040)), "that link is too long")
    }

    func testTheDraftChecksInTheServersOrder() {
        var draft = EventDraft(start: start)
        XCTAssertFalse(draft.ready)
        XCTAssertEqual(draft.problem(), "Title is required")
        draft.eventURL = "nope"
        draft.imageURL = "http://a.example/f.jpg"
        XCTAssertEqual(draft.problem(), "the image address has to start with https://", "the image first, as CreateEvent checks it")
        draft.imageURL = ""
        XCTAssertEqual(draft.problem(), "that doesn't look like a link — it should start with https://")
        draft.eventURL = ""
        draft.title = "A"
        XCTAssertTrue(draft.ready)
        XCTAssertNil(draft.problem())
    }

    func testAnEndIsAfterItsStart() {
        XCTAssertNil(EventPosting.endProblem(start: start, end: nil))
        XCTAssertNil(EventPosting.endProblem(start: start, end: start.addingTimeInterval(60)))
        XCTAssertEqual(EventPosting.endProblem(start: start, end: start), "The end has to be after the start.")
        XCTAssertEqual(EventPosting.endProblem(start: start, end: start.addingTimeInterval(-60)), "The end has to be after the start.")
        var draft = EventDraft(start: start)
        draft.title = "A"
        draft.hasEnd = true
        draft.endsAt = start
        XCTAssertEqual(draft.problem(), "The end has to be after the start.")
        draft.hasEnd = false
        XCTAssertNil(draft.problem(), "an end switched off is no end at all")
    }

    func testARefusalStartsWithACapital() {
        XCTAssertEqual(EventPosting.sentenceCased("this patch does not accept event suggestions"),
                       "This patch does not accept event suggestions")
        XCTAssertEqual(EventPosting.sentenceCased(""), "")
    }

    // MARK: - Tiers

    func testTheFollowersTierIsOfferedOnlyWithinThePatchsCeiling() {
        XCTAssertEqual(EventTier.offered(followersAllowed: true), [.public, .followers, .members])
        XCTAssertEqual(EventTier.offered(followersAllowed: false), [.public, .members])
        XCTAssertEqual(EventTier.offered(followersAllowed: true).map(\.label), ["Public", "Followers", "Members only"])
    }

    func testThePatchDecodesItsPostingFacts() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let json = #"{"node":{"id":"p","name":"A","slug":"a","timezone":"America/Chicago","accept_event_suggestions":true,"follower_permissions":{"events":false,"proposals":true,"charters":false,"members":true}},"is_unclaimed":false,"viewer_trusted":false}"#
        let response = try decoder.decode(PatchResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.node.timezone, "America/Chicago")
        XCTAssertEqual(response.node.acceptEventSuggestions, true)
        XCTAssertEqual(response.node.followerPermissions?.events, false)
        XCTAssertEqual(response.viewerTrusted, false)
        let bare = try decoder.decode(Patch.self, from: Data(#"{"id":"p","name":"A","slug":"a"}"#.utf8))
        XCTAssertNil(bare.acceptEventSuggestions)
        XCTAssertNil(bare.followerPermissions, "absent reads as allowed at the call site")
    }

    // MARK: - Reviewers, zones and the default start

    func testWhoReadsASuggestion() {
        XCTAssertEqual(EventPosting.reviewers(unclaimed: true), "quilt admins")
        XCTAssertEqual(EventPosting.reviewers(unclaimed: false), "patch admins")
    }

    func testTheFormIsWrittenInThePatchsZone() {
        XCTAssertEqual(EventPosting.zone(patchZone: "America/Chicago", quiltZone: "America/New_York").identifier, "America/Chicago")
        XCTAssertEqual(EventPosting.zone(patchZone: "", quiltZone: "America/New_York").identifier, "America/New_York",
                       "an empty patch zone inherits the quilt's")
        XCTAssertEqual(EventPosting.zone(patchZone: nil, quiltZone: nil), .current)
        XCTAssertEqual(EventPosting.zone(patchZone: "Not/AZone", quiltZone: "Europe/London").identifier, "Europe/London")
    }

    func testTheZoneIsSaidOnlyWhereItDiffers() throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let detroit = try XCTUnwrap(TimeZone(identifier: "America/Detroit"))
        let chicago = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        XCTAssertFalse(EventPosting.zoneDiffers(newYork, from: newYork, at: start))
        XCTAssertFalse(EventPosting.zoneDiffers(newYork, from: detroit, at: start), "two names, one clock")
        XCTAssertTrue(EventPosting.zoneDiffers(newYork, from: chicago, at: start))
        XCTAssertEqual(EventPosting.zoneNote(newYork), "Times are in America/New York, this patch’s timezone.")
    }

    func testTheDefaultStartIsTheNextWholeHourOnThePatchsClock() throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let now = Date(timeIntervalSince1970: 1_790_000_000) // 10:13:20 in New York
        let next = EventPosting.defaultStart(now: now, zone: newYork)
        XCTAssertEqual(EventPosting.instant(next), "2026-09-21T15:00:00.000Z")
        XCTAssertGreaterThan(next, now, "a default a form can be sent with")
        // A zone half an hour off the hour keeps its own whole hours.
        let kolkata = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        XCTAssertEqual(EventPosting.instant(EventPosting.defaultStart(now: now, zone: kolkata)), "2026-09-21T14:30:00.000Z")
        // The draft ends two hours later when an end is asked for.
        XCTAssertEqual(EventDraft(start: next).endsAt, next.addingTimeInterval(2 * 3600))
    }

    // MARK: - A moved patch's refusal

    func testAMovedPatchsRefusalKeepsItsAddress() {
        let body = #"{"error":"this patch has moved. Take part at its new home instead.","moved_to":"https://elsewhere.example.org/patches/a"}"#
        let error = APIError.from(status: 403, data: Data(body.utf8))
        XCTAssertEqual(error.movedTo, "https://elsewhere.example.org/patches/a")
        XCTAssertEqual(SignInModel.sentence(error), "this patch has moved. Take part at its new home instead.")
        XCTAssertNil(error.code)
        XCTAssertFalse(StepUp.needsStepUp(error))
        // A plain refusal is still a plain one.
        XCTAssertEqual(APIError.from(status: 403, data: Data(#"{"error":"this patch does not accept event suggestions"}"#.utf8)),
                       .message("this patch does not accept event suggestions", status: 403))
    }
}
