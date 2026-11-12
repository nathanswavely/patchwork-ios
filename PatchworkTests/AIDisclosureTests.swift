// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import Patchwork

/// Whether AI made a post (web ADR 2026-10-20), as values: what is read, what
/// each form sends on each of the quilt's three settings, and what each form
/// refuses before asking — on `required` only, and the image only while
/// there is an image.
final class AIDisclosureTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
    /// As `PatchworkAPI` sends it.
    private func sent(_ body: some Encodable) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(body)) as? [String: Any])
    }
    private let missing = AIDisclosure.missingLine

    // MARK: Reading

    func testTheSwitchReadsAbsentAndUnknownAsOff() {
        XCTAssertEqual(AIDisclosure(nil), .off, "a quilt from before the question asks nothing")
        XCTAssertEqual(AIDisclosure("sometimes"), .off)
        XCTAssertEqual(AIDisclosure("optional"), .optional)
        XCTAssertEqual(AIDisclosure("required"), .required)
        XCTAssertFalse(AIDisclosure.off.asks)
        XCTAssertTrue(AIDisclosure.optional.asks)
    }

    func testTheNewFieldsDecode() throws {
        let instance = try decoder().decode(Instance.self, from: Data(#"{"name":"Q","description":"","geography":{"timezone":"UTC"},"ai_disclosure":"required"}"#.utf8))
        XCTAssertEqual(AIDisclosure(instance.aiDisclosure), .required)
        let event = try decoder().decode(PatchworkEvent.self, from: Data(#"{"id":"e","title":"T","starts_at":"2026-10-20T22:00:00Z","ai_use":"generated","image_ai":"assisted"}"#.utf8))
        XCTAssertEqual(event.aiUse, "generated")
        XCTAssertEqual(event.imageAi, "assisted")
        let patch = try decoder().decode(Patch.self, from: Data(#"{"id":"p","name":"P","slug":"p","ai_work":true,"ai_use":"none","image_ai":null}"#.utf8))
        XCTAssertEqual(patch.aiWork, true)
        XCTAssertEqual(patch.aiUse, "none")
        XCTAssertNil(patch.imageAi)
        let quiet = try decoder().decode(Patch.self, from: Data(#"{"id":"p","name":"P","slug":"p"}"#.utf8))
        XCTAssertNil(quiet.aiWork, "a quilt from before the declaration still reads")
        let proposal = try decoder().decode(Proposal.self, from: Data(#"{"id":"p","title":"T","status":"open","ai_use":"generated"}"#.utf8))
        XCTAssertEqual(proposal.aiUse, "generated")
        let page = try decoder().decode(NoticePage.self, from: Data(#"{"items":[{"id":"n","title":"T","ai_use":"generated"},{"id":"m","title":"U","ai_use":null}]}"#.utf8))
        XCTAssertEqual(page.items.map(\.aiUse), ["generated", nil])
        let me = try XCTUnwrap(decoder().decode(SignInResponse.self, from: Data(#"{"id":"u","username":"x","hide_ai_work":true}"#.utf8)).user)
        XCTAssertEqual(me.hideAiWork, true)
    }

    func testOnlyGeneratedIsShownAndStrayWordsAreUnanswered() {
        XCTAssertTrue(AIUse.generated("generated"))
        XCTAssertFalse(AIUse.generated("assisted"), "assisted is recorded, never shown")
        XCTAssertFalse(AIUse.generated(nil))
        XCTAssertEqual(AIUse(stored: "none"), AIUse.none)
        XCTAssertNil(AIUse(stored: ""))
        XCTAssertNil(AIUse(stored: "mostly"))
        XCTAssertEqual(AIUse.allCases.map(\.label), ["No AI", "AI helped (editing, cleanup, translation)", "AI made this"])
    }

    // MARK: Events

    private func eventDraft() -> EventDraft {
        var draft = EventDraft(start: Date(timeIntervalSince1970: 1_800_000_000))
        draft.title = "Toaster triage"
        return draft
    }

    func testAnEventSendsItsAnswersOnlyWhereTheQuiltAsks() throws {
        var draft = eventDraft()
        draft.aiUse = .generated
        draft.imageURL = "https://example.org/flyer.jpg"
        draft.imageAlt = "A flyer"
        draft.imageAI = AIUse.none
        let off = try sent(draft.body(nodeId: "n", direct: true, ai: .off))
        XCTAssertNil(off["ai_use"], "a quilt with the question off is sent nothing")
        XCTAssertNil(off["image_ai"])
        let asked = try sent(draft.body(nodeId: "n", direct: true, ai: .optional))
        XCTAssertEqual(asked["ai_use"] as? String, "generated")
        XCTAssertEqual(asked["image_ai"] as? String, "none")
        draft.imageURL = ""
        XCTAssertNil(try sent(draft.body(nodeId: "n", direct: true, ai: .optional))["image_ai"],
                     "no image, no answer about one")
        draft.aiUse = nil
        XCTAssertNil(try sent(draft.body(nodeId: "n", direct: true, ai: .optional))["ai_use"], "unanswered is left out, never null")
    }

    func testAnEventIsRefusedUnansweredOnlyWhereTheQuiltRequires() {
        var draft = eventDraft()
        XCTAssertNil(draft.problem(ai: .off))
        XCTAssertNil(draft.problem(ai: .optional), "optional blocks nothing")
        XCTAssertEqual(draft.problem(ai: .required), missing)
        XCTAssertNil(draft.problem(), "the button's own readiness never waits on it")
        draft.aiUse = AIUse.none
        XCTAssertNil(draft.problem(ai: .required))
        draft.imageURL = "https://example.org/flyer.jpg"
        draft.imageAlt = "A flyer"
        XCTAssertEqual(draft.problem(ai: .required), missing, "the image is asked about while there is one")
        XCTAssertEqual(draft.unansweredAI, "imageAI")
        draft.imageAI = .assisted
        XCTAssertNil(draft.problem(ai: .required))
        draft.title = ""
        XCTAssertEqual(draft.problem(ai: .required), "Title is required", "the form's own rules come first")
    }

    func testAnEventEditSendsAnAnswerOnlyWhereItChanged() throws {
        let event = try decoder().decode(PatchworkEvent.self, from: Data("""
        {"id":"e","title":"Toaster triage","starts_at":"2026-10-20T22:00:00Z","timezone":"America/New_York",\
        "image_url":"https://example.org/flyer.jpg","image_alt":"A flyer","ai_use":"none","image_ai":"generated"}
        """.utf8))
        let original = EventDraft(editing: event)
        XCTAssertEqual(original.aiUse, AIUse.none, "the edit is pre-filled")
        XCTAssertEqual(original.imageAI, .generated)
        var draft = original
        draft.title = "Toaster triage, again"
        let untouched = try sent(draft.changes(from: original, direct: true))
        XCTAssertNil(untouched["ai_use"], "an untouched answer is left alone")
        XCTAssertNil(untouched["image_ai"])
        draft.aiUse = .assisted
        XCTAssertEqual(try sent(draft.changes(from: original, direct: true))["ai_use"] as? String, "assisted")
        draft.imageURL = ""
        XCTAssertNil(try sent(draft.changes(from: original, direct: true))["image_ai"], "a cleared image takes its answer with it")
    }

    func testAnEventEditAsksAnOldRowOnARequiredQuilt() throws {
        let event = try decoder().decode(PatchworkEvent.self, from: Data(#"{"id":"e","title":"T","starts_at":"2026-10-20T22:00:00Z"}"#.utf8))
        let original = EventDraft(editing: event)
        var draft = original
        draft.title = "T2"
        let changes = draft.changes(from: original, direct: true)
        XCTAssertNil(draft.editProblem(changes: changes, ai: .optional))
        XCTAssertEqual(draft.editProblem(changes: changes, ai: .required), missing)
    }

    // MARK: Patches

    private var patchDraft: PatchDraft {
        var draft = PatchDraft(palette: "anthem", block: "ohioStar", rotation: 90)
        draft.name = "Gallery Row"
        return draft
    }

    func testCreatingAPatchSendsTheAnswerByTheSwitchAndTheDeclarationAlways() throws {
        var draft = patchDraft
        XCTAssertNil(try sent(draft.createBody(ai: .optional))["ai_use"])
        XCTAssertNil(try sent(draft.createBody(ai: .optional))["ai_work"], "an unanswered declaration is not stated")
        draft.aiUse = .generated
        draft.aiWork = false
        let off = try sent(draft.createBody(ai: .off))
        XCTAssertNil(off["ai_use"])
        XCTAssertEqual(off["ai_work"] as? Bool, false, "the declaration is not the quilt's switch to ask")
        XCTAssertEqual(try sent(draft.createBody(ai: .required))["ai_use"] as? String, "generated")
        XCTAssertEqual(try sent(draft.updateBody(ai: .optional))["ai_use"] as? String, "generated", "setup sends it as creation does")
    }

    func testAPatchIsRefusedUnansweredOnlyWhereTheQuiltRequires() {
        var draft = patchDraft
        XCTAssertNil(draft.problem(ai: .optional))
        XCTAssertEqual(draft.problem(ai: .required), missing)
        draft.aiUse = .assisted
        XCTAssertNil(draft.problem(ai: .required))
    }

    func testSetupSeedsTheDescriptionsAnswerAndNeverTheDeclaration() throws {
        let listing = try decoder().decode(Patch.self, from: Data(#"{"id":"p","name":"P","slug":"p","ai_use":"assisted","ai_work":true}"#.utf8))
        let draft = PatchDraft(setup: listing)
        XCTAssertEqual(draft.aiUse, .assisted)
        XCTAssertNil(draft.aiWork, "whoever claims it answers for its work")
    }

    func testAPatchEditSendsOnlyTheAnswersThatMoved() throws {
        let patch = try decoder().decode(Patch.self, from: Data("""
        {"id":"p","name":"P","slug":"p","description":"Old","image_url":"https://example.org/a.png","image_alt":"A",\
        "ai_use":"none","image_ai":"none","ai_work":null}
        """.utf8))
        let original = PatchDraft(editing: patch)
        var draft = original
        draft.website = "https://example.org"
        let untouched = try sent(draft.changes(from: original))
        XCTAssertNil(untouched["ai_use"])
        XCTAssertNil(untouched["image_ai"])
        XCTAssertFalse(untouched.keys.contains("ai_work"), "an unanswered declaration is not sent as null")
        draft.aiWork = true
        draft.imageAI = .generated
        let changed = try sent(draft.changes(from: original))
        XCTAssertEqual(changed["ai_work"] as? Bool, true)
        XCTAssertEqual(changed["image_ai"] as? String, "generated")
        XCTAssertEqual(try sent(PatchEditBody(aiWork: false)) as NSDictionary, ["ai_work": false] as NSDictionary,
                       "the workspace prompt sends the declaration alone")
    }

    func testAPatchEditOwesAnAnswerOnlyForWhatItChanges() throws {
        let patch = try decoder().decode(Patch.self, from: Data(#"{"id":"p","name":"P","slug":"p","description":"Old"}"#.utf8))
        let original = PatchDraft(editing: patch)
        var draft = original
        draft.website = "https://example.org"
        XCTAssertNil(draft.editProblem(from: original, ai: .required), "a new website owes nothing")
        draft.description = "New"
        XCTAssertNil(draft.editProblem(from: original, ai: .optional))
        XCTAssertEqual(draft.editProblem(from: original, ai: .required), missing)
        draft.aiUse = AIUse.none
        XCTAssertNil(draft.editProblem(from: original, ai: .required))
        draft.imageURL = "https://example.org/b.png"
        draft.imageAlt = "B"
        XCTAssertEqual(draft.editProblem(from: original, ai: .required), missing, "a new image owes its own answer")
        XCTAssertEqual(draft.owedAI(from: original).first { $0.answer == nil }?.id, "imageAI")
    }

    func testASuggestionAnswersForItsWordsAndNeverDeclares() throws {
        var draft = SuggestionDraft()
        draft.name = "Gallery Row"
        XCTAssertEqual(draft.problem(ai: .required), missing)
        XCTAssertNil(draft.problem(ai: .optional))
        draft.aiUse = .assisted
        XCTAssertEqual(try sent(draft.body(ai: .optional))["ai_use"] as? String, "assisted")
        XCTAssertNil(try sent(draft.body(ai: .off))["ai_use"])
        XCTAssertNil(try sent(draft.body(ai: .optional))["ai_work"])
    }

    func testThePromptAsksOnlyTheAdminOfAClaimedPatchThatHasNotAnswered() {
        XCTAssertTrue(AIWork.prompts(runs: true, unclaimed: false, aiWork: nil))
        XCTAssertFalse(AIWork.prompts(runs: true, unclaimed: false, aiWork: false), "No is an answer, and the prompt goes")
        XCTAssertFalse(AIWork.prompts(runs: true, unclaimed: true, aiWork: nil), "an unclaimed listing carries no declaration")
        XCTAssertFalse(AIWork.prompts(runs: false, unclaimed: false, aiWork: nil))
    }

    // MARK: Proposals

    func testEveryProposalPathAsksAndSendsTheAnswer() throws {
        let rules = GovernanceRules(decisionMethod: "majority")
        var draft = ProposalDraft(title: "Open on Tuesdays")
        XCTAssertEqual(ProposalPosting.problem(draft, ai: .required), missing)
        XCTAssertNil(ProposalPosting.problem(draft), "the button's own readiness never waits on it")
        XCTAssertNil(ProposalPosting.problem(draft, ai: .optional))
        draft.aiUse = .generated
        XCTAssertNil(ProposalPosting.problem(draft, ai: .required))
        XCTAssertEqual(try sent(ProposalBody(draft, rules: rules, isPatchAdmin: false, ai: .optional))["ai_use"] as? String, "generated")
        XCTAssertNil(try sent(ProposalBody(draft, rules: rules, isPatchAdmin: false, ai: .off))["ai_use"])

        let amendment = { (ai: AIDisclosure, answer: AIUse?) in
            AmendmentBody(title: "T", why: "", targetDoc: "d.md", documentTitle: "D", proposed: "x", rules: rules,
                          isPatchAdmin: false, putToVote: false, durationHours: 72, aiUse: answer, ai: ai)
        }
        XCTAssertEqual(try sent(amendment(.optional, .assisted))["ai_use"] as? String, "assisted")
        XCTAssertNil(try sent(amendment(.off, .assisted))["ai_use"])
        XCTAssertNil(try sent(amendment(.optional, nil))["ai_use"])
    }

    // MARK: Notices

    func testANoticeIsAskedOnCreateAndOnEditAndSendsOnlyAChange() throws {
        var draft = NoticeDraft(title: "Kiln")
        XCTAssertEqual(Noticeboard.problem(draft, ai: .required), missing)
        XCTAssertNil(Noticeboard.problem(draft, ai: .optional))
        draft.aiUse = .generated
        XCTAssertEqual(try sent(NoticeBody(draft, ai: .optional))["ai_use"] as? String, "generated")
        XCTAssertNil(try sent(NoticeBody(draft, ai: .off))["ai_use"])

        let notice = Notice(id: "n", title: "Kiln")
        var stored = notice
        stored.aiUse = "none"
        let edit = NoticeDraft(editing: stored)
        XCTAssertEqual(edit.aiUse, AIUse.none, "the edit is pre-filled")
        XCTAssertNil(try sent(NoticeEditBody(edit, was: AIUse(stored: stored.aiUse)))["ai_use"], "an untouched answer is left alone")
        var changed = edit
        changed.aiUse = .assisted
        XCTAssertEqual(try sent(NoticeEditBody(changed, was: AIUse.none))["ai_use"] as? String, "assisted")
        XCTAssertEqual(Noticeboard.problem(NoticeDraft(editing: notice), ai: .required), missing,
                       "a notice from before the question is asked when it is rewritten")
    }

    // MARK: Reports

    func testUnlabelledAITravelsAsACodeAndReadsBackAsWords() {
        XCTAssertEqual(Noticeboard.reportReasons.map(\.value).suffix(2), ["unlabelled_ai", "Something else"],
                       "just before Something else, as the web orders it")
        XCTAssertEqual(Noticeboard.reasonLabel("unlabelled_ai"), "AI-made content without a label")
        XCTAssertEqual(Noticeboard.reasonLabel("Spam or scam"), "Spam or scam", "every other reason is its own words")
        XCTAssertTrue(Noticeboard.reportReasons(for: .notice).contains { $0.value == "unlabelled_ai" })
        XCTAssertFalse(Noticeboard.reportReasons(for: .reply).contains { $0.value == "unlabelled_ai" },
                       "a reply is asked nothing, so carries no answer to be wrong")
        XCTAssertFalse(Noticeboard.reportReasons(for: .user).contains { $0.value == "unlabelled_ai" })
    }

    // MARK: The reader's switch

    func testTheReadersSwitchSendsOnlyItself() throws {
        XCTAssertEqual(try sent(AccountChanges(hideAiWork: true)) as NSDictionary, ["hide_ai_work": true] as NSDictionary)
    }
}
