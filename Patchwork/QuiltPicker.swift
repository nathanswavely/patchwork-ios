// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct QuiltPicker: View {
    /// Quilts this one names as neighbours: doorways into their own inspect-and-confirm.
    var neighbors: [Instance.Neighbor] = []
    @EnvironmentObject private var store: QuiltStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var search = ""
    @State private var address = ""
    @State private var pending: Quilt?
    @State private var instance: Instance?
    @State private var busy = false
    @State private var error: String?
    private var choices: [Quilt] {
        let savedIDs = Set(store.saved.map(\.id))
        return (store.saved + Quilt.directory.filter { !savedIDs.contains($0.id) })
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        List {
            // One Group so every section's rows take the card surface: the
            // modifier does not reach them from the List itself.
            Group {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    QuiltMark()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Find your people.").font(Font.pw.title2)
                        Text("Choose a quilt to explore its patches and events. Each quilt is run by its own community.")
                            .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                    }
                }.padding(.vertical, 12)
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview") {
                Text("Design preview · fictional community data").font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
            }
            #endif
            Section {
                ForEach(choices) { quilt in
                    Button { Task { await inspect(quilt.url) } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(quilt.name).font(Font.pw.headline).foregroundStyle(Color.pwText)
                                Text(quilt.url.host() ?? quilt.id).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                        }.padding(.vertical, 6)
                    }.disabled(busy).accessibilityIdentifier("quiltChoice")
                }
                if choices.isEmpty {
                    Text("No matching quilts. You can connect by address below.")
                        .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                }
            } header: { heading("Quilts") }
            if !neighbors.isEmpty {
                Section {
                    ForEach(neighbors, id: \.url) { neighbor in
                        Button { Task { await inspectAddress(neighbor.url) } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(neighbor.name).font(Font.pw.headline).foregroundStyle(Color.pwText)
                                    Text(URL(string: neighbor.url)?.host() ?? neighbor.url).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.forward").font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                            }.padding(.vertical, 6)
                        }.disabled(busy)
                    }
                } header: { heading("Connected quilts") }
            }
            Section {
                TextField("community.example.org", text: $address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("Quilt address")
                    .onSubmit { Task { await inspectAddress() } }
                // A primary action, so the tint fills the control rather
                // than colouring the two words (DESIGN.md, Buttons).
                Button("Find quilt") { Task { await inspectAddress() } }
                    .font(Font.pw.headline)
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            } header: { heading("Have a quilt address?") }
              footer: { footnote("A quilt doesn’t need to be listed here for you to connect.") }
            if busy { ProgressView("Checking quilt…") }
            // `.red` stays: an error is a place the platform's own semantic
            // colour owns the meaning, and it is not the app's tint.
            if let error {
                Section { Text(error).font(Font.pw.subheadline).foregroundStyle(.red).accessibilityIdentifier("connectionError") }
            }
            Section {
                Link("View source code", destination: URL(string: "https://github.com/nathanswavely/patchwork-ios")!).exitLink()
                Link("Mozilla Public License 2.0", destination: URL(string: "https://www.mozilla.org/MPL/2.0/")!).exitLink()
            } header: { heading("Open source") }


            }.listRows()
        }
        .groundedList()
        .navigationTitle("Choose a quilt")
        .searchable(text: $search, prompt: "Find a quilt")
        .sheet(item: $pending) { quilt in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        QuiltMark()
                        Text(quilt.name).font(Font.pw.display)
                        Text(quilt.url.host() ?? quilt.id).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                        if let instance, !instance.description.isEmpty {
                            Text(instance.description).font(Font.pw.body).foregroundStyle(Color.pwText)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                }
                .background(Color.pwGround.ignoresSafeArea())
                .navigationTitle("About this quilt").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pending = nil } } }
                .safeAreaInset(edge: .bottom) {
                    Button("Explore quilt") {
                        pending = nil
                        store.connect(quilt)
                        dismiss()
                    }
                    .font(Font.pw.headline)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .accessibilityIdentifier("exploreQuilt")
                    .padding().frame(maxWidth: .infinity).background(.bar)
                }
            }
        }
        .toolbar {
            if store.selected != nil { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func heading(_ text: String) -> some View {
        Text(text).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
    }
    private func footnote(_ text: String) -> some View {
        Text(text).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted).textCase(nil)
    }
    private func inspectAddress(_ text: String? = nil) async {
        do { let url = try QuiltAddress.parse(text ?? address); await inspect(url) }
        catch { self.error = error.localizedDescription; pending = nil; instance = nil }
    }
    private func inspect(_ url: URL) async {
        busy = true; error = nil; pending = nil; instance = nil
        defer { busy = false }
        do {
            let info: Instance = try await PatchworkAPI(base: url).get("instance")
            guard !info.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.response }
            instance = info
            pending = Quilt(url: url, name: info.name)
        } catch { self.error = error.localizedDescription }
    }
}
