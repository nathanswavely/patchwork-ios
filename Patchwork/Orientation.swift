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

/// The first launch: no chooser, the featured quilt itself. Its canvas is
/// live underneath — it pans, zooms and opens patches — with the bars folded
/// away, and this welcome over its foot says whose quilt it is and offers the
/// one way in. Elsewhere is a smaller door to the full picker, where a quilt
/// is found by name or address.
///
/// It is the orientation card's job done larger, so the two never stack: a
/// first look marks its quilt's card as seen when it is answered.
struct FirstLookCard: View {
    let quiltName: String
    let instance: Instance?
    let explore: () -> Void
    let elsewhere: () -> Void
    @State private var page: InfoPage?
    /// The quilt's own one line about itself, where it has one.
    private var summary: String {
        let own = instance?.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return own.isEmpty ? "A quilt of the communities around you." : own
    }
    /// How much is here, in the two numbers a newcomer can picture.
    private var counts: String? {
        guard let stats = instance?.stats else { return nil }
        let parts = [
            stats.nodeCount.map { "\($0) \($0 == 1 ? "patch" : "patches")" },
            stats.eventCount.map { "\($0) \($0 == 1 ? "event" : "events")" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    var body: some View {
        // At the largest text sizes the welcome outgrows the screen, and then
        // it scrolls rather than pushing its one button out of reach.
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 14) { story; actions }.padding(20)
            VStack(alignment: .leading, spacing: 14) {
                ScrollView { story.padding([.horizontal, .top], 20) }.scrollBounceBehavior(.basedOnSize)
                actions.padding([.horizontal, .bottom], 20)
            }
        }
        .frame(maxWidth: 480, alignment: .leading)
        // Material for the same reason as the card's: it floats over cloth
        // that moves, and an opaque panel would read as a wall in front of it.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.pwBorder))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.smooth, value: counts)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("firstLook")
        .sheet(item: $page) { page in
            NavigationStack { page.view.modifier(IntroDone()) }
        }
    }
    /// Whose quilt this is and what it holds: the part that scrolls when
    /// the text is too large for it all to stand at once.
    private var story: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(quiltName)
                    .font(Font.pw.displayTitle2)
                    .foregroundStyle(Color.pwText)
                    .accessibilityAddTraits(.isHeader)
                Text(summary)
                    .font(Font.pw.body).foregroundStyle(Color.pwText)
                if let counts {
                    Text(counts).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                        .transition(.opacity)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Text("Every tile is a real group, placed near the groups it shares people with. No ads, no personalized algorithm.")
                .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    /// The way in and the two doors beside it, which never scroll away.
    private var actions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: explore) {
                Text("Start exploring").frame(maxWidth: .infinity)
            }
            .font(Font.pw.headline)
            .buttonStyle(.borderedProminent).controlSize(.large)
            .foregroundStyle(Color.pwOnAccent)
            .accessibilityIdentifier("exploreQuilt")
            // Side by side while both fit on a line, stacked when they do not,
            // so neither breaks inside a word.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { about; Spacer(minLength: 0); elsewhereDoor }
                VStack(alignment: .leading, spacing: 12) { about; elsewhereDoor }
            }
            .font(Font.pw.footnoteSemibold)
            .foregroundStyle(Color.pwTextMuted)
            .multilineTextAlignment(.leading)
        }
    }
    private var about: some View {
        Button("What is Patchwork?") { page = .about }.accessibilityIdentifier("introAbout")
    }
    private var elsewhereDoor: some View {
        Button("Find another quilt", action: elsewhere).accessibilityIdentifier("findAnotherQuilt")
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
