// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// The first launch: pick the quilts you want, once. Every quilt ticked here
/// is saved, the first of them opens, and every later launch goes straight
/// back to the quilt used last — the switcher (hold the Quilt tab) moves
/// between them and its Find a quilt adds more.
///
/// Nothing is read from a quilt until the reader asks for it: a quilt typed
/// by address is checked when it is added, and the directory's quilts are
/// checked when Explore is pressed, so a launch still contacts only quilts
/// somebody chose.
struct QuiltOnboarding: View {
    @EnvironmentObject private var store: QuiltStore
    @Environment(\.colorScheme) private var colorScheme
    /// Quilts added by address, after the directory's own.
    @State private var added: [Quilt] = []
    @State private var picked: [String] = []
    @State private var address = ""
    @State private var busy = false
    @State private var error: String?
    private var choices: [Quilt] {
        let directory = Quilt.directory
        return directory + added.filter { quilt in !directory.contains { $0.id == quilt.id } }
    }
    private var chosen: [Quilt] { choices.filter { picked.contains($0.id) } }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        HStack(alignment: .top, spacing: 16) {
                            QuiltMark()
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Find your people.").font(Font.pw.title2)
                                Text("Pick the quilts you want to explore. Each quilt is run by its own community, and you can add more later.")
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
                        ForEach(choices) { quilt in choiceRow(quilt) }
                    } header: { heading("Quilts") }
                    Section {
                        TextField("community.example.org", text: $address)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityLabel("Quilt address")
                            .onSubmit { Task { await add() } }
                        Button("Find quilt") { Task { await add() } }
                            .font(Font.pw.headline)
                            .buttonStyle(.bordered)
                            .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                    } header: { heading("Have a quilt address?") }
                      footer: { footnote("A quilt doesn’t need to be listed here for you to connect.") }
                    if let error {
                        // `.red` stays: an error is a place the platform's own
                        // semantic colour owns the meaning.
                        Section { Text(error).font(Font.pw.subheadline).foregroundStyle(.red).accessibilityIdentifier("connectionError") }
                    }
                    Section {
                        Link("View source code", destination: URL(string: "https://github.com/nathanswavely/patchwork-ios")!).exitLink()
                        Link("Mozilla Public License 2.0", destination: URL(string: "https://www.mozilla.org/MPL/2.0/")!).exitLink()
                    } header: { heading("Open source") }
                }.listRows()
            }
            .groundedList()
            .navigationTitle("Choose your quilts")
            .safeAreaInset(edge: .bottom) {
                // The way on appears with the first pick, so nothing on the
                // screen is a button that cannot be pressed yet.
                if !picked.isEmpty {
                    Button { Task { await explore() } } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(colorScheme == .dark ? Color.black : Color.white) }
                            Text(chosen.count == 1 ? "Explore quilt" : "Explore \(chosen.count) quilts")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .font(Font.pw.headline)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .disabled(busy)
                    .accessibilityIdentifier("exploreQuilt")
                    .padding().background(.bar)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: picked.isEmpty)
        }
    }

    /// A quilt as a row that ticks: the name, its address, and a circle that
    /// fills when it is picked.
    private func choiceRow(_ quilt: Quilt) -> some View {
        let on = picked.contains(quilt.id)
        return Button {
            if on { picked.removeAll { $0 == quilt.id } } else { picked.append(quilt.id) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(quilt.name).font(Font.pw.headline).foregroundStyle(Color.pwText)
                    Text(quilt.url.host() ?? quilt.id).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(on ? Color.pwAccent : Color.pwTextMuted)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityIdentifier("quiltChoice")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A quilt by address is checked now, named by the quilt itself, and
    /// joins the list already picked.
    private func add() async {
        error = nil
        do {
            let url = try QuiltAddress.parse(address)
            busy = true
            defer { busy = false }
            let quilt = try await Self.check(url)
            if !choices.contains(where: { $0.id == quilt.id }) { added.append(quilt) }
            if !picked.contains(quilt.id) { picked.append(quilt.id) }
            address = ""
        } catch { self.error = error.localizedDescription }
    }

    /// Every picked quilt answers before any is saved, so a quilt that is down
    /// or is not a quilt never lands in the switcher. The names kept are the
    /// quilts' own.
    private func explore() async {
        error = nil
        busy = true
        defer { busy = false }
        var ready: [Quilt] = []
        for quilt in chosen {
            do { ready.append(try await Self.check(quilt.url)) }
            catch {
                self.error = "Couldn’t reach \(quilt.name). \(error.localizedDescription)"
                return
            }
        }
        store.adopt(ready)
    }

    private static func check(_ url: URL) async throws -> Quilt {
        let info: Instance = try await PatchworkAPI(base: url).get("instance")
        let name = info.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw APIError.response }
        return Quilt(url: url, name: name)
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
    }
    private func footnote(_ text: String) -> some View {
        Text(text).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted).textCase(nil)
    }
}
