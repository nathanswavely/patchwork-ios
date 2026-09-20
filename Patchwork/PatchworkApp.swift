// SPDX-License-Identifier: MPL-2.0

import SwiftUI

@main struct PatchworkApp: App {
    @StateObject private var quilts = QuiltStore()
    /// The reader's standing theme choice (docs/adr/112). Per device, never on
    /// an account: the reader it exists for does not have one.
    @AppStorage(DisplayDefaults.themeKey) private var theme = ThemeChoice.system.rawValue
    var body: some Scene {
        WindowGroup {
            Group {
                if let quilt = quilts.selected {
                    QuiltHome(quilt: quilt).id(quilt.id)
                } else {
                    NavigationStack { QuiltPicker() }
                }
            }
            .preferredColorScheme(previewColorScheme ?? (ThemeChoice(rawValue: theme) ?? .system).scheme)
            .environmentObject(quilts)
            .tint(Color.accentColor)
        }
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
            .font(.title2)
            .foregroundStyle(.tint)
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
        } description: { Text(message) } actions: { Button("Try again", action: retry) }
    }
}
