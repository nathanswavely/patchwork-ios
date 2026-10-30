// SPDX-License-Identifier: MPL-2.0

import XCTest

/// A link to the quilt's website, tapped somewhere else, opens where the
/// website would have put it. The simulator cannot be tapped into a
/// universal link for a quilt that does not exist, so the link arrives at
/// launch (`--open-link`), through the same door the system uses.
final class LinkFlowTests: XCTestCase {
    private func launch(_ link: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--skip-intro", "--open-link", "https://quilt.example.org" + link]
        app.launch()
        return app
    }

    func testAPatchLinkDocksThePatchPastTheFirstLook() {
        let app = launch("/patches/common-thread")
        XCTAssertTrue(app.buttons["closePatch"].waitForExistence(timeout: 15), "the patch docks")
        XCTAssertFalse(app.otherElements["firstLook"].exists, "a tapped link is a choice of quilt")
    }

    func testAProposalLinkOpensItsScreenAndShares() {
        let app = launch("/patches/common-thread/governance/proposals/demo-proposal")
        XCTAssertTrue(app.navigationBars["Proposal"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["shareProposal"].exists, "its own address goes back out")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Sample quilt"].waitForExistence(timeout: 10))
    }

    func testAQuiltPageLinkOpensTheInformationStack() {
        let app = launch("/about")
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 15))
    }
}
