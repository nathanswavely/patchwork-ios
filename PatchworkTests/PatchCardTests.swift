// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import Patchwork

/// What a patch card says, and in what order the cards come — the two things
/// this app now states in the web's own words rather than its own.
final class PatchCardTests: XCTestCase {
    private func patch(_ json: String) throws -> Patch {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Patch.self, from: Data(json.utf8))
    }

    // MARK: - Counts

    func testAClaimedPatchCountsItsMembersAndItsEvents() throws {
        let many = try patch(#"{"id":"1","name":"A","slug":"a","member_count":12,"event_count":3}"#)
        XCTAssertEqual(many.cardCountsLabel, "12 Members · 3 Events")
    }

    func testTheSingularIsSingularOnBothSidesOfTheDot() throws {
        let one = try patch(#"{"id":"1","name":"A","slug":"a","member_count":1,"event_count":1}"#)
        XCTAssertEqual(one.cardCountsLabel, "1 Member · 1 Event")
    }

    func testAListingNobodyRunsCountsWhoFollowsIt() throws {
        let unclaimed = try patch(#"{"id":"1","name":"A","slug":"a","is_unclaimed":true,"follower_count":4,"member_count":9,"event_count":2}"#)
        XCTAssertEqual(unclaimed.cardCountsLabel, "4 Following · 2 Events",
                       "An unclaimed patch has no members to count, even when the payload carries a number")
        let byStatus = try patch(#"{"id":"1","name":"A","slug":"a","status":"unclaimed","follower_count":1,"event_count":0}"#)
        XCTAssertEqual(byStatus.cardCountsLabel, "1 Following · 0 Events")
    }

    func testAMissingCountIsZeroRatherThanAbsent() throws {
        let bare = try patch(#"{"id":"1","name":"A","slug":"a"}"#)
        XCTAssertEqual(bare.cardCountsLabel, "0 Members · 0 Events")
    }

    /// The card's event figure is every active event the patch owns; the
    /// head's is the upcoming one. Conflating them is the bug this asserts
    /// against: a card that says "0 Events" for a patch with a past calendar
    /// would be answering the head's question with the card's words.
    func testTheCardCountsAllEventsAndTheHeadCountsUpcomingOnes() throws {
        let both = try patch(#"{"id":"1","name":"A","slug":"a","member_count":2,"event_count":7,"upcoming_event_count":1}"#)
        XCTAssertEqual(both.cardCountsLabel, "2 Members · 7 Events")
        XCTAssertEqual(both.countsLabel, "2 Members · 1 Upcoming Event")
    }

    // MARK: - Order

    func testTheOrderMenuUsesTheWebsNames() {
        XCTAssertEqual(PatchOrder.allCases.map(\.rawValue), ["Quilt order", "Recently added", "A→Z"])
    }

    func testQuiltOrderFollowsThePlacementTheCanvasIsDrawing() throws {
        let patches = try ["a", "b", "c"].map { try patch(#"{"id":"\#($0)","name":"\#($0.uppercased())","slug":"\#($0)"}"#) }
        let sorted = PatchOrder.quilt.sort(patches, placement: ["c", "a", "b"])
        XCTAssertEqual(sorted.map(\.id), ["c", "a", "b"])
    }

    func testAPatchWithNoTileKeepsTheTailInItsGivenOrder() throws {
        let patches = try ["a", "b", "c"].map { try patch(#"{"id":"\#($0)","name":"\#($0.uppercased())","slug":"\#($0)"}"#) }
        let sorted = PatchOrder.quilt.sort(patches, placement: ["c"])
        XCTAssertEqual(sorted.map(\.id), ["c", "a", "b"],
                       "Unplaced patches keep the tail rather than being handed a place in a quilt they are not in")
    }

    func testRecentlyAddedAsksWhenAPatchArrivedAndFallsBackToWhenItWasListed() throws {
        let arrived = try patch(#"{"id":"arrived","name":"Zed","slug":"z","activated_at":"2026-05-01T00:00:00Z","created_at":"2020-01-01T00:00:00Z"}"#)
        let listed = try patch(#"{"id":"listed","name":"Ada","slug":"a","created_at":"2026-06-01T00:00:00Z"}"#)
        let undated = try patch(#"{"id":"undated","name":"Bea","slug":"b"}"#)
        let sorted = PatchOrder.recent.sort([arrived, undated, listed], placement: [])
        XCTAssertEqual(sorted.map(\.id), ["listed", "arrived", "undated"])
    }

    func testUndatedPatchesTieAndReadAToZ() throws {
        let zed = try patch(#"{"id":"z","name":"Zed","slug":"z"}"#)
        let ada = try patch(#"{"id":"a","name":"Ada","slug":"a"}"#)
        XCTAssertEqual(PatchOrder.recent.sort([zed, ada], placement: []).map(\.id), ["a", "z"])
    }

    func testAToZReadsAsAPersonWouldSayIt() throws {
        let names = ["Émile's", "apple", "Zebra", "Banana"]
        let patches = try names.enumerated().map { try patch(#"{"id":"\#($0.offset)","name":"\#($0.element)","slug":"s\#($0.offset)"}"#) }
        XCTAssertEqual(PatchOrder.alpha.sort(patches, placement: []).map(\.name),
                       ["apple", "Banana", "Émile's", "Zebra"])
    }
}
