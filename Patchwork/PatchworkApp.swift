// SPDX-License-Identifier: MPL-2.0

import SwiftUI

@main struct PatchworkApp: App {
    @StateObject private var quilts = QuiltStore()
    /// The navigation and tab bars draw their own text, so the two faces are
    /// put on them once, here, rather than per screen.
    init() { PWType.install() }
    /// The reader's standing theme choice (docs/adr/112). Per device, never on
    /// an account: the reader it exists for does not have one.
    @AppStorage(DisplayDefaults.themeKey) private var theme = ThemeChoice.system.rawValue
    var body: some Scene {
        WindowGroup {
            // With nothing chosen yet the app opens on the featured quilt
            // itself, its chrome folded away under a welcome (FirstLookCard).
            // Choosing it keeps the same view, so the quilt already on screen
            // is the one explored rather than a second copy loaded behind a
            // spinner; choosing another quilt swaps it out.
            let quilt = quilts.selected ?? Quilt.featured
            QuiltHome(quilt: quilt, firstLook: quilts.selected == nil).id(quilt.id)
                // A tapped link to a quilt whose admin lets links open here.
                .onOpenURL { quilts.receive($0) }
                .task { if let link = launchLink { quilts.receive(link) } }
            .preferredColorScheme(previewColorScheme ?? (ThemeChoice(rawValue: theme) ?? .system).scheme)
            .environmentObject(quilts)
            // The body face is the default for every descendant that does not
            // name its own, which is how it reaches the screens this slice
            // does not otherwise touch.
            .font(Font.pw.body)
            .foregroundStyle(Color.pwText)
            .tint(Color.pwAccent)
        }
    }
    /// A link handed over at launch, for the UI tests: a universal link
    /// cannot be tapped into a simulator for a quilt that does not exist.
    private var launchLink: URL? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--open-link"), index + 1 < arguments.count { return URL(string: arguments[index + 1]) }
        #endif
        return nil
    }
    private var previewColorScheme: ColorScheme? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--dark-preview") { return .dark }
        #endif
        return nil
    }
}

struct QuiltMark: View {
    var body: some View {
        Image(systemName: "square.grid.2x2.fill")
            .font(Font.pw.title2)
            // Ink, not the tint: this mark stands in for the quilt's own icon
            // where it has none, and identity is never what a tint means.
            .foregroundStyle(Color.pwText)
            .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }
}

struct FailureView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t load this quilt", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
        } actions: {
            // The app's ink would win over the button's own white; on the
            // rust the word is pwOnAccent.
            Button("Try again", action: retry).font(Font.pw.headline).buttonStyle(.borderedProminent).foregroundStyle(Color.pwOnAccent)
        }
    }
}
