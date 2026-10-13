// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import Patchwork

/// Raising a proposal and withdrawing your own, as values: who is shown the
/// door, what the form becomes under each way a patch decides, the window it
/// starts on, what is checked before sending, and exactly what is sent.
final class ProposalPostingTests: XCTestCase {
    private func json(_ body: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(body), as: UTF8.self)
    }
    private let majority = GovernanceRules(decisionMethod: "majority", defaultVoteDurationHours: 336, proposalVenue: "patchwork")
    private let adminDecides = GovernanceRules(decisionMethod: "admin", defaultVoteDurationHours: 48, proposalVenue: "patchwork")
    private let elsewhere = GovernanceRules(decisionMethod: "majority", defaultVoteDurationHours: 168, proposalVenue: "elsewhere")

    // MARK: The door

    func testMembersAndAdminsMayProposeAndNobodyElse() {
        XCTAssertTrue(ProposalPosting.mayPropose(signedIn: true, standing: .active(.member)))
        XCTAssertTrue(ProposalPosting.mayPropose(signedIn: true, standing: .active(.admin)))
        XCTAssertFalse(ProposalPosting.mayPropose(signedIn: true, standing: .active(.follower)), "following carries no authorship")
        XCTAssertFalse(ProposalPosting.mayPropose(signedIn: true, standing: .pending), "a request nobody has answered")
        XCTAssertFalse(ProposalPosting.mayPropose(signedIn: true, standing: nil), "a quilt admin with no role here is refused too")
        XCTAssertFalse(ProposalPosting.mayPropose(signedIn: false, standing: .active(.member)), "signed out is nobody")
    }

    func testTheDoorNamesTheOutcomeAndWaitsForTheRules() {
        XCTAssertEqual(ProposalPosting.door(signedIn: true, standing: .active(.member), rules: majority), "New proposal")
        XCTAssertEqual(ProposalPosting.door(signedIn: true, standing: .active(.admin), rules: majority), "New proposal")
        XCTAssertEqual(ProposalPosting.door(signedIn: true, standing: .active(.member), rules: adminDecides), "New proposal")
        XCTAssertEqual(ProposalPosting.door(signedIn: true, standing: .active(.admin), rules: adminDecides), "New change",
                       "a direct change is never called a proposal")
        XCTAssertNil(ProposalPosting.door(signedIn: true, standing: .active(.member), rules: nil), "no rules, no form to open")
        XCTAssertNil(ProposalPosting.door(signedIn: true, standing: .active(.follower), rules: majority))
        XCTAssertNil(ProposalPosting.door(signedIn: false, standing: nil, rules: majority))
    }

    // MARK: Each way a patch decides

    func testAVotingPatchVotes() {
        let outcome = ProposalPosting.outcome(rules: majority, isPatchAdmin: false, putToVote: false)
        XCTAssertEqual(outcome, .vote)
        XCTAssertEqual(ProposalPosting.outcome(rules: majority, isPatchAdmin: true, putToVote: false), .vote, "admins vote here too")
        XCTAssertTrue(ProposalPosting.asksDuration(outcome))
        XCTAssertEqual(ProposalPosting.durationLabel(outcome), "Voting duration")
        XCTAssertEqual(ProposalPosting.submitLabel(outcome, busy: false), "Submit proposal")
        XCTAssertEqual(ProposalPosting.submitLabel(outcome, busy: true), "Creating…")
        XCTAssertFalse(ProposalPosting.adminChooses(majority, isPatchAdmin: true), "nobody chooses on a voting patch")
    }

    func testAnAdminOfAnAdminDecidesPatchAppliesOrAsks() {
        XCTAssertTrue(ProposalPosting.adminChooses(adminDecides, isPatchAdmin: true))
        let applied = ProposalPosting.outcome(rules: adminDecides, isPatchAdmin: true, putToVote: false)
        XCTAssertEqual(applied, .applied)
        XCTAssertFalse(ProposalPosting.asksDuration(applied), "a direct change has no window")
        XCTAssertEqual(ProposalPosting.submitLabel(applied, busy: false), "Apply change")
        XCTAssertEqual(ProposalPosting.submitLabel(applied, busy: true), "Applying…")
        XCTAssertNil(ProposalPosting.outcomeNote(applied))
        for words in [ProposalPosting.submitLabel(applied, busy: false), ProposalPosting.submitLabel(applied, busy: true),
                      ProposalPosting.choices(adminDecides)[0].label, "New change"] {
            XCTAssertFalse(words.localizedCaseInsensitiveContains("propos"), words)
            XCTAssertFalse(words.localizedCaseInsensitiveContains("vote"), words)
            XCTAssertFalse(words.localizedCaseInsensitiveContains("submit"), words)
        }

        let asked = ProposalPosting.outcome(rules: adminDecides, isPatchAdmin: true, putToVote: true)
        XCTAssertEqual(asked, .advisoryVote)
        XCTAssertTrue(ProposalPosting.asksDuration(asked))
        XCTAssertEqual(ProposalPosting.durationLabel(asked), "How long to ask")
        XCTAssertEqual(ProposalPosting.submitLabel(asked, busy: false), "Open advisory vote")
        XCTAssertEqual(ProposalPosting.choices(adminDecides).map(\.label), ["Apply it now", "Ask the members first"])
    }

    func testAMembersProposalOnAnAdminDecidesPatchGoesToTheMaintainer() {
        XCTAssertFalse(ProposalPosting.adminChooses(adminDecides, isPatchAdmin: false))
        let outcome = ProposalPosting.outcome(rules: adminDecides, isPatchAdmin: false, putToVote: true)
        XCTAssertEqual(outcome, .toMaintainer, "a member's put_to_vote means nothing")
        XCTAssertFalse(ProposalPosting.asksDuration(outcome))
        XCTAssertEqual(ProposalPosting.submitLabel(outcome, busy: false), "Send to the maintainer")
        XCTAssertEqual(ProposalPosting.outcomeNote(outcome),
                       "This patch’s maintainer decides proposals. Yours goes to them, and they may ask the members before deciding.")
    }

    func testAPatchThatDecidesElsewhereHasNoBallotAndNoClock() {
        let member = ProposalPosting.outcome(rules: elsewhere, isPatchAdmin: false, putToVote: false)
        XCTAssertEqual(member, .discussion)
        XCTAssertFalse(ProposalPosting.asksDuration(member))
        XCTAssertTrue(ProposalPosting.outcomeNote(member)?.contains("no vote and no clock") == true)
        XCTAssertEqual(ProposalPosting.outcome(rules: elsewhere, isPatchAdmin: true, putToVote: false), .discussion)

        // Both at once: the server applies an admin's change first, and the
        // venue takes everything else — a member's request included.
        var both = adminDecides
        both.proposalVenue = "elsewhere"
        XCTAssertEqual(ProposalPosting.outcome(rules: both, isPatchAdmin: true, putToVote: false), .applied)
        XCTAssertEqual(ProposalPosting.outcome(rules: both, isPatchAdmin: true, putToVote: true), .discussion)
        XCTAssertEqual(ProposalPosting.outcome(rules: both, isPatchAdmin: false, putToVote: false), .discussion)
        let ask = ProposalPosting.choices(both)[1]
        XCTAssertFalse(ask.label.localizedCaseInsensitiveContains("members"), "asking first is not a vote there")
        XCTAssertEqual(ask.label, "Open it for discussion first")
    }

    // MARK: The window

    func testTheWindowStartsOnThePatchsOwnDefault() {
        XCTAssertEqual(ProposalPosting.defaultDuration(majority), 336, "not the web's hard-coded 72")
        XCTAssertEqual(ProposalPosting.defaultDuration(nil), 72, "the server's fallback")
        XCTAssertEqual(ProposalPosting.defaultDuration(GovernanceRules(defaultVoteDurationHours: 0)), 72)
        XCTAssertEqual(ProposalPosting.durationChoices(majority).map(\.hours), [24, 48, 72, 168, 336])
        let fiveDays = GovernanceRules(defaultVoteDurationHours: 120)
        XCTAssertEqual(ProposalPosting.durationChoices(fiveDays).map(\.hours), [24, 48, 72, 120, 168, 336],
                       "a default that is not one of the five joins them")
        XCTAssertEqual(ProposalPosting.durationChoices(fiveDays).first { $0.hours == 120 }?.label, "5 days")
        XCTAssertEqual(ProposalPosting.durationName(504), "3 weeks")
        XCTAssertEqual(ProposalPosting.durationName(36), "36 hours")
        XCTAssertEqual(ProposalPosting.durationName(72), "72 hours (3 days)")
        XCTAssertEqual(ProposalPosting.durationHint(majority), "This patch’s rules give a vote 2 weeks unless you choose otherwise.")
        XCTAssertTrue(ProposalPosting.durationHint(nil).hasPrefix("Tip: 72 hours"))
    }

    // MARK: Checked, then sent

    func testOnlyTheTitleIsCheckedAndInTheServersWords() {
        XCTAssertEqual(ProposalPosting.problem(ProposalDraft()), "title is required")
        XCTAssertEqual(ProposalPosting.problem(ProposalDraft(title: "  \n ")), "title is required", "a title of spaces is no title")
        XCTAssertEqual(EventPosting.sentenceCased("title is required"), "Title is required", "the web's own sentence")
        let long = ProposalDraft(title: String(repeating: "🧵", count: 500), body: String(repeating: "x", count: 100_000))
        XCTAssertNil(ProposalPosting.problem(long), "the server sets no length limit, so neither does this")
    }

    func testAVoteSendsItsWindowAndNoFlag() throws {
        let draft = ProposalDraft(title: "  Open on Tuesdays ", body: "\nBecause.\n", kind: .action, durationHours: 168, putToVote: true)
        let body = ProposalBody(draft, rules: majority, isPatchAdmin: true)
        XCTAssertEqual(try json(body), #"{"body":"Because.","duration_hours":168,"proposal_type":"action","title":"Open on Tuesdays"}"#)
    }

    func testADirectChangeSendsNoWindow() throws {
        let draft = ProposalDraft(title: "New projector", kind: .other, durationHours: 48)
        let body = ProposalBody(draft, rules: adminDecides, isPatchAdmin: true)
        XCTAssertEqual(try json(body), #"{"body":"","proposal_type":"other","put_to_vote":false,"title":"New projector"}"#)
    }

    func testAnAdvisoryVoteSendsBoth() throws {
        let draft = ProposalDraft(title: "New projector", durationHours: 24, putToVote: true)
        let body = ProposalBody(draft, rules: adminDecides, isPatchAdmin: true)
        XCTAssertEqual(body.durationHours, 24)
        XCTAssertEqual(body.putToVote, true)
    }

    func testARequestToTheMaintainerAndADiscussionSendNeither() {
        let draft = ProposalDraft(title: "Later starts", durationHours: 72, putToVote: true)
        let request = ProposalBody(draft, rules: adminDecides, isPatchAdmin: false)
        XCTAssertNil(request.durationHours)
        XCTAssertNil(request.putToVote, "only an admin who chooses sends the flag")
        let discussion = ProposalBody(draft, rules: elsewhere, isPatchAdmin: false)
        XCTAssertNil(discussion.durationHours, "no clock where nothing is put to a vote")
        XCTAssertNil(discussion.putToVote)
    }

    func testTheAnswerIsReadAsAProposal() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let made = try decoder.decode(Proposal.self, from: Data("""
        {"id":"p9","node_id":"n1","author_id":"u1","title":"New projector","body":"","status":"approved",
         "proposal_type":"other","duration_hours":48,"voting_ends_at":null,"created_at":"2026-10-13T10:00:00Z",
         "updated_at":"2026-10-13T10:00:00Z","target_doc":"","proposed_branch":"","proposed_body":"",
         "proposed_title":"","git_sha":"","state":"in_effect"}
        """.utf8))
        XCTAssertEqual(made.id, "p9")
        XCTAssertNil(made.votingEndsAt)
        XCTAssertEqual(made.state, "in_effect")
    }

    // MARK: Nominations stay the website's

    func testTheNominationNoteOnlyWhereTheWebWouldOfferIt() {
        let meritocratic = GovernanceRules(leadershipModel: "meritocratic", leadershipVenue: "patchwork")
        XCTAssertTrue(ProposalPosting.webOffersNomination(rules: meritocratic, seats: [], isPatchAdmin: true))
        XCTAssertFalse(ProposalPosting.webOffersNomination(rules: meritocratic, seats: [], isPatchAdmin: false))
        let elected = GovernanceRules(leadershipModel: "elected", leadershipVenue: "patchwork")
        let vacant = GovernanceSeat(id: "s1", username: nil, displayName: nil, termEndsAt: nil, vacant: true, fill: nil,
                                    contestOpens: nil, contestDue: nil, contestId: nil, holderWithheld: nil)
        let held = GovernanceSeat(id: "s2", username: "rowan", displayName: nil, termEndsAt: nil, vacant: false, fill: nil,
                                  contestOpens: nil, contestDue: nil, contestId: nil, holderWithheld: nil)
        XCTAssertTrue(ProposalPosting.webOffersNomination(rules: elected, seats: [held, vacant], isPatchAdmin: true))
        XCTAssertFalse(ProposalPosting.webOffersNomination(rules: elected, seats: [held], isPatchAdmin: true), "no vacancy")
        let away = GovernanceRules(leadershipModel: "meritocratic", leadershipVenue: "elsewhere")
        XCTAssertFalse(ProposalPosting.webOffersNomination(rules: away, seats: [], isPatchAdmin: true))
        XCTAssertFalse(ProposalPosting.webOffersNomination(rules: GovernanceRules(leadershipModel: "maintainer"), seats: [], isPatchAdmin: true))
    }

    // MARK: Withdrawing

    func testOnlyTheAuthorWithdrawsAnOpenProposal() {
        var mine = Proposal(id: "p1", title: "T", status: "open", state: "voting")
        mine.authorId = "me"
        XCTAssertTrue(ProposalPosting.mayWithdraw(mine, me: "me"))
        XCTAssertFalse(ProposalPosting.mayWithdraw(mine, me: "someone-else"), "the web offers it to the author only")
        XCTAssertFalse(ProposalPosting.mayWithdraw(mine, me: nil))
        for state in ["awaiting_admin", "elsewhere"] {
            var waiting = mine
            waiting.state = state
            XCTAssertTrue(ProposalPosting.mayWithdraw(waiting, me: "me"), state)
        }
        var applied = mine
        applied.status = "approved"; applied.state = "in_effect"
        XCTAssertFalse(ProposalPosting.mayWithdraw(applied, me: "me"), "only an open one")
        var gone = mine
        gone.status = "withdrawn"; gone.state = "withdrawn"
        XCTAssertFalse(ProposalPosting.mayWithdraw(gone, me: "me"))
        var election = mine
        election.seatsContested = 2
        XCTAssertFalse(ProposalPosting.mayWithdraw(election, me: "me"), "the calendar opens an election, and nobody withdraws one")
        var legacy = Proposal(id: "p2", title: "T", status: "open")
        legacy.authorId = "me"
        XCTAssertTrue(ProposalPosting.mayWithdraw(legacy, me: "me"), "an open row with no state is voting")
    }

    func testTheWithdrawalPath() {
        XCTAssertEqual(ProposalPosting.withdrawLabel, "Withdraw this proposal")
        XCTAssertEqual(ProposalPosting.withdrawQuestion, "Are you sure?")
    }
}
