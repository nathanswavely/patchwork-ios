// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// What a launch keeps of a quilt: kept per quilt, read back as written,
/// drawn by the next session before it asks, and gone with the quilt.
@MainActor final class QuiltKeepTests: XCTestCase {
    private let quilt = Quilt(url: URL(string: "https://keep-test.example.org:8443")!, name: "Keep test")
    private let other = Quilt(url: URL(string: "https://other-keep-test.example.org")!, name: "Other")
    override func tearDown() { QuiltKeep.forget(quilt); QuiltKeep.forget(other) }

    func testKeptPerQuiltAndForgottenWithIt() {
        QuiltKeep.write(Data("a".utf8), as: .instance, of: quilt)
        QuiltKeep.write(Data("b".utf8), as: .instance, of: other)
        XCTAssertEqual(QuiltKeep.read(.instance, of: quilt), Data("a".utf8))
        XCTAssertEqual(QuiltKeep.read(.instance, of: other), Data("b".utf8))
        XCTAssertNil(QuiltKeep.read(.tree, of: quilt))
        XCTAssertTrue(QuiltKeep.folder(quilt).lastPathComponent.hasSuffix("_8443"), "a port is part of the address")
        QuiltKeep.forget(quilt)
        XCTAssertNil(QuiltKeep.read(.instance, of: quilt))
        XCTAssertNotNil(QuiltKeep.read(.instance, of: other))
    }

    func testANewSessionDrawsTheKeptTreeBeforeAsking() {
        let tree = #"{"tree":{"children":[{"id":"p1","name":"Common Thread","slug":"common-thread"}]},"affinity":[]}"#
        QuiltKeep.write(Data(tree.utf8), as: .tree, of: quilt)
        let session = QuiltSession(quilt: quilt)
        XCTAssertFalse(session.loading, "no spinner over a kept quilt")
        XCTAssertEqual(session.patches.map(\.id), ["p1"])
        XCTAssertEqual(session.tiles.count, 1)
    }
}
