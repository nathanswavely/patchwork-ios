// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// What the top bar's field finds, shown under it while it is live: patches
/// and upcoming events, each a way through, and one row that narrows the quilt.
///
/// A found patch wears the same card language as Discover's answer and List
/// mode — the quilt's own tile beside its name, not a bare line of text — so
/// a reader who taps a search result and a reader who taps a card can see
/// they touched the same thing. The rows that are not patches are ink: the
/// one act that narrows the quilt, and the exit to the website's suggest form.
struct SearchResults: View {
    @EnvironmentObject private var session: QuiltSession
    @State private var events: [PatchworkEvent] = []
    private var trimmed: String { session.searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var patches: [Patch] { trimmed.isEmpty ? [] : session.patches.filter { QuiltLayout.matches($0, query: trimmed, tags: []) } }
    private var matchingEvents: [PatchworkEvent] {
        trimmed.isEmpty ? [] : events.filter { $0.title.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
    var body: some View {
        List {
            if trimmed.isEmpty {
                Text("Find a patch or an event by name.")
                    .font(Font.pw.body)
                    .foregroundStyle(Color.pwTextMuted)
                    .plainRow()
            } else {
                if !patches.isEmpty {
                    Section {
                        ForEach(patches) { patch in
                            CompactPatchCard(patch: patch,
                                             tagMotifs: session.tagMotifs,
                                             colorMode: session.colorMode,
                                             identifier: "searchPatch",
                                             open: { session.endSearch(); session.open(patch) }) {
                                if let tags = patch.tags?.prefix(2), !tags.isEmpty {
                                    Text(tags.joined(separator: ", "))
                                        .font(Font.pw.caption)
                                        .foregroundStyle(Color.pwTextMuted)
                                        .lineLimit(1)
                                }
                            }
                            .plainRow()
                        }
                    } header: { heading("Patches") }
                }
                if !matchingEvents.isEmpty {
                    Section {
                        ForEach(matchingEvents) { event in
                            // An event is a thing that could move too, so it
                            // takes the same surface the patch cards take —
                            // the platform's own chevron on it, because this
                            // one is a push rather than a docked sheet.
                            NavigationLink { EventDetail(quilt: session.quilt, initial: event) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.title).font(Font.pw.headline).foregroundStyle(Color.pwText)
                                    Text(event.dateLabel).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10).padding(.leading, 12)
                            }
                            .accessibilityIdentifier("searchEvent")
                            .padding(.trailing, 12)
                            .background(Color.pwSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.pwBorder, lineWidth: 1))
                            .plainRow()
                        }
                    } header: { heading("Events") }
                }
                Section {
                    Button { session.showMatches() } label: {
                        Text("Show matches on the quilt for \u{201C}\(trimmed)\u{201D}")
                            .font(Font.pw.subheadlineMedium)
                    }
                    // On the button itself, so the ink row that wraps it does
                    // not take the name the tests know it by.
                    .accessibilityIdentifier("showMatches")
                    .inkAction("square.grid.2x2")
                    .plainRow()
                } footer: {
                    footnote("Narrowing the quilt is this one step; typing alone never does it.")
                }
                // Nothing found is the one moment a reader has a thing this
                // quilt is missing. Suggesting it needs an account, so this is
                // a link to the website rather than a form that cannot submit,
                // and only where the quilt says it takes suggestions at all.
                // It carries the name they typed, the way the web's own
                // suggest row does — arriving at an empty form would make them
                // type it a second time to say the same thing.
                if patches.isEmpty, matchingEvents.isEmpty, session.instance?.submissionsEnabled == true {
                    Section {
                        Link(destination: session.api.suggestURL(name: trimmed)) {
                            Text("Suggest \u{201C}\(trimmed)\u{201D} as a patch")
                                .font(Font.pw.subheadlineMedium)
                        }
                        .accessibilityIdentifier("suggestPatch")
                        .exitLink()
                        .plainRow()
                    } footer: {
                        footnote("Nothing here matches \u{201C}\(trimmed)\u{201D}. Suggesting a patch happens on this quilt\u{2019}s website.")
                    }
                }
            }
        }
        // Grouped rather than plain: a plain list pins its section headers,
        // and a header sliding over a card is the one thing a stack of cards
        // on the ground must not do.
        .listStyle(.grouped)
        .groundedList()
        .scrollDismissesKeyboard(.immediately)
        .task { events = (try? await session.api.events(limit: 100))?.items ?? [] }
    }

    /// A section's name, not a screen's: Space Grotesk, never the hand.
    private func heading(_ title: String) -> some View {
        Text(title)
            .font(Font.pw.footnoteSemibold)
            .foregroundStyle(Color.pwTextMuted)
            .textCase(.uppercase)
            .padding(.top, 4)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(Font.pw.caption)
            .foregroundStyle(Color.pwTextMuted)
            .textCase(nil)
    }
}
