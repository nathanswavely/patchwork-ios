// SPDX-License-Identifier: MPL-2.0

import Foundation

// Voting, election ballots and discussion on a proposal (web ADRs 041, 044,
// 047, 051, 092, 097, 098, 106, 107, 109).
//
// The rules the proposal screen follows are values here with no view in
// them, so every sentence the screen says and every gate it draws a control
// behind is checked in `GovernanceTests` without a window open. The server
// is the authority on who may vote (`can_vote`); what is decided here is how
// that answer is said, and what the screen offers around it.

// MARK: - The payload's parts

/// One name on an election's slate. `id` is the candidate row, and it is
/// what a ballot names — never `userId`.
struct Candidate: Decodable, Identifiable, Hashable {
    let id: String
    var userId: String? = nil
    var username: String? = nil
    var displayName: String? = nil
    var approvals: Int? = nil
    var approvedByMe: Bool? = nil
    var seated: Bool? = nil
    var statement: String? = nil
    var name: String {
        let display = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty { return display }
        let handle = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return handle.isEmpty ? "Someone" : handle
    }
}

/// One ballot on the record (`voters[]`). A ballot cast by somebody who has
/// since left is kept and marked `counted: false`; a hidden member is named
/// "Hidden member" to a reader outside the room.
struct Ballot: Decodable, Hashable {
    var userId: String? = nil
    var displayName: String? = nil
    var username: String? = nil
    var value: String? = nil
    /// Absent on a payload older than the field, whose rows all counted.
    var counted: Bool? = nil
    var name: String {
        let display = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty { return display }
        let handle = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return handle.isEmpty ? "Someone" : handle
    }
    var isCounted: Bool { counted != false }
}

/// An election's turnout. `needed` is a count of ballots, not a percentage,
/// and zero means the contest needs no quorum.
struct ElectionTurnout: Decodable, Hashable {
    var voted: Int = 0
    var eligible: Int = 0
    var needed: Int = 0
    var met: Bool = false
}

/// One emoji on one comment, and whether the reader is among its holders.
struct Reaction: Decodable, Hashable {
    let emoji: String
    var count: Int = 0
    var me: Bool = false
}

/// A comment and its replies. The server nests one level only — a reply to
/// a reply is accepted and then never listed — so only a top-level comment
/// is offered Reply.
struct ProposalComment: Decodable, Identifiable, Hashable {
    let id: String
    var body: String = ""
    var authorName: String? = nil
    var authorId: String? = nil
    var createdAt: String? = nil
    var updatedAt: String? = nil
    var parentId: String? = nil
    var replies: [ProposalComment]? = nil
    var reactions: [Reaction]? = nil
    var author: String {
        let name = (authorName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Anonymous" : name
    }
}

struct CommentPage: Decodable {
    var items: [ProposalComment]? = nil
}

// MARK: - What the screen says, and when

enum VoteRules {
    /// The three values a vote can hold, in the order the buttons stand.
    enum Value: String, CaseIterable, Identifiable {
        case approve, reject, abstain
        var id: String { rawValue }
        /// The button's word before a vote.
        var present: String {
            switch self {
            case .approve: return "Approve"
            case .reject: return "Reject"
            case .abstain: return "Abstain"
            }
        }
        /// The filled button's word: the vote that is in.
        var past: String {
            switch self {
            case .approve: return "Approved"
            case .reject: return "Rejected"
            case .abstain: return "Abstained"
            }
        }
        var identifier: String {
            switch self {
            case .approve: return "voteApprove"
            case .reject: return "voteReject"
            case .abstain: return "voteAbstain"
            }
        }
    }

    /// `state`, falling back to the schema's `status` the way the web's
    /// detail page does: open is voting, a legacy `passed` is in effect.
    static func effectiveState(_ proposal: Proposal) -> String {
        let state = (proposal.state ?? "").trimmingCharacters(in: .whitespaces)
        if !state.isEmpty { return state }
        switch proposal.status {
        case "open": return "voting"
        case "passed": return "in_effect"
        default: return proposal.status ?? ""
        }
    }

    static func isVoting(_ proposal: Proposal) -> Bool { effectiveState(proposal) == "voting" }

    // MARK: Time left

    enum TimeLeft: Equatable {
        case ended
        case left(Int, Unit)
        enum Unit: String { case day, hour, minute }
    }

    /// The web's `timeLeft`: days ceiling'd (the day the window closes on
    /// counts), hours floored, minutes ceiling'd with a floor of one. Nil
    /// where there is no clock at all.
    static func timeLeft(_ endsAt: String?, now: Date = Date()) -> TimeLeft? {
        guard let endsAt, !endsAt.isEmpty, let end = PatchworkEvent.parseDate(endsAt) else { return nil }
        let seconds = end.timeIntervalSince(now)
        if seconds <= 0 { return .ended }
        if seconds >= 86_400 { return .left(Int((seconds / 86_400).rounded(.up)), .day) }
        if seconds >= 3_600 { return .left(Int((seconds / 3_600).rounded(.down)), .hour) }
        return .left(max(1, Int((seconds / 60).rounded(.up))), .minute)
    }

    /// "3 days left" / "Voting ended" — the banner's sentence.
    static func timeLeftSentence(_ left: TimeLeft?) -> String? {
        switch left {
        case nil: return nil
        case .ended: return "Voting ended"
        case .left(let n, let unit): return "\(n) \(unit.rawValue)\(n == 1 ? "" : "s") left"
        }
    }

    /// "3d" / "ended" — the bottom bar's chip.
    static func timeLeftShort(_ left: TimeLeft?) -> String? {
        switch left {
        case nil: return nil
        case .ended: return "ended"
        case .left(let n, let unit): return "\(n)\(unit.rawValue.prefix(1))"
        }
    }

    /// "3d left" / "Voting ended" — a list row.
    static func timeLeftRow(_ left: TimeLeft?) -> String? {
        switch left {
        case nil: return nil
        case .ended: return "Voting ended"
        case .left: return timeLeftShort(left).map { "\($0) left" }
        }
    }

    // MARK: The banner

    /// The status banner's sentence (web `ProposalStatusBanner`), chosen off
    /// the state and, for an election, its phase. "Cast your vote below." is
    /// said only where there is a vote below.
    static func banner(_ proposal: Proposal, now: Date = Date()) -> String? {
        let state = effectiveState(proposal)
        let phase = proposal.electionPhase ?? ""
        if phase == "nominating" {
            if let day = ProfileDate.day(proposal.nominationsCloseAt) {
                return "Nominations are open until \(day). Voting starts then."
            }
            return "Nominations are open. Voting starts when they close."
        }
        let left = timeLeftSentence(timeLeft(proposal.votingEndsAt, now: now))
        let cast = castsBelow(proposal, now: now) ? " Cast your vote below." : ""
        switch state {
        case "voting":
            if proposal.advisory == true {
                return (left.map { "Advisory vote. \($0). " } ?? "Advisory vote. ") + "The maintainer decides." + cast
            }
            return (left.map { "Voting is open. \($0)." } ?? "Voting is open.") + cast
        case "awaiting_admin":
            return proposal.ballots > 0
                ? "The members have been asked and the vote has closed. The maintainer decides, with the tally below."
                : "Waiting on the maintainer. This patch’s admins decide its proposals, and may ask the members first."
        case "elsewhere":
            return "Open for discussion. This patch decides at meetings, not here, and what it decides gets recorded on the charter afterwards."
        case "approved":
            return "The community approved this change. An admin needs to make it official."
        case "in_effect", "passed":
            if proposal.isElection { return "This election has closed and the council below is seated." }
            if proposal.isDirectChange { return "This change is in effect." }
            if proposal.advisory == true { return "The maintainer approved this. It is in effect." }
            return "Approved. This change is now in effect."
        case "lapsed":
            return "Voting ended without reaching quorum. This proposal lapsed and was not decided."
        case "unsettled":
            return "This election settled nothing; nobody was seated, and the seats it was for are unchanged."
        case "rejected":
            if let declined = proposal.declinedBy?.trimmingCharacters(in: .whitespaces), !declined.isEmpty {
                return "Declined by \(declined)."
            }
            return "This proposal did not pass. \(proposal.approveCount ?? 0) approved, \(proposal.rejectCount ?? 0) rejected."
        case "withdrawn":
            return "Withdrawn by the author."
        default:
            return nil
        }
    }

    /// Whether the page holds a vote this reader can cast right now.
    static func castsBelow(_ proposal: Proposal, now: Date = Date()) -> Bool {
        if proposal.isElection { return ballotOpen(proposal, now: now) }
        return proposal.canVote == true && isVoting(proposal)
    }

    // MARK: The vote section

    /// Where a tally is worth drawing (web `showsTally`): any vote in
    /// progress, and any settled proposal that was actually voted on. A
    /// request the maintainer decided alone has no tally to show.
    static func showsTally(_ proposal: Proposal) -> Bool {
        let state = effectiveState(proposal)
        if state == "voting" { return true }
        if state == "awaiting_admin" { return proposal.ballots > 0 }
        if ["approved", "in_effect", "rejected", "lapsed", "passed"].contains(state) {
            return proposal.advisory != true || proposal.ballots > 0
        }
        return false
    }

    /// The vote section at all: not an election, not a direct change, and a
    /// tally worth showing.
    static func showsVoteSection(_ proposal: Proposal) -> Bool {
        !proposal.isElection && !proposal.isDirectChange && showsTally(proposal)
    }

    /// The three buttons: the server says the reader may vote, and there is
    /// a vote open to cast.
    static func showsButtons(_ proposal: Proposal) -> Bool {
        proposal.canVote == true && isVoting(proposal) && !proposal.isElection
    }

    static func soleVoter(_ proposal: Proposal) -> Bool {
        isVoting(proposal) && proposal.canVote == true && proposal.advisory != true && proposal.eligibleVoters == 1
    }

    /// The reader's current vote, where they have one.
    static func myVote(_ proposal: Proposal) -> Value? {
        Value(rawValue: (proposal.myVote ?? "").trimmingCharacters(in: .whitespaces))
    }

    /// The fraction of the bar each value fills. Abstentions are part of the
    /// total, so an abstain-heavy vote reads as a short bar, not a full one.
    static func fills(_ proposal: Proposal) -> (approve: Double, reject: Double) {
        let total = Double(proposal.ballots)
        guard total > 0 else { return (0, 0) }
        return (Double(proposal.approveCount ?? 0) / total, Double(proposal.rejectCount ?? 0) / total)
    }

    static func countsLine(_ proposal: Proposal) -> String {
        "\(proposal.approveCount ?? 0) approve · \(proposal.rejectCount ?? 0) reject · \(proposal.abstainCount ?? 0) abstain"
    }

    /// The bar's summary: `5✓ 1✗`, the abstentions spelled out only where
    /// there are some, and the short time.
    static func compactTally(_ proposal: Proposal, now: Date = Date()) -> String {
        var parts = ["\(proposal.approveCount ?? 0)✓ \(proposal.rejectCount ?? 0)✗"]
        if (proposal.abstainCount ?? 0) > 0 { parts.append("\(proposal.abstainCount ?? 0) abstain") }
        if let short = timeLeftShort(timeLeft(proposal.votingEndsAt, now: now)) { parts.append(short) }
        return parts.joined(separator: " · ")
    }

    /// `ceil(eligible × quorum ÷ 100)`, the ballots a quorum takes.
    static func quorumNeeded(eligible: Int, percent: Int) -> Int {
        Int((Double(eligible) * Double(percent) / 100).rounded(.up))
    }

    static func quorumLine(_ proposal: Proposal, now: Date = Date()) -> String {
        if proposal.advisory == true { return "No quorum. This vote advises; it does not decide." }
        let percent = proposal.votingTerms?.quorumPercent ?? 0
        guard percent > 0 else { return "No quorum required" }
        let total = proposal.ballots
        let eligible = proposal.eligibleVoters ?? 0
        let met = eligible > 0 && Double(total) / Double(eligible) * 100 >= Double(percent)
        if met { return "Quorum met (\(total) of \(eligible) voted, \(percent)% needed)" }
        let closed = !isVoting(proposal) || timeLeft(proposal.votingEndsAt, now: now) == .ended
        return "\(closed ? "Quorum not met" : "Quorum not yet met") (\(total) of \(quorumNeeded(eligible: eligible, percent: percent)) needed)"
    }

    /// The threshold that decides this proposal: the amendment threshold on
    /// an amendment, the decision method on everything else.
    static func thresholdLine(_ proposal: Proposal) -> String {
        if proposal.advisory == true { return "Advisory: the maintainer decides, with this tally in front of them" }
        let terms = proposal.votingTerms
        let amendment = (terms?.amendmentThreshold ?? "").trimmingCharacters(in: .whitespaces)
        let method = proposal.proposalType == "amendment" && !amendment.isEmpty
            ? amendment : ((terms?.decisionMethod ?? "").isEmpty ? "majority" : terms!.decisionMethod!)
        switch method {
        case "majority": return "Majority: more than half of votes must approve"
        case "supermajority": return "Supermajority: at least 2 out of 3 votes must approve"
        case "consensus": return "Consensus: one reject blocks it"
        case "admin": return "Advisory: the maintainer decides, with this tally in front of them"
        default: return method
        }
    }

    /// "Rules as of Sep 10", and the tenure sentence where the bar in force
    /// is holding this reader back (web ADR 047, 098). Nil with no terms.
    static func termsLine(_ proposal: Proposal, locale: Locale = .current, timeZone: TimeZone = .current) -> String? {
        guard proposal.votingTerms != nil else { return nil }
        var head = "Rules fixed when voting opened"
        if let opened = PatchworkEvent.parseDate(proposal.createdAt ?? "") {
            head = "Rules as of \(format(opened, template: "MMMd", locale: locale, timeZone: timeZone))"
        }
        if let day = calendarDay(proposal.voteEligibleAt, timeZone: timeZone) {
            return "\(head). You can vote here from \(format(day, template: "MMMMd", locale: locale, timeZone: timeZone))"
        }
        if let tenure = proposal.tenureDays, tenure > 0, proposal.canVote != true {
            return "\(head). Voting requires \(tenure) days’ membership"
        }
        return head
    }

    /// A bare `YYYY-MM-DD` is a calendar day, not an instant: read in the
    /// reader's own calendar, or it names the day before west of Greenwich.
    static func calendarDay(_ value: String?, timeZone: TimeZone = .current) -> Date? {
        guard let value, value.count == 10 else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func format(_ date: Date, template: String, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    // MARK: Who owes a ballot

    /// Nothing in the payload says "your vote is needed"; this is the
    /// contract's derivation of it.
    static func needsMyVote(_ proposal: Proposal) -> Bool {
        if proposal.isElection {
            return proposal.electionPhase == "voting" && proposal.canVote == true
                && !(proposal.candidates ?? []).contains { $0.approvedByMe == true }
                && proposal.iAbstained != true
        }
        return proposal.canVote == true && (proposal.myVote ?? "").isEmpty
    }

    /// An election's ballot is open to this reader: the voting phase, the
    /// server's yes, and a clock that has not run out. The server takes a
    /// ballot until the hourly sweep closes the contest, but a ballot cast
    /// after the window is one nobody should be offered.
    static func ballotOpen(_ proposal: Proposal, now: Date = Date()) -> Bool {
        guard proposal.electionPhase == "voting", proposal.canVote == true else { return false }
        return timeLeft(proposal.votingEndsAt, now: now) != .ended
    }

    // MARK: The election panel

    static func electionHeading(_ proposal: Proposal) -> String {
        switch proposal.electionPhase {
        case "nominating": return "Nominations"
        case "voting": return "The ballot"
        default: return "Result"
        }
    }

    static func seatsLabel(_ seats: Int) -> String { "\(seats) seat\(seats == 1 ? "" : "s")" }

    static func electionLede(_ proposal: Proposal) -> String? {
        let seats = proposal.seatsContested ?? 0
        switch proposal.electionPhase {
        case "nominating":
            if let day = ProfileDate.day(proposal.nominationsCloseAt) {
                return "Anyone who is a member can stand. Nominations close \(day), and voting opens then."
            }
            return "Anyone who is a member can stand."
        case "voting":
            return "Approve as many candidates as you like. "
                + (seats == 1 ? "The most approved candidate takes the seat." : "The \(seats) most approved take the seats.")
        default:
            return nil
        }
    }

    static func turnoutLine(_ proposal: Proposal) -> String? {
        guard let turnout = proposal.electionTurnout, proposal.electionPhase != "nominating" else { return nil }
        let tally = "\(turnout.voted) of \(turnout.eligible) voted"
        if turnout.needed == 0 { return "No quorum required. \(tally)." }
        if turnout.met { return "Quorum met: \(tally), \(turnout.needed) needed." }
        return "\(proposal.electionPhase == "closed" ? "Quorum not met" : "Quorum not yet met"): \(tally), \(turnout.needed) needed."
    }

    /// A contest resolved before `seated` was stored has it false for
    /// everybody; the web then seats the top `seats_contested` with any
    /// approvals, and so does this.
    static func isSeated(_ candidate: Candidate, at index: Int, in proposal: Proposal) -> Bool {
        guard proposal.electionPhase == "closed", effectiveState(proposal) != "unsettled" else { return false }
        let stored = (proposal.candidates ?? []).contains { $0.seated == true }
        return stored ? candidate.seated == true : index < (proposal.seatsContested ?? 0) && (candidate.approvals ?? 0) > 0
    }

    static let statementLimit = 500

    /// The server counts a statement in runes, so this does too.
    static func charactersLeft(_ statement: String) -> Int { statementLimit - statement.unicodeScalars.count }

    static func clipStatement(_ statement: String) -> String {
        guard statement.unicodeScalars.count > statementLimit else { return statement }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: statement.unicodeScalars.prefix(statementLimit))
        return String(scalars)
    }

    /// Who can be put forward: active members and admins, minus the reader
    /// and minus anybody already standing.
    static func nominatable(_ members: [PatchMember], me: String?, candidates: [Candidate]) -> [PatchMember] {
        let standing = Set(candidates.compactMap(\.userId))
        return members.filter { member in
            guard member.role == "member" || member.role == "admin", let id = member.userId, !id.isEmpty else { return false }
            return id != me && !standing.contains(id)
        }
    }
}

// MARK: - Discussion

enum Discussion {
    /// The six the server takes, byte for byte, in the order they are shown.
    /// The heart carries its variation selector: a bare U+2764 is refused.
    static let heart = "\u{2764}\u{FE0F}"
    static let emoji = ["\u{1F44D}", "\u{1F44E}", heart, "\u{1F914}", "\u{1F389}", "\u{1F440}"]

    /// What VoiceOver calls each one.
    static func name(_ emoji: String) -> String {
        switch normalized(emoji) {
        case "\u{1F44D}": return "Thumbs up"
        case "\u{1F44E}": return "Thumbs down"
        case heart: return "Heart"
        case "\u{1F914}": return "Thinking"
        case "\u{1F389}": return "Celebrate"
        case "\u{1F440}": return "Eyes"
        default: return emoji
        }
    }

    /// A bare heart is the same reaction to a reader and a different one to
    /// the server, so it is read, and sent, with its selector.
    static func normalized(_ emoji: String) -> String {
        emoji == "\u{2764}" ? heart : emoji
    }

    struct Chip: Equatable {
        let emoji: String
        let count: Int
        let me: Bool
    }

    /// The reaction bar in the fixed order, whatever order the server sent.
    /// A reader who may react sees all six; anybody else sees only the ones
    /// somebody has used, and cannot press them.
    static func chips(_ reactions: [Reaction]?, canReact: Bool) -> [Chip] {
        var byEmoji: [String: Reaction] = [:]
        for reaction in reactions ?? [] { byEmoji[normalized(reaction.emoji)] = reaction }
        return emoji.compactMap { emoji in
            let reaction = byEmoji[emoji]
            let count = reaction?.count ?? 0
            guard canReact || count > 0 else { return nil }
            return Chip(emoji: emoji, count: count, me: canReact && reaction?.me == true)
        }
    }

    /// Items plus their replies. The server sends no count, and the web's
    /// badge reads a field that does not exist.
    static func count(_ comments: [ProposalComment]) -> Int {
        comments.reduce(0) { $0 + 1 + ($1.replies?.count ?? 0) }
    }

    /// Who may comment and react (web ADR 050, ADR 117): an active admin,
    /// member or follower — a follower only where the patch lets followers
    /// take part — and the quilt's own admins.
    static func canDiscuss(standing: Standing?, followerPermissions: FollowerPermissions?, isInstanceAdmin: Bool) -> Bool {
        if isInstanceAdmin { return true }
        switch standing {
        case .active(.admin), .active(.member): return true
        case .active(.follower): return followerPermissions?.proposals != false
        default: return false
        }
    }

    /// The author, and only the author, edits — an admin cannot put words
    /// in somebody's mouth. The server sends no `is_mine`; the id is compared.
    static func canEdit(_ comment: ProposalComment, me: String?) -> Bool {
        guard let me, !me.isEmpty, let author = comment.authorId, !author.isEmpty else { return false }
        return author == me
    }

    /// The author, a patch admin, or a quilt admin.
    static func canDelete(_ comment: ProposalComment, me: String?, standing: Standing?, isInstanceAdmin: Bool) -> Bool {
        guard let me, !me.isEmpty else { return false }
        return canEdit(comment, me: me) || standing == .active(.admin) || isInstanceAdmin
    }

    /// The confirmation's second line. There is no tombstone: a comment
    /// deleted takes its replies with it.
    static func deleteMessage(_ comment: ProposalComment) -> String? {
        let replies = comment.replies?.count ?? 0
        if replies == 0 { return nil }
        return replies == 1 ? "Its 1 reply goes with it." : "Its \(replies) replies go with it."
    }
}

// MARK: - The calls

/// `PUT proposals/{id}/ballot`: the whole set, every time. An empty set with
/// `abstain` is taking part while approving nobody; an empty set without it
/// takes the ballot back.
struct BallotBody: Encodable, Equatable {
    var candidateIds: [String]
    var abstain: Bool
    private enum CodingKeys: String, CodingKey { case candidateIds = "candidate_ids", abstain }
    static func approving(_ ids: some Collection<String>) -> BallotBody { BallotBody(candidateIds: ids.sorted(), abstain: false) }
    static let abstaining = BallotBody(candidateIds: [], abstain: true)
}

/// `POST proposals/{id}/candidates`: nobody named stands the reader, with
/// their statement; a named member is put forward, and a statement for
/// somebody else would be dropped by the server, so none is sent.
struct CandidacyBody: Encodable, Equatable {
    var userId: String?
    var statement: String?
    private enum CodingKeys: String, CodingKey { case userId = "user_id", statement }
}

struct CommentBody: Encodable, Equatable {
    var body: String
    var parentId: String?
    private enum CodingKeys: String, CodingKey { case body, parentId = "parent_id" }
}

private struct VoteBody: Encodable { let value: String }
private struct EmojiBody: Encodable { let emoji: String }
private struct EditBody: Encodable { let body: String }

extension PatchworkAPI {
    /// `POST proposals/{id}/vote`. The answer is not read: the proposal is
    /// asked for again after every vote, because a sole voter's ballot
    /// settles it inside this very request.
    func vote(proposal id: String, value: VoteRules.Value) async throws {
        try await postVoid("proposals/\(id)/vote", body: VoteBody(value: value.rawValue))
    }

    func castBallot(proposal id: String, candidateIDs: some Collection<String>, abstain: Bool) async throws {
        let body = abstain ? BallotBody.abstaining : BallotBody.approving(candidateIDs)
        try await sendVoid("PUT", "proposals/\(id)/ballot", body: body)
    }

    func stand(proposal id: String, statement: String) async throws {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        try await postVoid("proposals/\(id)/candidates", body: CandidacyBody(userId: nil, statement: trimmed.isEmpty ? nil : trimmed))
    }

    func nominate(proposal id: String, userID: String) async throws {
        try await postVoid("proposals/\(id)/candidates", body: CandidacyBody(userId: userID, statement: nil))
    }

    func withdrawCandidacy(proposal id: String) async throws {
        try await deleteVoid("proposals/\(id)/candidates/me")
    }

    func comments(proposal id: String) async throws -> [ProposalComment] {
        let page: CommentPage = try await get("proposals/\(id)/comments")
        return page.items ?? []
    }

    /// The body is trimmed here, because the server does not trim it.
    @discardableResult
    func comment(proposal id: String, body: String, parentID: String? = nil) async throws -> ProposalComment {
        try await post("proposals/\(id)/comments", body: CommentBody(body: body.trimmingCharacters(in: .whitespacesAndNewlines), parentId: parentID))
    }

    @discardableResult
    func editComment(id: String, body: String) async throws -> ProposalComment {
        try await patch("comments/\(id)", body: EditBody(body: body.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func deleteComment(id: String) async throws { try await deleteVoid("comments/\(id)") }

    func react(comment id: String, emoji: String) async throws {
        try await postVoid("comments/\(id)/reactions", body: EmojiBody(emoji: Discussion.normalized(emoji)))
    }

    func unreact(comment id: String, emoji: String) async throws {
        try await deleteVoid(Self.reactionPath(comment: id, emoji: emoji))
    }

    /// The emoji rides the path, so it is percent-encoded there — the heart
    /// as `%E2%9D%A4%EF%B8%8F`, selector and all.
    static func reactionPath(comment id: String, emoji: String) -> String {
        let encoded = Discussion.normalized(emoji).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? emoji
        return "comments/\(id)/reactions/\(encoded)"
    }

    /// Every active member and admin of a patch, for the nominee picker. The
    /// roster is paged by `after` (the web's picker sends `cursor`, which the
    /// server ignores, and so never reaches member 101).
    func electionMembers(slug: String) async throws -> [PatchMember] {
        var found: [PatchMember] = []
        var cursor: String?
        for _ in 0..<20 {
            let page: MemberPage = try await get("nodes/\(slug)/members", query: Self.memberPageQuery(after: cursor))
            found += (page.items ?? []).filter { $0.role == "member" || $0.role == "admin" }
            cursor = page.nextCursor
            if (cursor ?? "").isEmpty { break }
        }
        return found
    }

    static func memberPageQuery(after cursor: String?) -> [URLQueryItem] {
        var query = [URLQueryItem(name: "limit", value: "100")]
        if let cursor, !cursor.isEmpty { query.append(URLQueryItem(name: "after", value: cursor)) }
        return query
    }
}
