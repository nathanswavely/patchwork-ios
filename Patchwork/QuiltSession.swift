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
    var rankedTags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for patch in patches { for tag in Set(patch.tags ?? []) { counts[tag, default: 0] += 1 } }
        return counts.map { (tag: $0.key, count: $0.value) }
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
        if tagMotifs.isEmpty, let terms: [TagTerm] = try? await api.get("tags") {
            tagMotifs = Dictionary(terms.compactMap { term in term.motif.map { (term.name, $0) } }, uniquingKeysWith: { a, _ in a })
        }
        if icon == nil, let data = try? await api.data("instance/icon") {
            var image = UIImage(data: data)
            if image == nil { image = await SVGRasterizer().render(data, side: 50) }
            if let image { icon = image; tabIcon = image.tabIcon(); tabIconDim = image.tabIcon(dimmed: true) }
        }
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
