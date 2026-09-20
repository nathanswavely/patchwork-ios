// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import Patchwork

final class QuiltLayoutTests: XCTestCase {
    struct Scenario: Decodable {
        let patches: [Patch]
        let affinity: [Affinity]
        let sizes: [String: Int]
        let expected: [Expected]
        struct Expected: Decodable { let id: String; let x: Int; let y: Int; let size: Int }
    }
    func testLayoutMatchesWebBehaviorFixtures() throws {
        let url = Bundle(for: Self.self).url(forResource: "layout-fixtures", withExtension: "json")!
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let cases = try decoder.decode([Scenario].self, from: Data(contentsOf: url))
        for (index, scenario) in cases.enumerated() {
            let result = QuiltLayout.pack(scenario.patches, affinity: scenario.affinity, sizes: scenario.sizes)
            let real = result.filter { tile in scenario.patches.contains { $0.id == tile.id } }
            XCTAssertEqual(real, scenario.expected.map { QuiltLayout.Tile(id: $0.id, x: $0.x, y: $0.y, size: $0.size) }, "Scenario \(index)")
            var occupied = Set<QuiltLayout.Cell>()
            for tile in result {
                for y in tile.y..<(tile.y + tile.size) { for x in tile.x..<(tile.x + tile.size) {
                    XCTAssertTrue(occupied.insert(.init(x: x, y: y)).inserted, "Overlapping tiles")
                } }
            }
        }
    }
    @MainActor func testCanvasReleasesAfterLeavingAQuilt() throws {
        let patch = try JSONDecoder().decode(Patch.self, from: Data(#"{"id":"1","name":"A patch","slug":"a-patch"}"#.utf8))
        weak var released: CanvasScrollView?
        autoreleasepool {
            let view = CanvasScrollView(frame: .zero)
            released = view
            view.update(tiles: [.init(id: "1", x: 0, y: 0, size: 2)], patches: [patch], tagMotifs: [:], colorMode: .standard, select: { _ in })
        }
        XCTAssertNil(released)
    }
    func testFiltersMatchNameOrDescriptionAndAnySelectedTag() throws {
        let patch = try JSONDecoder().decode(Patch.self, from: Data(#"{"id":"1","name":"Café","slug":"cafe","description":"Neighborhood music","tags":["coffee"]}"#.utf8))
        XCTAssertTrue(QuiltLayout.matches(patch, query: "CAFE", tags: []))
        XCTAssertTrue(QuiltLayout.matches(patch, query: "music", tags: ["coffee", "art"]))
        XCTAssertFalse(QuiltLayout.matches(patch, query: "coffee", tags: []))
        XCTAssertFalse(QuiltLayout.matches(patch, query: "cafe", tags: ["art"]))
    }
}
