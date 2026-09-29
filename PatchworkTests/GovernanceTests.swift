// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// Voting, an election's ballot and the discussion, checked as values: the
/// payloads as the server sends them (`GetProposal`, `ListComments`), every
/// sentence the proposal screen says (web `ProposalStatusBanner`,
/// `VoteSection`, `ElectionPanel`, `CommentThread`), and what each act sends.
final class GovernanceTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func proposal(_ json: String) throws -> Proposal {
        try decoder().decode(Proposal.self, from: Data(json.utf8))
    }

    private let now = ISO8601DateFormatter().date(from: "2026-09-29T12:00:00Z")!

    /// A detail payload in the server's shape, every key present, the clock
    /// and the turnout as JSON null.
    private let awaitingJSON = """
    {"id":"019p","node_id":"n1","author_id":"u2","author_name":"Imani Osei","target_user_id":"","target_user_name":"",
     "seats_contested":0,"nominations_close_at":"","election_phase":"","candidates":[],"election_turnout":null,"i_abstained":false,
     "title":"Paint the door","body":"It is **brown**.","status":"open","state":"awaiting_admin","proposal_type":"action",
     "duration_hours":0,"voting_ends_at":null,"created_at":"2026-09-20T10:00:00.123Z","updated_at":"2026-09-20T10:00:00.123Z",
     "approve_count":0,"reject_count":0,"abstain_count":0,"voters":[],"my_vote":"","eligible_voters":4,"can_vote":false,
     "voting_terms":{"decision_method":"admin","quorum_percent":0,"default_vote_duration_hours":72,"amendment_threshold":"",
       "amendment_auto_apply":false,"succession_policy":"","min_voting_tenure_days":30,"subject_recusal":true},
     "tenure_days":0,"vote_eligible_at":"","applied_at":"","advisory":true,"can_decide":false,"declined_by":""}
    """

    /// `extra` goes first: with a key given twice, the first one is read.
    private func voting(canVote: Bool = true, myVote: String = "", approve: Int = 4, reject: Int = 1, abstain: Int = 0,
                        eligible: Int = 12, quorum: Int = 20, endsAt: String = "2026-10-03T10:30:00Z",
                        extra: String = "") throws -> Proposal {
        try proposal("""
        {"id":"p"\(extra),"title":"T","status":"open","state":"voting","proposal_type":"action","created_at":"2026-09-26T15:00:00Z",
         "voting_ends_at":"\(endsAt)","approve_count":\(approve),"reject_count":\(reject),"abstain_count":\(abstain),
         "voters":[{"user_id":"u1","display_name":"Rowan","username":"rowan","value":"approve","counted":true}],
         "my_vote":"\(myVote)","eligible_voters":\(eligible),"can_vote":\(canVote),
         "voting_terms":{"decision_method":"majority","quorum_percent":\(quorum)},"tenure_days":0,"vote_eligible_at":"",
         "advisory":false}
        """)
    }

    // MARK: - Decoding

    func testTheWholeDetailPayloadDecodesWithANullClockAndANullTurnout() throws {
        let p = try proposal(awaitingJSON)
        XCTAssertNil(p.votingEndsAt)
        XCTAssertNil(p.electionTurnout)
        XCTAssertEqual(p.nodeId, "n1")
        XCTAssertEqual(p.authorId, "u2")
        XCTAssertEqual(p.eligibleVoters, 4)
        XCTAssertEqual(p.canVote, false)
        XCTAssertEqual(p.myVote, "")
        XCTAssertEqual(p.advisory, true)
        XCTAssertEqual(p.votingTerms?.decisionMethod, "admin")
        XCTAssertEqual(p.votingTerms?.minVotingTenureDays, 30)
        XCTAssertEqual(p.votingTerms?.subjectRecusal, true)
        XCTAssertEqual(p.tenureDays, 0)
        XCTAssertEqual(p.voters, [])
        XCTAssertEqual(p.candidates, [])
        XCTAssertFalse(p.isElection)
    }

    func testAnElectionDecodesItsSlateAndTurnout() throws {
        let p = try proposal("""
        {"id":"e","title":"Council","status":"open","state":"voting","seats_contested":2,"election_phase":"voting",
         "nominations_close_at":"2026-09-27T10:00:00Z","voting_ends_at":"2026-10-04T10:00:00Z","i_abstained":false,"can_vote":true,
         "election_turnout":{"voted":4,"eligible":12,"needed":3,"met":true},
         "candidates":[{"id":"c1","user_id":"u2","username":"imani","display_name":"Imani Osei","approvals":3,"approved_by_me":true,"seated":false,"statement":"Keys."},
                       {"id":"c2","user_id":"u3","username":"theo","display_name":"","approvals":1,"approved_by_me":false,"seated":false}]}
        """)
        XCTAssertTrue(p.isElection)
        XCTAssertEqual(p.electionTurnout, ElectionTurnout(voted: 4, eligible: 12, needed: 3, met: true))
        XCTAssertEqual(p.candidates?.map(\.id), ["c1", "c2"])
        XCTAssertEqual(p.candidates?[0].approvedByMe, true)
        XCTAssertEqual(p.candidates?[0].statement, "Keys.")
        XCTAssertEqual(p.candidates?[1].name, "theo", "an empty display name falls back to the handle")
        XCTAssertNil(p.candidates?[1].statement)
    }

    func testTheCommentsPayloadDecodesWithRepliesAndReactions() throws {
        let json = """
        {"items":[{"id":"c1","body":"First","author_name":"Imani","author_id":"u2","created_at":"2026-09-28T10:00:00Z",
          "updated_at":"2026-09-28T10:00:00Z","parent_id":null,
          "replies":[{"id":"c2","body":"Reply","author_name":"","author_id":"u1","created_at":"2026-09-28T11:00:00Z",
            "updated_at":"2026-09-28T11:00:00Z","parent_id":"c1","replies":[],"reactions":[]}],
          "reactions":[{"emoji":"\u{2764}\u{FE0F}","count":2,"me":true},{"emoji":"\u{1F44D}","count":1,"me":false}]}]}
        """
        let page = try decoder().decode(CommentPage.self, from: Data(json.utf8))
        let first = try XCTUnwrap(page.items?.first)
        XCTAssertNil(first.parentId)
        XCTAssertEqual(first.replies?.first?.parentId, "c1")
        XCTAssertEqual(first.replies?.first?.author, "Anonymous", "an empty name reads as the web reads it")
        XCTAssertEqual(first.reactions?.first, Reaction(emoji: Discussion.heart, count: 2, me: true))
        XCTAssertEqual(Discussion.count(page.items ?? []), 2, "items plus their replies")
    }

    // MARK: - Time left

    func testTimeLeftCeilsDaysFloorsHoursAndCeilsMinutes() {
        let at = { (seconds: TimeInterval) in ISO8601DateFormatter().string(from: self.now.addingTimeInterval(seconds)) }
        XCTAssertEqual(VoteRules.timeLeft(at(2 * 86_400 + 60), now: now), .left(3, .day), "the closing day counts")
        XCTAssertEqual(VoteRules.timeLeft(at(86_400), now: now), .left(1, .day))
        XCTAssertEqual(VoteRules.timeLeft(at(5 * 3_600 + 2_400), now: now), .left(5, .hour))
        XCTAssertEqual(VoteRules.timeLeft(at(90), now: now), .left(2, .minute))
        XCTAssertEqual(VoteRules.timeLeft(at(10), now: now), .left(1, .minute))
        XCTAssertEqual(VoteRules.timeLeft(at(-10), now: now), .ended)
        XCTAssertNil(VoteRules.timeLeft(nil, now: now))
        XCTAssertNil(VoteRules.timeLeft("", now: now))
    }

    func testTheThreeWaysTimeLeftIsWritten() {
        XCTAssertEqual(VoteRules.timeLeftSentence(.left(3, .day)), "3 days left")
        XCTAssertEqual(VoteRules.timeLeftSentence(.left(1, .hour)), "1 hour left")
        XCTAssertEqual(VoteRules.timeLeftSentence(.ended), "Voting ended")
        XCTAssertEqual(VoteRules.timeLeftShort(.left(3, .day)), "3d")
        XCTAssertEqual(VoteRules.timeLeftShort(.left(12, .minute)), "12m")
        XCTAssertEqual(VoteRules.timeLeftShort(.ended), "ended")
        XCTAssertEqual(VoteRules.timeLeftRow(.left(3, .day)), "3d left")
        XCTAssertEqual(VoteRules.timeLeftRow(.ended), "Voting ended")
        XCTAssertNil(VoteRules.timeLeftRow(nil))
    }

    // MARK: - The banner

    func testCastYourVoteBelowOnlyWhereThereIsAVoteBelow() throws {
        XCTAssertEqual(VoteRules.banner(try voting(canVote: true), now: now), "Voting is open. 4 days left. Cast your vote below.")
        XCTAssertEqual(VoteRules.banner(try voting(canVote: false), now: now), "Voting is open. 4 days left.")
        XCTAssertEqual(VoteRules.banner(try voting(canVote: false, endsAt: "2026-09-28T00:00:00Z"), now: now), "Voting is open. Voting ended.")
        XCTAssertEqual(VoteRules.banner(try voting(extra: #","advisory":true"#), now: now),
                       "Advisory vote. 4 days left. The maintainer decides. Cast your vote below.")
    }

    func testTheBannerForEveryOtherState() throws {
        func banner(_ fields: String) throws -> String? { VoteRules.banner(try proposal(#"{"id":"p","title":"T",\#(fields)}"#), now: now) }
        XCTAssertEqual(VoteRules.banner(try proposal(awaitingJSON), now: now),
                       "Waiting on the maintainer. This patch’s admins decide its proposals, and may ask the members first.")
        XCTAssertEqual(try banner(#""status":"open","state":"awaiting_admin","approve_count":2"#),
                       "The members have been asked and the vote has closed. The maintainer decides, with the tally below.")
        XCTAssertEqual(try banner(#""status":"open","state":"elsewhere""#)?.hasPrefix("Open for discussion."), true)
        XCTAssertEqual(try banner(#""status":"approved","state":"approved""#), "The community approved this change. An admin needs to make it official.")
        XCTAssertEqual(try banner(#""status":"approved","state":"in_effect","voters":[]"#), "This change is in effect.")
        XCTAssertEqual(try banner(#""status":"approved","state":"in_effect","voters":[{"value":"approve"}],"approve_count":1"#),
                       "Approved. This change is now in effect.")
        XCTAssertEqual(try banner(#""status":"approved","state":"in_effect","advisory":true,"voters":[{"value":"approve"}]"#),
                       "The maintainer approved this. It is in effect.")
        XCTAssertEqual(try banner(#""status":"approved","state":"in_effect","seats_contested":1,"election_phase":"closed""#),
                       "This election has closed and the council below is seated.")
        XCTAssertEqual(try banner(#""status":"rejected","state":"lapsed""#),
                       "Voting ended without reaching quorum. This proposal lapsed and was not decided.")
        XCTAssertEqual(try banner(#""status":"rejected","state":"unsettled""#)?.hasPrefix("This election settled nothing"), true)
        XCTAssertEqual(try banner(#""status":"rejected","state":"rejected","declined_by":"Rowan""#), "Declined by Rowan.")
        XCTAssertEqual(try banner(#""status":"rejected","state":"rejected","approve_count":1,"reject_count":4"#),
                       "This proposal did not pass. 1 approved, 4 rejected.")
        XCTAssertEqual(try banner(#""status":"withdrawn","state":"withdrawn""#), "Withdrawn by the author.")
        XCTAssertEqual(try banner(#""status":"open""#)?.hasPrefix("Voting is open."), true, "an empty state falls back to the status")
    }

    func testAnElectionStillTakingNamesSaysWhenStandingCloses() throws {
        let dated = try proposal(#"{"id":"e","title":"T","status":"open","state":"voting","seats_contested":1,"election_phase":"nominating","nominations_close_at":"2026-10-05T12:00:00Z","can_vote":true}"#)
        XCTAssertTrue(VoteRules.banner(dated, now: now)!.hasPrefix("Nominations are open until "))
        XCTAssertTrue(VoteRules.banner(dated, now: now)!.hasSuffix(". Voting starts then."))
        let undated = try proposal(#"{"id":"e","title":"T","status":"open","state":"voting","seats_contested":1,"election_phase":"nominating","can_vote":true}"#)
        XCTAssertEqual(VoteRules.banner(undated, now: now), "Nominations are open. Voting starts when they close.")
        XCTAssertFalse(VoteRules.castsBelow(dated, now: now), "can_vote is not phase-aware; the ballot is")
    }

    // MARK: - The vote section

    func testQuorumSentences() throws {
        XCTAssertEqual(VoteRules.quorumLine(try voting(), now: now), "Quorum met (5 of 12 voted, 20% needed)")
        XCTAssertEqual(VoteRules.quorumLine(try voting(approve: 1, reject: 0), now: now), "Quorum not yet met (1 of 3 needed)")
        XCTAssertEqual(VoteRules.quorumLine(try voting(approve: 1, reject: 0, endsAt: "2026-09-28T00:00:00Z"), now: now),
                       "Quorum not met (1 of 3 needed)", "a window that has run promises nothing")
        XCTAssertEqual(VoteRules.quorumLine(try voting(quorum: 0), now: now), "No quorum required")
        XCTAssertEqual(VoteRules.quorumLine(try voting(extra: #","advisory":true"#), now: now), "No quorum. This vote advises; it does not decide.")
        XCTAssertEqual(VoteRules.quorumNeeded(eligible: 12, percent: 20), 3)
        XCTAssertEqual(VoteRules.quorumNeeded(eligible: 10, percent: 20), 2)
        XCTAssertEqual(VoteRules.quorumNeeded(eligible: 7, percent: 50), 4)
    }

    func testTheAmendmentThresholdAppliesOnlyToAnAmendment() throws {
        let terms = #","voting_terms":{"decision_method":"majority","amendment_threshold":"supermajority"}"#
        let action = try proposal(#"{"id":"p","title":"T","proposal_type":"action"\#(terms)}"#)
        let amendment = try proposal(#"{"id":"p","title":"T","proposal_type":"amendment"\#(terms)}"#)
        XCTAssertEqual(VoteRules.thresholdLine(action), "Majority: more than half of votes must approve")
        XCTAssertEqual(VoteRules.thresholdLine(amendment), "Supermajority: at least 2 out of 3 votes must approve")
        let consensus = try proposal(#"{"id":"p","title":"T","voting_terms":{"decision_method":"consensus"}}"#)
        XCTAssertEqual(VoteRules.thresholdLine(consensus), "Consensus: one reject blocks it")
        XCTAssertEqual(VoteRules.thresholdLine(try proposal(awaitingJSON)), "Advisory: the maintainer decides, with this tally in front of them")
    }

    func testTheTermsLineStatesTheRulesAndTheTenureInForce() throws {
        let locale = Locale(identifier: "en_US")
        let zone = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(VoteRules.termsLine(try voting(), locale: locale, timeZone: zone), "Rules as of Sep 26")
        XCTAssertEqual(VoteRules.termsLine(try voting(canVote: false, extra: #","vote_eligible_at":"2026-10-03""#), locale: locale, timeZone: zone),
                       "Rules as of Sep 26. You can vote here from October 3", "a calendar day, never the day before")
        XCTAssertEqual(VoteRules.termsLine(try voting(canVote: false, extra: #","tenure_days":30"#), locale: locale, timeZone: zone),
                       "Rules as of Sep 26. Voting requires 30 days’ membership")
        XCTAssertEqual(VoteRules.termsLine(try voting(canVote: true, extra: #","tenure_days":30"#), locale: locale, timeZone: zone),
                       "Rules as of Sep 26", "a member who may vote is not recited the rule")
        XCTAssertNil(VoteRules.termsLine(try proposal(#"{"id":"p","title":"T"}"#)))
    }

    func testWhereTheTallyAndTheButtonsAppear() throws {
        let open = try voting()
        XCTAssertTrue(VoteRules.showsVoteSection(open))
        XCTAssertTrue(VoteRules.showsButtons(open))
        XCTAssertFalse(VoteRules.showsButtons(try voting(canVote: false)))
        let direct = try proposal(#"{"id":"p","title":"T","status":"approved","state":"in_effect","voters":[]}"#)
        XCTAssertFalse(VoteRules.showsVoteSection(direct), "a direct change was never voted on")
        let advisoryAlone = try proposal(#"{"id":"p","title":"T","status":"rejected","state":"rejected","advisory":true,"voters":[]}"#)
        XCTAssertFalse(VoteRules.showsTally(advisoryAlone), "a maintainer who decided alone has no tally")
        XCTAssertFalse(VoteRules.showsTally(try proposal(awaitingJSON)))
        XCTAssertTrue(VoteRules.showsTally(try proposal(#"{"id":"p","title":"T","status":"rejected","state":"lapsed","approve_count":2}"#)))
        XCTAssertFalse(VoteRules.showsTally(try proposal(#"{"id":"p","title":"T","status":"withdrawn","state":"withdrawn"}"#)))
    }

    func testTheSoleVoterIsToldTheirVoteDecides() throws {
        XCTAssertTrue(VoteRules.soleVoter(try voting(eligible: 1)))
        XCTAssertFalse(VoteRules.soleVoter(try voting(eligible: 2)))
        XCTAssertFalse(VoteRules.soleVoter(try voting(eligible: 1, extra: #","advisory":true"#)), "an advisory vote decides nothing early")
    }

    func testTheBarsFillsAndTheCompactTally() throws {
        let p = try voting(approve: 2, reject: 1, abstain: 1)
        XCTAssertEqual(VoteRules.fills(p).approve, 0.5, "abstentions are part of the total")
        XCTAssertEqual(VoteRules.fills(p).reject, 0.25)
        XCTAssertEqual(VoteRules.countsLine(p), "2 approve · 1 reject · 1 abstain")
        XCTAssertEqual(VoteRules.compactTally(p, now: now), "2✓ 1✗ · 1 abstain · 4d")
        XCTAssertEqual(VoteRules.compactTally(try voting(approve: 5, reject: 1), now: now), "5✓ 1✗ · 4d", "no abstentions, no word for them")
        XCTAssertEqual(VoteRules.fills(try voting(approve: 0, reject: 0)).approve, 0)
    }

    func testTheCurrentVoteAndItsWords() throws {
        XCTAssertEqual(VoteRules.myVote(try voting(myVote: "reject")), .reject)
        XCTAssertNil(VoteRules.myVote(try voting(myVote: "")))
        XCTAssertEqual(VoteRules.Value.approve.past, "Approved")
        XCTAssertEqual(VoteRules.Value.reject.past, "Rejected")
        XCTAssertEqual(VoteRules.Value.abstain.past, "Abstained")
        XCTAssertEqual(VoteRules.Value.allCases.map(\.present), ["Approve", "Reject", "Abstain"])
    }

    // MARK: - Who owes a ballot, and what counts as a direct change

    func testNeedsMyVoteOnAnOrdinaryProposal() throws {
        XCTAssertTrue(VoteRules.needsMyVote(try voting(canVote: true, myVote: "")))
        XCTAssertFalse(VoteRules.needsMyVote(try voting(canVote: true, myVote: "abstain")), "an abstention is a ballot")
        XCTAssertFalse(VoteRules.needsMyVote(try voting(canVote: false, myVote: "")))
    }

    func testNeedsMyVoteInAnElection() throws {
        func election(phase: String, approved: Bool, abstained: Bool) throws -> Proposal {
            try proposal(#"{"id":"e","title":"T","status":"open","state":"voting","seats_contested":1,"election_phase":"\#(phase)","can_vote":true,"i_abstained":\#(abstained),"candidates":[{"id":"c1","approved_by_me":\#(approved)}]}"#)
        }
        XCTAssertTrue(VoteRules.needsMyVote(try election(phase: "voting", approved: false, abstained: false)))
        XCTAssertFalse(VoteRules.needsMyVote(try election(phase: "voting", approved: true, abstained: false)))
        XCTAssertFalse(VoteRules.needsMyVote(try election(phase: "voting", approved: false, abstained: true)))
        XCTAssertFalse(VoteRules.needsMyVote(try election(phase: "nominating", approved: false, abstained: false)))
    }

    func testDirectChangeDetection() throws {
        XCTAssertTrue(try proposal(#"{"id":"p","title":"T","status":"approved","state":"in_effect","voters":[]}"#).isDirectChange)
        XCTAssertFalse(try proposal(#"{"id":"p","title":"T","status":"approved","state":"in_effect","voters":[{"value":"approve","counted":false}]}"#).isDirectChange,
                       "a vote whose every ballot stopped counting still happened")
        XCTAssertFalse(try proposal(#"{"id":"p","title":"T","status":"approved","state":"approved","voters":[]}"#).isDirectChange)
        // A list row carries no voters: the web list's own test.
        XCTAssertTrue(try proposal(#"{"id":"p","title":"T","status":"approved","approve_count":0}"#).isDirectChange)
        XCTAssertFalse(try proposal(#"{"id":"p","title":"T","status":"approved","approve_count":3}"#).isDirectChange)
    }

    // MARK: - The election

    func testTheBallotIsOpenOnlyInTheVotingPhaseToAVoterWithTimeLeft() throws {
        func election(phase: String, canVote: Bool, ends: String) throws -> Proposal {
            try proposal(#"{"id":"e","title":"T","status":"open","state":"voting","seats_contested":1,"election_phase":"\#(phase)","can_vote":\#(canVote),"voting_ends_at":"\#(ends)"}"#)
        }
        XCTAssertTrue(VoteRules.ballotOpen(try election(phase: "voting", canVote: true, ends: "2026-10-02T00:00:00Z"), now: now))
        XCTAssertFalse(VoteRules.ballotOpen(try election(phase: "nominating", canVote: true, ends: "2026-10-02T00:00:00Z"), now: now))
        XCTAssertFalse(VoteRules.ballotOpen(try election(phase: "voting", canVote: false, ends: "2026-10-02T00:00:00Z"), now: now))
        XCTAssertFalse(VoteRules.ballotOpen(try election(phase: "voting", canVote: true, ends: "2026-09-28T00:00:00Z"), now: now),
                       "the server takes it until the sweep; nobody should be offered it")
    }

    func testTheElectionsWords() throws {
        let voting = try proposal(#"{"id":"e","title":"T","seats_contested":2,"election_phase":"voting","election_turnout":{"voted":4,"eligible":12,"needed":3,"met":true}}"#)
        XCTAssertEqual(VoteRules.electionHeading(voting), "The ballot")
        XCTAssertEqual(VoteRules.seatsLabel(1), "1 seat")
        XCTAssertEqual(VoteRules.seatsLabel(2), "2 seats")
        XCTAssertEqual(VoteRules.electionLede(voting), "Approve as many candidates as you like. The 2 most approved take the seats.")
        XCTAssertEqual(VoteRules.turnoutLine(voting), "Quorum met: 4 of 12 voted, 3 needed.")
        let closed = try proposal(#"{"id":"e","title":"T","seats_contested":1,"election_phase":"closed","election_turnout":{"voted":1,"eligible":12,"needed":3,"met":false}}"#)
        XCTAssertEqual(VoteRules.electionHeading(closed), "Result")
        XCTAssertEqual(VoteRules.turnoutLine(closed), "Quorum not met: 1 of 12 voted, 3 needed.")
        let nominating = try proposal(#"{"id":"e","title":"T","seats_contested":1,"election_phase":"nominating","election_turnout":{"voted":0,"eligible":12,"needed":0,"met":true}}"#)
        XCTAssertNil(VoteRules.turnoutLine(nominating), "nothing to be short of while names are taken")
        XCTAssertEqual(VoteRules.electionHeading(nominating), "Nominations")
    }

    func testAContestResolvedBeforeSeatsWereStoredSeatsTheTopApproved() throws {
        let p = try proposal(#"{"id":"e","title":"T","status":"approved","state":"in_effect","seats_contested":1,"election_phase":"closed","candidates":[{"id":"a","approvals":3},{"id":"b","approvals":1}]}"#)
        XCTAssertTrue(VoteRules.isSeated(p.candidates![0], at: 0, in: p))
        XCTAssertFalse(VoteRules.isSeated(p.candidates![1], at: 1, in: p))
        let stored = try proposal(#"{"id":"e","title":"T","status":"approved","state":"in_effect","seats_contested":1,"election_phase":"closed","candidates":[{"id":"a","approvals":3,"seated":false},{"id":"b","approvals":1,"seated":true}]}"#)
        XCTAssertFalse(VoteRules.isSeated(stored.candidates![0], at: 0, in: stored), "a stored outcome is the outcome")
        XCTAssertTrue(VoteRules.isSeated(stored.candidates![1], at: 1, in: stored))
    }

    func testTheStatementIsCountedInRunes() {
        XCTAssertEqual(VoteRules.charactersLeft(""), 500)
        XCTAssertEqual(VoteRules.charactersLeft("\u{2764}\u{FE0F}"), 498, "the heart is two runes to the server")
        XCTAssertEqual(VoteRules.clipStatement(String(repeating: "a", count: 600)).count, 500)
    }

    func testWhoCanBePutForward() {
        let members = [
            PatchMember(id: "m1", userId: "me", username: "me", displayName: nil, avatarUrl: nil, role: "member"),
            PatchMember(id: "m2", userId: "u2", username: "imani", displayName: nil, avatarUrl: nil, role: "admin"),
            PatchMember(id: "m3", userId: "u3", username: "theo", displayName: nil, avatarUrl: nil, role: "member"),
            PatchMember(id: "m4", userId: "u4", username: "fan", displayName: nil, avatarUrl: nil, role: "follower"),
        ]
        let standing = [Candidate(id: "c1", userId: "u3")]
        XCTAssertEqual(VoteRules.nominatable(members, me: "me", candidates: standing).map(\.id), ["m2"])
    }

    // MARK: - What the acts send

    func testTheBallotSendsTheWholeSetOrAbstains() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        func json(_ body: some Encodable) throws -> String { String(decoding: try encoder.encode(body), as: UTF8.self) }
        XCTAssertEqual(try json(BallotBody.abstaining), #"{"abstain":true,"candidate_ids":[]}"#)
        XCTAssertEqual(try json(BallotBody.approving(["c2", "c1"])), #"{"abstain":false,"candidate_ids":["c1","c2"]}"#,
                       "row ids, whole set, in a stable order")
        XCTAssertEqual(try json(BallotBody.approving([String]())), #"{"abstain":false,"candidate_ids":[]}"#,
                       "an empty set without abstain takes the ballot back")
        XCTAssertEqual(try json(CandidacyBody(userId: nil, statement: "Keys.")), #"{"statement":"Keys."}"#)
        XCTAssertEqual(try json(CandidacyBody(userId: "u3", statement: nil)), #"{"user_id":"u3"}"#)
        XCTAssertEqual(try json(CommentBody(body: "Hi", parentId: "c1")), #"{"body":"Hi","parent_id":"c1"}"#)
        XCTAssertEqual(try json(CommentBody(body: "Hi", parentId: nil)), #"{"body":"Hi"}"#)
    }

    func testTheHeartSurvivesThePath() throws {
        let path = PatchworkAPI.reactionPath(comment: "c1", emoji: Discussion.heart)
        XCTAssertEqual(path, "comments/c1/reactions/%E2%9D%A4%EF%B8%8F")
        XCTAssertEqual(PatchworkAPI.reactionPath(comment: "c1", emoji: "\u{2764}"), path, "a bare heart is sent with its selector")
        let url = PatchworkAPI.requestURL(base: URL(string: "https://quilt.example.org")!, path: path)
        XCTAssertEqual(url.absoluteString, "https://quilt.example.org/api/v1/comments/c1/reactions/%E2%9D%A4%EF%B8%8F",
                       "escaped once, not twice")
        let last = try XCTUnwrap(url.absoluteString.split(separator: "/").last.map(String.init)?.removingPercentEncoding)
        XCTAssertEqual(Array(last.unicodeScalars), [Unicode.Scalar(0x2764)!, Unicode.Scalar(0xFE0F)!])
        XCTAssertEqual(PatchworkAPI.requestURL(base: URL(string: "https://localhost:8443/")!, path: "proposals/p1/vote").absoluteString,
                       "https://localhost:8443/api/v1/proposals/p1/vote")
    }

    func testTheNomineePickerPagesByAfter() {
        XCTAssertEqual(PatchworkAPI.memberPageQuery(after: nil), [URLQueryItem(name: "limit", value: "100")])
        XCTAssertEqual(PatchworkAPI.memberPageQuery(after: "m100"),
                       [URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "after", value: "m100")],
                       "the server reads `after`; `cursor` is ignored")
    }

    func testARefusalSentAsPlainTextIsStillTheServersSentence() {
        // Go's `http.Error` sends the JSON with `text/plain` and a newline.
        let error = APIError.from(status: 403, data: Data("{\"error\":\"must be member of node to vote\"}\n".utf8))
        XCTAssertEqual(error, .message("must be member of node to vote", status: 403))
        XCTAssertEqual(ProposalDetailView.sentence(error, fallback: "Your vote was not recorded."), "Must be member of node to vote")
        XCTAssertEqual(ProposalDetailView.sentence(APIError.status(500), fallback: "Your vote was not recorded."), "Your vote was not recorded.")
    }

    // MARK: - The discussion

    func testReactionsKeepTheFixedOrderWhateverTheServerSent() {
        let sent = [Reaction(emoji: "\u{1F440}", count: 1, me: false), Reaction(emoji: "\u{2764}", count: 2, me: true), Reaction(emoji: "\u{1F44D}", count: 3, me: false)]
        let all = Discussion.chips(sent, canReact: true)
        XCTAssertEqual(all.map(\.emoji), Discussion.emoji, "all six, in the web's order")
        XCTAssertEqual(all.map(\.count), [3, 0, 2, 0, 0, 1])
        XCTAssertEqual(all[2], Discussion.Chip(emoji: Discussion.heart, count: 2, me: true), "a bare heart is the heart")
        let seen = Discussion.chips(sent, canReact: false)
        XCTAssertEqual(seen.map(\.emoji), ["\u{1F44D}", Discussion.heart, "\u{1F440}"], "without standing, only the used ones")
        XCTAssertFalse(seen.contains { $0.me })
        XCTAssertEqual(Discussion.heart.unicodeScalars.map(\.value), [0x2764, 0xFE0F])
    }

    func testWhoMayDiscuss() {
        let open = FollowerPermissions(events: true, proposals: true)
        let closed = FollowerPermissions(events: true, proposals: false)
        XCTAssertTrue(Discussion.canDiscuss(standing: .active(.member), followerPermissions: closed, isInstanceAdmin: false))
        XCTAssertTrue(Discussion.canDiscuss(standing: .active(.admin), followerPermissions: closed, isInstanceAdmin: false))
        XCTAssertTrue(Discussion.canDiscuss(standing: .active(.follower), followerPermissions: open, isInstanceAdmin: false))
        XCTAssertTrue(Discussion.canDiscuss(standing: .active(.follower), followerPermissions: nil, isInstanceAdmin: false), "absent reads as allowed")
        XCTAssertFalse(Discussion.canDiscuss(standing: .active(.follower), followerPermissions: closed, isInstanceAdmin: false),
                       "the patch keeps its followers out")
        XCTAssertFalse(Discussion.canDiscuss(standing: .pending, followerPermissions: open, isInstanceAdmin: false))
        XCTAssertFalse(Discussion.canDiscuss(standing: nil, followerPermissions: open, isInstanceAdmin: false))
        XCTAssertTrue(Discussion.canDiscuss(standing: nil, followerPermissions: nil, isInstanceAdmin: true))
    }

    func testTheAuthorEditsAndTheAuthorOrAnAdminDeletes() {
        let mine = ProposalComment(id: "c1", authorId: "me")
        let theirs = ProposalComment(id: "c2", authorId: "u2", replies: [ProposalComment(id: "r1"), ProposalComment(id: "r2")])
        XCTAssertTrue(Discussion.canEdit(mine, me: "me"))
        XCTAssertFalse(Discussion.canEdit(theirs, me: "me"))
        XCTAssertFalse(Discussion.canEdit(mine, me: nil))
        XCTAssertFalse(Discussion.canEdit(ProposalComment(id: "c3", authorId: ""), me: ""))
        XCTAssertTrue(Discussion.canDelete(mine, me: "me", standing: .active(.member), isInstanceAdmin: false))
        XCTAssertFalse(Discussion.canDelete(theirs, me: "me", standing: .active(.member), isInstanceAdmin: false))
        XCTAssertTrue(Discussion.canDelete(theirs, me: "me", standing: .active(.admin), isInstanceAdmin: false), "a patch admin")
        XCTAssertTrue(Discussion.canDelete(theirs, me: "me", standing: nil, isInstanceAdmin: true), "a quilt admin")
        XCTAssertFalse(Discussion.canEdit(theirs, me: "u3"), "an admin still cannot edit")
        XCTAssertEqual(Discussion.deleteMessage(theirs), "Its 2 replies go with it.")
        XCTAssertEqual(Discussion.deleteMessage(ProposalComment(id: "c", replies: [ProposalComment(id: "r")])), "Its 1 reply goes with it.")
        XCTAssertNil(Discussion.deleteMessage(mine))
    }

    // MARK: - The governance home and the list

    func testTheHomeAndTheRowsSayWhatIsOwedAndWhatIsLeft() throws {
        XCTAssertEqual(PatchGovernanceHome.needsVoteLine(1), "1 proposal needs your vote")
        XCTAssertEqual(PatchGovernanceHome.needsVoteLine(3), "3 proposals need your vote")
        let overview = try decoder().decode(GovernanceOverview.self, from: Data(#"{"needs_vote":2}"#.utf8))
        XCTAssertEqual(overview.needsVote, 2)
        XCTAssertEqual(PatchProposalList.rowLine(try voting(), now: now), "4d left")
        XCTAssertEqual(PatchProposalList.rowLine(try proposal(awaitingJSON), now: now), "waiting on the maintainer")
        XCTAssertEqual(PatchProposalList.rowLine(try proposal(#"{"id":"p","title":"T","status":"rejected","state":"lapsed"}"#), now: now), "lapsed")
        XCTAssertNil(PatchProposalList.rowLine(try proposal(#"{"id":"p","title":"T","status":"approved","approve_count":0}"#), now: now),
                     "a direct change says nothing more")
    }
}
