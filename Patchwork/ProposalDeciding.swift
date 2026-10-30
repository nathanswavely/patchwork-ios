// SPDX-License-Identifier: MPL-2.0

import Foundation

// Deciding and applying somebody else's proposal, from the banner where the
// web keeps the buttons (web `ProposalStatusBanner.svelte`; server
// `proposal_decide.go`, `ApplyProposal`; web ADRs 041, 047, 051, 092).
//
// Two different acts wear an admin's hands here, and they are not the same
// power. On a patch whose admins decide, the maintainer approves or declines
// any open proposal — mid-vote included, because the vote there only
// advises — and may ask the members first, once. On any patch, a proposal
// the members carried but nobody has made official yet (`approved`, where
// the patch does not apply amendments on its own) waits for an admin to put
// it in effect. Neither is offered on a voting patch's open vote: every
// voting method votes, admins included, and the server's apply gate says so.
//
// The server's `can_decide` is the gate for the first, read beside the
// reader's own standing from the membership index: the payload's answer is
// the decision gate's own, and the index is what every other act here
// reads. Neither is `is_admin`, which a quilt admin with no role also
// carries and whom both endpoints refuse.
//
// Every act is confirmed. The web asks only before a decline; approving and
// making official change the patch's governance on the spot and cannot be
// taken back, and asking the members can be done only once, so a stray tap
// on a phone should not do any of them.

enum ProposalDeciding {
    enum Act: String, Identifiable, CaseIterable {
        case approve, decline, askMembers, makeOfficial
        var id: String { rawValue }

        /// The button's word, the web's.
        var label: String {
            switch self {
            case .approve: return "Approve"
            case .decline: return "Decline"
            case .askMembers: return "Ask the members"
            case .makeOfficial: return "Make this official"
            }
        }

        /// The word it wears while the request is out.
        var busyLabel: String {
            switch self {
            case .approve, .decline: return "Working…"
            case .askMembers: return "Opening…"
            case .makeOfficial: return "Applying…"
            }
        }

        var identifier: String {
            switch self {
            case .approve: return "decideApprove"
            case .decline: return "decideDecline"
            case .askMembers: return "decideAskMembers"
            case .makeOfficial: return "makeOfficial"
            }
        }

        /// The confirmation's question.
        var question: String {
            switch self {
            case .approve: return "Approve this proposal?"
            case .decline: return "Decline this proposal?"
            case .askMembers: return "Ask the members?"
            case .makeOfficial: return "Make this official?"
            }
        }

        /// The confirmation's button: the web's own words for a decline.
        var confirmLabel: String {
            switch self {
            case .decline: return "Decline this proposal"
            default: return label
            }
        }

        var destructive: Bool { self == .decline }

        /// The web's toast fallback when the server says nothing readable.
        var fallback: String {
            switch self {
            case .approve, .decline: return "Failed to decide"
            case .askMembers: return "Failed to open the vote"
            case .makeOfficial: return "Failed to apply"
            }
        }
    }

    /// The acts this reader is offered on this proposal, in the order the
    /// web's banner stands them. Empty for everybody else.
    static func acts(_ proposal: Proposal, standing: Standing?, acting: Bool) -> [Act] {
        guard acting, standing == .active(.admin) else { return [] }
        // An election is closed by its electorate, never by an admin
        // (ADR 051); the server says `can_decide` on one anyway and then
        // refuses the decision.
        guard !proposal.isElection else { return [] }
        let state = VoteRules.effectiveState(proposal)
        if mayDecide(proposal) {
            var acts: [Act] = [.approve, .decline]
            if state == "awaiting_admin" && mayAskMembers(proposal) { acts.append(.askMembers) }
            return acts
        }
        if state == "approved" { return [.makeOfficial] }
        return []
    }

    /// The decision gate (`maintainerDecidable`), as the server answers it
    /// for this reader, on a proposal still open for a decision.
    static func mayDecide(_ proposal: Proposal) -> Bool {
        guard proposal.canDecide == true, proposal.status == "open" else { return false }
        return ["voting", "awaiting_admin"].contains(VoteRules.effectiveState(proposal))
    }

    /// The members can be asked once: a proposal whose advisory window has
    /// run carries its advice, and the server refuses a second window.
    static func mayAskMembers(_ proposal: Proposal) -> Bool {
        proposal.ballots == 0 && (proposal.votingEndsAt ?? "").isEmpty
    }

    /// The window an advisory vote opens with: the empty body the web sends
    /// takes the proposal's own terms' default, or 72 hours.
    static func advisoryHours(_ proposal: Proposal) -> Int {
        if let hours = proposal.votingTerms?.defaultVoteDurationHours, hours > 0 { return hours }
        return 72
    }

    /// What the confirmation says the act will do.
    static func message(_ act: Act, for proposal: Proposal) -> String {
        switch act {
        case .approve:
            var line = "It takes effect as soon as you approve it, and the record says you applied it."
            if proposal.ballots > 0 { line += " The members’ advice: \(VoteRules.countsLine(proposal))." }
            return line
        case .decline:
            return "It closes without taking effect, and the record says you declined it. It cannot be reopened."
        case .askMembers:
            return "Opens an advisory vote for \(ProposalPosting.durationName(advisoryHours(proposal))). You can still decide at any time, and the members can be asked only once."
        case .makeOfficial:
            return "The community approved this. Making it official puts it in effect, and the record says you applied it."
        }
    }
}

/// `POST proposals/{id}/decide`.
struct DecisionBody: Encodable, Equatable {
    let decision: String
    static let approve = DecisionBody(decision: "approve")
    static let decline = DecisionBody(decision: "decline")
}

extension PatchworkAPI {
    /// The maintainer's two verbs. The answer names the new state, and the
    /// proposal is read again after it anyway.
    func decide(proposal id: String, approve: Bool) async throws {
        try await postVoid("proposals/\(id)/decide", body: approve ? DecisionBody.approve : DecisionBody.decline)
    }

    /// An advisory vote on a proposal waiting on the maintainer, on the
    /// proposal's default window: the web sends an empty body, and so does
    /// this.
    func askTheMembers(proposal id: String) async throws {
        try await postVoid("proposals/\(id)/open-vote", body: NoBody())
    }

    /// The approved → in effect step.
    func makeOfficial(proposal id: String) async throws {
        try await postVoid("proposals/\(id)/apply")
    }

    /// Runs one act.
    func run(_ act: ProposalDeciding.Act, proposal id: String) async throws {
        switch act {
        case .approve: try await decide(proposal: id, approve: true)
        case .decline: try await decide(proposal: id, approve: false)
        case .askMembers: try await askTheMembers(proposal: id)
        case .makeOfficial: try await makeOfficial(proposal: id)
        }
    }
}
