// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import UIKit

struct QuiltCanvas: UIViewRepresentable {
    let tiles: [QuiltLayout.Tile]
    let patches: [Patch]
    let fitRequest: Int
    let select: (Patch) -> Void
    func makeUIView(context: Context) -> CanvasScrollView { CanvasScrollView() }
    func updateUIView(_ view: CanvasScrollView, context: Context) {
        view.update(tiles: tiles, patches: patches, fitRequest: fitRequest, select: select)
    }
}

final class CanvasScrollView: UIScrollView, UIScrollViewDelegate {
    private let board = UIView()
    private var buttons: [String: QuiltTileButton] = [:]
    private var current: [QuiltLayout.Tile] = []
    private var currentPatches: [Patch] = []
    private var request = -1
    private var needsFit = true
    private var lastBounds = CGSize.zero
    private var suppressSelectionUntil = 0.0
    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 0.3
        maximumZoomScale = 6
        backgroundColor = .systemGroupedBackground
        board.backgroundColor = .clear
        addSubview(board)
        accessibilityIdentifier = "quiltCanvas"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        suppressSelectionUntil = .infinity
    }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        suppressSelectionUntil = Date.timeIntervalSinceReferenceDate + 0.25
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { board }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        for button in buttons.values { button.updateLabelScale(zoomScale) }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastBounds { needsFit = true; lastBounds = bounds.size }
        if needsFit && bounds.width > 0 && board.bounds.width > 0 {
            needsFit = false
            let fit = min(bounds.width / board.bounds.width, bounds.height / board.bounds.height)
            setZoomScale(min(2.4, max(0.65, fit)), animated: false)
            contentOffset = CGPoint(x: max(0, (contentSize.width - bounds.width) / 2), y: max(0, (contentSize.height - bounds.height) / 2))
        }
        let horizontal = max(0, (bounds.width - board.frame.width) / 2)
        let vertical = max(0, (bounds.height - board.frame.height) / 2)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }
    func update(tiles: [QuiltLayout.Tile], patches: [Patch], fitRequest: Int, select: @escaping (Patch) -> Void) {
        if request != fitRequest { request = fitRequest; needsFit = true; setNeedsLayout() }
        guard current != tiles || currentPatches != patches else { return }
        currentPatches = patches
        let animate = !current.isEmpty && !UIAccessibility.isReduceMotionEnabled
        current = tiles
        let minX = tiles.map(\.x).min() ?? 0, minY = tiles.map(\.y).min() ?? 0
        let maxX = tiles.map { $0.x + $0.size }.max() ?? 1, maxY = tiles.map { $0.y + $0.size }.max() ?? 1
        let ids = Set(tiles.map(\.id))
        for id in Array(buttons.keys) where !ids.contains(id) { buttons.removeValue(forKey: id)?.removeFromSuperview() }
        let lookup = Dictionary(uniqueKeysWithValues: patches.map { ($0.id, $0) })
        let changes = {
            self.board.bounds = CGRect(x: 0, y: 0, width: Double(maxX - minX) * 76 + 32, height: Double(maxY - minY) * 76 + 32)
            self.board.frame.origin = .zero
            for tile in tiles {
                guard let patch = lookup[tile.id] else { continue }
                let button = self.buttons[tile.id] ?? QuiltTileButton()
                if self.buttons[tile.id] == nil {
                    self.buttons[tile.id] = button
                    self.board.addSubview(button)
                }
                button.caption.text = patch.name
                button.updateLabelScale(self.zoomScale)
                button.accessibilityLabel = patch.name
                button.accessibilityHint = "Opens patch details"
                button.accessibilityIdentifier = "quiltTile-\(patch.slug)"
                button.removeAction(identifiedBy: UIAction.Identifier("open"), for: .touchUpInside)
                button.addAction(UIAction(identifier: UIAction.Identifier("open")) { [weak self] _ in
                    guard let self, !self.isZooming, !self.isDragging, !self.isDecelerating,
                          Date.timeIntervalSinceReferenceDate >= self.suppressSelectionUntil else { return }
                    select(patch)
                }, for: .touchUpInside)
                button.frame = CGRect(x: Double(tile.x - minX) * 76 + 16, y: Double(tile.y - minY) * 76 + 16, width: Double(tile.size) * 76 - 4, height: Double(tile.size) * 76 - 4)
            }
            self.contentSize = self.board.frame.size
        }
        if animate { UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes) }
        else { changes() }
        needsFit = true
        setNeedsLayout()
    }
}

/// An explicitly bounded label prevents UIButton configuration layout from
/// centering an oversized text block outside a small quilt tile.
final class QuiltTileButton: UIButton {
    let caption = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 8
        clipsToBounds = true
        caption.textColor = .label
        caption.numberOfLines = 3
        caption.lineBreakMode = .byTruncatingTail
        caption.isAccessibilityElement = false
        caption.isUserInteractionEnabled = false
        addSubview(caption)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        caption.frame = bounds.insetBy(dx: 8, dy: 8)
    }
    func updateLabelScale(_ scale: CGFloat) {
        caption.font = .systemFont(ofSize: min(18, UIFont.preferredFont(forTextStyle: .caption1).pointSize) / scale, weight: .medium)
    }
    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.65 : 1 }
    }
}
