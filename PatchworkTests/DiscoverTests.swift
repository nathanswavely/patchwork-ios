// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// Discovery mode's answer and the exits around it: which half of the quilt a
/// patch lands in, whose number a tag chip prints, and what the two website
/// links carry with them.
final class DiscoverTests: XCTestCase {
    private func patch(_ id: String, name: String? = nil, tags: [String] = [], movedTo: String? = nil) throws -> Patch {
        let moved = movedTo.map { ",\"moved_to\":\"\($0)\"" } ?? ""
        let json = """
        {"id":"\(id)","name":"\(name ?? id)","slug":"\(id)",\
        "tags":[\(tags.map { "\"\($0)\"" }.joined(separator: ","))]\(moved)}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Patch.self, from: Data(json.utf8))
    }

    private func order(_ patches: [Patch]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: patches.enumerated().map { ($1.id, $0) })
    }

    // MARK: - The answer's two halves

    /// What was picked leads, and what was not is kept — not hidden, not
    /// mixed in. The web shows the rest behind one disclosure and so does
    /// this; a shortlist that quietly dropped four fifths of the quilt would
    /// be a verdict rather than an answer.
    func testPickedTagsSplitTheQuiltInTwo() throws {
        let patches = [
            try patch("a", tags: ["music"]),
            try patch("b", tags: ["craft"]),
            try patch("c", tags: ["music", "craft"]),
            try patch("d", tags: []),
        ]
        let split = DiscoverAnswer.split(patches, picked: ["music"], soonest: [:], order: order(patches))
        XCTAssertEqual(split.matching.map(\.id), ["a", "c"])
        XCTAssertEqual(split.rest.map(\.id), ["b", "d"])
        // Nothing falls out of the quilt between the two halves.
        XCTAssertEqual(split.matching.count + split.rest.count, patches.count)
    }

    /// "Show me everything instead" is one list, not a list and a remainder.
    func testPickingNothingAsksForTheWholeQuiltWithNoRest() throws {
        let patches = [try patch("a", tags: ["music"]), try patch("b", tags: ["craft"])]
        let split = DiscoverAnswer.split(patches, picked: [], soonest: [:], order: order(patches))
        XCTAssertEqual(split.matching.count, 2)
        XCTAssertTrue(split.rest.isEmpty)
    }

    /// Ordered by what is actually happening: soonest event first, then the
    /// quilt's own order. A patch with nothing coming up is last, never
    /// ranked by a count of nobody.
    func testSoonestEventLeadsAndQuiltOrderBreaksTies() throws {
        let patches = [
            try patch("quiet", tags: ["music"]),
            try patch("later", tags: ["music"]),
            try patch("tonight", tags: ["music"]),
            try patch("alsoQuiet", tags: ["music"]),
        ]
        let soonest: [String: Date] = [
            "later": Date(timeIntervalSince1970: 2_000_000),
            "tonight": Date(timeIntervalSince1970: 1_000_000),
        ]
        let split = DiscoverAnswer.split(patches, picked: ["music"], soonest: soonest, order: order(patches))
        XCTAssertEqual(split.matching.map(\.id), ["tonight", "later", "quiet", "alsoQuiet"])
    }

    /// The rest of the quilt is ordered by the same rule as the answer above
    /// it — it is the rest of one list, not a second kind of list.
    func testTheRestIsOrderedTheSameWay() throws {
        let patches = [
            try patch("quiet", tags: ["craft"]),
            try patch("soon", tags: ["craft"]),
            try patch("picked", tags: ["music"]),
        ]
        let split = DiscoverAnswer.split(
            patches,
            picked: ["music"],
            soonest: ["soon": Date(timeIntervalSince1970: 1_000)],
            order: order(patches)
        )
        XCTAssertEqual(split.rest.map(\.id), ["soon", "quiet"])
    }

    func testAPatchThatHasMovedKeepsItsForwardingAddress() throws {
        let moved = try patch("gone", tags: ["music"], movedTo: "https://elsewhere.example/patches/gone")
        XCTAssertEqual(moved.movedTo, "https://elsewhere.example/patches/gone")
        XCTAssertNil(try patch("here", tags: ["music"]).movedTo)
    }

    // MARK: - Whose count a chip prints

    private func terms(_ pairs: [(String, Int?)]) throws -> [TagTerm] {
        let json = pairs.map { name, count in
            count.map { "{\"name\":\"\(name)\",\"node_count\":\($0)}" } ?? "{\"name\":\"\(name)\"}"
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([TagTerm].self, from: Data("[\(json.joined(separator: ","))]".utf8))
    }

    /// `node_count` is the quilt's own public answer to "how many patches
    /// wear this", over the whole quilt. The tree this client holds is an
    /// approximation of that, so where the server has spoken it wins.
    func testServerCountsBeatLocallyDerivedOnes() throws {
        let patches = [try patch("a", tags: ["craft"]), try patch("b", tags: ["music"])]
        let ranked = QuiltSession.rank(patches: patches, terms: try terms([("craft", 9), ("music", 2)]))
        XCTAssertEqual(ranked.map(\.tag), ["craft", "music"])
        XCTAssertEqual(ranked.first?.count, 9, "the quilt's number, not this client's tally of one")
    }

    /// A quilt that will not serve its vocabulary still gets a shortlist —
    /// counted off the patches in hand rather than left blank.
    func testDerivedCountsAreTheFallbackWhenTheEndpointFailed() throws {
        let patches = [
            try patch("a", tags: ["craft", "music"]),
            try patch("b", tags: ["craft"]),
            try patch("c", tags: ["craft"]),
        ]
        let ranked = QuiltSession.rank(patches: patches, terms: [])
        XCTAssertEqual(ranked.map(\.tag), ["craft", "music"])
        XCTAssertEqual(ranked.map(\.count), [3, 1])
    }

    /// A vocabulary that answers for some terms and not others is mixed one
    /// term at a time, never all-or-nothing.
    func testATermWithNoCountFallsBackOnItsOwn() throws {
        let patches = [try patch("a", tags: ["craft", "music"]), try patch("b", tags: ["music"])]
        let ranked = QuiltSession.rank(patches: patches, terms: try terms([("craft", 5), ("music", nil)]))
        XCTAssertEqual(ranked.map(\.tag), ["craft", "music"])
        XCTAssertEqual(ranked.map(\.count), [5, 2])
    }

    /// Ties read A to Z, as they do on the web.
    func testTiesReadAToZ() throws {
        let patches = [try patch("a", tags: ["zither", "apple", "Mandolin"])]
        let ranked = QuiltSession.rank(patches: patches, terms: [])
        XCTAssertEqual(ranked.map(\.tag), ["apple", "Mandolin", "zither"])
    }

    /// A curated term nothing wears is not a chip: here the ranking is also
    /// the filter sheet's vocabulary, and a chip that can only empty the
    /// quilt is worse than an absent one.
    func testATermNobodyWearsIsNotOffered() throws {
        let patches = [try patch("a", tags: ["craft"])]
        let ranked = QuiltSession.rank(patches: patches, terms: try terms([("craft", 1), ("archive", 0)]))
        XCTAssertEqual(ranked.map(\.tag), ["craft"])
    }

    // MARK: - The exits

    private var api: PatchworkAPI { PatchworkAPI(base: URL(string: "https://quilt.example.org")!) }

    /// The suggestion link carries what the reader typed, so the form they
    /// land on is already about the thing they were looking for.
    func testSuggestLinkCarriesTheTypedName() {
        let url = api.suggestURL(name: "Bike Kitchen")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host(), "quilt.example.org")
        XCTAssertEqual(url.path(), "/submit")
        XCTAssertEqual(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            [URLQueryItem(name: "name", value: "Bike Kitchen")]
        )
    }

    func testSuggestLinkTrimsAndSurvivesAnEmptyName() {
        XCTAssertEqual(api.suggestURL(name: "  Bike Kitchen  ").query(), "name=Bike%20Kitchen")
        XCTAssertEqual(api.suggestURL(name: "   ").absoluteString, "https://quilt.example.org/submit")
    }

    /// Following is signposted, not stubbed: the sentence that says where it
    /// happens is the link, and it lands back on the patch being read.
    func testLoginLinkReturnsToThePatchBeingRead() {
        let url = api.loginURL(returningTo: "/patches/common-thread")
        XCTAssertEqual(url.path(), "/login")
        XCTAssertEqual(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            [URLQueryItem(name: "redirect", value: "/patches/common-thread")]
        )
        // Discover's footer names no one patch, so it carries no redirect.
        XCTAssertEqual(api.loginURL().absoluteString, "https://quilt.example.org/login")
    }

    // MARK: - Orientation

    /// Offered once per quilt and never again, and a second quilt is a second
    /// place to be greeted by.
    func testTheOrientationCardIsShownOncePerQuilt() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "introTests-\(UUID().uuidString)"))
        let quilt = Quilt(url: URL(string: "https://quilt.example.org")!, name: "Sample quilt")
        let neighbor = Quilt(url: URL(string: "https://neighbor.example.org")!, name: "Neighbor quilt")
        XCTAssertFalse(IntroState.seen(quilt, defaults: defaults))
        IntroState.markSeen(quilt, defaults: defaults)
        XCTAssertTrue(IntroState.seen(quilt, defaults: defaults))
        XCTAssertFalse(IntroState.seen(neighbor, defaults: defaults))
    }
}
