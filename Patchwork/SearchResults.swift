// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// What the top bar's field finds, shown under it while it is live: patches
/// and upcoming events, each a way through, and one row that narrows the quilt.
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
                Text("Find a patch or an event by name.").foregroundStyle(Color.secondary)
            } else {
                if !patches.isEmpty {
                    Section("Patches") {
                        ForEach(patches) { patch in
                            Button { session.endSearch(); session.open(patch) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(patch.name).foregroundStyle(Color.primary)
                                    if let tags = patch.tags?.prefix(2), !tags.isEmpty { Text(tags.joined(separator: ", ")).font(.subheadline).foregroundStyle(Color.secondary) }
                                }
                            }.accessibilityIdentifier("searchPatch")
                        }
                    }
                }
                if !matchingEvents.isEmpty {
                    Section("Events") {
                        ForEach(matchingEvents) { event in
                            NavigationLink { EventDetail(quilt: session.quilt, initial: event) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.title).foregroundStyle(Color.primary)
                                    Text(event.dateLabel).font(.subheadline).foregroundStyle(Color.secondary)
                                }
                            }.accessibilityIdentifier("searchEvent")
                        }
                    }
                }
                Section {
                    Button { session.showMatches() } label: { Label("Show matches on the quilt for \u{201C}\(trimmed)\u{201D}", systemImage: "square.grid.2x2") }
                        .accessibilityIdentifier("showMatches")
                } footer: { Text("Narrowing the quilt is this one step; typing alone never does it.") }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .task { events = (try? await session.api.events(limit: 100))?.items ?? [] }
    }
}
