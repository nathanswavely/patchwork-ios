// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// The quilt's information stack, the reader's Display settings, and the
/// muted ramp they reach. Muted values are checked against runs of the web's
/// own `mutedColors.js` under node, the same way the hash and the drafted
/// faces are: the two clients must draw one quilt.
final class QuiltInfoTests: XCTestCase {
    private func decode<T: Decodable>(_ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Decoding

    func testInstanceCarriesStatsAndSubmissions() throws {
        let instance: Instance = try decode(#"""
        {"name":"Lancaster Patchwork","description":"A living culture map.","domain":"example.org",
         "geography":{"latitude":40.03,"longitude":-76.3,"radius":25,"timezone":"America/New_York"},
         "stats":{"node_count":59,"event_count":458,"member_count":11},
         "modules":{"governance":true,"map":true},"version":"v0.30.0",
         "submissions_enabled":true,"email_enabled":true,"neighbor_quilts":[]}
        """#)
        XCTAssertEqual(instance.stats?.nodeCount, 59)
        XCTAssertEqual(instance.version, "v0.30.0")
        XCTAssertEqual(instance.submissionsEnabled, true)
    }

    /// A quilt that says nothing about submissions is not a quilt that says
    /// yes: the exit stays hidden rather than guessing.
    func testInstanceWithoutSubmissionsFlagDecodes() throws {
        let instance: Instance = try decode(#"{"name":"Quiet","description":"","geography":{}}"#)
        XCTAssertNil(instance.submissionsEnabled)
        XCTAssertNil(instance.stats)
    }

    func testLabelDecodesStewardsCostsAndCapabilities() throws {
        let label: QuiltLabel = try decode(###"""
        {"published":true,"currency":"USD","total_monthly_minor":1419,"stale":false,
         "stated_on":"2026-07-21","version":"v0.30.0","federation":false,"multi_quilt":false,
         "support_url":"https://buymeacoffee.com/example","feedback_url":"https://example.org/issues",
         "seamripped_from_name":"","seamripped_from_url":"",
         "prose":"## Why\n\nBecause somebody had to.",
         "stewards":[{"username":"someone","display_name":"Someone","avatar_url":"","blurb":""}],
         "cost_items":[{"id":"019f","service":"Hetzner Cloud","purpose":"the server","why":"EU-based",
                        "amount_minor":1349,"period":"monthly","stated_on":"2026-07-21","source":"manual"},
                       {"service":"A domain","amount_minor":1800,"period":"yearly"}]}
        """###)
        XCTAssertEqual(label.published, true)
        XCTAssertEqual(label.stewards?.count, 1)
        XCTAssertEqual(label.stewards?.first?.title, "Someone")
        XCTAssertEqual(label.costItems?.count, 2)
        XCTAssertEqual(label.costItems?.first?.service, "Hetzner Cloud")
        XCTAssertEqual(label.costItems?.first?.periodWord, "/month")
        XCTAssertEqual(label.costItems?.last?.periodWord, "/year")
        XCTAssertNil(label.costItems?.last?.purpose)
        XCTAssertEqual(label.multiQuilt, false)
        XCTAssertEqual(label.seamrippedFromName, "")
    }

    /// An unpublished Label answers with little more than the word, and the
    /// page has to survive that rather than insisting on a roster.
    func testUnpublishedLabelDecodes() throws {
        let label: QuiltLabel = try decode(#"{"published":false}"#)
        XCTAssertEqual(label.published, false)
        XCTAssertNil(label.stewards)
        XCTAssertNil(label.costItems)
    }

    func testStewardWithoutDisplayNameFallsBackToHandle() throws {
        let label: QuiltLabel = try decode(#"{"stewards":[{"username":"nobody","display_name":""}]}"#)
        XCTAssertEqual(label.stewards?.first?.title, "@nobody")
    }

    func testMoneyFormatsMinorUnits() {
        XCTAssertTrue(QuiltLabel.money(1349, "USD").contains("13.49"))
        XCTAssertTrue(QuiltLabel.money(nil, nil).contains("0.00"))
    }

    func testLiningDecodes() throws {
        let lining: Lining = try decode(###"{"title":"Community Standards","body":"## Keep each other safe\n\nText.","version":1}"###)
        XCTAssertEqual(lining.title, "Community Standards")
        XCTAssertTrue(lining.body?.hasPrefix("## Keep") == true)
    }

    /// "Last updated" is only true of a document the stewards replaced; the
    /// shipped default's timestamp is the software's, not this quilt's.
    func testLegalDocumentDatesOnlyWhenCustomized() throws {
        let customized: LegalDocument = try decode(###"{"doc":"privacy","title":"Privacy Policy","markdown":"## Short\n\nText.","customized":true,"updated_at":"2026-08-15T20:05:14.692Z"}"###)
        XCTAssertEqual(customized.updatedDay, "2026-08-15")
        let shipped: LegalDocument = try decode(###"{"doc":"terms","title":"User Agreement","markdown":"Text.","customized":false,"updated_at":"2026-08-15T20:05:14.692Z"}"###)
        XCTAssertNil(shipped.updatedDay)
    }

    // MARK: - Markdown

    func testMarkdownSplitsIntoBlocks() {
        let blocks = Markdown.blocks("""
        ## The short version

        Nobody runs this for profit.
        There are no ads here.

        - No ads.
        - No trackers.

        1. First
        2. Second

        > Quoted.

        ---

        # Bigger heading
        """)
        XCTAssertEqual(blocks, [
            .heading(level: 2, text: "The short version"),
            .paragraph("Nobody runs this for profit. There are no ads here."),
            .bullets(["No ads.", "No trackers."]),
            .numbers(["First", "Second"]),
            .quote("Quoted."),
            .rule,
            .heading(level: 1, text: "Bigger heading"),
        ])
    }

    /// A list that follows a paragraph with no blank line between them is
    /// still a list, and a heading closes whatever was open.
    func testMarkdownBlocksCloseOnAChangeOfKind() {
        XCTAssertEqual(Markdown.blocks("Intro:\n- one\n- two\n## Next\nAfter."), [
            .paragraph("Intro:"),
            .bullets(["one", "two"]),
            .heading(level: 2, text: "Next"),
            .paragraph("After."),
        ])
        XCTAssertEqual(Markdown.blocks(""), [])
        XCTAssertEqual(Markdown.blocks("#hashtag not a heading"), [.paragraph("#hashtag not a heading")])
    }

    func testMarkdownInlineKeepsLinksAndEmphasis() {
        let run = Markdown.inline("See the [Label](/label) and **this**.", base: URL(string: "https://example.org"))
        XCTAssertTrue(String(run.characters).contains("See the Label and this."))
        let link = run.runs.compactMap(\.link).first
        XCTAssertEqual(link?.absoluteString, "https://example.org/label")
    }

    // MARK: - Muted colours (docs/adr/112)

    /// Values from a node run of the web's own `mutedColors.js`.
    func testMutedRampMatchesTheWeb() {
        XCTAssertEqual(QuiltTheme.mutedSlots(primary: "#C02624", count: 6),
                       ["#bd776e", "#ffbfb6", "#4c100e", "#904e47", "#e1988f", "#6a2c27"])
        XCTAssertEqual(QuiltTheme.mutedSlots(primary: "#039BE6", count: 6),
                       ["#5793be", "#a4d8ff", "#002c46", "#2c6992", "#79b6e2", "#00476d"])
        XCTAssertEqual(QuiltTheme.mutedSlots(primary: "#B23282", count: 3),
                       ["#b47597", "#fdb9dd", "#461132"])
        XCTAssertEqual(QuiltTheme.mutedColor("#DA0956"), "#bc757f")
        // A short hex is expanded the same way a bundle's is.
        XCTAssertEqual(QuiltTheme.mutedSlots(primary: "#abc", count: 1), ["#7e8e9e"])
    }

    /// Stage Black has no chroma to cap, so it stays a grey ramp: that patch
    /// genuinely chose to be achromatic and muted may not invent a hue for it.
    func testMutedLeavesAnAchromaticChoiceAchromatic() {
        XCTAssertEqual(QuiltTheme.mutedSlots(primary: "#0A0A0A", count: 3), ["#8c8c8c", "#d1d1d1", "#292929"])
    }

    /// The cap is a ceiling, never a target. Measured back off an 8-bit hex
    /// the numbers move by a rounding step, so the tolerance is that step and
    /// not a licence: Dove keeps its own small chroma rather than being
    /// pushed up to the cap, and Scarlet comes down to it.
    func testMutedCapsChromaAndNeverRaisesIt() {
        let rounding = 2e-3
        let quiet = QuiltTheme.oklch("#C9C2B2")!
        XCTAssertLessThan(quiet.C, QuiltTheme.chromaCap)
        let muted = QuiltTheme.oklch(QuiltTheme.mutedSlot("#C9C2B2", 0))!
        XCTAssertLessThanOrEqual(muted.C, quiet.C + rounding, "a colour under the cap is never pushed up to it")
        let loud = QuiltTheme.oklch("#EC341C")!
        XCTAssertGreaterThan(loud.C, QuiltTheme.chromaCap)
        let quieted = QuiltTheme.oklch(QuiltTheme.mutedSlot("#EC341C", 0))!
        XCTAssertLessThanOrEqual(quieted.C, QuiltTheme.chromaCap + rounding)
        XCTAssertEqual(quieted.h, loud.h, accuracy: 0.02, "hue is carried through untouched")
    }

    func testMutedSlotCountIsClampedAndUnparseableHexIsLeftAlone() {
        XCTAssertEqual(QuiltTheme.mutedSlots(primary: "#039BE6", count: 9).count, 6)
        XCTAssertEqual(QuiltTheme.mutedSlots(primary: "#039BE6", count: 0), ["#5793be"])
        XCTAssertEqual(QuiltTheme.mutedSlot("nope", 0), "nope")
    }

    func testOklchMatchesTheWeb() {
        let c = QuiltTheme.oklch("#C02624")!
        XCTAssertEqual(c.L, 0.525748, accuracy: 1e-6)
        XCTAssertEqual(c.C, 0.189930, accuracy: 1e-6)
        XCTAssertEqual(c.h, 0.476400, accuracy: 1e-6)
    }

    /// Muted carries the *count* of slots over rather than filling it out to
    /// six: it may take colour away and may not add structure, so a patch
    /// whose bundle is one fabric keeps drawing one flat fabric.
    func testMutedPaletteKeepsTheSlotCountAndTheKey() {
        let restore = QuiltTheme.colorMode
        defer { QuiltTheme.colorMode = restore }
        let appearance = Appearance(bundle: ["#2E7D5B", "#204B4B", "#D9D6AF", "#D89E13"])
        QuiltTheme.colorMode = .standard
        let plain = QuiltTheme.palette(id: "demo-patch", appearance: appearance)
        XCTAssertEqual(plain.slots.count, 4)
        XCTAssertEqual(plain.primary, "#2E7D5B")
        QuiltTheme.colorMode = .muted
        let muted = QuiltTheme.palette(id: "demo-patch", appearance: appearance)
        XCTAssertEqual(muted.slots.count, 4, "the slot count is preserved, not filled out")
        XCTAssertEqual(muted.slots, QuiltTheme.mutedSlots(primary: "#2E7D5B", count: 4))
        XCTAssertEqual(Set(muted.slots).count, 4, "no two slots share a lightness, so a drafted block cannot flatten")
        // A pinned palette keeps its key so nothing downstream loses track of
        // which palette this is; only its colours change.
        let pinned = QuiltTheme.palette(id: "demo-patch", appearance: Appearance(palette: "anthem"))
        XCTAssertEqual(pinned.key, "anthem")
        XCTAssertEqual(pinned.primary, QuiltTheme.mutedSlot("#C02624", 0))
        XCTAssertEqual(QuiltTheme.ghost(0).primary, QuiltTheme.mutedSlot(QuiltTheme.palettes[abs(3) % 26].primary, 0))
    }

    // MARK: - Display settings

    func testDisplayChoicesRoundTripAndFallBack() {
        XCTAssertEqual(ColorMode(rawValue: "default"), .standard)
        XCTAssertEqual(ColorMode(rawValue: "muted"), .muted)
        XCTAssertNil(ColorMode(rawValue: "sepia"))
        XCTAssertNil(ThemeChoice.system.scheme)
        XCTAssertEqual(ThemeChoice.dark.scheme, .dark)
        XCTAssertEqual(ThemeChoice.allCases.map(\.title), ["System", "Light", "Dark"])
    }

    /// The preview fixtures back the UI test's walk through the stack.
    func testPreviewFixturesServeTheInfoStack() throws {
        let label: QuiltLabel = try PreviewData.response("label")
        XCTAssertEqual(label.published, true)
        XCTAssertEqual(label.stale, true)
        let lining: Lining = try PreviewData.response("instance/lining")
        XCTAssertEqual(lining.title, "Community Standards")
        let privacy: LegalDocument = try PreviewData.response("legal/privacy")
        XCTAssertEqual(privacy.updatedDay, "2026-01-01")
        let terms: LegalDocument = try PreviewData.response("legal/terms")
        XCTAssertNil(terms.updatedDay)
        let instance: Instance = try PreviewData.response("instance")
        XCTAssertEqual(instance.submissionsEnabled, true)
        XCTAssertEqual(instance.stats?.nodeCount, 12)
    }
}
