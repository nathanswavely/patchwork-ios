// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct QuiltPicker: View {
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
            Section {
                HStack(alignment: .top, spacing: 16) {
                    QuiltMark()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Find your people.").font(.title2.bold())
                        Text("Choose a quilt to explore its patches and events. Each quilt is run by its own community.")
                            .foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 12)
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview") {
                Text("Design preview · fictional community data").font(.footnote).foregroundStyle(.secondary)
            }
            #endif
            Section("Quilts") {
                ForEach(choices) { quilt in
                    Button { Task { await inspect(quilt.url) } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(quilt.name).foregroundStyle(Color.primary)
                                Text(quilt.url.host() ?? quilt.id).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.padding(.vertical, 6)
                    }.disabled(busy).accessibilityIdentifier("quiltChoice")
                }
                if choices.isEmpty { Text("No matching quilts. You can connect by address below.").foregroundStyle(.secondary) }
            }
            Section {
                TextField("community.example.org", text: $address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("Quilt address")
                    .onSubmit { Task { await inspectAddress() } }
                Button("Find quilt") { Task { await inspectAddress() } }
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            } header: { Text("Have a quilt address?") }
              footer: { Text("A quilt doesn’t need to be listed here for you to connect.") }
            if busy { ProgressView("Checking quilt…") }
            if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("connectionError") } }
            Section("Open source") {
                Link("View source code", destination: URL(string: "https://github.com/nathanswavely/patchwork-ios")!)
                Link("Mozilla Public License 2.0", destination: URL(string: "https://www.mozilla.org/MPL/2.0/")!)
            }


        }
        .navigationTitle("Choose a quilt")
        .searchable(text: $search, prompt: "Find a quilt")
        .sheet(item: $pending) { quilt in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        QuiltMark()
                        Text(quilt.name).font(.largeTitle.bold())
                        Text(quilt.url.host() ?? quilt.id).foregroundStyle(.secondary)
                        if let instance, !instance.description.isEmpty { Text(instance.description) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                }
                .navigationTitle("About this quilt").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pending = nil } } }
                .safeAreaInset(edge: .bottom) {
                    Button("Explore quilt") {
                        pending = nil
                        store.connect(quilt)
                        dismiss()
                    }
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
    private func inspectAddress() async {
        do { let url = try QuiltAddress.parse(address); await inspect(url) }
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
