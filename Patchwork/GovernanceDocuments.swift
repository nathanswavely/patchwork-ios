// SPDX-License-Identifier: MPL-2.0

import Foundation

// Changing a governance document, reading its history, and writing a new
// one (web `AmendmentEditor.svelte`, `GovernanceVersionHistory.svelte`,
// `GovernanceEdit.svelte`; server `CreateProposal`, `GetGovernanceVersions`,
// `GetGovernanceDiff`, `CreateGovernanceDoc`; web ADRs 011, 036, 037, 041,
// 053, 092).
//
// An amendment is a proposal like any other — the same outcome switch, the
// same door words — that carries the whole proposed text. The server
// branches the document's repository with it and merges the branch when the
// proposal takes effect, so what is sent is the text as written, not a
// patch. The summary of the change is worked out here, line by line, so the
// person writing it can see what they are asking for before they ask; the
// web shows a word-level diff, which on a phone is a wall of colour.

// MARK: - The line diff

enum LineDiff {
    enum Kind: Equatable { case same, added, removed }

    struct Line: Equatable {
        let kind: Kind
        let text: String
    }

    /// One row of the collapsed view: a line, or a run of unchanged lines
    /// folded away.
    enum Row: Equatable {
        case line(Line)
        case folded(Int)
    }

    /// Past this many cells the longest-common-subsequence table is not
    /// worth a phone's memory, and the middle is shown as replaced whole.
    static let tableLimit = 1_000_000

    /// The lines of `new` against `old`: the common head and tail kept as
    /// they are, the middle matched by its longest common subsequence.
    static func lines(old: String, new: String) -> [Line] {
        let a = split(old), b = split(new)
        var head = 0
        while head < a.count && head < b.count && a[head] == b[head] { head += 1 }
        var tail = 0
        while tail < a.count - head && tail < b.count - head && a[a.count - 1 - tail] == b[b.count - 1 - tail] { tail += 1 }
        let midA = Array(a[head..<(a.count - tail)]), midB = Array(b[head..<(b.count - tail)])
        var out = a[..<head].map { Line(kind: .same, text: $0) }
        if midA.count * midB.count > tableLimit {
            out += midA.map { Line(kind: .removed, text: $0) } + midB.map { Line(kind: .added, text: $0) }
        } else {
            out += middle(midA, midB)
        }
        out += a[(a.count - tail)...].map { Line(kind: .same, text: $0) }
        return out
    }

    private static func split(_ text: String) -> [String] {
        text.isEmpty ? [] : text.components(separatedBy: "\n")
    }

    private static func middle(_ a: [String], _ b: [String]) -> [Line] {
        let n = a.count, m = b.count
        guard n > 0 || m > 0 else { return [] }
        // lcs[i][j]: the longest common subsequence of a[i...] and b[j...].
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out: [Line] = []
        var i = 0, j = 0
        while i < n || j < m {
            if i < n && j < m && a[i] == b[j] {
                out.append(Line(kind: .same, text: a[i])); i += 1; j += 1
            } else if j == m || (i < n && lcs[i + 1][j] >= lcs[i][j + 1]) {
                // Removals before additions where both would do, so a
                // changed line reads as the old one and then the new one.
                out.append(Line(kind: .removed, text: a[i])); i += 1
            } else {
                out.append(Line(kind: .added, text: b[j])); j += 1
            }
        }
        return out
    }

    static func counts(_ lines: [Line]) -> (added: Int, removed: Int) {
        (lines.filter { $0.kind == .added }.count, lines.filter { $0.kind == .removed }.count)
    }

    /// "2 lines added, 1 removed", "1 line removed", "No changes yet".
    static func summary(_ lines: [Line]) -> String {
        let (added, removed) = counts(lines)
        func many(_ n: Int) -> String { "\(n) line\(n == 1 ? "" : "s")" }
        switch (added, removed) {
        case (0, 0): return "No changes yet"
        case (_, 0): return "\(many(added)) added"
        case (0, _): return "\(many(removed)) removed"
        default: return "\(many(added)) added, \(removed) removed"
        }
    }

    /// The changes with `context` unchanged lines either side of each, and
    /// every longer run of unchanged lines folded to a count.
    static func rows(_ lines: [Line], context: Int = 2) -> [Row] {
        var keep = Array(repeating: false, count: lines.count)
        for (index, line) in lines.enumerated() where line.kind != .same {
            for k in max(0, index - context)...min(lines.count - 1, index + context) { keep[k] = true }
        }
        var rows: [Row] = []
        var folded = 0
        for (index, line) in lines.enumerated() {
            if keep[index] {
                if folded > 0 { rows.append(.folded(folded)); folded = 0 }
                rows.append(.line(line))
            } else {
                folded += 1
            }
        }
        if folded > 0 { rows.append(.folded(folded)) }
        return rows
    }
}

// MARK: - What the server holds

/// One version of a document: a commit on its file (`CommitInfo`).
struct DocumentVersion: Decodable, Hashable, Identifiable {
    let sha: String
    var message: String? = nil
    var authorName: String? = nil
    var date: String? = nil
    var versionNumber: Int? = nil
    /// `rebuilt` or `restored` where the repair pass wrote it (web ADR 084).
    var repair: String? = nil
    var id: String { sha }
}

struct DocumentVersionPage: Decodable {
    var items: [DocumentVersion]? = nil
}

/// `GET governance/{id}/diff`: word-level hunks and a unified diff. The
/// server sends no `old_content`/`new_content`, which the web's history
/// reads first, so the web always falls back to the unified text.
struct DocumentDiff: Decodable {
    struct Hunk: Decodable, Hashable {
        let type: String
        let text: String
    }
    var hunks: [Hunk]? = nil
    var unified: String? = nil
}

enum DocumentHistory {
    /// The oldest rebuilt entry stands in for a history that no longer
    /// exists, so the screen says so rather than presenting v1 as where the
    /// document began.
    static func rebuiltOn(_ versions: [DocumentVersion]) -> String? {
        versions.last(where: { $0.repair == "rebuilt" })?.date
    }

    static func heading(_ count: Int) -> String {
        "Version history · \(count) version\(count == 1 ? "" : "s")"
    }

    /// The door's words on the document (web `GovernanceDetail`).
    static func doorLabel(_ version: Int?) -> String {
        guard let version, version > 0 else { return "History" }
        return "History (\(version) \(version == 1 ? "version" : "versions"))"
    }

    static func repairLabel(_ repair: String?) -> String? {
        switch repair {
        case "rebuilt": return "Rebuilt"
        case "restored": return "Restored"
        default: return nil
        }
    }
}

// MARK: - Amending

enum DocumentAmending {
    /// The rules file is changed through the rules form, never as text.
    static let rulesFile = "governance-rules.json"
    static func isRulesDoc(_ target: String?) -> Bool { target == rulesFile || target == "Governance Rules" }

    /// The door on a document, worded as the outcome: a direct change is
    /// never called a proposal (ADR 041). The web's door says "Propose
    /// change" either way.
    static func door(signedIn: Bool, standing: Standing?, rules: GovernanceRules?) -> String? {
        guard ProposalPosting.mayPropose(signedIn: signedIn, standing: standing), let rules else { return nil }
        return ProposalPosting.adminChooses(rules, isPatchAdmin: standing == .active(.admin)) ? "Change this document" : "Propose change"
    }

    static func heading(direct: Bool) -> String { direct ? "Changing" : "Proposing changes to" }
    static func whyLabel(direct: Bool) -> String { direct ? "Why this change? (optional)" : "Why are you proposing this? (optional)" }
    static func defaultTitle(_ document: String) -> String { "Update \(document)" }

    /// The server's check a form can fail, and the one thing the web will
    /// not send: an amendment that changes nothing.
    static func problem(title: String, original: String, proposed: String) -> String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "title is required" }
        if original == proposed { return "Change the document before you send it." }
        return nil
    }
}

/// `POST nodes/{slug}/proposals` for a change to a document, as the web's
/// amendment editor sends it — the proposed text as typed, the document's
/// filename as its target, the summary as the commit message — with the
/// outcome's window and flag as the general form sends them.
struct AmendmentBody: Encodable, Equatable {
    var title: String
    var body: String
    var proposalType = "amendment"
    var targetDoc: String
    var proposedBody: String
    var proposedTitle: String
    var changeSummary: String
    var durationHours: Int?
    var putToVote: Bool?
    private enum CodingKeys: String, CodingKey {
        case title, body, proposalType = "proposal_type", targetDoc = "target_doc", proposedBody = "proposed_body"
        case proposedTitle = "proposed_title", changeSummary = "change_summary", durationHours = "duration_hours", putToVote = "put_to_vote"
    }

    init(title: String, why: String, targetDoc: String, documentTitle: String, proposed: String,
         rules: GovernanceRules?, isPatchAdmin: Bool, putToVote: Bool, durationHours: Int) {
        let summary = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = summary
        body = why.trimmingCharacters(in: .whitespacesAndNewlines)
        self.targetDoc = targetDoc
        proposedBody = proposed
        proposedTitle = documentTitle
        changeSummary = summary
        let rulesDoc = DocumentAmending.isRulesDoc(targetDoc)
        let chooses = ProposalPosting.adminChooses(rules, isPatchAdmin: isPatchAdmin, rulesDoc: rulesDoc)
        let outcome = ProposalPosting.outcome(rules: rules, isPatchAdmin: isPatchAdmin, putToVote: chooses && putToVote, rulesDoc: rulesDoc)
        self.durationHours = ProposalPosting.asksDuration(outcome) ? durationHours : nil
        self.putToVote = chooses ? putToVote : nil
    }
}

// MARK: - A new document

enum NewDocument {
    /// The web's three starting points, in its words.
    struct Template: Identifiable, Equatable {
        let id: String
        let label: String
        let title: String
        let body: String
    }

    static let templates: [Template] = [
        Template(id: "", label: "Blank", title: "", body: ""),
        Template(id: "community-agreement", label: "Community Agreement", title: "Community Agreement", body: """
            # Community Agreement

            ## Purpose
            [What this community exists to do]

            ## Values
            - [Core value 1]
            - [Core value 2]
            - [Core value 3]

            ## Membership
            [How people join, what's expected of members]

            ## Decision Making
            [How the community makes decisions together]

            ## Amendments
            This agreement can be amended through the proposal process. Any member can propose changes.
            """),
        Template(id: "code-of-conduct", label: "Code of Conduct", title: "Code of Conduct", body: """
            # Code of Conduct

            ## Our Standards
            This community is dedicated to providing a welcoming and inclusive experience for everyone. We do not tolerate discrimination or harassment based on race, gender, sexual orientation, disability, age, religion, or any other protected characteristic.

            ## Expected Behavior
            - Be respectful and considerate
            - Listen actively and make space for different perspectives
            - Give and receive constructive feedback gracefully
            - Take responsibility for your impact on others

            ## Reporting
            If you experience or witness behavior that violates this code, contact a patch admin. All reports will be handled confidentially.

            ## Enforcement
            Violations may result in a warning, temporary suspension, or removal from the community, at the discretion of the admin team.
            """),
    ]

    /// Who may write one: an active admin of this patch, read off the
    /// membership index. The server also lets a quilt admin with no role
    /// here create one; the web's button and this door are the patch's own.
    static func mayCreate(signedIn: Bool, standing: Standing?) -> Bool {
        signedIn && standing == .active(.admin)
    }

    /// Members only until the patch decides otherwise (web ADR 036).
    static let defaultVisibility = "members"

    static func visibilityHint(_ visibility: String) -> String {
        visibility == "public"
            ? "Visitors, search engines, and other quilts can read this document."
            : "Only this patch’s members and admins can read this document. You can publish it later."
    }

    static func problem(title: String) -> String? {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "title is required" : nil
    }
}

/// `POST nodes/{slug}/governance`: the title and body trimmed, as the web
/// sends them, and the visibility always.
struct NewDocumentBody: Encodable, Equatable {
    var title: String
    var body: String
    var visibility: String
    init(title: String, body: String, visibility: String) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.visibility = visibility == "public" ? "public" : "members"
    }
}

extension PatchworkAPI {
    func propose(slug: String, amendment: AmendmentBody) async throws -> Proposal {
        try await post("nodes/\(slug)/proposals", body: amendment)
    }

    func documentVersions(_ id: String) async throws -> [DocumentVersion] {
        let page: DocumentVersionPage = try await get("governance/\(id)/versions")
        return page.items ?? []
    }

    func documentDiff(_ id: String, from: String, to: String) async throws -> DocumentDiff {
        try await get("governance/\(id)/diff", query: [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)])
    }

    /// Answers 201 with the document.
    func createDocument(slug: String, body: NewDocumentBody) async throws -> GovernanceDocument {
        try await post("nodes/\(slug)/governance", body: body)
    }
}
