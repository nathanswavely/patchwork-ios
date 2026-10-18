// SPDX-License-Identifier: MPL-2.0
import SwiftUI

struct QuiltBrowser: View {
    @EnvironmentObject private var session: QuiltSession
    /// The door to Discover, which is not scoped: where My Quilt is empty,
    /// the whole quilt's question is the natural next place to look.
    var openDiscover: (() -> Void)? = nil
    /// The first launch's window onto the quilt: the canvas alone, with no
    /// bars and no corner switcher, under the welcome that QuiltHome lays on it.
    var firstLook = false
    @State private var mode = "Quilt"
    @State private var sort = PatchOrder.quilt
    @State private var filtering = false
    @State private var pending: Patch?
    /// How much of the canvas's foot the view switcher covers, padding and
    /// all, so the quilt's names can keep clear of it.
    @State private var pillHeight: CGFloat = 0
    /// Where the map was left, so a trip to the quilt and back does not
    /// re-frame it.
    @State private var mapMemory = MapMemory()
    private var filtered: [Patch] { session.filtered }
    /// The list reads the quilt (docs/adr/074): by default its order *is* the
    /// placement the canvas is drawing, so the two panes can never disagree.
    private var ordered: [Patch] { sort.sort(filtered, placement: session.tiles.map(\.id)) }
    private var narrowed: Bool { session.activeFilterCount > 0 }
    var body: some View {
        Group {
            if session.loading { ProgressView("Loading quilt…") }
            else if let error = session.error { FailureView(message: error) { Task { await session.load() } } }
            else if session.patches.isEmpty && session.scope == .my {
                // An empty My Quilt is not an empty quilt: the reader simply
                // holds nothing yet. It says which lens is on and offers the
                // two ways out of it.
                ContentUnavailableView {
                    Label("Nothing in My Quilt yet", systemImage: "heart")
                } description: {
                    Text("Patches you follow or join gather here.")
                } actions: {
                    showWholeQuilt
                    if let openDiscover {
                        Button("Find patches in Discover", action: openDiscover)
                            .font(Font.pw.subheadlineMedium)
                            .accessibilityIdentifier("myQuiltDiscover")
                    }
                }
                .accessibilityIdentifier("myQuiltEmpty")
                .background(Color.pwGround.ignoresSafeArea())
            } else if session.patches.isEmpty {
                // The web's two silences, kept distinct: an empty quilt is
                // nobody's mistake and offers no action but the one door out.
                ContentUnavailableView {
                    Label("No patches here yet", systemImage: "square.grid.2x2")
                } description: {
                    Text("No patches on this quilt so far.")
                } actions: { suggestLink }
                .background(Color.pwGround.ignoresSafeArea())
            } else if filtered.isEmpty && session.scope == .my {
                // Two lenses at once (web ADR 022): the empty result names
                // both, and each can be let go of on its own.
                ContentUnavailableView {
                    Label("No patches match your filter in My Quilt", systemImage: "line.3.horizontal.decrease")
                } description: {
                    Text("Nothing you follow or join matches your filter.")
                } actions: {
                    Button("Clear filter") { session.clearFilters() }
                    showWholeQuilt
                }
                .accessibilityIdentifier("myQuiltFilteredEmpty")
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
                QuiltCanvas(tiles: session.tiles, patches: filtered, tagMotifs: session.tagMotifs, colorMode: session.colorMode, footer: pillHeight) { open($0) }
                    .ignoresSafeArea()
            } else if mode == "Map" {
                QuiltMap(patches: filtered,
                         quiltHasLocations: session.patches.contains(where: \.isPlaced),
                         tagMotifs: session.tagMotifs,
                         colorMode: session.colorMode,
                         docked: session.docked?.id,
                         memory: mapMemory,
                         quiltID: session.quilt.id) { open($0) }
            } else {
                cards
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) { if !firstLook && !session.loading && session.error == nil && !session.patches.isEmpty && !session.searching { pill } }
        .navigationTitle(session.quilt.name).navigationBarTitleDisplayMode(.inline)
        // Over the canvas the bar paints nothing; the controls carry their own glass.
        .toolbarBackground(mode == "List" || session.searching ? .automatic : .hidden, for: .navigationBar)
        .modifier(NoEdgeEffect(active: mode != "List" && !session.searching))
        .modifier(DiscoveryToolbar(filter: $filtering))
        .toolbar(firstLook ? .hidden : .automatic, for: .navigationBar, .tabBar)
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
                    .tapTarget()
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

    /// Where the quilt says it takes suggestions, an empty list offers the
    /// form — behind the sign-in sheet for a reader without an account,
    /// because suggesting needs one.
    @ViewBuilder private var suggestLink: some View {
        if session.instance?.submissionsEnabled == true {
            SuggestPatchDoor { Text("Suggest a patch") }
                .accessibilityIdentifier("suggestPatch")
        }
    }

    /// The way back out of My Quilt, from wherever it came up empty.
    private var showWholeQuilt: some View {
        Button("Show the whole quilt") { session.scope = .whole }
            .accessibilityIdentifier("showWholeQuilt")
    }

    /// The view switcher waits in the bottom-right corner, just over the tab
    /// bar and in thumb reach, as one button wearing the current view.
    private var pill: some View {
        ViewSwitcher(mode: $mode, showsMap: session.mapEnabled) { pillHeight = $0 + 12 }
            .padding(.trailing, 16)
            .padding(.bottom, 12)
    }
}

/// Quilt · Map · List folded into one glass button. A tap unfolds the three
/// views upward in the same capsule; choosing one (or tapping anywhere
/// else) folds it back down to the chosen view's glyph.
private struct ViewSwitcher: View {
    @Binding var mode: String
    let showsMap: Bool
    /// The folded button's height, which is what the canvas keeps its names
    /// clear of. Opening is momentary, so the names do not move for it.
    var foldedHeight: (CGFloat) -> Void = { _ in }
    @State private var open = false
    private var views: [String] { showsMap ? ["Quilt", "Map", "List"] : ["Quilt", "List"] }
    private func glyph(_ view: String, filled: Bool) -> String {
        switch view {
        case "Map": filled ? "map.fill" : "map"
        case "List": "list.bullet"
        default: filled ? "square.grid.2x2.fill" : "square.grid.2x2"
        }
    }
    var body: some View {
        VStack(spacing: 4) {
            if open {
                ForEach(views, id: \.self) { view in
                    let chosen = mode == view
                    Button {
                        mode = view
                        open = false
                    } label: {
                        Image(systemName: glyph(view, filled: chosen))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(chosen ? Color.pwOnAccent : Color.pwText)
                            .frame(width: 44, height: 44)
                            .background { if chosen { Circle().fill(Color.accentColor) } }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(view)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                    .accessibilityIdentifier("view\(view)")
                    .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .bottom)))
                }
            } else {
                Button { open = true } label: {
                    Image(systemName: glyph(mode, filled: true))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.pwText)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View: \(mode)")
                .accessibilityHint("Shows Quilt, Map and List")
                .accessibilityIdentifier("viewSwitcher")
            }
        }
        .padding(4)
        .modifier(GlassCapsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .animation(.snappy(duration: 0.25), value: open)
        // While it is open, a tap anywhere else folds it without acting.
        .background(alignment: .bottomTrailing) {
            if open {
                Color.clear.contentShape(Rectangle())
                    .frame(width: 4000, height: 4000)
                    .onTapGesture { open = false }
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: mode) { open = false }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if !open { foldedHeight($0) } }
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
