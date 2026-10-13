// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// A person, as a quilt publishes them (web `UserProfile`, ADR 006): who they
// are, where they have moved, the ways they can be reached by the people
// they organize with (ADR 083), their links, and the patches they run and
// belong to. Everything but the contact card is the same for every reader,
// the person themselves and the signed-out public included — a membership
// somebody hid is hidden from their own profile too.
//
// The values and the call live in this file; the screen is in
// `PersonProfile.swift`, and the doors to it are on every surface that
// carries a username.

// MARK: - The payload's parts

/// `GET users/{username}`. The server sends every field, an empty string
/// where there is nothing and an empty array where there are none, but each
/// is read as optional anyway, so a quilt a version behind is read rather
/// than refused.
struct Person: Decodable, Identifiable, Hashable {
    let id: String
    var username: String = ""
    var displayName: String = ""
    var bio: String = ""
    var avatarUrl: String = ""
    var links: [PatchLink] = []
    /// Where they went, if they went (web ADR 090). Empty is "not moved".
    var movedTo: String = ""
    var createdAt: String = ""
    var memberships: [PersonMembership] = []
    /// What they share with a patch this reader is also in. Always empty
    /// signed out, and empty across quilts, which are always read signed out.
    var contact: [ContactItem] = []

    init(id: String, username: String = "", displayName: String = "", bio: String = "", avatarUrl: String = "",
         links: [PatchLink] = [], movedTo: String = "", createdAt: String = "",
         memberships: [PersonMembership] = [], contact: [ContactItem] = []) {
        self.id = id; self.username = username; self.displayName = displayName; self.bio = bio
        self.avatarUrl = avatarUrl; self.links = links; self.movedTo = movedTo; self.createdAt = createdAt
        self.memberships = memberships; self.contact = contact
    }

    private enum CodingKeys: String, CodingKey {
        case id, username, displayName, bio, avatarUrl, links, movedTo, createdAt, memberships, contact
    }
    /// A link is `{url, label}` with the label allowed to be empty. A row
    /// missing either is read as empty rather than taking the whole profile
    /// down with it.
    private struct LooseLink: Decodable { let url: String?; let label: String? }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? "" }
        id = try c.decode(String.self, forKey: .id)
        username = text(.username); displayName = text(.displayName); bio = text(.bio)
        avatarUrl = text(.avatarUrl); movedTo = text(.movedTo); createdAt = text(.createdAt)
        links = (((try? c.decodeIfPresent([LooseLink].self, forKey: .links)) ?? nil) ?? [])
            .map { PatchLink(url: $0.url ?? "", label: $0.label ?? "") }
        memberships = ((try? c.decodeIfPresent([PersonMembership].self, forKey: .memberships)) ?? nil) ?? []
        contact = ((try? c.decodeIfPresent([ContactItem].self, forKey: .contact)) ?? nil) ?? []
    }

    /// What they filled in, or the handle — the web's `display_name || username`.
    var name: String {
        let display = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return display.isEmpty ? username : display
    }
    var initial: String { String((name.isEmpty ? "?" : name).prefix(1)).uppercased() }
    var avatar: URL? {
        guard let url = URL(string: avatarUrl.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }
    /// "@rowan · here since January 2026", or the handle alone where the
    /// date will not read.
    var handleLine: String {
        guard let since = People.month(createdAt) else { return "@" + username }
        return "@\(username) · here since \(since)"
    }
    /// The two halves of the contributor ladder, in the server's order
    /// (admins first, then by patch name). A role the web has no heading for
    /// is in neither.
    var runs: [PersonMembership] { memberships.filter { $0.role == "admin" } }
    var memberOf: [PersonMembership] { memberships.filter { $0.role == "member" } }
    /// The links that are links: an address this app will open.
    var openableLinks: [PersonLink] {
        links.compactMap { link in People.link(link).map { PersonLink(url: $0, title: People.linkTitle(link, url: $0)) } }
    }
    /// The web's empty state: no patches, no bio, no links. A contact card
    /// or a forwarding address on its own still leaves it "nothing here".
    var isEmpty: Bool {
        runs.isEmpty && memberOf.isEmpty
            && bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && links.isEmpty
    }
}

/// One of a person's links, as it is drawn: the address and what it says.
struct PersonLink: Hashable {
    let url: URL
    let title: String
}

/// One patch on a person's profile. The server lists only active, visible
/// admin and member rows on public, active patches; a follower, a pending
/// request, a hidden membership and a private patch never arrive.
struct PersonMembership: Decodable, Identifiable, Hashable {
    var nodeId: String = ""
    var nodeSlug: String = ""
    var nodeName: String = ""
    var role: String = ""
    var joinedAt: String = ""
    var id: String { nodeId.isEmpty ? nodeSlug : nodeId }

    init(nodeId: String = "", nodeSlug: String = "", nodeName: String = "", role: String = "", joinedAt: String = "") {
        self.nodeId = nodeId; self.nodeSlug = nodeSlug; self.nodeName = nodeName; self.role = role; self.joinedAt = joinedAt
    }
    private enum CodingKeys: String, CodingKey { case nodeId, nodeSlug, nodeName, role, joinedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? "" }
        nodeId = text(.nodeId); nodeSlug = text(.nodeSlug); nodeName = text(.nodeName)
        role = text(.role); joinedAt = text(.joinedAt)
    }
    var title: String { nodeName.isEmpty ? nodeSlug : nodeName }
}

// `ContactItem`, the one way to reach somebody, lives with the card that
// edits it in ContactCard.swift: the profile reads the same shape.

// MARK: - What the profile says

enum People {
    /// The username a door to somebody may be built from, or nothing.
    ///
    /// A deleted account is named "Deleted account" with a blank username,
    /// and a hidden member and a withheld chair are named with a blank one
    /// too — the server blanks it on purpose, because it is what a profile
    /// link is built from. So a blank username is never a door, whatever
    /// the name beside it says.
    static func door(_ username: String?) -> String? {
        let handle = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return handle.isEmpty ? nil : handle
    }

    /// "January 2026": the web's `formatMonth`, a long month and the year.
    static func month(_ stamp: String) -> String? {
        guard let date = ProfileDate.parse(stamp) else { return nil }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM y")
        return formatter.string(from: date)
    }

    /// The contact card's heading and its one sentence (web `UserProfile`).
    /// The sentence is about why the reader can see it, which is different
    /// for the person themselves.
    static func reachHeading(_ name: String) -> String { "Reach \(name)" }
    static func reachExplanation(isSelf: Bool) -> String {
        isSelf
            ? "What the people you organize with can see. Each item is here because you gave it to a patch you share with them."
            : "Shared with people they organize with. You can see this because you are in a patch they gave it to."
    }

    static let emptyLine = "Nothing here yet."
    /// Said only to the person themselves, under the empty state.
    static let hiddenHint = "Memberships you’ve hidden don’t appear on your profile. Manage them in Settings."
    static let notFoundTitle = "Person not found"

    /// Where a person went, and the host to name — only where the address is
    /// one this app would open (web `MovedNotice`).
    static func moved(_ raw: String) -> (url: URL, host: String)? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), !host.isEmpty else { return nil }
        return (url, bareHost(host))
    }
    static func movedLine(_ host: String) -> String { "This person has moved to \(host)." }

    /// Where a report about a person goes. A person belongs to no one patch,
    /// so unlike a notice or a reply the report has no patch's admins to go
    /// to: it is the quilt's own admins who read it.
    static let reportDestination = "Reports go to the instance admins, who review them against the community lining."

    // MARK: Links

    /// The address in a link, or nothing. The web hands `url` to an anchor
    /// as it is; this client opens only what is plainly a web address.
    static func link(_ link: PatchLink) -> URL? {
        guard let url = URL(string: link.url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), !host.isEmpty else { return nil }
        return url
    }

    /// The label, or the host without its `www.` (web `extractDomain`).
    static func linkTitle(_ link: PatchLink, url: URL) -> String {
        let label = link.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }
        return bareHost(url.host() ?? link.url)
    }

    static func bareHost(_ host: String) -> String {
        host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// An address's characters, kept as they are in a `mailto:`. Anything
    /// else — a space somebody typed — is escaped rather than refused.
    static let mailtoAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@.-_+!#$&'*/=?^`{|}~"))
}

// MARK: - The call

extension PatchworkAPI {
    /// Sign-in optional: the same read for everybody, with the contact card
    /// filled only for a signed-in reader who shares a patch with them.
    func person(_ username: String) async throws -> Person { try await get("users/\(username)") }
}

// MARK: - Where a person's patches open

/// How a patch named on somebody's profile is opened, set by whoever
/// presented the screen. A patch's profile docks over the quilt, and a
/// sheet cannot be docked under while another sheet is still up — so the
/// notifications sheet and the quilt's information stack close themselves
/// first, and say so here. Where nothing is set the screen docks the patch
/// itself, which is right inside a docked profile's own rooms and on a tab's
/// own stack.
private struct PatchDoorKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var patchDoor: ((String) -> Void)? {
        get { self[PatchDoorKey.self] }
        set { self[PatchDoorKey.self] = newValue }
    }
}

// MARK: - A name that opens a person

/// A name in running text — a candidate on a slate, the author of a notice
/// or a reply — that opens the person it names: ink, with the platform's
/// chevron hugging it, the house's text door. Where there is no username to
/// open (a deleted account, a hidden member) it is the same name, inert.
struct PersonName: View {
    let name: String
    let username: String?
    var font: Font = Font.pw.subheadlineSemibold
    /// The colour the name keeps where it is not a door.
    var inert: Color = .pwText
    let open: (String) -> Void

    var body: some View {
        if let handle = People.door(username) {
            Button { open(handle) } label: {
                Text(name).font(font).multilineTextAlignment(.leading).inkRow(fills: false)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityHint("Opens their profile")
            .accessibilityIdentifier("personDoor-\(handle)")
        } else {
            Text(name).font(font).foregroundStyle(inert)
        }
    }
}

extension View {
    /// The push a `PersonName` asks for, hung once on the screen itself:
    /// names live inside list rows, and a destination inside a lazy row is
    /// ignored.
    func personDestination(_ username: Binding<String?>, quilt: Quilt, close: (() -> Void)? = nil) -> some View {
        navigationDestination(item: username) { PersonProfile(quilt: quilt, username: $0, close: close) }
    }
}
