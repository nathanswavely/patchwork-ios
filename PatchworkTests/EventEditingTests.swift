// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// Editing and deleting an event, checked as values.
///
/// The editing rule is the server's `UpdateEvent` (`internal/handler/
/// events.go`), branch by branch, and the deleting rule its `DeleteEvent`.
/// Edit is offered only where saving would be accepted, so a disagreement
/// with the server here is a button that leads to a 403.
final class EventEditingTests: XCTestCase {
    private typealias Door = EventEditing.Door

    private func door(admin: Bool = false, standing: Standing? = nil, creator: Bool = false, trusted: Bool = false,
                      node: String? = "active", status: String? = "active", imported: Bool = false) -> Door {
        EventEditing.door(isInstanceAdmin: admin, standing: standing, isCreator: creator, viewerTrusted: trusted,
                          nodeStatus: node, eventStatus: status, imported: imported)
    }

    // MARK: - Who may edit

    func testAnImportedEventIsEditedByNobodyHereAdminsIncluded() {
        XCTAssertEqual(door(admin: true, imported: true), .none)
        XCTAssertEqual(door(standing: .active(.admin), imported: true), .none)
        XCTAssertEqual(door(standing: .active(.member), creator: true, imported: true), .none)
        XCTAssertEqual(door(creator: true, trusted: true, node: "unclaimed", imported: true), .none)
        XCTAssertEqual(door(creator: true, status: "pending_review", imported: true), .none)
    }

    func testTheInstanceAdminEditsAnythingDirectly() {
        XCTAssertEqual(door(admin: true), .direct)
        XCTAssertEqual(door(admin: true, node: "unclaimed", status: "pending_review"), .direct)
        XCTAssertEqual(door(admin: true, node: "archived"), .direct)
    }

    func testAPatchAdminEditsAnyEventOnTheirActivePatch() {
        XCTAssertEqual(door(standing: .active(.admin)), .direct, "not theirs, still theirs to edit")
        XCTAssertEqual(door(standing: .active(.admin), status: "pending_review"), .direct)
        XCTAssertEqual(door(standing: .active(.admin), node: "archived"), .none, "only while the patch is active")
    }

    func testACreatorWhoIsStillAMemberEditsDirectly() {
        XCTAssertEqual(door(standing: .active(.member), creator: true), .direct)
        XCTAssertEqual(door(standing: .active(.member), creator: false), .none, "a member's reach stops at what they made")
        XCTAssertEqual(door(standing: .active(.member), creator: true, node: "archived"), .none, "on an active patch only")
    }

    func testACreatorWhoLeftOrOnlyFollowsKeepsNoEditOnAnActivePatch() {
        // A suggestion adopted onto an active patch belongs to the patch
        // (web ADR 026), and so does an event whose poster has left.
        XCTAssertEqual(door(standing: nil, creator: true), .none)
        XCTAssertEqual(door(standing: .active(.follower), creator: true), .none)
        XCTAssertEqual(door(standing: .pending, creator: true), .none, "a request nobody has answered is not a membership")
    }

    func testATrustedCreatorEditsDirectlyOnAnUnclaimedPatch() {
        XCTAssertEqual(door(creator: true, trusted: true, node: "unclaimed"), .direct)
        XCTAssertEqual(door(creator: true, trusted: true, node: "unclaimed", status: "pending_review"), .direct)
        XCTAssertEqual(door(creator: false, trusted: true, node: "unclaimed"), .none, "trust reaches only your own")
        XCTAssertEqual(door(creator: true, trusted: true, node: "active"), .none, "trust is worth nothing on a claimed patch")
    }

    func testYourOwnPendingSuggestionIsFreeToEdit() {
        XCTAssertEqual(door(creator: true, status: "pending_review"), .pending)
        XCTAssertEqual(door(standing: .active(.follower), creator: true, status: "pending_review"), .pending)
        XCTAssertEqual(door(creator: true, node: "unclaimed", status: "pending_review"), .pending, "still waiting, so no re-review")
        XCTAssertEqual(door(creator: false, status: "pending_review"), .none, "somebody else's suggestion")
    }

    func testAnUntrustedCreatorsEditOnAnUnclaimedPatchGoesBackToReview() {
        XCTAssertEqual(door(creator: true, node: "unclaimed"), .reReview)
        XCTAssertEqual(door(creator: false, node: "unclaimed"), .none)
    }

    func testAPatchWhoseStatusWasNotSaidIsAnOrdinaryOne() {
        XCTAssertEqual(door(standing: .active(.member), creator: true, node: nil), .direct)
        XCTAssertEqual(door(creator: true, node: nil), .none)
    }

    func testOnlyTheDirectDoorOffersTheTier() {
        XCTAssertTrue(Door.direct.offersTier)
        XCTAssertFalse(Door.pending.offersTier, "a suggestion is public whatever it asks for")
        XCTAssertFalse(Door.reReview.offersTier)
        XCTAssertFalse(Door.none.offersTier)
    }

    // MARK: - Who may delete

    func testDeletingIsAdminsAndTheCreatorAlways() {
        func may(admin: Bool = false, standing: Standing? = nil, creator: Bool = false, imported: Bool = false) -> Bool {
            EventEditing.mayDelete(isInstanceAdmin: admin, standing: standing, isCreator: creator, imported: imported)
        }
        XCTAssertTrue(may(admin: true))
        XCTAssertTrue(may(standing: .active(.admin)))
        XCTAssertTrue(may(creator: true), "an adopted suggestion's submitter may still take it back (broader than the web)")
        XCTAssertTrue(may(standing: .active(.member), creator: true))
        XCTAssertFalse(may(standing: .active(.member)), "a member may not delete somebody else's")
        XCTAssertFalse(may(standing: .active(.follower)))
        XCTAssertFalse(may())
        // A feed's event skip-lists its item on delete: the feed's managers' call.
        XCTAssertTrue(may(admin: true, imported: true))
        XCTAssertTrue(may(standing: .active(.admin), imported: true))
        XCTAssertFalse(may(creator: true, imported: true))
    }

    func testTheDeleteWordsAreTheWebs() {
        XCTAssertEqual(EventEditing.deleteLabel(pending: true), "Withdraw")
        XCTAssertEqual(EventEditing.deleteLabel(pending: false), "Delete")
        XCTAssertEqual(EventEditing.deletedLine(pending: true), "Submission withdrawn")
        XCTAssertEqual(EventEditing.deletedLine(pending: false), "Event deleted")
        XCTAssertNotEqual(EventEditing.deleteQuestion(pending: true), EventEditing.deleteQuestion(pending: false))
        XCTAssertTrue(EventEditing.deleteMessage(pending: false).contains("Nobody is notified"), "web ADR 093")
    }

    // MARK: - The event as the detail reads it

    private func event(_ extra: String = "") throws -> PatchworkEvent {
        let json = """
        {"id":"e1","node_id":"n1","created_by":"u1","title":"Toaster triage","description":"Bring it.",\
        "location":"Back room","starts_at":"2026-10-20T22:00:00Z","ends_at":"2026-10-21T00:00:00Z",\
        "timezone":"America/New_York","recurrence":"","visibility":"members","status":"active",\
        "image_url":"https://example.org/flyer.jpg","image_alt":"A flyer","event_url":"https://example.org/e",\
        "node_name":"Repair Cafe","node_slug":"repair-cafe","node_status":"active","viewer_trusted":true\(extra)}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PatchworkEvent.self, from: Data(json.utf8))
    }

    func testTheDetailDecodesWhoMadeItAndWhetherItIsImported() throws {
        let plain = try event()
        XCTAssertEqual(plain.createdBy, "u1")
        XCTAssertEqual(plain.viewerTrusted, true)
        XCTAssertFalse(plain.imported)
        XCTAssertTrue(try event(#","source_id":"src-1""#).imported)
        XCTAssertFalse(try event(#","source_id":null"#).imported)
    }

    func testTheFormIsFilledFromTheEvent() throws {
        let draft = EventDraft(editing: try event())
        XCTAssertEqual(draft.title, "Toaster triage")
        XCTAssertEqual(draft.description, "Bring it.")
        XCTAssertEqual(draft.location, "Back room")
        XCTAssertEqual(draft.eventURL, "https://example.org/e")
        XCTAssertEqual(draft.imageURL, "https://example.org/flyer.jpg")
        XCTAssertEqual(draft.imageAlt, "A flyer")
        XCTAssertTrue(draft.hasEnd)
        XCTAssertEqual(EventPosting.instant(draft.startsAt), "2026-10-20T22:00:00.000Z")
        XCTAssertEqual(EventPosting.instant(draft.endsAt), "2026-10-21T00:00:00.000Z")
        XCTAssertEqual(draft.tier, .members)
    }

    // MARK: - What an edit sends

    private func sent(_ changes: EventChanges) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase // as `PatchworkAPI` sends it
        let data = try encoder.encode(changes)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testAnUntouchedFormSendsNothing() throws {
        let original = EventDraft(editing: try event())
        var draft = original
        draft.title = "  Toaster triage "
        let changes = draft.changes(from: original, direct: true)
        XCTAssertTrue(changes.isEmpty, "whitespace is not a change")
        XCTAssertTrue(try sent(changes).isEmpty)
    }

    func testOnlyWhatChangedIsSent() throws {
        let original = EventDraft(editing: try event())
        var draft = original
        draft.title = " Toaster and kettle triage "
        let body = try sent(draft.changes(from: original, direct: true))
        XCTAssertEqual(body as NSDictionary, ["title": "Toaster and kettle triage"] as NSDictionary)
    }

    func testClearingAFieldClearsIt() throws {
        let original = EventDraft(editing: try event())
        var draft = original
        draft.description = "  "
        draft.location = ""
        draft.eventURL = ""
        draft.hasEnd = false
        let body = try sent(draft.changes(from: original, direct: true))
        XCTAssertEqual(body["description"] as? String, "", "an empty string clears it, which the web cannot send")
        XCTAssertEqual(body["location"] as? String, "")
        XCTAssertEqual(body["event_url"] as? String, "")
        XCTAssertTrue(body["ends_at"] is NSNull, "the end is cleared with null")
        XCTAssertEqual(Set(body.keys), ["description", "location", "event_url", "ends_at"])
    }

    func testClearingTheImageClearsItsDescriptionToo() throws {
        let original = EventDraft(editing: try event())
        var draft = original
        draft.imageURL = " "
        let body = try sent(draft.changes(from: original, direct: true))
        XCTAssertEqual(body["image_url"] as? String, "")
        XCTAssertEqual(body["image_alt"] as? String, "", "a description with no picture left is not kept")
    }

    func testChangingOnlyTheDescriptionOfTheImageSendsOnlyThat() throws {
        let original = EventDraft(editing: try event())
        var draft = original
        draft.imageAlt = "The flyer, in red"
        let body = try sent(draft.changes(from: original, direct: true))
        XCTAssertEqual(Set(body.keys), ["image_alt"], "the server judges the pair against the stored address")
    }

    func testMovingTheTimes() throws {
        var original = EventDraft(editing: try event())
        var draft = original
        draft.startsAt = original.startsAt.addingTimeInterval(3600 + 30) // seconds are dropped
        draft.endsAt = original.endsAt.addingTimeInterval(3600)
        var body = try sent(draft.changes(from: original, direct: true))
        XCTAssertEqual(body["starts_at"] as? String, "2026-10-20T23:00:00.000Z")
        XCTAssertEqual(body["ends_at"] as? String, "2026-10-21T01:00:00.000Z")

        // An end where there was none is sent as an instant.
        original.hasEnd = false
        draft = original
        draft.hasEnd = true
        body = try sent(draft.changes(from: original, direct: true))
        XCTAssertEqual(Set(body.keys), ["ends_at"])
        XCTAssertEqual(body["ends_at"] as? String, EventPosting.instant(original.endsAt))
    }

    func testTheTierIsSentOnlyThroughTheDirectDoor() throws {
        let original = EventDraft(editing: try event())
        var draft = original
        draft.tier = .public
        XCTAssertEqual(try sent(draft.changes(from: original, direct: true))["visibility"] as? String, "public")
        XCTAssertTrue(draft.changes(from: original, direct: false).isEmpty, "not a choice a suggestion has")
    }

    func testAnEditNeverSendsAZoneARecurrenceOrAPatch() throws {
        let original = EventDraft(editing: try event())
        var draft = original
        draft.title = "Moved"
        draft.description = "x"
        draft.location = "y"
        draft.hasEnd = false
        draft.tier = .followers
        let body = try sent(draft.changes(from: original, direct: true))
        XCTAssertNil(body["timezone"])
        XCTAssertNil(body["recurrence"])
        XCTAssertNil(body["node_id"])
    }

    // MARK: - What the form checks before sending

    func testTheEditChecksWhatTheServerDoesNot() throws {
        let original = EventDraft(editing: try event())
        var draft = original
        draft.title = "   "
        XCTAssertEqual(draft.editProblem(changes: draft.changes(from: original, direct: true)), "Title is required")

        draft = original
        draft.endsAt = draft.startsAt
        XCTAssertEqual(draft.editProblem(changes: draft.changes(from: original, direct: true)), "The end has to be after the start.")
        draft.endsAt = draft.startsAt.addingTimeInterval(-60)
        XCTAssertEqual(draft.editProblem(changes: draft.changes(from: original, direct: true)), "The end has to be after the start.")

        draft = original
        draft.title = "Fine"
        XCTAssertNil(draft.editProblem(changes: draft.changes(from: original, direct: true)))
    }

    func testTheImageAndLinkAreCheckedOnlyWhereTheEditTouchesThem() throws {
        var original = EventDraft(editing: try event())
        original.imageURL = "http://old.example.org/flyer.jpg" // stored before the https rule
        var draft = original
        draft.title = "Renamed"
        XCTAssertNil(draft.editProblem(changes: draft.changes(from: original, direct: true)),
                     "an old flyer is not this edit's business")

        draft.imageAlt = "Changed"
        XCTAssertEqual(draft.editProblem(changes: draft.changes(from: original, direct: true)),
                       "the image address has to start with https://")

        draft = original
        draft.eventURL = "ftp://example.org"
        XCTAssertEqual(draft.editProblem(changes: draft.changes(from: original, direct: true)),
                       "that doesn't look like a link — it should start with https://")
    }

    // MARK: - The fixtures answer as the server does

    func testTheFixturesRefuseWhatTheServerRefuses() throws {
        _ = try PreviewData.write("POST", "auth/magic-link/verify", body: Data(#"{"code":"123456"}"#.utf8))
        defer { PreviewData.signOut() }

        XCTAssertThrowsError(try PreviewData.write("PATCH", "events/demo-event-imported", body: Data(#"{"title":"x"}"#.utf8))) {
            XCTAssertEqual(ProposalDetailView.sentence($0, fallback: ""),
                           "This event comes from an event source. Edit it in the source calendar, or detach it first")
        }
        XCTAssertThrowsError(try PreviewData.write("PATCH", "events/demo-event-2", body: Data(#"{"title":"x"}"#.utf8))) {
            XCTAssertEqual(ProposalDetailView.sentence($0, fallback: ""), "Insufficient permissions", "somebody else's event")
        }
        XCTAssertThrowsError(try PreviewData.write("PATCH", "events/demo-event-mine", body: Data(#"{"node_id":"x"}"#.utf8))) {
            XCTAssertEqual(ProposalDetailView.sentence($0, fallback: ""), "No valid fields to update")
        }
        XCTAssertThrowsError(try PreviewData.write("PATCH", "events/demo-event-mine", body: Data(#"{"recurrence":"weekly"}"#.utf8)))
        XCTAssertThrowsError(try PreviewData.write("DELETE", "events/demo-event-3", body: nil), "not the reader's, not their patch")
        XCTAssertThrowsError(try PreviewData.write("PATCH", "events/nope", body: Data(#"{"title":"x"}"#.utf8))) {
            XCTAssertEqual(($0 as? APIError)?.httpStatus, 404)
        }
    }

    func testTheFixturesAnswerAnEditWithTheBareEvent() throws {
        _ = try PreviewData.write("POST", "auth/magic-link/verify", body: Data(#"{"code":"123456"}"#.utf8))
        defer { PreviewData.signOut() }
        let answer = try PreviewData.write("PATCH", "events/demo-event-mine",
                                           body: Data(#"{"location":"","ends_at":null,"recurrence":""}"#.utf8))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let updated = try decoder.decode(PatchworkEvent.self, from: Data(answer.utf8))
        XCTAssertEqual(updated.location, "")
        XCTAssertNil(updated.endsAt)
        XCTAssertEqual(updated.recurrence, "", "a stored word may be retired")
        XCTAssertNil(updated.nodeSlug, "the 200 carries no patch beside it")
        XCTAssertFalse(updated.awaitingReview)
    }
}
