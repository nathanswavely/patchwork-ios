// SPDX-License-Identifier: MPL-2.0
import CoreGraphics

/// The map's two placement passes, kept free of MapKit so they can be tested
/// as arithmetic: which markers collapse into a cluster, and which of the
/// markers left standing get to wear their name. Both are the web's
/// (mapClusters.js, mapLabels.js; docs/adr/078) — screen points in, ids out.
enum MapPlacement {
    /// How close two markers must be before they collapse into one disc.
    /// Sized against the teardrop (26pt wide) plus room to read between them.
    static let clusterRadius: CGFloat = 44

    /// The quilt's own sizing measure, so the heaviest patch anchors its
    /// cluster, sits on top of its neighbours and wins the name.
    static func activity(_ patch: Patch) -> Int {
        (patch.memberCount ?? 0) + (patch.eventCount ?? 0) + (patch.followerCount ?? 0) / 3
    }

    /// One marker's input: an id, its weight, and where it lands on screen.
    struct Point: Equatable {
        let id: String
        let activity: Int
        let at: CGPoint
    }

    /// A group of one is a plain marker; anything larger is a cluster, led
    /// by its heaviest member.
    struct Group: Equatable {
        let lead: String
        let members: [String]
        var isCluster: Bool { members.count > 1 }
        /// Order-free, so a cluster that keeps its members keeps its identity
        /// across passes and its annotation is not torn down and restitched.
        var key: String { isCluster ? "c:" + members.sorted().joined(separator: ",") : lead }
    }

    /// Greedy, seeded by activity: heaviest first, each seed claiming every
    /// unclaimed marker within `radius` of it. Ties fall to the id so two
    /// passes over the same data always agree.
    static func cluster(_ points: [Point], radius: CGFloat = clusterRadius) -> [Group] {
        let ranked = points.sorted { $0.activity != $1.activity ? $0.activity > $1.activity : $0.id < $1.id }
        var claimed = Set<String>()
        var groups: [Group] = []
        for seed in ranked where !claimed.contains(seed.id) {
            claimed.insert(seed.id)
            var members = [seed.id]
            for other in ranked where !claimed.contains(other.id) {
                guard hypot(seed.at.x - other.at.x, seed.at.y - other.at.y) <= radius else { continue }
                claimed.insert(other.id)
                members.append(other.id)
            }
            groups.append(Group(lead: seed.id, members: members))
        }
        return groups
    }

    // MARK: Names

    /// Clear space a newcomer owes every name already placed.
    static let labelGap: CGFloat = 14
    /// What an incumbent owes instead, so the name being read survives its
    /// neighbour drifting a few points closer mid-pinch.
    static let labelKeepGap: CGFloat = 8

    /// The teardrop standing on its point: the tip is the coordinate, the
    /// head above it.
    static let markerSize = CGSize(width: 26, height: 34)
    static let headY: CGFloat = -22
    static let nameGap: CGFloat = 8

    /// The count disc's diameter, which grows with its count.
    static func discSide(_ count: Int) -> CGFloat { count > 20 ? 44 : count > 9 ? 38 : 32 }

    /// Where a name may sit, in the order tried: right of the pin reads
    /// best, but a name on the left, above or below is worth more than none.
    enum Slot: CaseIterable, Equatable {
        case right, left, above, below

        /// The name's frame relative to the marker's tip.
        func frame(_ size: CGSize) -> CGRect {
            let side = MapPlacement.markerSize.width / 2 + MapPlacement.nameGap
            switch self {
            case .right: return CGRect(x: side, y: MapPlacement.headY - size.height / 2, width: size.width, height: size.height)
            case .left: return CGRect(x: -side - size.width, y: MapPlacement.headY - size.height / 2, width: size.width, height: size.height)
            case .above: return CGRect(x: -size.width / 2, y: -MapPlacement.markerSize.height - MapPlacement.nameGap - size.height, width: size.width, height: size.height)
            case .below: return CGRect(x: -size.width / 2, y: MapPlacement.nameGap, width: size.width, height: size.height)
            }
        }
    }

    /// Decide the named set. `groups` arrive heaviest first, as `cluster`
    /// returns them; clusters are never candidates, having as many names as
    /// members. Every marker and disc is an obstacle before any name is
    /// placed: a name over a pin hides the very thing it describes.
    /// `point` is a marker's tip, or a cluster's centre (its members' mean).
    /// `incumbents` buys the smaller gap and nothing else.
    static func names(for groups: [Group], at point: (Group) -> CGPoint, size: (String) -> CGSize,
                      incumbents: Set<String>, visible: CGRect) -> [String: Slot] {
        var obstacles: [CGRect] = []
        for group in groups {
            let p = point(group)
            if group.isCluster {
                let r = discSide(group.members.count) / 2
                obstacles.append(CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            } else {
                obstacles.append(CGRect(x: p.x - markerSize.width / 2, y: p.y - markerSize.height,
                                        width: markerSize.width, height: markerSize.height))
            }
        }
        var placed: [CGRect] = []
        var chosen: [String: Slot] = [:]
        for group in groups where !group.isCluster {
            let p = point(group)
            let gap = incumbents.contains(group.lead) ? labelKeepGap : labelGap
            for slot in Slot.allCases {
                let box = slot.frame(size(group.lead)).offsetBy(dx: p.x, dy: p.y)
                guard visible.contains(box) else { continue }
                if obstacles.contains(where: { box.insetBy(dx: -2, dy: -2).intersects($0) }) { continue }
                if placed.contains(where: { box.insetBy(dx: -gap, dy: -gap).intersects($0) }) { continue }
                placed.append(box)
                chosen[group.lead] = slot
                break
            }
        }
        return chosen
    }

    /// Where a name goes when it is asked for (a tapped marker) rather than
    /// won: the first slot on screen, collisions notwithstanding.
    static func revealed(at p: CGPoint, size: CGSize, visible: CGRect) -> Slot {
        Slot.allCases.first { visible.contains($0.frame(size).offsetBy(dx: p.x, dy: p.y)) } ?? .right
    }
}
