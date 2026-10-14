// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// Events somebody suggested to a patch, waiting on its admins (web ADR 026,
// `PatchEvents.svelte`'s "Suggested events"). The web keeps the queue on the
// patch's events tab, so it is at the head of the patch's calendar here;
// the Dashboard's door opens the same section on a screen of its own.
//
// Approving publishes the suggestion as it is, and it is public: a
// suggestion is public from the moment it is made, and the review takes no
// tier. Declining deletes it outright and tells the person who suggested it,
// with the admin's note as the notification's body.

/// One patch's queue, shared by the calendar and the Dashboard's screen so
/// the two cannot act differently.
@MainActor final class SuggestionQueue: ObservableObject {
    @Published private(set) var items: [EventSubmission] = []
    @Published private(set) var loaded = false
    @Published var outcome: AdminOutcome?
    /// The one being declined, whose sheet is up.
    @Published var declining: EventSubmission?

    func load(api: PatchworkAPI, slug: String) async {
        do { items = try await api.eventSubmissions(slug: slug) }
        catch { /* A queue that cannot be read is not drawn; the calendar is still the calendar. */ }
        loaded = true
    }

    /// Off the list at once, back with the quilt's sentence on a refusal.
    /// An approval also tells every event list to read again, because the
    /// night is on the calendar now.
    func review(_ submission: EventSubmission, approve: Bool, note: String = "", session: QuiltSession) async {
        guard let index = items.firstIndex(of: submission) else { return }
        withAnimation { _ = items.remove(at: index) }
        outcome = nil
        do {
            try await session.api.review(eventID: submission.id, approve: approve, note: note)
            let done = approve ? "Event approved" : "Suggestion declined"
            outcome = AdminOutcome(text: done)
            UIAccessibility.post(notification: .announcement, argument: done)
            if approve { session.eventsChanged() }
            session.adminChanged()
        } catch {
            if case APIError.unauthenticated = error { session.signedOut() }
            withAnimation { items.insert(submission, at: min(index, items.count)) }
            outcome = AdminOutcome(text: ProposalDetailView.sentence(error, fallback: "Failed to review"), refused: true)
        }
    }
}

/// The queue as a section of a list: a card per suggestion with enough to
/// decide on — when, where, what, and who — and the title as a door to the
/// event's own page for the rest.
struct SuggestedEventsSection: View {
    @EnvironmentObject private var session: QuiltSession
    @ObservedObject var queue: SuggestionQueue
    /// The patch's own zone: the rows arrive with theirs blank.
    let zone: TimeZone
    let open: (PatchworkEvent) -> Void

    var body: some View {
        if let outcome = queue.outcome {
            Section { AdminOutcomeLine(outcome: outcome, id: "suggestionsOutcome") }
        }
        if !queue.items.isEmpty {
            Section {
                ForEach(queue.items) { row($0) }
            } header: {
                Text("Suggested events").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
                    .accessibilityIdentifier("suggestedEventsHeading")
            } footer: {
                Text(PatchAdmin.approvedTier).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted).textCase(nil)
            }
        }
    }

    private func row(_ submission: EventSubmission) -> some View {
        let event = submission.event
        return VStack(alignment: .leading, spacing: 6) {
            Button { open(event.inZone(zone)) } label: {
                Text(event.title).font(Font.pw.headline).multilineTextAlignment(.leading).inkRow(fills: false)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityHint("Opens the event")
            .accessibilityIdentifier("suggestionOpen-\(event.id)")
            let line = PatchAdmin.submissionLine(event, zone: zone)
            if !line.isEmpty { Text(line).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted) }
            if let description = event.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                Text(description).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted).lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Suggested by \(submission.submitter)").font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
            HStack(spacing: 16) {
                Button { Task { await queue.review(submission, approve: true, session: session) } } label: {
                    Text("Approve").font(Font.pw.subheadlineSemibold).foregroundStyle(.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.pwAccent)
                .controlSize(.small)
                .accessibilityLabel("Approve \(event.title)")
                .accessibilityIdentifier("suggestionApprove-\(event.id)")
                Button { queue.declining = submission } label: {
                    Text("Decline").font(Font.pw.subheadline).foregroundStyle(Color.pwText)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Decline \(event.title)")
                .accessibilityIdentifier("suggestionDecline-\(event.id)")
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

/// The web's inline decline form as a sheet, which is also the confirmation:
/// it says the suggestion is deleted and who is told, and offers the note
/// that goes to them.
struct DeclineSuggestionSheet: View {
    let submission: EventSubmission
    let decline: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Decline this suggestion?")
                            .font(Font.pw.displayTitle2).foregroundStyle(Color.pwText)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("declineHeading")
                        Text("“\(submission.event.title)”, suggested by \(submission.submitter).")
                            .font(Font.pw.body).foregroundStyle(Color.pwText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(PatchAdmin.declineConsequence)
                            .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    TextField("Note to the submitter (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                        .fieldStyle()
                        .accessibilityIdentifier("declineNote")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.pwGround.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button(role: .destructive) {
                    decline(note)
                    dismiss()
                } label: {
                    Text("Decline").font(Font.pw.headline).frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(.systemRed))
                .controlSize(.large)
                .accessibilityIdentifier("declineConfirm")
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension View {
    /// The decline sheet for a queue, hung once on the screen that shows it.
    func decliningSuggestions(_ queue: SuggestionQueue, session: QuiltSession) -> some View {
        modifier(DecliningSuggestions(queue: queue, session: session))
    }
}

private struct DecliningSuggestions: ViewModifier {
    @ObservedObject var queue: SuggestionQueue
    let session: QuiltSession
    func body(content: Content) -> some View {
        content.sheet(item: $queue.declining) { submission in
            DeclineSuggestionSheet(submission: submission) { note in
                Task { await queue.review(submission, approve: false, note: note, session: session) }
            }
        }
    }
}

/// The Dashboard's door: one patch's suggestions on a screen of their own.
struct SuggestedEventsView: View {
    @EnvironmentObject private var session: QuiltSession
    let slug: String
    @StateObject private var queue = SuggestionQueue()
    @State private var node: Patch?
    @State private var opened: PatchworkEvent?

    private var zone: TimeZone {
        if let node { return session.eventZone(for: node) }
        return EventPosting.zone(patchZone: nil, quiltZone: session.instance?.geography.timezone)
    }
    private var reviews: Bool {
        PatchAdmin.reviews(standing: session.standing(for: slug), isInstanceAdmin: session.me?.role == "admin")
    }

    var body: some View {
        List {
            Group {
                if reviews {
                    SuggestedEventsSection(queue: queue, zone: zone) { opened = $0 }
                } else {
                    Section { WebsiteOnlyNote(text: "Only this patch’s admins review suggested events.") }
                }
            }
            .listRows()
        }
        .groundedList()
        .navigationTitle("Suggested events").navigationBarTitleDisplayMode(.inline)
        .overlay {
            if reviews && queue.loaded && queue.items.isEmpty {
                ContentUnavailableView("No suggested events.", systemImage: "calendar.badge.checkmark")
                    .accessibilityIdentifier("suggestionsEmpty")
            } else if reviews && !queue.loaded {
                ProgressView()
            }
        }
        .navigationDestination(item: $opened) { EventDetail(quilt: session.quilt, initial: $0) }
        .decliningSuggestions(queue, session: session)
        .task {
            if node == nil {
                node = session.patches.first { $0.slug == slug }
                if let answer: PatchResponse = try? await session.api.get("nodes/\(slug)") { node = answer.node }
            }
            if reviews && !queue.loaded { await queue.load(api: session.api, slug: slug) }
        }
        .refreshable { await queue.load(api: session.api, slug: slug) }
    }
}
