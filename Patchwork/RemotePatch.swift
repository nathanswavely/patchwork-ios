// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// A patch on another quilt, read-only, from its own public API (web ADR 024).
///
/// Looking happens here; belonging happens on their soil. The sash says whose
/// quilt this is before anything else on the screen does, and every act deeper
/// than reading is a doorway out to that host — this client has no account on
/// any quilt, least of all a neighbour's.
struct RemotePatchView: View {
    let host: String
    let slug: String
    var close: (() -> Void)? = nil
    @State private var patch: Patch?
    @State private var events: [PatchworkEvent] = []
    @State private var instance: Instance?
    @State private var icon: UIImage?
    @State private var loading = true
    @State private var error: String?
    private var origin: URL? { URL(string: "https://\(host)") }
    private var api: PatchworkAPI? { origin.map { PatchworkAPI(base: $0) } }
    private var quiltName: String { instance?.name ?? host }
    private var visitURL: URL? { origin?.appendingPathComponent("patches/\(slug)") }
    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    if let icon {
                        Image(uiImage: icon).resizable().frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 3)).accessibilityHidden(true)
                    } else {
                        Image(systemName: "square.grid.2x2").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    Text("On \(quiltName), another quilt").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            if let patch {
                Section {
                    Text(patch.name).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                    Text(patch.countsLabel).font(.subheadline).foregroundStyle(.secondary)
                    if let tags = patch.tags, !tags.isEmpty {
                        Text(tags.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let description = patch.description, !description.isEmpty {
                        Text(description).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !events.isEmpty {
                    Section("Upcoming events") {
                        ForEach(events) { event in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title)
                                Text(event.shortDateLabel).font(.subheadline).foregroundStyle(.secondary)
                                if let location = event.location, !location.isEmpty {
                                    Text(location).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }.padding(.vertical, 2).accessibilityIdentifier("remoteEventRow")
                        }
                    }
                }
                Section {
                    if let visitURL { Link(destination: visitURL) { Label("Visit on \(quiltName)", systemImage: "arrow.up.forward.app") } }
                } footer: {
                    Text("You’re seeing this patch’s public face from your own quilt. Joining and everything deeper live on \(quiltName).")
                }
            }
            if loading { ProgressView("Reaching \(host)…") }
            if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Try again") { Task { await load() } }
                    if let visitURL { Link(destination: visitURL) { Label("Try their site", systemImage: "safari") } }
                }
            }
        }
        .navigationTitle("Patch").navigationBarTitleDisplayMode(.inline)
        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
        .task { await load() }
    }
    private func load() async {
        guard let api else {
            error = "That address isn’t a quilt this app can read."
            loading = false
            return
        }
        loading = true; error = nil
        defer { loading = false }
        do {
            let response: PatchResponse = try await api.get("nodes/\(slug)")
            patch = response.node
        } catch {
            if !Task.isCancelled {
                self.error = "Couldn’t reach this patch. Its quilt may be unreachable, or may not allow browsing from other quilts."
            }
            return
        }
        if let page = try? await api.events(slug: slug, limit: 5, from: Date()) { events = page.items ?? [] }
        if instance == nil { instance = try? await api.get("instance") }
        if icon == nil, let data = try? await api.data("instance/icon") {
            if let image = UIImage(data: data) { icon = image }
            else { icon = await SVGRasterizer().render(data, side: 18) }
        }
    }
}

/// Where a patch went, when it went to another quilt (web ADR 090).
///
/// A forwarding address of the shape `https://host/patches/slug` names a patch
/// on somebody else's quilt, and that is exactly what the read-only remote
/// view is for — so the banner opens it in-app and still offers the host's own
/// page. Anything else stays a plain link out.
struct MovedElsewhere: Hashable {
    let host: String
    let slug: String
    let url: URL
    init?(_ raw: String?) {
        guard let raw, let url = URL(string: raw), url.scheme == "https", let host = url.host(), !host.isEmpty else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "patches", !parts[1].isEmpty else { return nil }
        self.host = host
        self.slug = parts[1]
        self.url = url
    }
}
