// SPDX-License-Identifier: MPL-2.0

import Foundation

// A patch's noticeboard (web ADR 081): "a noticeboard with replies, not a
// feed, and not a forum". A notice is a title, a Markdown body and at most
// one image somebody already has online; a reply is a flat answer under it.
// The room is the patch's active members and admins and nobody else — not a
// follower, not the public, not a quilt admin who holds no role here — and
// the server answers everybody outside it with the same 404, so this client
// never learns whether a board it cannot read has anything on it.
//
// Quiet by default: a notice rings the bell only where its author asked it
// to, there is no unread count and no badge, and nothing here invents one.
//
// The values and the calls live in this file; the screens are in
// `PatchNoticeboard.swift` and `NoticeDetail.swift`. The board's settings
// and its report queue are an admin's, and stay the website's.

// MARK: - The payload's parts

/// One notice. The server sends every field and never a null — an absent
/// image is `""` — but each is read as optional anyway, so a quilt a version
/// behind is read rather than refused.
struct Notice: Decodable, Identifiable, Hashable {
    let id: String
    var nodeId: String = ""
    var authorId: String = ""
    var title: String = ""
    var body: String = ""
    var imageUrl: String = ""
    var imageAlt: String = ""
    var repliesOpen: Bool = true
    var membersTold: Bool = false
    var createdAt: String = ""
    var updatedAt: String = ""
    var authorUsername: String = ""
    var authorDisplayName: String = ""
    var replyCount: Int = 0

    init(id: String, nodeId: String = "", authorId: String = "", title: String = "", body: String = "",
         imageUrl: String = "", imageAlt: String = "", repliesOpen: Bool = true, membersTold: Bool = false,
         createdAt: String = "", updatedAt: String = "", authorUsername: String = "", authorDisplayName: String = "",
         replyCount: Int = 0) {
        self.id = id; self.nodeId = nodeId; self.authorId = authorId; self.title = title; self.body = body
        self.imageUrl = imageUrl; self.imageAlt = imageAlt; self.repliesOpen = repliesOpen; self.membersTold = membersTold
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.authorUsername = authorUsername
        self.authorDisplayName = authorDisplayName; self.replyCount = replyCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, nodeId, authorId, title, body, imageUrl, imageAlt, repliesOpen, membersTold
        case createdAt, updatedAt, authorUsername, authorDisplayName, replyCount
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? "" }
        id = try c.decode(String.self, forKey: .id)
        nodeId = text(.nodeId); authorId = text(.authorId); title = text(.title); body = text(.body)
        imageUrl = text(.imageUrl); imageAlt = text(.imageAlt)
        repliesOpen = ((try? c.decodeIfPresent(Bool.self, forKey: .repliesOpen)) ?? nil) ?? true
        membersTold = ((try? c.decodeIfPresent(Bool.self, forKey: .membersTold)) ?? nil) ?? false
        createdAt = text(.createdAt); updatedAt = text(.updatedAt)
        authorUsername = text(.authorUsername); authorDisplayName = text(.authorDisplayName)
        replyCount = ((try? c.decodeIfPresent(Int.self, forKey: .replyCount)) ?? nil) ?? 0
    }

    var author: String { Noticeboard.author(displayName: authorDisplayName, username: authorUsername) }
    /// The one image, where there is one and it is an address this app will
    /// load: https, with a host. Anything else is no image at all.
    var image: URL? {
        guard let parts = URLComponents(string: imageUrl.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty else { return nil }
        return parts.url
    }
}

/// One reply. Flat: there is no reply to a reply, and no reaction.
struct NoticeReply: Decodable, Identifiable, Hashable {
    let id: String
    var noticeId: String = ""
    var authorId: String = ""
    var body: String = ""
    var createdAt: String = ""
    var updatedAt: String = ""
    var authorUsername: String = ""
    var authorDisplayName: String = ""

    init(id: String, noticeId: String = "", authorId: String = "", body: String = "", createdAt: String = "",
         updatedAt: String = "", authorUsername: String = "", authorDisplayName: String = "") {
        self.id = id; self.noticeId = noticeId; self.authorId = authorId; self.body = body
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.authorUsername = authorUsername; self.authorDisplayName = authorDisplayName
    }

    private enum CodingKeys: String, CodingKey {
        case id, noticeId, authorId, body, createdAt, updatedAt, authorUsername, authorDisplayName
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? "" }
        id = try c.decode(String.self, forKey: .id)
        noticeId = text(.noticeId); authorId = text(.authorId); body = text(.body)
        createdAt = text(.createdAt); updatedAt = text(.updatedAt)
        authorUsername = text(.authorUsername); authorDisplayName = text(.authorDisplayName)
    }

    var author: String { Noticeboard.author(displayName: authorDisplayName, username: authorUsername) }
}

/// `GET nodes/{slug}/notices`: a page of the board, newest first, and what
/// this reader may do on it. The rights ride the list because there is
/// nowhere else for them: the patch's own payload says who puts up notices,
/// not whether *you* may.
struct NoticePage: Decodable {
    var items: [Notice] = []
    /// Empty on the last page — never null, never absent.
    var nextCursor: String = ""
    var mayPost: Bool = false
    /// The patch's starting position for a new notice's "Take replies".
    var repliesDefault: Bool = true
    /// `members` or `admins`.
    var noticePosting: String = "members"

    init(items: [Notice] = [], nextCursor: String = "", mayPost: Bool = false, repliesDefault: Bool = true, noticePosting: String = "members") {
        self.items = items; self.nextCursor = nextCursor; self.mayPost = mayPost
        self.repliesDefault = repliesDefault; self.noticePosting = noticePosting
    }
    private enum CodingKeys: String, CodingKey { case items, nextCursor, mayPost, repliesDefault, noticePosting }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = ((try? c.decodeIfPresent([Notice].self, forKey: .items)) ?? nil) ?? []
        nextCursor = ((try? c.decodeIfPresent(String.self, forKey: .nextCursor)) ?? nil) ?? ""
        mayPost = ((try? c.decodeIfPresent(Bool.self, forKey: .mayPost)) ?? nil) ?? false
        repliesDefault = ((try? c.decodeIfPresent(Bool.self, forKey: .repliesDefault)) ?? nil) ?? true
        noticePosting = ((try? c.decodeIfPresent(String.self, forKey: .noticePosting)) ?? nil) ?? "members"
    }
}

/// `GET notices/{id}`: the notice, the patch it hangs in, and the reader's
/// two rights over it. Only this read carries them — a write answers with
/// the bare notice — so they are kept from here.
struct NoticeEnvelope: Decodable {
    let notice: Notice
    var nodeSlug: String = ""
    /// The author, and only the author.
    var mayEdit: Bool = false
    /// The author or a patch admin: the replies switch, and taking it down.
    var mayManage: Bool = false

    private enum CodingKeys: String, CodingKey { case notice, nodeSlug, mayEdit, mayManage }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notice = try c.decode(Notice.self, forKey: .notice)
        nodeSlug = ((try? c.decodeIfPresent(String.self, forKey: .nodeSlug)) ?? nil) ?? ""
        mayEdit = ((try? c.decodeIfPresent(Bool.self, forKey: .mayEdit)) ?? nil) ?? false
        mayManage = ((try? c.decodeIfPresent(Bool.self, forKey: .mayManage)) ?? nil) ?? false
    }
}

/// `GET notices/{id}/replies`: oldest first.
struct ReplyPage: Decodable {
    var items: [NoticeReply] = []
    var nextCursor: String = ""
    private enum CodingKeys: String, CodingKey { case items, nextCursor }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = ((try? c.decodeIfPresent([NoticeReply].self, forKey: .items)) ?? nil) ?? []
        nextCursor = ((try? c.decodeIfPresent(String.self, forKey: .nextCursor)) ?? nil) ?? ""
    }
}

// MARK: - What the board says, and to whom

enum Noticeboard {
    // MARK: The room

    /// Who the board is for: an active member or admin of this patch. Not a
    /// follower, not somebody waiting to be let in — and not `is_admin`,
    /// which the patch's payload also answers true for a quilt admin who
    /// holds no role here and whom every noticeboard route then answers 404.
    static func inRoom(_ standing: Standing?) -> Bool {
        standing == .active(.member) || standing == .active(.admin)
    }

    static let outsideTitle = "The noticeboard is for this patch’s members."
    static let outsideDetail = "Become a member to read and put up notices."

    /// The line at the head of the board: who reads it, and — where the
    /// patch keeps posting to its admins — who writes on it.
    static func hint(posting: String) -> String {
        let base = "Read by this patch’s admins and members, and nobody else."
        return posting == "admins" ? base + " Its admins put up the notices." : base
    }

    // MARK: The words on a row

    /// A person's name, or what the server leaves where an account was.
    static func author(displayName: String, username: String) -> String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let handle = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return handle.isEmpty ? "Deleted account" : handle
    }

    static func replies(_ count: Int) -> String { count == 1 ? "1 reply" : "\(count) replies" }

    /// What a row says about its replies (web `PatchNoticeboard`): the count
    /// while they are open — "0 replies" included, because it says replies
    /// are taken — and, once they are off, that they are off and how many
    /// were kept.
    static func repliesLabel(_ notice: Notice) -> String {
        if notice.repliesOpen { return replies(notice.replyCount) }
        return notice.replyCount > 0 ? "replies off · \(notice.replyCount) kept" : "replies off"
    }

    /// The heading over a notice's replies.
    static func repliesHeading(_ count: Int) -> String { count == 0 ? "No replies" : replies(count) }

    /// How many replies a notice has, for that heading. The web counts the
    /// rows it has loaded, which understates a long thread until its last
    /// page is in; the notice's own count is the server's, so it is used
    /// until everything is loaded, and the rows are the truth after that.
    static func replyTotal(notice: Notice, loaded: Int, allLoaded: Bool) -> Int {
        allLoaded ? loaded : max(notice.replyCount, loaded)
    }

    static let repliesOffLine = "Replies are off on this notice."

    // MARK: Paging

    /// A page joined to what is already on screen, without a second copy of
    /// anything. A reply posted from here is appended at once, and a later
    /// "More replies" — whose cursor is the last row *loaded* — is then
    /// handed that same reply again.
    static func appending<Row: Identifiable>(_ page: [Row], to rows: [Row]) -> [Row] where Row.ID == String {
        var seen = Set(rows.map(\.id))
        return rows + page.filter { seen.insert($0.id).inserted }
    }

    // MARK: Who may do what

    /// Removing a reply: its author or a patch admin. The notice's author
    /// has no say over other people's replies.
    static func canRemove(_ reply: NoticeReply, me: String?, standing: Standing?) -> Bool {
        guard let me, !me.isEmpty else { return false }
        return reply.authorId == me || standing == .active(.admin)
    }

    /// Reporting is for what somebody else wrote. The server would take a
    /// report of your own notice; nothing offers it.
    static func canReport(authorId: String, me: String?) -> Bool {
        guard let me, !me.isEmpty else { return false }
        return authorId != me
    }

    // MARK: The server's checks, before sending

    static let titleLimit = 140
    static let bodyLimit = 20_000
    static let replyLimit = 5_000

    /// `validateNotice`, in the server's order and in its words. Lengths are
    /// bytes, as Go counts them, so a title of emoji runs out four times as
    /// fast as the web's `maxlength` suggests.
    static func problem(_ draft: NoticeDraft) -> String? {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return "a notice needs a title" }
        if title.utf8.count > titleLimit { return "keep the title under 140 characters" }
        if body.utf8.count > bodyLimit { return "that notice is too long" }
        return EventPosting.imageProblem(url: draft.imageURL, alt: draft.imageAlt)
    }

    static func replyProblem(_ text: String) -> String? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty || body.utf8.count > replyLimit { return "a reply needs a body under 5000 characters" }
        return nil
    }

    // MARK: What a write says afterwards

    static func putUpLine(toldMembers: Bool) -> String { toldMembers ? "Notice put up and members told" : "Notice put up" }
    static func repliesSwitchLine(open: Bool) -> String { open ? "Replies are on" : "Replies are off. Existing replies stay." }
    /// The take-down's second line. There is no tombstone: a notice taken
    /// down takes its replies with it.
    static func takeDownMessage(replies count: Int) -> String? {
        if count == 0 { return nil }
        return count == 1 ? "Its 1 reply goes with it." : "Its \(count) replies go with it."
    }

    // MARK: Reports

    /// The web's reasons, in the web's order. The server takes any text; the
    /// list is what keeps a report something an admin can sort.
    static let reportReasons = [
        "Harassment or intimidation", "Hate speech or discrimination", "Threats or incitement",
        "Sharing private information", "Spam or scam", "Impersonation", "Something else",
    ]
    /// Where a report about a notice or a reply goes: to this patch's
    /// admins (`content_reports.node_id`), never to the quilt's panel. The
    /// web's shared dialog says "the instance admins" here, which is true of
    /// every other kind of report and not of this one.
    static let reportDestination = "Reports about notices and replies go to this patch’s admins."
}

/// A notice being written, or rewritten.
struct NoticeDraft: Equatable {
    var title = ""
    var body = ""
    var imageURL = ""
    var imageAlt = ""
    var repliesOpen = true
    var tellMembers = false

    init(title: String = "", body: String = "", imageURL: String = "", imageAlt: String = "", repliesOpen: Bool = true, tellMembers: Bool = false) {
        self.title = title; self.body = body; self.imageURL = imageURL; self.imageAlt = imageAlt
        self.repliesOpen = repliesOpen; self.tellMembers = tellMembers
    }
    /// The edit form's starting point: the notice as it stands.
    init(editing notice: Notice) {
        self.init(title: notice.title, body: notice.body, imageURL: notice.imageUrl, imageAlt: notice.imageAlt,
                  repliesOpen: notice.repliesOpen, tellMembers: false)
    }
}

// MARK: - The calls

/// `POST nodes/{slug}/notices`. Every field trimmed, the way the web sends
/// them. A description with no image to describe is not sent: the field is
/// hidden while the address is empty, and what it last held is not the
/// author's to be surprised by.
struct NoticeBody: Encodable, Equatable {
    var title: String
    var body: String
    var imageUrl: String
    var imageAlt: String
    var repliesOpen: Bool
    var tellMembers: Bool
    private enum CodingKeys: String, CodingKey {
        case title, body, imageUrl = "image_url", imageAlt = "image_alt", repliesOpen = "replies_open", tellMembers = "tell_members"
    }
    init(_ draft: NoticeDraft) {
        let edit = NoticeEditBody(draft)
        title = edit.title; body = edit.body; imageUrl = edit.imageUrl; imageAlt = edit.imageAlt
        repliesOpen = draft.repliesOpen; tellMembers = draft.tellMembers
    }
}

/// `PATCH notices/{id}` as an edit: the four things an author may rewrite,
/// and nothing else. `replies_open` is left out on purpose — it is a
/// different right, and a request that carries both is refused whole for an
/// admin who is not the author.
struct NoticeEditBody: Encodable, Equatable {
    var title: String
    var body: String
    var imageUrl: String
    var imageAlt: String
    private enum CodingKeys: String, CodingKey { case title, body, imageUrl = "image_url", imageAlt = "image_alt" }
    init(_ draft: NoticeDraft) {
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        imageUrl = draft.imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        imageAlt = imageUrl.isEmpty ? "" : draft.imageAlt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// `PATCH notices/{id}` as the replies switch, alone.
struct RepliesSwitchBody: Encodable, Equatable {
    var repliesOpen: Bool
    private enum CodingKeys: String, CodingKey { case repliesOpen = "replies_open" }
}

/// `POST reports`, the quilt's one report endpoint, for the two kinds this
/// room has.
struct ReportBody: Encodable, Equatable {
    enum Kind: String, Encodable { case notice, reply }
    var entityType: Kind
    var entityId: String
    var reason: String
    var details: String
    private enum CodingKeys: String, CodingKey { case entityType = "entity_type", entityId = "entity_id", reason, details }
}

private struct ReplyBody: Encodable { let body: String }

extension PatchworkAPI {
    /// Built apart from the request, like every other query this client
    /// sends. The server's own page is twenty, and that is what is asked for.
    static func pageQuery(after cursor: String?, limit: Int = 20) -> [URLQueryItem] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor, !cursor.isEmpty { query.append(URLQueryItem(name: "after", value: cursor)) }
        return query
    }

    func notices(slug: String, after cursor: String? = nil) async throws -> NoticePage {
        try await get("nodes/\(slug)/notices", query: Self.pageQuery(after: cursor))
    }

    /// The notice is addressed by its id alone: the patch is not in the path.
    func notice(id: String) async throws -> NoticeEnvelope { try await get("notices/\(id)") }

    func putUp(slug: String, draft: NoticeDraft) async throws -> Notice {
        try await post("nodes/\(slug)/notices", body: NoticeBody(draft))
    }

    func editNotice(id: String, draft: NoticeDraft) async throws -> Notice {
        try await patch("notices/\(id)", body: NoticeEditBody(draft))
    }

    func setReplies(notice id: String, open: Bool) async throws -> Notice {
        try await patch("notices/\(id)", body: RepliesSwitchBody(repliesOpen: open))
    }

    func takeDown(notice id: String) async throws { try await deleteVoid("notices/\(id)") }

    func replies(notice id: String, after cursor: String? = nil) async throws -> ReplyPage {
        try await get("notices/\(id)/replies", query: Self.pageQuery(after: cursor))
    }

    func reply(notice id: String, body: String) async throws -> NoticeReply {
        try await post("notices/\(id)/replies", body: ReplyBody(body: body.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func removeReply(id: String) async throws { try await deleteVoid("replies/\(id)") }

    func report(_ kind: ReportBody.Kind, id: String, reason: String, details: String) async throws {
        try await postVoid("reports", body: ReportBody(entityType: kind, entityId: id, reason: reason,
                                                       details: details.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
}
