// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import WebKit

/// One quilt's discovery state. The quilt, its search, and Discover read the
/// same patches and the same filter, so narrowing on one narrows all of them.
@MainActor final class QuiltSession: ObservableObject {
    let quilt: Quilt
    let api: PatchworkAPI
    @Published var instance: Instance?
    @Published var icon: UIImage?
    @Published var tabIcon: UIImage?
    @Published var tabIconDim: UIImage?
    @Published private(set) var patches: [Patch] = []
    @Published private(set) var affinity: [Affinity] = []
    @Published private(set) var baseline: [QuiltLayout.Tile] = []
    @Published private(set) var tiles: [QuiltLayout.Tile] = []
    /// Tag name → motif slug from the quilt's vocabulary: how a patch that
    /// chose no motif still wears a mark that says what it is.
    @Published private(set) var tagMotifs: [String: String] = [:]
    /// The quilt's tag vocabulary as the server sent it. Kept whole rather
    /// than reduced to motifs, because `node_count` is the quilt's own answer
    /// to "how many patches wear this" — a whole-quilt, public number that the
    /// tree this client happens to hold is only an approximation of.
    @Published private(set) var tagTerms: [TagTerm] = []
    /// The search chip. Set only by "Show matches on the quilt", never by typing.
    @Published var query = "" { didSet { repack() } }
    @Published var tags = Set<String>() { didSet { repack() } }
    /// The patch whose profile is docked over whichever surface opened it.
    @Published var docked: Patch?
    @Published var switching = false
    /// The top bar's field is live: results show under it, and the bottom
    /// bar's search button focuses it rather than opening anything.
    @Published var searching = false
    @Published var searchText = ""
    @Published var loading = true
    @Published var error: String?
    /// The register the reader is drawing in (docs/adr/112). It is the
    /// reader's setting rather than the quilt's, but it lives here because
    /// the quilt is what it changes: publishing it re-renders the canvas, and
    /// setting `QuiltTheme.colorMode` from the same place keeps the palette
    /// the layers resolve in step with the one the views were told about.
    @Published private(set) var colorMode = QuiltTheme.colorMode
    /// Who this quilt says the reader is, or nobody. It is the account menu's
    /// whole state: there is one session per quilt, held in the cookie jar,
    /// and this is the quilt's own answer to `auth/me` about it.
    @Published private(set) var me: User?
    /// Every patch this reader holds something on — active or pending — as
    /// the quilt last stated it. One index, read by the profile, the cards and
    /// the Dashboard alike, so no two surfaces can disagree about who the
    /// reader is to a patch. Empty is the honest answer for a signed-out one.
    @Published private(set) var memberships: [Membership] = []
    /// How many notifications this reader has not read, on this quilt. It is
    /// the bell's whole state and the Dashboard's first row, which is why it
    /// lives here rather than in either of them: two surfaces counting
    /// separately would eventually disagree.
    ///
    /// Reading one subtracts locally and clearing zeroes locally; the poll
    /// below is reconciliation and nothing else (web issue #55 — a badge that
    /// moved only on the poll sat there for up to a minute after the thing
    /// had been read, which reads as broken). Zero is the honest answer for a
    /// signed-out reader, and no count is asked for without a session.
    @Published private(set) var unread = 0
    /// The sixty-second reconciliation, alive only while a signed-in reader
    /// has the app in front of them.
    private var unreadPoll: Task<Void, Never>?
    init(quilt: Quilt) { self.quilt = quilt; api = PatchworkAPI(base: quilt.url) }
    func apply(colorMode next: ColorMode) {
        QuiltTheme.colorMode = next
        guard colorMode != next else { return }
        colorMode = next
    }
    var filtered: [Patch] { patches.filter { QuiltLayout.matches($0, query: query, tags: tags) } }
    var activeFilterCount: Int { tags.count + (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1) }
    var mapEnabled: Bool { instance?.modules?["map"] != false }
    /// Tags by how many patches wear them, most-worn first; ties read A to Z.
    var rankedTags: [(tag: String, count: Int)] { Self.rank(patches: patches, terms: tagTerms) }
    /// The ranking, as a value so it can be checked without a quilt.
    ///
    /// The count is the server's `node_count` wherever the vocabulary
    /// endpoint answered for that tag, and the count derived from the patches
    /// in hand only where it did not — a quilt that will not serve `tags` gets
    /// a number that is honest about the tree rather than no number at all.
    /// Ordering is the web's: count descending, ties A to Z.
    ///
    /// A term nothing wears is dropped, which is where this parts company
    /// with the web. The web lists the whole vocabulary and prints the zero;
    /// here the same array is also the filter sheet's chips, and a chip that
    /// can only empty the quilt is worse than an absent one.
    nonisolated static func rank(patches: [Patch], terms: [TagTerm]) -> [(tag: String, count: Int)] {
        var derived: [String: Int] = [:]
        for patch in patches { for tag in Set(patch.tags ?? []) { derived[tag, default: 0] += 1 } }
        var served: [String: Int] = [:]
        for term in terms { if let count = term.nodeCount { served[term.name] = count } }
        var names = Set(derived.keys)
        for (name, count) in served where count > 0 { names.insert(name) }
        return names.map { (tag: $0, count: served[$0] ?? derived[$0] ?? 0) }
            .filter { $0.count > 0 }
            .sorted { $0.count == $1.count ? $0.tag.localizedStandardCompare($1.tag) == .orderedAscending : $0.count > $1.count }
    }
    func clearFilters() { query = ""; tags = [] }
    func endSearch() { searching = false; searchText = "" }
    /// The one act that narrows: the field's text becomes the search chip.
    func showMatches() {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        query = text
        endSearch()
    }
    func open(_ patch: Patch) { docked = patch }
    private func repack() {
        let sizes = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0.size) })
        tiles = activeFilterCount == 0 ? baseline : QuiltLayout.pack(filtered, affinity: affinity, sizes: sizes)
    }
    func load() async {
        loading = patches.isEmpty; error = nil
        defer { loading = false }
        do {
            let result: TreeResponse = try await api.get("nodes/tree")
            patches = result.tree.children ?? []; affinity = result.affinity ?? []
            baseline = QuiltLayout.pack(patches, affinity: affinity)
            repack()
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        if instance == nil { instance = try? await api.get("instance") }
        if tagTerms.isEmpty, let terms: [TagTerm] = try? await api.get("tags") {
            tagTerms = terms
            tagMotifs = Dictionary(terms.compactMap { term in term.motif.map { (term.name, $0) } }, uniquingKeysWith: { a, _ in a })
        }
        if icon == nil, let data = try? await api.data("instance/icon") {
            var image = UIImage(data: data)
            if image == nil { image = await SVGRasterizer().render(data, side: 50) }
            if let image { icon = image; tabIcon = image.tabIcon(); tabIconDim = image.tabIcon(dimmed: true) }
        }
        await refreshAccount()
    }

    // MARK: The account

    /// Read back who the cookie says this is — but only if there is a cookie.
    ///
    /// A reader who has never signed in to this quilt makes no authenticated
    /// request at all: the check is local, host-scoped, and costs no round
    /// trip, so a signed-out launch reads exactly the public endpoints it
    /// always did.
    func refreshAccount() async {
        guard api.hasSession() else { me = nil; memberships = []; return }
        do {
            me = try await api.account()
            await refreshMemberships()
            await refreshUnread()
            startUnreadPoll()
        }
        catch APIError.unauthenticated { signedOut() }
        catch { /* A quilt that cannot be reached is not a quilt that signed us out. */ }
    }

    /// The sheet's ending: the account menu is what confirms it.
    func signedIn(_ user: User) {
        me = user
        Task {
            await refreshMemberships()
            await refreshUnread()
            startUnreadPoll()
        }
    }

    /// Any authenticated call anywhere can land here: a 401 means the session
    /// is gone, whatever was being asked for.
    func signedOut() {
        me = nil
        memberships = []
        unread = UnreadTally.cleared
        stopUnreadPoll()
    }

    // MARK: The unread count

    /// The server's own number. Silent on failure: a bell with a stale badge
    /// beats an error nobody asked for, and the last known count stays.
    func refreshUnread() async {
        guard me != nil else { unread = UnreadTally.cleared; return }
        do { unread = UnreadTally.reconciled(try await api.unreadNotifications()) }
        catch APIError.unauthenticated { signedOut() }
        catch { /* Leave the last known count in place. */ }
    }

    /// One row — or several — went from unread to read.
    func noteRead(_ count: Int = 1) { unread = UnreadTally.read(unread, count) }
    /// A dismissed row takes the badge with it only if it was unread.
    func noteDismissed(wasUnread: Bool) { unread = UnreadTally.dismissed(unread, wasUnread: wasUnread) }
    /// Mark-all-read and clear-all both empty the table server-side.
    func clearUnread() { unread = UnreadTally.cleared }

    /// What the app's foreground does to the count: read it again on the way
    /// in, and keep the sixty-second reconciliation running only while
    /// somebody is looking at it. A backgrounded app polling a quilt is a
    /// request nobody asked for.
    func scenePhaseChanged(to phase: ScenePhase) {
        guard phase == .active else { stopUnreadPoll(); return }
        Task { await refreshUnread() }
        startUnreadPoll()
    }

    private func startUnreadPoll() {
        guard unreadPoll == nil, me != nil else { return }
        unreadPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refreshUnread()
            }
        }
    }

    private func stopUnreadPoll() {
        unreadPoll?.cancel()
        unreadPoll = nil
    }

    // MARK: The membership index

    /// Read back every patch this reader holds something on. Asked only where
    /// there is an account to ask about — a signed-out reader still makes
    /// exactly the public reads they always did — and asked again after every
    /// act, so the profile, the cards and the Dashboard all answer from one
    /// index rather than from three guesses about what just happened.
    func refreshMemberships() async {
        guard me != nil else { memberships = []; return }
        do {
            let page: MembershipPage = try await api.get("me/nodes")
            memberships = page.items
        } catch APIError.unauthenticated {
            signedOut()
        } catch {
            // A quilt that could not be reached has not changed who anyone is.
        }
    }

    /// Where the reader stands with one patch, or nowhere.
    func standing(for slug: String) -> Standing? { Self.standing(in: memberships, for: slug) }

    /// The same lookup as a value, so the index can be read without a quilt.
    nonisolated static func standing(in rows: [Membership], for slug: String) -> Standing? {
        rows.first { $0.nodeSlug == slug }?.standing
    }

    // MARK: The acts

    /// Follow a patch: a membership with the follower role, which the server
    /// accepts on a public patch and refuses on anything else.
    @discardableResult func follow(_ slug: String) async throws -> String {
        try await act("nodes/\(slug)/join", body: JoinRequest(role: "follower"))
    }

    /// Join a patch, with the message its admins will read where the policy
    /// makes them decide. The server answers `active` or `pending` and this
    /// client repeats that answer rather than predicting it.
    @discardableResult func join(_ slug: String, message: String = "") async throws -> String {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await act("nodes/\(slug)/join", body: JoinRequest(message: text.isEmpty ? nil : String(text.prefix(500))))
    }

    /// Unfollow and Leave are one call: `…/leave` ends whatever active row
    /// there is. They stay two names because they are two acts to the person
    /// doing them.
    @discardableResult func unfollow(_ slug: String) async throws -> String { try await act("nodes/\(slug)/leave") }
    @discardableResult func leave(_ slug: String) async throws -> String { try await act("nodes/\(slug)/leave") }

    /// Take back a request nobody has answered. Withdrawing is not leaving
    /// (web ADR 088), and the server keeps them apart, so this client does too.
    @discardableResult func withdraw(_ slug: String) async throws -> String { try await act("nodes/\(slug)/withdraw") }

    private func act(_ path: String) async throws -> String { try await act(path, body: NoBody()) }

    /// Every act ends in the same place: the index, asked again. Whatever the
    /// server actually did is then what every surface is drawing.
    private func act(_ path: String, body: some Encodable) async throws -> String {
        do {
            let answer: MembershipAct = try await api.post(path, body: body)
            await refreshMemberships()
            return answer.status ?? "ok"
        } catch APIError.unauthenticated {
            signedOut()
            throw APIError.unauthenticated
        }
    }

    /// Open a patch's profile from a surface that holds a slug rather than a
    /// patch — the Dashboard's rows, which are memberships. A patch on this
    /// quilt's tree is docked straight away; one the tree does not carry is
    /// fetched first, so a private patch the reader is in still opens.
    func open(slug: String) async {
        if let patch = patches.first(where: { $0.slug == slug }) { docked = patch; return }
        if let response: PatchResponse = try? await api.get("nodes/\(slug)") { docked = response.node }
    }

    /// Let go of this quilt, and only this quilt.
    ///
    /// The cookie is cleared whatever the POST did. A 401 means the session
    /// was already gone; anything else means the quilt could not be reached,
    /// and a reader who pressed Sign out on a train should not still be signed
    /// in when they get off — the server-side session then expires on its own.
    func signOut() async {
        do { try await api.signOut() }
        catch { }
        api.clearSession()
        signedOut()
    }
}

/// The two exits that have to carry something with them. Every authenticated
/// act still happens on the quilt's website, and a link that arrives there
/// blank makes the reader do the work twice: retype what they searched for, or
/// find again the patch they were reading when they decided to sign in.
extension PatchworkAPI {
    func webURL(_ path: String, query: [URLQueryItem]) -> URL {
        var parts = URLComponents(url: webURL(path), resolvingAgainstBaseURL: false)
        parts?.queryItems = query.isEmpty ? nil : query
        return parts?.url ?? webURL(path)
    }
    /// The website's sign-in, which is where following, joining and posting
    /// live. `redirect` is the web's own parameter: it lands the reader back
    /// on the page they left rather than on a signed-in home they never asked
    /// for.
    func loginURL(returningTo path: String? = nil) -> URL {
        guard let path, !path.isEmpty else { return webURL("login") }
        return webURL("login", query: [URLQueryItem(name: "redirect", value: path)])
    }
    /// The website's suggestion form, carrying the name the reader typed.
    func suggestURL(name: String) -> URL {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return webURL("submit") }
        return webURL("submit", query: [URLQueryItem(name: "name", value: text)])
    }
}

extension UIImage {
    /// A 25pt square drawn in its own colours: the quilt's mark is identity,
    /// not a template glyph, and keeps its hard edges.
    func tabIcon(dimmed: Bool = false) -> UIImage {
        let side: CGFloat = 25
        let scale = max(side / size.width, side / size.height)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            context.cgContext.clip(to: CGRect(x: 0, y: 0, width: side, height: side))
            draw(in: CGRect(origin: origin, size: drawn), blendMode: .normal, alpha: dimmed ? 0.45 : 1)
        }.withRenderingMode(.alwaysOriginal)
    }
}

extension Patch {
    /// The head's counts, worded as the web words them: a listing nobody runs
    /// counts who follows it, a claimed patch counts its members, and the
    /// upcoming count is never the all-time one beside it on the row.
    var countsLabel: String {
        var parts = [communityListing ? "\(followerCount ?? 0) Following" : "\(memberCount ?? 0) Member\(memberCount == 1 ? "" : "s")"]
        if let upcoming = upcomingEventCount { parts.append("\(upcoming) Upcoming Event\(upcoming == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}

/// Quilt icons are usually SVG, which UIImage cannot decode; a web page can.
/// The page draws it into a canvas and hands back a PNG, so nothing depends
/// on the web view ever being painted on screen.
@MainActor final class SVGRasterizer: NSObject, WKNavigationDelegate {
    private var loaded: CheckedContinuation<Void, Never>?
    private var webView: WKWebView?
    func render(_ data: Data, side: CGFloat) async -> UIImage? {
        guard let svg = String(data: data, encoding: .utf8), svg.contains("<svg") else { return nil }
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        web.navigationDelegate = self
        webView = web
        web.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: nil)
        await withCheckedContinuation { loaded = $0 }
        let scale = UIScreen.main.scale
        let px = Int(side * scale)
        let script = """
        return await new Promise(resolve => {
            const img = new Image();
            img.onload = () => {
                const canvas = document.createElement('canvas');
                canvas.width = \(px); canvas.height = \(px);
                canvas.getContext('2d').drawImage(img, 0, 0, \(px), \(px));
                resolve(canvas.toDataURL('image/png'));
            };
            img.onerror = () => resolve(null);
            img.src = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }));
        });
        """
        let result = try? await web.callAsyncJavaScript(script, arguments: ["svg": svg], contentWorld: .page)
        guard let dataURL = result as? String, let comma = dataURL.firstIndex(of: ","),
              let png = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) else { return nil }
        return UIImage(data: png, scale: scale)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded?.resume(); loaded = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loaded?.resume(); loaded = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loaded?.resume(); loaded = nil }
}
