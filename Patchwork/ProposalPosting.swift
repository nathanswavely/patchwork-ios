// SPDX-License-Identifier: MPL-2.0

import Foundation

// Raising a proposal, and taking your own back (web `ProposalForm.svelte`,
// `ProposalStatusBanner.svelte`; web ADRs 041, 048, 053, 092, 117).
//
// What the form is depends on how the patch decides, and the server decides
// it from the rules in force when the request lands: a vote, a request to
// the maintainer, a change applied on the spot, or a question left open for
// discussion because the patch decides at meetings. The web's form asks the
// same question of `decision_method` and forgets `proposal_venue`, so on a
// patch that decides elsewhere it offers a clock and a "Submit Proposal" for
// a proposal the server will open with neither. Here the server's own switch
// is ported whole, in its order, so the form says what will happen before
// anybody fills it — and the words follow ADR 041 and 092: a change applied
// directly is never called a proposal and never mentions a vote.
//
// There are no drafts (ADR 048): a proposal is born deciding, and its clock
// starts when it is made. The duration defaults to the patch's own
// `default_vote_duration_hours`, which is the server's fallback too; the web
// hard-codes 72 hours, so the patch's chosen window only ever applied to
// proposals nobody gave a duration.

enum ProposalPosting {
    // MARK: The door

    /// Who may raise a proposal: an active member or admin of this patch
    /// (the server's `mayPropose`). Not a follower, whatever the patch's
    /// `follower_permissions.proposals` says — that switch is about reading
    /// and discussing, never authorship (ADR 117) — not somebody waiting to
    /// be let in, and not a quilt admin holding no role here, whom the
    /// server refuses with "must be member of node".
    static func mayPropose(signedIn: Bool, standing: Standing?) -> Bool {
        guard signedIn else { return false }
        return standing == .active(.member) || standing == .active(.admin)
    }

    /// The door's words, or no door. It waits for the rules, because the
    /// rules are what decide what the form will be, and on an admin-decides
    /// patch an admin's door names the outcome: "New change".
    static func door(signedIn: Bool, standing: Standing?, rules: GovernanceRules?) -> String? {
        guard mayPropose(signedIn: signedIn, standing: standing), let rules else { return nil }
        return adminChooses(rules, isPatchAdmin: standing == .active(.admin)) ? "New change" : "New proposal"
    }

    /// The one sentence a follower is given where a member finds the door
    /// (web `ProposalList`).
    static let followerLine = "Become a member to create proposals and vote."

    // MARK: What the patch's rules make of it

    static func adminDecides(_ rules: GovernanceRules?) -> Bool { rules?.decisionMethod == "admin" }
    static func decidesElsewhere(_ rules: GovernanceRules?) -> Bool { rules?.proposalVenue == "elsewhere" }

    /// An admin of an admin-decides patch chooses between applying now and
    /// asking first; nobody else is offered a choice, and nobody else's
    /// request carries `put_to_vote`.
    static func adminChooses(_ rules: GovernanceRules?, isPatchAdmin: Bool) -> Bool {
        adminDecides(rules) && isPatchAdmin
    }

    /// What submitting will make, by the server's own switch in its order
    /// (`CreateProposal`): the direct change first, then the venue, then the
    /// maintainer's queue, then a vote — advisory where the maintainer asked.
    enum Outcome: Equatable {
        /// Born `in_effect`: a direct change, applied as it is saved.
        case applied
        /// Born `voting`, advising the maintainer rather than deciding.
        case advisoryVote
        /// Born `awaiting_admin`: no ballot and no clock until an admin acts.
        case toMaintainer
        /// Born `voting`, decided by the members' ballot.
        case vote
        /// Born `elsewhere`: open for discussion, with no ballot and no clock.
        case discussion
    }

    static func outcome(rules: GovernanceRules?, isPatchAdmin: Bool, putToVote: Bool) -> Outcome {
        let adminDecides = adminDecides(rules)
        if adminDecides && isPatchAdmin && !putToVote { return .applied }
        if decidesElsewhere(rules) { return .discussion }
        if adminDecides && !isPatchAdmin { return .toMaintainer }
        if adminDecides && isPatchAdmin && putToVote { return .advisoryVote }
        return .vote
    }

    /// Only a vote has a window to choose.
    static func asksDuration(_ outcome: Outcome) -> Bool { outcome == .vote || outcome == .advisoryVote }

    /// The heading of the duration field.
    static func durationLabel(_ outcome: Outcome) -> String {
        outcome == .advisoryVote ? "How long to ask" : "Voting duration"
    }

    /// The act at the foot of the form, and the word it wears while it runs.
    static func submitLabel(_ outcome: Outcome, busy: Bool) -> String {
        switch outcome {
        case .applied: return busy ? "Applying…" : "Apply change"
        case .advisoryVote: return busy ? "Opening…" : "Open advisory vote"
        case .toMaintainer: return busy ? "Sending…" : "Send to the maintainer"
        case .vote, .discussion: return busy ? "Creating…" : "Submit proposal"
        }
    }

    /// The line under the heading that says what will happen. The two an
    /// admin chooses between say it in their own descriptions instead.
    static func outcomeNote(_ outcome: Outcome) -> String? {
        switch outcome {
        case .vote:
            return "Voting opens as soon as you submit it, and runs for as long as you choose below."
        case .toMaintainer:
            return "This patch’s maintainer decides proposals. Yours goes to them, and they may ask the members before deciding."
        case .discussion:
            return "This patch decides at meetings, not here. Your proposal opens for discussion, with no vote and no clock, and what the meeting decides gets recorded on the charter afterwards."
        case .applied, .advisoryVote:
            return nil
        }
    }

    /// One of the two ways an admin of an admin-decides patch can go.
    struct Choice: Equatable {
        let putToVote: Bool
        let label: String
        let detail: String
        var identifier: String { putToVote ? "proposalAskFirst" : "proposalApplyNow" }
    }

    /// The web's two, in its words. On a patch that also decides at meetings
    /// the second is not a vote at all — the server opens it for discussion
    /// — so it is not called one.
    static func choices(_ rules: GovernanceRules?) -> [Choice] {
        let apply = Choice(putToVote: false, label: "Apply it now",
                           detail: "You decide this patch’s proposals. This takes effect as soon as you save it.")
        let ask = decidesElsewhere(rules)
            ? Choice(putToVote: true, label: "Open it for discussion first",
                     detail: "This patch decides at meetings, so nothing is put to a vote here. It stays open for discussion until you decide.")
            : Choice(putToVote: true, label: "Ask the members first",
                     detail: "Opens an advisory vote. You still decide, at any time, with the tally in front of you.")
        return [apply, ask]
    }

    // MARK: The type

    /// Action and Other. Membership is a nomination, and stays the website's.
    enum Kind: String, CaseIterable, Identifiable {
        case action, other
        var id: String { rawValue }
        var label: String { self == .action ? "Action" : "Other" }
        var detail: String {
            switch self {
            case .action: return "Propose a concrete action for the community to take"
            case .other: return "Any other proposal that needs community input"
            }
        }
    }

    /// Whether the web would offer this reader the Membership type (its
    /// `canNominate`): a patch admin, on a meritocratic patch or an elected
    /// one with a vacant seat, where leadership is Patchwork's to run. Only
    /// then is the quiet note that nominating is the website's worth saying.
    static func webOffersNomination(rules: GovernanceRules?, seats: [GovernanceSeat], isPatchAdmin: Bool) -> Bool {
        guard isPatchAdmin, let rules, rules.leadershipVenue != "elsewhere" else { return false }
        switch rules.leadershipModel {
        case "meritocratic": return true
        case "elected": return seats.contains(where: \.isVacant)
        default: return false
        }
    }

    static let nominationNote = "Nominating a member for admin happens on this quilt’s website."
    static let documentsNote = "Changing a governance document or the rules happens on this quilt’s website."

    // MARK: The window

    /// The web's five, in its words.
    static let durations: [(hours: Int, label: String)] = [
        (24, "24 hours"), (48, "48 hours"), (72, "72 hours (3 days)"), (168, "1 week"), (336, "2 weeks"),
    ]

    /// The patch's own window, as the server would apply it to a proposal
    /// sent without one; 72 hours where the patch has not chosen.
    static func defaultDuration(_ rules: GovernanceRules?) -> Int {
        if let hours = rules?.defaultVoteDurationHours, hours > 0 { return hours }
        return 72
    }

    /// The web's five, with the patch's own default among them where it is
    /// not one of the five already, in order.
    static func durationChoices(_ rules: GovernanceRules?) -> [(hours: Int, label: String)] {
        let preferred = defaultDuration(rules)
        guard !durations.contains(where: { $0.hours == preferred }) else { return durations }
        return (durations + [(preferred, durationName(preferred))]).sorted { $0.hours < $1.hours }
    }

    /// "5 days", "3 weeks", "36 hours".
    static func durationName(_ hours: Int) -> String {
        if let known = durations.first(where: { $0.hours == hours }) { return known.label }
        if hours % 168 == 0 { let n = hours / 168; return "\(n) week\(n == 1 ? "" : "s")" }
        if hours % 24 == 0 { let n = hours / 24; return "\(n) day\(n == 1 ? "" : "s")" }
        return "\(hours) hour\(hours == 1 ? "" : "s")"
    }

    /// The hint under the window: the patch's own choice where it made one,
    /// and the web's tip where it did not.
    static func durationHint(_ rules: GovernanceRules?) -> String {
        if let hours = rules?.defaultVoteDurationHours, hours > 0 {
            return "This patch’s rules give a vote \(durationName(hours)) unless you choose otherwise."
        }
        return "Tip: 72 hours gives everyone a chance to vote before the question goes stale."
    }

    // MARK: Checked before sending

    /// The server's checks that a form can fail, in its order and words.
    /// The server sets no limit on a proposal's length — nor does the web —
    /// so the one thing to check is the title, trimmed the way the web sends
    /// it, so a title of spaces is not accepted here and then shown blank.
    static func problem(_ draft: ProposalDraft) -> String? {
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "title is required" }
        return nil
    }

    // MARK: Taking it back

    /// Withdraw is offered to the author alone, as the web offers it, on an
    /// open proposal that is not an election — in the states the web's
    /// banner carries the button in. The server would also take it from a
    /// patch admin; deciding somebody else's proposal stays the website's.
    static func mayWithdraw(_ proposal: Proposal, me: String?) -> Bool {
        guard let me, !me.isEmpty, proposal.authorId == me else { return false }
        guard proposal.status == "open", !proposal.isElection else { return false }
        return ["voting", "awaiting_admin", "elsewhere"].contains(VoteRules.effectiveState(proposal))
    }

    static let withdrawLabel = "Withdraw this proposal"
    /// The web's confirmation asks "Are you sure?" and confirms with
    /// "Withdraw"; the second line says what the server then does.
    static let withdrawQuestion = "Are you sure?"
    static let withdrawMessage = "It cannot be reopened, and everyone taking part is told it was withdrawn."
}

/// A proposal being written.
struct ProposalDraft: Equatable {
    var title = ""
    var body = ""
    var kind: ProposalPosting.Kind = .action
    var durationHours = 72
    var putToVote = false
}

/// `POST nodes/{slug}/proposals`, as the web's form sends it: the title and
/// body trimmed, a window only where a vote will run, and `put_to_vote` only
/// where an admin of an admin-decides patch chose — a number or a flag the
/// server ignores would be a choice the form pretended to mean something.
struct ProposalBody: Encodable, Equatable {
    var title: String
    var body: String
    var proposalType: String
    var durationHours: Int?
    var putToVote: Bool?
    private enum CodingKeys: String, CodingKey {
        case title, body, proposalType = "proposal_type", durationHours = "duration_hours", putToVote = "put_to_vote"
    }

    init(_ draft: ProposalDraft, rules: GovernanceRules?, isPatchAdmin: Bool) {
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        proposalType = draft.kind.rawValue
        let chooses = ProposalPosting.adminChooses(rules, isPatchAdmin: isPatchAdmin)
        let outcome = ProposalPosting.outcome(rules: rules, isPatchAdmin: isPatchAdmin, putToVote: chooses && draft.putToVote)
        durationHours = ProposalPosting.asksDuration(outcome) ? draft.durationHours : nil
        putToVote = chooses ? draft.putToVote : nil
    }
}

extension PatchworkAPI {
    /// The answer is the bare proposal (201), with no viewer fields: its id
    /// is what the screen it opens on reads the rest by.
    func propose(slug: String, body: ProposalBody) async throws -> Proposal {
        try await post("nodes/\(slug)/proposals", body: body)
    }

    func withdraw(proposal id: String) async throws { try await deleteVoid("proposals/\(id)") }
}
