// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// The form behind "New event" and "Suggest an event" (web `EventForm.svelte`,
// reached through `/events/new?node=slug`). The door has already said which
// of the two this will be, and the form says it again in its heading, so
// nobody fills in a suggestion believing it is a post.
//
// The same form edits an event (web `/events/:id/edit`): filled from the
// event, its patch stated rather than asked, its times on the event's own
// clock, and only what changed sent back (see `EventEditing`). Event links,
// the trust request, recurrence, the CSV upload, a map picker, a zone
// override and choosing or changing a patch from here are the website's.

// MARK: - The door, read off what the app holds

extension QuiltSession {
    /// The door for one patch: the posting rule's inputs, read from the
    /// session, the membership index, the quilt's `instance` and the patch's
    /// own `nodes/{slug}` envelope where it has been fetched.
    func eventDoor(for patch: Patch, envelope: PatchResponse?) -> EventPosting.Door {
        let standing = standing(for: patch.slug) ?? envelope?.standing ?? Standing.from(node: patch)
        return EventPosting.door(
            signedIn: me != nil,
            isInstanceAdmin: me?.role == "admin",
            viewerTrusted: envelope?.viewerTrusted == true,
            isUnclaimed: envelope?.isUnclaimed ?? patch.communityListing,
            standing: standing,
            isBanned: envelope?.banned ?? patch.isBanned ?? false,
            submissionsEnabled: instance?.submissionsEnabled ?? true,
            acceptSuggestions: patch.acceptEventSuggestions == true,
            hasMoved: patch.movedTo?.isEmpty == false
        )
    }

    /// The clock the form is written in: the patch's, else the quilt's.
    func eventZone(for patch: Patch) -> TimeZone {
        EventPosting.zone(patchZone: patch.timezone, quiltZone: instance?.geography.timezone)
    }

    /// The editing rule's inputs for one event, read from the same places
    /// the posting door reads them: `auth/me`'s role and the membership
    /// index, with the event's own detail for the rest.
    func editDoor(for event: PatchworkEvent) -> EventEditing.Door {
        guard let me else { return .none }
        return EventEditing.door(
            isInstanceAdmin: me.role == "admin",
            standing: event.nodeSlug.flatMap(standing(for:)),
            isCreator: event.createdBy == me.id,
            viewerTrusted: event.viewerTrusted == true,
            nodeStatus: event.nodeStatus,
            eventStatus: event.status,
            imported: event.imported
        )
    }

    func mayDelete(_ event: PatchworkEvent) -> Bool {
        guard let me else { return false }
        return EventEditing.mayDelete(isInstanceAdmin: me.role == "admin",
                                      standing: event.nodeSlug.flatMap(standing(for:)),
                                      isCreator: event.createdBy == me.id, imported: event.imported)
    }
}

/// The door as a toolbar button: a patch's calendar, in the bar at its foot.
/// Words and not a bare plus, because the words are the point — they say
/// whether this posts or suggests before anything is typed — and the top bar
/// already holds Subscribe and Done, where a label this long squeezed the
/// title and the system drew the icon alone.
struct EventDoorButton: View {
    let door: EventPosting.Door
    let open: () -> Void
    var body: some View {
        if let label = door.label {
            Button(action: open) {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(Font.pw.subheadlineSemibold)
                    Text(label).font(Font.pw.subheadlineSemibold)
                }
                .foregroundStyle(Color.pwText)
            }
            .accessibilityLabel(label)
            .accessibilityIdentifier("eventDoor")
        }
    }
}

/// The door as a row: under the events of the profile's glimpse. Ink with its
/// own glyph, because it is an act and not a place.
struct EventDoorRow: View {
    let door: EventPosting.Door
    let open: () -> Void
    var body: some View {
        if let label = door.label {
            Button(action: open) {
                Text(label).font(Font.pw.subheadlineMedium).inkAction("plus.circle")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("eventDoor")
        }
    }
}

// MARK: - The form

struct EventFormSheet: View {
    enum Mode {
        /// `.direct` or `.suggest` — which one the door promised.
        case new(Patch, EventPosting.Right)
        /// The event as the detail last read it, and the door an edit of it
        /// goes through.
        case edit(PatchworkEvent, EventEditing.Door)
    }
    let mode: Mode
    let unclaimed: Bool
    let zone: TimeZone
    /// The patch's `follower_permissions.events`: a ceiling on the tier.
    let followersAllowed: Bool
    /// New: a post that went straight onto the calendar, which the presenter
    /// opens once this sheet has gone. Edit: the event as the server now
    /// holds it, whichever door the edit went through.
    let onPosted: (PatchworkEvent) -> Void
    /// The event as it was opened, to send only what differs from it.
    private let original: EventDraft?

    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EventDraft
    @State private var busy = false
    @State private var failure: String?
    @State private var movedTo: URL?
    /// The server held it for review: the form is replaced by the web's card.
    @State private var submitted = false

    init(patch: Patch, right: EventPosting.Right, unclaimed: Bool, zone: TimeZone, followersAllowed: Bool,
         onPosted: @escaping (PatchworkEvent) -> Void) {
        mode = .new(patch, right)
        self.unclaimed = unclaimed
        self.zone = zone
        self.followersAllowed = followersAllowed
        self.onPosted = onPosted
        original = nil
        _draft = State(initialValue: EventDraft(start: EventPosting.defaultStart(zone: zone)))
    }

    /// The edit form. Its clock is the event's own (web ADRs 045 and 067),
    /// so an organizer on tour still reads the 8pm they are correcting.
    init(editing event: PatchworkEvent, door: EventEditing.Door, followersAllowed: Bool,
         onSaved: @escaping (PatchworkEvent) -> Void) {
        mode = .edit(event, door)
        unclaimed = event.communitySubmitted
        zone = event.zone
        self.followersAllowed = followersAllowed
        onPosted = onSaved
        let filled = EventDraft(editing: event)
        original = filled
        _draft = State(initialValue: filled)
    }

    private var editing: PatchworkEvent? { if case .edit(let event, _) = mode { return event } else { return nil } }
    private var direct: Bool {
        switch mode {
        case .new(_, let right): return right == .direct
        case .edit(_, let door): return door.offersTier
        }
    }
    /// The web keeps "Followers" on screen for an event that already says
    /// it, whatever the patch's switch says now: the switch is read, never
    /// written, so the row's own value stays choosable.
    private var tiers: [EventTier] {
        EventTier.offered(followersAllowed: followersAllowed || original?.tier == .followers)
    }
    private var changes: EventChanges? { original.map { draft.changes(from: $0, direct: direct) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if submitted { reviewCard } else { form }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.pwGround.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                if !submitted {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                }
            }
            // The act rides the foot of the sheet rather than the end of a
            // long scroll: the decision stays within reach, and a keyboard
            // cannot cover it (the join sheet learned this first).
            .safeAreaInset(edge: .bottom) { foot }
        }
        .interactiveDismissDisabled(busy)
        // Signed out from under the form — a 401 — there is nobody left to
        // post as, so the form goes the way Settings goes.
        .onChange(of: session.me == nil) { _, gone in if gone { dismiss() } }
    }

    // MARK: The fields, in the web's order

    @ViewBuilder private var form: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading)
                .font(Font.pw.displayTitle2).foregroundStyle(Color.pwText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("eventFormHeading")
            Text(sentence)
                .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("eventFormSentence")
        }
        if let note = editing?.recurrenceNote {
            // Nothing here repeats, and nothing here can make it: the word
            // an organizer once stored is told the truth and left alone.
            Label(note + ". Saving changes this date only.", systemImage: "arrow.triangle.2.circlepath")
                .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("eventFormRecurrence")
        }
        field("Title") {
            TextField("What’s happening?", text: $draft.title)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.next)
                .fieldStyle()
                .accessibilityIdentifier("eventTitle")
        }
        field("Description") {
            TextField("A few lines about it", text: $draft.description, axis: .vertical)
                .lineLimit(3...8)
                .fieldStyle()
                .accessibilityIdentifier("eventDescription")
        }
        // Only for somebody posting to their own patch: a suggestion is
        // public whatever it asks for, so a choice it cannot keep is not
        // offered at all.
        if direct { tierField }
        field("Location") {
            TextField("Where is this happening?", text: $draft.location)
                .textContentType(.fullStreetAddress)
                .fieldStyle()
                .accessibilityIdentifier("eventLocation")
        }
        field("Event page", hint: "Where to buy tickets or read more, if this event has a page somewhere else.") {
            TextField(text: $draft.eventURL, prompt: Text(verbatim: "https://…")) { Text("Event page") }
                .keyboardType(.URL).textContentType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .fieldStyle()
                .accessibilityIdentifier("eventURL")
        }
        field("Image address", hint: "Link a flyer or photo you already have online. Patchwork points at it and never keeps a copy.") {
            TextField(text: $draft.imageURL, prompt: Text(verbatim: "https://…")) { Text("Image address") }
                .keyboardType(.URL).textContentType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .fieldStyle()
                .accessibilityIdentifier("eventImageURL")
        }
        // Asked for only once there is something to describe: a
        // description beside an empty address is a field with no referent.
        if !draft.imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            field("Describe the image", hint: "Read aloud by screen readers, and shown if the image stops loading.") {
                TextField("Flyer for the March show", text: $draft.imageAlt)
                    .fieldStyle()
                    .accessibilityIdentifier("eventImageAlt")
            }
        }
        timeFields
        if let failure {
            VStack(alignment: .leading, spacing: 8) {
                Label { Text(failure).font(Font.pw.footnote) } icon: {
                    Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
                }
                .foregroundStyle(Color.pwText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("eventFormError")
                if let movedTo {
                    Link(destination: movedTo) {
                        Text("Go to its new home on \(movedTo.host() ?? movedTo.absoluteString)").font(Font.pw.subheadline)
                    }
                    .exitLink()
                    .accessibilityIdentifier("eventFormMovedTo")
                }
            }
        }
    }

    private var tierField: some View {
        field("Who can see this") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Who can see this", selection: $draft.tier) {
                    ForEach(tiers) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("eventTier")
                if !followersAllowed {
                    // The ceiling (web ADR 2026-09-19): said once, as a fact
                    // about where the reader is, and nothing greyed out.
                    Text("Followers can’t see this patch’s non-public events. That is set at the patch level, under Follower Permissions.")
                        .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("eventTierCeiling")
                }
            }
        }
    }

    /// The two times, written on the patch's clock rather than the reader's
    /// (web ADRs 045 and 067): 8pm is the fact on the flyer wherever the
    /// person typing it happens to be standing.
    private var timeFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("Starts") {
                DatePicker("Starts", selection: $draft.startsAt, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fieldStyle()
                    .accessibilityIdentifier("eventStarts")
            }
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $draft.hasEnd.animation()) { Text("Add an end time").font(Font.pw.body) }
                    .tint(Color.pwAccent)
                    .fieldStyle()
                    .accessibilityIdentifier("eventHasEnd")
                if draft.hasEnd {
                    DatePicker("Ends", selection: $draft.endsAt, in: draft.startsAt..., displayedComponents: [.date, .hourAndMinute])
                        .font(Font.pw.body)
                        .fieldStyle()
                        .accessibilityIdentifier("eventEnds")
                }
            }
            if EventPosting.zoneDiffers(zone) {
                Text(EventPosting.zoneNote(zone))
                    .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("eventZoneNote")
            }
        }
        .environment(\.timeZone, zone)
        .onChange(of: draft.hasEnd) { _, on in
            // An end offered on the start itself is an end nobody meant.
            if on && draft.endsAt <= draft.startsAt { draft.endsAt = draft.startsAt.addingTimeInterval(2 * 3600) }
        }
        .onChange(of: draft.startsAt) { old, new in
            // Moving the start carries the end with it, so the length the
            // organizer set survives a change of day.
            if draft.hasEnd { draft.endsAt = draft.endsAt.addingTimeInterval(new.timeIntervalSince(old)) }
        }
    }

    private func field<Content: View>(_ title: String, hint: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
            content()
            if let hint {
                Text(hint).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: The review card

    /// The web's "Submitted for review" card, in place of the form. A pending
    /// suggestion is on no list — only its submitter can open it — so this
    /// card is the whole acknowledgement, and nothing tries to show it
    /// anywhere else.
    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Submitted for review", systemImage: "clock.badge.questionmark")
                .font(Font.pw.title3).foregroundStyle(Color.pwText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("eventSubmittedHeading")
            Text("The \(EventPosting.reviewers(unclaimed: unclaimed)) will look at it. Your event will appear on the calendar once it’s approved.")
                .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("eventSubmittedSentence")
        }
        .cardSurface()
    }

    // MARK: The act

    private var foot: some View {
        Button {
            if submitted { dismiss() } else { submit() }
        } label: {
            Group {
                if busy { ProgressView().tint(Color.pwOnAccent) }
                else { Text(submitted ? "Done" : actLabel).font(Font.pw.headline) }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            // The app's root sets ink on everything; a filled control's
            // label is the design's white (DESIGN.md, primary-action). A
            // disabled one has no fill to be white on, so it is muted ink.
            .foregroundStyle(footEnabled ? Color.pwOnAccent : Color.pwTextMuted)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.pwAccent)
        .controlSize(.large)
        .disabled(!footEnabled)
        .accessibilityIdentifier(submitted ? "eventSubmittedDone" : "eventFormSubmit")
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    /// An edit waits for something to have changed, the way a system
    /// Save does: sending nothing is a 400 ("no valid fields to update").
    private var footEnabled: Bool { !busy && (submitted || (draft.ready && changes?.isEmpty != true)) }

    // MARK: The words, by mode

    private var heading: String {
        switch mode {
        case .new: return direct ? "New event" : "Suggest an event"
        case .edit: return "Edit event"
        }
    }
    private var sentence: String {
        switch mode {
        case .new(let patch, _):
            return direct
                ? "Add an event for \(patch.name). It appears as soon as you save it."
                : "Suggest an event for \(patch.name). It will be reviewed before it appears."
        case .edit(_, let door):
            // The web says nothing until the card; this says it before the
            // form is touched, the way the posting door does.
            return door == .reReview
                ? "Update your event details. Saving sends it back to the quilt admins, and it leaves the calendar until they approve it."
                : "Update your event details."
        }
    }
    private var actLabel: String {
        switch mode {
        case .new: return direct ? "Create event" : "Suggest event"
        case .edit: return "Save changes"
        }
    }

    private func submit() {
        guard !busy else { return }
        failure = nil
        movedTo = nil
        if let editing, let changes { return save(editing, changes) }
        guard case .new(let patch, _) = mode else { return }
        if let problem = draft.problem() {
            failure = EventPosting.sentenceCased(problem)
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                let event = try await session.api.createEvent(draft.body(nodeId: patch.id, direct: direct))
                // The server's answer decides the ending, not the door's
                // prediction: a grant or a membership can change between
                // the two, and the card must never promise a review that
                // is not happening.
                if event.awaitingReview {
                    withAnimation { submitted = true }
                } else {
                    onPosted(event)
                    dismiss()
                }
            } catch APIError.unauthenticated {
                session.signedOut()
            } catch {
                failure = EventPosting.sentenceCased(SignInModel.sentence(error))
                if let raw = (error as? APIError)?.movedTo, let url = URL(string: raw),
                   url.scheme == "https" || url.scheme == "http" {
                    movedTo = url
                }
            }
        }
    }

    /// `PATCH events/{id}` with what changed. The answer's status decides
    /// the ending, as a post's does: back in review is the web's card, and
    /// anything else is the event page, already showing the change.
    private func save(_ event: PatchworkEvent, _ changes: EventChanges) {
        if let problem = draft.editProblem(changes: changes) {
            failure = EventPosting.sentenceCased(problem)
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                let updated = try await session.api.updateEvent(id: event.id, changes)
                onPosted(updated)
                if updated.awaitingReview {
                    withAnimation { submitted = true }
                } else {
                    dismiss()
                }
            } catch APIError.unauthenticated {
                session.signedOut()
            } catch {
                failure = EventPosting.sentenceCased(ProposalDetailView.sentence(error, fallback: "Failed to update event"))
            }
        }
    }
}
