// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// Notification preferences: the web's `NotificationPreferences.svelte`. One
// section per category the server lists, one row per type, a switch per
// channel the server offers. Saving sends only what changed — the web
// re-sends the whole matrix on every toggle, which writes a row for every
// type and so marks `quilt.bulletin` decided, silently retiring Discover's
// one-time offer of the monthly note (web ADR 076). This page must not.

// MARK: - The matrix, as the quilt serves it

/// `GET notifications/preferences`.
///
/// `channels` on each type is a JSON object keyed by channel name, and the
/// client's decoder rewrites dictionary keys along with property names —
/// `in_app` arrives as `inApp`. The map is therefore decoded as it comes and
/// then re-keyed against the channel list, whose names are values and come
/// through untouched. That keeps the server's own spelling everywhere this
/// client reads or writes a channel, whichever decoder read the payload.
struct NotificationPreferences: Decodable, Equatable {
    var channels: [String]
    var categories: [Category]

    struct Category: Decodable, Equatable, Identifiable {
        let id: String
        let label: String
        let description: String?
        var types: [Kind]
    }

    struct Kind: Decodable, Equatable, Identifiable {
        let type: String
        let label: String
        /// Keyed by the server's channel names once the whole payload is read.
        var channels: [String: Bool]
        /// Whether the reader has ever answered for this type, as opposed to
        /// sitting on its default.
        let decided: Bool?
        var id: String { type }
    }

    init(channels: [String], categories: [Category]) {
        self.channels = channels
        self.categories = categories
    }

    private enum CodingKeys: String, CodingKey { case channels, categories }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let channels = try container.decodeIfPresent([String].self, forKey: .channels) ?? ["in_app"]
        let categories = try container.decodeIfPresent([Category].self, forKey: .categories) ?? []
        self.channels = channels
        self.categories = categories.map { category in
            var category = category
            category.types = category.types.map { kind in
                var kind = kind
                kind.channels = Self.rekeyed(kind.channels, for: channels)
                return kind
            }
            return category
        }
    }

    /// The map keyed by the listed channel names, read under either spelling.
    /// A channel the server lists but a type left out reads as off; a key the
    /// server does not list is not this page's to show.
    static func rekeyed(_ map: [String: Bool], for channels: [String]) -> [String: Bool] {
        var out: [String: Bool] = [:]
        for channel in channels {
            out[channel] = map[channel] ?? map[camelCased(channel)] ?? false
        }
        return out
    }

    /// What `.convertFromSnakeCase` makes of a key: `in_app` → `inApp`.
    static func camelCased(_ key: String) -> String {
        let parts = key.split(separator: "_", omittingEmptySubsequences: true)
        guard let first = parts.first else { return key }
        return String(first) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined()
    }

    func isOn(_ type: String, _ channel: String) -> Bool {
        for category in categories {
            if let kind = category.types.first(where: { $0.type == type }) { return kind.channels[channel] ?? false }
        }
        return false
    }

    mutating func set(_ type: String, _ channel: String, _ on: Bool) {
        for c in categories.indices {
            for t in categories[c].types.indices where categories[c].types[t].type == type {
                categories[c].types[t].channels[channel] = on
            }
        }
    }

    /// Exactly the pairs that differ between what the quilt holds and what
    /// the page shows, in the page's order — and nothing else, so a type the
    /// reader never touched stays undecided.
    static func changes(from saved: Self, to shown: Self) -> [PreferenceChange] {
        var out: [PreferenceChange] = []
        for category in shown.categories {
            for kind in category.types {
                for channel in shown.channels {
                    let now = kind.channels[channel] ?? false
                    if now != saved.isOn(kind.type, channel) {
                        out.append(PreferenceChange(type: kind.type, channel: channel, enabled: now))
                    }
                }
            }
        }
        return out
    }

    mutating func apply(_ changes: [PreferenceChange]) {
        for change in changes { set(change.type, change.channel, change.enabled) }
    }

    /// A refused save, put back: each pair it carried returns to where it
    /// was — unless the reader has already moved it again, in which case
    /// their newer choice stands and goes with the next save.
    mutating func revert(_ changes: [PreferenceChange]) {
        for change in changes where isOn(change.type, change.channel) == change.enabled {
            set(change.type, change.channel, !change.enabled)
        }
    }

    /// The web's column words.
    static func channelLabel(_ channel: String) -> String {
        switch channel {
        case "in_app": return "In-app"
        case "email": return "Email"
        default: return channel
        }
    }
}

/// One row of the `PUT` body.
struct PreferenceChange: Codable, Equatable, Hashable {
    let type: String
    let channel: String
    let enabled: Bool
}

/// `PUT notifications/preferences`. The server upserts each row as sent.
struct PreferenceUpdate: Encodable { let preferences: [PreferenceChange] }

extension PatchworkAPI {
    func notificationPreferences() async throws -> NotificationPreferences { try await get("notifications/preferences") }
    func savePreferences(_ changes: [PreferenceChange]) async throws {
        try await sendVoid("PUT", "notifications/preferences", body: PreferenceUpdate(preferences: changes))
    }
}

// MARK: - Saving

/// The page's state: what the quilt holds (`saved`), what the page shows
/// (`shown`), and a short wait between the two so a run of toggles goes as
/// one write. A switch moves at once; a refusal moves it back.
@MainActor final class PreferencesModel: ObservableObject {
    @Published private(set) var shown: NotificationPreferences?
    @Published private(set) var failure: String?
    @Published private(set) var loadFailed = false
    private(set) var saved: NotificationPreferences?
    private var pending: Task<Void, Never>?
    var api: PatchworkAPI?
    var signedOut: @MainActor () -> Void = {}
    /// The web's debounce.
    var delay: UInt64 = 500_000_000

    func load() async {
        guard let api else { return }
        do {
            let answer = try await api.notificationPreferences()
            saved = answer
            shown = answer
            loadFailed = false
        } catch APIError.unauthenticated {
            signedOut()
        } catch {
            loadFailed = true
        }
    }

    func toggle(_ type: String, _ channel: String, _ on: Bool) {
        shown?.set(type, channel, on)
        failure = nil
        pending?.cancel()
        pending = Task { [weak self, delay] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// Send what changed, now. Called when the wait runs out and when the
    /// page goes, so leaving within the wait loses nothing.
    func flush() async {
        pending?.cancel()
        pending = nil
        guard let api, let shown, let saved else { return }
        let changes = NotificationPreferences.changes(from: saved, to: shown)
        guard !changes.isEmpty else { return }
        // Counted as held from here, so a second flush while this one is out
        // sends only what moved after it.
        self.saved?.apply(changes)
        do {
            try await api.savePreferences(changes)
        } catch APIError.unauthenticated {
            signedOut()
        } catch {
            self.saved?.revert(changes)
            self.shown?.revert(changes)
            failure = "Failed to save preferences"
        }
    }
}

// MARK: - The page

struct NotificationPreferencesView: View {
    @EnvironmentObject private var session: QuiltSession
    @StateObject private var model = PreferencesModel()

    var body: some View {
        List {
            Group {
                Section {
                    Text("Choose how you want to be notified about activity in your patches.")
                        .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                }
                if let failure = model.failure {
                    Section {
                        Label { Text(failure).font(Font.pw.footnote) } icon: {
                            Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
                        }
                        .foregroundStyle(Color.pwText)
                        .accessibilityIdentifier("preferencesError")
                    }
                }
                if let prefs = model.shown {
                    ForEach(prefs.categories) { category in
                        Section {
                            ForEach(category.types) { kind in row(kind, channels: prefs.channels) }
                        } header: {
                            settingsHeading(category.label)
                        } footer: {
                            if let description = category.description, !description.isEmpty { settingsFootnote(description) }
                        }
                    }
                } else if model.loadFailed {
                    Section {
                        Text("Failed to load preferences").font(Font.pw.footnote).foregroundStyle(Color.pwText)
                        Button { Task { await model.load() } } label: {
                            Text("Try again").font(Font.pw.body).inkAction("arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("preferencesRetry")
                    }
                } else {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                }
            }
            .listRows()
        }
        .groundedList()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.api = session.api
            let quilt = session
            model.signedOut = { [weak quilt] in quilt?.signedOut() }
            if model.shown == nil { await model.load() }
        }
        .onDisappear { Task { await model.flush() } }
    }

    /// One switch where the quilt offers one channel; the type's name over a
    /// switch per channel where it offers more.
    @ViewBuilder private func row(_ kind: NotificationPreferences.Kind, channels: [String]) -> some View {
        if channels.count == 1, let channel = channels.first {
            toggle(kind, channel: channel) { Text(kind.label).font(Font.pw.body) }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.label).font(Font.pw.body).foregroundStyle(Color.pwText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(channels, id: \.self) { channel in
                    toggle(kind, channel: channel) {
                        Text(NotificationPreferences.channelLabel(channel)).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func toggle<Label: View>(_ kind: NotificationPreferences.Kind, channel: String, @ViewBuilder label: () -> Label) -> some View {
        Toggle(isOn: Binding(
            get: { model.shown?.isOn(kind.type, channel) ?? false },
            set: { model.toggle(kind.type, channel, $0) }
        ), label: label)
        .tint(Color.pwAccent)
        .frame(minHeight: 36)
        .accessibilityLabel("\(kind.label), \(NotificationPreferences.channelLabel(channel))")
        .accessibilityIdentifier("preference-\(kind.type)-\(channel)")
    }
}
