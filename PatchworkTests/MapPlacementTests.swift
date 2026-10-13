// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import Patchwork

final class MapPlacementTests: XCTestCase {
    private func point(_ id: String, _ activity: Int, _ x: CGFloat, _ y: CGFloat) -> MapPlacement.Point {
        MapPlacement.Point(id: id, activity: activity, at: CGPoint(x: x, y: y))
    }

    func testHeaviestPatchAnchorsItsCluster() {
        let groups = MapPlacement.cluster([point("a", 1, 100, 100), point("b", 9, 120, 100), point("c", 3, 300, 300)])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].lead, "b")
        XCTAssertEqual(groups[0].members, ["b", "a"])
        XCTAssertFalse(groups[1].isCluster)
    }

    func testClusterKeyIgnoresMemberOrder() {
        XCTAssertEqual(MapPlacement.Group(lead: "b", members: ["b", "a"]).key,
                       MapPlacement.Group(lead: "a", members: ["a", "b"]).key)
    }

    func testMarkersFurtherApartThanTheRadiusStayApart() {
        let groups = MapPlacement.cluster([point("a", 1, 0, 0), point("b", 1, MapPlacement.clusterRadius + 1, 0)])
        XCTAssertEqual(groups.count, 2)
    }

    private let visible = CGRect(x: 0, y: 0, width: 400, height: 800)
    private let label = CGSize(width: 80, height: 15)

    private func names(_ points: [MapPlacement.Point], incumbents: Set<String> = []) -> [String: MapPlacement.Slot] {
        let at = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0.at) })
        let groups = MapPlacement.cluster(points)
        return MapPlacement.names(for: groups, at: { at[$0.lead]! }, size: { _ in self.label },
                                  incumbents: incumbents, visible: visible)
    }

    func testALoneMarkerIsNamedOnTheRight() {
        XCTAssertEqual(names([point("a", 1, 100, 100)]), ["a": .right])
    }

    func testANameAtTheRightEdgeMovesLeft() {
        XCTAssertEqual(names([point("a", 1, 380, 100)]), ["a": .left])
    }

    func testANameNeverCoversAnotherMarker() {
        // b's pin stands where a's right-hand name would go; a takes the left.
        let slots = names([point("a", 9, 200, 100), point("b", 1, 260, 100)])
        XCTAssertEqual(slots["a"], .left)
    }

    func testClustersCarryNoName() {
        XCTAssertTrue(names([point("a", 1, 100, 100), point("b", 1, 110, 100)]).isEmpty)
    }

    func testAnIncumbentIsForgivenACloserNeighbour() {
        // b's right-hand name would sit 10pt under a's: too close for a
        // newcomer (14), close enough for a name already standing (8).
        let points = [point("a", 9, 100, 100), point("b", 1, 150, 125)]
        XCTAssertEqual(names(points)["b"], .below)
        XCTAssertEqual(names(points, incumbents: ["a", "b"])["b"], .right)
    }

    func testRevealedNameStaysOnScreen() {
        XCTAssertEqual(MapPlacement.revealed(at: CGPoint(x: 390, y: 100), size: label, visible: visible), .left)
    }
}
