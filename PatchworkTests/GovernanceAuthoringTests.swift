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

    // MARK: - Nominations

    private func seat(_ id: String, vacant: Bool) -> GovernanceSeat {
        GovernanceSeat(id: id, username: vacant ? nil : "rowan", displayName: nil, termEndsAt: nil, vacant: vacant, fill: nil,
                       contestOpens: nil, contestDue: nil, contestId: nil, holderWithheld: nil)
    }

    func testAnAdminNominatesWhereTheCommunityRatifies() {
        let meritocratic = GovernanceRules(decisionMethod: "majority", leadershipModel: "meritocratic", leadershipVenue: "patchwork")
        XCTAssertTrue(ProposalPosting.mayNominate(rules: meritocratic, seats: [], isPatchAdmin: true))
        XCTAssertEqual(ProposalPosting.kinds(mayNominate: true), [.action, .membership, .other], "the web's order")
        XCTAssertEqual(ProposalPosting.kinds(mayNominate: false), [.action, .other])
        XCTAssertFalse(ProposalPosting.mayNominate(rules: meritocratic, seats: [], isPatchAdmin: false), "admins nominate")
        let elected = GovernanceRules(decisionMethod: "majority", leadershipModel: "elected", leadershipVenue: "patchwork")
        XCTAssertTrue(ProposalPosting.mayNominate(rules: elected, seats: [seat("a", vacant: false), seat("b", vacant: true)], isPatchAdmin: true))
        XCTAssertFalse(ProposalPosting.mayNominate(rules: elected, seats: [seat("a", vacant: false)], isPatchAdmin: true), "nothing to nominate into")
        let maintainer = GovernanceRules(decisionMethod: "majority", leadershipModel: "maintainer")
        XCTAssertFalse(ProposalPosting.mayNominate(rules: maintainer, seats: [], isPatchAdmin: true))
        let decidedByAdmins = GovernanceRules(decisionMethod: "admin", leadershipModel: "meritocratic", leadershipVenue: "patchwork")
        XCTAssertTrue(ProposalPosting.webOffersNomination(rules: decidedByAdmins, seats: [], isPatchAdmin: true))
        XCTAssertFalse(ProposalPosting.mayNominate(rules: decidedByAdmins, seats: [], isPatchAdmin: true),
                       "no vote resolves it there, so nobody would be promoted")
    }

    func testOnlyPlainMembersCanBeNominated() {
        let rows = [
            PatchMember(id: "1", userId: "a", username: "a", displayName: "Admin", avatarUrl: nil, role: "admin"),
            PatchMember(id: "2", userId: "m", username: "m", displayName: "Member", avatarUrl: nil, role: "member"),
            PatchMember(id: "3", userId: "f", username: "f", displayName: "Follower", avatarUrl: nil, role: "follower"),
            PatchMember(id: "4", userId: "", username: "h", displayName: "Hidden", avatarUrl: nil, role: "member"),
        ]
        XCTAssertEqual(ProposalPosting.nominatable(rows).map(\.id), ["2"])
    }

    func testANominationNamesItsMemberAndNobodyElseSendsOne() throws {
        let meritocratic = GovernanceRules(decisionMethod: "majority", defaultVoteDurationHours: 168, leadershipModel: "meritocratic")
        var draft = ProposalDraft(title: "Hana for admin", kind: .membership, durationHours: 168)
        XCTAssertEqual(ProposalPosting.problem(draft), "Choose the member this nomination is about")
        draft.nomineeID = "u-hana"
        XCTAssertNil(ProposalPosting.problem(draft))
        XCTAssertEqual(try json(ProposalBody(draft, rules: meritocratic, isPatchAdmin: true)),
                       #"{"body":"","duration_hours":168,"proposal_type":"membership","target_user_id":"u-hana","title":"Hana for admin"}"#)
        draft.kind = .action
        XCTAssertFalse(try json(ProposalBody(draft, rules: meritocratic, isPatchAdmin: true)).contains("target_user_id"),
                       "a nominee left behind by a change of type is not sent")
    }

    func testTheCouncilNoteSaysWhereTheWayOntoTheCouncilIs() {
        let elected = GovernanceRules(leadershipModel: "elected", leadershipVenue: "patchwork")
        XCTAssertTrue(ProposalPosting.councilNote(rules: elected, seats: [], isPatchAdmin: false, nextContestOpens: nil)!.hasPrefix("Admins here hold seats"))
        let full = ProposalPosting.councilNote(rules: elected, seats: [seat("a", vacant: false)], isPatchAdmin: true, nextContestOpens: nil)!
        XCTAssertTrue(full.hasPrefix("Every seat on the council is held"))
        XCTAssertTrue(full.hasSuffix("Adding a seat happens on this quilt’s website."))
        XCTAssertNil(ProposalPosting.councilNote(rules: elected, seats: [seat("b", vacant: true)], isPatchAdmin: true, nextContestOpens: nil))
        XCTAssertNil(ProposalPosting.councilNote(rules: GovernanceRules(leadershipModel: "meritocratic"), seats: [], isPatchAdmin: true, nextContestOpens: nil))
        XCTAssertEqual(ProposalPosting.nomineeHint(elected), "If this passes, they take the vacant seat and serve out its term. Nobody has to approve it afterwards.")
    }
}
