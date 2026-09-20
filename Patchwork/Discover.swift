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
    @State private var showRest = false
    /// Each patch's next event, from the upcoming feed: the honest rotating fact.
    @State private var next: [String: PatchworkEvent] = [:]
    private let shortlist = 8
    private var ranked: [(tag: String, count: Int)] { session.rankedTags }
    private var visible: [(tag: String, count: Int)] { showAll ? ranked : Array(ranked.prefix(shortlist)) }
    private var answer: DiscoverAnswer.Split {
        DiscoverAnswer.split(
            session.patches,
            picked: picked,
            soonest: next.compactMapValues(\.date),
            order: Dictionary(uniqueKeysWithValues: session.baseline.enumerated().map { ($1.id, $0) })
        )
    }
    var body: some View {
        Group {
            if session.loading { ProgressView("Loading quilt…") }
            else if let error = session.error { FailureView(message: error) { Task { await session.load() } } }
            else if answering || ranked.isEmpty { answerList } else { ask }
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
                // The one display moment on this surface. It is not the
                // screen's name — that is the inline title — but it is the
                // app speaking in its own voice, once, in five words, and
                // this whole surface exists to ask it. Shantell is the
                // hand-lettered voice the web reserves "for big headings
                // where it's personality, not strain" (app.css), and a
                // question nobody has to read at length is exactly that.
                Text("What are you drawn to?")
                    .font(Font.pw.displayTitle)
                    .foregroundStyle(Color.pwText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Pick a few and we’ll pull up the patches that match. These are the tags this quilt actually wears, most-worn first.")
                    .font(Font.pw.body)
                    .foregroundStyle(Color.pwTextMuted)
                FlowLayout(spacing: 8) {
                    ForEach(visible, id: \.tag) { entry in
                        Chip(title: entry.tag, count: entry.count, active: picked.contains(entry.tag)) {
                            if picked.contains(entry.tag) { picked.remove(entry.tag) } else { picked.insert(entry.tag) }
                        }
                    }
                }
                if !showAll && ranked.count > shortlist {
                    Button("Show all tags (\(ranked.count - shortlist) more)") { showAll = true }
                        .font(Font.pw.subheadlineMedium)
                        .inkAction("chevron.down")
                }
                if !picked.isEmpty {
                    Text("\(picked.count) selected").font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .background(Color.pwGround.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                // The tint fills the control and nothing else on this screen.
                if picked.isEmpty {
                    Button { answering = true } label: {
                        Text("Pick at least one").font(Font.pw.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).controlSize(.large).tint(.gray)
                    .foregroundStyle(Color.pwText)
                } else {
                    Button { answering = true } label: {
                        Text("Show me patches").font(Font.pw.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                }
                Button("Show me everything instead") { picked = []; answering = true }
                    .font(Font.pw.subheadline)
                    .foregroundStyle(Color.pwText)
            }.padding().background(.bar)
        }
    }
    /// The answer is a stack of cards on the quilt's ground, the way List mode
    /// is (docs/adr/078) — a plain `List` re-grounded, with the rows carrying
    /// their own card surface rather than the system's inset grey.
    private var answerList: some View {
        List {
            if !ranked.isEmpty {
                Button { answering = false } label: {
                    Text("Ask me again").font(Font.pw.subheadlineMedium)
                }
                .inkAction("arrow.uturn.backward")
                .plainRow()
            }
            if session.patches.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nothing here yet").font(Font.pw.title2).foregroundStyle(Color.pwText)
                        Text("No patches on this quilt so far. Add one, and the next person who comes looking will have something to find.")
                            .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                        Link("Add a patch on the website", destination: session.api.webURL("patches/new"))
                            .font(Font.pw.subheadlineMedium)
                            .exitLink(fills: false)
                    }.padding(.vertical, 4)
                }.plainRow()
            } else {
                let split = answer
                Section {
                    ForEach(split.matching) { patch in row(patch) }
                } header: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(picked.isEmpty ? "Everything on this quilt" : "Patches you might like")
                            .font(Font.pw.title2).foregroundStyle(Color.pwText)
                        Text("\(split.matching.count) \(split.matching.count == 1 ? "patch" : "patches")\(picked.isEmpty ? "" : " match what you picked") — the ones with something coming up are first.")
                            .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    }.textCase(nil).padding(.bottom, 6)
                } footer: {
                    // Nothing follows this section where the answer is the
                    // whole quilt, so the footer belongs to it; with a rest
                    // section below, it moves down there instead.
                    if split.rest.isEmpty { closing }
                }
                // The answer is a shortlist, not a verdict on everything else.
                // The rest of the quilt stays one tap away — folded so the
                // question still has a short answer, and counted so nobody
                // has to guess how much of the quilt they have not been shown.
                if !split.rest.isEmpty {
                    Section {
                        Button {
                            withAnimation { showRest.toggle() }
                        } label: {
                            Text("\(showRest ? "Hide" : "Show") the rest of the quilt (\(split.rest.count))")
                                .font(Font.pw.subheadlineMedium)
                        }
                        // The identifier belongs to the button itself, not to
                        // the row the ink modifier wraps it in.
                        .accessibilityIdentifier("showRest")
                        .inkAction(showRest ? "chevron.up" : "chevron.down")
                        .plainRow()
                        if showRest {
                            ForEach(split.rest) { patch in row(patch) }
                        }
                    } footer: {
                        closing
                    }
                }
            }
        }
        // Grouped rather than plain: a plain list pins its section headers,
        // and a header sliding over a card is the one thing a stack of cards
        // on the ground must not do.
        .listStyle(.grouped)
        .groundedList()
    }
    /// One patch, the same row in both lists: what it is, what it wears, and
    /// the next honest thing happening on it.
    private func row(_ patch: Patch) -> some View {
        CompactPatchCard(patch: patch,
                         tagMotifs: session.tagMotifs,
                         colorMode: session.colorMode,
                         identifier: "discoverRow",
                         open: { session.open(patch) }) {
            if let tags = patch.tags, !tags.isEmpty {
                Text(tags.joined(separator: " · "))
                    .font(Font.pw.caption)
                    .foregroundStyle(Color.pwTextMuted)
                    .lineLimit(1)
            }
            // The next honest thing happening on this patch, read from the
            // upcoming feed rather than claimed.
            if let event = next[patch.slug] {
                Label("\(event.shortDateLabel) · \(event.title)", systemImage: "calendar")
                    .font(Font.pw.caption)
                    .foregroundStyle(Color.pwTextMuted)
                    .lineLimit(1)
            }
        }
        .plainRow()
    }
    /// The foot of the answer. Following is the thing the web sends people
    /// away with, and this client has no account to do it with — so the
    /// sentence that says so is itself the door to where it can be done,
    /// rather than a button that would only be refused.
    private var closing: some View {
        VStack(alignment: .leading, spacing: 4) {
            Link(destination: session.api.loginURL()) {
                Text("Following needs an account — reading never does.")
                    .font(Font.pw.footnote)
            }
            .accessibilityIdentifier("followOnWebsite")
            .exitLink(fills: false)
            QuiltInfoFooter()
        }
        .textCase(nil)
    }
}

/// The answer's two halves, as a value so the split and its ordering can be
/// checked without a quilt on screen.
enum DiscoverAnswer {
    struct Split {
        var matching: [Patch] = []
        var rest: [Patch] = []
    }
    /// Patches wearing any picked tag first — the ones with something coming
    /// up soonest, then in quilt order — and everything else as the rest,
    /// ordered the same way. Picking nothing asks for the whole quilt, which
    /// has no rest to show.
    static func split(_ patches: [Patch], picked: Set<String>, soonest: [String: Date], order: [String: Int]) -> Split {
        let sort = { (a: Patch, b: Patch) -> Bool in
            let first = soonest[a.slug] ?? .distantFuture, second = soonest[b.slug] ?? .distantFuture
            return first == second ? (order[a.id] ?? .max) < (order[b.id] ?? .max) : first < second
        }
        guard !picked.isEmpty else { return Split(matching: patches.sorted(by: sort), rest: []) }
        let matches = { (patch: Patch) in !picked.isDisjoint(with: patch.tags ?? []) }
        return Split(
            matching: patches.filter(matches).sorted(by: sort),
            rest: patches.filter { !matches($0) }.sorted(by: sort)
        )
    }
}
