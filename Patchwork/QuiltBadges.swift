// SPDX-License-Identifier: MPL-2.0
import UIKit

/// Name badges: the pill floating over a tile that names its patch, and
/// nothing else (CONTEXT.md "Name badge"). Badges are pinned to their tiles
/// and travel with the quilt; which tiles wear one is decided by zoom and
/// tile size alone, over the whole quilt, so panning never changes the set.
/// Where badges would crowd, the larger tile wins and the rest wait for a
/// closer zoom. The thresholds are the web's, each of which was measured
/// before it was set — see QuiltCanvas.svelte for the sweeps behind them.
enum QuiltBadges {
    /// On-screen tile size that earns a badge, and the smaller size an
    /// incumbent holds down to. A name already read should not blink off and
    /// back on while the reader pinches.
    static let minPx: CGFloat = 52
    static let keepPx: CGFloat = 44
    /// Width cap as a multiple of the badge's own type size, and how deep a
    /// name may stack: tiles are square and a pill is wide, so wrapping spends
    /// the dimension that has room.
    static let textEm: CGFloat = 8.5
    static let maxLines = 3
    /// Quilt a new badge owes its neighbours, what an incumbent owes on a
    /// roomy tile, and the tile size at which it is owed in full.
    static let gap: CGFloat = 32
    static let keepGap: CGFloat = 26
    static let roomyPx: CGFloat = 80

    struct Shape: Hashable {
        let textWidth: CGFloat
        let lines: Int
    }

    /// The badge's type and the box its chrome adds around the text, derived
    /// from one size so the cap, the footprint and the collision test move
    /// together when Dynamic Type does.
    struct Typeface {
        let font: UIFont
        let lineHeight: CGFloat
        let textMax: CGFloat
        let chromeX: CGFloat
        let chromeY: CGFloat
        let radius: CGFloat
        init(size: CGFloat) {
            // The badge is the quilt's own label and is set in the quilt's
            // own face, as the web sets it (`--font`); SF Pro stands in only
            // if the bundled font failed to register.
            font = PWType.baseFont(.text, size: size, weight: 600)
            lineHeight = (size * 1.3).rounded()
            textMax = (size * QuiltBadges.textEm).rounded()
            chromeX = 2 * (0.4 * size).rounded() + 2
            chromeY = 2 * (0.2 * size).rounded() + 2
            radius = 0.5 * size
        }
        /// Caption-sized, following the reader's text size up to a bound the
        /// tiles can carry.
        static func current() -> Typeface {
            Typeface(size: min(UIFont.preferredFont(forTextStyle: .caption1).pointSize, 17))
        }
    }

    /// A tile: its id, its name, and its frame at the current zoom, in the
    /// badge layer's coordinates — points on screen, wherever the screen is.
    struct Candidate {
        let id: String
        let name: String
        let rect: CGRect
    }

    struct Placement: Equatable {
        let id: String
        let name: String
        let rect: CGRect
        let shape: Shape
    }

    /// Every shape one name can wear, shallowest first, measured once per name.
    final class Measurer {
        private(set) var type: Typeface
        private var cache: [String: [Shape]] = [:]
        init(type: Typeface) { self.type = type }
        func reset(type: Typeface) { self.type = type; cache = [:] }

        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: type.font]).width
        }

        func shapes(_ name: String) -> [Shape] {
            if let hit = cache[name] { return hit }
            var shapes: [Shape] = []
            let full = width(name)
            if full <= type.textMax { shapes.append(Shape(textWidth: full.rounded(.up), lines: 1)) }
            // Deeper splits, kept only while each buys a narrower pill; +2pt
            // slack absorbs measurement-versus-layout rounding.
            let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
            var narrowest = full
            var lines = 2
            while lines <= QuiltBadges.maxLines && words.count >= lines {
                var memo: [Int: CGFloat] = [:]
                let best = balanced(words, lines: lines, from: 0, memo: &memo)
                if best >= narrowest { break }
                narrowest = best
                if best <= type.textMax { shapes.append(Shape(textWidth: best.rounded(.up) + 2, lines: lines)) }
                lines += 1
            }
            if shapes.isEmpty {
                // One unbroken word, or more name than the budget holds: sit at
                // the cap and let the label truncate mid-word.
                let wrapped = min(Int((full / type.textMax).rounded(.up)), QuiltBadges.maxLines)
                shapes.append(Shape(textWidth: type.textMax, lines: max(2, wrapped)))
            }
            cache[name] = shapes
            return shapes
        }

        /// Narrowest balanced width for `words` on exactly `lines` lines: the
        /// widest line under the best split, so a long tail word is never
        /// stranded by a greedy first cut.
        private func balanced(_ words: [String], lines: Int, from: Int, memo: inout [Int: CGFloat]) -> CGFloat {
            if lines == 1 { return width(words[from...].joined(separator: " ")) }
            let key = from * 8 + lines
            if let hit = memo[key] { return hit }
            var best = CGFloat.infinity
            var end = from + 1
            while end <= words.count - (lines - 1) {
                let head = width(words[from..<end].joined(separator: " "))
                if head >= best { break }
                best = min(best, max(head, balanced(words, lines: lines - 1, from: end, memo: &memo)))
                end += 1
            }
            memo[key] = best
            return best
        }
    }

    /// Which tiles wear a badge at this zoom, and in what shape. Incumbents go
    /// first and keep their spot for as long as they can hold a badge at all;
    /// then larger tiles, so the bigger name wins a collision. A pill that
    /// does not fit stacks onto another line and asks again, and only a name
    /// that fits at no depth gives up its badge. The plan covers the whole
    /// quilt and knows nothing of the screen: a badge sits at its tile's
    /// centre, and the screen's edges and the bars cut it as they cut the tile.
    static func plan(_ candidates: [Candidate], held: Set<String>, type: Typeface,
                     shapes: (String) -> [Shape]) -> [Placement] {
        let sorted = candidates.enumerated().sorted { a, b in
            let ha = held.contains(a.element.id), hb = held.contains(b.element.id)
            if ha != hb { return ha }
            if a.element.rect.width != b.element.rect.width { return a.element.rect.width > b.element.rect.width }
            return a.offset < b.offset
        }.map(\.element)
        var placed = Buckets()
        var out: [Placement] = []
        for candidate in sorted {
            let screenPx = candidate.rect.width
            let incumbent = held.contains(candidate.id)
            if screenPx < (incumbent ? keepPx : minPx) { continue }
            // What this badge owes its neighbours: the full gap to move in; to
            // stay, a gap that slides toward keepGap as its tile grows past the
            // floor — leniency only while there is a tile under it worth reading.
            let relax = incumbent ? max(0, min(1, (screenPx - minPx) / (roomyPx - minPx))) : 0
            let owed = gap + (keepGap - gap) * relax
            for shape in shapes(candidate.name) {
                let w = shape.textWidth + type.chromeX
                let h = type.chromeY + CGFloat(shape.lines) * type.lineHeight
                let box = CGRect(x: candidate.rect.midX - w / 2, y: candidate.rect.midY - h / 2, width: w, height: h)
                let grown = box.insetBy(dx: -owed, dy: -owed)
                if placed.collides(grown) { continue }
                placed.insert(box)
                out.append(Placement(id: candidate.id, name: candidate.name, rect: box, shape: shape))
                break
            }
        }
        return out
    }

    /// Placed pills bucketed by area, so the collision test asks only the
    /// neighbourhood: planning the whole quilt on every zoom tick is then
    /// linear in its tiles rather than quadratic.
    private struct Buckets {
        private struct Cell: Hashable { let x: Int; let y: Int }
        private static let side: CGFloat = 128
        private var cells: [Cell: [CGRect]] = [:]
        private func span(_ rect: CGRect) -> (ClosedRange<Int>, ClosedRange<Int>) {
            (Int((rect.minX / Self.side).rounded(.down))...Int((rect.maxX / Self.side).rounded(.down)),
             Int((rect.minY / Self.side).rounded(.down))...Int((rect.maxY / Self.side).rounded(.down)))
        }
        func collides(_ rect: CGRect) -> Bool {
            let (xs, ys) = span(rect)
            for x in xs { for y in ys where cells[Cell(x: x, y: y)]?.contains(where: { rect.intersects($0) }) == true { return true } }
            return false
        }
        mutating func insert(_ rect: CGRect) {
            let (xs, ys) = span(rect)
            for x in xs { for y in ys { cells[Cell(x: x, y: y), default: []].append(rect) } }
        }
    }
}

/// The layer badges live in: a sibling of the zoomed board inside the scroll
/// view, so it scrolls with the quilt for free and a pan costs the badges
/// nothing — no plan, no layout. It is not zoomed itself: its coordinates are
/// the board's at the current zoom, so a pill keeps its point size while the
/// tile under it grows, and the canvas re-plans it on every zoom tick. Only
/// the badges near the screen are realised as views, so a quilt of hundreds
/// does not carry hundreds of blurs; which ones exist is invisible, because
/// the set itself never depends on the screen. It takes no touches; the
/// canvas hands a touch on a badge to the badge's patch.
final class BadgeLayer: UIView {
    /// Called when the reader's text size changes, so the canvas re-plans.
    var onTypeChange: (() -> Void)?
    private var placements: [QuiltBadges.Placement] = []
    private var views: [String: BadgeView] = [:]
    /// Badges fading out after a zoom took their room, kept apart so a touch
    /// never lands on one and a returning name can take it back.
    private var leaving: [String: BadgeView] = [:]
    private var spare: [BadgeView] = []
    private var held = Set<String>()
    private var type = QuiltBadges.Typeface.current()
    private lazy var measurer = QuiltBadges.Measurer(type: type)
    /// What is on screen, and the wider region whose badges exist as views.
    private var visible = CGRect.null
    private var realised = CGRect.null

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (layer: Self, _: UITraitCollection) in
            layer.textSizeChanged()
        }
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        clipsToBounds = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The patch whose badge is under a point, if any.
    func badge(at point: CGPoint) -> String? {
        views.first { !$0.value.isHidden && $0.value.frame.contains(point) }?.key
    }

    /// A new plan for a new zoom, a new quilt or a new text size. With `fade`
    /// a badge that comes or goes does so over a moment, unless the reader
    /// has asked for less motion.
    func plan(_ candidates: [QuiltBadges.Candidate], visible: CGRect, fade: Bool) {
        placements = QuiltBadges.plan(candidates, held: held, type: type, shapes: measurer.shapes)
        held = Set(placements.map(\.id))
        self.visible = visible
        sync(fade: fade && !UIAccessibility.isReduceMotionEnabled)
    }

    /// The screen moved over the quilt. Nothing is planned; badges only come
    /// into being as views when the screen nears them.
    func reveal(_ visible: CGRect) {
        self.visible = visible
        if realised.contains(visible) { return }
        sync(fade: false)
    }

    private func sync(fade: Bool) {
        guard !visible.isNull, !visible.isEmpty else { return }
        realised = visible.insetBy(dx: -visible.width / 2, dy: -visible.height / 2)
        var wanted = Set<String>()
        for placement in placements where placement.rect.intersects(realised) {
            wanted.insert(placement.id)
            let view: BadgeView
            if let live = views[placement.id] {
                view = live
            } else if let returning = leaving.removeValue(forKey: placement.id) {
                returning.layer.removeAllAnimations()
                returning.alpha = 1
                view = returning
            } else {
                view = spare.popLast() ?? { let made = BadgeView(); addSubview(made); return made }()
                view.isHidden = false
                view.alpha = 1
                if fade && placement.rect.intersects(visible) {
                    view.alpha = 0
                    UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) { view.alpha = 1 }
                }
            }
            views[placement.id] = view
            view.configure(name: placement.name, shape: placement.shape, type: type)
            view.frame = placement.rect
        }
        for (id, view) in views where !wanted.contains(id) {
            views[id] = nil
            if fade && !held.contains(id) && view.frame.intersects(visible) {
                leaving[id] = view
                UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) { view.alpha = 0 } completion: { [weak self] _ in
                    guard let self, self.leaving[id] === view else { return }
                    self.leaving[id] = nil
                    self.retire(view)
                }
            } else {
                retire(view)
            }
        }
    }

    /// A badge no longer wanted goes back to the pool hidden, so the next
    /// one to appear does not pay for a new blur.
    private func retire(_ view: BadgeView) {
        view.layer.removeAllAnimations()
        view.isHidden = true
        if spare.count < 48 { spare.append(view) } else { view.removeFromSuperview() }
    }

    /// A new text size re-measures every badge: the type is the reader's.
    private func textSizeChanged() {
        type = .current()
        measurer.reset(type: type)
        held = []
        onTypeChange?()
    }
}

/// One frosted pill in the reader's own theme: the name, centred, balanced
/// across the lines it was measured at, a hairline of thread around it.
final class BadgeView: UIView {
    private let label = UILabel()
    private var lines = 1

    private let frost = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _: UITraitCollection) in
            view.applyTheme()
        }
        isUserInteractionEnabled = false
        // Frosted, the way the web's badge is: a blur behind the tinted pill,
        // so the name earns its contrast from the reader's theme rather than
        // from whatever fabric happens to lie under it.
        clipsToBounds = true
        frost.frame = bounds
        frost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        frost.isUserInteractionEnabled = false
        addSubview(frost)
        backgroundColor = .clear
        frost.contentView.backgroundColor = QuiltInk.labelBackground
        layer.borderWidth = 1
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.textColor = QuiltInk.labelText
        label.isAccessibilityElement = false
        addSubview(label)
        isAccessibilityElement = false
        applyTheme()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(name: String, shape: QuiltBadges.Shape, type: QuiltBadges.Typeface) {
        lines = shape.lines
        label.numberOfLines = shape.lines
        layer.cornerRadius = type.radius
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = type.lineHeight
        paragraph.maximumLineHeight = type.lineHeight
        paragraph.lineBreakMode = .byTruncatingTail
        if label.text != name || label.font != type.font {
            label.attributedText = NSAttributedString(string: name, attributes: [.font: type.font, .paragraphStyle: paragraph, .foregroundColor: QuiltInk.labelText])
        }
        label.frame = CGRect(x: type.chromeX / 2, y: type.chromeY / 2, width: shape.textWidth, height: CGFloat(shape.lines) * type.lineHeight)
    }

    private func applyTheme() {
        layer.borderColor = QuiltInk.thread.resolvedColor(with: traitCollection).cgColor
    }
    // The border is a dynamic colour resolved by hand, so a change of
    // appearance resolves it again.
}
