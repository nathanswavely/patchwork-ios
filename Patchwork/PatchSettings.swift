// SPDX-License-Identifier: MPL-2.0

import Foundation

// The rest of what a patch's admin keeps from a phone, as values: the
// noticeboard's report queue and its two settings (web
// `PatchSettingsNoticeboard.svelte`, ADR 081), the role changes on the
// members room (`PatchSettingsMembers.svelte`, ADRs 051, 052, 100, 117), and
// editing the patch itself (`PatchSettingsInfo.svelte` and
// `PatchSettingsAppearance.svelte`). The screens are in `NoticeReports.swift`,
// `PatchMembers.swift` and `PatchForm.swift`.
//
// What stays the website's, and why: Sources (feeds, the duplicates
// crosswalk and aggregator holds are a desk's work), the patch's
// notification categories (set once), Verification (an instance admin's
// page), and Danger — archiving, which only an instance admin can undo.

// MARK: - The report queue

/// One report about a notice or a reply, as the patch's own queue serves it
/// (`ListPatchReports`): the report, who made it, and what it is about,
/// quoted so the admin can judge it without leaving the queue.
///
/// The server sends every field; each is read as optional anyway, so a quilt
/// a version behind is read rather than refused.
struct NoticeReport: Decodable, Identifiable, Hashable {
    let id: String
    var reporterId = ""
    /// `notice` or `reply`.
    var entityType = ""
    var entityId = ""
    var reason = ""
    var details = ""
    /// `pending`, `resolved` or `dismissed`.
    var status = "pending"
    var resolutionNote = ""
    var createdAt = ""
    /// The reporter's display name, else their username. The server always
    /// says who reported; the queue is the patch's admins', and they are
    /// told.
    var reporterName = ""
    /// A notice's title, or a reply's body.
    var target = ""
    /// The notice to open: the reported one, or the one a reported reply
    /// sits under.
    var noticeId = ""
    /// What was reported is no longer there: its author took it down, or
    /// another admin did, before this report was reviewed.
    var gone = false

    init(id: String, entityType: String = "notice", entityId: String = "", reason: String = "", details: String = "",
         status: String = "pending", resolutionNote: String = "", createdAt: String = "", reporterName: String = "",
         target: String = "", noticeId: String = "", gone: Bool = false) {
        self.id = id; self.entityType = entityType; self.entityId = entityId; self.reason = reason
        self.details = details; self.status = status; self.resolutionNote = resolutionNote; self.createdAt = createdAt
        self.reporterName = reporterName; self.target = target; self.noticeId = noticeId; self.gone = gone
    }

    private enum CodingKeys: String, CodingKey {
        case id, reporterId, entityType, entityId, reason, details, status, resolutionNote, createdAt
        case reporterName, target, noticeId, gone
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? "" }
        id = try c.decode(String.self, forKey: .id)
        reporterId = text(.reporterId); entityType = text(.entityType); entityId = text(.entityId)
        reason = text(.reason); details = text(.details)
        let state = text(.status)
        status = state.isEmpty ? "pending" : state
        resolutionNote = text(.resolutionNote); createdAt = text(.createdAt)
        reporterName = text(.reporterName); target = text(.target); noticeId = text(.noticeId)
        gone = ((try? c.decodeIfPresent(Bool.self, forKey: .gone)) ?? nil) ?? false
    }

    /// "notice" or "reply", for the sentences that name it.
    var thing: String { entityType == "reply" ? "reply" : "notice" }
}

struct NoticeReportPage: Decodable {
    var items: [NoticeReport] = []
    var nextCursor = ""
    private enum CodingKeys: String, CodingKey { case items, nextCursor }
    init(items: [NoticeReport] = [], nextCursor: String = "") { self.items = items; self.nextCursor = nextCursor }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = ((try? c.decodeIfPresent([NoticeReport].self, forKey: .items)) ?? nil) ?? []
        nextCursor = ((try? c.decodeIfPresent(String.self, forKey: .nextCursor)) ?? nil) ?? ""
    }
}

enum NoticeReports {
    /// The queue's three tabs, in the web's order and words.
    enum Status: String, CaseIterable, Identifiable {
        case pending, resolved, dismissed
        var id: String { rawValue }
        var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
        /// The web's "No {tab} reports."
        var empty: String { "No \(rawValue) reports." }
    }

    /// The moderation kit (ADR 081, decision 2): three things, and nothing a
    /// forum would add.
    enum Action: String, CaseIterable, Identifiable, Equatable {
        case dismiss
        case remove
        case closeReplies = "close_replies"
        var id: String { rawValue }
        /// The web's option labels.
        func title(_ thing: String) -> String {
            switch self {
            case .dismiss: return "Dismiss, leave it up"
            case .remove: return "Remove the \(thing)"
            case .closeReplies: return "Switch replies off on the notice"
            }
        }
        /// What the option does that its label cannot say: what changes for
        /// the room, and what the person who reported it hears — which is
        /// "reviewed", and no more, whatever was decided.
        func consequence(_ thing: String) -> String {
            switch self {
            case .dismiss:
                return "The \(thing) stays up. Whoever reported it is told it was reviewed, and nothing more."
            case .remove:
                return "The \(thing) is taken down for good, for everyone. Whoever reported it is told it was reviewed, and nothing more."
            case .closeReplies:
                return thing == "reply"
                    ? "The reply stays up, and nobody can reply under its notice until its author or an admin switches replies back on."
                    : "The notice stays up, and nobody can reply to it until its author or an admin switches replies back on."
            }
        }
        var destructive: Bool { self == .remove }
    }

    /// What may be done about a report. Something already taken down can
    /// only be dismissed — the web offers nothing else, and there is nothing
    /// left to remove or to close.
    static func actions(for report: NoticeReport) -> [Action] {
        report.gone ? [.dismiss] : Action.allCases
    }

    /// `PATCH nodes/{slug}/reports/{id}`. The note always travels, trimmed
    /// and possibly empty, as the web sends it.
    struct ActBody: Encodable, Equatable {
        let action: String
        let resolutionNote: String
    }
    static func body(_ action: Action, note: String = "") -> ActBody {
        ActBody(action: action.rawValue, resolutionNote: note.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A page of one tab, oldest report first, as the server orders it.
    static func query(_ status: Status, after: String? = nil, limit: Int = 20) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "status", value: status.rawValue), URLQueryItem(name: "limit", value: String(limit))]
        if let after, !after.isEmpty { items.append(URLQueryItem(name: "after", value: after)) }
        return items
    }

    // MARK: Words

    /// The row's head: what it is, when, and who — the web's "reported by".
    static func head(_ report: NoticeReport, now: Date = Date()) -> String {
        var parts = [report.thing.prefix(1).uppercased() + report.thing.dropFirst()]
        let ago = NotificationTime.ago(report.createdAt, now: now)
        if !ago.isEmpty { parts.append(ago) }
        let name = report.reporterName.trimmingCharacters(in: .whitespacesAndNewlines)
        parts.append("reported by \(name.isEmpty ? "someone" : name)")
        return parts.joined(separator: " · ")
    }
    static let gone = "Already taken down."
    static let intro = "Reports about notices and replies come to this patch’s admins. Three things can be done with one: dismiss it, remove what was reported, or switch replies off on the notice."
    /// The web's toasts.
    static let done = "Report reviewed"
    static let failed = "Could not resolve the report"

    /// The Dashboard's ask and the board's door: a count that may be a floor,
    /// because the queue is paged and has no total.
    static func askLabel(_ count: Int, more: Bool) -> String {
        let number = DashboardGrouping.countLabel(count: count, more: more)
        return count == 1 && !more ? "1 report to review" : "\(number) reports to review"
    }
}

// MARK: - The noticeboard's settings

enum NoticeboardSettings {
    /// "Who puts up notices": the web's two segments, in its order.
    enum Posting: String, CaseIterable, Identifiable {
        case members, admins
        var id: String { rawValue }
        var title: String { self == .members ? "Members" : "Admins only" }
    }

    /// Each control saves itself, as the web's do: one field per write.
    struct Body: Encodable, Equatable {
        var noticePosting: String? = nil
        var noticeRepliesDefault: Bool? = nil
    }
    static func body(posting: Posting) -> Body { Body(noticePosting: posting.rawValue) }
    static func body(repliesDefault: Bool) -> Body { Body(noticeRepliesDefault: repliesDefault) }

    /// The web's toasts.
    static func saved(posting: Posting) -> String {
        posting == .admins ? "Only admins put up notices now" : "Members can put up notices"
    }
    static func saved(repliesDefault: Bool) -> String {
        repliesDefault ? "New notices take replies" : "New notices start with replies off"
    }
    static let postingDetail = "Members too, or only this patch’s admins. Anyone in the room can reply either way."
    static let repliesDetail = "The starting position. Each notice’s author decides for their own, and can change it later."
}

// MARK: - Roles

/// A role change from the members room (`PATCH nodes/{slug}/members/{userId}`
/// with `{"role"}`). Two of the web's three: making somebody an admin, and
/// making an admin a member again. Moving somebody down to follower stays on
/// the website, where its consequence — their contact shares are dropped —
/// is beside the control.
enum RoleChange: String, Equatable, Identifiable {
    case promote, demote
    var id: String { rawValue }
    var role: String { self == .promote ? "admin" : "member" }
    struct Body: Encodable, Equatable { let role: String }
    var body: Body { Body(role: role) }
    var title: String { self == .promote ? "Promote to admin" : "Make member" }
    var symbol: String { self == .promote ? "person.badge.shield.checkmark" : "person" }
    /// The web's toasts.
    static let done = "Role updated"
    static let failed = "Failed to change role"
    /// What the confirmation says that the button cannot: what the role
    /// carries, and that nobody is told — the server sends no notification
    /// for a role change.
    func consequence(_ name: String, isMe: Bool) -> String {
        switch (self, isMe) {
        case (.promote, _):
            return "\(name) can answer requests, review suggestions, change this patch’s settings and anyone’s role here. They aren’t notified."
        case (.demote, true):
            return "You stop being an admin of this patch, and these tools go with it. Only another admin can make you one again."
        case (.demote, false):
            return "\(name) stays a member and stops being an admin. They aren’t notified."
        }
    }

    /// Whether a promotion made here would be honoured, read from the rules
    /// the governance overview carries. The server refuses one where the
    /// patch chooses its admins elsewhere, ratifies them by proposal
    /// (meritocratic), or elects its council — each with a sentence about
    /// using that mechanism instead — so the act is offered only where
    /// leadership is a maintainer's to hand out. Rules that could not be
    /// read offer nothing: a refusal is not an answer worth a button.
    static func promotionAllowed(_ rules: GovernanceRules?) -> Bool {
        guard let rules, rules.leadershipVenue != "elsewhere" else { return false }
        return rules.leadershipModel != "meritocratic" && rules.leadershipModel != "elected"
    }

    /// The acts on one row of the members room. Only the patch's own admin is
    /// offered any; never on a follower (a follower joins, ADR 117), an
    /// invited row, or anybody not active. Demotion is offered on the
    /// reader's own row too, as the web's control is: the server allows it,
    /// and the last-admin floor is its to state.
    static func offered(_ member: PatchMember, runs: Bool, rules: GovernanceRules?) -> [RoleChange] {
        guard runs, let userId = member.userId, !userId.isEmpty else { return [] }
        guard member.status == nil || member.status == "active" else { return [] }
        switch member.role {
        case "member": return promotionAllowed(rules) ? [.promote] : []
        case "admin": return [.demote]
        default: return []
        }
    }

    /// The line under the roster: why "Promote to admin" is or is not there,
    /// in the server's terms (its 409s), and what stays on the website.
    static func note(_ overview: GovernanceOverview?) -> String {
        let website = "Moving someone to follower happens on this quilt’s website."
        guard let rules = overview?.rules else {
            return "Making someone an admin happens on this quilt’s website. " + website
        }
        if rules.leadershipVenue == "elsewhere" {
            return "This patch chooses its admins elsewhere, so admins are not made here: that decision is recorded on its Governance page. " + website
        }
        switch rules.leadershipModel {
        case "meritocratic":
            return "This patch ratifies admins by proposal, so admins are not made here: nominate them on its Governance page. " + website
        case "elected":
            return councilNote(seats: overview?.seats ?? [], nextContestOpens: overview?.nextContestOpens) + " " + website
        default:
            return website
        }
    }

    /// The web's council note, in its three cases.
    static func councilNote(seats: [GovernanceSeat], nextContestOpens: String?) -> String {
        let lead = "This patch elects its council, so admins are not made here."
        let vacant = seats.filter(\.isVacant).count
        if vacant > 0 {
            return lead + " \(vacant) seat\(vacant == 1 ? " is" : "s are") vacant: an admin nominates a member on the Governance page and the members ratify it."
        }
        if let opens = ProfileDate.day(nextContestOpens) {
            let held = seats.count == 1 ? "The 1 seat is held" : "All \(seats.count) seats are held"
            return lead + " \(held); the next election opens \(opens). To make room sooner, add a seat on the Governance page, or bring a seat’s term end forward there."
        }
        return lead + " Every seat is held and no election is scheduled. To make room, add a seat on the Governance page."
    }
}

extension PatchMember {
    /// The same row holding another role: what the roster shows the moment a
    /// change is asked for.
    func withRole(_ role: String) -> PatchMember {
        PatchMember(id: id, userId: userId, username: username, displayName: displayName, avatarUrl: avatarUrl,
                    role: role, status: status, joinedAt: joinedAt, joinMessage: joinMessage)
    }
}

// MARK: - Editing the patch

/// `PATCH nodes/{slug}` from the edit form: only what changed. Every field
/// is optional and an absent one is not sent, so a save never writes back a
/// value the reader did not touch — which matters most for the tile, where a
/// block drafted on the website would otherwise be overwritten by the
/// curated one the form shows. A cleared text field is sent as `""`, and a
/// point taken off the map as `null` for both halves, which is how the
/// server clears each.
struct PatchEditBody: Encodable, Equatable {
    var name: String?
    var description: String?
    var address: String?
    var website: String?
    /// Outer nil: unchanged. Inner nil: taken off the map.
    var point: MapPoint??
    var tags: [String]?
    var suggestTags: [String]?
    var appearance: AppearanceChoice?
    var visibility: String?
    var acceptEventSuggestions: Bool?
    var timezone: String?
    /// The answer to the server's 409 about events that follow the zone:
    /// `keep_clock` or `keep_instant`. Sent only once it has been asked.
    var timezoneEvents: String?
    /// The image and its description travel together (web ADR 007).
    var imageUrl: String?
    var imageAlt: String?
    var links: [PatchLink]?

    var isEmpty: Bool { self == PatchEditBody() }

    private enum CodingKeys: String, CodingKey {
        case name, description, address, website, latitude, longitude, tags, suggestTags, appearance
        case visibility, acceptEventSuggestions, timezone, timezoneEvents, imageUrl, imageAlt, links
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(address, forKey: .address)
        try c.encodeIfPresent(website, forKey: .website)
        if let point {
            if let point {
                try c.encode(point.latitude, forKey: .latitude)
                try c.encode(point.longitude, forKey: .longitude)
            } else {
                try c.encodeNil(forKey: .latitude)
                try c.encodeNil(forKey: .longitude)
            }
        }
        try c.encodeIfPresent(tags, forKey: .tags)
        try c.encodeIfPresent(suggestTags, forKey: .suggestTags)
        try c.encodeIfPresent(appearance, forKey: .appearance)
        try c.encodeIfPresent(visibility, forKey: .visibility)
        try c.encodeIfPresent(acceptEventSuggestions, forKey: .acceptEventSuggestions)
        try c.encodeIfPresent(timezone, forKey: .timezone)
        try c.encodeIfPresent(timezoneEvents, forKey: .timezoneEvents)
        try c.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try c.encodeIfPresent(imageAlt, forKey: .imageAlt)
        try c.encodeIfPresent(links, forKey: .links)
    }
}

enum PatchEditing {
    /// Whether the form may touch the tile. A patch wearing a block drafted
    /// on the website, or a bundle of fabrics picked there, is shown as it is
    /// and left alone: the form only knows curated blocks and pre-cut
    /// palettes, and saving one would throw the drafted work away.
    static func appearanceLocked(_ appearance: Appearance?) -> Bool {
        if case .drafted = appearance?.block { return true }
        return !(appearance?.bundle ?? []).isEmpty
    }
    static let appearanceLockedNote = "This patch wears a block or fabrics drafted on the website. Change how it looks in Patch Settings → Appearance there."

    /// The web's place-zone check before the round trip: an IANA place name
    /// this device resolves, never a bare offset like EST, which is not a
    /// place and is an hour wrong half the year. Empty follows the quilt.
    static func zoneProblem(_ text: String) -> String? {
        let zone = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !zone.isEmpty else { return nil }
        if zone == "UTC" || (zone.contains("/") && TimeZone(identifier: zone) != nil) { return nil }
        return "That is not a place this quilt keeps time in. Try America/New_York."
    }

    /// The 409 that asks what happens to the events that follow the zone.
    static let zoneQuestionCode = "timezone_events_undecided"
    /// The server's sentence starts with the count; the buttons read in the
    /// singular for one event, as the web's do.
    static func zoneEventCount(_ sentence: String) -> Int {
        Int(sentence.prefix { $0.isNumber }) ?? 0
    }
    static func keepClockTitle(_ count: Int) -> String { count == 1 ? "Keep the listed time" : "Keep the listed times" }
    static func keepInstantTitle(_ count: Int) -> String {
        count == 1 ? "Leave the event where it is" : "Leave the events where they are"
    }
    static let zoneExplainer = "Keeping listed times moves each event to the new zone, so 7pm stays 7pm. Leaving them where they are keeps the exact moment and changes the clock time shown. Events with a timezone of their own, and events from a calendar feed, are not touched."

    /// Visibility, with the consequence beside the word (the web's options).
    static let visibilities: [(value: String, title: String, detail: String)] = [
        ("public", "Public", "On the quilt. Anyone can find this patch through the quilt, search, the map, and public event feeds, and other quilts can follow it."),
        ("private", "Private", "Off the quilt. Kept out of the quilt, search, the map, and public feeds, and it does not federate."),
    ]

    /// What the form leaves to Patch Settings on the website, said once at
    /// its foot.
    static let websiteNote = "When the group was founded, a move to another quilt, feeds and sources, the patch’s notifications, and archiving it are in Patch Settings on the website. The membership policy is one of the patch’s rules, changed from its Governance room."

    static let saved = "Changes saved"
    static let failed = "Failed to save"
}

extension PatchDraft {
    /// The edit form's draft: the patch as it stands. The tile is the one it
    /// wears — chosen or hash-assigned — so nothing changes unless somebody
    /// changes it.
    init(editing patch: Patch) {
        self.init(setup: patch)
        visibility = patch.visibility == "private" ? "private" : "public"
        acceptSuggestions = patch.acceptEventSuggestions == true
        timezone = patch.timezone ?? ""
        imageURL = patch.imageUrl ?? ""
        imageAlt = patch.imageAlt ?? ""
        links = patch.links ?? []
    }

    /// The fields that differ from the patch as it was loaded — nothing more.
    func changes(from original: PatchDraft, appearanceLocked: Bool = false) -> PatchEditBody {
        func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var body = PatchEditBody()
        if trimmed(name) != trimmed(original.name) { body.name = trimmed(name) }
        if trimmed(description) != trimmed(original.description) { body.description = trimmed(description) }
        if trimmed(address) != trimmed(original.address) { body.address = trimmed(address) }
        if trimmed(website) != trimmed(original.website) { body.website = trimmed(website) }
        if point != original.point { body.point = .some(point) }
        // The web sends the whole set with any suggestion, and the server's
        // replace is scoped to approved tags, so a word waiting for review
        // is never deleted by it.
        if tags != original.tags || !suggestTags.isEmpty {
            body.tags = tags
            if !suggestTags.isEmpty { body.suggestTags = suggestTags }
        }
        if !appearanceLocked && appearance != original.appearance { body.appearance = appearance }
        if visibility != original.visibility { body.visibility = visibility }
        if acceptSuggestions != original.acceptSuggestions { body.acceptEventSuggestions = acceptSuggestions }
        if trimmed(timezone) != trimmed(original.timezone) { body.timezone = trimmed(timezone) }
        if trimmed(imageURL) != trimmed(original.imageURL) || trimmed(imageAlt) != trimmed(original.imageAlt) {
            body.imageUrl = trimmed(imageURL)
            body.imageAlt = trimmed(imageURL).isEmpty ? "" : trimmed(imageAlt)
        }
        let cleaned = links.map { PatchLink(url: trimmed($0.url), label: trimmed($0.label)) }.filter { !$0.url.isEmpty }
        if cleaned != original.links { body.links = cleaned }
        return body
    }

    /// The edit form's own checks, before anything is sent, in the words the
    /// server or the web would use.
    func editProblem() -> String? {
        if let problem = problem() { return problem }
        if let problem = PatchEditing.zoneProblem(timezone) { return problem }
        let url = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty, let problem = EventPosting.imageProblem(url: url, alt: imageAlt) { return sentenceCased(problem) }
        return nil
    }
}

// MARK: - The calls

extension PatchworkAPI {
    func noticeReports(slug: String, status: NoticeReports.Status, after: String? = nil, limit: Int = 20) async throws -> NoticeReportPage {
        try await get("nodes/\(slug)/reports", query: NoticeReports.query(status, after: after, limit: limit))
    }
    func actOnReport(slug: String, id: String, _ action: NoticeReports.Action, note: String = "") async throws {
        let _: AdminAnswer = try await patch("nodes/\(slug)/reports/\(id)", body: NoticeReports.body(action, note: note))
    }
    func saveNoticeboardSettings(slug: String, _ body: NoticeboardSettings.Body) async throws {
        try await sendVoid("PATCH", "nodes/\(slug)", body: body)
    }
    func changeRole(slug: String, userId: String, _ change: RoleChange) async throws {
        let _: AdminAnswer = try await patch("nodes/\(slug)/members/\(userId)", body: change.body)
    }
    func editPatch(slug: String, _ body: PatchEditBody) async throws {
        try await sendVoid("PATCH", "nodes/\(slug)", body: body)
    }
}
