// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

final class ContractTests: XCTestCase {
    func testQuiltAddressesRequireHTTPSAndAnOrigin() throws {
        XCTAssertEqual(try QuiltAddress.parse(" Community.Example.org/ ").absoluteString, "https://community.example.org")
        for value in ["", "http://example.org", "https://user:secret@example.org", "https://example.org/patches/a", "https://example.org?token=secret", "https://example.org#x", "file:///tmp/a"] {
            XCTAssertThrowsError(try QuiltAddress.parse(value), value)
        }
    }
    func testBothTimestampFormatsDecode() {
        XCTAssertNotNil(PatchworkEvent.parseDate("2026-09-19T19:30:00Z"))
        XCTAssertNotNil(PatchworkEvent.parseDate("2026-09-19T19:30:00.123Z"))
        XCTAssertNil(PatchworkEvent.parseDate("not a date"))
    }
    func testNullableEmptyCollectionsDecode() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let tree = try decoder.decode(TreeResponse.self, from: Data(#"{"tree":{"children":null}}"#.utf8))
        XCTAssertNil(tree.tree.children)
        let page = try decoder.decode(EventPage.self, from: Data(#"{"items":null,"next_cursor":"next"}"#.utf8))
        XCTAssertNil(page.items)
        XCTAssertEqual(page.nextCursor, "next")
    }
    func testPatchDetailUsesNodeEnvelope() throws {
        let response = try JSONDecoder().decode(PatchResponse.self, from: Data(#"{"node":{"id":"patch","name":"Our patch","slug":"our-patch","address":"12 Example Street"},"is_unclaimed":true}"#.utf8))
        XCTAssertEqual(response.node.address, "12 Example Street")
        XCTAssertEqual(response.node.slug, "our-patch")
    }
    func testPublicContractAndOptionalFields() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let event = try decoder.decode(PatchworkEvent.self, from: Data(#"{"id":"event","title":"Gathering","starts_at":"2026-09-19T19:30:00Z","timezone":"America/New_York","node_name":"Our patch","event_url":"https://example.org/event"}"#.utf8))
        XCTAssertEqual(event.nodeName, "Our patch")
        XCTAssertEqual(event.eventUrl, "https://example.org/event")
        XCTAssertNotNil(event.date)
    }
    @MainActor func testNoQuiltIsSelectedOnLaunch() {
        XCTAssertNil(QuiltStore().selected)
    }
}
