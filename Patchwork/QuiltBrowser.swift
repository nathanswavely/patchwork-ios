// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import MapKit

struct QuiltBrowser: View {
    @EnvironmentObject private var session: QuiltSession
    @State private var mode = "Quilt"
    @State private var sort = "Quilt order"
    @State private var filtering = false
    @State private var pending: Patch?
    private var filtered: [Patch] { session.filtered }
    private var ordered: [Patch] {
        if sort == "Name" { return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
        if sort == "Newest" { return filtered.sorted { ($0.activatedAt ?? $0.createdAt ?? "") > ($1.activatedAt ?? $1.createdAt ?? "") } }
        let lookup = Dictionary(uniqueKeysWithValues: filtered.map { ($0.id, $0) })
        return session.tiles.compactMap { lookup[$0.id] }
    }
    private var located: [Patch] { filtered.filter { guard let lat = $0.latitude, let lon = $0.longitude else { return false }; return (-90...90).contains(lat) && (-180...180).contains(lon) } }
    var body: some View {
        Group {
            if session.loading { ProgressView("Loading quilt…") }
            else if let error = session.error { FailureView(message: error) { Task { await session.load() } } }
            else if session.patches.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "square.grid.2x2", description: Text("No patches on this quilt so far."))
            } else if filtered.isEmpty {
                ContentUnavailableView {
                    Label("No patches match", systemImage: "line.3.horizontal.decrease")
                } description: { Text("Nothing on this quilt matches your filters.") } actions: { Button("Clear filters") { session.clearFilters() } }
            } else if mode == "Quilt" {
                QuiltCanvas(tiles: session.tiles, patches: filtered, tagMotifs: session.tagMotifs, colorMode: session.colorMode) { open($0) }
                    .ignoresSafeArea()
            } else if mode == "Map" {
                if located.isEmpty { ContentUnavailableView("No locations to show", systemImage: "map", description: Text("These patches haven’t shared map coordinates.")) }
                else {
                    Map {
                        ForEach(located) { patch in
                            Annotation(patch.name, coordinate: CLLocationCoordinate2D(latitude: patch.latitude!, longitude: patch.longitude!)) {
                                Button { open(patch) } label: { Image(systemName: "mappin.circle.fill").font(.title).padding(6).background(.background, in: Circle()) }.accessibilityLabel(patch.name)
                            }
                        }
                    }.id(session.query + session.tags.sorted().joined(separator: ",")).ignoresSafeArea()
                }
            } else {
                List {
                    Section {
                        Picker("Order", selection: $sort) { ForEach(["Quilt order", "Name", "Newest"], id: \.self) { Text($0) } }
                        ForEach(ordered) { patch in
                            Button { open(patch) } label: { PatchRow(patch: patch) }.accessibilityIdentifier("patchRow")
                        }
                    } header: {
                        Text("\(filtered.count) of \(session.patches.count) patches")
                    } footer: {
                        // The web carries a footer strip on every page; here it
                        // is one quiet row at the end of the reading surfaces.
                        QuiltInfoFooter()
                    }
                }
                .refreshable { await session.load() }
                .safeAreaPadding(.bottom, 64)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { if !session.loading && session.error == nil && !session.patches.isEmpty && !session.searching { pill } }
        .navigationTitle(session.quilt.name).navigationBarTitleDisplayMode(.inline)
        // Over the canvas the bar paints nothing; the controls carry their own glass.
        .toolbarBackground(mode == "List" || session.searching ? .automatic : .hidden, for: .navigationBar)
        .modifier(NoEdgeEffect(active: mode != "List" && !session.searching))
        .modifier(DiscoveryToolbar(filter: $filtering))
        .sheet(isPresented: $filtering, onDismiss: { if let patch = pending { pending = nil; session.open(patch) } }) { FilterSheet() }
    }
    /// One temporary overlay at a time: a tap on the surface behind the filter
    /// sheet closes the sheet first, then docks the patch.
    private func open(_ patch: Patch) {
        if filtering { pending = patch; filtering = false } else { session.open(patch) }
    }
    /// The view switcher rides the foot of the canvas, in thumb reach.
    private var pill: some View {
        Picker("View", selection: $mode) {
            Text("Quilt").tag("Quilt")
            if session.mapEnabled { Text("Map").tag("Map") }
            Text("List").tag("List")
        }
        .pickerStyle(.segmented).frame(width: session.mapEnabled ? 240 : 170)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(4).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .padding(.bottom, 12)
    }
}

struct PatchRow: View {
    let patch: Patch
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(patch.name).font(.headline).foregroundStyle(Color.primary)
            if let description = patch.description, !description.isEmpty { Text(description).font(.subheadline).foregroundStyle(Color.secondary).lineLimit(2) }
            Text(patch.countsLabel).font(.caption).foregroundStyle(Color.secondary)
        }.padding(.vertical, 6)
    }
}

/// The system fades content under the bar as it scrolls beneath; over the
/// quilt that fade is a band, so it is off and the canvas runs to the edge.
private struct NoEdgeEffect: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.scrollEdgeEffectHidden(active, for: .all) } else { content }
    }
}
