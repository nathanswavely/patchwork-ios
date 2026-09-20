// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// Discovery mode: the quilt shows everything and asks nothing, so this
/// surface asks one question and shows a short answer. It ends in the patch;
/// following stays on the website until sign-in exists here.
struct Discover: View {
    @EnvironmentObject private var session: QuiltSession
    @Environment(\.colorScheme) private var colorScheme
    @State private var picked = Set<String>()
    @State private var answering = false
    @State private var showAll = false
    /// Each patch's next event, from the upcoming feed: the honest rotating fact.
    @State private var next: [String: PatchworkEvent] = [:]
    private let shortlist = 8
    private var ranked: [(tag: String, count: Int)] { session.rankedTags }
    private var visible: [(tag: String, count: Int)] { showAll ? ranked : Array(ranked.prefix(shortlist)) }
    /// Patches wearing any picked tag, the ones with something coming up first (soonest first), then in quilt order.
    private var matching: [Patch] {
        let pool = picked.isEmpty ? session.patches : session.patches.filter { !picked.isDisjoint(with: $0.tags ?? []) }
        let order = Dictionary(uniqueKeysWithValues: session.baseline.enumerated().map { ($1.id, $0) })
        return pool.sorted {
            let a = next[$0.slug]?.date ?? .distantFuture, b = next[$1.slug]?.date ?? .distantFuture
            return a == b ? (order[$0.id] ?? .max) < (order[$1.id] ?? .max) : a < b
        }
    }
    var body: some View {
        Group {
            if session.loading { ProgressView("Loading quilt…") }
            else if let error = session.error { FailureView(message: error) { Task { await session.load() } } }
            else if answering || ranked.isEmpty { answer } else { ask }
        }
        .navigationTitle("Discover").navigationBarTitleDisplayMode(.inline)
        .modifier(DiscoveryToolbar())
        .task {
            guard let items = (try? await session.api.events(limit: 100))?.items else { return }
            var soonest: [String: PatchworkEvent] = [:]
            for event in items {
                guard let slug = event.nodeSlug else { continue }
                if let current = soonest[slug], (current.date ?? .distantFuture) <= (event.date ?? .distantFuture) { continue }
                soonest[slug] = event
            }
            next = soonest
        }
    }
    private var ask: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("What are you drawn to?").font(.title.bold())
                Text("Pick a few and we’ll pull up the patches that match. These are the tags this quilt actually wears, most-worn first.").foregroundStyle(Color.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(visible, id: \.tag) { entry in
                        Chip(title: entry.tag, count: entry.count, active: picked.contains(entry.tag)) {
                            if picked.contains(entry.tag) { picked.remove(entry.tag) } else { picked.insert(entry.tag) }
                        }
                    }
                }
                if !showAll && ranked.count > shortlist { Button("Show all tags (\(ranked.count - shortlist) more)") { showAll = true } }
                if !picked.isEmpty { Text("\(picked.count) selected").font(.footnote).foregroundStyle(Color.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if picked.isEmpty {
                    Button { answering = true } label: { Text("Pick at least one").frame(maxWidth: .infinity) }.buttonStyle(.bordered).controlSize(.large)
                } else {
                    Button { answering = true } label: { Text("Show me patches").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                }
                Button("Show me everything instead") { picked = []; answering = true }.font(.subheadline)
            }.padding().background(.bar)
        }
    }
    private var answer: some View {
        List {
            if !ranked.isEmpty {
                Button { answering = false } label: { Label("Ask me again", systemImage: "arrow.uturn.backward") }
            }
            if session.patches.isEmpty {
                Section {
                    Text("Nothing here yet").font(.title2.bold())
                    Text("No patches on this quilt so far. Add one, and the next person who comes looking will have something to find.").foregroundStyle(Color.secondary)
                    Link("Add a patch on the website", destination: session.api.webURL("patches/new"))
                }
            } else {
                Section {
                    ForEach(matching) { patch in
                        Button { session.open(patch) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(patch.name).font(.headline).foregroundStyle(Color.primary)
                                if let tags = patch.tags, !tags.isEmpty { Text(tags.joined(separator: " · ")).font(.caption).foregroundStyle(Color.secondary) }
                                if let event = next[patch.slug] {
                                    Label("\(event.shortDateLabel) · \(event.title)", systemImage: "calendar").font(.caption).foregroundStyle(Color.secondary).lineLimit(1)
                                }
                            }.padding(.vertical, 4)
                        }.accessibilityIdentifier("discoverRow")
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(picked.isEmpty ? "Everything on this quilt" : "Patches you might like").font(.title2.bold()).foregroundStyle(Color.primary)
                        Text("\(matching.count) \(matching.count == 1 ? "patch" : "patches")\(picked.isEmpty ? "" : " match what you picked") — the ones with something coming up are first.")
                    }.textCase(nil).padding(.bottom, 6)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Following a patch is available on this quilt’s website.")
                        QuiltInfoFooter()
                    }
                }
            }
        }
    }
}
