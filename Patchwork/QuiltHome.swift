// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import UIKit

struct QuiltHome: View {
    @StateObject private var session: QuiltSession
    @State private var pane = Pane.quilt
    /// The reader's colour register, read here so a change to it reaches the
    /// session — and through it the canvas — wherever the sheet was opened from.
    @AppStorage(DisplayDefaults.colorsKey) private var colors = ColorMode.standard.rawValue
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
                    Tab(value: Pane.quilt) { quiltPane } label: { Label { Text("Quilt") } icon: { quiltIcon } }
                    Tab("Events", systemImage: "calendar", value: Pane.events) { eventsPane }
                    Tab("Discover", systemImage: "safari", value: Pane.discover) { discoverPane }
                    // There is no Dashboard until there is an account to dash:
                    // the tab arrives with the session and leaves with it.
                    if session.me != nil {
                        Tab("Dashboard", systemImage: "rectangle.stack", value: Pane.dashboard) { dashboardPane }
                    }
                    // A button, not a place: choosing it focuses the top bar's field (see onChange).
                    Tab("Search", systemImage: "magnifyingglass", value: Pane.search, role: .search) { Color.clear }
                }
            } else {
                TabView(selection: $pane) {
                    quiltPane.tabItem { Label { Text("Quilt") } icon: { quiltIcon } }.tag(Pane.quilt)
                    eventsPane.tabItem { Label("Events", systemImage: "calendar") }.tag(Pane.events)
                    discoverPane.tabItem { Label("Discover", systemImage: "safari") }.tag(Pane.discover)
                    if session.me != nil {
                        dashboardPane.tabItem { Label("Dashboard", systemImage: "rectangle.stack") }.tag(Pane.dashboard)
                    }
                    Color.clear.tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(Pane.search)
                }
            }
        }
        .onChange(of: pane) { was, now in
            // Bouncing back from Search fires this again; that second pass must not end the search it just began.
            if now == .search { pane = was; session.searching = true }
            else if was != .search { session.endSearch() }
        }
        // Letting go of the account takes its tab with it, so the selection
        // has to come home rather than point at a place that is gone.
        .onChange(of: session.me) { _, now in if now == nil, pane == .dashboard { pane = .quilt } }
        // Hold the quilt's tab to switch quilts, the way a profile tab switches accounts.
        .background(TabBarLongPress(item: 0) { session.switching = true })
        .sheet(item: $session.docked) { patch in PatchSheet(initial: patch) }
        .sheet(isPresented: $session.switching) { NavigationStack { QuiltPicker(neighbors: session.instance?.neighborQuilts ?? []) } }
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
    /// The quilt, with the orientation card over the foot of it. The overlay
    /// goes on the tab's own content rather than on the `TabView`, so the
    /// card floats inside the canvas instead of underneath the tab bar; the
    /// padding clears the canvas's own Quilt/Map/List pill, because the card
    /// may cover the quilt but never a control.
    private var quiltPane: some View {
        NavigationStack { QuiltBrowser() }
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
    private var eventsPane: some View { NavigationStack { EventList(quilt: session.quilt).modifier(DiscoveryToolbar()) } }
    private var discoverPane: some View { NavigationStack { Discover() } }
    private var dashboardPane: some View {
        NavigationStack { Dashboard(openDiscover: { pane = .discover }) }
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
                // The bell belongs beside the account, because it is the
                // account's: a signed-out reader has nothing to be told.
                if session.me != nil, !session.searching {
                    ToolbarItem(placement: .topBarTrailing) { NotificationBell(presented: $notifications) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if session.searching {
                        Button("Cancel") { session.endSearch() }
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
                        } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("Account")
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

/// Liquid glass where the system has it; material where it does not. The
/// glass is tinted with the app's own surface: the quilt under it is dense
/// and unpredictable, and a control that carries text needs a floor of its
/// own without a band behind it. Tinted regular glass is the system's answer
/// to exactly that — it stays glass, it just reads frosted.
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content.background(.thickMaterial, in: Capsule()).overlay(Capsule().strokeBorder(Color.pwBorder, lineWidth: 1))
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
