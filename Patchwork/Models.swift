// SPDX-License-Identifier: MPL-2.0

import Foundation

struct Quilt: Codable, Identifiable, Hashable {
    var url: URL
    var name: String
    var id: String { url.absoluteString }
    static var directory: [Quilt] {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") {
            return [Quilt(url: URL(string: "https://quilt.example.org")!, name: "Sample quilt")]
        }
        #endif
        return [Quilt(url: URL(string: "https://lancasterpatchwork.org")!, name: "Lancaster Patchwork")]
    }
}

struct Instance: Decodable {
    let name: String
    let description: String
    let geography: Geography
    let neighborQuilts: [Neighbor]?
    let modules: [String: Bool]?
    struct Geography: Decodable { let timezone: String? }
    struct Neighbor: Decodable { let name: String; let url: String }
}

struct Patch: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String
    let description: String?
    let tags: [String]?
    let memberCount: Int?
    let followerCount: Int?
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let eventCount: Int?
    let upcomingEventCount: Int?
    let isUnclaimed: Bool?
    let status: String?
    let imageUrl: String?
    let imageAlt: String?
    let website: String?
    let links: [PatchLink]?
    let activatedAt: String?
    let createdAt: String?
    let appearance: Appearance?
    var communityListing: Bool { isUnclaimed == true || status == "unclaimed" }
}

/// What a patch chose for its tile — palette, block, rotation, bundle, motif —
/// as one concept (docs/adr/004). Every key is optional and every value is
/// opaque until a registry recognises it; an unknown key falls back to the
/// hash-assigned tile rather than erroring, so a foreign quilt's custom
/// palette degrades instead of breaking the quilt.
struct Appearance: Decodable, Hashable {
    let palette: String?
    let block: Block?
    let rotation: Int?
    let bundle: [String]?
    let icon: String?
    /// A curated slug, or a drafted block embedded inline (docs/adr/029).
    enum Block: Hashable {
        case curated(String)
        case drafted(DraftedBlock)
    }
    private enum CodingKeys: String, CodingKey { case palette, block, rotation, bundle, icon }
    init(palette: String? = nil, block: Block? = nil, rotation: Int? = nil, bundle: [String]? = nil, icon: String? = nil) {
        self.palette = palette; self.block = block; self.rotation = rotation; self.bundle = bundle; self.icon = icon
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        palette = try container.decodeIfPresent(String.self, forKey: .palette)
        rotation = try container.decodeIfPresent(Int.self, forKey: .rotation)
        bundle = try container.decodeIfPresent([String].self, forKey: .bundle)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        if let slug = try? container.decodeIfPresent(String.self, forKey: .block) { block = .curated(slug) }
        else if let draft = try? container.decodeIfPresent(DraftedBlock.self, forKey: .block) { block = .drafted(draft) }
        else { block = nil }
    }
}

/// A drafted block: a square grid, seams between wall anchors, and the bundle
/// slot each piece is cut from, all in quarter-cell units (docs/adr/029).
struct DraftedBlock: Decodable, Hashable {
    let grid: Int
    let seams: [[Int]]?
    let colors: [String: [Int]]?
    init(grid: Int, seams: [[Int]]? = nil, colors: [String: [Int]]? = nil) { self.grid = grid; self.seams = seams; self.colors = colors }
}

/// One term of the quilt's tag vocabulary. A tag may carry a motif, which is
/// how a patch that chose none still wears a mark that says what it is.
struct TagTerm: Decodable, Hashable {
    let name: String
    let motif: String?
    let nodeCount: Int?
}

struct PatchLink: Decodable, Hashable {
    let url: String
    let label: String
}

struct Affinity: Decodable, Hashable {
    let source: String
    let target: String
    let strength: Double
}

struct PatchResponse: Decodable {
    let node: Patch
}

struct TreeResponse: Decodable {
    let tree: Root
    let affinity: [Affinity]?
    struct Root: Decodable { let children: [Patch]? }
}

struct PatchworkEvent: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let location: String?
    let startsAt: String
    let endsAt: String?
    let timezone: String?
    let nodeName: String?
    let nodeSlug: String?
    let eventUrl: String?
    /// Everything below is additive and optional: the list endpoint sends
    /// some of it, the detail endpoint the rest, and a quilt running an older
    /// build sends none of it. Absent is never an error.
    let nodeId: String?
    let nodeStatus: String?
    let visibility: String?
    let recurrence: String?
    let imageUrl: String?
    let imageAlt: String?
    let latitude: Double?
    let longitude: Double?
    let status: String?
    let sourceId: String?
    let links: [EventLink]?
    let mentions: [EventMention]?

    var date: Date? { Self.parseDate(startsAt) }
    var endDate: Date? { endsAt.flatMap(Self.parseDate) }
    static func parseDate(_ value: String) -> Date? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: value) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: value)
    }
    /// An event's time belongs to the place it happens, not to its reader:
    /// every formatter here reads the instant in the event's own zone.
    var zone: TimeZone { TimeZone(identifier: timezone ?? "") ?? .current }
    var dateLabel: String { label(dateStyle: .full) }
    var shortDateLabel: String { label(dateStyle: .medium) }
    func label(dateStyle: DateFormatter.Style) -> String {
        guard let date else { return "Time to be confirmed" }
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    /// Whether the two ends land on one calendar day *in the event's zone* —
    /// the day the organizer meant, not the reader's and not UTC's.
    var endsOnTheSameDay: Bool {
        guard let date, let endDate else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.isDate(date, inSameDayAs: endDate)
    }
    /// "Sunday, 20 September 2026 at 2:00 PM – 5:00 PM" on one day; the whole
    /// of the other end when the event runs past midnight.
    func rangeLabel(dateStyle: DateFormatter.Style = .full) -> String {
        let start = label(dateStyle: dateStyle)
        guard let endDate else { return start }
        return endsOnTheSameDay
            ? "\(start) – \(timeLabel(endDate))"
            : "\(start) – \(PatchworkEvent.labelFor(endDate, zone: zone, dateStyle: dateStyle))"
    }
    private static func labelFor(_ date: Date, zone: TimeZone, dateStyle: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    /// What the event says about who it is for. Public wears nothing: a chip
    /// on every row would say nothing at all.
    var tierLabel: String? {
        switch visibility {
        case "followers": return "Followers"
        case "members": return "Members only"
        default: return nil
        }
    }
    /// Events on unclaimed patches wear the community-submitted label away
    /// from their patch.
    var communitySubmitted: Bool { nodeStatus == "unclaimed" }
    var awaitingReview: Bool { status == "pending_review" }
    /// The word an organizer stored, told the truth: nothing expands a
    /// recurrence, so this page is one date of whatever they meant.
    var recurrenceNote: String? {
        let labels = [
            "daily": "The organizer says this repeats daily",
            "weekly": "The organizer says this repeats weekly",
            "biweekly": "The organizer says this repeats every two weeks",
            "monthly": "The organizer says this repeats monthly",
        ]
        guard let recurrence, let label = labels[recurrence] else { return nil }
        return label + " — only this date is on the calendar"
    }
    /// "with X": only a settled handshake is anybody else's business.
    var confirmedLinks: [EventLink] { (links ?? []).filter { $0.status == "confirmed" } }
    var flyerURL: URL? {
        guard let imageUrl, !imageUrl.isEmpty else { return nil }
        guard let url = URL(string: imageUrl), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }
    /// The event's own page out on the web, only where the scheme is one a
    /// browser can follow — an imported event gets this straight from a feed.
    var externalURL: URL? {
        guard let eventUrl, !eventUrl.isEmpty else { return nil }
        guard let url = URL(string: eventUrl), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }
}

/// A patch's presence on another patch's event, once both sides agreed.
struct EventLink: Decodable, Identifiable, Hashable {
    let id: String
    let nodeId: String?
    let nodeName: String?
    let nodeSlug: String?
    let nodeStatus: String?
    let status: String?
}

/// A display-only doorway to a patch on another quilt.
struct EventMention: Decodable, Identifiable, Hashable {
    let id: String
    let host: String
    let slug: String
    let name: String?
    var title: String { name?.isEmpty == false ? name! : slug }
    var url: URL? { URL(string: "https://\(host)/patches/\(slug)") }
}

struct EventPage: Decodable {
    let items: [PatchworkEvent]?
    let nextCursor: String?
}

enum QuiltAddress {
    static func parse(_ input: String) throws -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw APIError.address }
        let value = text.contains("://") ? text : "https://" + text
        guard var parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, !host.contains(" "),
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { throw APIError.address }
        parts.scheme = "https"
        parts.host = host.lowercased()
        parts.path = ""
        guard let url = parts.url else { throw APIError.address }
        return url
    }
}
