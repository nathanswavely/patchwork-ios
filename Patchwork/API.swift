// SPDX-License-Identifier: MPL-2.0

import Foundation

enum APIError: LocalizedError, Equatable {
    case address, response, status(Int)
    /// The server's own sentence, decoded from an `{"error": …}` body. The
    /// quilt words a refusal better than this client can — "that username is
    /// taken", "that address isn’t an address" — so where it says something,
    /// that is what the person is shown.
    case message(String, status: Int)
    /// A 401 from an authenticated call: the session is gone or was never
    /// there. It is a state, not a failure to report — whoever asked clears
    /// the account and carries on reading the public quilt.
    case unauthenticated
    var errorDescription: String? {
        switch self {
        case .address: return "Enter a quilt’s HTTPS address, such as community.example.org, without a page path."
        case .response: return "This address did not return a Patchwork response. Check the address and try again."
        case .status(let status): return "The quilt could not complete the request (HTTP \(status)). Try again shortly."
        case .message(let message, _): return message
        case .unauthenticated: return "You are signed out of this quilt."
        }
    }
    /// What a non-2xx answer means, read from the body where the body says.
    static func from(status: Int, data: Data) -> APIError {
        if status == 401 { return .unauthenticated }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = (object["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return .message(message, status: status)
        }
        return .status(status)
    }
}

struct PatchworkAPI {
    let base: URL
    /// The name of the session cookie the server sets (HttpOnly, Secure,
    /// SameSite=Lax). There is no bearer token anywhere in this contract.
    static let sessionCookie = "patchwork_session"
    /// One session for the app, and it keeps cookies.
    ///
    /// This used to be `.ephemeral` with `httpShouldSetCookies = false`, which
    /// was the honest shape of a client that could not sign in. Now that it
    /// can, the session cookie has to survive a relaunch, so the storage is
    /// `HTTPCookieStorage.shared` — the system's own jar, private to this app,
    /// shared with nothing and no web view.
    ///
    /// Cookies are host-scoped by the cookie standard itself, so a reader
    /// signed in to two saved quilts keeps two separate sessions with no
    /// bookkeeping here at all: a request to `a.example` is never sent
    /// `b.example`'s cookie, and clearing one quilt's session cannot touch the
    /// other's. That is why nothing in this client indexes sessions by quilt.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .onlyFromMainDocumentDomain
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()
    private static var isPreview: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--preview")
        #else
        return false
        #endif
    }
    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        #if DEBUG
        if Self.isPreview {
            return try PreviewData.response(path, query: query)
        }
        #endif
        var parts = URLComponents(url: base.appendingPathComponent("api/v1/" + path), resolvingAgainstBaseURL: false)!
        parts.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: parts.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.response }
        guard (200..<300).contains(http.statusCode) else { throw APIError.from(status: http.statusCode, data: data) }
        do { return try Self.decoder().decode(T.self, from: data) }
        catch { throw APIError.response }
    }
    /// A write. Three of them exist — ask for a code, answer it, and let go —
    /// and every one of them needs the two headers the server refuses a
    /// request without: `X-Patchwork-Request` (the quilt's own CSRF gate) and
    /// a JSON content type. A body is encoded snake_case, the way the server
    /// spells its fields.
    func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        let data = try await postData(path, body: body)
        do { return try Self.decoder().decode(T.self, from: data) }
        catch { throw APIError.response }
    }
    /// The same write where the answer is not read: logging out.
    func postVoid(_ path: String, body: some Encodable) async throws { _ = try await postData(path, body: body) }
    func postVoid(_ path: String) async throws { try await postVoid(path, body: NoBody()) }
    private func postData(_ path: String, body: some Encodable) async throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try await write("POST", path, payload: try encoder.encode(body))
    }
    /// The other two verbs, which arrived with the notifications list: marking
    /// one read is a `PATCH`, dismissing one and clearing the lot are
    /// `DELETE`s. They are the same write as a `POST` in every way that
    /// matters — the quilt's CSRF gate refuses a request without
    /// `X-Patchwork-Request` whatever the method is — so they share its body
    /// rather than growing a second one that could drift out of step with it.
    /// Neither carries a body: the path is the whole of what they say.
    func patchVoid(_ path: String) async throws { _ = try await write("PATCH", path, payload: nil) }
    func deleteVoid(_ path: String) async throws { _ = try await write("DELETE", path, payload: nil) }
    /// One request for every non-GET this client makes.
    private func write(_ method: String, _ path: String, payload: Data?) async throws -> Data {
        #if DEBUG
        if Self.isPreview { return Data(try PreviewData.write(method, path, body: payload).utf8) }
        #endif
        var request = URLRequest(url: base.appendingPathComponent("api/v1/" + path))
        request.httpMethod = method
        request.httpBody = payload
        request.setValue("true", forHTTPHeaderField: "X-Patchwork-Request")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.response }
        guard (200..<300).contains(http.statusCode) else { throw APIError.from(status: http.statusCode, data: data) }
        return data
    }
    /// Whether this quilt's host has a session cookie in the jar.
    ///
    /// This is what keeps a signed-out launch signed out: `auth/me` is the one
    /// authenticated read this client makes, and asking it with no cookie
    /// would be a 401 round trip announcing to every quilt that the app
    /// opened. The storage is injectable so the host scoping can be checked
    /// without touching the shared jar.
    func hasSession(in storage: HTTPCookieStorage = .shared) -> Bool {
        #if DEBUG
        if Self.isPreview { return PreviewData.signedIn }
        #endif
        return Self.hasSession(for: base, in: storage)
    }
    /// The same check as a value: is there a `patchwork_session` cookie this
    /// URL would be sent? `cookies(for:)` applies the cookie's own domain,
    /// path and Secure rules, so a cookie set by one quilt is invisible here
    /// to every other.
    static func hasSession(for url: URL, in storage: HTTPCookieStorage) -> Bool {
        (storage.cookies(for: url) ?? []).contains { $0.name == sessionCookie }
    }
    /// Forget this quilt's session, and only this quilt's.
    func clearSession(in storage: HTTPCookieStorage = .shared) {
        #if DEBUG
        if Self.isPreview { PreviewData.signOut(); return }
        #endif
        Self.clearSession(for: base, in: storage)
    }
    static func clearSession(for url: URL, in storage: HTTPCookieStorage) {
        for cookie in storage.cookies(for: url) ?? [] { storage.deleteCookie(cookie) }
    }
    /// The same feed with bounds already resolved to instants — what the date
    /// presets produce. `from`/`to` travel as instants, never bare dates: the
    /// server compares `starts_at` as text, so a bare date as `to` would drop
    /// the day it names.
    func events(slug: String? = nil, after: String? = nil, limit: Int = 30, fromInstant: String?, toInstant: String? = nil) async throws -> EventPage {
        var query = Self.eventsQuery(slug: slug, after: after, limit: limit)
        if let fromInstant, !fromInstant.isEmpty { query.append(URLQueryItem(name: "from", value: fromInstant)) }
        if let toInstant, !toInstant.isEmpty { query.append(URLQueryItem(name: "to", value: toInstant)) }
        return try await get("events", query: query)
    }
    func events(slug: String? = nil, after: String? = nil, limit: Int = 30, from: Date? = nil, to: Date? = nil, includePast: Bool = false) async throws -> EventPage {
        try await get("events", query: Self.eventsQuery(slug: slug, after: after, limit: limit, from: from, to: to, includePast: includePast))
    }
    /// The events query, built apart from the request so the gates a patch's
    /// calendar turns on can be checked without a network. `from` keeps a
    /// section headed "Upcoming" from holding last month; `include_past`
    /// drops that bound, and `to` is what turns the dropped bound into a
    /// deliberate request for what already happened. The server orders
    /// events oldest first and pages forward, so asking for the whole
    /// calendar at once hands a busy venue its own history before tonight —
    /// which is why the two halves are asked for separately.
    static func eventsQuery(slug: String?, after: String? = nil, limit: Int = 30, from: Date? = nil, to: Date? = nil, includePast: Bool = false) -> [URLQueryItem] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let slug { query.append(URLQueryItem(name: "node_slug", value: slug)) }
        if let from { query.append(URLQueryItem(name: "from", value: ISO8601DateFormatter().string(from: from))) }
        if let to { query.append(URLQueryItem(name: "to", value: ISO8601DateFormatter().string(from: to))) }
        if includePast { query.append(URLQueryItem(name: "include_past", value: "true")) }
        if let after, !after.isEmpty { query.append(URLQueryItem(name: "after", value: after)) }
        return query
    }
    /// The same feed, narrowed to the patches the reader actually holds an
    /// active row on. It is the first read this client makes that is *about*
    /// the reader rather than about the quilt, which is why it carries
    /// `scope=my` and why nothing asks for it while signed out.
    func myEvents(from: Date, limit: Int = 20) async throws -> EventPage {
        try await get("events", query: Self.myEventsQuery(from: from, limit: limit))
    }
    /// Built apart from the request, like every other query here, so the one
    /// this client sends about a person can be checked without a network.
    /// `from` travels as an instant for the same reason every other bound
    /// does: the server compares `starts_at` as text.
    static func myEventsQuery(from: Date, limit: Int = 20) -> [URLQueryItem] {
        [
            URLQueryItem(name: "scope", value: "my"),
            URLQueryItem(name: "from", value: ISO8601DateFormatter().string(from: from)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
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
    /// A public API address, for the feeds a reader hands to another app.
    func apiURL(_ path: String) -> URL { base.appendingPathComponent("api/v1/" + path) }
    /// The same address a calendar app subscribes to. `webcal` is what hands
    /// an ICS feed to Calendar rather than downloading it once.
    func subscriptionURL(_ path: String) -> URL? {
        var parts = URLComponents(url: apiURL(path), resolvingAgainstBaseURL: false)
        parts?.scheme = "webcal"
        return parts?.url
    }
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

/// A POST with nothing to say — `auth/logout`.
struct NoBody: Encodable {}

/// The whole of what this client can do with an account: ask a quilt to email
/// a code, answer it, choose a username the first time, read back who that
/// made you, and let go. Every one of them is on the quilt the reader chose;
/// there is no central anything.
extension PatchworkAPI {
    /// "Email me a code." The quilt answers 200 whether or not the address has
    /// an account — it will not tell a stranger who is registered — and 400
    /// only when the address is not an address.
    func requestCode(email: String) async throws {
        try await postVoid("auth/magic-link", body: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines)])
    }
    /// The code, answered. Two 200s mean two different things: a user, or a
    /// handoff to choosing a username.
    func verify(email: String, code: String) async throws -> SignInOutcome {
        let response: SignInResponse = try await post(
            "auth/magic-link/verify",
            body: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "code": SignInFlow.normalize(code: code)]
        )
        return try response.outcome()
    }
    /// The second half of a first sign-in.
    func signUp(token: String, username: String, displayName: String) async throws -> User {
        let response: SignInResponse = try await post("auth/signup", body: SignUpBody(token: token, username: username, displayName: displayName))
        guard let user = response.user else { throw APIError.response }
        return user
    }
    /// Who the cookie says this is. 401 — the signed-out answer — arrives as
    /// `APIError.unauthenticated` rather than as a status to report.
    func account() async throws -> User {
        let response: SignInResponse = try await get("auth/me")
        guard let user = response.user else { throw APIError.response }
        return user
    }
    func signOut() async throws { try await postVoid("auth/logout") }
}

private struct SignUpBody: Encodable {
    let token: String
    let username: String
    /// Optional to the person, always sent: the server takes an empty string.
    let displayName: String
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
