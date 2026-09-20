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
    var date: Date? { Self.parseDate(startsAt) }
    static func parseDate(_ value: String) -> Date? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: value) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: value)
    }
    var dateLabel: String { label(dateStyle: .full) }
    var shortDateLabel: String { label(dateStyle: .medium) }
    private func label(dateStyle: DateFormatter.Style) -> String {
        guard let date else { return "Time to be confirmed" }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timezone ?? "") ?? .current
        formatter.dateStyle = dateStyle
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
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
