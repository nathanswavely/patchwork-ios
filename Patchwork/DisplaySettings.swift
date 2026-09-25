// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// The two standing choices a reader makes about how a quilt looks to them
/// (the web's Display menu, docs/adr/112). Both are per device and neither is
/// on an account: the reader this exists for does not have one. Nothing here
/// is sent anywhere, so it never becomes user data.
enum ColorMode: String, CaseIterable, Hashable {
    case standard = "default"
    case muted
    var title: String { self == .standard ? "Default" : "Muted" }
}

enum ThemeChoice: String, CaseIterable, Hashable {
    case system, light, dark
    var title: String { rawValue.capitalized }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// The keys the preferences are held under, shared with nothing.
enum DisplayDefaults {
    static let colorsKey = "patchwork-colors"
    static let themeKey = "patchwork-theme"
    static var colorMode: ColorMode {
        ColorMode(rawValue: UserDefaults.standard.string(forKey: colorsKey) ?? "") ?? .standard
    }
    static var theme: ThemeChoice {
        ThemeChoice(rawValue: UserDefaults.standard.string(forKey: themeKey) ?? "") ?? .system
    }
}

/// Display: no account needed, and no quilt needed either — it is the reader's
/// own setting, so it says what it changes and nothing about who they are.
struct DisplaySettings: View {
    @AppStorage(DisplayDefaults.themeKey) private var theme = ThemeChoice.system.rawValue
    @AppStorage(DisplayDefaults.colorsKey) private var colors = ColorMode.standard.rawValue
    var body: some View {
        List {
            // One Group so both sections' rows take the card surface: the
            // modifier does not reach them from the List itself.
            Group {
            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(ThemeChoice.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("themePicker")
            } header: {
                heading("Theme")
            } footer: {
                footnote("System follows your device’s light or dark appearance.")
            }
            Section {
                Picker("Colors", selection: $colors) {
                    ForEach(ColorMode.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("colorsPicker")
            } header: {
                heading("Colors")
            } footer: {
                footnote("Default draws what each patch chose. Muted keeps a patch’s hue, evens the lightness across every tile and caps how saturated any of them can get — it never adds a colour a patch didn’t choose.")
            }
            }.listRows()
        }
        .groundedList()
        .navigationTitle("Display")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
    }

    private func footnote(_ text: String) -> some View {
        Text(text).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted).textCase(nil)
    }
}
