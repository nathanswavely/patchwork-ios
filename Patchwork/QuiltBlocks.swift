// SPDX-License-Identifier: MPL-2.0
import CoreGraphics
import Foundation

/// The curated block registry and the drafted-block engine — the client's
/// copy of quiltBlocks.js and draftGeometry.js. A block is a list of pieces in
/// the unit square, in paint order, each cut from one fabric; the canvas
/// scales them to the tile and rotates them about its centre.
enum QuiltBlocks {
    enum Fabric { case primary, secondary, bg }
    struct Piece {
        let points: [CGPoint]
        let fabric: Fabric
        init(_ points: [CGPoint], _ fabric: Fabric) { self.points = points; self.fabric = fabric }
    }
    /// A piece resolved to the colour it is cut from.
    struct Cut { let points: [CGPoint]; let hex: String }

    static let keys = ["pinwheel", "ohioStar", "brokenDishes", "flyingGeese", "fourPatch", "ninePatch",
                       "hourglass", "sawtoothStar", "railFence", "logCabin", "bearsPaw", "windmill"]
    static let names = ["Pinwheel", "Ohio Star", "Broken Dishes", "Flying Geese", "Four Patch", "Nine Patch",
                        "Hourglass", "Sawtooth Star", "Rail Fence", "Log Cabin", "Bear's Paw", "Windmill"]
    private static let indexByKey = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, $0) })

    /// Block index for a patch, honouring a pinned curated slug.
    static func index(id: String, appearance: Appearance?) -> Int {
        if case let .curated(slug)? = appearance?.block, let pinned = indexByKey[slug] { return pinned }
        return QuiltTheme.index(id, count: keys.count)
    }
    /// Rotation in degrees, honouring a pinned one.
    static func rotation(id: String, appearance: Appearance?) -> Int {
        if let r = appearance?.rotation, [0, 90, 180, 270].contains(r) { return r }
        return [0, 90, 180, 270][QuiltTheme.index(id + "_rot", count: 4)]
    }

    /// Every piece a tile draws, resolved to hex, in paint order: a valid draft
    /// renders as drafted, anything else as the curated block the id or the
    /// appearance names.
    static func cuts(id: String, appearance: Appearance?, palette: QuiltTheme.Palette) -> [Cut] {
        if case let .drafted(draft)? = appearance?.block, DraftGeometry.isValid(draft) {
            return draftCuts(draft, palette: palette)
        }
        return curated(index(id: id, appearance: appearance)).map { piece in
            let hex: String
            switch piece.fabric {
            case .primary: hex = palette.primary
            case .secondary: hex = palette.secondary
            case .bg: hex = palette.bg
            }
            return Cut(points: piece.points, hex: hex)
        }
    }

    /// A drafted block: the ground, then every piece of every cell coloured by
    /// bundle slot; missing entries take slot zero and slots past the bundle wrap.
    static func draftCuts(_ draft: DraftedBlock, palette: QuiltTheme.Palette) -> [Cut] {
        let slots = palette.slots.isEmpty ? [palette.primary, palette.secondary, palette.bg] : palette.slots
        let scale = 1 / (4 * Double(draft.grid))
        var cuts = [Cut(points: rect(0, 0, 1, 1), hex: palette.bg)]
        for cell in DraftGeometry.faces(for: draft) {
            let cellSlots = draft.colors?["\(cell.r),\(cell.c)"] ?? []
            for (i, face) in cell.faces.enumerated() {
                let slot = i < cellSlots.count ? cellSlots[i] : 0
                let hex = slot < slots.count ? slots[slot] : slots[slot % slots.count]
                cuts.append(Cut(points: face.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }, hex: hex))
            }
        }
        return cuts
    }

    static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> [CGPoint] {
        [CGPoint(x: x, y: y), CGPoint(x: x + w, y: y), CGPoint(x: x + w, y: y + h), CGPoint(x: x, y: y + h)]
    }
    private static func poly(_ coords: [(Double, Double)]) -> [CGPoint] { coords.map { CGPoint(x: $0.0, y: $0.1) } }

    /// The twelve traditional blocks, transcribed piece for piece from the web.
    static func curated(_ index: Int) -> [Piece] {
        let h = 0.5
        switch keys[abs(index) % keys.count] {
        case "pinwheel":
            return [
                Piece(poly([(0, 0), (h, 0), (h, h)]), .primary), Piece(poly([(h, 0), (1, 0), (h, h)]), .bg),
                Piece(poly([(1, 0), (1, h), (h, h)]), .secondary), Piece(poly([(1, h), (1, 1), (h, h)]), .bg),
                Piece(poly([(1, 1), (h, 1), (h, h)]), .primary), Piece(poly([(h, 1), (0, 1), (h, h)]), .bg),
                Piece(poly([(0, 1), (0, h), (h, h)]), .secondary), Piece(poly([(0, h), (0, 0), (h, h)]), .bg),
            ]
        case "ohioStar":
            let t = 1.0 / 3, m = t / 2
            return [
                Piece(rect(0, 0, 1, 1), .bg),
                Piece(rect(0, 0, t, t), .secondary), Piece(rect(2 * t, 0, t, t), .secondary),
                Piece(rect(0, 2 * t, t, t), .secondary), Piece(rect(2 * t, 2 * t, t, t), .secondary),
                Piece(rect(t, t, t, t), .primary),
                Piece(poly([(t, 0), (t + m, t), (2 * t, 0)]), .primary),
                Piece(poly([(t, 1), (t + m, 2 * t), (2 * t, 1)]), .primary),
                Piece(poly([(0, t), (t, t + m), (0, 2 * t)]), .primary),
                Piece(poly([(1, t), (2 * t, t + m), (1, 2 * t)]), .primary),
            ]
        case "brokenDishes":
            return [
                Piece(poly([(0, 0), (h, 0), (0, h)]), .primary), Piece(poly([(h, 0), (h, h), (0, h)]), .bg),
                Piece(poly([(h, 0), (1, 0), (1, h)]), .bg), Piece(poly([(h, 0), (1, h), (h, h)]), .secondary),
                Piece(poly([(0, h), (h, h), (h, 1)]), .secondary), Piece(poly([(0, h), (h, 1), (0, 1)]), .bg),
                Piece(poly([(h, h), (1, h), (h, 1)]), .bg), Piece(poly([(1, h), (1, 1), (h, 1)]), .primary),
            ]
        case "flyingGeese":
            let row = 0.25
            return [Piece(rect(0, 0, 1, 1), .bg)] + (0..<4).map { i in
                let y = Double(i) * row
                return Piece(poly([(0, y + row), (0.5, y), (1, y + row)]), i % 2 == 0 ? .primary : .secondary)
            }
        case "fourPatch":
            return [Piece(rect(0, 0, h, h), .primary), Piece(rect(h, 0, h, h), .secondary),
                    Piece(rect(0, h, h, h), .secondary), Piece(rect(h, h, h, h), .primary)]
        case "ninePatch":
            let t = 1.0 / 3
            var pieces: [Piece] = []
            for r in 0..<3 { for c in 0..<3 {
                let fabric: Fabric = (r + c) % 2 == 0 ? .primary : ((r + c) % 3 == 0 ? .secondary : .bg)
                pieces.append(Piece(rect(Double(c) * t, Double(r) * t, t, t), fabric))
            } }
            return pieces
        case "hourglass":
            return [Piece(rect(0, 0, 1, 1), .bg), Piece(poly([(0, 0), (1, 0), (h, h)]), .primary),
                    Piece(poly([(0, 1), (1, 1), (h, h)]), .secondary)]
        case "sawtoothStar":
            let t = 0.25
            return [
                Piece(rect(0, 0, 1, 1), .bg), Piece(rect(t, t, 2 * t, 2 * t), .primary),
                Piece(poly([(t, 0), (2 * t, t), (3 * t, 0)]), .secondary),
                Piece(poly([(t, 1), (2 * t, 3 * t), (3 * t, 1)]), .secondary),
                Piece(poly([(0, t), (t, 2 * t), (0, 3 * t)]), .secondary),
                Piece(poly([(1, t), (3 * t, 2 * t), (1, 3 * t)]), .secondary),
                Piece(rect(0, 0, t, t), .secondary), Piece(rect(3 * t, 0, t, t), .secondary),
                Piece(rect(0, 3 * t, t, t), .secondary), Piece(rect(3 * t, 3 * t, t, t), .secondary),
            ]
        case "railFence":
            let u = 0.2
            return [
                Piece(poly([(0, 0), (2 * u, 0), (0, 2 * u)]), .primary),
                Piece(poly([(2 * u, 0), (4 * u, 0), (0, 4 * u), (0, 2 * u)]), .bg),
                Piece(poly([(4 * u, 0), (1, 0), (1, u), (u, 1), (0, 1), (0, 4 * u)]), .secondary),
                Piece(poly([(1, u), (1, 3 * u), (3 * u, 1), (u, 1)]), .bg),
                Piece(poly([(1, 3 * u), (1, 1), (3 * u, 1)]), .primary),
            ]
        case "logCabin":
            let step = 1.0 / 8
            return (0..<4).map { i in
                let inset = Double(i) * step
                return Piece(rect(inset, inset, 1 - 2 * inset, 1 - 2 * inset), i == 0 ? .primary : (i % 2 == 0 ? .secondary : .bg))
            }
        case "bearsPaw":
            let t = 0.25
            return [
                Piece(rect(0, 0, 1, 1), .bg), Piece(rect(t, t, 2 * t, 2 * t), .primary),
                Piece(rect(0, 0, t, t), .secondary), Piece(rect(3 * t, 0, t, t), .secondary),
                Piece(rect(0, 3 * t, t, t), .secondary), Piece(rect(3 * t, 3 * t, t, t), .secondary),
                Piece(poly([(t, 0), (t, t), (2 * t, 0)]), .secondary),
                Piece(poly([(0, t), (t, t), (0, 2 * t)]), .secondary),
                Piece(poly([(3 * t, 0), (3 * t, t), (2 * t, 0)]), .secondary),
                Piece(poly([(1, t), (3 * t, t), (1, 2 * t)]), .secondary),
                Piece(poly([(t, 1), (t, 3 * t), (2 * t, 1)]), .secondary),
                Piece(poly([(0, 3 * t), (t, 3 * t), (0, 2 * t)]), .secondary),
                Piece(poly([(3 * t, 1), (3 * t, 3 * t), (2 * t, 1)]), .secondary),
                Piece(poly([(1, 3 * t), (3 * t, 3 * t), (1, 2 * t)]), .secondary),
            ]
        default: // windmill
            return [
                Piece(rect(0, 0, 1, 1), .bg),
                Piece(poly([(0, 0), (h, 0), (h, h)]), .primary), Piece(poly([(1, 0), (1, h), (h, h)]), .secondary),
                Piece(poly([(1, 1), (h, 1), (h, h)]), .primary), Piece(poly([(0, 1), (0, h), (h, h)]), .secondary),
            ]
        }
    }
}

/// The pieced-block engine (docs/adr/029): a grid of cells, each split by the
/// seams that cross it into convex faces, sorted by centroid so a face's index
/// is its identity in `colors["r,c"]`. Coordinates are quarter-cell units, so a
/// grid-n block spans 0…4n. Mirrors draftGeometry.js and the server's Go copy.
enum DraftGeometry {
    static let maxGrid = 10
    static let seamBudget = 24
    static let bundleSlots = 6
    static let fineAnchorMaxGrid = 5
    private static let eps = 1e-9

    typealias Point = (x: Double, y: Double)
    struct Cell { let r: Int; let c: Int; let faces: [[Point]] }

    static func isLegalAnchor(grid: Int, _ x: Int, _ y: Int) -> Bool {
        let max = 4 * grid
        guard x >= 0, y >= 0, x <= max, y <= max else { return false }
        guard x % 4 == 0 || y % 4 == 0 else { return false }
        if grid > fineAnchorMaxGrid && (x % 2 != 0 || y % 2 != 0) { return false }
        return true
    }

    /// The structural check the backend also runs; never aesthetic.
    static func isValid(_ draft: DraftedBlock) -> Bool {
        guard draft.grid >= 1, draft.grid <= maxGrid else { return false }
        let seams = draft.seams ?? []
        guard seams.count <= seamBudget else { return false }
        for seam in seams {
            guard seam.count == 4, isLegalAnchor(grid: draft.grid, seam[0], seam[1]), isLegalAnchor(grid: draft.grid, seam[2], seam[3]),
                  !(seam[0] == seam[2] && seam[1] == seam[3]) else { return false }
        }
        for (key, slots) in draft.colors ?? [:] {
            let parts = key.split(separator: ",")
            guard parts.count == 2, let r = Int(parts[0]), let c = Int(parts[1]), r >= 0, c >= 0, r < draft.grid, c < draft.grid else { return false }
            guard slots.allSatisfy({ $0 >= 0 && $0 < bundleSlots }) else { return false }
        }
        return true
    }

    static func area(_ poly: [Point]) -> Double {
        var a = 0.0
        for i in poly.indices { let p = poly[i], q = poly[(i + 1) % poly.count]; a += p.x * q.y - q.x * p.y }
        return abs(a) / 2
    }

    static func centroid(_ poly: [Point]) -> Point {
        var a = 0.0, cx = 0.0, cy = 0.0
        for i in poly.indices {
            let p = poly[i], q = poly[(i + 1) % poly.count]
            let cross = p.x * q.y - q.x * p.y
            a += cross; cx += (p.x + q.x) * cross; cy += (p.y + q.y) * cross
        }
        if abs(a) < eps {
            let n = Double(poly.count)
            return (poly.reduce(0) { $0 + $1.x } / n, poly.reduce(0) { $0 + $1.y } / n)
        }
        return (cx / (3 * a), cy / (3 * a))
    }

    /// Liang–Barsky clip of a seam to one cell; nil when it misses, grazes, or
    /// lies along a wall (a wall-collinear seam splits nothing).
    static func clip(_ seam: [Int], xmin: Double, ymin: Double, xmax: Double, ymax: Double) -> (Double, Double, Double, Double)? {
        let x1 = Double(seam[0]), y1 = Double(seam[1]), x2 = Double(seam[2]), y2 = Double(seam[3])
        let dx = x2 - x1, dy = y2 - y1
        var t0 = 0.0, t1 = 1.0
        for (p, q) in [(-dx, x1 - xmin), (dx, xmax - x1), (-dy, y1 - ymin), (dy, ymax - y1)] {
            if abs(p) < eps {
                if q < -eps { return nil }
            } else {
                let t = q / p
                if p < 0 { if t > t1 { return nil }; if t > t0 { t0 = t } }
                else { if t < t0 { return nil }; if t < t1 { t1 = t } }
            }
        }
        if t1 - t0 < eps { return nil }
        let ax = x1 + t0 * dx, ay = y1 + t0 * dy, bx = x1 + t1 * dx, by = y1 + t1 * dy
        if abs(ax - bx) < eps && (abs(ax - xmin) < eps || abs(ax - xmax) < eps) { return nil }
        if abs(ay - by) < eps && (abs(ay - ymin) < eps || abs(ay - ymax) < eps) { return nil }
        return (ax, ay, bx, by)
    }

    /// Split a convex polygon by the line through a–b; one polygon back when
    /// the line misses its interior.
    static func split(_ poly: [Point], _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> [[Point]] {
        let dx = bx - ax, dy = by - ay
        let side: [Int] = poly.map { p in
            let s = dx * (p.y - ay) - dy * (p.x - ax)
            return abs(s) < eps ? 0 : (s > 0 ? 1 : -1)
        }
        guard side.contains(1), side.contains(-1) else { return [poly] }
        var left: [Point] = [], right: [Point] = []
        for i in poly.indices {
            let j = (i + 1) % poly.count
            let p = poly[i], q = poly[j]
            if side[i] >= 0 { left.append(p) }
            if side[i] <= 0 { right.append(p) }
            if side[i] * side[j] < 0 {
                let denom = dx * (q.y - p.y) - dy * (q.x - p.x)
                let t = (dy * (p.x - ax) - dx * (p.y - ay)) / denom
                let cut = (x: p.x + t * (q.x - p.x), y: p.y + t * (q.y - p.y))
                left.append(cut); right.append(cut)
            }
        }
        var out: [[Point]] = []
        if left.count >= 3 && area(left) > eps { out.append(left) }
        if right.count >= 3 && area(right) > eps { out.append(right) }
        return out.isEmpty ? [poly] : out
    }

    /// The pieces of one cell, sorted by centroid (y, then x).
    static func faces(seams: [[Int]], r: Int, c: Int) -> [[Point]] {
        let xmin = Double(4 * c), ymin = Double(4 * r), xmax = xmin + 4, ymax = ymin + 4
        var faces: [[Point]] = [[(xmin, ymin), (xmax, ymin), (xmax, ymax), (xmin, ymax)]]
        for seam in seams where seam.count == 4 {
            guard let (ax, ay, bx, by) = clip(seam, xmin: xmin, ymin: ymin, xmax: xmax, ymax: ymax) else { continue }
            faces = faces.flatMap { split($0, ax, ay, bx, by) }
        }
        return faces.sorted { a, b in
            let ca = centroid(a), cb = centroid(b)
            return abs(ca.y - cb.y) > 1e-6 ? ca.y < cb.y : ca.x < cb.x
        }
    }

    /// Every cell's pieces, row-major.
    static func faces(for draft: DraftedBlock) -> [Cell] {
        let seams = draft.seams ?? []
        var cells: [Cell] = []
        for r in 0..<draft.grid { for c in 0..<draft.grid { cells.append(Cell(r: r, c: c, faces: faces(seams: seams, r: r, c: c))) } }
        return cells
    }
}
