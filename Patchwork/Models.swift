// SPDX-License-Identifier: MPL-2.0

import Foundation

struct Quilt: Codable, Identifiable, Hashable {
    var url: URL
    var name: String
    var id: String { url.absoluteString }
    static var directory: [Quilt] {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") {
            return [Quilt(url: URL(string: "https://quilt.example.org")!, name: "Sample quilt")]
        }
        #endif
        return [Quilt(url: URL(string: "https://lancasterpatchwork.org")!, name: "Lancaster Patchwork")]
    }
}

struct Instance: Decodable {
    let name: String
    let description: String
    let geography: Geography
    let neighborQuilts: [Neighbor]?
    let modules: [String: Bool]?
    let stats: Stats?
    let version: String?
    /// Whether this quilt takes patch suggestions at all. It gates the one
    /// exit this browsing client offers to the website's submission form; it
    /// never stands in for a native form, which needs sign-in.
    let submissionsEnabled: Bool?
    struct Geography: Decodable { let timezone: String? }
    struct Neighbor: Decodable { let name: String; let url: String }
    struct Stats: Decodable { let nodeCount: Int?; let eventCount: Int?; let memberCount: Int? }
}

/// The Label (docs/adr/023): the quilt's public statement of how it is run
/// and paid for, readable signed out because its most important reader has no
/// account yet. Every field is optional — an unpublished Label answers with
/// `published: false` and little else.
struct QuiltLabel: Decodable {
    let published: Bool?
    let stewards: [Steward]?
    let prose: String?
    let costItems: [CostItem]?
    let currency: String?
    let totalMonthlyMinor: Int?
    /// The figures have not been reviewed since `statedOn`.
    let stale: Bool?
    let statedOn: String?
    let version: String?
    let federation: Bool?
    let multiQuilt: Bool?
    let supportUrl: String?
    let feedbackUrl: String?
    let seamrippedFromName: String?
    let seamrippedFromUrl: String?
    struct Steward: Decodable, Hashable, Identifiable {
        let username: String
        let displayName: String?
        let avatarUrl: String?
        let blurb: String?
        var id: String { username }
        var title: String { (displayName?.isEmpty == false ? displayName : nil) ?? "@" + username }
    }
    struct CostItem: Decodable, Hashable {
        let service: String?
        let purpose: String?
        let why: String?
        let amountMinor: Int?
        let period: String?
        var periodWord: String { period == "yearly" ? "/year" : "/month" }
    }
    /// Minor units in the quilt's own currency, the way the web formats it.
    static func money(_ minor: Int?, _ currency: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = (currency?.isEmpty == false ? currency : nil) ?? "USD"
        let amount = NSNumber(value: Double(minor ?? 0) / 100)
        return formatter.string(from: amount) ?? String(format: "%.2f %@", amount.doubleValue, currency ?? "")
    }
}

/// The lining: the shared baseline community-standards charter every active
/// patch on this quilt starts from (docs/adr/037). This is the shipped
/// baseline only, never one patch's amended copy.
struct Lining: Decodable {
    let title: String?
    let body: String?
}

/// A legal document — the privacy policy or the user agreement (docs/adr/028).
/// The server always has something to serve, so there is no empty state.
struct LegalDocument: Decodable {
    let title: String?
    let markdown: String?
    /// True when the stewards replaced the shipped default, which is the only
    /// case where "last updated" says anything.
    let customized: Bool?
    let updatedAt: String?
    var updatedDay: String? {
        guard customized == true, let updatedAt, updatedAt.count >= 10 else { return nil }
        return String(updatedAt.prefix(10))
    }
}

struct Patch: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String
    let description: String?
    let tags: [String]?
    let memberCount: Int?
    let followerCount: Int?
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let eventCount: Int?
    let upcomingEventCount: Int?
    let isUnclaimed: Bool?
    let status: String?
    let imageUrl: String?
    let imageAlt: String?
    let website: String?
    let links: [PatchLink]?
    let activatedAt: String?
    let createdAt: String?
    let appearance: Appearance?
    /// The atproto DID a claim proved, the forwarding address of a patch that
    /// left, whether the patch is publicly readable at all, and the two
    /// disclosure settings a signed-out reader is governed by.
    let did: String?
    let movedTo: String?
    let visibility: String?
    let publicMemberList: String?
    let publicGovernanceRecord: String?
    var communityListing: Bool { isUnclaimed == true || status == "unclaimed" }
}

/// What a patch chose for its tile — palette, block, rotation, bundle, motif —
/// as one concept (docs/adr/004). Every key is optional and every value is
/// opaque until a registry recognises it; an unknown key falls back to the
/// hash-assigned tile rather than erroring, so a foreign quilt's custom
/// palette degrades instead of breaking the quilt.
struct Appearance: Decodable, Hashable {
    let palette: String?
    let block: Block?
    let rotation: Int?
    let bundle: [String]?
    let icon: String?
    /// A curated slug, or a drafted block embedded inline (docs/adr/029).
    enum Block: Hashable {
        case curated(String)
        case drafted(DraftedBlock)
    }
    private enum CodingKeys: String, CodingKey { case palette, block, rotation, bundle, icon }
    init(palette: String? = nil, block: Block? = nil, rotation: Int? = nil, bundle: [String]? = nil, icon: String? = nil) {
        self.palette = palette; self.block = block; self.rotation = rotation; self.bundle = bundle; self.icon = icon
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        palette = try container.decodeIfPresent(String.self, forKey: .palette)
        rotation = try container.decodeIfPresent(Int.self, forKey: .rotation)
        bundle = try container.decodeIfPresent([String].self, forKey: .bundle)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        if let slug = try? container.decodeIfPresent(String.self, forKey: .block) { block = .curated(slug) }
        else if let draft = try? container.decodeIfPresent(DraftedBlock.self, forKey: .block) { block = .drafted(draft) }
        else { block = nil }
    }
}

/// A drafted block: a square grid, seams between wall anchors, and the bundle
/// slot each piece is cut from, all in quarter-cell units (docs/adr/029).
struct DraftedBlock: Decodable, Hashable {
    let grid: Int
    let seams: [[Int]]?
    let colors: [String: [Int]]?
    init(grid: Int, seams: [[Int]]? = nil, colors: [String: [Int]]? = nil) { self.grid = grid; self.seams = seams; self.colors = colors }
}

/// One term of the quilt's tag vocabulary. A tag may carry a motif, which is
/// how a patch that chose none still wears a mark that says what it is.
struct TagTerm: Decodable, Hashable {
    let name: String
    let motif: String?
    let nodeCount: Int?
}

struct PatchLink: Decodable, Hashable {
    let url: String
    let label: String
}

struct Affinity: Decodable, Hashable {
    let source: String
    let target: String
    let strength: Double
}

/// The patch payload's envelope. `is_unclaimed` and `lining_status` ride here
/// rather than on the node, so a reader that only unpacks `node` loses the two
/// facts the head has to wear (web ADR 037, ADR 042).
struct PatchResponse: Decodable {
    let node: Patch
    let isUnclaimed: Bool?
    let liningStatus: String?
}

struct TreeResponse: Decodable {
    let tree: Root
    let affinity: [Affinity]?
    struct Root: Decodable { let children: [Patch]? }
}

struct PatchworkEvent: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let location: String?
    let startsAt: String
    let endsAt: String?
    let timezone: String?
    let nodeName: String?
    let nodeSlug: String?
    let eventUrl: String?
    /// Everything below is additive and optional: the list endpoint sends
    /// some of it, the detail endpoint the rest, and a quilt running an older
    /// build sends none of it. Absent is never an error.
    let nodeId: String?
    let nodeStatus: String?
    let visibility: String?
    let recurrence: String?
    let imageUrl: String?
    let imageAlt: String?
    let latitude: Double?
    let longitude: Double?
    let status: String?
    let sourceId: String?
    let links: [EventLink]?
    let mentions: [EventMention]?

    var date: Date? { Self.parseDate(startsAt) }
    var endDate: Date? { endsAt.flatMap(Self.parseDate) }
    static func parseDate(_ value: String) -> Date? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: value) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: value)
    }
    /// An event's time belongs to the place it happens, not to its reader:
    /// every formatter here reads the instant in the event's own zone.
    var zone: TimeZone { TimeZone(identifier: timezone ?? "") ?? .current }
    var dateLabel: String { label(dateStyle: .full) }
    var shortDateLabel: String { label(dateStyle: .medium) }
    func label(dateStyle: DateFormatter.Style) -> String {
        guard let date else { return "Time to be confirmed" }
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    /// Whether the two ends land on one calendar day *in the event's zone* —
    /// the day the organizer meant, not the reader's and not UTC's.
    var endsOnTheSameDay: Bool {
        guard let date, let endDate else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.isDate(date, inSameDayAs: endDate)
    }
    /// "Sunday, 20 September 2026 at 2:00 PM – 5:00 PM" on one day; the whole
    /// of the other end when the event runs past midnight.
    func rangeLabel(dateStyle: DateFormatter.Style = .full) -> String {
        let start = label(dateStyle: dateStyle)
        guard let endDate else { return start }
        return endsOnTheSameDay
            ? "\(start) – \(timeLabel(endDate))"
            : "\(start) – \(PatchworkEvent.labelFor(endDate, zone: zone, dateStyle: dateStyle))"
    }
    private static func labelFor(_ date: Date, zone: TimeZone, dateStyle: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    /// What the event says about who it is for. Public wears nothing: a chip
    /// on every row would say nothing at all.
    var tierLabel: String? {
        switch visibility {
        case "followers": return "Followers"
        case "members": return "Members only"
        default: return nil
        }
    }
    /// Events on unclaimed patches wear the community-submitted label away
    /// from their patch.
    var communitySubmitted: Bool { nodeStatus == "unclaimed" }
    var awaitingReview: Bool { status == "pending_review" }
    /// The word an organizer stored, told the truth: nothing expands a
    /// recurrence, so this page is one date of whatever they meant.
    var recurrenceNote: String? {
        let labels = [
            "daily": "The organizer says this repeats daily",
            "weekly": "The organizer says this repeats weekly",
            "biweekly": "The organizer says this repeats every two weeks",
            "monthly": "The organizer says this repeats monthly",
        ]
        guard let recurrence, let label = labels[recurrence] else { return nil }
        return label + " — only this date is on the calendar"
    }
    /// "with X": only a settled handshake is anybody else's business.
    var confirmedLinks: [EventLink] { (links ?? []).filter { $0.status == "confirmed" } }
    var flyerURL: URL? {
        guard let imageUrl, !imageUrl.isEmpty else { return nil }
        guard let url = URL(string: imageUrl), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }
    /// The event's own page out on the web, only where the scheme is one a
    /// browser can follow — an imported event gets this straight from a feed.
    var externalURL: URL? {
        guard let eventUrl, !eventUrl.isEmpty else { return nil }
        guard let url = URL(string: eventUrl), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }
}

/// A patch's presence on another patch's event, once both sides agreed.
struct EventLink: Decodable, Identifiable, Hashable {
    let id: String
    let nodeId: String?
    let nodeName: String?
    let nodeSlug: String?
    let nodeStatus: String?
    let status: String?
}

/// A display-only doorway to a patch on another quilt.
struct EventMention: Decodable, Identifiable, Hashable {
    let id: String
    let host: String
    let slug: String
    let name: String?
    var title: String { name?.isEmpty == false ? name! : slug }
    var url: URL? { URL(string: "https://\(host)/patches/\(slug)") }
}

struct EventPage: Decodable {
    let items: [PatchworkEvent]?
    let nextCursor: String?
}

enum QuiltAddress {
    static func parse(_ input: String) throws -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw APIError.address }
        let value = text.contains("://") ? text : "https://" + text
        guard var parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, !host.contains(" "),
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { throw APIError.address }
        parts.scheme = "https"
        parts.host = host.lowercased()
        parts.path = ""
        guard let url = parts.url else { throw APIError.address }
        return url
    }
}

// MARK: - Profile depth
//
// Everything below is the public (signed-out) half of a patch's face beyond
// its head: who is in it, how it decides, what it has decided, and the same
// face read from another quilt. Appended as one block so the shared file
// grows rather than moves.

/// How much of its roster a patch publishes (web ADR 095). The counts stay
/// public at every rung — the quilt sizes the patch's tile by them — so a
/// withheld list is never reported as an empty one.
enum RosterDisclosure: String, Hashable {
    case everyone, admins, nobody
    init(_ raw: String?) { self = RosterDisclosure(rawValue: raw ?? "") ?? .everyone }
}

struct PatchMember: Decodable, Identifiable, Hashable {
    let id: String
    let userId: String?
    let username: String?
    let displayName: String?
    let avatarUrl: String?
    let role: String?
    /// The name as the API gives it: whichever of the two the person filled in.
    var name: String {
        let display = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty { return display }
        let handle = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return handle.isEmpty ? "Someone" : handle
    }
    var initial: String { String(name.first ?? "?").uppercased() }
    var avatar: URL? { (avatarUrl?.isEmpty == false) ? URL(string: avatarUrl!) : nil }
}

struct MemberPage: Decodable {
    let items: [PatchMember]?
    let nextCursor: String?
    let memberCount: Int?
    let followerCount: Int?
    let publicMemberList: String?
}

/// The roster as a reader outside the patch is shown it. A signed-out reader
/// is always an outsider, so the patch's setting decides on its own.
struct MemberRoster: Equatable {
    var disclosure: RosterDisclosure = .everyone
    /// Admins and members, never followers: the two are counted apart and
    /// never summed (web CONTEXT.md "Member count").
    var members: [PatchMember] = []
    var memberCount = 0
    var followerCount = 0
    var cursor: String?
    var withheld: Bool { disclosure == .nobody }
    var adminsOnly: Bool { disclosure == .admins }
    var title: String { adminsOnly ? "Admins" : "Members" }
    /// Two kinds of empty, two sentences. A withheld list must never read as
    /// a patch with nobody in it.
    var emptyTitle: String { withheld ? "Member list not published" : "No members yet" }
    var emptyMessage: String {
        withheld
            ? "This patch doesn’t publish its member list."
            : "Nobody has joined this patch yet."
    }
    var countLine: String {
        var parts = [memberCount == 1 ? "1 member" : "\(memberCount) members"]
        if followerCount > 0 { parts.append(followerCount == 1 ? "1 following" : "\(followerCount) following") }
        return parts.joined(separator: " · ")
    }
    init() {}
    init(page: MemberPage) {
        disclosure = RosterDisclosure(page.publicMemberList)
        members = (page.items ?? []).filter { $0.role != "follower" }
        memberCount = page.memberCount ?? members.count
        followerCount = page.followerCount ?? 0
        cursor = page.nextCursor
    }
    mutating func append(_ page: MemberPage) {
        let known = Set(members.map(\.id))
        members += (page.items ?? []).filter { $0.role != "follower" && !known.contains($0.id) }
        memberCount = page.memberCount ?? memberCount
        followerCount = page.followerCount ?? followerCount
        cursor = page.nextCursor
    }
}

struct GovernanceDocument: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let body: String?
    /// "charter" or "lining" — the shared baseline every patch starts with.
    let kind: String?
    let visibility: String?
    let version: Int?
    let createdAt: String?
    let updatedAt: String?
}

struct GovernanceDocumentPage: Decodable {
    let items: [GovernanceDocument]?
    /// Whether this listing held only what the patch published, so an empty
    /// one can say which kind of empty it is without counting what it was
    /// not shown (web ADR 036).
    let publishedOnly: Bool?
}

struct GovernanceRules: Decodable, Hashable {
    let decisionMethod: String?
    let quorumPercent: Int?
    let defaultVoteDurationHours: Int?
    let leadershipModel: String?
    let leadershipVenue: String?
    let proposalVenue: String?
    let inactivityDays: Int?
    let adminTermMonths: Int?
    let maxAdmins: Int?
}

struct GovernanceAdmin: Decodable, Identifiable, Hashable {
    let userId: String
    let username: String?
    let displayName: String?
    let avatarUrl: String?
    let joinedAt: String?
    var id: String { userId }
    var name: String {
        let display = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty { return display }
        let handle = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return handle.isEmpty ? "Someone" : handle
    }
    var initial: String { String(name.first ?? "?").uppercased() }
    var avatar: URL? { (avatarUrl?.isEmpty == false) ? URL(string: avatarUrl!) : nil }
}

/// One chair on a council (web ADR 100). A chair whose holder this reader is
/// not shown is *held*, not vacant: three states, never two.
struct GovernanceSeat: Decodable, Identifiable, Hashable {
    let id: String
    let username: String?
    let displayName: String?
    let termEndsAt: String?
    let vacant: Bool?
    let fill: String?
    let contestOpens: String?
    let contestDue: Bool?
    let contestId: String?
    let holderWithheld: Bool?
    var isVacant: Bool { vacant == true }
    var holder: String {
        if isVacant { return "Vacant" }
        if holderWithheld == true { return "Held" }
        let display = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty { return display }
        let handle = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return handle.isEmpty ? "Held" : handle
    }
    /// One sentence about this chair, in the words the web uses for it.
    var fate: String {
        switch fill {
        case "contest_open":
            return isVacant
                ? "In the contest running now."
                : "Held until \(ProfileDate.day(termEndsAt) ?? "the term ends"), and in the contest running now."
        case "nomination":
            return "Filled by nomination: an admin puts a member forward and the members ratify it."
        case "contest_scheduled":
            let opens = ProfileDate.day(contestOpens)
            if contestDue == true { return "Its contest is due to open." }
            return opens.map { "Contested from \($0)." } ?? "Contested when the calendar opens."
        default:
            if let ends = ProfileDate.day(termEndsAt) { return "Held until \(ends)." }
            return isVacant ? "Vacant, with no contest scheduled." : "Held, with no term end set."
        }
    }
}

struct GovernanceElection: Decodable, Hashable {
    let id: String
    let phase: String?
    let seats: Int?
    let nominationsCloseAt: String?
    let votingEndsAt: String?
    let candidates: Int?
}

struct GovernanceOverview: Decodable {
    let rules: GovernanceRules?
    let admins: [GovernanceAdmin]?
    /// Which kind of empty `admins` is. Read before its length, or a patch
    /// that withholds its roster is reported as leaderless (web ADR 095).
    let adminsWithheld: Bool?
    let proposalsWithheld: Bool?
    let election: GovernanceElection?
    let seats: [GovernanceSeat]?
    let nextTermEnd: String?
    let nextContestOpens: String?
    let membershipPolicy: String?
    let memberCount: Int?
    let documentCount: Int?
    let openProposals: Int?
    let passedProposals: Int?
    let rejectedProposals: Int?
    var leadershipLabel: String {
        switch rules?.leadershipModel {
        case "maintainer": return "Maintainer"
        case "meritocratic": return "Meritocratic"
        case "elected": return "Elected council"
        case let other?: return other.capitalized
        default: return "Not set"
        }
    }
    /// The council block renders only where this patch actually runs one.
    var showsCouncil: Bool { rules?.leadershipModel == "elected" && rules?.leadershipVenue != "elsewhere" }
    /// How decisions are made, in sentences. A patch that decides elsewhere
    /// gets the venue line instead: narrating a quorum it does not run would
    /// state what nothing enforces (web ADR 049).
    var decisionNarrative: String {
        guard let rules else { return "" }
        if rules.proposalVenue == "elsewhere" {
            return "Proposals are decided outside Patchwork. They stay open here for discussion, and adoption is recorded on the charter."
        }
        var text: String
        switch rules.decisionMethod {
        case "admin": text = "The maintainer makes all decisions for this patch, and may ask the members before deciding."
        case "majority": text = "This patch decides things by majority vote. More than half must agree."
        case "supermajority": text = "Decisions require a supermajority: at least 2 out of 3 voters must agree."
        case "consensus": text = "Decisions are by consensus: one reject blocks a proposal, and a proposal nobody rejects carries."
        case let other?: text = "Decisions use \(other) voting."
        default: return ""
        }
        if let quorum = rules.quorumPercent, quorum > 0 {
            text += " At least \(quorum)% of members must participate for a vote to count."
        } else if rules.decisionMethod != "admin" {
            text += " Any number of votes counts. No minimum participation required."
        }
        if rules.decisionMethod != "admin", let hours = rules.defaultVoteDurationHours, hours > 0 {
            let days = Int((Double(hours) / 24).rounded())
            text += days <= 1 ? " Proposals stay open for \(hours) hours." : " Proposals stay open for \(days) days."
        }
        return text
    }
    var leadershipNarrative: String {
        guard let rules, rules.leadershipVenue != "elsewhere" else { return "" }
        var text: String
        switch rules.leadershipModel {
        case "maintainer": text = "One person maintains this patch. They handle day-to-day decisions and can designate a successor."
        case "meritocratic": text = "Admins earn their role through sustained contribution. When a seat opens, existing admins nominate from active members and the community ratifies."
        case "elected": text = "The community elects admins for fixed terms. Regular elections ensure power rotates."
        default: return ""
        }
        if let days = rules.inactivityDays, days > 0 {
            text += " An admin who does not vote, propose or comment here for \(days) days is warned, and the seat is declared vacant at \(days * 2) days."
        }
        return text
    }
}

struct Proposal: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let body: String?
    let status: String?
    let state: String?
    let proposalType: String?
    let targetDoc: String?
    let authorName: String?
    let votingEndsAt: String?
    let createdAt: String?
    let approveCount: Int?
    let rejectCount: Int?
    let abstainCount: Int?
    let electionPhase: String?
    var ballots: Int { (approveCount ?? 0) + (rejectCount ?? 0) + (abstainCount ?? 0) }
    /// An approved proposal with no ballots was born applied under
    /// admin-decides rules: a direct change, not a vote nobody turned up to.
    var isDirectChange: Bool { status == "approved" && ballots == 0 }
    /// What this proposal's outcome is *called*. `state` is read before
    /// `status` because a lapsed vote and an unsettled contest both carry the
    /// schema's terminal `rejected` without anybody having rejected anything
    /// (web ADR 097, ADR 051).
    var outcome: String {
        if isDirectChange { return "applied" }
        if state == "lapsed" { return "lapsed" }
        if state == "unsettled" { return "unsettled" }
        return status ?? ""
    }
    /// Red is for a decision the patch made; an absence keeps the muted default.
    var outcomeIsDecision: Bool { outcome == "rejected" }
    var outcomeIsOpen: Bool { outcome == "open" }
}

struct ProposalPage: Decodable {
    let items: [Proposal]?
    let nextCursor: String?
    let publicGovernanceRecord: String?
}

/// One settled thing, assembled from whatever feature owns it (web ADR 055).
struct GovernanceRecordEntry: Decodable, Identifiable, Hashable {
    let kind: String
    let at: String?
    let title: String
    let summary: String?
    let link: String?
    let outcome: String?
    let actor: String?
    let names: [String]?
    var id: String { "\(kind)|\(at ?? "")|\(title)" }
    var kindLabel: String {
        switch kind {
        case "vote": return "Vote"
        case "direct": return "Direct change"
        case "election": return "Election"
        case "council": return "Council"
        case "adoption": return "Adopted elsewhere"
        default: return kind.capitalized
        }
    }
    var settled: Bool { !["unsettled", "failed", "lapsed"].contains(outcome ?? "") }
    /// Names as a person reads them aloud: a record is prose.
    private func listOf(_ names: [String]) -> String {
        if names.count == 1 { return names[0] }
        return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
    }
    /// One sentence saying how it was settled. No tally: the outcome is
    /// stored when a vote resolves and never moves, while counts are
    /// recomputed and drift (web ADR 044).
    var outcomeLine: String {
        switch kind {
        case "vote":
            if outcome == "carried" { return "Carried by a vote." }
            if outcome == "lapsed" { return "Put to a vote. Nobody decided it either way; the proposal lapsed." }
            return "Put to a vote and did not carry."
        case "direct":
            if outcome == "declined" { return actor.map { "Declined by \($0)." } ?? "Declined by the maintainer." }
            return actor.map { "Applied by \($0)." } ?? "Applied without a vote."
        case "election":
            guard outcome == "seated" else { return "Settled nothing. Nobody was elected." }
            if let names, !names.isEmpty { return "The members seated \(listOf(names))." }
            return "The members seated a council."
        case "council":
            if let names, !names.isEmpty { return "Seated \(listOf(names))." }
            return "A meeting chose the council."
        case "adoption":
            return "A meeting adopted this text."
        default:
            return ""
        }
    }
}

struct GovernanceRecordPage: Decodable {
    let items: [GovernanceRecordEntry]?
    let publicGovernanceRecord: String?
}

/// Dates on a profile arrive as either a full timestamp or a bare calendar
/// day (`next_contest_opens`), and either may be an empty string.
enum ProfileDate {
    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = PatchworkEvent.parseDate(value) { return date }
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = .current
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: value)
    }
    static func day(_ value: String?) -> String? {
        guard let date = parse(value) else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
    static func monthYear(_ value: String?) -> String? {
        guard let date = parse(value) else { return nil }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM y")
        return formatter.string(from: date)
    }
}

/// The atproto handle a `did:web` names, and nothing else (web ADR 062). The
/// handle is derived from the DID rather than the verification domain because
/// the DID is the half that travels when a patch forks.
enum AtprotoHandle {
    static func from(_ did: String?) -> String? {
        let value = (did ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("did:web:") else { return nil }
        let host = value.dropFirst("did:web:".count).split(separator: ":").first.map(String.init) ?? ""
        guard !host.isEmpty else { return nil }
        return host.replacingOccurrences(of: "%3A", with: ":", options: .caseInsensitive)
    }
}

// The account half of the contract. This client holds one signed-in person at
// a time per quilt, and this is everything it knows about them.

/// The person the session cookie names (`auth/me`, and the answer to both
/// sign-in posts). `email` is served only to the account that owns it.
struct User: Decodable, Hashable, Identifiable {
    let id: String
    let username: String
    let displayName: String?
    let bio: String?
    let avatarUrl: String?
    let role: String?
    let email: String?
    /// The name to print, the way a steward's is printed: what they filled in,
    /// or the handle with its at sign so a bare word is never mistaken for a
    /// display name nobody chose.
    var title: String { (displayName?.isEmpty == false ? displayName : nil) ?? handle }
    var handle: String { "@" + username }
    var avatar: URL? { (avatarUrl?.isEmpty == false) ? URL(string: avatarUrl!) : nil }
}

/// What a 200 from `auth/magic-link/verify` turned out to be.
enum SignInOutcome: Equatable {
    case signedIn(User)
    /// The address has no account yet. The token is the quilt's proof that
    /// this address answered its code, and it is spent by `auth/signup`.
    case usernameRequired(token: String)
}

/// Both sign-in posts and `auth/me` answer at the same level: either the user
/// object itself or, for the address with no account, a status and a token. So
/// one type decodes both, and the shape is read afterwards rather than guessed
/// at from which endpoint was called.
struct SignInResponse: Decodable {
    let status: String?
    let signupToken: String?
    let user: User?
    private enum CodingKeys: String, CodingKey { case status, signupToken, user }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        signupToken = try? container.decodeIfPresent(String.self, forKey: .signupToken)
        // Tolerated rather than required: a quilt that wraps the user in
        // `{"user": …}` is read the same as one that does not.
        if let nested = try? container.decode(User.self, forKey: .user) { user = nested }
        else { user = try? User(from: decoder) }
    }
    func outcome() throws -> SignInOutcome {
        if status == "username_required" {
            guard let token = signupToken, !token.isEmpty else { throw APIError.response }
            return .usernameRequired(token: token)
        }
        guard let user else { throw APIError.response }
        return .signedIn(user)
    }
}
