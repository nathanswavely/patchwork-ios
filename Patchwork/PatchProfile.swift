// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// The docked profile: the patch's own profile, over the surface that opened
/// it. At rest the sheet shows the head and a cut of the first glimpse;
/// pulled up it shows everything, and the pull is what fetches the events.
struct PatchSheet: View {
    @EnvironmentObject private var session: QuiltSession
    let initial: Patch
    @State private var detail: Patch?
    @State private var events: [PatchworkEvent]?
    @State private var error: String?
    @State private var rest: CGFloat = 320
    @State private var detent = PresentationDetent.height(320)
    @State private var headBottom: CGFloat = 0
    @State private var sheetTop: CGFloat = 0
    /// How much of the first glimpse shows under the head at rest: enough for
    /// its rule, its title and a line of it, cut off. The cut is the invitation.
    private let peek: CGFloat = 96
    private var patch: Patch { detail ?? initial }
    private var api: PatchworkAPI { session.api }
    private var cover: URL? { patch.imageUrl.flatMap { URL(string: $0, relativeTo: session.quilt.url) } }
    private func close() { session.docked = nil }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    head.background(GeometryReader { proxy in Color.clear.preference(key: HeadBottomKey.self, value: proxy.frame(in: .global).maxY) })
                    glimpses
                }
            }
            .navigationTitle("Patch").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ShareLink(item: api.webURL("patches/\(patch.slug)")) }
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) }
            }
        }
        .background(GeometryReader { proxy in Color.clear.preference(key: SheetTopKey.self, value: proxy.frame(in: .global).minY) })
        .onPreferenceChange(HeadBottomKey.self) { headBottom = $0; measure() }
        .onPreferenceChange(SheetTopKey.self) { sheetTop = $0; measure() }
        .presentationDetents([.height(rest), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: detent) { _, now in if now == .large && events == nil { Task { await loadEvents() } } }
        .task { await load() }
    }
    /// The rest height is measured from the sheet's top edge to the foot of the
    /// head, not from the head's own height, so the bar above it is counted.
    private func measure() {
        guard detent != .large, headBottom > sheetTop else { return }
        let height = min((headBottom - sheetTop + peek).rounded(), UIScreen.main.bounds.height * 0.8)
        guard abs(height - rest) > 1 else { return }
        rest = height
        detent = .height(height)
    }
    private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cover {
                AsyncImage(url: cover) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color(.secondarySystemGroupedBackground) }
                    .frame(height: 160).frame(maxWidth: .infinity).clipped()
                    .accessibilityLabel(patch.imageAlt ?? "")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(patch.name).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                Text(patch.countsLabel).font(.subheadline).foregroundStyle(Color.secondary)
                if let tags = patch.tags, !tags.isEmpty { Text(tags.joined(separator: " · ")).font(.footnote).foregroundStyle(Color.secondary) }
                if let description = patch.description, !description.isEmpty { Text(description).textSelection(.enabled) }
            }.padding(.horizontal, 20).padding(.top, 12)
        }
    }
    private var glimpses: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                NavigationLink { EventList(quilt: session.quilt, slug: patch.slug, close: close) } label: {
                    HStack {
                        Text("Upcoming events").font(.headline).foregroundStyle(Color.primary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Color(.tertiaryLabel))
                    }
                }
                if let events {
                    if events.isEmpty { Text("No upcoming events").foregroundStyle(Color.secondary) }
                    ForEach(events.prefix(3)) { event in
                        NavigationLink { EventDetail(quilt: session.quilt, initial: event, close: close) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title).foregroundStyle(Color.primary)
                                Text(event.dateLabel).font(.subheadline).foregroundStyle(Color.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.accessibilityIdentifier("eventRow")
                    }
                } else { Text("Pull up to see what’s coming.").foregroundStyle(Color.secondary) }
            }
            if let address = patch.address, !address.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                    Text("Find this patch").font(.headline)
                    Label(address, systemImage: "mappin.and.ellipse")
                    if let url = mapsURL { Link("Get directions", destination: url) }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Link(destination: api.webURL("patches/\(patch.slug)")) { Label("Visit patch website", systemImage: "safari") }
                if let site = patch.website, let url = URL(string: site), url.scheme == "https" || url.scheme == "http" {
                    Link(destination: url) { Label(url.host() ?? site, systemImage: "link") }
                }
                Text("Joining, following, and governance are available on this quilt’s website while the native app is being developed.")
                    .font(.footnote).foregroundStyle(Color.secondary)
            }
            if let error {
                Text(error).foregroundStyle(Color.secondary)
                Button("Reload patch") { Task { await load() } }
            }
        }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 32)
    }
    private var mapsURL: URL? {
        var parts = URLComponents(string: "https://maps.apple.com/")!
        parts.queryItems = [URLQueryItem(name: "daddr", value: patch.address)]
        return parts.url
    }
    private func load() async {
        error = nil
        do {
            let response: PatchResponse = try await api.get("nodes/\(initial.slug)")
            detail = response.node
        }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func loadEvents() async {
        do { events = (try await api.events(slug: patch.slug)).items ?? [] }
        catch { if !Task.isCancelled { events = []; self.error = error.localizedDescription } }
    }
}

private struct HeadBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct SheetTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
