// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Integer geometry for the public quilt. Presentation and gestures live separately.
enum QuiltLayout {
    struct Cell: Hashable { let x: Int; let y: Int }
    struct Tile: Equatable {
        let id: String
        let x: Int
        let y: Int
        let size: Int
    }
    static func matches(_ patch: Patch, query: String, tags: Set<String>) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return (tags.isEmpty || !(tags.intersection(patch.tags ?? [])).isEmpty)
            && (text.isEmpty || patch.name.range(of: text, options: options) != nil
                || (patch.description ?? "").range(of: text, options: options) != nil)
    }
    static func pack(_ patches: [Patch], affinity: [Affinity], sizes: [String: Int] = [:]) -> [Tile] {
        guard !patches.isEmpty else { return [] }
        let activity = patches.map { ($0.memberCount ?? 0) + ($0.eventCount ?? 0) + ($0.followerCount ?? 0) / 3 }
        let ranked = activity.sorted(by: >)
        var ideal = activity.map { value -> Int in
            let rank = ranked.firstIndex(of: value)!
            let earned = value >= 24 ? 4 : value >= 10 ? 3 : value >= 3 ? 2 : 1
            let cap = rank < max(1, Int(ceil(Double(patches.count) * 0.04))) ? 4
                : rank < max(1, Int(ceil(Double(patches.count) * 0.12))) ? 3
                : rank < Int(ceil(Double(patches.count) * 0.4)) ? 2 : 1
            return min(earned, cap)
        }
        if ideal.allSatisfy({ $0 == 1 }) { ideal = ideal.map { _ in 2 } }
        for i in patches.indices { ideal[i] = sizes[patches[i].id] ?? ideal[i] }
        var queue = patches.indices.sorted { ideal[$0] == ideal[$1] ? $0 < $1 : ideal[$0] > ideal[$1] }
        var weights: [String: [String: Double]] = [:]
        for edge in affinity {
            weights[edge.source, default: [:]][edge.target] = edge.strength
            weights[edge.target, default: [:]][edge.source] = edge.strength
        }
        var occupied = Set<Cell>()
        var frontier: [Cell] = []
        var tiles: [Tile] = []
        var fillers = 0
        func place(_ tile: Tile) {
            tiles.append(tile)
            for y in tile.y..<(tile.y + tile.size) { for x in tile.x..<(tile.x + tile.size) { occupied.insert(Cell(x: x, y: y)) } }
            frontier.removeAll { occupied.contains($0) }
            for y in (tile.y - 1)...(tile.y + tile.size) {
                for x in (tile.x - 1)...(tile.x + tile.size) {
                    let c = Cell(x: x, y: y)
                    let edge = (x >= tile.x && x < tile.x + tile.size) || (y >= tile.y && y < tile.y + tile.size)
                    if edge && !occupied.contains(c) && !frontier.contains(c) { frontier.append(c) }
                }
            }
        }
        let first = queue.removeFirst()
        place(Tile(id: patches[first].id, x: 0, y: 0, size: ideal[first]))
        while !queue.isEmpty {
            let connection = queue.map { i in tiles.reduce(0.0) { $0 + (weights[patches[i].id]?[$1.id] ?? 0) } }
            let next = connection.firstIndex(of: connection.max()!)!
            let i = queue.remove(at: next)
            let id = patches[i].id
            let related = tiles.filter { (weights[id]?[$0.id] ?? 0) > 0 }
            let anchors = related.isEmpty ? tiles : related
            var total = 0.0, tx = 0.0, ty = 0.0
            for tile in anchors {
                let weight = related.isEmpty ? 1 : weights[id]![tile.id]!
                total += weight
                tx += (Double(tile.x) + Double(tile.size) / 2) * weight
                ty += (Double(tile.y) + Double(tile.size) / 2) * weight
            }
            tx /= total; ty /= total
            let ordered = frontier.enumerated().sorted {
                let a = hypot(Double($0.element.x) - tx, Double($0.element.y) - ty)
                let b = hypot(Double($1.element.x) - tx, Double($1.element.y) - ty)
                return a == b ? $0.offset < $1.offset : a < b
            }.map(\.element)
            var chosen: Tile?
            let candidates = [ideal[i]] + (ideal[i] > 1 ? [ideal[i] - 1] : []) + (ideal[i] < 4 ? [ideal[i] + 1] : [])
            for side in candidates {
                for cell in ordered {
                    var score = -1.0
                    for dy in 0..<side { for dx in 0..<side {
                        let x = cell.x - dx, y = cell.y - dy
                        var clear = true
                        for row in y..<(y + side) { for col in x..<(x + side) { if occupied.contains(Cell(x: col, y: row)) { clear = false } } }
                        if !clear { continue }
                        var touching = 0
                        for offset in 0..<side {
                            for c in [Cell(x: x + offset, y: y - 1), Cell(x: x + offset, y: y + side), Cell(x: x - 1, y: y + offset), Cell(x: x + side, y: y + offset)] {
                                if occupied.contains(c) { touching += 1 }
                            }
                        }
                        if touching == 0 { continue }
                        let value = Double(touching * 10) - hypot(Double(x) + Double(side) / 2 - tx, Double(y) + Double(side) / 2 - ty)
                        if value > score { score = value; chosen = Tile(id: id, x: x, y: y, size: side) }
                    } }
                    if chosen != nil { break }
                }
                if chosen != nil { break }
            }
            if let chosen { place(chosen) }
            else if let cell = ordered.first {
                // A neutral cell bridges a gap when no earned square can attach.
                if fillers < patches.count * 2 {
                    place(Tile(id: "filler-\(tiles.count)", x: cell.x, y: cell.y, size: 1))
                    fillers += 1
                    queue.insert(i, at: 0)
                } else { place(Tile(id: id, x: cell.x, y: cell.y, size: 1)) }
            }
        }
        return tiles
    }
}
