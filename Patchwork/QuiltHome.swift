// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import UIKit

struct QuiltHome: View {
    @StateObject private var session: QuiltSession
    @State private var pane = Pane.quilt
    /// Where the reader was before Search, which is where the X takes them.
    @State private var lastPane = Pane.quilt
    /// The filter sheet over the Events tab; the quilt's own lives in QuiltBrowser.
    @State private var eventFiltering = false
    /// The reader's colour register, read here so a change to it reaches the
    /// session — and through it the canvas — wherever the sheet was opened from.
    @AppStorage(DisplayDefaults.colorsKey) private var colors = ColorMode.standard.rawValue
    /// The full quilt picker, reached from the switcher card's "Find a quilt".
    /// The card closes first and the picker opens once it has gone (see the
    /// switcher's `onDismiss`); `wantsPicker` is the note passed between them.
    @State private var finding = false
    @State private var wantsPicker = false
    /// The one-time orientation card, over the foot of the quilt (see Orientation.swift).
    @State private var intro = false
    /// Read here, where there is exactly one of them. The unread poll belongs
    /// to the session, and this is the one view that can tell it whether
    /// anybody is looking: the discovery toolbar is on four surfaces at once
    /// and would have started four polls.
    @Environment(\.scenePhase) private var scenePhase
    enum Pane: Hashable { case quilt, events, discover, dashboard, search }
    init(quilt: Quilt) { _session = StateObject(wrappedValue: QuiltSession(quilt: quilt)) }
    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                TabView(selection: $pane) {
                    Tab(value: Pane.quilt) { quiltPane } label: { quiltLabel }
                    Tab("Events", systemImage: "calendar", value: Pane.events) { eventsPane }
                    Tab("Discover", systemImage: "safari", value: Pane.discover) { discoverPane }
                    // There is no Dashboard until there is an account to dash:
                    // the tab arrives with the session and leaves with it.
                    if session.me != nil {
                        Tab("Dashboard", systemImage: "rectangle.stack", value: Pane.dashboard) { dashboardPane }
                    }
                    // A plain tab, not a search-role one: the system lays a
                    // search-role tab out as its own magnifier pill once it has
                    // been selected, which split the bar and read as a lost
                    // item. This app has its own field in the top bar and uses
                    // none of the search role's behaviour, so the tab stays in
                    // line with the other four (see onChange).
                    Tab("Search", systemImage: "magnifyingglass", value: Pane.search) { searchPane }
                }
            } else {
                TabView(selection: $pane) {
                    quiltPane.tabItem { quiltLabel }.tag(Pane.quilt)
                    eventsPane.tabItem { Label("Events", systemImage: "calendar") }.tag(Pane.events)
                    discoverPane.tabItem { Label("Discover", systemImage: "safari") }.tag(Pane.discover)
                    if session.me != nil {
                        dashboardPane.tabItem { Label("Dashboard", systemImage: "rectangle.stack") }.tag(Pane.dashboard)
                    }
                    searchPane.tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(Pane.search)
                }
            }
        }
        .onChange(of: pane) { was, now in
            // Search is a place: choosing it keeps the pill selected while the
            // field is live rather than bouncing the selection back, which
            // slid the indicator across the bar. Where the reader came from is
            // kept for the way back; choosing another tab ends the search.
            if now == .search { session.searching = true }
            else { lastPane = now; if was == .search { session.endSearch() } }
        }
        .onChange(of: session.searching) { _, now in
            if !now, pane == .search { pane = lastPane }
        }
        // Letting go of the account takes its tab with it, so the selection
        // has to come home rather than point at a place that is gone.
        .onChange(of: session.me) { _, now in if now == nil, pane == .dashboard { pane = .quilt } }
        // Hold the quilt's tab to switch lens or quilt, the way a profile tab switches accounts.
        .background(TabBarLongPress(item: 0) { session.switching = true })
        .sheet(item: $session.docked) { patch in PatchSheet(initial: patch) }
        .sheet(isPresented: $session.switching, onDismiss: {
            if wantsPicker { wantsPicker = false; finding = true }
        }) {
            QuiltSwitcher { wantsPicker = true; session.switching = false }
        }
        .sheet(isPresented: $finding) { NavigationStack { QuiltPicker(neighbors: session.instance?.neighborQuilts ?? []) } }
        // Said once, on the quilt the reader is left on, after Settings has gone.
        .alert("Your account has been deleted.", isPresented: $session.farewell) {
            Button("OK", role: .cancel) {}
        }
        .task { await session.load() }
        .onAppear {
            session.apply(colorMode: ColorMode(rawValue: colors) ?? .standard)
            if !IntroState.seen(session.quilt) { intro = true }
        }
        .onChange(of: colors) { _, now in session.apply(colorMode: ColorMode(rawValue: now) ?? .standard) }
        // Coming back to the app reads the count again and restarts the
        // reconciliation; leaving it stops.
        .onChange(of: scenePhase) { _, now in session.scenePhaseChanged(to: now) }
        .environmentObject(session)
    }
    /// The search tab's own page: the ground the results overlay draws on,
    /// wearing the same top bar as every other surface so the field lands in
    /// it, focused.
    private var searchPane: some View {
        NavigationStack { Color.pwGround.ignoresSafeArea().modifier(DiscoveryToolbar()) }
    }
    /// The quilt, with the orientation card over the foot of it. The overlay
    /// goes on the tab's own content rather than on the `TabView`, so the
    /// card floats inside the canvas instead of underneath the tab bar; the
    /// padding clears the canvas's own Quilt/Map/List pill, because the card
    /// may cover the quilt but never a control.
    private var quiltPane: some View {
        NavigationStack { QuiltBrowser(openDiscover: { pane = .discover }) }
            .overlay(alignment: .bottom) {
                if intro, !session.searching {
                    IntroCard(quiltName: session.instance?.name ?? session.quilt.name) {
                        IntroState.markSeen(session.quilt)
                        withAnimation { intro = false }
                    }
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
    }
    /// The calendar narrows through the host patch, so it wears the quilt's
    /// Filter too: the same sheet, the same state the canvas reads.
    private var eventsPane: some View {
        NavigationStack {
            EventList(quilt: session.quilt)
                .modifier(DiscoveryToolbar(filter: $eventFiltering))
                .sheet(isPresented: $eventFiltering) { FilterSheet() }
        }
    }
    private var discoverPane: some View { NavigationStack { Discover() } }
    private var dashboardPane: some View {
        NavigationStack { Dashboard(openDiscover: { pane = .discover }) }
    }
    /// The tab says which lens is on, so a reader in My Quilt can see it from
    /// every other tab too. The identifier is the stable handle; the words
    /// are what change.
    private var quiltLabel: some View {
        Label { Text(session.scope == .my ? "My Quilt" : "Quilt") } icon: { quiltIcon }
            .accessibilityIdentifier("quiltTab")
    }
    @ViewBuilder private var quiltIcon: some View {
        if let icon = session.tabIcon, let dim = session.tabIconDim { Image(uiImage: pane == .quilt ? icon : dim).renderingMode(.original) }
        else { Image(systemName: pane == .quilt ? "square.grid.2x2.fill" : "square.grid.2x2") }
    }
}

/// The one top bar on every discovery surface: filter where the surface
/// narrows, the live search field in the middle, and the account menu —
/// which gives way to Cancel while the field is in use.
struct DiscoveryToolbar: ViewModifier {
    @EnvironmentObject private var session: QuiltSession
    var filter: Binding<Bool>? = nil
    @State private var about = false
    @State private var display = false
    @State private var signIn = false
    @State private var notifications = false
    @State private var settings = false
    /// How the reader left Settings, acted on once the sheet has gone.
    @State private var settingsExit: SettingsExit?
    @FocusState private var focused: Bool
    private var fieldWidth: CGFloat { min(420, max(200, UIScreen.main.bounds.width - (session.searching ? 108 : 150))) }
    func body(content: Content) -> some View {
        content
            .overlay { if session.searching { SearchResults() } }
            .toolbar {
                if let filter, !session.searching {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { filter.wrappedValue = true } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                                .overlay(alignment: .topTrailing) {
                                    if session.activeFilterCount > 0 {
                                        Text("\(session.activeFilterCount)").font(Font.pw.caption2Semibold).foregroundStyle(Color(.systemBackground))
                                            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                                            .background(Color.pwAccent, in: Capsule()).offset(x: 10, y: -8)
                                    }
                                }
                        }
                        .accessibilityLabel("Filter")
                        .accessibilityValue(session.activeFilterCount > 0 ? "\(session.activeFilterCount) active" : "")
                    }
                }
                ToolbarItem(placement: .principal) { field }
                ToolbarItem(placement: .topBarTrailing) {
                    if session.searching {
                        Button { session.endSearch() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Cancel search")
                            .accessibilityIdentifier("cancelSearch")
                    } else {
                        Menu {
                            // Signing in is native now. Joining a patch,
                            // following and posting are still the website's.
                            if let me = session.me {
                                Button {} label: {
                                    Text(me.title)
                                    Text(me.handle)
                                }
                                .disabled(true)
                                // A menu row's label is its title alone, so
                                // the handle under it would be drawn and never
                                // spoken. Both, in one sentence.
                                .accessibilityLabel("Signed in as \(me.title), \(me.handle)")
                                .accessibilityIdentifier("accountMe")
                                // The bell lives under the account rather than
                                // beside it: a second bar button squeezed the
                                // field, and what it opens is the account's.
                                Button { notifications = true } label: {
                                    Text("Notifications")
                                    if session.unread > 0 { Text("\(UnreadTally.badge(session.unread)) unread") }
                                    Image(systemName: session.unread > 0 ? "bell.badge" : "bell")
                                }
                                .accessibilityLabel("Notifications, \(session.unread) unread")
                                .accessibilityIdentifier("notificationBell")
                                // The account's own settings, between what
                                // the account hears and letting go of it.
                                Button { settings = true } label: { Label("Settings", systemImage: "gearshape") }
                                    .accessibilityIdentifier("accountSettings")
                                Button { Task { await session.signOut() } } label: {
                                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                                }
                            } else {
                                Button { signIn = true } label: { Label("Sign in", systemImage: "person.badge.key") }
                            }
                            Divider()
                            Button { about = true } label: { Label("About this quilt", systemImage: "info.circle") }
                            Button { display = true } label: { Label("Display", systemImage: "slider.horizontal.3") }
                            Button { session.switching = true } label: { Label("Switch quilt", systemImage: "square.grid.2x2") }
                        } label: {
                            // The unread count rides the account glyph, hung
                            // inside a padded frame so the capsule cannot clip
                            // it; the padding is unconditional so the glyph
                            // does not shift when the count arrives.
                            Image(systemName: "person.crop.circle")
                                .padding(.top, 6).padding(.trailing, 7)
                                .overlay(alignment: .topTrailing) {
                                    if session.unread > 0 {
                                        Text(UnreadTally.badge(session.unread))
                                            .font(Font.pw.caption2Semibold).foregroundStyle(Color(.systemBackground))
                                            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                                            .background(Color.pwAccent, in: Capsule())
                                    }
                                }
                                .padding(.bottom, 6).padding(.leading, 7)
                        }
                        .accessibilityLabel(session.me == nil ? "Account" : "Account, \(session.unread) unread")
                        .accessibilityIdentifier("Account")
                    }
                }
            }
            .onChange(of: session.searching) { _, now in focused = now }
            .sheet(isPresented: $about) { QuiltInfoSheet() }
            .sheet(isPresented: $display) { DisplaySheet() }
            .sheet(isPresented: $signIn) {
                SignInSheet(api: session.api, quiltName: session.instance?.name ?? session.quilt.name) { user in
                    session.signedIn(user)
                }
            }
            .sheet(isPresented: $notifications) { NotificationsSheet() }
            .sheet(isPresented: $settings, onDismiss: leaveSettings) {
                SettingsSheet { exit in settingsExit = exit; settings = false }
            }
    }
    /// What Settings asked for on its way out, done once it has gone: the
    /// quilt underneath is where a patch docks and where the goodbye is said,
    /// and signing out takes the Dashboard tab with it, which must not happen
    /// while a sheet presented from that tab is still up.
    private func leaveSettings() {
        guard let exit = settingsExit else { return }
        settingsExit = nil
        switch exit {
        case .deleted:
            session.signedOut()
            session.farewell = true
        case .signOut:
            Task { await session.signOut() }
        case .dock(let slug):
            Task { await session.open(slug: slug) }
        }
    }
    /// At rest the field is a button wearing the field's clothes: a text field
    /// hosted in the bar's UIKit toolbar item reports neither focus nor editing
    /// to SwiftUI, but a freshly inserted one can be given focus. So the tap
    /// swaps the real field in, focused, and nothing appears to change.
    @ViewBuilder private var field: some View {
        if session.searching {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.pwTextMuted)
                TextField("Search patches and events", text: $session.searchText)
                    .focused($focused).submitLabel(.search).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .onSubmit { session.showMatches() }
                    .accessibilityIdentifier("searchField")
                if !session.searchText.isEmpty {
                    Button { session.searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.pwTextMuted) }.accessibilityLabel("Clear text")
                }
            }
            .modifier(FieldChrome(width: fieldWidth))
            .onAppear { DispatchQueue.main.async { focused = true } }
        } else {
            Button { session.searching = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("Search patches and events").lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.pwTextMuted)
                .modifier(FieldChrome(width: fieldWidth))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")
        }
    }
}

/// The capsule both forms of the field wear.
private struct FieldChrome: ViewModifier {
    let width: CGFloat
    func body(content: Content) -> some View {
        content.font(Font.pw.subheadline).padding(.horizontal, 14).frame(height: 44).frame(width: width).modifier(GlassCapsule())
    }
}

/// Liquid glass where the system has it, the same glass the bar's own
/// buttons wear so the field and its neighbours are one family; material
/// with a hairline where it does not. The glass carries a tint of the app's
/// surface, because the quilt under it is dense and unpredictable and a
/// control that carries text needs some floor of its own.
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            // The same glass the bar's buttons wear, tinted with the app's
            // surface so a placeholder still reads over dense cloth.
            content.glassEffect(.regular.tint(Color.pwSurface.opacity(0.72)).interactive(), in: Capsule())
        } else {
            content.background(.thickMaterial, in: Capsule()).overlay(Capsule().strokeBorder(Color.pwBorder, lineWidth: 1))
        }
    }
}

/// Display is the reader's own setting, not the quilt's, so it opens as its
/// own sheet beside the quilt's information rather than inside it.
struct DisplaySheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            DisplaySettings()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Finds the tab bar under this view and reports a long press on one of its
/// items. UIKit still draws SwiftUI's tab bar, so the press attaches there.
private struct TabBarLongPress: UIViewRepresentable {
    let item: Int
    let action: () -> Void
    func makeUIView(context: Context) -> Probe { Probe(item: item, action: action) }
    func updateUIView(_ view: Probe, context: Context) { view.action = action }
    final class Probe: UIView, UIGestureRecognizerDelegate {
        let item: Int
        var action: () -> Void
        private weak var bar: UITabBar?
        private var attempts = 0
        init(item: Int, action: @escaping () -> Void) {
            self.item = item; self.action = action
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            attempts = 0
            attach()
        }
        /// The tab bar is built a little after this view lands in the window, so look again for a while.
        private func attach() {
            guard bar == nil, let window else { return }
            guard let found = Self.tabBar(in: window.rootViewController) ?? Self.tabBar(in: window) else {
                attempts += 1
                if attempts < 20 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.attach() } }
                return
            }
            let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed))
            press.minimumPressDuration = 0.45
            press.cancelsTouchesInView = false
            press.delegate = self
            found.addGestureRecognizer(press)
            bar = found
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        private static func tabBar(in controller: UIViewController?) -> UITabBar? {
            guard let controller else { return nil }
            if let tabs = controller as? UITabBarController { return tabs.tabBar }
            for child in controller.children { if let bar = tabBar(in: child) { return bar } }
            return tabBar(in: controller.presentedViewController)
        }
        @objc private func pressed(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let bar, let count = bar.items?.count, count > 0 else { return }
            let point = gesture.location(in: bar)
            let controls = Self.controls(in: bar).map { $0.convert($0.bounds, to: bar) }.filter { $0.width > 20 }.sorted { $0.minX < $1.minX }
            let index: Int? = controls.count == count ? controls.firstIndex { $0.contains(point) } : Int(point.x / (bar.bounds.width / CGFloat(count)))
            if index == item { action() }
        }
        private static func tabBar(in view: UIView) -> UITabBar? {
            if let bar = view as? UITabBar { return bar }
            for child in view.subviews { if let bar = tabBar(in: child) { return bar } }
            return nil
        }
        private static func controls(in view: UIView) -> [UIView] {
            view.subviews.flatMap { $0 is UIControl ? [$0] : controls(in: $0) }
        }
    }
}
