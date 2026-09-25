// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import MapKit

struct QuiltBrowser: View {
    @EnvironmentObject private var session: QuiltSession
    @State private var mode = "Quilt"
    @State private var sort = PatchOrder.quilt
    @State private var filtering = false
    @State private var pending: Patch?
    private var filtered: [Patch] { session.filtered }
    /// The list reads the quilt (docs/adr/074): by default its order *is* the
    /// placement the canvas is drawing, so the two panes can never disagree.
    private var ordered: [Patch] { sort.sort(filtered, placement: session.tiles.map(\.id)) }
    private var narrowed: Bool { session.activeFilterCount > 0 }
    private var located: [Patch] { filtered.filter { guard let lat = $0.latitude, let lon = $0.longitude else { return false }; return (-90...90).contains(lat) && (-180...180).contains(lon) } }
    var body: some View {
        Group {
            if session.loading { ProgressView("Loading quilt…") }
            else if let error = session.error { FailureView(message: error) { Task { await session.load() } } }
            else if session.patches.isEmpty {
                // The web's two silences, kept distinct: an empty quilt is
                // nobody's mistake and offers no action but the one door out.
                ContentUnavailableView {
                    Label("No patches here yet", systemImage: "square.grid.2x2")
                } description: {
                    Text("No patches on this quilt so far.")
                } actions: { suggestLink }
                .background(Color.pwGround.ignoresSafeArea())
            } else if filtered.isEmpty {
                ContentUnavailableView {
                    Label("No patches match your filter", systemImage: "line.3.horizontal.decrease")
                } description: {
                    Text("Nothing on this quilt matches your filter.")
                } actions: {
                    Button("Clear filter") { session.clearFilters() }
                    suggestLink
                }
                .background(Color.pwGround.ignoresSafeArea())
            } else if mode == "Quilt" {
                QuiltCanvas(tiles: session.tiles, patches: filtered, tagMotifs: session.tagMotifs, colorMode: session.colorMode) { open($0) }
                    .ignoresSafeArea()
            } else if mode == "Map" {
                if located.isEmpty { ContentUnavailableView("No locations to show", systemImage: "map", description: Text("These patches haven’t shared map coordinates.")) }
                else {
                    Map {
                        ForEach(located) { patch in
                            Annotation(patch.name, coordinate: CLLocationCoordinate2D(latitude: patch.latitude!, longitude: patch.longitude!)) {
                                Button { open(patch) } label: { Image(systemName: "mappin.circle.fill").font(Font.pw.title).padding(6).background(.background, in: Circle()) }.accessibilityLabel(patch.name)
                            }
                        }
                    }.id(session.query + session.tags.sorted().joined(separator: ",")).ignoresSafeArea()
                }
            } else {
                cards
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
    /// The list, as the web's cards pane reads it (docs/adr/074, docs/adr/078):
    /// a header that names what is on screen and how it is ordered, then the
    /// patches as cards on the quilt's own ground. A grouped `List` was the
    /// wrong instrument — a patch is a thing that could move to another
    /// surface, which is what a card is for, and a chevroned system row said
    /// "setting" where the web says "patch".
    private var cards: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                header
                ForEach(ordered) { patch in
                    PatchCard(patch: patch,
                              tagMotifs: session.tagMotifs,
                              colorMode: session.colorMode) { open(patch) }
                }
                // The web carries a footer strip on every page; here it is one
                // quiet row at the end of the reading surfaces.
                QuiltInfoFooter().padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.pwGround.ignoresSafeArea())
        .refreshable { await session.load() }
        .safeAreaPadding(.bottom, 64)
    }

    /// "Patches", how many there are, and the order menu — the list's own
    /// controls and nothing else. The Quilt/Map/List switch belongs to the
    /// canvas, which is the thing it changes.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            // The screen saying its own name: the one display moment on this
            // surface, in the hand-lettered face the web reserves for exactly
            // that (app.css `--font-display`).
            Text("Patches").font(Font.pw.displayTitle2).foregroundStyle(Color.pwText)
            Text(countLabel).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
            Spacer(minLength: 8)
            Menu {
                Picker("Order", selection: $sort) {
                    ForEach(PatchOrder.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                    .font(Font.pw.subheadline)
                    .labelStyle(.titleAndIcon)
                    // The order is a menu, not a link: ink, with the control's
                    // own glyph doing the work the colour used to.
                    .foregroundStyle(Color.pwText)
            }
            .accessibilityIdentifier("patchOrder")
        }
        .padding(.bottom, 2)
    }

    /// The web's own two forms: a plain count, and — where the quilt has been
    /// narrowed — how many of how many, so the filter's work is visible.
    private var countLabel: String {
        narrowed ? "\(filtered.count) of \(session.patches.count)" : "\(filtered.count) results"
    }

    /// Where the quilt says it takes suggestions, an empty list offers the one
    /// link to the website's form. There is no native form: suggesting a patch
    /// needs an account.
    @ViewBuilder private var suggestLink: some View {
        if session.instance?.submissionsEnabled == true {
            Link("Suggest a patch", destination: session.api.webURL("submit"))
                .exitLink(fills: false)
                .accessibilityIdentifier("suggestPatch")
        }
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

/// The system fades content under the bar as it scrolls beneath; over the
/// quilt that fade is a band, so it is off and the canvas runs to the edge.
private struct NoEdgeEffect: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.scrollEdgeEffectHidden(active, for: .all) } else { content }
    }
}
