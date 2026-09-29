// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// A patch's whole calendar, which is the room the profile's Events glimpse
/// is a glimpse of.
///
/// The whole calendar is `include_past=true` — the glimpse is bounded by
/// `from=now` so a section headed Upcoming can only hold what is, and this
/// screen is where that bound is deliberately dropped. It is dropped in two
/// halves rather than one, because the server orders events oldest first and
/// pages forward: asking a venue with three hundred past shows for "all of
/// it" hands back last spring and nothing about tonight. So Upcoming is
/// fetched on open, and what already happened is a second, explicit request
/// that a reader makes when they want it.
///
/// Subscribing is the one thing a signed-out reader can genuinely do with a
/// calendar, and the feeds exist only for a public patch (web ADR 031), so
/// the affordance appears only when the patch says `visibility == "public"`.
///
/// The calendar is also where an event is added (web `PatchEvents.svelte`):
/// "New event" for a member or an admin, "Suggest an event" for anybody the
/// patch would take one from, as a button in the bar. Which of the two is
/// read off the patch's own `nodes/{slug}` answer, fetched here, because the
/// door has to say what posting will do before the form is filled.
struct PatchCalendar: View {
    @EnvironmentObject private var session: QuiltSession
    let quilt: Quilt
    let patch: Patch
    var close: (() -> Void)? = nil
    /// The patch as `nodes/{slug}` states it to this reader, with the
    /// envelope's trust and ban beside it.
    @State private var envelope: PatchResponse?
    @State private var composing = false
    @State private var signingIn = false
    /// A post the form handed back, waiting for the form to leave before it
    /// is opened; and the one opened.
    @State private var posted: PatchworkEvent?
    @State private var opened: PatchworkEvent?
    @State private var upcoming: [PatchworkEvent] = []
    @State private var upcomingCursor: String?
    @State private var earlier: [PatchworkEvent] = []
    @State private var earlierCursor: String?
    @State private var askedForEarlier = false
    @State private var loading = false
    @State private var loaded = false
    @State private var subscribing = false
    @State private var error: String?
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    private var feedsAvailable: Bool { patch.visibility == "public" }
    private var node: Patch { envelope?.node ?? patch }
    /// Only on the quilt the reader is signed in to: a calendar read from
    /// anywhere else is somebody else's quilt, and no act crosses to it.
    private var door: EventPosting.Door {
        guard quilt.url == session.quilt.url else { return .none }
        return session.eventDoor(for: node, envelope: envelope)
    }
    var body: some View {
        List {
            // One Group so every section's rows take the card surface: the
            // modifier does not reach them from the List itself.
            Group {
            Section {
                ForEach(upcoming) { row($0) }
                if let cursor = upcomingCursor, !cursor.isEmpty {
                    Button("Load more") { Task { await loadUpcoming(after: cursor) } }
                        .font(Font.pw.subheadlineMedium).inkAction("arrow.down.circle").disabled(loading)
                }
                if loaded && upcoming.isEmpty {
                    Text("Nothing coming up.").font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                }
            } header: { heading("Upcoming") } footer: {
                if patch.communityListing && !upcoming.isEmpty {
                    // Every event on a patch nobody runs was put there by the
                    // community, derived from its status and said once.
                    footnote("Community-submitted.")
                }
            }
            Section {
                if askedForEarlier {
                    ForEach(earlier) { row($0) }
                    if let cursor = earlierCursor, !cursor.isEmpty {
                        Button("Load more") { Task { await loadEarlier(after: cursor) } }
                            .font(Font.pw.subheadlineMedium).inkAction("arrow.down.circle").disabled(loading)
                    }
                    if !loading && earlier.isEmpty {
                        Text("Nothing on the calendar before today.").font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                    }
                } else {
                    Button("Show what already happened") { Task { await loadEarlier() } }
                        .font(Font.pw.subheadlineMedium)
                        .accessibilityIdentifier("showEarlierEvents")
                        .inkAction("clock.arrow.circlepath")
                }
            } header: { heading("Earlier") } footer: {
                if askedForEarlier { footnote("Oldest first, from the beginning of this patch’s calendar.") }
            }
            if loading { ProgressView("Loading calendar…") }
            if let error {
                Section {
                    Text(error).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    Button("Try again") { Task { await loadUpcoming() } }
                        .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
                }
            }
            Section {
                Text("Times are shown in each event’s local time zone.").font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
            }
            }.listRows()
        }
        .groundedList()
        .navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if feedsAvailable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Subscribe", systemImage: "calendar.badge.plus") { subscribing = true }
                        .accessibilityIdentifier("subscribeToCalendar")
                }
            }
            if door != .none {
                ToolbarItem(placement: .bottomBar) {
                    EventDoorButton(door: door) { if door == .signIn { signingIn = true } else { composing = true } }
                }
            }
            if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
        }
        .sheet(isPresented: $subscribing) {
            NavigationStack { SubscribeToPatch(api: api, slug: patch.slug, name: patch.name) }
                .presentationDetents([.medium, .large])
        }
        // The post opens once the form has gone, from here — a push onto
        // this calendar's own stack, so Back is the calendar with the new
        // night already in it.
        .sheet(isPresented: $composing, onDismiss: { if let posted { opened = posted; self.posted = nil } }) {
            if case .form(let right) = door {
                EventFormSheet(patch: node, right: right, unclaimed: envelope?.isUnclaimed ?? node.communityListing,
                               zone: session.eventZone(for: node),
                               followersAllowed: node.followerPermissions?.events != false) { event in
                    posted = event
                    Task { await loadUpcoming() }
                }
            }
        }
        .signInGate($signingIn)
        .navigationDestination(item: $opened) { EventDetail(quilt: quilt, initial: $0, close: close) }
        .task {
            if !loaded { await loadUpcoming() }
            await loadNode()
        }
        // Signing in through the door changes who is asking: the envelope's
        // trust and standing are read again for the new reader.
        .onChange(of: session.me?.id) { _, _ in Task { await loadNode() } }
        .refreshable { await loadUpcoming() }
    }
    private func loadNode() async {
        guard quilt.url == session.quilt.url else { return }
        if let answer: PatchResponse = try? await api.get("nodes/\(patch.slug)") { envelope = answer }
    }
    private func heading(_ text: String) -> some View {
        Text(text).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
    }
    private func footnote(_ text: String) -> some View {
        Text(text).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted).textCase(nil)
    }
    private func row(_ event: PatchworkEvent) -> some View {
        NavigationLink { EventDetail(quilt: quilt, initial: event, close: close) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(event.title).font(Font.pw.headline).foregroundStyle(Color.pwText)
                Text(event.dateLabel).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                if let location = event.location, !location.isEmpty {
                    Text(location).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted).lineLimit(1)
                }
            }.padding(.vertical, 5)
        }.accessibilityIdentifier("calendarRow")
    }
    private func loadUpcoming(after: String? = nil) async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false; loaded = true }
        do {
            let page = try await api.events(slug: patch.slug, after: after, limit: 100, from: Date())
            upcoming = merge(after == nil ? [] : upcoming, page.items ?? [])
            upcomingCursor = page.nextCursor
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func loadEarlier(after: String? = nil) async {
        guard !loading else { return }
        loading = true; error = nil; askedForEarlier = true
        defer { loading = false }
        do {
            let page = try await api.events(slug: patch.slug, after: after, limit: 100, to: Date(), includePast: true)
            earlier = merge(after == nil ? [] : earlier, page.items ?? [])
            earlierCursor = page.nextCursor
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func merge(_ existing: [PatchworkEvent], _ incoming: [PatchworkEvent]) -> [PatchworkEvent] {
        let known = Set(existing.map(\.id))
        return existing + incoming.filter { !known.contains($0.id) }
    }
}

/// The two public feeds a patch's calendar publishes. Nothing here signs
/// anyone in: a calendar address is handed to the reader's own calendar app,
/// and the RSS one to their own reader.
struct SubscribeToPatch: View {
    let api: PatchworkAPI
    let slug: String
    let name: String
    @Environment(\.dismiss) private var dismiss
    private func heading(_ text: String) -> some View {
        Text(text).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
    }
    private func footnote(_ text: String) -> some View {
        Text(text).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted).textCase(nil)
    }
    private var ics: URL { api.apiURL("nodes/\(slug)/events.ics") }
    private var rss: URL { api.apiURL("nodes/\(slug)/events.rss") }
    var body: some View {
        List {
            Group {
            Section {
                if let subscription = api.subscriptionURL("nodes/\(slug)/events.ics") {
                    Link(destination: subscription) { Label("Add to Calendar", systemImage: "calendar.badge.plus") }
                        .accessibilityIdentifier("addToCalendar")
                        .exitLink()
                }
                // A share sheet is the system's own control and keeps the
                // platform's chrome; only the words that leave are ink.
                ShareLink(item: ics) { Label("Share the calendar address", systemImage: "square.and.arrow.up") }
                    .foregroundStyle(Color.pwText)
            } header: { heading("Calendar (ICS)") }
              footer: { footnote("Your calendar app keeps this patch’s events up to date once it has the address.") }
            Section {
                Link(destination: rss) { Label("Open the events feed", systemImage: "dot.radiowaves.up.forward") }.exitLink()
                ShareLink(item: rss) { Label("Share the feed address", systemImage: "square.and.arrow.up") }
                    .foregroundStyle(Color.pwText)
            } header: { heading("RSS") }
              footer: { footnote("New events from \(name) arrive in any feed reader.") }
            }.listRows()
        }
        .groundedList()
        .navigationTitle("Subscribe").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
