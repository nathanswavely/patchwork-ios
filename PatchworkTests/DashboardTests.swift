// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// The Dashboard's two decisions — how the index becomes four lists, and what
/// a count says when the count is only a floor — and the one query this client
/// sends about a person rather than about a quilt.
final class DashboardTests: XCTestCase {
    private func rows(_ json: String) throws -> [Membership] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MembershipPage.self, from: Data(json.utf8)).items
    }

    private func row(slug: String, name: String, role: String?, status: String) -> String {
        let roleField = role.map { ",\"role\":\"\($0)\"" } ?? ""
        return "{\"id\":\"m-\(slug)\",\"user_id\":\"u\",\"node_id\":\"n-\(slug)\"\(roleField)," +
            "\"status\":\"\(status)\",\"node_slug\":\"\(slug)\",\"node_name\":\"\(name)\"}"
    }

    // MARK: - Grouping

    func testTheIndexBecomesTheWebsFourLists() throws {
        let index = try rows("""
        {"items":[
        \(row(slug: "a", name: "Anvil Club", role: "admin", status: "active")),
        \(row(slug: "b", name: "Bike Kitchen", role: "member", status: "active")),
        \(row(slug: "c", name: "Common Thread", role: "follower", status: "active")),
        \(row(slug: "d", name: "Drum Room", role: nil, status: "pending"))
        ]}
        """)
        let sections = DashboardGrouping.group(index)
        XCTAssertEqual(sections.managing.map(\.slug), ["a"])
        XCTAssertEqual(sections.member.map(\.slug), ["b"])
        XCTAssertEqual(sections.following.map(\.slug), ["c"])
        XCTAssertEqual(sections.requested.map(\.slug), ["d"], "Withdrawing is not leaving, so a request is its own list")
        XCTAssertFalse(sections.isEmpty)
    }

    func testEachListReadsAToZ() throws {
        let index = try rows("""
        {"items":[
        \(row(slug: "z", name: "Zither Circle", role: "follower", status: "active")),
        \(row(slug: "a", name: "Anvil Club", role: "follower", status: "active")),
        \(row(slug: "m", name: "Market Friends", role: "follower", status: "active"))
        ]}
        """)
        XCTAssertEqual(DashboardGrouping.group(index).following.map(\.name),
                       ["Anvil Club", "Market Friends", "Zither Circle"],
                       "A dashboard is a place to find a patch again, not a feed")
    }

    func testARowThatIsNeitherActiveNorPendingIsNotDrawn() throws {
        let index = try rows("{\"items\":[\(row(slug: "a", name: "A", role: "member", status: "banned"))]}")
        XCTAssertTrue(DashboardGrouping.group(index).isEmpty,
                      "The server serves active and pending rows; anything else is not a section this app invents")
    }

    func testAnEmptyIndexIsAnEmptyDashboard() {
        XCTAssertTrue(DashboardGrouping.group([]).isEmpty)
    }

    // MARK: - What a badge can honestly say

    func testAFullPageWithACursorBehindItSaysSoRatherThanPrintingTwenty() {
        XCTAssertEqual(DashboardGrouping.countLabel(count: 20, more: true), "20+")
        XCTAssertEqual(DashboardGrouping.countLabel(count: 20, more: false), "20")
        XCTAssertEqual(DashboardGrouping.countLabel(count: 3, more: false), "3")
    }

    // MARK: - The one query about a person

    func testTheScopedEventsQueryIsTheReadersOwnFeed() {
        let from = Date(timeIntervalSince1970: 1_790_000_000)
        let query = PatchworkAPI.myEventsQuery(from: from, limit: 20)
        XCTAssertEqual(query.first { $0.name == "scope" }?.value, "my")
        XCTAssertEqual(query.first { $0.name == "limit" }?.value, "20")
        let bound = query.first { $0.name == "from" }?.value
        XCTAssertEqual(bound, ISO8601DateFormatter().string(from: from))
        // An instant, never a bare date: the server compares `starts_at` as
        // text, so a bare date would drop the day it names.
        XCTAssertEqual(bound?.hasSuffix("Z"), true)
        XCTAssertNil(query.first { $0.name == "node_slug" }, "The feed is scoped by who you are, not by which patch")
    }
}
