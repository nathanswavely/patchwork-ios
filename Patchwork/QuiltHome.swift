// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct QuiltHome: View {
    let quilt: Quilt
    @State private var choosing = false
    var body: some View {
        TabView {
            NavigationStack {
                QuiltBrowser(quilt: quilt)
                    .toolbar { ToolbarItem(placement: .topBarLeading) { switcher } }
            }.tabItem { Label("Quilt", systemImage: "square.grid.2x2") }
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

struct PatchDetail: View {
    let quilt: Quilt
    let initial: Patch
    var close: (() -> Void)? = nil
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
                NavigationLink { EventList(quilt: quilt, slug: patch.slug, close: close) } label: {
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ShareLink(item: api.webURL("patches/\(patch.slug)")) }
            if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
        }
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
