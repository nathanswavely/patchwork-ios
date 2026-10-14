// SPDX-License-Identifier: MPL-2.0

import Foundation

// Creating a patch, as values: the web's `PatchForm.svelte` with no view in
// it. The same draft fills the create form (`POST nodes`) and the second half
// of a claim (`POST claims/{id}/setup`, then `PATCH nodes/{slug}`), because
// on the web a claim's setup *is* creation with the fields already filled
// (ADR 039), and two forms would drift apart.

/// How a patch takes members. The web's three cards, in the web's order,
/// which is also the order of how closed they are.
enum MembershipPolicyChoice: String, CaseIterable, Identifiable, Encodable {
    case inviteOnly = "invite_only"
    case approvalRequired = "approval_required"
    case open
    var id: String { rawValue }
    var name: String {
        switch self {
        case .inviteOnly: return "Invite only"
        case .approvalRequired: return "Approval required"
        case .open: return "Open"
        }
    }
    var detail: String {
        switch self {
        case .inviteOnly: return "Only people an admin invites can join."
        case .approvalRequired: return "Anyone can ask to join; an admin approves each request."
        case .open: return "Anyone can join without approval."
        }
    }
}

/// The four governance templates the web offers, with its words. Minimal is
/// the default (web ADR 041): the typical new patch is one person running a
/// listing, and ceremony is opted into rather than inherited.
enum GovernanceTemplate: String, CaseIterable, Identifiable, Encodable {
    case minimal, casual, collaborative, formal
    var id: String { rawValue }
    var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var detail: String {
        switch self {
        case .minimal: return "No overhead. You're the only one running it."
        case .casual: return "Small group. Majority rules."
        case .collaborative: return "Open community, structured process. Trust builds through contribution."
        case .formal: return "Coalition-scale governance. Elected council, term limits, full accountability."
        }
    }
    var leadership: String {
        switch self {
        case .minimal, .casual: return "Maintainer"
        case .collaborative: return "Meritocratic"
        case .formal: return "Elected Council"
        }
    }
    var bestFor: String {
        switch self {
        case .minimal: return "Bands, solo artists, pop-up projects"
        case .casual: return "Small collectives, meetups, studios (5\u{2013}20 people)"
        case .collaborative: return "Venues, co-ops, makerspaces (20\u{2013}100 people)"
        case .formal: return "Arts districts, coalitions (100+ people)"
        }
    }
    /// What each template's own rules say about who can join — the web's
    /// `TEMPLATE_MEMBERSHIP_POLICY`, which mirrors the server's defaults.
    /// Only setup seeds the policy from it; creation starts closed.
    var membershipPolicy: MembershipPolicyChoice {
        switch self {
        case .minimal: return .inviteOnly
        case .casual: return .open
        case .collaborative, .formal: return .approvalRequired
        }
    }
}

/// A point a person confirmed on the map. Never one the address implied:
/// the gazetteer's answer is a suggestion until somebody presses the button
/// that takes it (web ADR 082).
struct MapPoint: Equatable, Hashable {
    var latitude: Double
    var longitude: Double
    var isValid: Bool { (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}

/// Everything the form holds.
struct PatchDraft: Equatable {
    var name = ""
    var description = ""
    var address = ""
    var website = ""
    /// Only ever set by a confirmation on the map.
    var point: MapPoint?
    /// Curated tags, in priority order: the first motif-bearing one decides
    /// the default motif.
    var tags: [String] = []
    /// Words that are not in the vocabulary yet (web ADR 114). They travel
    /// in their own field, so an unknown name in `tags` stays an error.
    var suggestTags: [String] = []
    /// Preselected to the closed option. The web learned this twice: unset
    /// reads as a choice between equals, and a five-minute-old account took
    /// the first card and got a patch anyone could join. Closed is the safe
    /// way to fail when nobody engages with the question.
    var policy: MembershipPolicyChoice = .inviteOnly
    /// In setup the policy follows the template until the claimant answers it
    /// themselves; after that it is theirs and nothing moves it.
    var policyAnswered = false
    var template: GovernanceTemplate = .minimal
    var palette: String
    var block: String
    var rotation: Int
    /// Empty means unset: the motif follows the first tag.
    var motif = ""

    init(palette: String, block: String, rotation: Int) {
        self.palette = palette; self.block = block; self.rotation = rotation
    }

    /// Creation always shows a concrete tile, seeded at random so every new
    /// patch starts somewhere real, and pins it.
    static func seeded<G: RandomNumberGenerator>(using generator: inout G) -> PatchDraft {
        PatchDraft(palette: QuiltTheme.palettes.randomElement(using: &generator)?.key ?? "adolescents",
                   block: QuiltBlocks.keys.randomElement(using: &generator) ?? "pinwheel",
                   rotation: [0, 90, 180, 270].randomElement(using: &generator) ?? 0)
    }
    static func seeded() -> PatchDraft {
        var generator = SystemRandomNumberGenerator()
        return seeded(using: &generator)
    }

    /// Setup's draft: the listing as it stands, its tile seeded from what it
    /// already wears — chosen or hash-assigned — so the claimant sees what is
    /// there rather than a reroll, and the policy seeded from Minimal.
    init(setup listing: Patch) {
        let palette = QuiltTheme.byKey[listing.appearance?.palette ?? ""]?.key
            ?? QuiltTheme.palettes[QuiltTheme.index(listing.id, count: QuiltTheme.palettes.count)].key ?? "adolescents"
        self.init(palette: palette,
                  block: QuiltBlocks.keys[QuiltBlocks.index(id: listing.id, appearance: listing.appearance)],
                  rotation: QuiltBlocks.rotation(id: listing.id, appearance: listing.appearance))
        name = listing.name
        description = listing.description ?? ""
        address = listing.address ?? ""
        website = listing.website ?? ""
        if let latitude = listing.latitude, let longitude = listing.longitude {
            let point = MapPoint(latitude: latitude, longitude: longitude)
            if point.isValid { self.point = point }
        }
        tags = listing.tags ?? []
        if let icon = listing.appearance?.icon, Motifs.keys.contains(icon) { motif = icon }
        policy = template.membershipPolicy
    }

    /// Choosing a template: in setup it carries the policy with it until the
    /// policy has been answered; at creation it never does.
    mutating func choose(_ next: GovernanceTemplate, setup: Bool) {
        template = next
        if setup && !policyAnswered { policy = next.membershipPolicy }
    }
    mutating func answer(_ next: MembershipPolicyChoice) {
        policy = next
        policyAnswered = true
    }
    mutating func rotate() { rotation = (rotation + 90) % 360 }
    /// A motif pressed again is a motif let go of.
    mutating func toggleMotif(_ key: String) { motif = motif == key ? "" : key }

    /// The one rule the form checks itself, in the web's words.
    func problem() -> String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Name is required" : nil
    }

    var appearance: AppearanceChoice {
        AppearanceChoice(palette: palette, block: block, rotation: rotation, icon: motif.isEmpty ? nil : motif)
    }

    private static func filled(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `POST nodes`. `membership_policy` is always sent: the server defaults
    /// an omitted one to `open`, which is the one default the form exists
    /// to avoid. `visibility` is always `public`, as the web sends it.
    var createBody: PatchCreateBody {
        PatchCreateBody(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: Self.filled(description), address: Self.filled(address), website: Self.filled(website),
                        latitude: point?.latitude, longitude: point?.longitude,
                        visibility: "public", membershipPolicy: policy, template: template, appearance: appearance,
                        tags: tags.isEmpty ? nil : tags, suggestTags: suggestTags.isEmpty ? nil : suggestTags)
    }

    /// `POST claims/{id}/setup`: the template and the policy travel here,
    /// because setup is where governance is forked and `PATCH nodes` takes
    /// no membership policy at all.
    var setupBody: ClaimSetupBody { ClaimSetupBody(template: template, membershipPolicy: policy) }

    /// `PATCH nodes/{slug}` once the patch is the claimant's: the fields, as
    /// the web sends them after setup.
    var updateBody: PatchUpdateBody {
        PatchUpdateBody(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: Self.filled(description), address: Self.filled(address), website: Self.filled(website),
                        latitude: point?.latitude, longitude: point?.longitude, visibility: "public",
                        appearance: appearance, tags: tags.isEmpty ? nil : tags, suggestTags: suggestTags.isEmpty ? nil : suggestTags)
    }

    /// The draft as a patch, for the live miniature: the same drawing the
    /// quilt will make of it, from the same appearance keys.
    func preview(id: String) -> Patch? {
        var appearance: [String: Any] = ["palette": palette, "block": block, "rotation": rotation]
        if !motif.isEmpty { appearance["icon"] = motif }
        let object: [String: Any] = ["id": id, "name": name.isEmpty ? "New patch" : name, "slug": id,
                                     "tags": tags, "appearance": appearance]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(Patch.self, from: data)
    }
}

/// A patch's chosen tile, as the server stores it. The form never sends a
/// bundle or a drafted block: those are drafted in Patch Settings on the
/// website.
struct AppearanceChoice: Encodable, Equatable {
    let palette: String
    let block: String
    let rotation: Int
    let icon: String?
}

struct PatchCreateBody: Encodable, Equatable {
    let name: String
    let description: String?
    let address: String?
    let website: String?
    let latitude: Double?
    let longitude: Double?
    let visibility: String
    let membershipPolicy: MembershipPolicyChoice
    let template: GovernanceTemplate
    let appearance: AppearanceChoice
    let tags: [String]?
    let suggestTags: [String]?
}

struct ClaimSetupBody: Encodable, Equatable {
    let template: GovernanceTemplate
    let membershipPolicy: MembershipPolicyChoice
}

struct PatchUpdateBody: Encodable, Equatable {
    let name: String
    let description: String?
    let address: String?
    let website: String?
    let latitude: Double?
    let longitude: Double?
    let visibility: String
    let appearance: AppearanceChoice
    let tags: [String]?
    let suggestTags: [String]?
}

/// The 201 from `POST nodes`: the new node, and — when a suggested word had
/// already been declined — the one sentence the web toasts about it.
struct CreatedPatch: Decodable {
    let node: Patch
    let tagWarning: String?
    private enum CodingKeys: String, CodingKey { case tagWarning }
    init(from decoder: Decoder) throws {
        node = try Patch(from: decoder)
        tagWarning = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .tagWarning)
    }
}

// MARK: - Tags

/// The tag picker's rules (web `TagPicker.svelte`).
enum TagSuggestion {
    /// The server's `normalizeTagName`, so the chip says what will be saved:
    /// runs of space, underscore and hyphen become one hyphen, anything that
    /// is not a letter, a number or a hyphen goes, lowercased, trimmed of
    /// hyphens, at most 32 characters.
    static func normalize(_ raw: String) -> String {
        var text = raw.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "[\\s_-]+", with: "-", options: .regularExpression)
        text = String(text.unicodeScalars.filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == "-" }.map(Character.init))
        text = text.lowercased()
        while text.hasPrefix("-") { text.removeFirst() }
        while text.hasSuffix("-") { text.removeLast() }
        text = String(text.prefix(32))
        while text.hasSuffix("-") { text.removeLast() }
        return text
    }

    enum Outcome: Equatable {
        /// Already a curated word: picked like any other.
        case picked(String)
        /// A new word, to travel in `suggest_tags`.
        case suggested(String)
        /// Said under the field, in the web's words.
        case refused(String)
    }

    static func add(_ raw: String, vocabulary: [String], picked: [String], suggested: [String]) -> Outcome {
        let name = normalize(raw)
        guard !name.isEmpty else { return .refused("Enter a word to suggest.") }
        if vocabulary.contains(name) { return .picked(name) }
        if suggested.contains(name) { return .refused("\(name) is already waiting for review.") }
        return .suggested(name)
    }
}

// MARK: - The map's suggestion

/// `GET gazetteer/suggest?q=` (web ADR 082): one suggested placement for an
/// address, or a polite miss. A miss and an instance with no gazetteer are
/// the same answer here, as on the web — the person places the pin either way.
struct PlaceSuggestion: Decodable, Equatable {
    struct Place: Decodable, Equatable {
        let latitude: Double?
        let longitude: Double?
    }
    let found: Bool?
    let available: Bool?
    let place: Place?
    let label: String?
    /// The point it proposes, if it proposes one at all.
    var point: MapPoint? {
        guard found == true, let latitude = place?.latitude, let longitude = place?.longitude else { return nil }
        let point = MapPoint(latitude: latitude, longitude: longitude)
        return point.isValid ? point : nil
    }
    /// Below three characters an address is a fragment, not a thing anybody
    /// named; the web asks about nothing shorter.
    static func worthLookingUp(_ address: String) -> Bool {
        address.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }
}

extension PatchworkAPI {
    func createPatch(_ body: PatchCreateBody) async throws -> CreatedPatch { try await post("nodes", body: body) }

    /// Every failure is a miss: nothing about a lookup is the person's
    /// problem, because the map works the same without it.
    func suggestPlace(_ address: String) async -> PlaceSuggestion? {
        let query = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PlaceSuggestion.worthLookingUp(query) else { return nil }
        return try? await get("gazetteer/suggest", query: [URLQueryItem(name: "q", value: String(query.prefix(300)))])
    }
}
