// SPDX-License-Identifier: MPL-2.0
import UIKit

/// Name badges: the pill floating over a tile that names its patch, and
/// nothing else (CONTEXT.md "Name badge"). Badges reveal progressively as
/// tiles earn on-screen room; where they would crowd, the larger tile wins
/// and the rest wait for a closer zoom. The thresholds are the web's, each of
/// which was measured before it was set — see QuiltCanvas.svelte for the
/// sweeps behind them.
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
    /// Visible quilt a new badge owes its neighbours, what an incumbent owes
    /// on a roomy tile, and the tile size at which it is owed in full.
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
            font = .systemFont(ofSize: size, weight: .semibold)
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

    /// A tile on screen: its id, its name, and its frame in the badge layer's coordinates.
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

    /// Which tiles wear a badge this pass, and in what shape. Incumbents go
    /// first and keep their spot for as long as they can hold a badge at all;
    /// then larger tiles, so the bigger name wins a collision. A pill that
    /// does not fit stacks onto another line and asks again, and only a name
    /// that fits at no depth gives up its badge.
    static func plan(_ candidates: [Candidate], held: Set<String>, viewport: CGSize, type: Typeface,
                     shapes: (String) -> [Shape]) -> [Placement] {
        let sorted = candidates.enumerated().sorted { a, b in
            let ha = held.contains(a.element.id), hb = held.contains(b.element.id)
            if ha != hb { return ha }
            if a.element.rect.width != b.element.rect.width { return a.element.rect.width > b.element.rect.width }
            return a.offset < b.offset
        }.map(\.element)
        var placed: [CGRect] = []
        var out: [Placement] = []
        for candidate in sorted {
            let screenPx = candidate.rect.width
            let incumbent = held.contains(candidate.id)
            if screenPx < (incumbent ? keepPx : minPx) { continue }
            let x = candidate.rect.midX, y = candidate.rect.midY
            if x < -150 || x > viewport.width + 150 || y < -50 || y > viewport.height + 50 { continue }
            // What this badge owes its neighbours: the full gap to move in; to
            // stay, a gap that slides toward keepGap as its tile grows past the
            // floor — leniency only while there is a tile under it worth reading.
            let relax = incumbent ? max(0, min(1, (screenPx - minPx) / (roomyPx - minPx))) : 0
            let owed = gap + (keepGap - gap) * relax
            for shape in shapes(candidate.name) {
                let w = shape.textWidth + type.chromeX
                let h = type.chromeY + CGFloat(shape.lines) * type.lineHeight
                let box = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
                let grown = box.insetBy(dx: -owed, dy: -owed)
                if placed.contains(where: { grown.intersects($0) }) { continue }
                placed.append(box)
                out.append(Placement(id: candidate.id, name: candidate.name, rect: box, shape: shape))
                break
            }
        }
        return out
    }
}

/// The non-scrolling layer badges live in: screen space, above the canvas,
/// clipped at the viewport so a badge at the edge clips rather than reshapes.
/// It takes no touches itself; the canvas hands a touch on a badge to the
/// badge's patch.
final class BadgeLayer: UIView {
    private var views: [String: BadgeView] = [:]
    private var held = Set<String>()
    private var type = QuiltBadges.Typeface.current()
    private lazy var measurer = QuiltBadges.Measurer(type: type)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The patch whose badge is under a point, if any.
    func badge(at point: CGPoint) -> String? {
        views.first { $0.value.frame.contains(point) }?.key
    }

    func apply(_ candidates: [QuiltBadges.Candidate]) {
        let placements = QuiltBadges.plan(candidates, held: held, viewport: bounds.size, type: type, shapes: measurer.shapes)
        held = Set(placements.map(\.id))
        for placement in placements {
            let view = views[placement.id] ?? {
                let view = BadgeView()
                addSubview(view)
                views[placement.id] = view
                return view
            }()
            view.configure(name: placement.name, shape: placement.shape, type: type)
            view.frame = placement.rect
        }
        for (id, view) in views where !held.contains(id) {
            view.removeFromSuperview()
            views[id] = nil
        }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            type = .current()
            measurer.reset(type: type)
            held = []
        }
    }
}

/// One frosted pill in the reader's own theme: the name, centred, balanced
/// across the lines it was measured at, a hairline of thread around it.
final class BadgeView: UIView {
    private let label = UILabel()
    private var lines = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = QuiltInk.labelBackground
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
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        applyTheme()
    }
}
