// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// The settings half of People, checked as values: the contact card's
/// payloads and draft, My Patches' rows and rules, and the notification
/// matrix — its channel map read under the client's own decoder, and a save
/// that carries only what changed.
final class PeopleSettingsTests: XCTestCase {
    /// The decoder `PatchworkAPI` reads every answer with.
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    private func encoded(_ value: some Encodable) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any])
    }

    // MARK: The contact card

    func testTheOwnersCardDecodesWithItsCountsAndOmittedFields() throws {
        let json = #"{"items":[{"id":"c1","kind":"phone","value":"+1 717 555 0100","label":"work","position":0,"shared_with":2},{"id":"c2","kind":"email","value":"reach@example.com","position":1},{"id":"c3","kind":"fax","value":"555","position":2}]}"#
        let items = try decode(ContactItemList.self, json).items
        XCTAssertEqual(items.map(\.id), ["c1", "c2", "c3"])
        XCTAssertEqual(items[0].sharingLine, "Shared with 2 patches")
        XCTAssertEqual(items[1].label, nil, "an empty label is omitted by the server")
        XCTAssertEqual(items[1].sharingLine, "Not shared with any patch", "shared_with is omitted at zero")
        XCTAssertEqual(items[0].word, "Phone")
        XCTAssertEqual(items[2].word, "fax", "an unknown kind falls back to its own name")
        XCTAssertNil(items[2].contactKind)
        XCTAssertEqual(try decode(ContactItemList.self, "{}").items, [], "no items key is an empty card")
    }

    func testAPatchsSharingViewDecodesTheFlagsAndWhetherItMayShare() throws {
        let json = #"{"items":[{"id":"c1","kind":"phone","value":"1","position":0,"shared":true},{"id":"c2","kind":"note","value":"Text first","position":1,"shared":false}],"can_share":true}"#
        let shares = try decode(ContactShares.self, json)
        XCTAssertTrue(shares.canShare)
        XCTAssertEqual(shares.sharedIDs, ["c1"])
        let follower = try decode(ContactShares.self, #"{"items":[],"can_share":false}"#)
        XCTAssertFalse(follower.canShare)
    }

    func testTheShareSetAndTheItemBodyTravelInTheServersSpelling() throws {
        XCTAssertEqual(try encoded(ContactShareSet(itemIds: ["a", "b"])) as NSDictionary, ["item_ids": ["a", "b"]] as NSDictionary)
        var draft = ContactDraft(kind: .handle, value: "  @sam on Signal ", label: "  ")
        XCTAssertEqual(try encoded(draft.body) as NSDictionary,
                       ["kind": "handle", "value": "@sam on Signal", "label": ""] as NSDictionary,
                       "trimmed, and an emptied label still travels so it is emptied")
        draft.value = "   "
        XCTAssertFalse(draft.hasValue, "an item needs a value")
        XCTAssertEqual(try decode(UnshareAnswer.self, #"{"unshared_from":3}"#).unsharedFrom, 3)
    }

    func testAnEditDiffersOnlyWhenItSaysSomethingNew() throws {
        let item = try decode(ContactItem.self, #"{"id":"c1","kind":"phone","value":"+1 555","position":0}"#)
        var draft = ContactDraft(item: item)
        XCTAssertFalse(draft.differs(from: item))
        draft.value = "+1 555 "
        XCTAssertFalse(draft.differs(from: item), "whitespace is not an edit")
        draft.label = "home"
        XCTAssertTrue(draft.differs(from: item))
    }

    func testAFieldStopsAtItsLimitInTheBytesTheServerCounts() {
        XCTAssertEqual(ContactDraft.clamp("abcdef", to: 4), "abcd")
        XCTAssertEqual(ContactDraft.clamp("abc", to: 4), "abc")
        // "é" is two bytes: a third would be five.
        XCTAssertEqual(ContactDraft.clamp("ééé", to: 5), "éé")
        XCTAssertEqual(ContactKind.phone.limit, 60)
        XCTAssertEqual(ContactKind.note.limit, 200)
    }

    func testTheCardsSentences() {
        XCTAssertEqual(ContactWording.reach(0), "Not reachable")
        XCTAssertEqual(ContactWording.reach(1), "Reachable by 1")
        XCTAssertEqual(ContactWording.shareOutcome(patch: "Repair Cafe", count: 0), "Repair Cafe can no longer reach you")
        XCTAssertEqual(ContactWording.shareOutcome(patch: "Repair Cafe", count: 1), "Repair Cafe can reach you by 1 item")
        XCTAssertEqual(ContactWording.shareOutcome(patch: "Repair Cafe", count: 3), "Repair Cafe can reach you by 3 items")
        XCTAssertEqual(ContactWording.unshared(1), "No longer shown to 1 patch")
        XCTAssertEqual(ContactWording.unshared(2), "No longer shown to 2 patches")
    }

    // MARK: My Patches

    func testAMembershipRowCarriesItsVisibilityAndSharingCount() throws {
        let json = #"{"items":[{"id":"m1","user_id":"u","node_id":"n1","role":"member","status":"active","visible":false,"share_contact":false,"joined_at":"2026-09-01T10:00:00Z","node_name":"Repair Cafe","node_slug":"repair","node_description":"","node_visibility":"public","membership_policy":"open","node_status":"active","contact_items_shared":2}],"next_cursor":""}"#
        let row = try XCTUnwrap(decode(MembershipPage.self, json).items.first)
        XCTAssertEqual(row.visible, false)
        XCTAssertEqual(row.contactItemsShared, 2)
        XCTAssertEqual(MyPatchesRules.summary(row), "Hidden · Reachable by 2")
    }

    func testClaimsDecodeAndKnowWhenTheyAreReady() throws {
        let json = #"{"items":[{"id":"k1","method":"email","status":"approved","created_at":"2026-09-01 10:00:00","setup_expires_at":"2026-09-15 10:00:00","node_slug":"river","node_name":"River Walkers"},{"id":"k2","method":"dns","status":"pending","created_at":"2026-09-02 10:00:00","node_slug":"bikes","node_name":""}]}"#
        let claims = try decode(ClaimList.self, json).items
        XCTAssertTrue(claims[0].ready)
        XCTAssertNotNil(MyPatchesRules.day(claims[0].setupExpiresAt), "SQLite's own time format reads as a day")
        XCTAssertFalse(claims[1].ready)
        XCTAssertEqual(claims[1].name, "bikes", "a blank name falls back to the address")
    }

    func testVisibilityTravelsAsOneFieldAndIsReadBack() throws {
        XCTAssertEqual(try encoded(MembershipVisibility(visible: false)) as NSDictionary, ["visible": false] as NSDictionary)
        XCTAssertEqual(try decode(MembershipVisibility.self, #"{"node_id":"n1","visible":true}"#).visible, true)
        XCTAssertTrue(MyPatchesRules.visibilitySentence(false).contains("Its admins and members still see you"))
    }

    func testAFollowerIsOfferedTheRungOnlyWhereItCanSucceed() throws {
        func row(policy: String, status: String = "active") throws -> Membership {
            try decode(Membership.self, #"{"id":"m","role":"follower","status":"active","membership_policy":"\#(policy)","node_status":"\#(status)","node_slug":"s"}"#)
        }
        XCTAssertEqual(MyPatchesRules.rung(try row(policy: "open")), .now)
        XCTAssertEqual(MyPatchesRules.rung(try row(policy: "approval_required")), .request)
        XCTAssertNil(MyPatchesRules.rung(try row(policy: "invite_only")))
        XCTAssertNil(MyPatchesRules.rung(try row(policy: "open", status: "unclaimed")))
        XCTAssertEqual(MyPatchesRules.rungTitle(.now), "Become a member")
        XCTAssertEqual(MyPatchesRules.rungTitle(.request), "Send request")
        XCTAssertEqual(MyPatchesRules.stateNote(try row(policy: "invite_only"))?.label, "Invite only")
        XCTAssertEqual(MyPatchesRules.stateNote(try row(policy: "open", status: "unclaimed"))?.label, "Unclaimed")
        XCTAssertNil(MyPatchesRules.stateNote(try row(policy: "open")))
    }

    // MARK: Notification preferences

    private let matrix = #"{"channels":["in_app","email"],"categories":[{"id":"proposals","label":"Proposals","description":"New proposals, voting updates, deadlines","types":[{"type":"proposal.new","label":"New proposal in your patch","channels":{"in_app":true,"email":false},"decided":false},{"type":"proposal.approved","label":"Proposal approved","channels":{"in_app":true,"email":true},"decided":true}]},{"id":"quilt","label":"The quilt","description":"A monthly note.","types":[{"type":"quilt.bulletin","label":"New patches this month","channels":{"in_app":false,"email":false},"decided":false}]}]}"#

    func testTheChannelMapSurvivesTheSnakeCaseDecoder() throws {
        let prefs = try decode(NotificationPreferences.self, matrix)
        XCTAssertEqual(prefs.channels, ["in_app", "email"])
        let first = try XCTUnwrap(prefs.categories.first?.types.first)
        XCTAssertEqual(first.channels, ["in_app": true, "email": false],
                       "keyed by the server's names, not the decoder's `inApp`")
        XCTAssertTrue(prefs.isOn("proposal.new", "in_app"))
        XCTAssertFalse(prefs.isOn("proposal.new", "email"))
        XCTAssertTrue(prefs.isOn("proposal.approved", "email"))
        XCTAssertEqual(prefs.categories.map(\.label), ["Proposals", "The quilt"])
        XCTAssertEqual(prefs.categories[0].types[1].decided, true)

        // A plain decoder, which leaves the keys alone, reads the same matrix.
        let plain = try JSONDecoder().decode(NotificationPreferences.self, from: Data(matrix.utf8))
        XCTAssertEqual(plain.channels, prefs.channels)
        XCTAssertTrue(plain.isOn("proposal.new", "in_app"))
    }

    func testOnlyListedChannelsAreReadAndAMissingOneIsOff() throws {
        let json = #"{"channels":["in_app"],"categories":[{"id":"c","label":"C","description":"","types":[{"type":"t","label":"T","channels":{"in_app":true,"email":true}},{"type":"u","label":"U","channels":{}}]}]}"#
        let prefs = try decode(NotificationPreferences.self, json)
        XCTAssertEqual(prefs.categories[0].types[0].channels, ["in_app": true], "email is not offered on this quilt")
        XCTAssertFalse(prefs.isOn("u", "in_app"))
        XCTAssertEqual(NotificationPreferences.camelCased("in_app"), "inApp")
        XCTAssertEqual(NotificationPreferences.camelCased("email"), "email")
        XCTAssertEqual(NotificationPreferences.channelLabel("in_app"), "In-app")
        XCTAssertEqual(NotificationPreferences.channelLabel("email"), "Email")
    }

    func testASaveCarriesOnlyThePairsThatChanged() throws {
        let saved = try decode(NotificationPreferences.self, matrix)
        var shown = saved
        XCTAssertEqual(NotificationPreferences.changes(from: saved, to: shown), [], "nothing moved, nothing sent")
        shown.set("proposal.new", "email", true)
        XCTAssertEqual(NotificationPreferences.changes(from: saved, to: shown),
                       [PreferenceChange(type: "proposal.new", channel: "email", enabled: true)],
                       "one pair — never the whole matrix, so the bulletin stays undecided")
        shown.set("proposal.new", "email", false)
        XCTAssertEqual(NotificationPreferences.changes(from: saved, to: shown), [], "moved and moved back is no change")
        shown.set("quilt.bulletin", "in_app", true)
        shown.set("proposal.approved", "email", false)
        let changes = NotificationPreferences.changes(from: saved, to: shown)
        XCTAssertEqual(Set(changes), [
            PreferenceChange(type: "quilt.bulletin", channel: "in_app", enabled: true),
            PreferenceChange(type: "proposal.approved", channel: "email", enabled: false),
        ])
        let body = try encoded(PreferenceUpdate(preferences: [PreferenceChange(type: "proposal.new", channel: "in_app", enabled: false)]))
        XCTAssertEqual(body as NSDictionary,
                       ["preferences": [["type": "proposal.new", "channel": "in_app", "enabled": false]]] as NSDictionary)
    }

    func testARefusedSaveIsPutBackUnlessMovedAgain() throws {
        let saved = try decode(NotificationPreferences.self, matrix)
        var shown = saved
        shown.set("proposal.new", "email", true)
        shown.set("quilt.bulletin", "email", true)
        let sent = NotificationPreferences.changes(from: saved, to: shown)
        // The reader moves one of the two again while the save is out.
        shown.set("quilt.bulletin", "email", false)
        shown.set("quilt.bulletin", "in_app", true)
        shown.revert(sent)
        XCTAssertFalse(shown.isOn("proposal.new", "email"), "put back")
        XCTAssertFalse(shown.isOn("quilt.bulletin", "email"), "already back where it was")
        XCTAssertTrue(shown.isOn("quilt.bulletin", "in_app"), "the newer choice stands")
        var held = saved
        held.apply(sent)
        XCTAssertTrue(held.isOn("proposal.new", "email"))
    }
}
