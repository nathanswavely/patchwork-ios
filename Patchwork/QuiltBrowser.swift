// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import MapKit

struct QuiltBrowser: View {
    let quilt: Quilt
    @State private var patches: [Patch] = []
    @State private var affinity: [Affinity] = []
    @State private var baseline: [QuiltLayout.Tile] = []
    @State private var tiles: [QuiltLayout.Tile] = []
    @State private var query = ""
    @State private var tags = Set<String>()
    @State private var mode = "Quilt"
    @State private var sort = "Quilt order"
    @State private var selected: Patch?
    @State private var filtering = false
    @State private var loading = true
    @State private var error: String?
    @State private var fitRequest = 0
    private var filtered: [Patch] { patches.filter { QuiltLayout.matches($0, query: query, tags: tags) } }
    private var allTags: [String] { Array(Set(patches.flatMap { $0.tags ?? [] })).sorted() }
    private var ordered: [Patch] {
        if sort == "Name" { return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
        if sort == "Newest" { return filtered.sorted { ($0.activatedAt ?? $0.createdAt ?? "") > ($1.activatedAt ?? $1.createdAt ?? "") } }
        let lookup = Dictionary(uniqueKeysWithValues: filtered.map { ($0.id, $0) })
        return tiles.compactMap { lookup[$0.id] }
    }
    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $mode) {
                ForEach(["Quilt", "Map", "List"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8)
            HStack {
                Text("\(filtered.count) patches").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if !query.isEmpty || !tags.isEmpty { Button("Clear") { query = ""; tags = [] } }
                Button { filtering = true } label: { Label(tags.isEmpty ? "Filter" : "Filter (\(tags.count))", systemImage: "line.3.horizontal.decrease") }
            }.frame(minHeight: 44).padding(.horizontal).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            if loading { Spacer(); ProgressView("Loading quilt…"); Spacer() }
            else if let error { FailureView(message: error) { Task { await load() } } }
            else if filtered.isEmpty {
                ContentUnavailableView("No patches found", systemImage: "square.grid.2x2", description: Text("Try another search or clear your filters."))
            } else if mode == "Quilt" {
                QuiltCanvas(tiles: tiles, patches: filtered, fitRequest: fitRequest) { selected = $0 }
                    .overlay(alignment: .bottomTrailing) {
                        Button { fitRequest += 1 } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 20)).frame(width: 44, height: 44) }
                            .background(.regularMaterial, in: Circle()).padding().accessibilityLabel("Fit quilt")
                    }
            } else if mode == "Map" {
                if located.isEmpty { ContentUnavailableView("No locations to show", systemImage: "map", description: Text("These patches haven’t shared map coordinates.")) }
                else {
                    Map {
                        ForEach(located) { patch in
                            Annotation(patch.name, coordinate: CLLocationCoordinate2D(latitude: patch.latitude!, longitude: patch.longitude!)) {
                                Button { selected = patch } label: { Image(systemName: "mappin.circle.fill").font(.title).padding(6).background(.background, in: Circle()) }.accessibilityLabel(patch.name)
                            }
                        }
                    }.id(query + tags.sorted().joined(separator: ","))
                }
            } else {
                List {
                    Picker("Order", selection: $sort) { ForEach(["Quilt order", "Name", "Newest"], id: \.self) { Text($0) } }
                    ForEach(ordered) { patch in
                        Button { selected = patch } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(patch.name).font(.headline).foregroundStyle(.primary)
                                if let description = patch.description { Text(description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                            }.padding(.vertical, 6)
                        }.accessibilityIdentifier("patchRow")
                    }
                }.refreshable { await load() }
            }
        }
        .navigationTitle(quilt.name).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search patches")
        .onChange(of: query) { _, _ in repack() }
        .onChange(of: tags) { _, _ in repack() }
        .task { await load() }
        .sheet(item: $selected) { patch in
            NavigationStack {
                PatchDetail(quilt: quilt, initial: patch, close: { selected = nil })
            }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $filtering) {
            NavigationStack {
                List {
                    ForEach(allTags, id: \.self) { tag in
                        Button { if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) } } label: {
                            HStack { Text(tag); Spacer(); if tags.contains(tag) { Image(systemName: "checkmark") } }
                        }.accessibilityAddTraits(tags.contains(tag) ? .isSelected : [])
                    }
                    if !tags.isEmpty { Button("Clear filters") { tags = [] } }
                }.navigationTitle("Filter by interest")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { filtering = false } } }
            }
        }
    }
    private var located: [Patch] { filtered.filter { guard let lat = $0.latitude, let lon = $0.longitude else { return false }; return (-90...90).contains(lat) && (-180...180).contains(lon) } }
    private func repack() {
        let sizes = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0.size) })
        tiles = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && tags.isEmpty ? baseline : QuiltLayout.pack(filtered, affinity: affinity, sizes: sizes)
    }
    private func load() async {
        loading = patches.isEmpty; error = nil
        defer { loading = false }
        do {
            let result: TreeResponse = try await PatchworkAPI(base: quilt.url).get("nodes/tree")
            patches = result.tree.children ?? []; affinity = result.affinity ?? []
            baseline = QuiltLayout.pack(patches, affinity: affinity)
            repack()
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
