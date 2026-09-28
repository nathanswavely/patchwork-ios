// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// Account settings, drilled the way the web's settings are on a phone (web
// PR #363): one level on screen at a time — an index of sections, each
// opening its own page, one way back — with the rare sections last, and
// deletion last of all, on its own page, in red.

// MARK: - What a save sends, as a value

/// The body of `PATCH auth/me`: only the fields being saved. Every property
/// is optional and the synthesised encoding leaves a nil one out entirely,
/// which is what the server reads as "leave this alone" — a field sent empty
/// would be a field cleared.
struct AccountChanges: Encodable, Equatable {
    var displayName: String?
    var bio: String?
    var links: [PatchLink]?
    var startOnMyQuilt: Bool?
    var hideAmendedLinings: Bool?
}

/// The Profile page's fields, held apart from the account until Save.
struct ProfileDraft: Equatable {
    /// One link being edited. The id is the row's, not the link's, so two
    /// empty rows are still two rows.
    struct Row: Identifiable, Equatable {
        let id: UUID
        var label: String
        var url: String
        init(id: UUID = UUID(), label: String = "", url: String = "") { self.id = id; self.label = label; self.url = url }
    }
    var displayName: String
    var bio: String
    var links: [Row]

    init(user: User) {
        displayName = user.displayName ?? ""
        bio = user.bio ?? ""
        links = (user.links ?? []).map { Row(label: $0.label, url: $0.url) }
    }

    /// The links as they are saved: trimmed, and a row with no address left
    /// out — a label with nowhere to go is not a link (the web drops it too).
    static func cleaned(_ rows: [Row]) -> [PatchLink] {
        rows.map { PatchLink(url: $0.url.trimmingCharacters(in: .whitespacesAndNewlines),
                             label: $0.label.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.url.isEmpty }
    }

    /// What Save sends: each field only if it differs from what the account
    /// already says, or nothing at all. Sending the untouched ones as well
    /// would race another device's edit to the same account for no reason.
    func changes(from user: User) -> AccountChanges? {
        var changes = AccountChanges()
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name != (user.displayName ?? "") { changes.displayName = name }
        let about = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        if about != (user.bio ?? "") { changes.bio = about }
        let saved = Self.cleaned(links)
        if saved != (user.links ?? []) { changes.links = saved }
        return changes == AccountChanges() ? nil : changes
    }
}

/// One signed-in session, from `GET auth/sessions` (web `SessionInfo`).
struct AccountSession: Decodable, Identifiable, Equatable {
    let id: String
    /// A coarse device label the server derives from the user agent.
    let label: String?
    let createdAt: String?
    let lastUsedAt: String?
    let current: Bool?
    var isCurrent: Bool { current == true }
}

/// The two ways the server writes a session's times — an RFC 3339 instant,
/// or SQLite's own `YYYY-MM-DD HH:MM:SS` in UTC — read into one date.
enum AccountDate {
    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = PatchworkEvent.parseDate(value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss.SSS"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
    /// "Active 3h ago · Signed in 12 Sep 2026", with whichever half is known.
    static func sessionLine(_ session: AccountSession, now: Date = Date()) -> String {
        var parts: [String] = []
        if let used = parse(session.lastUsedAt) {
            let iso = ISO8601DateFormatter().string(from: used)
            let ago = NotificationTime.ago(iso, now: now)
            if !ago.isEmpty { parts.append(ago == "just now" ? "Active just now" : "Active \(ago)") }
        }
        if let created = parse(session.createdAt) {
            parts.append("Signed in \(created.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }
}

/// What deletion answers with, and what a refusal of it means.
struct DeletionAnswer: Decodable { let status: String? }

extension PatchworkAPI {
    /// `PATCH auth/me` with only the fields being saved; the answer is the user.
    @discardableResult func updateAccount(_ changes: AccountChanges) async throws -> User {
        let response: SignInResponse = try await patch("auth/me", body: changes)
        guard let user = response.user else { throw APIError.response }
        return user
    }
    func sessions() async throws -> [AccountSession] { try await get("auth/sessions") }
    func revokeOtherSessions() async throws { try await postVoid("auth/sessions/revoke-others") }
    func revokeSession(_ id: String) async throws { try await deleteVoid("auth/sessions/\(id)") }
    /// `DELETE users/me`, confirmed by the username typed out. Step-up gated
    /// on the server; the caller wraps it in a `StepUpGate`.
    func deleteAccount(confirmUsername: String) async throws -> DeletionAnswer {
        try await delete("users/me", body: ["confirm_username": confirmUsername])
    }
}

// MARK: - The sheet

/// How the reader left Settings, acted on by whoever presented it once the
/// sheet has gone: docking a patch or saying goodbye both need the quilt
/// underneath, and a sheet cannot present over a sheet that is leaving.
enum SettingsExit: Equatable {
    /// The account is gone; the cookie already is.
    case deleted
    /// The Confirm sheet's "sign out, then back in with a code".
    case signOut
    /// A patch named in a refusal: dock it on the quilt.
    case dock(String)
}

struct SettingsSheet: View {
    let onExit: (SettingsExit) -> Void
    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            SettingsIndex(onExit: onExit)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        // Signed out from anywhere — a 401 on any page — there are no
        // settings left to show.
        .onChange(of: session.me == nil) { _, gone in if gone { dismiss() } }
    }
}

/// The index: who you are, the sections as rows, and deletion alone at the foot.
struct SettingsIndex: View {
    let onExit: (SettingsExit) -> Void
    @EnvironmentObject private var session: QuiltSession
    var body: some View {
        List {
            Group {
                if let me = session.me {
                    Section {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(me.title).font(Font.pw.headline).foregroundStyle(Color.pwText)
                            Text("\(me.handle) on \(session.instance?.name ?? session.quilt.name)")
                                .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                }
                Section {
                    row("Profile", detail: "Name, bio and links", symbol: "person.crop.circle", id: "settingsProfile") { ProfileSettings() }
                    row("When you open Patchwork", detail: (session.me?.startOnMyQuilt == true) ? "My Quilt" : "The whole quilt",
                        symbol: "house", id: "settingsLanding") { LandingSettings() }
                    row("Discovery", detail: (session.me?.hideAmendedLinings == true) ? "Hiding amended linings" : "Showing every patch",
                        symbol: "eye", id: "settingsDiscovery") { DiscoverySettings() }
                    row("Security", detail: "Recovery codes and devices", symbol: "lock", id: "settingsSecurity") { SecuritySettings() }
                    row("Your data", detail: "Download or take a copy", symbol: "square.and.arrow.down", id: "settingsData") { YourDataSettings() }
                }
                // Last, alone, and red: the one thing on this list that cannot
                // be taken back. It opens a page rather than acting from here.
                Section {
                    NavigationLink { DeleteAccountSettings(onExit: onExit) } label: {
                        Label("Delete account", systemImage: "trash")
                            .font(Font.pw.body)
                            .foregroundStyle(Color(.systemRed))
                    }
                    .accessibilityIdentifier("settingsDelete")
                }
            }
            .listRows()
        }
        .groundedList()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row<Destination: View>(_ title: String, detail: String, symbol: String, id: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Font.pw.body).foregroundStyle(Color.pwText)
                    Text(detail).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                }
            } icon: {
                Image(systemName: symbol).foregroundStyle(Color.pwTextMuted)
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier(id)
    }
}

// MARK: - Parts every page uses

private func settingsHeading(_ text: String) -> some View {
    Text(text).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
}

private func settingsFootnote(_ text: String) -> some View {
    Text(text).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted).textCase(nil)
}

/// A refusal's sentence starts where a sentence starts: the server writes
/// them lowercase for the web to place mid-toast.
private func sentenceCased(_ text: String) -> String {
    guard let first = text.first else { return text }
    return first.uppercased() + text.dropFirst()
}

// MARK: - Profile

struct ProfileSettings: View {
    @EnvironmentObject private var session: QuiltSession
    @Environment(\.openURL) private var openURL
    @State private var draft: ProfileDraft?
    @State private var saving = false
    @State private var failure: String?
    @State private var saved = false

    private var changes: AccountChanges? {
        guard let draft, let me = session.me else { return nil }
        return draft.changes(from: me)
    }

    var body: some View {
        List {
            Group {
                if let me = session.me {
                    Section {
                        HStack {
                            Text(me.handle).font(Font.pw.body).foregroundStyle(Color.pwText)
                            Spacer(minLength: 0)
                        }
                        Link(destination: session.api.webURL("users/\(me.username)")) {
                            Text("View public profile").font(Font.pw.body)
                        }
                        .exitLink()
                        .accessibilityIdentifier("profilePublicLink")
                    } header: {
                        settingsHeading("Username")
                    } footer: {
                        settingsFootnote("Your username can’t be changed. Your public profile shows your name, bio, links and the memberships you keep visible.")
                    }
                }
                if draft != nil {
                    Section {
                        TextField("How you want to be listed", text: binding(\.displayName))
                            .textContentType(.name)
                            .accessibilityIdentifier("profileDisplayName")
                    } header: { settingsHeading("Display name") }
                    Section {
                        TextField("A line or two about you", text: binding(\.bio), axis: .vertical)
                            .lineLimit(3...8)
                            .accessibilityIdentifier("profileBio")
                    } header: { settingsHeading("Bio") }
                    Section {
                        ForEach(Array((draft?.links ?? []).enumerated()), id: \.element.id) { index, row in
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Label", text: linkBinding(row.id, \.label))
                                    .accessibilityIdentifier("profileLinkLabel")
                                TextField(text: linkBinding(row.id, \.url), prompt: Text(verbatim: "https://…")) { Text("Address") }
                                    .keyboardType(.URL)
                                    .textContentType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityIdentifier("profileLinkURL")
                                // Below the link it removes, not squeezed beside it.
                                Button { draft?.links.removeAll { $0.id == row.id } } label: {
                                    Text("Remove link").font(Font.pw.footnote).inkAction("minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove link \(index + 1)")
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { offsets in draft?.links.remove(atOffsets: offsets) }
                        Button { draft?.links.append(ProfileDraft.Row()) } label: {
                            Text("Add link").font(Font.pw.body).inkAction("plus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("profileAddLink")
                    } header: {
                        settingsHeading("Links")
                    } footer: {
                        settingsFootnote("A link with no address is left out when you save.")
                    }
                }
                if let failure {
                    Section { Text(failure).font(Font.pw.footnote).foregroundStyle(Color.pwText) }
                } else if saved {
                    Section {
                        Label("Saved", systemImage: "checkmark").font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                            .accessibilityIdentifier("profileSaved")
                    }
                }
            }
            .listRows()
        }
        .groundedList()
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Save rides the bar, so the decision is always within reach
            // however long the links run.
            ToolbarItem(placement: .confirmationAction) {
                if saving { ProgressView() } else {
                    Button("Save") { Task { await save() } }
                        .disabled(changes == nil)
                        .accessibilityIdentifier("profileSave")
                }
            }
        }
        .onAppear { if draft == nil, let me = session.me { draft = ProfileDraft(user: me) } }
        .onChange(of: draft) { _, _ in saved = false; failure = nil }
    }

    private func binding(_ key: WritableKeyPath<ProfileDraft, String>) -> Binding<String> {
        Binding(get: { draft?[keyPath: key] ?? "" }, set: { draft?[keyPath: key] = $0 })
    }

    private func linkBinding(_ id: UUID, _ key: WritableKeyPath<ProfileDraft.Row, String>) -> Binding<String> {
        Binding(
            get: { draft?.links.first { $0.id == id }?[keyPath: key] ?? "" },
            set: { value in
                guard let index = draft?.links.firstIndex(where: { $0.id == id }) else { return }
                draft?.links[index][keyPath: key] = value
            }
        )
    }

    private func save() async {
        guard let changes else { return }
        saving = true
        failure = nil
        defer { saving = false }
        do {
            try await session.api.updateAccount(changes)
            // Read the account back rather than trusting the draft: the menu,
            // the index and this page then all say what the quilt now holds.
            await session.refreshAccount()
            if let me = session.me { draft = ProfileDraft(user: me) }
            saved = true
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            failure = SignInModel.sentence(error)
        }
    }
}

// MARK: - The two switches

/// One switch saved the moment it moves, the way the web saves it: a single
/// toggle does not need a Save button. A refusal puts it back.
private struct AccountSwitch: View {
    let title: String
    let heading: String
    let footer: String
    let identifier: String
    let read: (User) -> Bool
    let changes: (Bool) -> AccountChanges
    var after: (() async -> Void)? = nil
    @EnvironmentObject private var session: QuiltSession
    @State private var on = false
    @State private var saving = false
    @State private var failure: String?

    var body: some View {
        List {
            Group {
                Section {
                    Toggle(isOn: Binding(get: { on }, set: { value in on = value; Task { await save(value) } })) {
                        Text(title).font(Font.pw.body)
                    }
                    .tint(Color.pwAccent)
                    .disabled(saving)
                    .accessibilityIdentifier(identifier)
                    if let failure { Text(failure).font(Font.pw.footnote).foregroundStyle(Color.pwText) }
                } header: {
                    settingsHeading(heading)
                } footer: {
                    settingsFootnote(footer)
                }
            }
            .listRows()
        }
        .groundedList()
        .onAppear { on = session.me.map(read) ?? false }
    }

    private func save(_ value: Bool) async {
        saving = true
        failure = nil
        defer { saving = false }
        do {
            try await session.api.updateAccount(changes(value))
            await session.refreshAccount()
            await after?()
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            on = !value
            failure = SignInModel.sentence(error)
        }
    }
}

/// Web ADR 035: the preference fires once, at a cold launch, and never
/// re-asserts — so moving it here changes the next launch, not this one.
struct LandingSettings: View {
    var body: some View {
        AccountSwitch(
            title: "Start on My Quilt",
            heading: "When you open Patchwork",
            footer: "Patchwork opens on the whole quilt. Switch this on to start on My Quilt instead, from the next time the app opens. You can still switch lens whenever you like.",
            identifier: "startOnMyQuilt",
            read: { $0.startOnMyQuilt == true },
            changes: { AccountChanges(startOnMyQuilt: $0) }
        )
        .navigationTitle("When you open Patchwork")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Web ADR 037's personal filter. The server applies it to the tree, so the
/// quilt is read again once it is saved; the whole tree too, since Discover
/// and search read it even while My Quilt is on.
struct DiscoverySettings: View {
    @EnvironmentObject private var session: QuiltSession
    var body: some View {
        AccountSwitch(
            title: "Hide patches with amended linings",
            heading: "Discovery",
            footer: "Keeps patches that changed the shared community standards out of your quilt, search, map and event feed. Direct links still work. If this quilt already hides them for everyone, this can only hide more, never less.",
            identifier: "hideAmendedLinings",
            read: { $0.hideAmendedLinings == true },
            changes: { AccountChanges(hideAmendedLinings: $0) },
            after: { await session.loadTree(refreshingWhole: true) }
        )
        .navigationTitle("Discovery")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Security

struct SecuritySettings: View {
    @EnvironmentObject private var session: QuiltSession
    @State private var sessions: [AccountSession]?
    @State private var failure: String?
    @State private var confirmOthers = false
    @State private var busy = false

    var body: some View {
        List {
            Group {
                RecoveryCodesSection(api: session.api)
                Section {
                    if let sessions {
                        ForEach(sessions) { row in sessionRow(row) }
                        if sessions.contains(where: { !$0.isCurrent }) {
                            Button(role: .destructive) { confirmOthers = true } label: {
                                Text("Sign out other devices").font(Font.pw.body)
                            }
                            .disabled(busy)
                            .accessibilityIdentifier("sessionsSignOutOthers")
                            .confirmationDialog("Sign out every other device?", isPresented: $confirmOthers, titleVisibility: .visible) {
                                Button("Sign out other devices", role: .destructive) { Task { await signOutOthers() } }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("This device stays signed in.")
                            }
                        }
                    } else if failure == nil {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    if let failure { Text(failure).font(Font.pw.footnote).foregroundStyle(Color.pwText) }
                } header: {
                    settingsHeading("Signed-in devices")
                } footer: {
                    settingsFootnote("Where you’re signed in to this quilt. Sign out any you don’t recognise.")
                }
                Section {
                    Text("This app doesn’t use passkeys yet. Signing in by emailed code works everywhere, and a recovery code confirms anything a passkey would.")
                        .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                        .accessibilityIdentifier("passkeysNote")
                } header: {
                    settingsHeading("Passkeys")
                }
            }
            .listRows()
        }
        .groundedList()
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSessions() }
        .refreshable { await loadSessions() }
    }

    private func sessionRow(_ row: AccountSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(row.label?.isEmpty == false ? row.label! : "Unknown device").font(Font.pw.body).foregroundStyle(Color.pwText)
                if row.isCurrent {
                    Text("This device")
                        .font(Font.pw.caption2Semibold).foregroundStyle(Color.pwTextMuted)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(Color.pwBorder, lineWidth: 1))
                        .accessibilityIdentifier("sessionThisDevice")
                }
            }
            let line = AccountDate.sessionLine(row)
            if !line.isEmpty { Text(line).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted) }
            // This one is signing out *here*: that is the account menu's job,
            // not a row's.
            if !row.isCurrent {
                Button { Task { await revoke(row) } } label: {
                    Text("Sign out").font(Font.pw.footnote).inkAction("xmark.circle")
                }
                .buttonStyle(.borderless)
                .disabled(busy)
                .accessibilityIdentifier("sessionSignOut")
            }
        }
        .padding(.vertical, 2)
        .swipeActions {
            if !row.isCurrent {
                Button(role: .destructive) { Task { await revoke(row) } } label: { Label("Sign out", systemImage: "xmark") }
            }
        }
    }

    private func loadSessions() async {
        do { sessions = try await session.api.sessions(); failure = nil }
        catch APIError.unauthenticated { session.signedOut() }
        catch { failure = SignInModel.sentence(error) }
    }

    private func revoke(_ row: AccountSession) async {
        busy = true
        defer { busy = false }
        do {
            try await session.api.revokeSession(row.id)
            sessions?.removeAll { $0.id == row.id }
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            failure = SignInModel.sentence(error)
        }
    }

    private func signOutOthers() async {
        busy = true
        defer { busy = false }
        do {
            try await session.api.revokeOtherSessions()
            sessions = sessions?.filter(\.isCurrent)
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            failure = SignInModel.sentence(error)
        }
    }
}

// MARK: - Your data

struct YourDataSettings: View {
    @EnvironmentObject private var session: QuiltSession
    private struct TakenFile: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }
    @State private var file: TakenFile?
    @State private var fetching: String?
    @State private var failure: String?

    var body: some View {
        List {
            Group {
                Section {
                    Text("One file with everything this quilt holds about you: your profile, memberships, what you wrote and your settings. Nothing anyone else wrote, and nothing that could sign you in.")
                        .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    take("Download my data", path: "users/me/export", fallback: "patchwork-my-data.json", id: "dataExport")
                } header: { settingsHeading("Download my data") }
                Section {
                    Text("A copy of this quilt as you can see it, in the format a new Patchwork reads, so a community can start again elsewhere without waiting for an admin. No email addresses, contact cards or noticeboards.")
                        .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    take("Take a copy", path: "users/me/seamrip", fallback: "patchwork-member-seamrip.zip", id: "dataSeamrip")
                } header: { settingsHeading("Member seamrip") }
                if let failure {
                    Section { Text(failure).font(Font.pw.footnote).foregroundStyle(Color.pwText) }
                }
            }
            .listRows()
        }
        .groundedList()
        .navigationTitle("Your data")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $file) { file in ActivitySheet(url: file.url).ignoresSafeArea() }
    }

    private func take(_ title: String, path: String, fallback: String, id: String) -> some View {
        Button { Task { await fetch(path, fallback: fallback) } } label: {
            HStack(spacing: 8) {
                Text(title).font(Font.pw.body).foregroundStyle(Color.pwText)
                Spacer(minLength: 0)
                if fetching == path { ProgressView() } else {
                    Image(systemName: "square.and.arrow.up").foregroundStyle(Color.pwTextMuted)
                }
            }
        }
        .disabled(fetching != nil)
        .accessibilityIdentifier(id)
    }

    /// Fetched into a folder of its own under the app's temporary directory,
    /// named as the quilt named it, and handed to the share sheet — Save to
    /// Files is the download, and anything else the reader wants is one
    /// more choice on the same sheet.
    private func fetch(_ path: String, fallback: String) async {
        fetching = path
        failure = nil
        defer { fetching = nil }
        do {
            let download = try await session.api.download(path)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(download.filename ?? fallback)
            try download.data.write(to: url, options: .atomic)
            file = TakenFile(url: url)
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            failure = SignInModel.sentence(error)
        }
    }
}

// MARK: - Delete account

/// Web ADR 086: erase the person, keep the acts. Its own page, reached last,
/// with what goes and what stays said before the field that confirms it.
struct DeleteAccountSettings: View {
    let onExit: (SettingsExit) -> Void
    @EnvironmentObject private var session: QuiltSession
    @StateObject private var gate = StepUpGate()
    @State private var typed = ""
    @State private var asking = false
    @State private var deleting = false
    @State private var failure: String?
    @State private var blockers: [Refusal.PatchRef] = []

    private var username: String { session.me?.username ?? "" }
    private var matches: Bool { !username.isEmpty && typed == username }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("This happens at once and cannot be undone.")
                    .font(Font.pw.headline).foregroundStyle(Color.pwText)
                paragraph("Erased", "your name, email address, bio, links and contact card; every membership you hold; your notifications; your sessions and recovery codes.")
                paragraph("Kept", "your votes, proposals and posts, shown as “Deleted account” with no name and no link. A record that loses a voter is not a record.")
                paragraph("Retired", "your username. Nobody can register \(username.isEmpty ? "it" : "@" + username) again, so links meant for you never reach somebody else.")
                Text("Copies that already went to other servers, or out in an export you took before today, are beyond this quilt’s reach.")
                    .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                if !blockers.isEmpty { blockerList }
                Divider().padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    (Text("Type your username to confirm: ").font(Font.pw.subheadline) + Text(verbatim: username).font(Font.pw.subheadlineSemibold))
                        .foregroundStyle(Color.pwText)
                    TextField(text: $typed, prompt: Text(verbatim: username)) { Text("Username") }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .fieldStyle()
                        .accessibilityIdentifier("deleteConfirmField")
                        .onChange(of: typed) { _, _ in failure = nil }
                }
                if let failure {
                    Label { Text(failure).font(Font.pw.footnote) } icon: {
                        Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
                    }
                    .foregroundStyle(Color.pwText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("deleteError")
                }
                Button(role: .destructive) { asking = true } label: {
                    Group {
                        if deleting { ProgressView().tint(.white) } else { Text("Delete my account").font(Font.pw.headline) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .foregroundStyle(matches ? Color.white : Color.pwTextMuted)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(.systemRed))
                .controlSize(.large)
                .disabled(!matches || deleting)
                .accessibilityIdentifier("deleteAccount")
                .confirmationDialog("Delete your account?", isPresented: $asking, titleVisibility: .visible) {
                    Button("Delete my account", role: .destructive) { Task { await delete() } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You will be signed out, and this cannot be undone.")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.pwGround.ignoresSafeArea())
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .stepUpSheet(gate, api: session.api)
    }

    private func paragraph(_ lead: String, _ rest: String) -> some View {
        // Each run carries its own face: `.bold()` on a run with no font of
        // its own falls back to the system's, a size smaller than the rest.
        (Text(lead + ": ").font(Font.pw.bodyBold) + Text(rest).font(Font.pw.body))
            .foregroundStyle(Color.pwText)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The patches in the way, each a door to the patch itself, where the
    /// handover happens.
    private var blockerList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hand these patches to somebody else first — you are their only admin.")
                .font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwText)
                .accessibilityIdentifier("deleteSoleAdmin")
            ForEach(blockers, id: \.slug) { patch in
                Button { onExit(.dock(patch.slug)) } label: {
                    Text(patch.name).font(Font.pw.body)
                }
                .buttonStyle(.plain)
                .inkRow()
                .frame(minHeight: 44)
                .accessibilityIdentifier("deleteBlocker")
            }
            Text("Name a successor, promote another admin, or hold an election, then come back.")
                .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
        }
        .cardSurface()
    }

    private func delete() async {
        deleting = true
        failure = nil
        blockers = []
        defer { deleting = false }
        let confirm = typed
        do {
            _ = try await gate.run { try await session.api.deleteAccount(confirmUsername: confirm) }
            // The server cleared its cookie; forget this quilt's copy too.
            // Signing the session out waits for the sheet to go (see
            // `SettingsExit`), so the Dashboard is not pulled out from under it.
            session.api.clearSession()
            onExit(.deleted)
        } catch is StepUpGate.SignOutRequested {
            onExit(.signOut)
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch let error as APIError {
            switch error.code {
            case "sole_admin":
                if case .refused(let refusal, _) = error { blockers = refusal.patches ?? [] }
                if blockers.isEmpty { failure = sentenceCased(error.errorDescription ?? "") }
            case "last_instance_admin":
                failure = sentenceCased(error.errorDescription ?? "")
            case let code? where StepUp.refusalCodes.contains(code):
                // Confirmed, and still asked: say so rather than loop.
                failure = "The quilt still asked for confirmation. Try again in a moment."
            default:
                failure = sentenceCased(SignInModel.sentence(error))
            }
        } catch {
            failure = SignInModel.sentence(error)
        }
    }
}
