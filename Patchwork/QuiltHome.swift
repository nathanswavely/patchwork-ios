// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct QuiltHome: View {
    let quilt: Quilt
    @State private var choosing = false
    var body: some View {
        TabView {
            NavigationStack {
                PatchList(quilt: quilt)
                    .toolbar { ToolbarItem(placement: .topBarLeading) { switcher } }
            }.tabItem { Label("Patches", systemImage: "square.grid.2x2") }
            NavigationStack {
                EventList(quilt: quilt)
                    .toolbar { ToolbarItem(placement: .topBarLeading) { switcher } }
            }.tabItem { Label("Events", systemImage: "calendar") }
        }
        .sheet(isPresented: $choosing) { NavigationStack { QuiltPicker() } }
    }
    private var switcher: some View {
        Button { choosing = true } label: { Label("Quilts", systemImage: "square.grid.2x2.fill") }
            .accessibilityLabel("Switch quilt")
    }
}

struct PatchList: View {
    let quilt: Quilt
    @State private var patches: [Patch] = []
    @State private var search = ""
    @State private var loading = true
    @State private var error: String?
    private var filtered: [Patch] {
        patches.filter { search.isEmpty || ($0.name + " " + ($0.tags ?? []).joined(separator: " ")).localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    QuiltMark()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(quilt.name).font(.headline)
                        Text(quilt.url.host() ?? "").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
            }
            Section("Explore patches") {
                ForEach(filtered) { patch in
                    NavigationLink {
                        PatchDetail(quilt: quilt, initial: patch)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(patch.name).font(.headline)
                            if let description = patch.description, !description.isEmpty {
                                Text(description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                            if let tags = patch.tags, !tags.isEmpty {
                                Text(tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }.padding(.vertical, 7)
                    }.accessibilityIdentifier("patchRow")
                }
            }
        }
        .navigationTitle("Patches")
        .searchable(text: $search, prompt: "Patches and interests")
        .overlay {
            if loading { ProgressView("Loading patches…") }
            else if let error { FailureView(message: error) { Task { await load() } }.background(.background) }
            else if filtered.isEmpty { ContentUnavailableView("No patches found", systemImage: "square.grid.2x2", description: Text(search.isEmpty ? "Public patches will appear here when this quilt adds them." : "Try another name or interest.")) }
        }
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        loading = patches.isEmpty; error = nil
        defer { loading = false }
        do {
            let result: TreeResponse = try await PatchworkAPI(base: quilt.url).get("nodes/tree")
            patches = result.tree.children ?? []
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct PatchDetail: View {
    let quilt: Quilt
    let initial: Patch
    @State private var detail: Patch?
    @State private var error: String?
    private var patch: Patch { detail ?? initial }
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    var body: some View {
        List {
            Section {
                Text(patch.name).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                if let tags = patch.tags, !tags.isEmpty {
                    Text(tags.joined(separator: " · ")).foregroundStyle(.secondary)
                }
                if let description = patch.description, !description.isEmpty {
                    Text(description).textSelection(.enabled)
                }
            }
            if let address = patch.address, !address.isEmpty {
                Section("Find this patch") {
                    Label(address, systemImage: "mappin.and.ellipse")
                    if let url = mapsURL {
                        Link("Get directions", destination: url)
                    }
                }
            }
            Section {
                NavigationLink { EventList(quilt: quilt, slug: patch.slug) } label: {
                    Label("Upcoming events", systemImage: "calendar")
                }
                Link(destination: api.webURL("patches/\(patch.slug)")) {
                    Label("Visit patch website", systemImage: "safari")
                }
            } footer: { Text("Joining, following, and governance are available on this quilt’s website while the native app is being developed.") }
            if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Reload patch") { Task { await load() } }
                }
            }
        }
        .navigationTitle("Patch").navigationBarTitleDisplayMode(.inline)
        .toolbar { ShareLink(item: api.webURL("patches/\(patch.slug)")) }
        .task { await load() }
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
}
