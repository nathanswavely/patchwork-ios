// SPDX-License-Identifier: MPL-2.0

import Foundation

// What a patch's admin answers from a phone: the requests to join, the
// events somebody suggested, the invitations, and removing somebody and
// taking them back. Reference: the web's `PatchSettingsMembers.svelte` and
// `PatchEvents.svelte` ("Suggested events"), the server's `ListMembers`,
// `UpdateMember`, `InviteMember`, `RescindInvitation`,
// `ListNodeEventSubmissions` and `ReviewEventSubmission`, and web ADRs 026,
// 040, 081, 093 and 098.
//
// None of it is step-up gated. Role changes are left on the website: the
// server refuses most promotions with a sentence about how the patch makes
// its admins, and the web's council note carries context a phone row cannot.

// MARK: - The shapes

/// One outstanding invitation, as the members listing carries it to the
/// patch's own admins (`invitedPeople`).
struct InvitedPerson: Decodable, Identifiable, Hashable {
    let id: String
    let userId: String
    let username: String?
    let displayName: String?
    let avatarUrl: String?
    let invitedAt: String?
    var name: String {
        let display = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty { return display }
        let handle = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return handle.isEmpty ? "Someone" : handle
    }
    var initial: String { String(name.first ?? "?").uppercased() }
    var avatar: URL? { (avatarUrl?.isEmpty == false) ? URL(string: avatarUrl!) : nil }
}

/// A suggestion waiting on the patch's admins: the event as it was
/// suggested, and who suggested it.
///
/// The server's list reads fewer columns than an event has: `timezone`, the
/// image pair and the event's page arrive as empty strings, whatever the
/// event holds. So the time is read in the patch's own zone here, and the
/// event is handed to its page carrying that zone (`PatchworkEvent.inZone`).
struct EventSubmission: Decodable, Identifiable, Hashable {
    let event: PatchworkEvent
    let submitterUsername: String?
    let submitterDisplayName: String?
    var id: String { event.id }
    /// The web's "Suggested by {display_name || username || 'unknown'}".
    var submitter: String {
        for candidate in [submitterDisplayName, submitterUsername] {
            let text = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return "unknown"
    }
    private enum CodingKeys: String, CodingKey { case submitterUsername, submitterDisplayName }
    init(from decoder: Decoder) throws {
        event = try PatchworkEvent(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        submitterUsername = try container.decodeIfPresent(String.self, forKey: .submitterUsername)
        submitterDisplayName = try container.decodeIfPresent(String.self, forKey: .submitterDisplayName)
    }
    init(event: PatchworkEvent, submitterUsername: String?, submitterDisplayName: String?) {
        self.event = event
        self.submitterUsername = submitterUsername
        self.submitterDisplayName = submitterDisplayName
    }
}

struct SubmissionPage: Decodable {
    let items: [EventSubmission]?
}

/// What a write answers. Only the status is ever read, and nothing waits on
/// it: the screens draw the act as done the moment it is asked for.
struct AdminAnswer: Decodable {
    let status: String?
}

extension PatchworkEvent {
    /// The same event, keeping time in the zone given — for a suggestion,
    /// whose list row arrives with its zone blank, so the page it opens says
    /// the hour the patch means before its own read comes back.
    func inZone(_ zone: TimeZone) -> PatchworkEvent {
        guard (timezone ?? "").isEmpty else { return self }
        return PatchworkEvent(
            id: id, title: title, description: description, location: location, startsAt: startsAt,
            endsAt: endsAt, timezone: zone.identifier, nodeName: nodeName, nodeSlug: nodeSlug, eventUrl: eventUrl,
            nodeId: nodeId, nodeStatus: nodeStatus, visibility: visibility, recurrence: recurrence,
            imageUrl: imageUrl, imageAlt: imageAlt, latitude: latitude, longitude: longitude, status: status,
            sourceId: sourceId, links: links, mentions: mentions, createdBy: createdBy, viewerTrusted: viewerTrusted)
    }
}

// MARK: - The rules

enum PatchAdmin {
    /// Whether the reader runs this patch, read off the membership index.
    ///
    /// Never off `is_admin` alone, and never the quilt's admin: the members
    /// listing quietly answers anybody else's `status=pending` with the
    /// active list rather than a refusal, and the invitation routes answer an
    /// instance admin with no role here 404 (web ADR 081's room rule). So the
    /// door is drawn only where every act behind it will be honoured.
    static func runs(_ standing: Standing?) -> Bool { standing == .active(.admin) }

    /// Who reviews a suggestion: the patch's admins, or the quilt's admin
    /// (the web's `canReview`, and the server's `ReviewEventSubmission`).
    static func reviews(standing: Standing?, isInstanceAdmin: Bool) -> Bool {
        isInstanceAdmin || runs(standing)
    }

    /// Whether Remove is offered on a member's row. Never on the reader
    /// themselves — the server refuses it ("cannot ban yourself"), where the
    /// web draws the button anyway — and never on a row that is not an
    /// active member or admin, which is all the server bans.
    static func mayRemove(_ member: PatchMember, me: String?) -> Bool {
        guard let userId = member.userId, !userId.isEmpty, userId != me else { return false }
        guard member.status == nil || member.status == "active" else { return false }
        return member.role == "member" || member.role == "admin"
    }

    // MARK: Queries

    /// A page of the queue, oldest request first, as the server orders it.
    static func membersQuery(status: String, after: String? = nil, limit: Int = 20) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "status", value: status), URLQueryItem(name: "limit", value: String(limit))]
        if let after, !after.isEmpty { items.append(URLQueryItem(name: "after", value: after)) }
        return items
    }

    // MARK: The four acts on a membership

    /// One `PATCH nodes/{slug}/members/{userId}` and everything said about
    /// it. Rejecting and reinstating send the same body; the server tells
    /// them apart by the row's state.
    enum MemberAct: Equatable {
        case approve, reject, remove, reinstate
        var status: String {
            switch self {
            case .approve: return "active"
            case .reject, .reinstate: return "left"
            case .remove: return "banned"
            }
        }
        var body: StatusBody { StatusBody(status: status) }
        /// The button, and the confirmation's button (the web's
        /// `ConfirmAction` labels).
        var title: String {
            switch self {
            case .approve: return "Approve"
            case .reject: return "Reject"
            case .remove: return "Remove"
            case .reinstate: return "Reinstate"
            }
        }
        var destructive: Bool { self == .reject || self == .remove }
        /// The web's toasts.
        var done: String {
            switch self {
            case .approve: return "Member approved"
            case .reject: return "Request rejected"
            case .remove: return "Member removed"
            case .reinstate: return "Member reinstated"
            }
        }
        var failed: String {
            switch self {
            case .approve: return "Failed to approve member"
            case .reject: return "Failed to reject member"
            case .remove: return "Failed to remove member"
            case .reinstate: return "Failed to reinstate"
            }
        }
        /// The line under the web's "Are you sure?": what the act does that
        /// the button cannot say — who is told, and what they can do next.
        func consequence(_ name: String) -> String {
            switch self {
            case .approve:
                return "\(name) becomes a member and is told their request was approved."
            case .reject:
                return "\(name) isn’t told, and can ask to join again later."
            case .remove:
                return "\(name) is told they were removed, and can’t rejoin unless an admin reinstates them."
            case .reinstate:
                return "\(name) is told, and can ask to join again. Reinstating doesn’t make them a member."
            }
        }
    }

    struct StatusBody: Encodable, Equatable { let status: String }

    // MARK: Reviewing a suggestion

    /// `PATCH events/{id}/review`. The note goes only with a decline, and
    /// only where somebody wrote one, trimmed — the web's rule.
    struct ReviewBody: Encodable, Equatable {
        let action: String
        let note: String?
    }
    static func reviewBody(approve: Bool, note: String = "") -> ReviewBody {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReviewBody(action: approve ? "approve" : "reject", note: approve || text.isEmpty ? nil : text)
    }

    // MARK: Inviting

    struct InviteBody: Encodable, Equatable { let username: String }
    /// The name as typed, trimmed; nothing to send while it is empty. The
    /// server strips a leading `@` itself, so a pasted handle is kept as it
    /// came.
    static func inviteBody(_ text: String) -> InviteBody? {
        let username = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, username != "@" else { return nil }
        return InviteBody(username: username)
    }

    // MARK: Words

    /// The Dashboard's asks, in the web's words for the requests.
    static func requestsLabel(_ count: Int) -> String {
        count == 1 ? "1 pending member request" : "\(count) pending member requests"
    }
    static func suggestionsLabel(_ count: Int) -> String {
        count == 1 ? "1 suggested event" : "\(count) suggested events"
    }
    static func queueCount(_ count: Int) -> String {
        count == 1 ? "1 request waiting" : "\(count) requests waiting"
    }
    /// "Asked 2d ago": the request's own moment (`joined_at` on a pending
    /// row is when it was made).
    static func asked(_ joinedAt: String?, now: Date = Date()) -> String? {
        let ago = NotificationTime.ago(joinedAt, now: now)
        return ago.isEmpty ? nil : "Asked \(ago)"
    }
    static func invitedLine(_ invitedAt: String?, now: Date = Date()) -> String? {
        let ago = NotificationTime.ago(invitedAt, now: now)
        return ago.isEmpty ? nil : "Invited \(ago)"
    }
    /// The intro note, in curly quotes as the web sets it.
    static func quoted(_ message: String?) -> String? {
        let text = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : "“\(text)”"
    }

    /// "Sat, Oct 18 · 7:00 PM · Library basement": the web's suggested-event
    /// line (`formatEventDate` · `formatEventTime` · location), the year
    /// added only when it is not this one, read in the zone given.
    static func submissionLine(_ event: PatchworkEvent, zone: TimeZone, now: Date = Date()) -> String {
        var parts: [String] = []
        if let date = event.date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            let day = DateFormatter()
            day.locale = Locale(identifier: "en_US")
            day.timeZone = zone
            day.setLocalizedDateFormatFromTemplate(sameYear ? "EEE MMM d" : "EEE MMM d y")
            let time = DateFormatter()
            time.locale = Locale(identifier: "en_US")
            time.timeZone = zone
            time.setLocalizedDateFormatFromTemplate("h:mm a")
            // The system sets a narrow no-break space before "PM"; a plain
            // one reads the same and matches what is typed and searched.
            parts = [day.string(from: date), time.string(from: date)].map { $0.replacingOccurrences(of: "\u{202F}", with: " ") }
        }
        if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            parts.append(location)
        }
        return parts.joined(separator: " · ")
    }

    static let approvedTier = "Approving publishes a suggestion to everyone. To keep it to followers or members, edit the event once it’s approved."
    static let declineConsequence = "Declining deletes the suggestion from this quilt. Whoever suggested it is told it was declined, with your note if you write one."
    static let roleNote = "Changing someone’s role, or making them an admin, happens on this quilt’s website."
    static let inviteHelp = "They’re notified and join only if they accept."

    // MARK: Where a request notification goes

    /// `membership.request` links to `/patches/{slug}/members?status=pending`.
    /// The queue is an admin's; anybody else the link reaches (an admin who
    /// has since stepped down) is shown the roster, as before.
    static func requestsRoute(slug: String, standing: Standing?) -> NotificationRoute {
        runs(standing) ? .joinRequests(slug) : .members(slug)
    }
}

// MARK: - The calls

extension PatchworkAPI {
    /// A page of the members listing under one status — `pending` or
    /// `banned`, which the server honours only for the patch's admins.
    func members(slug: String, status: String, after: String? = nil, limit: Int = 20) async throws -> MemberPage {
        try await get("nodes/\(slug)/members", query: PatchAdmin.membersQuery(status: status, after: after, limit: limit))
    }
    /// How long a queue is: the listing's own count under that status, read
    /// from a page of one (the web Dashboard's way).
    func memberTotal(slug: String, status: String) async throws -> Int {
        try await members(slug: slug, status: status, limit: 1).memberCount ?? 0
    }
    func setMember(slug: String, userId: String, _ act: PatchAdmin.MemberAct) async throws {
        let _: AdminAnswer = try await patch("nodes/\(slug)/members/\(userId)", body: act.body)
    }
    /// Unpaged, newest first.
    func eventSubmissions(slug: String) async throws -> [EventSubmission] {
        let page: SubmissionPage = try await get("nodes/\(slug)/event-submissions")
        return page.items ?? []
    }
    func review(eventID: String, approve: Bool, note: String = "") async throws {
        let _: AdminAnswer = try await patch("events/\(eventID)/review", body: PatchAdmin.reviewBody(approve: approve, note: note))
    }
    func invite(slug: String, body: PatchAdmin.InviteBody) async throws {
        let _: AdminAnswer = try await post("nodes/\(slug)/invitations", body: body)
    }
    func rescindInvitation(slug: String, userId: String) async throws {
        try await deleteVoid("nodes/\(slug)/invitations/\(userId)")
    }
}
