// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct EventList: View {
    let quilt: Quilt
    var slug: String? = nil
    @State private var events: [PatchworkEvent] = []
    @State private var cursor: String?
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    var body: some View {
        List {
            Section {
                ForEach(events) { event in
                    NavigationLink { EventDetail(quilt: quilt, initial: event) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(event.title).font(.headline)
                            Text(event.dateLabel).font(.subheadline).foregroundStyle(.secondary)
                            if let name = event.nodeName { Label(name, systemImage: "square.grid.2x2").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 7)
                    }.accessibilityIdentifier("eventRow")
                }
            } header: { Text("Coming up") } footer: { Text("Times are shown in each event’s local time zone.") }
            if let cursor, !cursor.isEmpty {
                Button("Load more events") { Task { await load(after: cursor) } }.disabled(loading)
            }
            if loading { ProgressView("Loading events…") }
            if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Try again") { Task { await load(after: events.isEmpty ? nil : cursor) } }
                }
            }
        }
        .navigationTitle("Events")
        .overlay {
            if loaded && !loading && error == nil && events.isEmpty {
                ContentUnavailableView("No upcoming events", systemImage: "calendar", description: Text("Check back for the next gathering."))
            }
        }
        .task { if !loaded { await load() } }
        .refreshable { await load() }
    }
    private func load(after: String? = nil) async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false; loaded = true }
        do {
            let page = try await PatchworkAPI(base: quilt.url).events(slug: slug, after: after)
            if after == nil { events = page.items ?? [] }
            else {
                let ids = Set(events.map(\.id))
                events += (page.items ?? []).filter { !ids.contains($0.id) }
            }
            cursor = page.nextCursor
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct EventDetail: View {
    let quilt: Quilt
    let initial: PatchworkEvent
    @State private var detail: PatchworkEvent?
    @State private var error: String?
    private var event: PatchworkEvent { detail ?? initial }
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    var body: some View {
        List {
            Section {
                Text(event.title).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                if let name = event.nodeName { Text(name).font(.headline).foregroundStyle(.secondary) }
            }
            Section {
                Label(event.dateLabel, systemImage: "calendar")
                if let timezone = event.timezone { Text(timezone.replacingOccurrences(of: "_", with: " ")).font(.caption).foregroundStyle(.secondary) }
                if let location = event.location, !location.isEmpty { Label(location, systemImage: "mappin.and.ellipse") }
            }
            if let description = event.description, !description.isEmpty {
                Section("About this event") { Text(description).textSelection(.enabled) }
            }
            Section {
                if let raw = event.eventUrl, let url = URL(string: raw), url.scheme == "https" || url.scheme == "http" {
                    Link(destination: url) { Label("Event details at \(url.host() ?? "source")", systemImage: "arrow.up.right.square") }
                }
                Link("Open on quilt website", destination: api.webURL("events/\(event.id)"))
            }
            if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Reload event") { Task { await load() } }
                }
            }
        }
        .navigationTitle("Event").navigationBarTitleDisplayMode(.inline)
        .toolbar { ShareLink(item: api.webURL("events/\(event.id)")) }
        .task { await load() }
    }
    private func load() async {
        error = nil
        do { detail = try await api.get("events/\(initial.id)") }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
