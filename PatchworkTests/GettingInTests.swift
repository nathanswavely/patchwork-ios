// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// Getting in, checked as values: answering an invitation, creating and
/// suggesting a patch, claiming one and setting it up, and the first-time
/// account's Welcome.
final class GettingInTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    private func patch(_ json: String) throws -> Patch { try decode(Patch.self, json) }

    // MARK: - Invitations

    func testAnInvitationDecodesAsTheServerSendsIt() throws {
        let page = try decode(InvitationPage.self, #"{"items":[{"id":"m1","node_id":"n1","node_slug":"food-share","node_name":"Food Share","status":"invited","invited_at":"2026-10-01T10:00:00Z"}]}"#)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].nodeSlug, "food-share")
        XCTAssertEqual(page.items[0].name, "Food Share")
    }

    func testOnlyInvitedRowsAreReadAsInvitations() throws {
        // The web's own guard: a stub that answers with membership rows must
        // not turn a membership into an invitation.
        let page = try decode(InvitationPage.self, #"{"items":[{"id":"m1","node_slug":"a","status":"active"},{"id":"m2","node_slug":"b","status":"invited"}]}"#)
        XCTAssertEqual(page.items.map(\.nodeSlug), ["b"])
        XCTAssertTrue(try decode(InvitationPage.self, "{}").items.isEmpty)
    }

    func testAnInvitationTakesThePlaceOfTheOffers() throws {
        let node = try patch(#"{"id":"p","name":"Food Share","slug":"food-share","visibility":"public","membership_policy":"invite_only"}"#)
        XCTAssertEqual(Relationship.resolve(node: node, standing: nil, invited: true), .invited)
        XCTAssertEqual(Relationship.resolve(node: node, standing: nil), .offering(.init(follow: true, join: nil)),
                       "uninvited, an invite-only patch can be followed and not joined")
    }

    func testAStandingTheIndexHoldsOutranksAnInvitation() throws {
        let node = try patch(#"{"id":"p","name":"Food Share","slug":"food-share","visibility":"public","membership_policy":"invite_only"}"#)
        XCTAssertEqual(Relationship.resolve(node: node, standing: .active(.member), invited: true), .holding(.member))
        XCTAssertEqual(Relationship.resolve(node: node, standing: .pending, invited: true), .requested)
    }

    func testAnInvitationIsNotAnsweredOnAMovedOrBannedPatch() throws {
        let moved = try patch(#"{"id":"p","name":"A","slug":"a","visibility":"public","membership_policy":"invite_only","moved_to":"https://neighbor.example.org/patches/a"}"#)
        XCTAssertEqual(Relationship.resolve(node: moved, standing: nil, invited: true), .none, "accepting is a join, and a moved patch takes none")
        let banned = try patch(#"{"id":"p","name":"A","slug":"a","visibility":"public","is_banned":true}"#)
        XCTAssertEqual(Relationship.resolve(node: banned, standing: nil, invited: true), .none)
    }

    func testTheAnswersAreSaidInTheWebsWords() {
        XCTAssertEqual(RelationshipControl.sentence(for: "active"), "You are now a member")
        XCTAssertEqual(RelationshipControl.sentence(for: "declined"), "Invitation declined")
        XCTAssertEqual(Relationship.invitedLabel, "You've been invited to join")
    }

    // MARK: - Creating a patch

    private func json(_ body: some Encodable) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(body)) as? [String: Any])
    }

    private var draft: PatchDraft { PatchDraft(palette: "anthem", block: "ohioStar", rotation: 90) }

    func testANewDraftStartsClosedAndMinimal() {
        XCTAssertEqual(draft.policy, .inviteOnly, "preselected to the closed option, as the web does")
        XCTAssertEqual(draft.template, .minimal)
        var generator = SystemRandomNumberGenerator()
        let seeded = PatchDraft.seeded(using: &generator)
        XCTAssertNotNil(QuiltTheme.byKey[seeded.palette], "a seeded tile is a real palette")
        XCTAssertTrue(QuiltBlocks.keys.contains(seeded.block))
        XCTAssertTrue([0, 90, 180, 270].contains(seeded.rotation))
    }

    func testTheCreateBodyAlwaysCarriesTheMembershipPolicy() throws {
        var bare = draft
        bare.name = "  Night Market  "
        let body = try json(bare.createBody)
        XCTAssertEqual(body["membership_policy"] as? String, "invite_only",
                       "the server defaults a missing policy to open, so it is never left out")
        XCTAssertEqual(body["name"] as? String, "Night Market", "trimmed, as the web sends it")
        XCTAssertEqual(body["visibility"] as? String, "public")
        XCTAssertEqual(body["template"] as? String, "minimal")
        for absent in ["description", "address", "website", "latitude", "longitude", "tags", "suggest_tags"] {
            XCTAssertNil(body[absent], "\(absent) is left out while blank")
        }
        let appearance = try XCTUnwrap(body["appearance"] as? [String: Any])
        XCTAssertEqual(appearance["palette"] as? String, "anthem")
        XCTAssertEqual(appearance["block"] as? String, "ohioStar")
        XCTAssertEqual(appearance["rotation"] as? Int, 90)
        XCTAssertNil(appearance["icon"], "an unset motif follows the first tag")

        var open = bare
        open.answer(.open)
        XCTAssertEqual(try json(open.createBody)["membership_policy"] as? String, "open")
    }

    func testOnlyAConfirmedPointTravels() throws {
        var filled = draft
        filled.name = "Night Market"
        filled.address = "12 Example Street"
        XCTAssertNil(try json(filled.createBody)["latitude"], "an address implies no point")
        filled.point = MapPoint(latitude: 40.0379, longitude: -76.3055)
        let body = try json(filled.createBody)
        XCTAssertEqual(body["latitude"] as? Double, 40.0379)
        XCTAssertEqual(body["longitude"] as? Double, -76.3055)
        XCTAssertEqual(body["address"] as? String, "12 Example Street")
    }

    func testTagsAndSuggestedWordsTravelApart() throws {
        var filled = draft
        filled.name = "N"
        filled.tags = ["music", "venue"]
        filled.suggestTags = ["zines"]
        filled.toggleMotif("vinyl")
        let body = try json(filled.createBody)
        XCTAssertEqual(body["tags"] as? [String], ["music", "venue"], "in priority order")
        XCTAssertEqual(body["suggest_tags"] as? [String], ["zines"])
        XCTAssertEqual((body["appearance"] as? [String: Any])?["icon"] as? String, "vinyl")
        filled.toggleMotif("vinyl")
        XCTAssertEqual(filled.motif, "", "pressed again, a motif is let go of")
    }

    func testANameIsTheOneThingTheFormChecks() {
        XCTAssertEqual(draft.problem(), "Name is required")
        var named = draft
        named.name = "   "
        XCTAssertEqual(named.problem(), "Name is required")
        named.name = "Night Market"
        XCTAssertNil(named.problem())
    }

    func testCreationNeverLetsTheTemplateMoveThePolicy() {
        var creating = draft
        creating.choose(.casual, setup: false)
        XCTAssertEqual(creating.template, .casual)
        XCTAssertEqual(creating.policy, .inviteOnly)
    }

    func testSetupSeedsThePolicyFromTheTemplateUntilItIsAnswered() throws {
        let listing = try patch(#"{"id":"extra-9","name":"Evening Choir","slug":"extra-9","description":"We sing.","address":"1 Hall Lane","latitude":40.1,"longitude":-76.2,"tags":["music"],"appearance":{"palette":"anthem","icon":"micStage"}}"#)
        var setup = PatchDraft(setup: listing)
        XCTAssertEqual(setup.name, "Evening Choir")
        XCTAssertEqual(setup.address, "1 Hall Lane")
        XCTAssertEqual(setup.point, MapPoint(latitude: 40.1, longitude: -76.2), "the listing's own point is already the listing's")
        XCTAssertEqual(setup.tags, ["music"])
        XCTAssertEqual(setup.palette, "anthem", "the tile it already wears, not a reroll")
        XCTAssertEqual(setup.motif, "micStage")
        XCTAssertEqual(setup.policy, .inviteOnly, "Minimal's own answer")
        setup.choose(.casual, setup: true)
        XCTAssertEqual(setup.policy, .open, "follows the template")
        setup.choose(.collaborative, setup: true)
        XCTAssertEqual(setup.policy, .approvalRequired)
        setup.answer(.inviteOnly)
        setup.choose(.casual, setup: true)
        XCTAssertEqual(setup.policy, .inviteOnly, "once answered, nothing moves it")
        let body = try json(setup.setupBody)
        XCTAssertEqual(body["template"] as? String, "casual")
        XCTAssertEqual(body["membership_policy"] as? String, "invite_only")
        let update = try json(setup.updateBody)
        XCTAssertNil(update["membership_policy"], "PATCH nodes takes no policy: governance moves through the rules")
        XCTAssertEqual(update["visibility"] as? String, "public")
    }

    func testTheTemplatesAreTheWebs() {
        XCTAssertEqual(GovernanceTemplate.allCases.map(\.name), ["Minimal", "Casual", "Collaborative", "Formal"])
        XCTAssertEqual(GovernanceTemplate.minimal.detail, "No overhead. You're the only one running it.")
        XCTAssertEqual(GovernanceTemplate.formal.leadership, "Elected Council")
        XCTAssertEqual(GovernanceTemplate.allCases.map(\.membershipPolicy), [.inviteOnly, .open, .approvalRequired, .approvalRequired])
        XCTAssertEqual(MembershipPolicyChoice.allCases.map(\.name), ["Invite only", "Approval required", "Open"])
    }

    func testATagIsNormalisedTheWayTheServerSavesIt() {
        XCTAssertEqual(TagSuggestion.normalize("  Zine Fair! "), "zine-fair")
        XCTAssertEqual(TagSuggestion.normalize("open__mic -- night"), "open-mic-night")
        XCTAssertEqual(TagSuggestion.normalize("Café"), "café")
        XCTAssertEqual(TagSuggestion.normalize(String(repeating: "a", count: 40)).count, 32)
        XCTAssertEqual(TagSuggestion.add("Music", vocabulary: ["music"], picked: [], suggested: []), .picked("music"),
                       "a curated word is picked, never queued")
        XCTAssertEqual(TagSuggestion.add("zines", vocabulary: ["music"], picked: [], suggested: []), .suggested("zines"))
        XCTAssertEqual(TagSuggestion.add("zines", vocabulary: [], picked: [], suggested: ["zines"]), .refused("zines is already waiting for review."))
        XCTAssertEqual(TagSuggestion.add("!!", vocabulary: [], picked: [], suggested: []), .refused("Enter a word to suggest."))
    }

    func testAPlaceIsOnlyASuggestionWhenTheGazetteerFoundOne() throws {
        let found = try decode(PlaceSuggestion.self, #"{"found":true,"available":true,"place":{"latitude":40.0379,"longitude":-76.3055},"label":"12 Example Street"}"#)
        XCTAssertEqual(found.point, MapPoint(latitude: 40.0379, longitude: -76.3055))
        XCTAssertNil(try decode(PlaceSuggestion.self, #"{"found":false,"available":false}"#).point)
        XCTAssertNil(try decode(PlaceSuggestion.self, #"{"found":true,"place":{"latitude":120,"longitude":0}}"#).point)
        XCTAssertFalse(PlaceSuggestion.worthLookingUp(" ab "))
        XCTAssertTrue(PlaceSuggestion.worthLookingUp("Pub"))
    }

    func testTheCreatedNodeAndItsWarningDecode() throws {
        let created = try decode(CreatedPatch.self, #"{"id":"n1","name":"Night Market","slug":"night-market","tag_warning":"zines was declined"}"#)
        XCTAssertEqual(created.node.slug, "night-market")
        XCTAssertEqual(created.tagWarning, "zines was declined")
        XCTAssertNil(try decode(CreatedPatch.self, #"{"id":"n1","name":"N","slug":"n"}"#).tagWarning)
    }

    func testTheMiniatureIsTheDraftsTile() throws {
        var filled = draft
        filled.tags = ["music"]
        let preview = try XCTUnwrap(filled.preview(id: "new-patch"))
        XCTAssertEqual(QuiltTheme.palette(for: preview).key, "anthem")
        XCTAssertEqual(QuiltBlocks.rotation(id: preview.id, appearance: preview.appearance), 90)
        XCTAssertEqual(Motifs.key(for: preview, tagMotifs: ["music": "musicNotes"]), "musicNotes", "unset, it follows the first tag")
        XCTAssertEqual(Motifs.name("musicNotes"), "Music notes")
    }

    // MARK: - Suggesting a patch

    func testASuggestionSendsWhatTheWebSends() throws {
        var suggestion = SuggestionDraft()
        suggestion.name = " Gallery Row "
        suggestion.links = [.init(url: " https://galleryrow.example.org ", label: ""), .init(url: "", label: "orphan")]
        suggestion.tags = ["craft"]
        let body = try json(suggestion.body)
        XCTAssertEqual(body["name"] as? String, "Gallery Row")
        XCTAssertEqual(body["description"] as? String, "", "always sent; the server takes an empty one")
        let links = try XCTUnwrap(body["links"] as? [[String: Any]])
        XCTAssertEqual(links.count, 1, "a link with no address is dropped")
        XCTAssertEqual(links[0]["url"] as? String, "https://galleryrow.example.org")
        XCTAssertNil(links[0]["label"])
        XCTAssertEqual(body["tags"] as? [String], ["craft"])
        for absent in ["website", "address", "feed_url"] { XCTAssertNil(body[absent]) }
        suggestion.feedURL = "https://galleryrow.example.org/calendar.ics"
        XCTAssertEqual(try json(suggestion.body)["feed_url"] as? String, "https://galleryrow.example.org/calendar.ics")
        XCTAssertEqual(SuggestionDraft().problem(), "Name is required")
    }

    func testASuggestionsTwoEndings() throws {
        let published = try decode(SubmissionAnswer.self, #"{"status":"unclaimed","node":{"id":"n1","slug":"gallery-row","name":"Gallery Row"}}"#)
        XCTAssertTrue(published.published)
        XCTAssertEqual(published.node?.slug, "gallery-row")
        let waiting = try decode(SubmissionAnswer.self, #"{"status":"pending_review","message":"Submission sent for review","id":"s1"}"#)
        XCTAssertFalse(waiting.published)
        XCTAssertEqual(SuggestionRules.reviewNote(trusted: true), "As a trusted contributor, your suggestion joins the quilt at once.")
        XCTAssertTrue(SuggestionRules.reviewNote(trusted: false).hasPrefix("An instance admin reviews suggestions."))
    }

    func testACollisionNamesThePatchItHit() {
        let error = APIError.from(status: 409, data: Data(#"{"error":"a patch with a similar name already exists","existing_slug":"common-thread"}"#.utf8))
        XCTAssertEqual(error.existingSlug, "common-thread")
        XCTAssertEqual(error.httpStatus, 409)
        XCTAssertEqual(SuggestionRules.sentence(error), "A patch with a similar name already exists.")
        let other = APIError.from(status: 400, data: Data(#"{"error":"could not read a calendar at that address"}"#.utf8))
        XCTAssertNil(other.existingSlug)
        XCTAssertEqual(SuggestionRules.sentence(other), "Could not read a calendar at that address")
    }

    // MARK: - Claiming

    func testWhatAPatchTakesIsReadFromClaimsMine() throws {
        let state = try decode(ClaimState.self, #"{"claim":null,"methods":{"dns":true,"meta_tag":true,"did":true,"email":false,"admin":true},"verification_domain":"choir.example.org","node_status":"unclaimed"}"#)
        XCTAssertNil(state.claim)
        XCTAssertTrue(state.offers(.metaTag), "the snake-case decoder rewrites meta_tag; it is still read")
        XCTAssertTrue(state.offers(.dns))
        XCTAssertFalse(state.offers(.email))
        XCTAssertEqual(state.domain, "choir.example.org")
        XCTAssertEqual(ClaimMethod.unavailableReason(.email, domain: "choir.example.org"), "This quilt can't send email")
        XCTAssertEqual(ClaimMethod.unavailableReason(.dns, domain: ""), "Requires a verified domain on this listing")
        XCTAssertEqual(ClaimMethod.unavailableReason(.dns, domain: "x.org"), "Unavailable on this listing")
    }

    func testAnOpenClaimCarriesItsInstructions() throws {
        let state = try decode(ClaimState.self, #"{"claim":{"id":"c1","method":"dns","evidence":"","status":"pending","email":"","created_at":"2026-10-01T10:00:00Z","instructions":"Add a TXT record on x.org with the value: patchwork-verify=abc","record_value":"patchwork-verify=abc"},"methods":{"admin":true},"verification_domain":"x.org","node_status":"unclaimed"}"#)
        let claim = try XCTUnwrap(state.claim)
        XCTAssertEqual(claim.kind, .dns)
        XCTAssertTrue(claim.kind?.verifiable == true)
        XCTAssertFalse(claim.approved)
        XCTAssertEqual(claim.recordValue, "patchwork-verify=abc")
        let approved = try decode(PatchClaimDetail.self, #"{"id":"c2","method":"email","status":"approved","setup_expires_at":"2026-10-27T10:00:00Z"}"#)
        XCTAssertTrue(approved.approved)
        XCTAssertFalse(ClaimMethod.email.verifiable, "an email claim is completed by its link, not by Verify Now")
    }

    func testAClaimSendsOnlyWhatItsMethodAsksFor() throws {
        let email = try json(ClaimRequestBody(method: .email, evidence: "ignored", email: " me@choir.example.org "))
        XCTAssertEqual(email["method"] as? String, "email")
        XCTAssertEqual(email["email"] as? String, "me@choir.example.org")
        XCTAssertNil(email["evidence"])
        let admin = try json(ClaimRequestBody(method: .admin, evidence: " I run it. ", email: "x@y"))
        XCTAssertEqual(admin["evidence"] as? String, "I run it.")
        XCTAssertNil(admin["email"])
        XCTAssertEqual(try json(ClaimRequestBody(method: .metaTag, evidence: "", email: ""))["method"] as? String, "meta_tag")
        XCTAssertFalse(ClaimRules.canSubmit(nil, email: ""))
        XCTAssertFalse(ClaimRules.canSubmit(.email, email: "me"))
        XCTAssertTrue(ClaimRules.canSubmit(.email, email: "me@choir.example.org"))
        XCTAssertTrue(ClaimRules.canSubmit(.dns, email: ""))
    }

    func testVerifyingAnswersEitherWay() throws {
        let still = try decode(ClaimVerification.self, #"{"status":"pending","verified":false,"error":"TXT record not found — it may take a few minutes to propagate"}"#)
        XCTAssertEqual(still.verified, false)
        XCTAssertEqual(still.error, "TXT record not found — it may take a few minutes to propagate")
        let done = try decode(ClaimVerification.self, #"{"status":"approved","verified":true,"slug":"x","setup_required":true}"#)
        XCTAssertEqual(done.setupRequired, true)
    }

    func testASetupRefusalIsSaidInTheRightWords() {
        let expired = APIError.from(status: 410, data: Data(#"{"error":"this claim's setup window has expired. The patch is claimable again"}"#.utf8))
        XCTAssertEqual(PatchSetupRules.sentence(expired), "This claim's setup window has expired. The patch is claimable again")
        XCTAssertTrue(PatchSetupRules.isFinal(expired))
        let taken = APIError.from(status: 409, data: Data(#"{"error":"this patch is no longer unclaimed"}"#.utf8))
        XCTAssertEqual(PatchSetupRules.sentence(taken), "This patch is no longer claimable.", "the web's own words for somebody else's setup")
        XCTAssertTrue(PatchSetupRules.isFinal(taken))
        let other = APIError.from(status: 400, data: Data(#"{"error":"unknown governance template"}"#.utf8))
        XCTAssertEqual(PatchSetupRules.sentence(other), "Unknown governance template")
        XCTAssertFalse(PatchSetupRules.isFinal(other))
    }

    // MARK: - A first account

    func testTheWelcomeIsForAReaderWhoBelongsNowhereYet() throws {
        XCTAssertTrue(WelcomeRule.shouldWelcome(memberships: [], dismissed: false))
        XCTAssertFalse(WelcomeRule.shouldWelcome(memberships: [], dismissed: true), "skipping genuinely exits")
        let row = try decode(Membership.self, #"{"id":"m","node_slug":"a","status":"active","role":"follower"}"#)
        XCTAssertFalse(WelcomeRule.shouldWelcome(memberships: [row], dismissed: false))
        let quilt = Quilt(url: URL(string: "https://quilt.example.org")!, name: "Q")
        XCTAssertEqual(WelcomeRule.key(quilt: quilt, userID: "u1"), "welcome-dismissed:https://quilt.example.org:u1",
                       "kept per quilt and per account, as the web keys it per user")
    }

    func testTheLabelPanelSaysWhoAndWhat() throws {
        let one = try decode(QuiltLabel.self, ###"{"published":true,"stewards":[{"username":"sam","display_name":"Sample Steward"}],"total_monthly_minor":1350,"currency":"USD","prose":"## Why\n\nThis quilt is fictional.\n\nMore."}"###)
        XCTAssertEqual(WelcomeRule.stewardLine(one), "This quilt is stewarded by Sample Steward and costs about $13.50/month to run.")
        XCTAssertEqual(WelcomeRule.proseLine(one.prose), "This quilt is fictional.", "the first line that is not a heading")
        let many = try decode(QuiltLabel.self, #"{"published":true,"stewards":[{"username":"a"},{"username":"b","display_name":"Bee"},{"username":"c"},{"username":"d"}]}"#)
        XCTAssertEqual(WelcomeRule.stewardLine(many), "This quilt is stewarded by @a, Bee, @c +1.")
        let three = try decode(QuiltLabel.self, #"{"stewards":[{"username":"a"},{"username":"b"},{"username":"c"}]}"#)
        XCTAssertEqual(WelcomeRule.stewardLine(three), "This quilt is stewarded by @a, @b, @c.")
        XCTAssertEqual(WelcomeRule.proseLine(String(repeating: "a", count: 200))?.count, 141, "cut at 140, with an ellipsis")
        XCTAssertEqual(WelcomeRule.expectations.count, 4)
    }

    func testTheAgreementLineNamesBothDocuments() {
        XCTAssertEqual(String(AgreementLine.sentence.characters),
                       "By creating an account you agree to the User Agreement and Privacy Policy.")
        XCTAssertEqual(AgreementLine.doc(for: URL(string: "patchwork-legal:terms")!), .terms)
        XCTAssertEqual(AgreementLine.doc(for: URL(string: "patchwork-legal:privacy")!), .privacy)
        XCTAssertNil(AgreementLine.doc(for: URL(string: "https://quilt.example.org/terms")!))
    }
}
