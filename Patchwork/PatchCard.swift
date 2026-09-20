// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// The patch card and the tile miniature it leads with — the web's card
/// anatomy (CONTEXT.md "Patch card", docs/adr/078 "the map says where, the
/// card says who"), in native clothes.
///
/// A card is "a bordered surface holding something that could move" — the
/// web's own definition — so it is the one shape in this app that is not a
/// system list row: the patch list is a stack of them on the quilt's ground.
/// They are written as their own views rather than inside `QuiltBrowser` so
/// Discover rows and search results can adopt the same language later without
/// a second drawing of the tile.

// MARK: - The miniature

/// The patch's own tile, small. It is the *same* drawing the canvas makes —
/// `QuiltBlocks.cuts` over `QuiltTheme.palette`, rotated about the centre —
/// so a reader moving between the quilt and the list sees one patch, not two
/// decorations of it. Nothing here is invented: an unknown key falls back
/// exactly as the canvas's does, because both ask the same registries.
struct TileMiniature: View {
    let patch: Patch
    /// The quilt's tag vocabulary, which is how a patch that chose no motif
    /// still wears a mark that says what it is. Absent, the mark resolves to
    /// the chosen motif or the quilt mark.
    var tagMotifs: [String: String] = [:]
    var side: CGFloat = 60
    /// Republished by the session; held so the miniature recuts when the
    /// reader changes register, the way the canvas does (docs/adr/112).
    var colorMode: ColorMode = QuiltTheme.colorMode

    private var palette: QuiltTheme.Palette { QuiltTheme.palette(for: patch) }
    private var rotation: Int { QuiltBlocks.rotation(id: patch.id, appearance: patch.appearance) }
    /// The corner mark's size here is the canvas's rule read at this scale:
    /// a share of the tile, capped at the full 22pt disc.
    private var markSize: CGFloat { min(QuiltInk.markSize, side * QuiltInk.markShare) }
    private var inset: CGFloat { max(2, QuiltInk.markInset * side / QuiltInk.unit) }

    var body: some View {
        Canvas { context, size in
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: .degrees(Double(rotation)))
            context.translateBy(x: -size.width / 2, y: -size.height / 2)
            for cut in QuiltBlocks.cuts(id: patch.id, appearance: patch.appearance, palette: palette) {
                guard let uiColor = UIColor(hex: cut.hex) else { continue }
                let color = Color(uiColor)
                var path = Path()
                path.addLines(cut.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
                path.closeSubpath()
                context.fill(path, with: .color(color))
                // The canvas's hairline seal, for the same reason: no ground
                // may show in the join between two fabrics.
                context.stroke(path, with: .color(color), lineWidth: 0.5)
            }
        }
        .frame(width: side, height: side)
        .background(Color(UIColor(hex: palette.bg) ?? .clear))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topLeading) {
            mark(Motifs.image(Motifs.key(for: patch, tagMotifs: tagMotifs)),
                 disc: Color(UIColor(hex: palette.primary) ?? .label),
                 ink: Color(QuiltTheme.textOnColor(palette.primary)))
        }
        .overlay(alignment: .topTrailing) {
            // Status wears a neutral disc in both themes, never the patch's
            // own colour (DESIGN.md "Don't mean status with colour").
            if patch.communityListing {
                mark(Motifs.unclaimed, disc: Color(QuiltInk.statusDisc), ink: .white)
            }
        }
        .accessibilityHidden(true)
        .id(colorMode)
    }

    @ViewBuilder private func mark(_ image: UIImage?, disc: Color, ink: Color) -> some View {
        if let image {
            Circle()
                .fill(disc)
                .overlay(Circle().strokeBorder(Color(QuiltInk.threadHeavy), lineWidth: 1))
                .overlay {
                    Image(uiImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: markSize * 0.64, height: markSize * 0.64)
                        .foregroundStyle(ink)
                }
                .frame(width: markSize, height: markSize)
                .padding(inset)
        }
    }
}

// MARK: - The card

/// One patch, as the web's cards pane shows it to a signed-out visitor: the
/// tile, the name, the counts, the state it wears, and what it says about
/// itself. The whole card is the door into the patch; the only other thing on
/// it is the follow heart, which is an exit to the website.
struct PatchCard: View {
    let patch: Patch
    var tagMotifs: [String: String] = [:]
    var colorMode: ColorMode = QuiltTheme.colorMode
    /// Where following actually happens. Signed out is the only state this
    /// client has, so the heart is a `Link` and never a control with a state
    /// to fake (DESIGN.md "Don't … invent authenticated actions").
    var followURL: URL?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                TileMiniature(patch: patch, tagMotifs: tagMotifs, side: 60, colorMode: colorMode)
                VStack(alignment: .leading, spacing: 4) {
                    Text(patch.name)
                        .font(.headline)
                        .foregroundStyle(Color.pwText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text(patch.cardCountsLabel)
                            .font(.subheadline)
                            .foregroundStyle(Color.pwTextMuted)
                        if patch.movedTo?.isEmpty == false { movedChip }
                    }
                    if let description = patch.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(Color.pwTextMuted)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // Room for the heart, which is laid over the card rather than
                // inside this button: a link inside a button is a target that
                // swallows the card's own tap.
                Spacer(minLength: followURL == nil ? 0 : 28)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardSurface()
        .overlay(alignment: .topTrailing) { follow }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("patchRow")
        .accessibilityHint("Opens patch details.")
    }

    /// A fact, not a chip that does anything: this patch left, and the profile
    /// is where its forwarding address is.
    private var movedChip: some View {
        Text("Moved")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.pwTextMuted)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Color.pwBorder))
    }

    @ViewBuilder private var follow: some View {
        if let followURL {
            Link(destination: followURL) {
                Image(systemName: "heart")
                    .font(.subheadline)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Follow \(patch.name)")
            .accessibilityHint("Opens this quilt’s website to sign in.")
        }
    }
}

// MARK: - What a card says

extension Patch {
    /// The card's counts, worded as the web's card words them: a listing
    /// nobody runs counts who follows it, a claimed patch counts its members,
    /// and the event figure beside them is every active event the patch owns —
    /// not the upcoming one the profile's head carries. The two numbers answer
    /// different questions and a remote snapshot carries only this one
    /// (CONTEXT.md "Upcoming events"), which is why the head and the card are
    /// allowed to differ.
    var cardCountsLabel: String {
        let who: String
        if communityListing {
            who = "\(followerCount ?? 0) Following"
        } else {
            let members = memberCount ?? 0
            who = "\(members) Member\(members == 1 ? "" : "s")"
        }
        let events = eventCount ?? 0
        return "\(who) · \(events) Event\(events == 1 ? "" : "s")"
    }
}

// MARK: - The order menu

/// The three orders the web's cards pane offers, under the web's names
/// (docs/adr/074 "the list reads the quilt"). The app used to say "Name" and
/// "Newest", which are the same two orders under names nobody would recognise
/// from the site.
enum PatchOrder: String, CaseIterable, Identifiable {
    case quilt = "Quilt order"
    case recent = "Recently added"
    case alpha = "A→Z"

    var id: String { rawValue }

    /// Quilt order is not a ranking of this list's own devising: it is the
    /// placement the canvas is drawing at this moment, read back. `placement`
    /// is the laid-out tile ids in order; a patch with no tile — a filtered
    /// set the canvas has not packed yet — keeps the tail rather than being
    /// handed a place in a quilt it is not in.
    func sort(_ patches: [Patch], placement: [String]) -> [Patch] {
        switch self {
        case .alpha:
            return patches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recent:
            // "How new is this patch to the quilt?" — answered by when its
            // community arrived if one has, and by when its listing appeared
            // if not. Ties read A to Z, as the web breaks them.
            func newness(_ patch: Patch) -> String { patch.activatedAt ?? patch.createdAt ?? "" }
            return patches.sorted {
                newness($0) == newness($1)
                    ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    : newness($0) > newness($1)
            }
        case .quilt:
            let rank = Dictionary(placement.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a })
            return patches.enumerated().sorted { left, right in
                let a = rank[left.element.id] ?? Int.max, b = rank[right.element.id] ?? Int.max
                return a == b ? left.offset < right.offset : a < b
            }.map(\.element)
        }
    }
}
