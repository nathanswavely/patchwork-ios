// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import UIKit

/// The site's two typefaces, bundled (`Patchwork/Fonts`, registered through
/// `UIAppFonts` in `Patchwork/Info.plist`) and scaled by Dynamic Type.
///
/// The web sets `--font: 'Space Grotesk'` for body and UI and reserves
/// `--font-display: 'Shantell Sans'` — the hand-lettered voice — "for big
/// headings where it's personality, not strain" (web/src/app.css). That
/// division is kept exactly: everything a person reads or operates is Space
/// Grotesk, and Shantell appears only where a screen says its own name.
///
/// Both are variable fonts, shipped as their single variable TTF rather than a
/// rack of statics, so a weight is a coordinate on the `wght` axis rather than
/// another file. Both are SIL Open Font Licence 1.1; the licence texts are in
/// `docs/third-party/`.
///
/// Nothing here can fail loudly: if a face is missing or refuses to register,
/// every call falls back to SF Pro at the same text style, so the app is
/// legible with no fonts at all.
enum PWType {
    /// The two roles, named after what they are for rather than what they are.
    enum Face {
        case text, display

        /// The family as the font's own name table spells it.
        var family: String { self == .text ? "Space Grotesk" : "Shantell Sans" }
        /// The PostScript name of the variable font's default instance, which
        /// is what `UIAppFonts` registers and what `UIFont(name:)` answers to.
        /// Both fonts default to Light, which is why nothing asks for the
        /// default: every call names a weight on the axis.
        var postScriptName: String { self == .text ? "SpaceGrotesk-Light" : "ShantellSans-Light" }
        /// The `wght` range the axis actually offers. A weight outside it is
        /// clamped rather than ignored, because a descriptor handed an
        /// out-of-range coordinate silently returns the default instance.
        var weights: ClosedRange<CGFloat> { self == .text ? 300...700 : 300...800 }
    }

    /// `wght`, as a four-character tag packed the way Core Text wants it.
    private static let weightAxis = 0x77676874

    /// Whether a face registered at all. Resolved once: a missing font is a
    /// packaging mistake, not a per-call condition.
    static func isAvailable(_ face: Face) -> Bool { available[face] ?? false }
    private static let available: [Face: Bool] = [
        .text: UIFont(name: Face.text.postScriptName, size: 12) != nil,
        .display: UIFont(name: Face.display.postScriptName, size: 12) != nil,
    ]

    /// One font: a face, a weight on its axis, and the text style whose
    /// metrics it grows by. `size` is the style's own size at the Large
    /// content size, so the result matches the system's rhythm before Dynamic
    /// Type moves both of them together.
    static func font(_ face: Face, size: CGFloat, weight: CGFloat, style: UIFont.TextStyle) -> Font {
        Font(uiFont(face, size: size, weight: weight, style: style))
    }

    /// The same, as a `UIFont`, for the UIKit surfaces that draw their own
    /// text — the navigation bar, the tab bar, the quilt's name badges.
    static func uiFont(_ face: Face, size: CGFloat, weight: CGFloat, style: UIFont.TextStyle) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: baseFont(face, size: size, weight: weight))
    }

    /// The unscaled font, at the size the style draws at the Large content
    /// size. `UIFontMetrics` refuses to scale a font it already scaled, so the
    /// two steps are separate and only this one is ever handed to it.
    static func baseFont(_ face: Face, size: CGFloat, weight: CGFloat) -> UIFont {
        guard isAvailable(face) else { return .systemFont(ofSize: size, weight: systemWeight(weight)) }
        let clamped = min(max(weight, face.weights.lowerBound), face.weights.upperBound)
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: face.postScriptName,
            kCTFontVariationAttribute as UIFontDescriptor.AttributeName: [weightAxis: clamped],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    /// The nearest system weight, for the fallback. It only has to be close:
    /// this path exists so a missing font reads plainly, not identically.
    private static func systemWeight(_ weight: CGFloat) -> UIFont.Weight {
        switch weight {
        case ..<350: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        default: return .bold
        }
    }

    /// Put the two faces on the UIKit chrome SwiftUI does not reach: the
    /// navigation bar's titles and the tab bar's labels. A large navigation
    /// title is a screen saying its own name — "Events", "Choose a quilt" —
    /// which is a display moment; an inline title is a label, and stays text.
    @MainActor static func install() {
        let bar = UINavigationBarAppearance()
        bar.configureWithDefaultBackground()
        bar.largeTitleTextAttributes[.font] = uiFont(.display, size: 34, weight: 700, style: .largeTitle)
        bar.titleTextAttributes[.font] = uiFont(.text, size: 17, weight: 600, style: .headline)
        let transparent = UINavigationBarAppearance()
        transparent.configureWithTransparentBackground()
        transparent.largeTitleTextAttributes = bar.largeTitleTextAttributes
        transparent.titleTextAttributes = bar.titleTextAttributes
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = transparent

        let item = UITabBarItemAppearance()
        for state in [item.normal, item.selected, item.disabled] {
            state.titleTextAttributes[.font] = uiFont(.text, size: 10, weight: 500, style: .caption2)
        }
        let tabs = UITabBarAppearance()
        tabs.configureWithDefaultBackground()
        tabs.stackedLayoutAppearance = item
        tabs.inlineLayoutAppearance = item
        tabs.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
    }
}

/// The type scale, named after the system text styles it stands in for, so a
/// call site reads the way `.font(.headline)` did and grows the same way.
///
/// Sizes are the system's own at the Large content size; `UIFontMetrics` does
/// the rest, which is what keeps these usable at the accessibility sizes.
struct PWTypeScale {
    /// The display face. Reserved for a screen or a patch saying its own name.
    var display: Font { PWType.font(.display, size: 34, weight: 700, style: .largeTitle) }
    var displayTitle: Font { PWType.font(.display, size: 28, weight: 700, style: .title1) }
    var displayTitle2: Font { PWType.font(.display, size: 22, weight: 700, style: .title2) }

    var largeTitle: Font { PWType.font(.text, size: 34, weight: 700, style: .largeTitle) }
    var title: Font { PWType.font(.text, size: 28, weight: 700, style: .title1) }
    var title2: Font { PWType.font(.text, size: 22, weight: 700, style: .title2) }
    var title3: Font { PWType.font(.text, size: 20, weight: 600, style: .title3) }
    var headline: Font { PWType.font(.text, size: 17, weight: 600, style: .headline) }
    var body: Font { PWType.font(.text, size: 17, weight: 400, style: .body) }
    var bodyBold: Font { PWType.font(.text, size: 17, weight: 700, style: .body) }
    var callout: Font { PWType.font(.text, size: 16, weight: 400, style: .callout) }
    var subheadline: Font { PWType.font(.text, size: 15, weight: 400, style: .subheadline) }
    var subheadlineMedium: Font { PWType.font(.text, size: 15, weight: 500, style: .subheadline) }
    var subheadlineSemibold: Font { PWType.font(.text, size: 15, weight: 600, style: .subheadline) }
    /// A patch card's name: the web's 0.9rem/700, which is smaller and
    /// heavier than a headline because a card is dense by design.
    var cardTitle: Font { PWType.font(.text, size: 15, weight: 700, style: .subheadline) }
    var footnote: Font { PWType.font(.text, size: 13, weight: 400, style: .footnote) }
    var footnoteSemibold: Font { PWType.font(.text, size: 13, weight: 600, style: .footnote) }
    var caption: Font { PWType.font(.text, size: 12, weight: 400, style: .caption1) }
    var captionSemibold: Font { PWType.font(.text, size: 12, weight: 600, style: .caption1) }
    var caption2: Font { PWType.font(.text, size: 11, weight: 400, style: .caption2) }
    var caption2Semibold: Font { PWType.font(.text, size: 11, weight: 600, style: .caption2) }
}

extension Font {
    /// `Font.pw.headline` — the app's scale, in place of the system's.
    static let pw = PWTypeScale()
}
