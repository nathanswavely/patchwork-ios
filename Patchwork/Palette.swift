// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import UIKit

/// The app's own identity colours, and the only place a ground, a surface, a
/// hairline or a text colour is named.
///
/// The quilt is the patches' own and always has been (`QuiltTheme`); this is
/// the room the quilt hangs in. Its five colours are lifted from the web's
/// tokens rather than invented, so a reader who knows the site recognises the
/// app: the ground is the textile canvas (`--lt-canvas`, raw cotton `#F4F0E8`
/// / raw denim `#151820`, which is also the web's `--color-bg`), the surface
/// is the web's `--color-surface` one step off it, the hairline is
/// `--color-border` (the unbleached-thread family the quilt's own
/// `QuiltInk.thread` draws from), and the two text colours are `--color-text`
/// and `--color-text-muted`.
///
/// They live in `Assets.xcassets/Palette` rather than here as literals so each
/// carries its own light, dark and **Increase Contrast** variants, which is
/// what lets a system setting reach them without a single `if`.
///
/// | token          | light     | dark      | light ⇧contrast | dark ⇧contrast |
/// | -------------- | --------- | --------- | --------------- | -------------- |
/// | `pwGround`     | `#F4F0E8` | `#151820` | `#F7F4ED`       | `#0E1016`      |
/// | `pwSurface`    | `#FAF6EE` | `#1C2028` | `#FFFFFF`       | `#242A33`      |
/// | `pwBorder`     | `#DDD8CC` | `#2A2E38` | `#A9A294`       | `#4A5060`      |
/// | `pwText`       | `#2A2520` | `#E0DBD4` | `#1A1510`       | `#F5F2EC`      |
/// | `pwTextMuted`  | `#6B655C` | `#9B958C` | `#4E483F`       | `#BAB4AA`      |
///
/// Contrast (WCAG, against the ground): text 13.4:1 light / 12.9:1 dark;
/// muted 5.1:1 light / 5.5:1 dark — AA for body text at both ends, and the
/// Increase Contrast variants only ever move further from the ground.
///
/// **The one tint rule still stands.** None of these is a tint: the single
/// accent is `AccentColor` (`#0272B5` light, `#39B4F6` dark — the web's
/// `--color-primary`), and nothing else in the chrome may stand for action.
extension Color {
    /// The ground everything is laid on: the textile canvas.
    static let pwGround = Color("PWGround")
    /// A card, a row, a sheet's head — one step off the ground.
    static let pwSurface = Color("PWSurface")
    /// The hairline a surface is cut out with. Never a divider between words.
    static let pwBorder = Color("PWBorder")
    /// Reading ink.
    static let pwText = Color("PWText")
    /// Everything that is true but secondary: counts, captions, the aside.
    static let pwTextMuted = Color("PWTextMuted")
    /// The one tint, read from the asset by name rather than through
    /// `Color.accentColor`: that one answers with whatever tint the
    /// environment is carrying, which is the system's blue until something
    /// sets it, and the app was quietly drawing iOS blue because of it.
    static let pwAccent = Color("AccentColor")
}

extension UIColor {
    /// The ground, for the UIKit side of the canvas.
    static let pwGround = UIColor(named: "PWGround") ?? .systemGroupedBackground
}

/// What a card is made of, in one place so the list, the profile's head and
/// anything that adopts the language later cannot drift apart.
enum PatchworkCard {
    static let radius: CGFloat = 14
    static let hairline: CGFloat = 1 / 3
    static let padding: CGFloat = 14
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
}

/// The card's own clothes: the surface, the hairline it is cut out with, and
/// nothing else. There is no shadow — the quilt's only drop shadow belongs to
/// a corner mark, and a stack of floating cards would be the app inventing an
/// elevation system the web does not have.
struct CardSurface: ViewModifier {
    var padding: CGFloat = PatchworkCard.padding
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.pwSurface, in: PatchworkCard.shape)
            .overlay(PatchworkCard.shape.strokeBorder(Color.pwBorder, lineWidth: PatchworkCard.hairline))
    }
}

/// A grouped `List` re-grounded: the quilt's canvas colour behind it and the
/// card surface under its rows, so a system list stops announcing itself as
/// iOS default grey and belongs to the same room as the patch cards.
///
/// The row colour is *not* set here. `listRowBackground` applied to the `List`
/// itself does not reach the rows — the list's own white keeps winning — so
/// each list wraps its sections in `Group { … }.listRows()`, which does.
struct GroundedList: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Color.pwGround.ignoresSafeArea())
    }
}

/// A link reads as ink with an exit mark beside it, never as coloured text.
///
/// The tint is rust and it belongs to *controls* — a selected segment, a
/// toggle, the follow heart, a prominent button. Text that happens to be
/// tappable is still text: colouring it is what made the app look like a web
/// page rendered in iOS blue, and a page of coloured phrases says "link" so
/// often that it stops saying anything. The arrow says where the tap goes —
/// out of the app — which the colour never did.
struct ExitLink: ViewModifier {
    /// Where a row already ends in something else, the arrow hugs the text
    /// instead of taking the width.
    var fills = true
    func body(content: Content) -> some View {
        HStack(spacing: 6) {
            content.foregroundStyle(Color.pwText)
            Image(systemName: "arrow.up.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.pwTextMuted)
                .accessibilityHidden(true)
            if fills { Spacer(minLength: 0) }
        }
    }
}

/// The same rule for a door that stays inside the app: ink, and the platform's
/// own chevron to say it opens something.
struct InkRow: ViewModifier {
    /// As with `ExitLink`: where the door shares its line with something else,
    /// the chevron hugs the text instead of taking the whole width.
    var fills = true
    func body(content: Content) -> some View {
        HStack(spacing: 6) {
            content.foregroundStyle(Color.pwText)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.pwTextMuted)
                .accessibilityHidden(true)
            if fills { Spacer(minLength: 0) }
        }
    }
}

/// An act rather than a door: "Try again", "Load more", "Show all tags". It
/// is still a word, so it is still ink — the glyph beside it is what says it
/// can be pressed, and the tint stays where it belongs, on filled controls.
struct InkAction: ViewModifier {
    let symbol: String
    func body(content: Content) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.pwTextMuted)
                .accessibilityHidden(true)
            content.foregroundStyle(Color.pwText)
            Spacer(minLength: 0)
        }
    }
}

extension View {
    func cardSurface(padding: CGFloat = PatchworkCard.padding) -> some View { modifier(CardSurface(padding: padding)) }
    func groundedList() -> some View { modifier(GroundedList()) }
    /// The card surface under a list's rows. Applied to a `Group` of sections
    /// inside the list, which is the one place it propagates from.
    func listRows() -> some View { listRowBackground(Color.pwSurface) }
    /// A row in a re-grounded plain `List` that carries its own surface — a
    /// card, or a line of ink on the ground. The list must not draw a second
    /// surface under it, and a rule between two cards belongs to neither.
    func plainRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }
    /// A link out of the app: ink text, and an arrow that says so.
    func exitLink(fills: Bool = true) -> some View { modifier(ExitLink(fills: fills)) }
    /// A door within the app that is text rather than a list row.
    func inkRow(fills: Bool = true) -> some View { modifier(InkRow(fills: fills)) }
    /// A worded act — retry, load more, unfold — in ink, with its own glyph.
    func inkAction(_ symbol: String) -> some View { modifier(InkAction(symbol: symbol)) }
}
