// SPDX-License-Identifier: MPL-2.0

import Foundation

// Posting an event to a patch, or suggesting one (web ADR 026).
//
// Whether an event publishes at once or waits for review is the server's
// decision, and the web's rule for predicting it is `eventPostingRight` in
// `web/src/lib/patchWorkspace.js`. It is ported here as a value with no view
// in it, so the door can say which of the two will happen before anybody
// fills the form — never find out on submit — and so the rule is checked
// in `EventPostingTests` case by case against the web's own.

enum EventPosting {
    /// What posting here would actually do. `none` draws no door at all.
    enum Right: Equatable {
        case none, direct, suggest

        /// The door's words, exactly as the web's patch bar and profile
        /// glimpse word it: the outcome, not the patch's state.
        var doorLabel: String? {
            switch self {
            case .none: return nil
            case .direct: return "New event"
            case .suggest: return "Suggest an event"
            }
        }
    }

    /// `eventPostingRight`, in the web's order. Every input is something the
    /// app already holds: the session, the membership index, the quilt's
    /// `instance`, and the `nodes/{slug}` envelope. The defaults are the
    /// web's defaults, so a call that leaves an input out means what the
    /// web's call leaving it out means.
    static func right(
        signedIn: Bool = false,
        isInstanceAdmin: Bool = false,
        viewerTrusted: Bool = false,
        isUnclaimed: Bool = false,
        isMemberOrAdmin: Bool = false,
        isBanned: Bool = false,
        submissionsEnabled: Bool = true,
        acceptSuggestions: Bool = false,
        hasMoved: Bool = false
    ) -> Right {
        if !signedIn || isBanned { return .none }
        if isInstanceAdmin { return .direct }
        // A patch that has moved takes no suggestions from outside (web ADR
        // 090); its own members and admins still post, because the old home
        // stays a record and a record can be corrected.
        if hasMoved && !isMemberOrAdmin { return .none }
        if isUnclaimed {
            if viewerTrusted { return .direct }
            return submissionsEnabled ? .suggest : .none
        }
        if isMemberOrAdmin { return .direct }
        if !submissionsEnabled { return .none }
        return acceptSuggestions ? .suggest : .none
    }

    /// A member or an admin — not a follower, and not a request nobody has
    /// answered. Following is frictionless and grants no write rights; the
    /// server's `userHasNodeRole(…, "member", "admin")` is the test.
    static func isMemberOrAdmin(_ standing: Standing?) -> Bool {
        standing == .active(.member) || standing == .active(.admin)
    }

    /// Where the door is, and what it opens.
    enum Door: Equatable {
        case none
        /// Nobody is signed in, and a stranger could suggest here: the door
        /// is the native sign-in sheet, the way the heart on a card is.
        case signIn
        case form(Right)

        var label: String? {
            switch self {
            case .none: return nil
            case .signIn: return Right.suggest.doorLabel
            case .form(let right): return right.doorLabel
            }
        }
    }

    /// The web draws no door for a signed-out reader. This client draws the
    /// one a stranger would get once signed in — a suggestion — and only
    /// where the patch would take one, so the sheet never leads to a form
    /// that then refuses. A reader who turns out to be a member finds "New
    /// event" in its place once the sheet has closed.
    static func door(signedIn: Bool, isInstanceAdmin: Bool, viewerTrusted: Bool, isUnclaimed: Bool,
                     standing: Standing?, isBanned: Bool, submissionsEnabled: Bool,
                     acceptSuggestions: Bool, hasMoved: Bool) -> Door {
        guard signedIn else {
            let stranger = right(signedIn: true, isUnclaimed: isUnclaimed, submissionsEnabled: submissionsEnabled,
                                 acceptSuggestions: acceptSuggestions, hasMoved: hasMoved)
            return stranger == .suggest ? .signIn : .none
        }
        let answer = right(signedIn: true, isInstanceAdmin: isInstanceAdmin, viewerTrusted: viewerTrusted,
                           isUnclaimed: isUnclaimed, isMemberOrAdmin: isMemberOrAdmin(standing), isBanned: isBanned,
                           submissionsEnabled: submissionsEnabled, acceptSuggestions: acceptSuggestions, hasMoved: hasMoved)
        return answer == .none ? .none : .form(answer)
    }

    /// Who reads a suggestion: the quilt's admins hold an unclaimed patch's
    /// calendar in trust, and a claimed patch's own admins hold theirs.
    static func reviewers(unclaimed: Bool) -> String {
        unclaimed ? "quilt admins" : "patch admins"
    }

    /// The zone the form's times are written in (web ADRs 045 and 067): the
    /// patch's own, else the quilt's, else the device's. An event inherits
    /// its patch's zone, so a new one is written in it.
    static func zone(patchZone: String?, quiltZone: String?) -> TimeZone {
        for name in [patchZone, quiltZone] {
            let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let zone = TimeZone(identifier: trimmed) { return zone }
        }
        return .current
    }

    /// Whether the times need saying out loud — the web's
    /// `sameZoneAsViewer`, inverted. Compared by name first; two names can
    /// still be one clock (New York and Detroit never disagree), so a
    /// mismatch falls through to what the two zones read at this moment.
    /// An organizer posting a show in their own city is not doing a
    /// conversion and does not need to be told about one.
    static func zoneDiffers(_ zone: TimeZone, from device: TimeZone = .current, at moment: Date = Date()) -> Bool {
        if zone.identifier == device.identifier { return false }
        return zone.secondsFromGMT(for: moment) != device.secondsFromGMT(for: moment)
            || zone.abbreviation(for: moment) != device.abbreviation(for: moment)
    }

    /// The line under the pickers, in the web's words.
    static func zoneNote(_ zone: TimeZone) -> String {
        "Times are in \(zone.identifier.replacingOccurrences(of: "_", with: " ")), this patch’s timezone."
    }

    /// The next whole hour on the patch's clock. A date picker opens on now,
    /// and now is already a minute in the past by the time the form is sent;
    /// the next hour is a start somebody might actually mean.
    static func defaultStart(now: Date = Date(), zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        let hour = calendar.date(from: parts) ?? now
        return calendar.date(byAdding: .hour, value: 1, to: hour) ?? now.addingTimeInterval(3600)
    }

    /// An instant the way the web's `toISOString()` writes it — UTC, to the
    /// millisecond — so an event posted here and one posted from a browser
    /// store the same shape. Seconds are dropped first: a picker shows
    /// minutes, and a start at 8:00:37 is nobody's 8pm.
    static func instant(_ date: Date) -> String {
        let minute = (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date(timeIntervalSinceReferenceDate: minute))
    }

    /// A refusal's sentence starts where a sentence starts: the server
    /// writes them lowercase for the web to place mid-toast.
    static func sentenceCased(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: The server's checks, before sending

    /// `validateImageRef` (`internal/handler/image_ref.go`), in the server's
    /// order and in its words. Lengths are bytes, as Go counts them.
    static func imageProblem(url rawURL: String, alt rawAlt: String) -> String? {
        let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let alt = rawAlt.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty { return nil }
        if url.utf8.count > 2048 { return "that image address is too long" }
        if alt.utf8.count > 300 { return "keep the description under 300 characters" }
        guard let parts = URLComponents(string: url), let host = parts.host, !host.isEmpty else {
            return "that doesn't look like an image address"
        }
        // https only: a TLS page pulling an http picture has it blocked as
        // mixed content, so an http flyer is one nobody will ever see.
        if parts.scheme?.lowercased() != "https" { return "the image address has to start with https://" }
        if alt.isEmpty { return "add a short description of the image, so it still says something if it fails to load" }
        return nil
    }

    /// `validateEventURL`: the event's own page on the web (web ADR 079).
    /// Unlike an image, plain http is fine — it is a link that works, and
    /// half the venues in a small scene still serve one.
    static func linkProblem(_ raw: String) -> String? {
        let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if link.isEmpty { return nil }
        if link.utf8.count > 2048 { return "that link is too long" }
        guard let parts = URLComponents(string: link), let host = parts.host, !host.isEmpty,
              let scheme = parts.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return "that doesn't look like a link — it should start with https://"
        }
        return nil
    }

    /// The one rule here the server does not state: an end is after its
    /// start, or it is not an end.
    static func endProblem(start: Date, end: Date?) -> String? {
        guard let end else { return nil }
        return end > start ? nil : "The end has to be after the start."
    }
}

// MARK: - The draft and what it sends

/// Who an event is for, within what the patch allows (web ADR 2026-09-19).
enum EventTier: String, CaseIterable, Identifiable {
    case `public`, followers, members
    var id: String { rawValue }
    /// The UI's words, matching the roles table and how charters read.
    var label: String {
        switch self {
        case .public: return "Public"
        case .followers: return "Followers"
        case .members: return "Members only"
        }
    }
    /// Where the patch's `follower_permissions.events` is off, the followers
    /// tier would be read down to members-only on every read path, so the
    /// form does not offer it.
    static func offered(followersAllowed: Bool) -> [EventTier] {
        followersAllowed ? allCases : [.public, .members]
    }
}

/// The body of `POST events`. A nil property is left out of the JSON
/// entirely: the server reads absence and an empty string alike for every
/// optional field here, and an absent `visibility` is what a suggestion
/// sends, because a suggestion is public whatever it asks for (web ADR 026).
/// No `timezone` field exists at all — an event inherits its patch's zone —
/// and no `recurrence`, which the server refuses.
struct EventBody: Encodable, Equatable {
    var nodeId: String
    var title: String
    var description: String?
    var location: String?
    var startsAt: String
    var endsAt: String?
    var eventUrl: String?
    var imageUrl: String?
    var imageAlt: String?
    var visibility: String?
    private enum CodingKeys: String, CodingKey {
        case nodeId = "node_id", title, description, location, startsAt = "starts_at", endsAt = "ends_at"
        case eventUrl = "event_url", imageUrl = "image_url", imageAlt = "image_alt", visibility
    }
}

/// The form's fields, held apart from the request until the act.
struct EventDraft: Equatable {
    var title = ""
    var description = ""
    var location = ""
    var eventURL = ""
    var imageURL = ""
    var imageAlt = ""
    var startsAt: Date
    var hasEnd = false
    var endsAt: Date
    var tier = EventTier.public

    init(start: Date) {
        startsAt = start
        endsAt = start.addingTimeInterval(2 * 3600)
    }

    var end: Date? { hasEnd ? endsAt : nil }
    /// The one thing the button waits for. The start always has a value.
    var ready: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// What the server would refuse, said before asking it: the image, then
    /// the link (the server's own order), the required title, then the end.
    func problem() -> String? {
        if let problem = EventPosting.imageProblem(url: imageURL, alt: imageAlt) { return problem }
        if let problem = EventPosting.linkProblem(eventURL) { return problem }
        if !ready { return "Title is required" }
        return EventPosting.endProblem(start: startsAt, end: end)
    }

    /// Fields trimmed, empties left out, the end only where there is one,
    /// and a tier only where the reader is posting directly.
    func body(nodeId: String, direct: Bool) -> EventBody {
        func value(_ text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let image = value(imageURL)
        return EventBody(
            nodeId: nodeId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: value(description),
            location: value(location),
            startsAt: EventPosting.instant(startsAt),
            endsAt: end.map(EventPosting.instant),
            eventUrl: value(eventURL),
            imageUrl: image,
            // A description with no picture left to describe goes nowhere:
            // the field that holds it is hidden once the address is cleared.
            imageAlt: image == nil ? nil : value(imageAlt),
            visibility: direct ? tier.rawValue : nil
        )
    }
}

extension PatchworkAPI {
    /// `POST events`. 201 answers with the event, whose `status` says which
    /// of the two it became: `active`, or `pending_review`.
    func createEvent(_ body: EventBody) async throws -> PatchworkEvent {
        try await post("events", body: body)
    }
}
