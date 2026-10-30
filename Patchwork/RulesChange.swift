// SPDX-License-Identifier: MPL-2.0

import Foundation

// Changing a patch's governance rules (web `RulesProposalEditor.svelte`,
// `StructuredRulesEditor.svelte`, `StructuredRulesDiff.svelte`,
// `lib/governanceRules.js`; server `GetGovernanceRules`, `CreateProposal`,
// `GovernanceElectorate`; web ADRs 041, 047, 052, 053, 092, 098, 104).
//
// The rules file is whole-document, not a patch: a change is an amendment
// to `governance-rules.json` carrying the entire file, and whatever the
// submission leaves out the server's sync reads back as its default. So the
// rules are read whole from `nodes/{slug}/governance/rules` — every field,
// including the ones this form does not edit — and written back whole with
// the edited fields laid over them, exactly as the web spreads what it
// loaded. A field nobody here knows about survives the round trip, and the
// diff names every key that moved, not only the labelled ones, so nothing
// changes in silence.
//
// The voting knobs are hidden, not cleared, when the method is "Admin
// decides" (ADR 041): their stored values pass through untouched and come
// back if the patch adopts a voting method again.

// MARK: - Any JSON

/// A JSON value kept exactly as it came, so a document can be read,
/// partly edited and written back without losing what was not edited.
indirect enum JSONValue: Codable, Equatable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var string: String? { if case .string(let value) = self { return value }; return nil }
    var int: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(value)
        default: return nil
        }
    }
    var bool: Bool? { if case .bool(let value) = self { return value }; return nil }
    var object: [String: JSONValue]? { if case .object(let value) = self { return value }; return nil }
}

// MARK: - The document

/// The rules as the server holds them, keyed the way the file spells them.
struct RulesDocument: Equatable {
    var fields: [String: JSONValue]

    /// The app's decoder turns snake-case keys into camel case, dictionary
    /// keys included, so the keys are put back the way the file spells them
    /// before anything reads them — every rule key is lower snake case.
    init(decoded: [String: JSONValue]) { fields = Self.snaked(decoded) }
    init(fields: [String: JSONValue]) { self.fields = fields }

    /// The file as JSON text, read without any key strategy (an amendment's
    /// `current_doc_content` and `proposed_body`).
    init?(json: String) {
        guard let data = json.data(using: .utf8), let object = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return nil }
        fields = object
    }

    static func snake(_ key: String) -> String {
        var out = ""
        for character in key {
            if character.isUppercase { out += "_" + character.lowercased() } else { out.append(character) }
        }
        return out
    }

    static func snaked(_ object: [String: JSONValue]) -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for (key, value) in object {
            if case .object(let inner) = value { out[snake(key)] = .object(snaked(inner)) } else { out[snake(key)] = value }
        }
        return out
    }

    subscript(key: String) -> JSONValue? {
        get { fields[key] }
        set { fields[key] = newValue }
    }

    /// The file's text as it is sent: indented, its keys in order, so the
    /// governance repository's history reads as a diff of settings.
    func text() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(fields)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    /// Enough of the rules for the outcome switch: what decides, and where.
    var governanceRules: GovernanceRules {
        GovernanceRules(decisionMethod: fields["decision_method"]?.string,
                        defaultVoteDurationHours: fields["default_vote_duration_hours"]?.int,
                        proposalVenue: fields["proposal_venue"]?.string)
    }
}

// MARK: - The form

enum RulesChange {
    struct Option: Hashable {
        let value: String
        let label: String
        var hint = ""
    }

    // The web's options, in its words (`lib/governanceRules.js`).
    static let decisionOptions = [
        Option(value: "admin", label: "Admin decides"), Option(value: "majority", label: "Majority vote"),
        Option(value: "supermajority", label: "Supermajority (2/3)"), Option(value: "consensus", label: "Full consensus"),
    ]
    static let thresholdOptions = Array(decisionOptions.dropFirst())
    static let periodOptions: [(hours: Int, label: String)] = [
        (24, "24 hours"), (48, "48 hours"), (72, "72 hours (3 days)"), (168, "1 week"), (336, "2 weeks"),
    ]
    static let successionOptions = [
        Option(value: "longest_tenure", label: "Longest-tenured members step in",
               hint: "The longest-standing members who have taken part recently become interim admins. If nobody has, nobody steps in."),
        Option(value: "nomination", label: "Nomination",
               hint: "Admins name their successors. If none are left to, the longest-standing members who have taken part recently step in."),
        Option(value: "election", label: "Election",
               hint: "Members elect the next admins. Until then the longest-standing members who have taken part recently step in, and if nobody has the seats stay empty until the election."),
        Option(value: "instance_admin", label: "Instance admin intervenes", hint: "An instance admin is notified and decides who runs the patch."),
        Option(value: "freeze", label: "Patch freezes", hint: "Nobody is promoted; the patch keeps running with no admin."),
    ]
    static let tenureOptions: [(days: Int, label: String)] = [(0, "Immediate"), (7, "7 days"), (30, "30 days"), (90, "90 days")]
    static let membershipOptions = [
        Option(value: "open", label: "Open"), Option(value: "approval_required", label: "Approval required"),
        Option(value: "invite_only", label: "Invite only"),
    ]
    static let venueOptions = [Option(value: "patchwork", label: "In Patchwork"), Option(value: "elsewhere", label: "Somewhere else, recorded here")]
    static let decisionHints = [
        "admin": "An admin decides every proposal. An admin can still put one to an advisory vote first, and the result comes back to them.",
        "majority": "More approvals than rejections carries a proposal.",
        "supermajority": "Two thirds of the ballots cast must approve.",
        "consensus": "One reject defeats a proposal, however many approve it.",
    ]
    static let leadershipVenueHint = "Pick the second if your board is elected at a meeting, on paper, or in another tool. Patchwork will stop conducting leadership changes and let an admin record what was decided."
    static let proposalVenueHint = "Pick the second if your members decide at meetings. Proposals stay open for discussion and lose the vote buttons, and an admin records the adopted text on the charter afterwards. Rules changes stay a direct change an admin applies."
    static let recusalHint = "Someone nominated for admin sits their own vote out. They stay in the electorate for everything else."
    static let followerEventsHint = "Off: followers see this patch’s public events only."

    /// A stored succession policy this form has no option for is shown as
    /// itself and left alone, never swapped for the first option.
    static func successionChoices(_ current: String) -> [Option] {
        successionOptions.contains { $0.value == current } ? successionOptions : successionOptions + [Option(value: current, label: current)]
    }

    /// The patch's own period among the web's five where it is not one.
    static func periodChoices(_ current: Int) -> [(hours: Int, label: String)] {
        periodOptions.contains { $0.hours == current } ? periodOptions
            : (periodOptions + [(current, ProposalPosting.durationName(current))]).sorted { $0.hours < $1.hours }
    }

    static func tenureChoices(_ current: Int) -> [(days: Int, label: String)] {
        tenureOptions.contains { $0.days == current } ? tenureOptions
            : (tenureOptions + [(current, "\(current) days")]).sorted { $0.days < $1.days }
    }

    // MARK: The door

    enum Door: Equatable {
        case open(String)
        case note(String)
    }

    /// Who is offered a change and what it is called (web
    /// `GovernanceOverview`): a member or an admin; "Change these rules" for
    /// the admin of a patch whose admins decide, or of one that decides at
    /// meetings — where a member's rules proposal is refused, and told who
    /// changes them instead.
    static func door(signedIn: Bool, standing: Standing?, rules: GovernanceRules?) -> Door? {
        guard ProposalPosting.mayPropose(signedIn: signedIn, standing: standing), let rules else { return nil }
        let admin = standing == .active(.admin)
        if ProposalPosting.decidesElsewhere(rules) {
            return admin ? .open("Change these rules") : .note("An admin changes these rules directly.")
        }
        if ProposalPosting.adminDecides(rules) && admin { return .open("Change these rules") }
        return .open("Propose a change to these rules")
    }

    // MARK: The edited fields

    /// The fields the web's editor edits, read off the document the way it
    /// reads them.
    struct Draft: Equatable {
        var decisionMethod = "majority"
        var quorumPercent = 0
        var periodHours = 72
        var amendmentThreshold = "majority"
        var autoApply = true
        var successionPolicy = "longest_tenure"
        var tenureDays = 0
        var subjectRecusal = false
        var leadershipVenue = "patchwork"
        var proposalVenue = "patchwork"
        var membershipPolicy = "open"
        var followerEvents = true
        var followerProposals = true
        var followerCharters = false
        var followerMembers = true

        var adminDecides: Bool { decisionMethod == "admin" }

        init() {}

        init(_ document: RulesDocument) {
            // 'admin_decides' is a value an older editor could have written;
            // the backend's word is 'admin'.
            let method = document["decision_method"]?.string ?? ""
            decisionMethod = method == "admin_decides" ? "admin" : (method.isEmpty ? "majority" : method)
            quorumPercent = document["quorum_percent"]?.int ?? 0
            let hours = document["default_vote_duration_hours"]?.int ?? 0
            periodHours = hours > 0 ? hours : 72
            let threshold = document["amendment_threshold"]?.string ?? ""
            amendmentThreshold = threshold.isEmpty ? "majority" : threshold
            autoApply = document["amendment_auto_apply"]?.bool ?? true
            let succession = document["succession_policy"]?.string ?? ""
            successionPolicy = succession.isEmpty ? "longest_tenure" : succession
            tenureDays = document["min_voting_tenure_days"]?.int ?? 0
            subjectRecusal = document["subject_recusal"]?.bool == true
            leadershipVenue = document["leadership_venue"]?.string == "elsewhere" ? "elsewhere" : "patchwork"
            proposalVenue = document["proposal_venue"]?.string == "elsewhere" ? "elsewhere" : "patchwork"
            let policy = document["membership_policy"]?.string ?? ""
            membershipPolicy = policy.isEmpty ? "open" : policy
            let fp = document["follower_permissions"]?.object ?? [:]
            followerEvents = fp["events"]?.bool != false
            followerProposals = fp["proposals"]?.bool != false
            // Charters alone is off unless a patch turned it on (web ADR 116).
            followerCharters = fp["charters"]?.bool == true
            followerMembers = fp["members"]?.bool != false
        }

        /// The document with this draft laid over it — every field it does
        /// not edit carried through, and the voting knobs left as stored
        /// while the admins decide.
        func applied(to current: RulesDocument) -> RulesDocument {
            var out = current
            out["decision_method"] = .string(decisionMethod)
            out["leadership_venue"] = .string(leadershipVenue)
            out["proposal_venue"] = .string(proposalVenue)
            out["succession_policy"] = .string(successionPolicy)
            out["membership_policy"] = .string(membershipPolicy)
            out["follower_permissions"] = .object([
                "events": .bool(followerEvents), "proposals": .bool(followerProposals),
                "charters": .bool(followerCharters), "members": .bool(followerMembers),
            ])
            if !adminDecides {
                out["quorum_percent"] = .int(quorumPercent)
                out["default_vote_duration_hours"] = .int(periodHours)
                out["amendment_threshold"] = .string(amendmentThreshold)
                out["amendment_auto_apply"] = .bool(autoApply)
                out["min_voting_tenure_days"] = .int(tenureDays)
                out["subject_recusal"] = .bool(subjectRecusal)
            }
            return out
        }
    }

    // MARK: Current → proposed

    struct DiffRow: Equatable, Identifiable {
        let key: String
        let label: String
        let from: String
        let to: String
        var id: String { key }
    }

    static let labels = [
        "decision_method": "Decision Method", "quorum_percent": "Quorum", "default_vote_duration_hours": "Default Voting Period",
        "amendment_threshold": "Amendment Threshold", "amendment_auto_apply": "Auto-Apply Amendments",
        "succession_policy": "Succession Policy", "min_voting_tenure_days": "Min Voting Tenure",
        "subject_recusal": "Recuse a proposal’s subject", "leadership_venue": "Where admins are chosen",
        "proposal_venue": "Where proposals are decided", "leadership_model": "Leadership",
        "membership_policy": "Membership Policy", "follower_permissions": "Follower Permissions",
    ]
    private static let labelOrder = ["decision_method", "quorum_percent", "default_vote_duration_hours", "amendment_threshold",
                                     "amendment_auto_apply", "succession_policy", "min_voting_tenure_days", "subject_recusal",
                                     "leadership_venue", "proposal_venue", "leadership_model", "membership_policy", "follower_permissions"]
    private static let valueLabels = [
        "admin": "Admin decides", "majority": "Majority vote", "supermajority": "Supermajority (2/3)", "consensus": "Full consensus",
        "patchwork": "In Patchwork", "elsewhere": "Somewhere else, recorded here", "longest_tenure": "Longest-tenured member",
        "instance_admin": "Instance admin intervenes", "freeze": "Patch freezes", "open": "Open",
        "approval_required": "Approval required", "invite_only": "Invite only",
    ]
    private static let durationLabels = [24: "24 hours", 48: "48 hours", 72: "3 days", 168: "1 week", 336: "2 weeks"]

    static func label(_ key: String) -> String {
        if let known = labels[key] { return known }
        let words = key.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// A value as the web's diff says it.
    static func format(_ key: String, _ value: JSONValue?) -> String {
        guard let value, value != .null else { return "—" }
        switch key {
        case "quorum_percent": return "\(value.int ?? 0)%"
        case "default_vote_duration_hours":
            let hours = value.int ?? 0
            return durationLabels[hours] ?? "\(hours)h"
        case "amendment_auto_apply": return value.bool == true ? "Yes" : "No"
        case "min_voting_tenure_days":
            let days = value.int ?? 0
            return days == 0 ? "Immediate" : "\(days) days"
        case "follower_permissions":
            guard let fp = value.object else { break }
            var granted: [String] = []
            if fp["events"]?.bool != false { granted.append("Events") }
            if fp["proposals"]?.bool != false { granted.append("Proposals") }
            if fp["charters"]?.bool == true { granted.append("Charters") }
            if fp["members"]?.bool != false { granted.append("Members") }
            return granted.isEmpty ? "None" : granted.joined(separator: ", ")
        default: break
        }
        switch value {
        case .string(let text): return valueLabels[text] ?? text
        case .int(let n): return String(n)
        case .double(let n): return String(n)
        case .bool(let flag): return flag ? "true" : "false"
        default:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "—"
        }
    }

    /// Every key either side carries that moved, the labelled ones first in
    /// the web's order, and how many did not.
    static func diff(current: RulesDocument, proposed: RulesDocument) -> (rows: [DiffRow], unchanged: Int) {
        let keys = Set(labelOrder).union(current.fields.keys).union(proposed.fields.keys)
        let ordered = labelOrder + keys.subtracting(labelOrder).sorted()
        let changed = ordered.filter { current[$0] != proposed[$0] }
        let rows = changed.map { DiffRow(key: $0, label: label($0), from: format($0, current[$0]), to: format($0, proposed[$0])) }
        return (rows, keys.count - changed.count)
    }

    static func unchangedLine(_ count: Int) -> String { "(\(count) field\(count == 1 ? "" : "s") unchanged)" }

    // MARK: The title

    private static let titleValues = [
        "admin": "admin decides", "majority": "majority vote", "supermajority": "supermajority vote",
        "consensus": "consensus", "approval_required": "approval-required", "invite_only": "invite-only",
    ]
    private static func titleValue(_ value: String) -> String { titleValues[value] ?? value.replacingOccurrences(of: "_", with: " ") }

    /// The web's summary, made from what moved.
    static func title(current: RulesDocument, proposed: RulesDocument) -> String {
        var changes: [String] = []
        if current["decision_method"] != proposed["decision_method"], let value = proposed["decision_method"]?.string {
            changes.append("decisions by \(titleValue(value))")
        }
        if current["quorum_percent"] != proposed["quorum_percent"], let value = proposed["quorum_percent"]?.int {
            changes.append("set quorum to \(value)%")
        }
        if current["default_vote_duration_hours"] != proposed["default_vote_duration_hours"], let value = proposed["default_vote_duration_hours"]?.int {
            changes.append("\(Int((Double(value) / 24).rounded()))-day voting period")
        }
        if current["membership_policy"] != proposed["membership_policy"], let value = proposed["membership_policy"]?.string {
            changes.append("\(titleValue(value)) membership")
        }
        if current["leadership_model"] != proposed["leadership_model"], let value = proposed["leadership_model"]?.string {
            changes.append("\(titleValue(value)) leadership")
        }
        guard !changes.isEmpty else { return "Update governance rules" }
        let joined = changes.joined(separator: ", ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    // MARK: What it comes to (web ADR 104)

    struct Electorate: Decodable, Equatable {
        var members: Int = 0
        var tenureDays: [Int] = []
        var patchAgeDays: Int = 0
    }

    /// The server's arithmetic, mirrored: a patch younger than its own bar
    /// has no bar (web ADR 098), and a quorum is `ceil(count × percent)`.
    static func canVoteToday(_ electorate: Electorate, tenureDays: Int) -> Int {
        let inForce = tenureDays > 0 && electorate.patchAgeDays >= tenureDays
        return inForce ? electorate.tenureDays.filter { $0 >= tenureDays }.count : electorate.members
    }

    static func quorumHint(_ electorate: Electorate?, quorum: Int, tenureDays: Int) -> String? {
        guard let electorate else { return nil }
        if quorum <= 0 { return "No quorum: however few people vote, the result stands." }
        let voters = canVoteToday(electorate, tenureDays: tenureDays)
        if voters == 0 { return "Nobody can vote here today, so no quorum can be met and a proposal would close with nothing decided." }
        if voters == 1 { return "One person can vote here today, so that single ballot is the whole quorum. An abstention counts toward it." }
        let needed = min(voters, VoteRules.quorumNeeded(eligible: voters, percent: quorum))
        return "\(needed) of the \(voters) people who can vote today must cast a ballot, or a proposal closes with nothing decided. An abstention counts toward it."
    }

    static func tenureHint(_ electorate: Electorate?, tenureDays: Int) -> String? {
        if tenureDays <= 0 { return "Everybody votes from the day they join." }
        guard let electorate else { return nil }
        if electorate.patchAgeDays < tenureDays {
            let age = electorate.patchAgeDays == 0 ? "was made today"
                : electorate.patchAgeDays == 1 ? "is a day old" : "is \(electorate.patchAgeDays) days old"
            return "Not in force yet: this patch \(age), younger than the wait it asks for, so every member can vote until it is \(tenureDays) days old."
        }
        let voters = canVoteToday(electorate, tenureDays: tenureDays)
        let held = electorate.members - voters
        if held == 0 { return "All \(electorate.members) of your members have been here \(tenureDays) days, so all of them can vote." }
        return "\(voters) of your \(electorate.members) members have been here \(tenureDays) days. The other \(held) cannot vote yet, and \(held == 1 ? "is" : "are") not counted toward a quorum."
    }

    // MARK: Before it is pressed

    /// What pressing the button will do, in a sentence (the web's
    /// `submitConsequence`, extended to the outcomes it does not name).
    static func consequence(_ outcome: ProposalPosting.Outcome, hours: Int) -> String {
        switch outcome {
        case .applied: return "Saving changes these rules now. Nobody votes on it."
        case .vote:
            return "This goes to the members as a proposal and opens a vote for \(ProposalPosting.durationName(hours)). These rules do not change unless it carries."
        case .advisoryVote:
            return "This asks the members in an advisory vote for \(ProposalPosting.durationName(hours)). These rules do not change until you decide."
        case .toMaintainer, .discussion:
            return ProposalPosting.outcomeNote(outcome) ?? ""
        }
    }
}

extension PatchworkAPI {
    func governanceRules(slug: String) async throws -> RulesDocument {
        let decoded: [String: JSONValue] = try await get("nodes/\(slug)/governance/rules")
        return RulesDocument(decoded: decoded)
    }

    func electorate(slug: String) async throws -> RulesChange.Electorate {
        try await get("nodes/\(slug)/governance/electorate")
    }
}
