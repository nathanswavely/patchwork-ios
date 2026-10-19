// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// Where a tapped link to a quilt's website lands, checked as values against
/// the website's own route table.
final class LinkTargetTests: XCTestCase {
    private func target(_ path: String) -> LinkTarget {
        LinkTarget.of(URL(string: "https://lancasterpatchwork.org" + path)!)
    }

    func testTheShellsOwnPlaces() {
        XCTAssertEqual(target(""), .quilt(my: false))
        XCTAssertEqual(target("/"), .quilt(my: false))
        XCTAssertEqual(target("/my"), .quilt(my: true))
        XCTAssertEqual(target("/map/my"), .quilt(my: true))
        XCTAssertEqual(target("/events"), .events(my: false))
        XCTAssertEqual(target("/events/my"), .events(my: true))
        XCTAssertEqual(target("/discover"), .discover)
        XCTAssertEqual(target("/dashboard"), .dashboard)
        XCTAssertEqual(target("/notifications"), .notifications)
        XCTAssertEqual(target("/label"), .info(.label))
        XCTAssertEqual(target("/governance"), .info(.governance), "the quilt's page about governance, not a patch's")
        XCTAssertEqual(target("/terms"), .info(.terms))
    }

    func testPatchesAndTheirRooms() {
        XCTAssertEqual(target("/patches/common-thread"), .patch(slug: "common-thread"))
        XCTAssertEqual(target("/patches/common-thread/"), .patch(slug: "common-thread"))
        XCTAssertEqual(target("/patches/common-thread/events"), .screen(.calendar(slug: "common-thread")))
        XCTAssertEqual(target("/patches/common-thread/governance/abc"), .screen(.proposal(slug: "common-thread", id: "abc")))
        XCTAssertEqual(target("/patches/common-thread/governance/docs/d1"), .screen(.document(slug: "common-thread", id: "d1")))
        XCTAssertEqual(target("/patches/common-thread/noticeboard/n1"), .screen(.notice(slug: "common-thread", id: "n1")))
        XCTAssertEqual(target("/patches/common-thread/members?status=pending"), .screen(.joinRequests(slug: "common-thread")))
    }

    func testEventsPeopleAndInvites() {
        XCTAssertEqual(target("/events/e1"), .screen(.event(id: "e1")))
        XCTAssertEqual(target("/users/rowan"), .screen(.person(username: "rowan")))
        XCTAssertEqual(target("/invite/tok123"), .invite(link: "https://lancasterpatchwork.org/invite/tok123"))
    }

    func testFormsAndUnbuiltPagesStayTheWebsites() {
        XCTAssertEqual(target("/patches/new"), .website(path: "/patches/new"))
        XCTAssertEqual(target("/events/new"), .website(path: "/events/new"))
        XCTAssertEqual(target("/patches/common-thread/settings/info"), .website(path: "/patches/common-thread/settings/info"))
        XCTAssertEqual(target("/admin/review"), .website(path: "/admin/review"))
    }
}
