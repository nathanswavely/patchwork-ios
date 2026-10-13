// SPDX-License-Identifier: MPL-2.0

import Foundation

// Editing an event, and deleting one (web `EventDetail.svelte` and the edit
// mode of `EventForm.svelte`).
//
// The server sends no `may_edit` with an event: the web works the answer out
// on the client from who the reader is and where they stand, and so does
// this. The rule is the server's `UpdateEvent` (it decides which of three
// doors an edit goes through) and lives here as a value with no view in it,
// so the detail screen offers Edit only where saving would be accepted, and
// so `EventEditingTests` can hold it to the server branch by branch.

enum EventEditing {
    /// What saving an edit would do, or `none` where it would be refused.
    enum Door: Equatable {
        case none
        /// Whoever may post here directly edits directly: every field,
        /// the tier included, and the status untouched.
        case direct
        /// The reader's own suggestion, still waiting: free to edit, still
        /// waiting afterwards, and public whatever it asks for.
        case pending
        /// The reader's own event on a patch nobody runs, without trust:
        /// saving puts it back in the queue for the quilt admins.
        case reReview

        /// The tier is a choice only through the direct door. Anybody else
        /// sending anything but `public` is refused, so it is not offered.
        var offersTier: Bool { self == .direct }
    }

    /// `UpdateEvent`'s rule, in its own order. The inputs are what the app
    /// already holds: `auth/me`'s role, the membership index's standing for
    /// the event's patch, and the event as `GET events/{id}` states it —
    /// its creator, `node_status`, `status`, `source_id` and `viewer_trusted`.
    ///
    /// The web's button is drawn by a looser test (a creator who is a member
    /// sees Edit whatever the patch's status); where the two disagree this
    /// follows the server, because a button that only leads to a 403 is the
    /// thing the rule exists to avoid.
    static func door(isInstanceAdmin: Bool, standing: Standing?, isCreator: Bool, viewerTrusted: Bool,
                     nodeStatus: String?, eventStatus: String?, imported: Bool) -> Door {
        // The source is authoritative (web ADR 031): an imported event is
        // changed in its own calendar, by everyone, admins included.
        if imported { return .none }
        // A patch a list never said the status of is an ordinary one.
        let active = (nodeStatus ?? "active") == "active"
        let unclaimed = nodeStatus == "unclaimed"
        if isInstanceAdmin { return .direct }
        if active && standing == .active(.admin) { return .direct }
        guard isCreator else { return .none }
        // A member's reach stops at what they made, and only while they are
        // still a member: a creator who has left keeps Delete, not Edit.
        if active && standing == .active(.member) { return .direct }
        if unclaimed && viewerTrusted { return .direct }
        if eventStatus == "pending_review" { return .pending }
        if unclaimed { return .reReview }
        // A suggestion adopted onto an active patch belongs to the patch
        // (web ADR 026): its outside submitter keeps no edit.
        return .none
    }

    /// `DeleteEvent`: the instance admin, the patch's admins, and the
    /// event's own creator, always — removing your own contribution is free,
    /// pending or published, and even after the patch adopted it. That is
    /// broader than the web, which draws no Delete for an adopted
    /// suggestion's submitter; the server allows it, so this does.
    ///
    /// An imported event is the one exception: deleting it skip-lists the
    /// feed item so the next sync does not bring it back, which is the
    /// feed's managers' call, and the web offers it to them alone.
    static func mayDelete(isInstanceAdmin: Bool, standing: Standing?, isCreator: Bool, imported: Bool) -> Bool {
        if isInstanceAdmin || standing == .active(.admin) { return true }
        if imported { return false }
        return isCreator
    }

    /// The act's word, as the web words it: a suggestion still waiting is
    /// withdrawn, and anything else is deleted. There is no "cancel" — the
    /// quilt has no cancelled status, and a show that is off is deleted.
    static func deleteLabel(pending: Bool) -> String { pending ? "Withdraw" : "Delete" }

    /// The confirmation's question. The web asks "Are you sure?"; a native
    /// dialog's title says what is about to happen instead.
    static func deleteQuestion(pending: Bool) -> String {
        pending ? "Withdraw this suggestion?" : "Delete this event?"
    }

    /// What the act leaves behind, said once. Nobody is told about a
    /// deletion (web ADR 093), and the organizer should hear that before
    /// they rely on the quilt to tell anybody the night is off.
    static func deleteMessage(pending: Bool) -> String {
        pending
            ? "It leaves the review queue, and nobody will see it."
            : "It comes off the calendar for everyone. Nobody is notified."
    }

    /// The web's toast after the act.
    static func deletedLine(pending: Bool) -> String { pending ? "Submission withdrawn" : "Event deleted" }
}

// MARK: - What an edit sends

/// The body of `PATCH events/{id}`: only the keys that changed. The server
/// writes every key present and leaves every absent one alone, so a key is
/// left out to mean "unchanged", `""` clears a text field, and `ends_at`
/// is cleared with `null`. The web cannot clear a description, a location
/// or an end at all — it sends an empty field as `undefined` — and this is
/// the deliberate improvement on it.
///
/// No `timezone` (the form has no zone control, and a key left out keeps
/// whatever the event holds), no `recurrence` (the server refuses any new
/// word, and this form offers no way to retire an old one), and no
/// `node_id`, which the server ignores: an event cannot move patches.
struct EventChanges: Encodable, Equatable {
    var title: String?
    var description: String?
    var location: String?
    var startsAt: String?
    /// Absent (`nil`), set (`.some(instant)`), or cleared (`.some(nil)`,
    /// sent as JSON `null`).
    var endsAt: String??
    var eventUrl: String?
    var imageUrl: String?
    var imageAlt: String?
    var visibility: String?

    var isEmpty: Bool { self == EventChanges() }

    private enum CodingKeys: String, CodingKey {
        case title, description, location, startsAt = "starts_at", endsAt = "ends_at"
        case eventUrl = "event_url", imageUrl = "image_url", imageAlt = "image_alt", visibility
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(startsAt, forKey: .startsAt)
        if let endsAt {
            if let end = endsAt { try container.encode(end, forKey: .endsAt) } else { try container.encodeNil(forKey: .endsAt) }
        }
        try container.encodeIfPresent(eventUrl, forKey: .eventUrl)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encodeIfPresent(imageAlt, forKey: .imageAlt)
        try container.encodeIfPresent(visibility, forKey: .visibility)
    }
}

extension EventDraft {
    /// The form filled from the event as it stands, its times read on its
    /// own clock by the picker the form is drawn in. An event with no start
    /// the app can read opens on the next whole hour, which is a change.
    init(editing event: PatchworkEvent) {
        self.init(start: event.date ?? EventPosting.defaultStart(zone: event.zone))
        title = event.title
        description = event.description ?? ""
        location = event.location ?? ""
        eventURL = event.eventUrl ?? ""
        imageURL = event.imageUrl ?? ""
        imageAlt = event.imageAlt ?? ""
        if let end = event.endDate {
            hasEnd = true
            endsAt = end
        }
        tier = event.visibility.flatMap(EventTier.init(rawValue:)) ?? .public
    }

    /// The image as it would be stored: a description goes with its picture,
    /// so clearing the address clears the description too.
    private var storedImage: (url: String, alt: String) {
        let url = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return (url, url.isEmpty ? "" : imageAlt.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// What differs from the event as it was opened, trimmed the way a new
    /// event is. The tier is compared only where the reader may choose it.
    func changes(from original: EventDraft, direct: Bool) -> EventChanges {
        func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        func changed(_ now: String, _ was: String) -> String? { trimmed(now) == trimmed(was) ? nil : trimmed(now) }
        var body = EventChanges()
        body.title = changed(title, original.title)
        body.description = changed(description, original.description)
        body.location = changed(location, original.location)
        body.eventUrl = changed(eventURL, original.eventURL)
        let start = EventPosting.instant(startsAt)
        if start != EventPosting.instant(original.startsAt) { body.startsAt = start }
        let end = self.end.map(EventPosting.instant), wasEnd = original.end.map(EventPosting.instant)
        if end != wasEnd { body.endsAt = .some(end) }
        let image = storedImage, wasImage = original.storedImage
        if image.url != wasImage.url { body.imageUrl = image.url }
        if image.alt != wasImage.alt { body.imageAlt = image.alt }
        if direct && tier != original.tier { body.visibility = tier.rawValue }
        return body
    }

    /// What the server would refuse or does not check, said before asking:
    /// the image pair and the link only where the edit touches them (an old
    /// event's stored flyer is not this edit's business), then the required
    /// title and an end after the start, in the create form's words.
    func editProblem(changes: EventChanges) -> String? {
        if changes.imageUrl != nil || changes.imageAlt != nil,
           let problem = EventPosting.imageProblem(url: imageURL, alt: storedImage.alt) { return problem }
        if changes.eventUrl != nil, let problem = EventPosting.linkProblem(eventURL) { return problem }
        if !ready { return "Title is required" }
        return EventPosting.endProblem(start: startsAt, end: end)
    }
}

extension PatchworkAPI {
    /// `PATCH events/{id}`. 200 answers with the bare event — no patch name,
    /// slug or links — whose `status` says whether the edit went back into
    /// review; the detail reads the rest again.
    func updateEvent(id: String, _ changes: EventChanges) async throws -> PatchworkEvent {
        try await patch("events/\(id)", body: changes)
    }

    /// `DELETE events/{id}`: the row is gone, not marked.
    func deleteEvent(id: String) async throws {
        try await deleteVoid("events/\(id)")
    }
}
