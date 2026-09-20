// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// The public half of a patch's face beyond its head: what the new payloads
/// decode to, and — more to the point — which sentence each kind of empty
/// gets. A withheld roster and an empty one decode to the same array and must
/// never read the same way.
final class ProfileDepthTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    // MARK: - The node and its envelope

    func testPatchCarriesTheProfileDepthFields() throws {
        let json = #"""
        {"node":{"id":"n","name":"Our patch","slug":"our-patch","did":"did:web:ourpatch.example",
        "moved_to":"https://other.example/patches/our-patch","visibility":"public",
        "public_member_list":"admins","public_governance_record":"nobody",
        "links":[{"url":"https://example.org","label":"Our site"}]},
        "is_unclaimed":false,"lining_status":"diverged"}
        """#
        let response = try decoder().decode(PatchResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.node.did, "did:web:ourpatch.example")
        XCTAssertEqual(response.node.visibility, "public")
        XCTAssertEqual(response.node.publicMemberList, "admins")
        XCTAssertEqual(response.node.publicGovernanceRecord, "nobody")
        XCTAssertEqual(response.node.links?.first?.label, "Our site")
        // The two facts that ride the envelope rather than the node. Read off
        // `node` they are always nil, which silently drops the badge on the
        // one patch that must wear it.
        XCTAssertEqual(response.isUnclaimed, false)
        XCTAssertEqual(response.liningStatus, "diverged")
    }

    func testEnvelopeFieldsAreOptional() throws {
        let response = try decoder().decode(PatchResponse.self, from: Data(#"{"node":{"id":"n","name":"N","slug":"n"}}"#.utf8))
        XCTAssertNil(response.isUnclaimed)
        XCTAssertNil(response.liningStatus)
        XCTAssertNil(response.node.did)
    }

    func testAtprotoHandleComesOffTheDIDAndNothingElse() {
        XCTAssertEqual(AtprotoHandle.from("did:web:tellus.example"), "tellus.example")
        // Extra colon-separated segments are path, not host (the did:web method).
        XCTAssertEqual(AtprotoHandle.from("did:web:tellus.example:patch:1"), "tellus.example")
        XCTAssertEqual(AtprotoHandle.from("did:web:localhost%3A8080"), "localhost:8080")
        for value in ["did:plc:abc123", "tellus.example", "", "did:web:"] {
            XCTAssertNil(AtprotoHandle.from(value), value)
        }
        XCTAssertNil(AtprotoHandle.from(nil))
    }

    func testAForwardingAddressIsOnlyARemotePatchWhenItNamesOne() {
        let moved = MovedElsewhere("https://other.example/patches/our-patch")
        XCTAssertEqual(moved?.host, "other.example")
        XCTAssertEqual(moved?.slug, "our-patch")
        for value in ["https://other.example", "https://other.example/events/1", "http://other.example/patches/a", "not a url"] {
            XCTAssertNil(MovedElsewhere(value), value)
        }
        XCTAssertNil(MovedElsewhere(nil))
    }

    // MARK: - Members (web ADR 095)

    func testRosterKeepsServerCountsAndDropsFollowers() throws {
        let json = #"""
        {"items":[{"id":"m1","user_id":"u1","role":"admin","username":"rowan","display_name":"Rowan Hale"},
        {"id":"m2","user_id":"u2","role":"member","username":"theo","display_name":""},
        {"id":"m3","user_id":"u3","role":"follower","username":"watcher"}],
        "next_cursor":"c1","member_count":40,"follower_count":12,"public_member_list":"everyone"}
        """#
        let roster = MemberRoster(page: try decoder().decode(MemberPage.self, from: Data(json.utf8)))
        // Admins plus members, never followers: the two are counted apart and
        // never summed.
        XCTAssertEqual(roster.members.map(\.username), ["rowan", "theo"])
        // The count is the server's, not the page's length — that is the bug
        // that had the head saying 40 and the roster saying 2.
        XCTAssertEqual(roster.memberCount, 40)
        XCTAssertEqual(roster.followerCount, 12)
        XCTAssertEqual(roster.countLine, "40 members · 12 following")
        XCTAssertEqual(roster.cursor, "c1")
        XCTAssertFalse(roster.withheld)
        XCTAssertEqual(roster.title, "Members")
        // A name falls back to the username the API gave when there is no
        // display name to use.
        XCTAssertEqual(roster.members[1].name, "theo")
        XCTAssertEqual(roster.members[1].initial, "T")
    }

    func testAWithheldRosterNeverReadsAsAnEmptyOne() throws {
        let json = #"{"items":[],"next_cursor":"","member_count":8,"follower_count":3,"public_member_list":"nobody"}"#
        let roster = MemberRoster(page: try decoder().decode(MemberPage.self, from: Data(json.utf8)))
        XCTAssertTrue(roster.withheld)
        XCTAssertEqual(roster.emptyTitle, "Member list not published")
        XCTAssertEqual(roster.emptyMessage, "This patch doesn’t publish its member list.")
        XCTAssertNotEqual(roster.emptyMessage, "No members yet.")
        // The count stays public at every rung: the quilt sizes this patch's
        // tile by it, so withholding it here would hide nothing.
        XCTAssertEqual(roster.countLine, "8 members · 3 following")
    }

    func testAnAdminsOnlyRosterIsHeadedAdmins() throws {
        let json = #"{"items":[{"id":"m1","user_id":"u1","role":"admin","username":"rowan"}],"member_count":40,"follower_count":0,"public_member_list":"admins"}"#
        let roster = MemberRoster(page: try decoder().decode(MemberPage.self, from: Data(json.utf8)))
        XCTAssertTrue(roster.adminsOnly)
        XCTAssertFalse(roster.withheld)
        // Beside "Admins" the total would count people the list omits.
        XCTAssertEqual(roster.title, "Admins")
        XCTAssertEqual(roster.memberCount, 40)
    }

    func testAnAbsentSettingMeansEveryone() {
        XCTAssertEqual(RosterDisclosure(nil), .everyone)
        XCTAssertEqual(RosterDisclosure("something-new"), .everyone)
        XCTAssertEqual(RosterDisclosure("nobody"), .nobody)
    }

    func testRosterPagingDoesNotDuplicateOrRecount() throws {
        let first = #"{"items":[{"id":"m1","user_id":"u1","role":"member","username":"a"}],"next_cursor":"m1","member_count":3,"follower_count":0,"public_member_list":"everyone"}"#
        let second = #"{"items":[{"id":"m1","user_id":"u1","role":"member","username":"a"},{"id":"m2","user_id":"u2","role":"member","username":"b"}],"next_cursor":"","member_count":3,"follower_count":0,"public_member_list":"everyone"}"#
        var roster = MemberRoster(page: try decoder().decode(MemberPage.self, from: Data(first.utf8)))
        roster.append(try decoder().decode(MemberPage.self, from: Data(second.utf8)))
        XCTAssertEqual(roster.members.map(\.username), ["a", "b"])
        XCTAssertEqual(roster.memberCount, 3)
        XCTAssertEqual(roster.cursor, "")
    }

    // MARK: - Governance documents (web ADR 036, ADR 037)

    func testGovernanceListingSaysWhichKindOfEmptyItIs() throws {
        let published = try decoder().decode(GovernanceDocumentPage.self, from: Data(#"{"items":[],"published_only":true}"#.utf8))
        XCTAssertEqual(published.publishedOnly, true)
        let everything = try decoder().decode(GovernanceDocumentPage.self, from: Data(#"{"items":null}"#.utf8))
        XCTAssertNil(everything.items)
        XCTAssertNil(everything.publishedOnly)
    }

    func testGovernanceDocumentDecodesTheLiveShape() throws {
        let json = ###"{"id":"d1","node_id":"n","title":"Community Standards","body":"## Keep each other safe\n\nText.","kind":"lining","visibility":"public","version":1,"created_by":"u","created_at":"2026-09-16T20:02:34.644Z","updated_at":"2026-09-16T20:02:34.644Z","filename":"community-standards.md"}"###
        let document = try decoder().decode(GovernanceDocument.self, from: Data(json.utf8))
        XCTAssertEqual(document.kind, "lining")
        XCTAssertEqual(document.version, 1)
        XCTAssertNotNil(ProfileDate.day(document.updatedAt))
    }

    // MARK: - Governance overview

    func testOverviewWithheldAdminsAreNotAVacancy() throws {
        let json = #"{"admins":[],"admins_withheld":true,"document_count":0,"election":null,"member_count":2,"membership_policy":"open","needs_vote":0,"next_contest_opens":"","next_term_end":"","open_proposals":0,"passed_proposals":1,"rejected_proposals":0,"proposals_withheld":true,"rules":{"decision_method":"majority","quorum_percent":0,"default_vote_duration_hours":72,"leadership_model":"maintainer","inactivity_days":90,"max_admins":3},"seats":[],"successor":{}}"#
        let overview = try decoder().decode(GovernanceOverview.self, from: Data(json.utf8))
        XCTAssertEqual(overview.adminsWithheld, true)
        XCTAssertEqual(overview.admins?.isEmpty, true)
        XCTAssertEqual(overview.proposalsWithheld, true)
        XCTAssertNil(overview.election)
        XCTAssertEqual(overview.leadershipLabel, "Maintainer")
        XCTAssertFalse(overview.showsCouncil)
        XCTAssertTrue(overview.decisionNarrative.contains("majority vote"))
        XCTAssertTrue(overview.decisionNarrative.contains("No minimum participation"))
        XCTAssertTrue(overview.decisionNarrative.contains("3 days"))
        XCTAssertTrue(overview.leadershipNarrative.contains("90 days"))
        XCTAssertTrue(overview.leadershipNarrative.contains("180 days"))
    }

    func testAPatchThatDecidesElsewhereIsNotNarratedAQuorumItDoesNotRun() throws {
        let json = #"{"rules":{"decision_method":"majority","quorum_percent":50,"proposal_venue":"elsewhere","leadership_venue":"elsewhere","leadership_model":"elected"}}"#
        let overview = try decoder().decode(GovernanceOverview.self, from: Data(json.utf8))
        XCTAssertEqual(overview.decisionNarrative, "Proposals are decided outside Patchwork. They stay open here for discussion, and adoption is recorded on the charter.")
        XCTAssertEqual(overview.leadershipNarrative, "")
        // An elected patch that elects elsewhere runs no council here.
        XCTAssertFalse(overview.showsCouncil)
    }

    func testASeatWhoseHolderIsWithheldIsHeldNotVacant() throws {
        let json = #"{"id":"s1","vacant":false,"holder_withheld":true,"fill":"contest_scheduled","contest_opens":"2027-08-15","term_ends_at":"2027-08-15T00:00:00Z"}"#
        let seat = try decoder().decode(GovernanceSeat.self, from: Data(json.utf8))
        XCTAssertFalse(seat.isVacant)
        XCTAssertEqual(seat.holder, "Held")
        XCTAssertTrue(seat.fate.contains("Contested from"))
    }

    func testAVacantSeatInAnOpenContestSaysSo() throws {
        let json = #"{"id":"s2","vacant":true,"fill":"contest_open","contest_id":"p9"}"#
        let seat = try decoder().decode(GovernanceSeat.self, from: Data(json.utf8))
        XCTAssertTrue(seat.isVacant)
        XCTAssertEqual(seat.holder, "Vacant")
        XCTAssertEqual(seat.fate, "In the contest running now.")
    }

    // MARK: - Proposals (web ADR 097, ADR 051, ADR 041)

    func testOutcomeReadsStateBeforeStatus() throws {
        let lapsed = try decoder().decode(Proposal.self, from: Data(#"{"id":"p","title":"T","status":"rejected","state":"lapsed"}"#.utf8))
        // Nobody rejected it: the window closed under quorum.
        XCTAssertEqual(lapsed.outcome, "lapsed")
        XCTAssertFalse(lapsed.outcomeIsDecision)
        let unsettled = try decoder().decode(Proposal.self, from: Data(#"{"id":"p","title":"T","status":"rejected","state":"unsettled"}"#.utf8))
        XCTAssertEqual(unsettled.outcome, "unsettled")
        XCTAssertFalse(unsettled.outcomeIsDecision)
        let rejected = try decoder().decode(Proposal.self, from: Data(#"{"id":"p","title":"T","status":"rejected","state":"closed","reject_count":4,"approve_count":1}"#.utf8))
        XCTAssertEqual(rejected.outcome, "rejected")
        XCTAssertTrue(rejected.outcomeIsDecision)
    }

    func testAnApprovedProposalWithNoBallotsIsAnAppliedDirectChange() throws {
        let direct = try decoder().decode(Proposal.self, from: Data(#"{"id":"p","title":"T","status":"approved","approve_count":0,"reject_count":0,"abstain_count":0}"#.utf8))
        XCTAssertTrue(direct.isDirectChange)
        XCTAssertEqual(direct.outcome, "applied")
        let voted = try decoder().decode(Proposal.self, from: Data(#"{"id":"p","title":"T","status":"approved","approve_count":6,"reject_count":1}"#.utf8))
        XCTAssertFalse(voted.isDirectChange)
        XCTAssertEqual(voted.outcome, "approved")
        XCTAssertEqual(voted.ballots, 7)
    }

    func testProposalPageStatesWhetherTheRecordIsPublic() throws {
        let page = try decoder().decode(ProposalPage.self, from: Data(#"{"items":[],"next_cursor":"","public_governance_record":"nobody"}"#.utf8))
        XCTAssertEqual(page.publicGovernanceRecord, "nobody")
        XCTAssertEqual(page.items?.isEmpty, true)
    }

    // MARK: - Record (web ADR 055, ADR 097, ADR 106)

    func testRecordSentencesDistinguishAnAbsenceFromADecision() throws {
        let json = #"""
        {"items":[
        {"kind":"vote","at":"2026-08-14T12:00:00Z","title":"Amend hours","outcome":"carried"},
        {"kind":"vote","at":"2026-06-08T12:00:00Z","title":"Second kiln","outcome":"lapsed"},
        {"kind":"direct","at":"2026-04-02T12:00:00Z","title":"Publish","outcome":"applied","actor":"Rowan Hale"},
        {"kind":"election","at":"2026-03-01T12:00:00Z","title":"Council","outcome":"seated","names":["Ana","Sam","Kit"]},
        {"kind":"election","at":"2026-02-01T12:00:00Z","title":"Council","outcome":"unsettled"},
        {"kind":"adoption","at":"2026-01-01T12:00:00Z","title":"Charter"}],
        "public_governance_record":"everyone"}
        """#
        let page = try decoder().decode(GovernanceRecordPage.self, from: Data(json.utf8))
        let entries = try XCTUnwrap(page.items)
        XCTAssertEqual(entries[0].outcomeLine, "Carried by a vote.")
        XCTAssertTrue(entries[0].settled)
        // A lapse is not a vote that failed: "did not carry" says the members
        // answered no, which is the one thing it must not say.
        XCTAssertEqual(entries[1].outcomeLine, "Put to a vote. Nobody decided it either way; the proposal lapsed.")
        XCTAssertFalse(entries[1].settled)
        XCTAssertEqual(entries[2].outcomeLine, "Applied by Rowan Hale.")
        XCTAssertEqual(entries[3].outcomeLine, "The members seated Ana, Sam and Kit.")
        XCTAssertEqual(entries[4].outcomeLine, "Settled nothing. Nobody was elected.")
        XCTAssertEqual(entries[5].outcomeLine, "A meeting adopted this text.")
        XCTAssertEqual(entries[0].kindLabel, "Vote")
        XCTAssertEqual(entries[2].kindLabel, "Direct change")
        XCTAssertEqual(entries[5].kindLabel, "Adopted elsewhere")
    }

    func testARecordWithoutNamesStillReadsAsASentence() throws {
        let json = #"{"kind":"council","at":"2026-01-01T12:00:00Z","title":"Council","names":[]}"#
        let entry = try decoder().decode(GovernanceRecordEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.outcomeLine, "A meeting chose the council.")
        let one = try decoder().decode(GovernanceRecordEntry.self, from: Data(#"{"kind":"council","title":"C","names":["Ana"]}"#.utf8))
        XCTAssertEqual(one.outcomeLine, "Seated Ana.")
    }

    // MARK: - Query and feed addresses

    func testUpcomingEventsAreBoundedByFromAndTheCalendarIsNot() {
        let from = Date(timeIntervalSince1970: 1_790_000_000)
        let glimpse = PatchworkAPI.eventsQuery(slug: "our-patch", limit: 3, from: from)
        XCTAssertEqual(glimpse.first { $0.name == "node_slug" }?.value, "our-patch")
        XCTAssertEqual(glimpse.first { $0.name == "limit" }?.value, "3")
        XCTAssertEqual(glimpse.first { $0.name == "from" }?.value, ISO8601DateFormatter().string(from: from))
        XCTAssertNil(glimpse.first { $0.name == "include_past" })

        // The calendar's upcoming half is the same bounded ask, uncapped.
        let calendarUpcoming = PatchworkAPI.eventsQuery(slug: "our-patch", limit: 100, from: from)
        XCTAssertNil(calendarUpcoming.first { $0.name == "include_past" })
        XCTAssertNotNil(calendarUpcoming.first { $0.name == "from" })

        // Its earlier half drops the bound and puts one at the other end:
        // the server pages oldest-first, so "the whole calendar" in one ask
        // would hand a busy venue its own history instead of tonight.
        let calendarEarlier = PatchworkAPI.eventsQuery(slug: "our-patch", limit: 100, to: from, includePast: true)
        XCTAssertEqual(calendarEarlier.first { $0.name == "include_past" }?.value, "true")
        XCTAssertEqual(calendarEarlier.first { $0.name == "to" }?.value, ISO8601DateFormatter().string(from: from))
        XCTAssertNil(calendarEarlier.first { $0.name == "from" })
    }

    func testFeedAddressesAreTheQuiltsOwnAPIPaths() throws {
        let api = PatchworkAPI(base: URL(string: "https://quilt.example.org")!)
        XCTAssertEqual(api.apiURL("nodes/our-patch/events.ics").absoluteString, "https://quilt.example.org/api/v1/nodes/our-patch/events.ics")
        XCTAssertEqual(api.apiURL("nodes/our-patch/events.rss").absoluteString, "https://quilt.example.org/api/v1/nodes/our-patch/events.rss")
        // webcal is what hands the feed to a calendar app rather than
        // downloading it once.
        XCTAssertEqual(api.subscriptionURL("nodes/our-patch/events.ics")?.absoluteString, "webcal://quilt.example.org/api/v1/nodes/our-patch/events.ics")
    }

    func testProfileDatesReadBothATimestampAndABareDay() {
        XCTAssertNotNil(ProfileDate.parse("2026-08-14T12:00:00Z"))
        XCTAssertNotNil(ProfileDate.parse("2026-08-14T12:00:00.123Z"))
        // next_contest_opens is a calendar day, not a timestamp.
        XCTAssertNotNil(ProfileDate.parse("2027-08-15"))
        // An empty string is how the server says "no date", and must not
        // become a formatted one.
        XCTAssertNil(ProfileDate.parse(""))
        XCTAssertNil(ProfileDate.parse(nil))
        XCTAssertNil(ProfileDate.day(""))
        XCTAssertNil(ProfileDate.monthYear(nil))
    }
}
