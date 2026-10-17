// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import Patchwork

/// Deciding, nominating, amending a document, changing the rules and
/// writing a new document, as values: who is offered each act, what each
/// form sends, and what each diff says.
final class GovernanceAuthoringTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
    private func proposal(_ json: String) throws -> Proposal {
        try decoder().decode(Proposal.self, from: Data(json.utf8))
    }
    private func json(_ body: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(body), as: UTF8.self)
    }

    // MARK: - Deciding and applying

    func testTheMaintainerDecidesAWaitingRequestAndMayAskOnce() throws {
        let waiting = try proposal(#"{"id":"p","title":"T","status":"open","state":"awaiting_admin","can_decide":true,"advisory":true,"voting_ends_at":null}"#)
        XCTAssertEqual(ProposalDeciding.acts(waiting, standing: .active(.admin), acting: true), [.approve, .decline, .askMembers])
        let asked = try proposal(#"{"id":"p","title":"T","status":"open","state":"awaiting_admin","can_decide":true,"advisory":true,"voting_ends_at":"2026-10-01T00:00:00Z","approve_count":2}"#)
        XCTAssertEqual(ProposalDeciding.acts(asked, standing: .active(.admin), acting: true), [.approve, .decline],
                       "the members can be asked once; the advice is on the proposal")
        let advising = try proposal(#"{"id":"p","title":"T","status":"open","state":"voting","can_decide":true,"advisory":true,"voting_ends_at":"2026-10-30T00:00:00Z"}"#)
        XCTAssertEqual(ProposalDeciding.acts(advising, standing: .active(.admin), acting: true), [.approve, .decline],
                       "mid-vote included: the vote only advises")
    }

    func testNobodyElseDecides() throws {
        let waiting = try proposal(#"{"id":"p","title":"T","status":"open","state":"awaiting_admin","can_decide":true}"#)
        XCTAssertEqual(ProposalDeciding.acts(waiting, standing: .active(.member), acting: true), [])
        XCTAssertEqual(ProposalDeciding.acts(waiting, standing: nil, acting: true), [], "a quilt admin with no role here")
        XCTAssertEqual(ProposalDeciding.acts(waiting, standing: .active(.admin), acting: false), [], "another quilt's admin")
        let vote = try proposal(#"{"id":"p","title":"T","status":"open","state":"voting","can_decide":false}"#)
        XCTAssertEqual(ProposalDeciding.acts(vote, standing: .active(.admin), acting: true), [],
                       "a voting patch's open vote is the members' to decide")
        let election = try proposal(#"{"id":"p","title":"T","status":"open","state":"voting","can_decide":true,"seats_contested":1,"election_phase":"voting"}"#)
        XCTAssertEqual(ProposalDeciding.acts(election, standing: .active(.admin), acting: true), [],
                       "the electorate closes an election, whatever can_decide says")
        let settled = try proposal(#"{"id":"p","title":"T","status":"rejected","state":"rejected","can_decide":false}"#)
        XCTAssertEqual(ProposalDeciding.acts(settled, standing: .active(.admin), acting: true), [])
    }

    func testAnApprovedVoteWaitsForAnAdminToMakeItOfficial() throws {
        let approved = try proposal(#"{"id":"p","title":"T","status":"approved","state":"approved","can_decide":false}"#)
        XCTAssertEqual(ProposalDeciding.acts(approved, standing: .active(.admin), acting: true), [.makeOfficial])
        XCTAssertEqual(ProposalDeciding.acts(approved, standing: .active(.member), acting: true), [])
        let inEffect = try proposal(#"{"id":"p","title":"T","status":"approved","state":"in_effect"}"#)
        XCTAssertEqual(ProposalDeciding.acts(inEffect, standing: .active(.admin), acting: true), [])
    }

    func testTheConfirmationsSayWhatHappens() throws {
        let asked = try proposal(#"{"id":"p","title":"T","status":"open","state":"voting","approve_count":3,"reject_count":1,"voting_terms":{"default_vote_duration_hours":48}}"#)
        XCTAssertTrue(ProposalDeciding.message(.approve, for: asked).contains("3 approve · 1 reject · 0 abstain"), "the advice is in front of them")
        XCTAssertEqual(ProposalDeciding.Act.decline.confirmLabel, "Decline this proposal", "the web's words")
        XCTAssertTrue(ProposalDeciding.message(.askMembers, for: asked).contains("48 hours"), "the proposal's own window")
        let bare = try proposal(#"{"id":"p","title":"T"}"#)
        XCTAssertTrue(ProposalDeciding.message(.askMembers, for: bare).contains("72 hours"))
        XCTAssertTrue(ProposalDeciding.Act.decline.destructive)
        XCTAssertFalse(ProposalDeciding.Act.approve.destructive)
    }

    func testTheDecisionBody() throws {
        XCTAssertEqual(try json(DecisionBody.approve), #"{"decision":"approve"}"#)
        XCTAssertEqual(try json(DecisionBody.decline), #"{"decision":"decline"}"#)
    }

    func testARequestTheMaintainerApprovedIsNotADirectChange() throws {
        let direct = try proposal(#"{"id":"p","title":"T","status":"approved","state":"in_effect","voters":[],"created_at":"2026-10-01T10:00:00Z","applied_at":"2026-10-01T10:00:00Z"}"#)
        XCTAssertTrue(direct.isDirectChange)
        let decided = try proposal(#"{"id":"p","title":"T","status":"approved","state":"in_effect","voters":[],"advisory":true,"created_at":"2026-10-01T10:00:00Z","applied_at":"2026-10-03T09:00:00Z"}"#)
        XCTAssertFalse(decided.isDirectChange, "its author did not apply it")
        XCTAssertEqual(VoteRules.banner(decided), "The maintainer approved this. It is in effect.")
    }
}
