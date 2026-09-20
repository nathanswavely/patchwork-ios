// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// The people in a patch, as a patch publishes them (web ADR 006, ADR 095).
///
/// A signed-out reader is always outside the room, so the patch's own
/// `public_member_list` setting decides on its own: `everyone` lists members
/// and admins, `admins` lists only the admins and says so once above the list,
/// and `nobody` lists nobody. The counts stay public at every rung — the quilt
/// sizes this patch's tile by them — so the withheld state states the number
/// and says the list is not published. It never says there are no members.
struct PatchMemberList: View {
    let quilt: Quilt
    let slug: String
    var close: (() -> Void)? = nil
    @State private var roster = MemberRoster()
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    var body: some View {
        List {
            if loaded && !roster.withheld {
                Section {
                    ForEach(roster.members) { member in
                        PersonRow(name: member.name, initial: member.initial, avatar: member.avatar, role: member.role)
                            .accessibilityIdentifier("memberRow")
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 3) {
                        // The counts are the server's, never the loaded
                        // array's: the listing is paged, and counting what
                        // arrived would report the page size as the patch's
                        // size. On a patch where somebody has hidden their
                        // membership the count sits above a shorter list on
                        // purpose.
                        Text(roster.countLine)
                        if roster.adminsOnly {
                            // Said once, above the list: three rows under a
                            // count of forty otherwise reads as a bug.
                            Text("Only this patch’s admins are listed publicly.")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if let cursor = roster.cursor, !cursor.isEmpty {
                    Button("Load more") { Task { await load(after: cursor) } }.disabled(loading)
                }
            }
            if loading { ProgressView("Loading members…") }
            if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Try again") { Task { await load() } }
                }
            }
            Section {
                WebsiteOnlyNote(text: "Joining and following this patch happen on this quilt’s website.")
            }
        }
        .navigationTitle(roster.title).navigationBarTitleDisplayMode(.inline)
        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
        .overlay {
            if loaded && !loading && error == nil && (roster.withheld || roster.members.isEmpty) {
                ContentUnavailableView {
                    Label(roster.emptyTitle, systemImage: roster.withheld ? "eye.slash" : "person.2")
                } description: {
                    VStack(spacing: 6) {
                        Text(roster.emptyMessage)
                        if roster.withheld { Text(roster.countLine).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .task { if !loaded { await load() } }
        .refreshable { await load() }
    }
    private func load(after: String? = nil) async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false; loaded = true }
        do {
            let page: MemberPage = try await api.get("nodes/\(slug)/members", query: query(after: after))
            if after == nil { roster = MemberRoster(page: page) } else { roster.append(page) }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func query(after: String?) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: "50")]
        if let after, !after.isEmpty { items.append(URLQueryItem(name: "after", value: after)) }
        return items
    }
}
