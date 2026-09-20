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
    var communityListing: Bool { isUnclaimed == true || status == "unclaimed" }
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
    var dateLabel: String {
        guard let date else { return "Time to be confirmed" }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timezone ?? "") ?? .current
        formatter.dateStyle = .full
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
