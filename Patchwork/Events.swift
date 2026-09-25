// SPDX-License-Identifier: MPL-2.0

import MapKit
import SwiftUI

/// The quilt's calendar: flat, soonest first, the way the web reads it. No
/// day headers — a gathering is one row among the next ones, and grouping
/// by day made a quiet week look like a wall of empty headings.
struct EventList: View {
    @EnvironmentObject private var session: QuiltSession
    let quilt: Quilt
    /// Set when this list is one patch's own calendar, which is also where
    /// the standing subscriptions belong.
    var slug: String? = nil
    var close: (() -> Void)? = nil
    @State private var events: [PatchworkEvent] = []
    @State private var cursor: String?
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    @State private var dates = EventDateFilter()
    @State private var pickingRange = false

    /// The quilt's own zone decides what "today" means. A reader on tour
    /// asking for tonight is asking about the quilt's night, not theirs.
    private var zone: TimeZone { TimeZone(identifier: session.instance?.geography.timezone ?? "") ?? .current }
    /// The tag chips and the search chip narrow the calendar through the
    /// host patch, as they do on the web: an event has no tags of its own.
    private var visiblePatchIDs: Set<String> {
        Set(session.patches.filter { QuiltLayout.matches($0, query: session.query, tags: session.tags) }.map(\.id))
    }
    private var visiblePatchSlugs: Set<String> {
        let ids = visiblePatchIDs
        return Set(session.patches.filter { ids.contains($0.id) }.map(\.slug))
    }
    private var filtered: [PatchworkEvent] {
        guard session.activeFilterCount > 0 else { return events }
        let ids = visiblePatchIDs, slugs = visiblePatchSlugs
        return events.filter { event in
            if let nodeId = event.nodeId { return ids.contains(nodeId) }
            if let nodeSlug = event.nodeSlug { return slugs.contains(nodeSlug) }
            return false
        }
    }
    private var forRange: String { dates.isActive ? " for this date range" : "" }

    var body: some View {
        List {
            // One Group so the rows take the card surface (see GroundedList).
            Group {
            Section {
                dateControl
            } footer: {
                Text("Times are shown in each event’s local time zone.")
            }
            Section {
                ForEach(filtered) { event in
                    NavigationLink { EventDetail(quilt: quilt, initial: event, close: close) } label: {
                        EventRow(event: event)
                    }.accessibilityIdentifier("eventRow")
                }
            } header: { Text("Coming up") }
            if let cursor, !cursor.isEmpty {
                Button("Load more events") { Task { await load(after: cursor) } }.disabled(loading)
            }
            if loading { ProgressView("Loading events…") }
            if let error {
                Section {
                    Text(error).foregroundStyle(Color.pwTextMuted)
                    Button("Try again") { Task { await load(after: events.isEmpty ? nil : cursor) } }
                }
            }
            }.listRows()
        }
        .groundedList()
        .navigationTitle("Events")
        .toolbar {
            if let slug { ToolbarItem(placement: .topBarTrailing) { SubscribeMenu(api: PatchworkAPI(base: quilt.url), slug: slug) } }
            if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
        }
        .overlay { emptyState }
        .sheet(isPresented: $pickingRange) { CustomRangeSheet(filter: $dates, timeZone: zone) }
        .task { if !loaded { await load() } }
        .onChange(of: dates) { _, _ in Task { await load() } }
        .refreshable { await load() }
    }

    /// One control, worded as the web words it, opened as a native menu: the
    /// presets with a checkmark on the live one, and the custom range behind
    /// its own step because two dates are not a menu item.
    private var dateControl: some View {
        Menu {
            Picker("Date", selection: presetBinding) {
                ForEach(EventDatePreset.offered) { Text($0.label).tag($0) }
            }
            Divider()
            Button("Custom range…") { pickingRange = true }
        } label: {
            HStack {
                // A menu is a control, and its label is still words: ink,
                // with the control's own glyph doing what the colour did.
                Label("Date", systemImage: "calendar").font(Font.pw.subheadlineMedium).foregroundStyle(Color.pwText)
                Spacer()
                Text(dates.label(timeZone: zone)).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                Image(systemName: "chevron.up.chevron.down").font(Font.pw.caption2).foregroundStyle(Color.pwTextMuted)
            }
        }
        .accessibilityIdentifier("dateFilter")
        .accessibilityLabel("Date filter")
        .accessibilityValue(dates.label(timeZone: zone))
    }
    private var presetBinding: Binding<EventDatePreset> {
        Binding(get: { dates.preset }, set: { dates = EventDateFilter(preset: $0) })
    }

    /// Two different silences. A filter that empties the list is standing
    /// state and says so, with the way out beside it; an empty calendar is
    /// nobody's mistake.
    @ViewBuilder private var emptyState: some View {
        if loaded && !loading && error == nil && filtered.isEmpty {
            if session.activeFilterCount > 0 {
                ContentUnavailableView {
                    Label("No events match your filter", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Nothing on this quilt matches what you picked\(forRange).")
                } actions: {
                    Button("Clear filter") { session.clearFilters() }
                        .font(Font.pw.headline).buttonStyle(.borderedProminent)
                }
                .accessibilityIdentifier("eventsFilteredEmpty")
            } else {
                ContentUnavailableView(
                    dates.isActive ? "No events in this range" : "No upcoming events",
                    systemImage: "calendar",
                    description: Text(dates.isActive ? "Try a wider date range." : "Check back for the next gathering.")
                )
                .accessibilityIdentifier("eventsEmpty")
            }
        }
    }

    private func load(after: String? = nil) async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false; loaded = true }
        let bounds = EventDateBounds.resolve(dates, timeZone: zone)
        do {
            let page = try await PatchworkAPI(base: quilt.url)
                .events(slug: slug, after: after, fromInstant: bounds.from, toInstant: bounds.to)
            if after == nil { events = page.items ?? [] }
            else {
                let ids = Set(events.map(\.id))
                events += (page.items ?? []).filter { !ids.contains($0.id) }
            }
            cursor = page.nextCursor
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

/// A row states the four facts a person scans for — when, what, where, and
/// whose — and wears a tier chip only where the event is not everyone's.
struct EventRow: View {
    let event: PatchworkEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // The date is the row's own emphasis, and emphasis is weight
            // here rather than colour: the tint means "you can press this".
            Text(event.shortDateLabel).font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwText)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(event.title).font(Font.pw.headline)
                EventTierChip(event: event)
            }
            if let location = event.location, !location.isEmpty {
                Text(location).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted).lineLimit(2)
            }
            if let name = event.nodeName {
                HStack(spacing: 6) {
                    Label(name, systemImage: "square.grid.2x2").font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    if event.communitySubmitted { EventBadge(text: "Community-submitted") }
                }
            }
        }.padding(.vertical, 5)
    }
}

/// What an event's visibility says, wherever an event is drawn. A public
/// event wears nothing: a chip on every row says nothing at all. Words, not
/// a glyph — "who can see this" is not something an icon says unambiguously.
struct EventTierChip: View {
    let event: PatchworkEvent
    var body: some View {
        if let label = event.tierLabel { EventBadge(text: label) }
    }
}

/// A quiet outlined pill. Status never wears a colour here; it wears words.
struct EventBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Font.pw.caption2Semibold)
            .foregroundStyle(Color.pwTextMuted)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Color.pwBorder))
    }
}

/// Two dates and an Apply, in the system's own pickers.
struct CustomRangeSheet: View {
    @Binding var filter: EventDateFilter
    let timeZone: TimeZone
    @Environment(\.dismiss) private var dismiss
    @State private var from = Date()
    @State private var to = Date()
    @State private var hasEnd = true
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $from, displayedComponents: .date)
                Toggle("Set an end date", isOn: $hasEnd)
                if hasEnd { DatePicker("To", selection: $to, in: from..., displayedComponents: .date) }
            }
            .navigationTitle("Custom range").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        filter = EventDateFilter(preset: .custom, customFrom: from, customTo: hasEnd ? to : nil)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            from = filter.customFrom ?? Date()
            to = filter.customTo ?? max(from, Date())
            hasEnd = filter.customTo != nil
        }
        .presentationDetents([.medium])
    }
}

/// A patch's standing calendar, for a reader who wants every night rather
/// than one. `webcal:` hands the subscription to Calendar; the RSS feed is
/// for everybody else's reader.
struct SubscribeMenu: View {
    let api: PatchworkAPI
    let slug: String
    @Environment(\.openURL) private var openURL
    var body: some View {
        Menu {
            if let webcal = api.subscriptionURL(slug: slug) {
                Button { openURL(webcal) } label: { Label("Subscribe in Calendar", systemImage: "calendar.badge.plus") }
            }
            ShareLink(item: api.feedURL(slug: slug)) { Label("RSS feed", systemImage: "dot.radiowaves.up.forward") }
        } label: {
            Label("Subscribe", systemImage: "square.and.arrow.down")
        }
        .accessibilityIdentifier("subscribeMenu")
    }
}

// MARK: - Detail

struct EventDetail: View {
    @EnvironmentObject private var session: QuiltSession
    let quilt: Quilt
    let initial: PatchworkEvent
    var close: (() -> Void)? = nil
    @State private var detail: PatchworkEvent?
    @State private var error: String?
    @State private var openingHost = false
    private var event: PatchworkEvent { detail ?? initial }
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    private var permalink: URL { api.webURL("events/\(event.id)") }
    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = event.latitude, let longitude = event.longitude else { return nil }
        guard latitude != 0 || longitude != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        List {
            // One Group so the rows take the card surface (see GroundedList).
            Group {
            if event.awaitingReview {
                Section {
                    Label("Awaiting review", systemImage: "clock.badge.questionmark").font(Font.pw.headline)
                    Text("The \(event.communitySubmitted ? "quilt admins" : "patch admins") will look at this event before it appears on the calendar.")
                        .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                }
            }
            Section {
                Text(event.title).font(Font.pw.largeTitle).fixedSize(horizontal: false, vertical: true)
                hostRow
                if !event.confirmedLinks.isEmpty || !(event.mentions ?? []).isEmpty { companions }
            }
            Section {
                Label(event.rangeLabel(), systemImage: "calendar")
                if let timezone = event.timezone {
                    Text(timezone.replacingOccurrences(of: "_", with: " ")).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                }
                if let note = event.recurrenceNote {
                    Label(note, systemImage: "arrow.triangle.2.circlepath").font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                }
                if let location = event.location, !location.isEmpty { Label(location, systemImage: "mappin.and.ellipse") }
            }
            if let coordinate { placeSection(coordinate) }
            if let flyer = event.flyerURL { flyerSection(flyer) }
            if let description = event.description, !description.isEmpty {
                Section("About this event") { Text(description).textSelection(.enabled) }
            }
            Section {
                // Nothing to add while a submission is still in the queue:
                // the endpoint 404s and there is no night to keep.
                if !event.awaitingReview { AddToCalendarMenu(event: event, permalink: permalink, api: api) }
                if let url = event.externalURL {
                    Link(destination: url) {
                        Label("Tickets & details on \(url.host()?.replacingOccurrences(of: "www.", with: "") ?? "the web")", systemImage: "arrow.up.right.square")
                    }.exitLink()
                }
                Link("Open on quilt website", destination: permalink).exitLink()
            }
            if let error {
                Section {
                    Text(error).foregroundStyle(Color.pwTextMuted)
                    Button("Reload event") { Task { await load() } }
                }
            }
            }.listRows()
        }
        .groundedList()
        .navigationTitle("Event").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ShareLink(item: permalink) }
            if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
        }
        .task { await load() }
    }

    /// "Hosted by X" is a door, not a caption: it opens the patch's own
    /// docked profile over whatever surface this event was reached from.
    @ViewBuilder private var hostRow: some View {
        if let name = event.nodeName {
            VStack(alignment: .leading, spacing: 6) {
                Button { Task { await openHost() } } label: {
                    HStack(spacing: 4) {
                        Text("Hosted by \(name)").font(Font.pw.headline)
                        if openingHost { ProgressView().controlSize(.mini) }
                        else { Image(systemName: "chevron.right").font(Font.pw.footnoteSemibold).foregroundStyle(Color(.tertiaryLabel)) }
                    }
                }
                .disabled(event.nodeSlug == nil || openingHost)
                .accessibilityIdentifier("eventHost")
                .accessibilityHint("Opens this patch’s profile")
                HStack(spacing: 6) {
                    if event.communitySubmitted { EventBadge(text: "Community-submitted") }
                    EventTierChip(event: event)
                }
            }
        }
    }

    /// "with X" — a settled handshake, and the cross-quilt mentions beside
    /// it, which are plain doorways to somebody else's quilt.
    private var companions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("with").font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
            FlowLayout(spacing: 8) {
                ForEach(event.confirmedLinks) { link in
                    Button {
                        if let slug = link.nodeSlug { Task { await open(slug: slug) } }
                    } label: {
                        Text(link.nodeName ?? link.nodeSlug ?? "A patch").font(Font.pw.subheadlineMedium)
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.gray)
                    .accessibilityIdentifier("eventLinkChip")
                }
                ForEach(event.mentions ?? []) { mention in
                    if let url = mention.url {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Text(mention.title)
                                Image(systemName: "arrow.up.right").font(Font.pw.caption2Semibold)
                                Text(mention.host).font(Font.pw.caption2).foregroundStyle(Color.pwTextMuted)
                            }.font(Font.pw.subheadlineMedium)
                        }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.gray)
                    }
                }
            }
        }.padding(.vertical, 2)
    }

    /// The flyer, held wherever the patch keeps it; nothing here proxies the
    /// bytes. `alt` is required where the flyer is set, so a host that stops
    /// serving the file leaves something to read rather than a blank card.
    @ViewBuilder private func flyerSection(_ flyer: URL) -> some View {
        Section {
            AsyncImage(url: flyer) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                        .accessibilityLabel(event.imageAlt ?? "Event flyer")
                case .empty:
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                default:
                    Label(event.imageAlt ?? "A flyer for this event, which its host is no longer serving.",
                          systemImage: "photo")
                        .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                        .padding(.vertical, 10)
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
    }

    /// Where it is, on a map that does not move: a still picture of the
    /// place, and the two things a person actually wants from it handed to
    /// Maps, which knows how to get them there.
    private func placeSection(_ coordinate: CLLocationCoordinate2D) -> some View {
        Section("Where") {
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)), interactionModes: []) {
                Marker(event.title, coordinate: coordinate)
            }
            .frame(height: 150)
            .listRowInsets(EdgeInsets())
            .accessibilityLabel("Map of \(event.location ?? event.title)")
            Button { mapItem(coordinate).openInMaps() } label: { Label("Open in Maps", systemImage: "map") }
            Button {
                mapItem(coordinate).openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
            } label: { Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") }
        }
    }
    private func mapItem(_ coordinate: CLLocationCoordinate2D) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = event.location?.isEmpty == false ? event.location : event.title
        return item
    }

    private func openHost() async {
        guard let slug = event.nodeSlug else { return }
        await open(slug: slug)
    }
    /// The patch the quilt already knows opens straight away; one it does
    /// not — a private patch, or a quilt whose tree this surface never
    /// loaded — is fetched by slug first, and then it is the same door.
    private func open(slug: String) async {
        if let known = session.patches.first(where: { $0.slug == slug }) {
            session.open(known)
            return
        }
        openingHost = true
        defer { openingHost = false }
        if let response: PatchResponse = try? await api.get("nodes/\(slug)") {
            session.open(response.node)
        } else {
            error = "That patch could not be opened from here."
        }
    }

    private func load() async {
        error = nil
        do { detail = try await api.get("events/\(initial.id)") }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
