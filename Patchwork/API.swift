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
            return try PreviewData.response(path)
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
    func events(slug: String? = nil, after: String? = nil, limit: Int = 30) async throws -> EventPage {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let slug { query.append(URLQueryItem(name: "node_slug", value: slug)) }
        if let after, !after.isEmpty { query.append(URLQueryItem(name: "after", value: after)) }
        return try await get("events", query: query)
    }
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
