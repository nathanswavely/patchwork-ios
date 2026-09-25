// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import UIKit

struct QuiltCanvas: UIViewRepresentable {
    let tiles: [QuiltLayout.Tile]
    let patches: [Patch]
    var tagMotifs: [String: String] = [:]
    /// The register the tiles are cut in. It rides along so a change to it is
    /// a change to this view's value, which is what makes `updateUIView` run
    /// and the tiles recut; the mode is otherwise invisible to SwiftUI.
    var colorMode: ColorMode = .standard
    let select: (Patch) -> Void
    func makeUIView(context: Context) -> CanvasView { CanvasView() }
    func updateUIView(_ view: CanvasView, context: Context) {
        QuiltTheme.colorMode = colorMode
        view.update(tiles: tiles, patches: patches, tagMotifs: tagMotifs, colorMode: colorMode, select: select)
    }
}

/// The ink the quilt is drawn with, and the sizes that hold still on screen.
/// Seam ink and marks are screen pixels — a stitch is a mark on a map and
/// must not fatten as you approach — while the fabric is world units. Colours
/// follow the web's textile tokens (textile.css, app.css) in both themes.
enum QuiltInk {
    /// World points per grid unit.
    static let unit: CGFloat = 76
    /// The stitch itself, and the binding the quilt's outer edge wears.
    static let seamWidth: CGFloat = 0.6
    static let bindingWidth: CGFloat = 2.4
    /// A corner mark: the disc one wants, its inset from the corner, the share
    /// of a tile it may never exceed, and the size below which it is a speck.
    static let markSize: CGFloat = 22
    static let markInset: CGFloat = 6
    static let markShare: CGFloat = 0.3
    static let markMin: CGFloat = 9
    static let markGlyph: CGFloat = markSize * 0.64
    static let markShadowOffset: CGFloat = 1

    static let seam = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0, alpha: 0.72) : UIColor(red: 28 / 255, green: 24 / 255, blue: 18 / 255, alpha: 0.55) }
    static let thread = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#2e3240")! : UIColor(hex: "#c8c0b0")! }
    static let threadHeavy = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#4a5060")! : UIColor(hex: "#7a746a")! }
    static let labelBackground = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0, alpha: 0.5) : UIColor(red: 250 / 255, green: 246 / 255, blue: 238 / 255, alpha: 0.45) }
    static let labelText = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#e8e6e3")! : UIColor(hex: "#2a2520")! }
    /// Status wears a neutral dark disc, so a tile's own colour never means "unclaimed".
    static let statusDisc = UIColor(white: 0, alpha: 0.55)
    static let markShadow = UIColor(white: 0, alpha: 0.28)
}

/// The canvas and the badge layer over it. Badges are screen-space and never
/// scroll; a touch on one belongs to its patch, while the quilt still pans
/// underneath it.
final class CanvasView: UIView, UIGestureRecognizerDelegate {
    let scroll = CanvasScrollView()
    let badges = BadgeLayer()
    private var select: ((Patch) -> Void)?
    private var patchesByID: [String: Patch] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(scroll)
        addSubview(badges)
        scroll.onViewChange = { [weak self] in self?.updateBadges() }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.delegate = self
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The quilt runs under the bars; its names do not. The badge layer is
    /// the safe area, so a name clips at the bar's edge rather than sitting
    /// behind glass or the status bar.
    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        badges.frame = bounds.inset(by: safeAreaInsets)
        updateBadges()
    }
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if badges.badge(at: convert(point, to: badges)) != nil { return scroll }
        return super.hitTest(point, with: event)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        badges.badge(at: touch.location(in: badges)) != nil
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard scroll.canSelect, let id = badges.badge(at: gesture.location(in: badges)), let patch = patchesByID[id] else { return }
        select?(patch)
    }

    func update(tiles: [QuiltLayout.Tile], patches: [Patch], tagMotifs: [String: String], colorMode: ColorMode, select: @escaping (Patch) -> Void) {
        self.select = select
        patchesByID = Dictionary(patches.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        scroll.update(tiles: tiles, patches: patches, tagMotifs: tagMotifs, colorMode: colorMode, select: select)
        updateBadges()
    }

    func updateBadges() {
        guard bounds.width > 0 else { return }
        badges.apply(scroll.badgeCandidates(in: badges))
    }
}

final class CanvasScrollView: UIScrollView, UIScrollViewDelegate {
    var onViewChange: (() -> Void)?
    private let board = UIView()
    private let seams = CAShapeLayer()
    private let binding = CAShapeLayer()
    private var tileViews: [String: QuiltTileView] = [:]
    private var current: [QuiltLayout.Tile] = []
    private var currentPatches: [Patch] = []
    private var currentMotifs: [String: String] = [:]
    private var currentColorMode = QuiltTheme.colorMode
    private var needsFit = true
    private var lastBounds = CGSize.zero
    private var suppressSelectionUntil = 0.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 0.3
        maximumZoomScale = 6
        // The quilt hangs on the textile canvas — raw cotton, raw denim —
        // not on iOS grouped grey (Palette.swift).
        backgroundColor = .pwGround
        contentInsetAdjustmentBehavior = .never
        if #available(iOS 26.0, *) { topEdgeEffect.isHidden = true; bottomEdgeEffect.isHidden = true }
        board.backgroundColor = .clear
        addSubview(board)
        for layer in [seams, binding] {
            layer.fillColor = nil
            layer.lineCap = .round
            layer.lineJoin = .round
            layer.zPosition = 1
            board.layer.addSublayer(layer)
        }
        binding.lineCap = .square
        binding.opacity = 0.9
        applyTheme()
        accessibilityIdentifier = "quiltCanvas"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func touchesShouldCancel(in view: UIView) -> Bool { true }
    var canSelect: Bool {
        !isZooming && !isDragging && !isDecelerating && Date.timeIntervalSinceReferenceDate >= suppressSelectionUntil
    }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { suppressSelectionUntil = .infinity }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        suppressSelectionUntil = Date.timeIntervalSinceReferenceDate + 0.25
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { board }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { applyZoom(); onViewChange?() }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { onViewChange?() }

    /// Everything that holds still on screen while the quilt scales.
    private func applyZoom() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        seams.lineWidth = QuiltInk.seamWidth / zoomScale
        binding.lineWidth = QuiltInk.bindingWidth / zoomScale
        for tile in tileViews.values { tile.apply(zoom: zoomScale) }
        CATransaction.commit()
    }

    private func applyTheme() {
        seams.strokeColor = QuiltInk.seam.resolvedColor(with: traitCollection).cgColor
        binding.strokeColor = QuiltInk.seam.resolvedColor(with: traitCollection).cgColor
    }
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        applyTheme()
    }

    /// The tiles as the badge layer sees them: screen frames, fillers left out.
    func badgeCandidates(in view: UIView) -> [QuiltBadges.Candidate] {
        current.compactMap { tile in
            guard let tileView = tileViews[tile.id], let name = tileView.patchName else { return nil }
            return QuiltBadges.Candidate(id: tile.id, name: name, rect: board.convert(tileView.frame, to: view))
        }
    }

    /// The canvas runs under the bars, so fitting and centring use the safe
    /// area. On a phone the fit is floored so the smallest tile still clears
    /// the badge threshold: a quilt fitted whole into a phone screen is
    /// anonymous confetti, and it is better to start legible and let the
    /// person pan.
    override func layoutSubviews() {
        super.layoutSubviews()
        let visible = bounds.inset(by: safeAreaInsets)
        if visible.size != lastBounds { needsFit = true; lastBounds = visible.size }
        if needsFit && visible.width > 0 && board.bounds.width > 0 {
            needsFit = false
            let fit = min(visible.width / board.bounds.width, visible.height / board.bounds.height)
            let floor = visible.width <= 700 ? (QuiltBadges.minPx + 8) / QuiltInk.unit : minimumZoomScale
            setZoomScale(min(2.4, max(floor, fit)), animated: false)
            centre(in: visible)
            contentOffset = CGPoint(x: max(0, (contentSize.width - visible.width) / 2) - contentInset.left,
                                    y: max(0, (contentSize.height - visible.height) / 2) - contentInset.top)
            applyZoom()
        }
        centre(in: visible)
    }
    private func centre(in visible: CGRect) {
        let horizontal = max(0, (visible.width - board.frame.width) / 2)
        let vertical = max(0, (visible.height - board.frame.height) / 2)
        contentInset = UIEdgeInsets(top: safeAreaInsets.top + vertical, left: safeAreaInsets.left + horizontal,
                                    bottom: safeAreaInsets.bottom + vertical, right: safeAreaInsets.right + horizontal)
    }

    func update(tiles: [QuiltLayout.Tile], patches: [Patch], tagMotifs: [String: String], colorMode: ColorMode, select: @escaping (Patch) -> Void) {
        guard current != tiles || currentPatches != patches || currentMotifs != tagMotifs
                || currentColorMode != colorMode else { return }
        currentPatches = patches
        currentMotifs = tagMotifs
        currentColorMode = colorMode
        let animate = !current.isEmpty && !UIAccessibility.isReduceMotionEnabled
        current = tiles
        let unit = QuiltInk.unit, pad: CGFloat = 16
        let minX = tiles.map(\.x).min() ?? 0, minY = tiles.map(\.y).min() ?? 0
        let maxX = tiles.map { $0.x + $0.size }.max() ?? 1, maxY = tiles.map { $0.y + $0.size }.max() ?? 1
        let ids = Set(tiles.map(\.id))
        for id in Array(tileViews.keys) where !ids.contains(id) { tileViews.removeValue(forKey: id)?.removeFromSuperview() }
        let lookup = Dictionary(patches.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let seamPaths = Self.seamPaths(tiles, minX: minX, minY: minY, unit: unit, pad: pad)
        let changes = {
            self.board.bounds = CGRect(x: 0, y: 0, width: CGFloat(maxX - minX) * unit + 2 * pad, height: CGFloat(maxY - minY) * unit + 2 * pad)
            self.board.frame.origin = .zero
            for tile in tiles {
                let patch = lookup[tile.id]
                guard patch != nil || tile.id.hasPrefix("filler-") else { continue }
                let view = self.tileViews[tile.id] ?? QuiltTileView()
                if self.tileViews[tile.id] == nil {
                    self.tileViews[tile.id] = view
                    self.board.addSubview(view)
                }
                if let patch {
                    view.configure(patch: patch, tagMotifs: tagMotifs, colorMode: colorMode)
                    view.removeAction(identifiedBy: UIAction.Identifier("open"), for: .touchUpInside)
                    view.addAction(UIAction(identifier: UIAction.Identifier("open")) { [weak self] _ in
                        guard let self, self.canSelect else { return }
                        select(patch)
                    }, for: .touchUpInside)
                } else {
                    view.configure(filler: Int(tile.id.dropFirst("filler-".count)) ?? 0, colorMode: colorMode)
                }
                view.frame = CGRect(x: CGFloat(tile.x - minX) * unit + pad, y: CGFloat(tile.y - minY) * unit + pad,
                                    width: CGFloat(tile.size) * unit, height: CGFloat(tile.size) * unit)
                view.apply(zoom: self.zoomScale)
            }
            self.contentSize = self.board.frame.size
        }
        let settle = {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.seams.path = seamPaths.interior
            self.binding.path = seamPaths.outer
            self.seams.isHidden = false
            self.binding.isHidden = false
            CATransaction.commit()
        }
        if animate {
            // A seam belongs to the boundary, and the boundaries are moving:
            // the ink waits for the tiles to land rather than morphing between
            // two lattices.
            seams.isHidden = true; binding.isHidden = true
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes) { _ in settle() }
        } else { changes(); settle() }
        needsFit = true
        setNeedsLayout()
    }

    /// Every unique boundary segment once, so an interior seam is stroked at
    /// one darkness; a segment claimed by a single tile is the quilt's own
    /// edge, which is what the binding is drawn along (docs/adr/066).
    static func seamPaths(_ tiles: [QuiltLayout.Tile], minX: Int, minY: Int, unit: CGFloat, pad: CGFloat) -> (interior: CGPath, outer: CGPath) {
        struct Segment: Hashable { let horizontal: Bool; let x: Int; let y: Int }
        var claims: [Segment: Int] = [:]
        for tile in tiles {
            let x = tile.x - minX, y = tile.y - minY
            for i in 0..<tile.size {
                claims[Segment(horizontal: true, x: x + i, y: y), default: 0] += 1
                claims[Segment(horizontal: true, x: x + i, y: y + tile.size), default: 0] += 1
                claims[Segment(horizontal: false, x: x, y: y + i), default: 0] += 1
                claims[Segment(horizontal: false, x: x + tile.size, y: y + i), default: 0] += 1
            }
        }
        let interior = CGMutablePath(), outer = CGMutablePath()
        for (segment, count) in claims.sorted(by: { ($0.key.y, $0.key.x, $0.key.horizontal ? 0 : 1) < ($1.key.y, $1.key.x, $1.key.horizontal ? 0 : 1) }) {
            let start = CGPoint(x: CGFloat(segment.x) * unit + pad, y: CGFloat(segment.y) * unit + pad)
            let end = segment.horizontal ? CGPoint(x: start.x + unit, y: start.y) : CGPoint(x: start.x, y: start.y + unit)
            interior.move(to: start); interior.addLine(to: end)
            if count == 1 { outer.move(to: start); outer.addLine(to: end) }
        }
        return (interior, outer)
    }
}

/// One tile: its block, cut from its palette and warped only by rotation, and
/// the corner marks it wears. The block lives in a unit-square layer scaled
/// to the tile, so a repack that resizes the tile animates as one transform.
final class QuiltTileView: UIControl {
    private(set) var patchName: String?
    private let block = CALayer()
    private var cuts: [CAShapeLayer] = []
    private var marks: [CornerMark] = []
    private var rotation = 0
    private var identity: (id: String, appearance: Appearance?, motif: String?, unclaimed: Bool, filler: Int?, colorMode: ColorMode)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        block.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        layer.addSublayer(block)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(patch: Patch, tagMotifs: [String: String], colorMode: ColorMode) {
        let motif = Motifs.key(for: patch, tagMotifs: tagMotifs)
        patchName = patch.name
        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = patch.name
        accessibilityHint = "Opens patch details"
        accessibilityIdentifier = "quiltTile-\(patch.slug)"
        let next = (id: patch.id, appearance: patch.appearance, motif: Optional(motif), unclaimed: patch.communityListing, filler: Optional<Int>.none, colorMode: colorMode)
        guard identity?.id != next.id || identity?.appearance != next.appearance || identity?.motif != next.motif
                || identity?.unclaimed != next.unclaimed || identity?.filler != nil
                || identity?.colorMode != next.colorMode else { return }
        identity = next
        let palette = QuiltTheme.palette(for: patch)
        rotation = QuiltBlocks.rotation(id: patch.id, appearance: patch.appearance)
        block.opacity = 1
        setCuts(QuiltBlocks.cuts(id: patch.id, appearance: patch.appearance, palette: palette))
        marks.forEach { $0.removeFromSuperlayer() }
        marks = [CornerMark(corner: .topLeft, disc: UIColor(hex: palette.primary) ?? .label,
                            glyph: Motifs.glyph(motif, color: QuiltTheme.textOnColor(palette.primary)))]
        if patch.communityListing {
            marks.append(CornerMark(corner: .topRight, disc: QuiltInk.statusDisc, glyph: Motifs.unclaimedGlyph(color: .white)))
        }
        marks.forEach { layer.addSublayer($0) }
        setNeedsLayout()
    }

    /// A neutral cell bridging a gap: a ghost block at low opacity, never
    /// tappable, never named.
    func configure(filler index: Int, colorMode: ColorMode) {
        patchName = nil
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityIdentifier = nil
        guard identity?.filler != index || identity?.colorMode != colorMode else { return }
        identity = (id: "filler-\(index)", appearance: nil, motif: nil, unclaimed: false, filler: index, colorMode: colorMode)
        rotation = 0
        block.opacity = 0.15
        let palette = QuiltTheme.ghost(index)
        setCuts(QuiltBlocks.curated(index).map { piece in
            switch piece.fabric {
            case .primary: return QuiltBlocks.Cut(points: piece.points, hex: palette.primary)
            case .secondary: return QuiltBlocks.Cut(points: piece.points, hex: palette.secondary)
            case .bg: return QuiltBlocks.Cut(points: piece.points, hex: palette.bg)
            }
        })
        marks.forEach { $0.removeFromSuperlayer() }
        marks = []
        setNeedsLayout()
    }

    /// One layer per fabric, every piece cut from it a subpath: an edge
    /// interior to a fabric is then no edge at all, and the seal stroke that
    /// closes the hairline between two fabrics is paid once per fabric.
    private func setCuts(_ pieces: [QuiltBlocks.Cut]) {
        cuts.forEach { $0.removeFromSuperlayer() }
        cuts = []
        var order: [String] = []
        var paths: [String: CGMutablePath] = [:]
        for piece in pieces where piece.points.count >= 3 {
            let path = paths[piece.hex] ?? { order.append(piece.hex); let p = CGMutablePath(); paths[piece.hex] = p; return p }()
            path.addLines(between: piece.points)
            path.closeSubpath()
        }
        for hex in order {
            let shape = CAShapeLayer()
            shape.path = paths[hex]
            let color = (UIColor(hex: hex) ?? .systemGray).cgColor
            shape.fillColor = color
            shape.strokeColor = color
            shape.lineJoin = .round
            shape.frame = block.bounds
            block.addSublayer(shape)
            cuts.append(shape)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        block.position = CGPoint(x: side / 2, y: side / 2)
        block.transform = CATransform3DConcat(CATransform3DMakeScale(side, side, 1), CATransform3DMakeRotation(CGFloat(rotation) * .pi / 180, 0, 0, 1))
        for mark in marks { mark.position = mark.corner.point(side: side) }
        CATransaction.commit()
    }

    /// Hold the marks at a fixed on-screen size and the seal at a hairline,
    /// whatever the zoom. One size per tile, so its marks appear and vanish
    /// together; they shrink, then go, when the tile is too small to host them.
    func apply(zoom: CGFloat) {
        let side = bounds.width
        guard side > 0 else { return }
        for cut in cuts { cut.lineWidth = 1 / (zoom * side) }
        let px = min(QuiltInk.markSize, side * zoom * QuiltInk.markShare)
        let hidden = px < QuiltInk.markMin
        for mark in marks {
            mark.isHidden = hidden
            let scale = px / QuiltInk.markSize / zoom
            mark.transform = CATransform3DMakeScale(scale, scale, 1)
        }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.65 : 1 }
    }
}

/// A small disc in one corner carrying one glyph, anchored on that corner so
/// counter-scaling keeps it inset by the same screen distance at any zoom.
/// Every disc wears a seam ring and a shadow because it sits on arbitrary
/// fabric — often the very colour it is filled with.
final class CornerMark: CALayer {
    enum Corner {
        case topLeft, topRight, bottomRight
        var anchor: CGPoint {
            switch self { case .topLeft: return CGPoint(x: 0, y: 0); case .topRight: return CGPoint(x: 1, y: 0); case .bottomRight: return CGPoint(x: 1, y: 1) }
        }
        func point(side: CGFloat) -> CGPoint { CGPoint(x: anchor.x * side, y: anchor.y * side) }
    }
    let corner: Corner
    private let disc = CAShapeLayer()

    init(corner: Corner, disc fill: UIColor, glyph: CGImage?) {
        self.corner = corner
        super.init()
        let extent = QuiltInk.markInset + QuiltInk.markSize + QuiltInk.markInset
        bounds = CGRect(x: 0, y: 0, width: extent, height: extent)
        anchorPoint = corner.anchor
        let centre = QuiltInk.markInset + QuiltInk.markSize / 2
        let radius = QuiltInk.markSize / 2
        let shadow = CAShapeLayer()
        shadow.path = CGPath(ellipseIn: CGRect(x: centre - radius + QuiltInk.markShadowOffset, y: centre - radius + QuiltInk.markShadowOffset,
                                               width: QuiltInk.markSize, height: QuiltInk.markSize), transform: nil)
        shadow.fillColor = QuiltInk.markShadow.cgColor
        addSublayer(shadow)
        disc.path = CGPath(ellipseIn: CGRect(x: centre - radius, y: centre - radius, width: QuiltInk.markSize, height: QuiltInk.markSize), transform: nil)
        disc.fillColor = fill.cgColor
        disc.lineWidth = 1.5
        addSublayer(disc)
        let image = CALayer()
        image.contents = glyph
        image.contentsGravity = .resizeAspect
        image.frame = CGRect(x: centre - QuiltInk.markGlyph / 2, y: centre - QuiltInk.markGlyph / 2, width: QuiltInk.markGlyph, height: QuiltInk.markGlyph)
        addSublayer(image)
        // The ring is theme ink; the disc is not, so only the ring re-resolves.
        disc.strokeColor = QuiltInk.threadHeavy.resolvedColor(with: UITraitCollection.current).cgColor
    }
    override init(layer: Any) {
        corner = (layer as? CornerMark)?.corner ?? .topLeft
        super.init(layer: layer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

extension Motifs {
    private static var glyphs: [String: CGImage] = [:]

    /// A motif rendered in one colour at mark size, cached: marks are stamped
    /// once per tile and counter-scaled from there.
    static func glyph(_ key: String, color: UIColor) -> CGImage? {
        render(name: "motif-\(key)", color: color)
    }
    static func unclaimedGlyph(color: UIColor) -> CGImage? { render(name: "mark-unclaimed", color: color) }

    private static func render(name: String, color: UIColor) -> CGImage? {
        let cacheKey = "\(name)|\(color.description)"
        if let hit = glyphs[cacheKey] { return hit }
        guard let image = UIImage(named: name) else { return nil }
        let side = QuiltInk.markGlyph
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let drawn = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.withTintColor(color, renderingMode: .alwaysOriginal).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        glyphs[cacheKey] = drawn.cgImage
        return drawn.cgImage
    }
}
