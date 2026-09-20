// SPDX-License-Identifier: MPL-2.0

import Foundation

enum APIError: LocalizedError {
    case address, response, status(Int)
    var errorDescription: String? {
        switch self {
        case .address: return "Enter a quilt’s HTTPS address, such as community.example.org, without a page path."
        case .response: return "This address did not return a Patchwork response. Check the address and try again."
        case .status(let status): return "The quilt could not complete the request (HTTP \(status)). Try again shortly."
        }
    }
}

struct PatchworkAPI {
    let base: URL
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()
    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") {
            return try PreviewData.response(path, query: query)
        }
        #endif
        var parts = URLComponents(url: base.appendingPathComponent("api/v1/" + path), resolvingAgainstBaseURL: false)!
        parts.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: parts.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.response }
        guard (200..<300).contains(http.statusCode) else { throw APIError.status(http.statusCode) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.response }
    }
    /// The events feed. `from`/`to` are instants, not bare dates: the server
    /// compares `starts_at` as text, so a day has to travel as the two
    /// instants that bound it (see EventDateBounds). `includePast` drops the
    /// lower bound entirely, which is what a patch's whole calendar wants;
    /// an explicit `from` always wins over it, as it does on the server.
    func events(slug: String? = nil, after: String? = nil, limit: Int = 30,
                from: String? = nil, to: String? = nil, includePast: Bool = false) async throws -> EventPage {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let slug { query.append(URLQueryItem(name: "node_slug", value: slug)) }
        if let from, !from.isEmpty { query.append(URLQueryItem(name: "from", value: from)) }
        if let to, !to.isEmpty { query.append(URLQueryItem(name: "to", value: to)) }
        if includePast, from == nil { query.append(URLQueryItem(name: "include_past", value: "true")) }
        if let after, !after.isEmpty { query.append(URLQueryItem(name: "after", value: after)) }
        return try await get("events", query: query)
    }
    /// One event as a calendar file, exactly as the quilt serves it to the
    /// web. Nothing here parses it — it is handed straight to a share sheet.
    func eventCalendar(_ id: String) async throws -> Data {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") { return PreviewData.calendarFile(id) }
        #endif
        return try await data("events/\(id)/event.ics")
    }
    /// A patch's standing calendar, for a reader who wants every night rather
    /// than one: `webcal:` hands the subscription to the Calendar app, and the
    /// RSS feed is for everybody else's reader.
    func subscriptionURL(slug: String) -> URL? {
        guard var parts = URLComponents(url: base.appendingPathComponent("api/v1/nodes/\(slug)/events.ics"), resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = "webcal"
        return parts.url
    }
    func feedURL(slug: String) -> URL { base.appendingPathComponent("api/v1/nodes/\(slug)/events.rss") }
    func webURL(_ path: String) -> URL { base.appendingPathComponent(path) }
    /// Raw bytes, for the quilt's icon. Preview data serves no images.
    func data(_ path: String) async throws -> Data {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") { throw APIError.status(404) }
        #endif
        let (data, response) = try await Self.session.data(for: URLRequest(url: base.appendingPathComponent("api/v1/" + path)))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError.response }
        return data
    }
}

@MainActor final class QuiltStore: ObservableObject {
    @Published var saved: [Quilt] = []
    @Published var selected: Quilt?
    init() {
        if let data = UserDefaults.standard.data(forKey: "savedQuilts"),
           let quilts = try? JSONDecoder().decode([Quilt].self, from: data) {
            saved = quilts.filter { (try? QuiltAddress.parse($0.url.absoluteString)) != nil }
        }
    }
    func connect(_ quilt: Quilt) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") {
            selected = quilt
            return
        }
        #endif
        saved.removeAll { $0.id == quilt.id }
        saved.append(quilt)
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: "savedQuilts") }
        selected = quilt
    }
}
