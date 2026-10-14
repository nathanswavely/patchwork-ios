// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// Getting in, checked as values: answering an invitation, creating and
/// suggesting a patch, claiming one and setting it up, and the first-time
/// account's Welcome.
final class GettingInTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    private func patch(_ json: String) throws -> Patch { try decode(Patch.self, json) }

    // MARK: - Invitations

    func testAnInvitationDecodesAsTheServerSendsIt() throws {
        let page = try decode(InvitationPage.self, #"{"items":[{"id":"m1","node_id":"n1","node_slug":"food-share","node_name":"Food Share","status":"invited","invited_at":"2026-10-01T10:00:00Z"}]}"#)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].nodeSlug, "food-share")
        XCTAssertEqual(page.items[0].name, "Food Share")
    }

    func testOnlyInvitedRowsAreReadAsInvitations() throws {
        // The web's own guard: a stub that answers with membership rows must
        // not turn a membership into an invitation.
        let page = try decode(InvitationPage.self, #"{"items":[{"id":"m1","node_slug":"a","status":"active"},{"id":"m2","node_slug":"b","status":"invited"}]}"#)
        XCTAssertEqual(page.items.map(\.nodeSlug), ["b"])
        XCTAssertTrue(try decode(InvitationPage.self, "{}").items.isEmpty)
    }

    func testAnInvitationTakesThePlaceOfTheOffers() throws {
        let node = try patch(#"{"id":"p","name":"Food Share","slug":"food-share","visibility":"public","membership_policy":"invite_only"}"#)
        XCTAssertEqual(Relationship.resolve(node: node, standing: nil, invited: true), .invited)
        XCTAssertEqual(Relationship.resolve(node: node, standing: nil), .offering(.init(follow: true, join: nil)),
                       "uninvited, an invite-only patch can be followed and not joined")
    }

    func testAStandingTheIndexHoldsOutranksAnInvitation() throws {
        let node = try patch(#"{"id":"p","name":"Food Share","slug":"food-share","visibility":"public","membership_policy":"invite_only"}"#)
        XCTAssertEqual(Relationship.resolve(node: node, standing: .active(.member), invited: true), .holding(.member))
        XCTAssertEqual(Relationship.resolve(node: node, standing: .pending, invited: true), .requested)
    }

    func testAnInvitationIsNotAnsweredOnAMovedOrBannedPatch() throws {
        let moved = try patch(#"{"id":"p","name":"A","slug":"a","visibility":"public","membership_policy":"invite_only","moved_to":"https://neighbor.example.org/patches/a"}"#)
        XCTAssertEqual(Relationship.resolve(node: moved, standing: nil, invited: true), .none, "accepting is a join, and a moved patch takes none")
        let banned = try patch(#"{"id":"p","name":"A","slug":"a","visibility":"public","is_banned":true}"#)
        XCTAssertEqual(Relationship.resolve(node: banned, standing: nil, invited: true), .none)
    }

    func testTheAnswersAreSaidInTheWebsWords() {
        XCTAssertEqual(RelationshipControl.sentence(for: "active"), "You are now a member")
        XCTAssertEqual(RelationshipControl.sentence(for: "declined"), "Invitation declined")
        XCTAssertEqual(Relationship.invitedLabel, "You've been invited to join")
    }
}
