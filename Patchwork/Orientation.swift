// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// The orientation card (web docs/adr/040): the one thing this client says
/// unprompted, the first time a reader opens a quilt.
///
/// Overlaid on the foot of the quilt rather than presented as a sheet. A
/// sheet would be the one blocking thing in a client whose whole posture is
/// that reading costs nothing — it would have to be dismissed before the
/// quilt could be looked at, which is exactly backwards for a card whose
/// content is "you can read this without an account". As an overlay it sits
/// over the canvas, which is dismissible content, never over a control, and
/// the quilt pans and opens underneath it.
///
/// It is offered once. Both answers — reading the About page or saying no —
/// are answers, and neither brings it back.
struct IntroCard: View {
    let quiltName: String
    let dismiss: () -> Void
    @State private var page: InfoPage?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The quilt saying its own name, which is the display face's one
            // job — and this card is two short lines, never a paragraph of it.
            Text("\(quiltName) is a quilt of the communities around you.")
                .font(Font.pw.displayTitle2)
                .foregroundStyle(Color.pwText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Every tile is a real group, placed near the groups it shares people with. No ads, no personalized algorithm. Run by people here.")
                .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                // A door into the About page, so it wears the chevron rather
                // than a colour — hugging its text, because the decline
                // shares the line with it.
                Button("What is Patchwork?") { page = .about }
                    .font(Font.pw.footnoteSemibold)
                    .accessibilityIdentifier("introAbout")
                    .inkRow(fills: false)
                Spacer(minLength: 0)
                // A worded decline, not an ✕: the card's actual question is
                // whether you need an account, and this answers it.
                Button("I’ll lurk for now") { dismiss() }
                    .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                    .accessibilityIdentifier("introDismiss")
            }
        }
        .padding(14)
        .frame(maxWidth: 420, alignment: .leading)
        // Material, not the card surface: this one floats over a live quilt
        // that pans and opens underneath it, and an opaque panel over moving
        // cloth would read as the modal the card exists in order not to be.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.pwBorder))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("introCard")
        // Reading About is the card's job done, so it closes behind the
        // page rather than waiting on the foot of the quilt for a second
        // answer it has already had.
        .sheet(item: $page, onDismiss: dismiss) { page in
            NavigationStack { page.view.modifier(IntroDone()) }
        }
    }
}

private struct IntroDone: ViewModifier {
    @Environment(\.dismiss) private var close
    func body(content: Content) -> some View {
        content.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { close() } } }
    }
}

/// Whether this reader has met a given quilt before. Keyed per quilt, because
/// the card names the quilt in its own first sentence: connecting to a second
/// quilt is meeting a second place, and being greeted by it once is right.
/// There is no account to scope this to — an anonymous reader is the device.
enum IntroState {
    private static let prefix = "introSeen."
    static func key(for quilt: Quilt) -> String { prefix + (quilt.url.host() ?? quilt.id) }
    static func seen(_ quilt: Quilt, defaults: UserDefaults = .standard) -> Bool {
        #if DEBUG
        // The UI tests say which side of this they are testing, because
        // `UserDefaults` outlives a launch and "the first time" is otherwise
        // whichever test happened to run first on that simulator.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--forget-intro") { return false }
        if arguments.contains("--skip-intro") { return true }
        #endif
        return defaults.bool(forKey: key(for: quilt))
    }
    static func markSeen(_ quilt: Quilt, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key(for: quilt))
    }
}
