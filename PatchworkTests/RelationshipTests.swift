// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// Which control a patch earns, checked as a value with no window open.
///
/// Every branch here corresponds to something the server will or will not
/// accept, and the point of the file is that the two cannot drift apart: a
/// control this client offers on a patch the server would refuse is the exact
/// mistake the browsing passes avoided by offering no controls at all.
final class RelationshipTests: XCTestCase {
    private func patch(_ json: String) throws -> Patch {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Patch.self, from: Data(json.utf8))
    }

    private func membership(_ json: String) throws -> Membership {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Membership.self, from: Data(json.utf8))
    }

    /// A public, claimed patch that admits anyone: the ordinary case both
    /// offers are read against.
    private var openPatch: String {
        #"{"id":"p","name":"Common Thread","slug":"common-thread","visibility":"public","membership_policy":"open"}"#
    }

    // MARK: - Nothing at all

    func testABannedReaderIsOfferedNothing() throws {
        let node = try patch(#"{"id":"p","name":"A","slug":"a","visibility":"public","membership_policy":"open","is_banned":true}"#)
        XCTAssertEqual(Relationship.resolve(node: node, standing: nil), .none)
        // And not even a standing they still hold on paper.
        XCTAssertEqual(Relationship.resolve(node: node, standing: .active(.member)), .none)
    }

    func testAPatchThatHasMovedOffersNothing() throws {
        let node = try patch(#"{"id":"p","name":"A","slug":"a","visibility":"public","membership_policy":"open","moved_to":"https://neighbor.example.org/patches/a"}"#)
        XCTAssertEqual(Relationship.resolve(node: node, standing: nil), .none,
                       "The moved notice already explains it; a Follow button would be a control the server refuses")
    }

    // MARK: - A standing already held

    func testEachActiveRoleWearsItsOwnMarkAndItsOwnExit() throws {
        let node = try patch(openPatch)
        XCTAssertEqual(Relationship.resolve(node: node, standing: .active(.follower)), .holding(.follower))
        XCTAssertEqual(Relationship.resolve(node: node, standing: .active(.member)), .holding(.member))
        XCTAssertEqual(Relationship.resolve(node: node, standing: .active(.admin)), .holding(.admin))

        XCTAssertEqual(MembershipRole.follower.mark, "Following")
        XCTAssertEqual(MembershipRole.member.mark, "Member")
        XCTAssertEqual(MembershipRole.admin.mark, "Admin")
        // Following is left by unfollowing; a membership is left by leaving.
        XCTAssertEqual(MembershipRole.follower.exit, "Unfollow")
        XCTAssertEqual(MembershipRole.member.exit, "Leave")
        XCTAssertEqual(MembershipRole.admin.exit, "Leave")
    }

    func testAPendingRequestIsItsOwnStateWithItsOwnWayBack() throws {
        XCTAssertEqual(Relationship.resolve(node: try patch(openPatch), standing: .pending), .requested,
                       "A request is neither a membership nor a stranger")
    }

    // MARK: - What a stranger is offered

    func testFollowIsOfferedOnAPublicPatchAndOnNoOther() throws {
        let publicPatch = try patch(openPatch)
        guard case .offering(let offer) = Relationship.resolve(node: publicPatch, standing: nil) else {
            return XCTFail("a public patch offers something")
        }
        XCTAssertTrue(offer.follow)

        let privatePatch = try patch(#"{"id":"p","name":"A","slug":"a","visibility":"private","membership_policy":"open"}"#)
        guard case .offering(let restricted) = Relationship.resolve(node: privatePatch, standing: nil) else {
            return XCTFail("a private patch can still be joined")
        }
        XCTAssertFalse(restricted.follow, "Following is a public act on a public patch")
        XCTAssertEqual(restricted.join, .now)
        // The tree states no visibility and serves only public patches, so
        // a patch with none is followable — otherwise no card on the quilt
        // could ever wear a heart.
        let fromTree = try patch(#"{"id":"t","name":"A","slug":"a","membership_policy":"open"}"#)
        guard case .offering(let listed) = Relationship.resolve(node: fromTree, standing: nil) else { return XCTFail("expected an offer") }
        XCTAssertTrue(listed.follow, "A tree-served patch is public")
    }

    func testAnUnclaimedListingIsFollowedAndNotJoined() throws {
        let byFlag = try patch(#"{"id":"p","name":"A","slug":"a","visibility":"public","is_unclaimed":true}"#)
        XCTAssertEqual(Relationship.resolve(node: byFlag, standing: nil), .offering(.init(follow: true, join: nil)),
                       "There is nobody to be a member of yet")
        let byStatus = try patch(#"{"id":"p","name":"A","slug":"a","visibility":"public","status":"unclaimed"}"#)
        XCTAssertEqual(Relationship.resolve(node: byStatus, standing: nil), .offering(.init(follow: true, join: nil)))
    }

    func testAnInviteOnlyPatchIsFollowedAndNotJoined() throws {
        let node = try patch(#"{"id":"p","name":"A","slug":"a","visibility":"public","membership_policy":"invite_only"}"#)
        XCTAssertEqual(Relationship.resolve(node: node, standing: nil), .offering(.init(follow: true, join: nil)),
                       "An invite-only patch does the asking itself")
    }

    func testApprovalRequiredAsksAndOpenAdmits() throws {
        let asks = try patch(#"{"id":"p","name":"A","slug":"a","visibility":"public","membership_policy":"approval_required"}"#)
        guard case .offering(let offer) = Relationship.resolve(node: asks, standing: nil) else { return XCTFail("offered") }
        XCTAssertEqual(offer.join, .request)
        XCTAssertEqual(offer.join?.title, "Request to join")
        XCTAssertEqual(Relationship.Join.now.title, "Join")
    }

    func testAPrivateUnclaimedListingOffersNothingRatherThanAnEmptyRow() throws {
        let node = try patch(#"{"id":"p","name":"A","slug":"a","visibility":"private","is_unclaimed":true}"#)
        XCTAssertEqual(Relationship.resolve(node: node, standing: nil), .none)
    }

    /// The toast reads the answer, not the button that was pressed: an open
    /// patch that turned on approval between the two is still told the truth.
    func testTheOutcomeIsWordedFromWhatTheServerAnswered() {
        XCTAssertEqual(Relationship.joinOutcome(status: "pending"), "Membership request sent")
        XCTAssertEqual(Relationship.joinOutcome(status: "active"), "You are now a member")
        // A leave, an unfollow and a withdrawal say nothing: the mark is gone,
        // which was the whole answer.
        XCTAssertNil(RelationshipControl.sentence(for: "ok"))
        XCTAssertEqual(RelationshipControl.sentence(for: "pending"), "Membership request sent")
    }

    // MARK: - The membership index

    func testTheIndexAnswersForOnePatchAndNotForAnother() throws {
        let rows = [
            try membership(#"{"id":"m1","user_id":"u","node_id":"n1","role":"follower","status":"active","node_slug":"listening-room","node_name":"The Listening Room"}"#),
            try membership(#"{"id":"m2","user_id":"u","node_id":"n2","status":"pending","node_slug":"common-thread","node_name":"Common Thread"}"#),
        ]
        XCTAssertEqual(QuiltSession.standing(in: rows, for: "listening-room"), .active(.follower))
        XCTAssertEqual(QuiltSession.standing(in: rows, for: "common-thread"), .pending)
        XCTAssertNil(QuiltSession.standing(in: rows, for: "extra-0"))
    }

    func testAPendingRowCarriesNoRoleAndIsNotGivenOne() throws {
        let row = try membership(#"{"id":"m","user_id":"u","node_id":"n","status":"pending","node_slug":"a","node_name":"A"}"#)
        XCTAssertNil(row.role)
        XCTAssertEqual(row.standing, .pending, "A pending row is pending, whatever role it would eventually hold")
    }

    func testARowNamesItsPatchAndFallsBackToTheSlug() throws {
        let named = try membership(#"{"id":"m","user_id":"u","node_id":"n","status":"active","role":"member","node_slug":"a","node_name":"Anvil Club"}"#)
        XCTAssertEqual(named.name, "Anvil Club")
        let unnamed = try membership(#"{"id":"m","user_id":"u","node_id":"n","status":"active","role":"member","node_slug":"a","node_name":""}"#)
        XCTAssertEqual(unnamed.name, "a")
    }

    // MARK: - Decoding `me/nodes`

    func testTheIndexDecodesAsAnObjectAndAsABareArray() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let row = #"{"id":"m","user_id":"u","node_id":"n","role":"admin","status":"active","visible":true,"joined_at":"2026-09-01T10:00:00Z","node_name":"A","node_slug":"a","node_description":"d","node_visibility":"public","membership_policy":"open","node_status":"active"}"#
        let wrapped = try decoder.decode(MembershipPage.self, from: Data("{\"items\":[\(row)]}".utf8))
        XCTAssertEqual(wrapped.items.count, 1)
        XCTAssertEqual(wrapped.items.first?.standing, .active(.admin))
        XCTAssertEqual(wrapped.items.first?.membershipPolicy, "open")
        let bare = try decoder.decode(MembershipPage.self, from: Data("[\(row)]".utf8))
        XCTAssertEqual(bare.items.count, 1)
        XCTAssertEqual(bare.items.first?.nodeSlug, "a")
        // An envelope with no rows at all is an empty index, not a failure.
        XCTAssertTrue(try decoder.decode(MembershipPage.self, from: Data(#"{"items":null}"#.utf8)).items.isEmpty)
    }

    /// The patch's own answer about the reader, which is what a profile has to
    /// read from before the index has come back.
    func testTheNodeItselfCanStateWhereTheReaderStands() throws {
        let admin = try patch(#"{"id":"p","name":"A","slug":"a","visibility":"public","is_member":true,"is_admin":true,"membership_role":"admin"}"#)
        XCTAssertEqual(Standing.from(node: admin), .active(.admin))
        let member = try patch(#"{"id":"p","name":"A","slug":"a","visibility":"public","is_member":true}"#)
        XCTAssertEqual(Standing.from(node: member), .active(.member), "A member with no role stated is still a member")
        let stranger = try patch(openPatch)
        XCTAssertNil(Standing.from(node: stranger))
    }

    /// The four fields may ride the envelope rather than the node, and a
    /// reader that only unpacked one of the two would silently lose them.
    func testTheEnvelopeAndTheNodeAreBothReadForTheReadersOwnStanding() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let onEnvelope = try decoder.decode(PatchResponse.self, from: Data(#"{"node":{"id":"p","name":"A","slug":"a"},"is_member":true,"membership_role":"member","is_banned":false}"#.utf8))
        XCTAssertEqual(onEnvelope.standing, .active(.member))
        XCTAssertFalse(onEnvelope.banned)
        let onNode = try decoder.decode(PatchResponse.self, from: Data(#"{"node":{"id":"p","name":"A","slug":"a","is_member":true,"membership_role":"follower","is_banned":true}}"#.utf8))
        XCTAssertEqual(onNode.standing, .active(.follower))
        XCTAssertTrue(onNode.banned)
    }
}
