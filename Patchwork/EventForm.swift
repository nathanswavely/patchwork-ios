// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// The form behind "New event" and "Suggest an event" (web `EventForm.svelte`,
// reached through `/events/new?node=slug`). The door has already said which
// of the two this will be, and the form says it again in its heading, so
// nobody fills in a suggestion believing it is a post. Editing, deleting,
// event links, the trust request, recurrence, the CSV upload, a map picker
// and choosing a patch from here are the website's.

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
    let patch: Patch
    /// `.direct` or `.suggest` — which one the door promised.
    let right: EventPosting.Right
    let unclaimed: Bool
    let zone: TimeZone
    /// The patch's `follower_permissions.events`: a ceiling on the tier.
    let followersAllowed: Bool
    /// A post that went straight onto the calendar. The presenter opens it
    /// once this sheet has gone.
    let onPosted: (PatchworkEvent) -> Void

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
        self.patch = patch
        self.right = right
        self.unclaimed = unclaimed
        self.zone = zone
        self.followersAllowed = followersAllowed
        self.onPosted = onPosted
        _draft = State(initialValue: EventDraft(start: EventPosting.defaultStart(zone: zone)))
    }

    private var direct: Bool { right == .direct }

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
            Text(direct ? "New event" : "Suggest an event")
                .font(Font.pw.displayTitle2).foregroundStyle(Color.pwText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("eventFormHeading")
            Text(direct
                 ? "Add an event for \(patch.name). It appears as soon as you save it."
                 : "Suggest an event for \(patch.name). It will be reviewed before it appears.")
                .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("eventFormSentence")
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
                    ForEach(EventTier.offered(followersAllowed: followersAllowed)) { Text($0.label).tag($0) }
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
                if busy { ProgressView().tint(.white) }
                else { Text(submitted ? "Done" : (direct ? "Create event" : "Suggest event")).font(Font.pw.headline) }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            // The app's root sets ink on everything; a filled control's
            // label is the design's white (DESIGN.md, primary-action). A
            // disabled one has no fill to be white on, so it is muted ink.
            .foregroundStyle(footEnabled ? Color.white : Color.pwTextMuted)
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

    private var footEnabled: Bool { !busy && (submitted || draft.ready) }

    private func submit() {
        guard !busy else { return }
        failure = nil
        movedTo = nil
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
}
