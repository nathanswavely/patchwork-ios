// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import Patchwork

/// The registries and the hash must agree with the web's quiltTheme.js,
/// quiltBlocks.js and draftGeometry.js, or a patch wears a different tile in
/// the app than on the site. Expected values were computed by running the web
/// modules under node against the same inputs.
final class QuiltAppearanceTests: XCTestCase {
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()
    private func patch(_ json: String) throws -> Patch { try decoder.decode(Patch.self, from: Data(json.utf8)) }

    func testHashMatchesTheWeb() {
        XCTAssertEqual(QuiltTheme.hash("demo-patch"), 1770388446)
        XCTAssertEqual(QuiltTheme.hash("demo-patch-2"), 536248835)
        XCTAssertEqual(QuiltTheme.hash("extra-0"), -1305291341)
        XCTAssertEqual(QuiltTheme.hash("Ünïcode—patch"), 1088175294)
        XCTAssertEqual(QuiltTheme.palettes.count, 26)
        XCTAssertEqual(QuiltTheme.index("demo-patch", count: 26), 8)
        XCTAssertEqual(QuiltTheme.index("extra-0", count: 26), 3)
        XCTAssertEqual(QuiltTheme.index("extra-9", count: 26), 20)
        XCTAssertEqual(QuiltTheme.index("019f9967-1edd-78ed-894d-29cc6494fb7b", count: 26), 1)
        XCTAssertEqual(QuiltBlocks.index(id: "demo-patch", appearance: nil), 6)
        XCTAssertEqual(QuiltBlocks.rotation(id: "demo-patch", appearance: nil), 180)
        XCTAssertEqual(QuiltBlocks.index(id: "demo-patch-2", appearance: nil), 11)
        XCTAssertEqual(QuiltBlocks.rotation(id: "demo-patch-2", appearance: nil), 270)
        XCTAssertEqual(QuiltBlocks.index(id: "extra-9", appearance: nil), 8)
        XCTAssertEqual(QuiltBlocks.rotation(id: "extra-9", appearance: nil), 0)
    }

    func testPaletteRegistryOrderAndCutKeys() {
        let expected = ["adolescents", "pinkRazors", "greatestSongs", "allroysRevenge", "anthem", "allTheShoes", "bottlesToTheGround", "liberalAnimation",
                        "punchButterscotch", "brickChambray", "rustSeafoam", "amberInkBlue", "mustardPetrol", "goldenrodMerlot", "mossMuslinPink",
                        "fernPeach", "bottleGreenLemon", "seafoamMulberry", "spruceCoral", "petrolButterscotch", "workwearSafetyOrange", "skyBrick",
                        "inkBlueCamel", "violetHiVis", "lilacSpruce", "mulberryPistachio"]
        XCTAssertEqual(QuiltTheme.palettes.map(\.key), expected)
        let cut = QuiltTheme.byKey["inkBlueCamel"]
        XCTAssertEqual(cut?.primary, "#3A4E8A")
        XCTAssertEqual(cut?.secondary, "#D9A066")
        XCTAssertEqual(cut?.bg, "#C9C2B2")
        XCTAssertEqual(cut?.name, "Ink Blue")
        XCTAssertEqual(QuiltTheme.wall.count, 56)
    }

    func testPaletteResolutionOrder() {
        XCTAssertEqual(QuiltTheme.palette(id: "demo-patch", appearance: Appearance(palette: "allroysRevenge")).key, "allroysRevenge")
        XCTAssertEqual(QuiltTheme.palette(id: "demo-patch", appearance: Appearance(palette: "nope")).key, "punchButterscotch", "an unknown key falls back to the hash")
        XCTAssertEqual(QuiltTheme.palette(id: "demo-patch", appearance: nil).key, "punchButterscotch")
        let bundled = QuiltTheme.palette(id: "demo-patch", appearance: Appearance(palette: "anthem", bundle: ["#0A0A0A", "#F2EEE4", "#261922"]))
        XCTAssertNil(bundled.key)
        XCTAssertEqual(bundled.primary, "#0A0A0A")
        XCTAssertEqual(bundled.slots, ["#0A0A0A", "#F2EEE4", "#261922"])
        let short = QuiltTheme.palette(id: "x", appearance: Appearance(bundle: ["nope", "#123456"]))
        XCTAssertEqual(short.primary, "#123456")
        XCTAssertEqual(short.secondary, "#123456")
        XCTAssertEqual(short.bg, "#081727", "a one-fabric bundle grounds on its own fabric, darkened")
        XCTAssertEqual(short.slots.count, 1)
        XCTAssertEqual(QuiltTheme.ghost(0).key, "allroysRevenge")
    }

    func testTextOnColor() {
        XCTAssertEqual(QuiltTheme.textOnColor("#FCFD1B"), UIColor(hex: "#151820"))
        XCTAssertEqual(QuiltTheme.textOnColor("#0a0a0a"), .white)
        XCTAssertEqual(QuiltTheme.textOnColor("bad"), .white)
    }

    func testAppearanceDecodesCuratedDraftedAndUnknownBlocks() throws {
        let curated = try patch(#"{"id":"a","name":"A","slug":"a","appearance":{"palette":"anthem","block":"bearsPaw","rotation":90,"icon":"guitar"}}"#)
        XCTAssertEqual(curated.appearance?.block, .curated("bearsPaw"))
        XCTAssertEqual(curated.appearance?.rotation, 90)
        XCTAssertEqual(curated.appearance?.icon, "guitar")
        let drafted = try patch(##"{"id":"b","name":"B","slug":"b","appearance":{"block":{"grid":3,"colors":{"0,1":[1]}},"bundle":["#2E7D5B","#204B4B"]}}"##)
        guard case let .drafted(draft)? = drafted.appearance?.block else { return XCTFail("expected a drafted block") }
        XCTAssertEqual(draft.grid, 3)
        XCTAssertEqual(draft.colors?["0,1"], [1])
        XCTAssertEqual(drafted.appearance?.bundle?.count, 2)
        let odd = try patch(#"{"id":"c","name":"C","slug":"c","appearance":{"block":7,"palette":"anthem"}}"#)
        XCTAssertNil(odd.appearance?.block, "an unrecognised block shape degrades rather than failing the patch")
        XCTAssertEqual(odd.appearance?.palette, "anthem")
        XCTAssertNil(try patch(#"{"id":"d","name":"D","slug":"d"}"#).appearance)
    }

    func testDraftedFacesMatchTheWeb() throws {
        let allfornauts = try decoder.decode(DraftedBlock.self, from: Data(#"{"grid": 5, "seams": [[0, 10, 8, 10], [2, 12, 2, 4], [0, 6, 12, 6], [10, 8, 10, 0], [6, 0, 6, 12], [4, 2, 12, 2]], "colors": {"0,1": [1, 0, 0, 1]}}"#.utf8))
        XCTAssertTrue(DraftGeometry.isValid(allfornauts))
        let cells = DraftGeometry.faces(for: allfornauts)
        XCTAssertEqual(cells.map(\.faces.count), [1, 4, 4, 1, 1, 4, 4, 4, 1, 1, 4, 4, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
        let sample = cells.first { $0.r == 0 && $0.c == 1 }!
        let expected: [[[Double]]] = [[[4, 0], [6, 0], [6, 2], [4, 2]], [[6, 0], [8, 0], [8, 2], [6, 2]], [[6, 2], [6, 4], [4, 4], [4, 2]], [[8, 2], [8, 4], [6, 4], [6, 2]]]
        XCTAssertEqual(sample.faces.map { $0.map { [$0.x, $0.y] } }, expected)

        let torn = try decoder.decode(DraftedBlock.self, from: Data(#"{"grid":5,"seams":[[0,0,20,20],[0,20,20,0],[10,0,10,20],[0,10,20,10]],"colors":{}}"#.utf8))
        let first = DraftGeometry.faces(for: torn).first!.faces
        XCTAssertEqual(first.map { $0.map { [$0.x, $0.y] } }, [[[0, 0], [4, 0], [4, 4]], [[0, 0], [4, 4], [0, 4]]])

        let plain = DraftedBlock(grid: 3)
        XCTAssertEqual(DraftGeometry.faces(for: plain).reduce(0) { $0 + $1.faces.count }, 9)
        let cuts = QuiltBlocks.draftCuts(DraftedBlock(grid: 3, colors: ["0,1": [1], "0,2": [2], "1,0": [1], "1,2": [1], "2,0": [2], "2,1": [1]]),
                                         palette: QuiltTheme.palette(id: "x", appearance: Appearance(bundle: ["#2E7D5B", "#204B4B", "#D9D6AF", "#D89E13"])))
        XCTAssertEqual(cuts.count, 10, "the ground plus nine cells")
        XCTAssertEqual(cuts.first?.hex, "#D9D6AF")
        XCTAssertEqual(cuts[2].hex, "#204B4B", "cell (0,1) is cut from slot one")
        XCTAssertEqual(cuts[1].hex, "#2E7D5B", "an uncoloured cell takes slot zero")
    }

    func testDraftValidationMirrorsTheBackend() {
        XCTAssertFalse(DraftGeometry.isValid(DraftedBlock(grid: 0)))
        XCTAssertFalse(DraftGeometry.isValid(DraftedBlock(grid: 11)))
        XCTAssertFalse(DraftGeometry.isValid(DraftedBlock(grid: 2, seams: [[1, 1, 4, 4]])), "an anchor must sit on a cell wall")
        XCTAssertFalse(DraftGeometry.isValid(DraftedBlock(grid: 6, seams: [[0, 1, 24, 1]])), "above 5x5 only midpoints survive")
        XCTAssertTrue(DraftGeometry.isValid(DraftedBlock(grid: 6, seams: [[0, 2, 24, 2]])))
        XCTAssertFalse(DraftGeometry.isValid(DraftedBlock(grid: 2, seams: Array(repeating: [0, 0, 8, 8], count: 25))))
        XCTAssertFalse(DraftGeometry.isValid(DraftedBlock(grid: 2, colors: ["2,0": [0]])))
        XCTAssertFalse(DraftGeometry.isValid(DraftedBlock(grid: 2, colors: ["0,0": [6]])))
        let unknown = QuiltBlocks.cuts(id: "demo-patch", appearance: Appearance(block: .drafted(DraftedBlock(grid: 0))), palette: QuiltTheme.palette(id: "demo-patch", appearance: nil))
        XCTAssertEqual(unknown.count, QuiltBlocks.curated(6).count, "an invalid draft renders the hash-assigned curated block")
    }

    func testCuratedBlocksAreTranscribedWhole() {
        let pieceCounts = [8, 10, 8, 5, 4, 9, 3, 10, 5, 4, 14, 5]
        for (index, expected) in pieceCounts.enumerated() {
            let pieces = QuiltBlocks.curated(index)
            XCTAssertEqual(pieces.count, expected, QuiltBlocks.keys[index])
            for piece in pieces {
                XCTAssertGreaterThanOrEqual(piece.points.count, 3)
                for point in piece.points {
                    XCTAssert((0...1).contains(point.x) && (0...1).contains(point.y), "\(QuiltBlocks.keys[index]) leaves the square")
                }
            }
        }
        XCTAssertEqual(QuiltBlocks.index(id: "demo-patch", appearance: Appearance(block: .curated("logCabin"))), 9)
        XCTAssertEqual(QuiltBlocks.index(id: "demo-patch", appearance: Appearance(block: .curated("nope"))), 6)
        XCTAssertEqual(QuiltBlocks.rotation(id: "demo-patch", appearance: Appearance(rotation: 45)), 180, "a rotation off the four is ignored")
    }

    func testMotifResolution() throws {
        let motifs = ["band": "guitar", "punk": "skull", "odd": "notAMotif"]
        XCTAssertEqual(Motifs.key(for: try patch(#"{"id":"a","name":"A","slug":"a","tags":["band"],"appearance":{"icon":"camera"}}"#), tagMotifs: motifs), "camera")
        XCTAssertEqual(Motifs.key(for: try patch(#"{"id":"a","name":"A","slug":"a","tags":["band"],"appearance":{"icon":"custom"}}"#), tagMotifs: motifs), "guitar", "an unknown chosen motif falls through to the tags")
        XCTAssertEqual(Motifs.key(for: try patch(#"{"id":"a","name":"A","slug":"a","tags":["odd","punk","band"]}"#), tagMotifs: motifs), "skull", "the first motif-bearing tag in stored order wins")
        XCTAssertEqual(Motifs.key(for: try patch(#"{"id":"a","name":"A","slug":"a","tags":["brewery"]}"#), tagMotifs: motifs), "quilt")
        for key in Motifs.keys { XCTAssertNotNil(Motifs.image(key), "missing glyph for \(key)") }
        XCTAssertNotNil(Motifs.unclaimed)
    }

    func testBadgesDiscloseBySizeAndHoldWithHysteresis() {
        let type = QuiltBadges.Typeface(size: 12)
        let flat: (String) -> [QuiltBadges.Shape] = { _ in [QuiltBadges.Shape(textWidth: 60, lines: 1)] }
        let big = QuiltBadges.Candidate(id: "big", name: "Big", rect: CGRect(x: 50, y: 50, width: 100, height: 100))
        let small = QuiltBadges.Candidate(id: "small", name: "Small", rect: CGRect(x: 300, y: 50, width: 50, height: 50))
        let viewport = CGSize(width: 800, height: 600)
        var plan = QuiltBadges.plan([big, small], held: [], viewport: viewport, type: type, shapes: flat)
        XCTAssertEqual(plan.map(\.id), ["big"], "a tile earns a badge at 52pt on screen")
        plan = QuiltBadges.plan([big, small], held: ["small"], viewport: viewport, type: type, shapes: flat)
        XCTAssertEqual(plan.map(\.id), ["small", "big"], "an incumbent holds down to 44pt and is placed first")
        XCTAssertEqual(plan[1].rect, CGRect(x: 100 - 36, y: 100 - 11, width: 72, height: 22))
        let offscreen = QuiltBadges.Candidate(id: "off", name: "Off", rect: CGRect(x: -400, y: 50, width: 100, height: 100))
        XCTAssertTrue(QuiltBadges.plan([offscreen], held: [], viewport: viewport, type: type, shapes: flat).isEmpty)
    }

    func testBadgesStackBeforeTheyGiveUp() {
        let type = QuiltBadges.Typeface(size: 12)
        let left = QuiltBadges.Candidate(id: "l", name: "Left", rect: CGRect(x: 50, y: 50, width: 100, height: 100))
        let right = QuiltBadges.Candidate(id: "r", name: "Right", rect: CGRect(x: 150, y: 50, width: 100, height: 100))
        let viewport = CGSize(width: 800, height: 600)
        let flat: (String) -> [QuiltBadges.Shape] = { _ in [QuiltBadges.Shape(textWidth: 60, lines: 1)] }
        XCTAssertEqual(QuiltBadges.plan([left, right], held: [], viewport: viewport, type: type, shapes: flat).map(\.id), ["l"],
                       "two pills 100pt apart cannot both clear a 32pt gap")
        let stacking: (String) -> [QuiltBadges.Shape] = { _ in [QuiltBadges.Shape(textWidth: 60, lines: 1), QuiltBadges.Shape(textWidth: 20, lines: 2)] }
        let plan = QuiltBadges.plan([left, right], held: [], viewport: viewport, type: type, shapes: stacking)
        XCTAssertEqual(plan.map(\.id), ["l", "r"])
        XCTAssertEqual(plan[0].shape.lines, 1, "the first badge wears the flat pill")
        XCTAssertEqual(plan[1].shape.lines, 2, "the second stacks to clear its neighbour")
        let held = QuiltBadges.plan([left, right], held: ["r"], viewport: viewport, type: type, shapes: flat)
        XCTAssertEqual(held.map(\.id), ["r"], "an incumbent keeps its spot against a rival of equal size")
    }

    func testMeasurerOffersNarrowerShapesOnly() {
        let measurer = QuiltBadges.Measurer(type: QuiltBadges.Typeface(size: 12))
        let shapes = measurer.shapes("Long's Park Amphitheater Foundation")
        XCTAssertFalse(shapes.isEmpty)
        XCTAssertTrue(shapes.allSatisfy { $0.lines <= QuiltBadges.maxLines && $0.textWidth <= measurer.type.textMax })
        XCTAssertEqual(shapes.map(\.textWidth), shapes.map(\.textWidth).sorted(by: >), "each deeper shape is narrower than the last")
        let unbroken = measurer.shapes("Supercalifragilisticexpialidocious")
        XCTAssertEqual(unbroken.count, 1)
        XCTAssertEqual(unbroken[0].textWidth, measurer.type.textMax)
        XCTAssertGreaterThanOrEqual(unbroken[0].lines, 2)
        XCTAssertEqual(measurer.shapes("Zine").count, 1)
    }

    func testSeamsAreStrokedOnceAndTheEdgeWearsTheBinding() {
        let tiles = [QuiltLayout.Tile(id: "a", x: 0, y: 0, size: 1), QuiltLayout.Tile(id: "b", x: 1, y: 0, size: 1)]
        let paths = CanvasScrollView.seamPaths(tiles, minX: 0, minY: 0, unit: 10, pad: 0)
        func segments(_ path: CGPath) -> Int {
            var moves = 0
            path.applyWithBlock { if $0.pointee.type == .moveToPoint { moves += 1 } }
            return moves
        }
        XCTAssertEqual(segments(paths.interior), 7, "the shared seam is one segment, not two")
        XCTAssertEqual(segments(paths.outer), 6, "the binding runs along the six outer segments")
    }
}
