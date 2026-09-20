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
struct PatchCalendar: View {
    let quilt: Quilt
    let patch: Patch
    var close: (() -> Void)? = nil
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
    var body: some View {
        List {
            Section {
                ForEach(upcoming) { row($0) }
                if let cursor = upcomingCursor, !cursor.isEmpty {
                    Button("Load more") { Task { await loadUpcoming(after: cursor) } }.disabled(loading)
                }
                if loaded && upcoming.isEmpty { Text("Nothing coming up.").foregroundStyle(.secondary) }
            } header: { Text("Upcoming") } footer: {
                if patch.communityListing && !upcoming.isEmpty {
                    // Every event on a patch nobody runs was put there by the
                    // community, derived from its status and said once.
                    Text("Community-submitted.")
                }
            }
            Section {
                if askedForEarlier {
                    ForEach(earlier) { row($0) }
                    if let cursor = earlierCursor, !cursor.isEmpty {
                        Button("Load more") { Task { await loadEarlier(after: cursor) } }.disabled(loading)
                    }
                    if !loading && earlier.isEmpty { Text("Nothing on the calendar before today.").foregroundStyle(.secondary) }
                } else {
                    Button("Show what already happened") { Task { await loadEarlier() } }
                        .accessibilityIdentifier("showEarlierEvents")
                }
            } header: { Text("Earlier") } footer: {
                if askedForEarlier { Text("Oldest first, from the beginning of this patch’s calendar.") }
            }
            if loading { ProgressView("Loading calendar…") }
            if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Try again") { Task { await loadUpcoming() } }
                }
            }
            Section {
                Text("Times are shown in each event’s local time zone.").font(Font.pw.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if feedsAvailable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Subscribe", systemImage: "calendar.badge.plus") { subscribing = true }
                        .accessibilityIdentifier("subscribeToCalendar")
                }
            }
            if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
        }
        .sheet(isPresented: $subscribing) {
            NavigationStack { SubscribeToPatch(api: api, slug: patch.slug, name: patch.name) }
                .presentationDetents([.medium, .large])
        }
        .task { if !loaded { await loadUpcoming() } }
        .refreshable { await loadUpcoming() }
    }
    private func row(_ event: PatchworkEvent) -> some View {
        NavigationLink { EventDetail(quilt: quilt, initial: event, close: close) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(event.title).font(Font.pw.headline)
                Text(event.dateLabel).font(Font.pw.subheadline).foregroundStyle(.secondary)
                if let location = event.location, !location.isEmpty {
                    Text(location).font(Font.pw.caption).foregroundStyle(.secondary).lineLimit(1)
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
    private var ics: URL { api.apiURL("nodes/\(slug)/events.ics") }
    private var rss: URL { api.apiURL("nodes/\(slug)/events.rss") }
    var body: some View {
        List {
            Section {
                if let subscription = api.subscriptionURL("nodes/\(slug)/events.ics") {
                    Link(destination: subscription) { Label("Add to Calendar", systemImage: "calendar.badge.plus") }
                        .accessibilityIdentifier("addToCalendar")
                }
                ShareLink(item: ics) { Label("Share the calendar address", systemImage: "square.and.arrow.up") }
            } header: { Text("Calendar (ICS)") }
              footer: { Text("Your calendar app keeps this patch’s events up to date once it has the address.") }
            Section {
                Link(destination: rss) { Label("Open the events feed", systemImage: "dot.radiowaves.up.forward") }
                ShareLink(item: rss) { Label("Share the feed address", systemImage: "square.and.arrow.up") }
            } header: { Text("RSS") }
              footer: { Text("New events from \(name) arrive in any feed reader.") }
        }
        .navigationTitle("Subscribe").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
