// SPDX-License-Identifier: MPL-2.0

import SwiftUI

@main struct PatchworkApp: App {
    @StateObject private var quilts = QuiltStore()
    var body: some Scene {
        WindowGroup {
            Group {
                if let quilt = quilts.selected {
                    QuiltHome(quilt: quilt).id(quilt.id)
                } else {
                    NavigationStack { QuiltPicker() }
                }
            }
            .preferredColorScheme(previewColorScheme)
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
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            GridRow { Color(red: 0.01, green: 0.45, blue: 0.71); Color(red: 0.75, green: 0.15, blue: 0.14) }
            GridRow { Color(red: 0.72, green: 0.49, blue: 0.06); Color(red: 0.36, green: 0.42, blue: 0.28) }
        }
        .frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 7))
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
