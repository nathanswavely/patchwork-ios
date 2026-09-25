// SPDX-License-Identifier: MPL-2.0

#if DEBUG
import Foundation

/// Fictional, offline design fixtures. Only enabled by an explicit debug launch argument.
enum PreviewData {
    /// The events are dated from the day the fixtures are read rather than
    /// pinned to a calendar date, so the date presets mean something offline:
    /// one tonight, one in two days, one next week. Counted in the sample
    /// quilt's own zone, because that is the zone the presets resolve in —
    /// counting in UTC put the evening fixture on the quilt's *next* day for
    /// the four hours a New York evening runs past midnight in Greenwich.
    private static func instant(daysFromToday days: Int, hour: Int = 18) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let midnight = calendar.startOfDay(for: Date())
        let day = calendar.date(byAdding: .day, value: days, to: midnight) ?? midnight
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: day.addingTimeInterval(TimeInterval(hour * 3600)))
    }

    /// Tonight, and still ahead of whoever is reading. The fixture's point is
    /// one event later today, and a fixed 6pm stops being that at 6pm: a suite
    /// run in the evening found the day's event already over and the patch's
    /// "Upcoming" section starting two days out. Not clamped: in the last hour
    /// of the day the hour runs to 24, which `instant` reads as midnight, so
    /// the event stays the soonest thing ahead rather than the last thing
    /// behind — a clamp to 23:00 had made it already-over for that hour.
    private static var tonightHour: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return max(18, calendar.component(.hour, from: Date()) + 1)
    }

    private static var events: [(id: String, json: String)] {
        let tonight = """
        {"id":"demo-event","node_id":"demo-patch","title":"Saturday open studio",\
        "description":"Bring something you’re working on, or try something new. There will be fabric, paper, and a pot of coffee. Everyone is welcome; no experience needed.",\
        "location":"12 Example Street","latitude":40.0379,"longitude":-76.3055,\
        "starts_at":"\(instant(daysFromToday: 0, hour: tonightHour))","ends_at":"\(instant(daysFromToday: 0, hour: tonightHour + 3))",\
        "timezone":"America/New_York","recurrence":"weekly","visibility":"public","status":"active",\
        "image_url":"https://quilt.example.org/flyers/open-studio.jpg","image_alt":"A hand-lettered flyer for open studio night",\
        "event_url":"https://quilt.example.org/whats-on/open-studio",\
        "node_name":"Common Thread Studio","node_slug":"common-thread","node_status":"active",\
        "links":[{"id":"link-1","node_id":"demo-patch-2","node_name":"The Listening Room","node_slug":"listening-room","node_status":"active","status":"confirmed"},\
        {"id":"link-2","node_id":"extra-0","node_name":"Community Garden","node_slug":"extra-0","node_status":"active","status":"pending"}],\
        "mentions":[{"id":"mention-1","host":"neighbor.example.org","slug":"paper-mill","name":"The Paper Mill"}]}
        """
        let soon = """
        {"id":"demo-event-2","node_id":"demo-patch","title":"Fall mending circle",\
        "description":"Bring the thing with the hole in it.","location":"12 Example Street",\
        "starts_at":"\(instant(daysFromToday: 2))","ends_at":"\(instant(daysFromToday: 2, hour: 20))",\
        "timezone":"America/New_York","recurrence":"","visibility":"followers","status":"active",\
        "image_url":"","image_alt":"","event_url":"",\
        "node_name":"Common Thread Studio","node_slug":"common-thread","node_status":"active"}
        """
        let later = """
        {"id":"demo-event-3","node_id":"demo-patch-2","title":"Records and coffee",\
        "description":"Somebody brings a record, everybody listens to it.","location":"The Listening Room",\
        "starts_at":"\(instant(daysFromToday: 9))","timezone":"America/New_York",\
        "recurrence":"","visibility":"members","status":"active","image_url":"","image_alt":"","event_url":"",\
        "node_name":"The Listening Room","node_slug":"listening-room","node_status":"unclaimed"}
        """
        return [("demo-event", tonight), ("demo-event-2", soon), ("demo-event-3", later)]
    }

    /// The offline stand-in for `events/{id}/event.ics`, so the share
    /// fallback has a file to hand over with no network.
    static func calendarFile(_ id: String) -> Data {
        let stamp = instant(daysFromToday: 0, hour: tonightHour)
            .replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")
        return Data("""
        BEGIN:VCALENDAR\r
        PRODID:-//Patchwork//quilt.example.org//EN\r
        VERSION:2.0\r
        BEGIN:VEVENT\r
        UID:\(id)@quilt.example.org\r
        SUMMARY:Saturday open studio\r
        DTSTART:\(stamp)\r
        END:VEVENT\r
        END:VCALENDAR\r
        """.utf8)
    }

    /// The feed the way the server serves it: `starts_at` compared as text
    /// against the `from`/`to` instants, ascending, so the date presets
    /// behave offline the way they do against a quilt.
    private static func eventsPage(_ query: [URLQueryItem]) -> String {
        let value = { (name: String) in query.first { $0.name == name }?.value ?? "" }
        let slug = value("node_slug"), from = value("from"), to = value("to")
        // `scope=my` is the one narrowing that is about the reader rather than
        // the quilt: the patches they hold an active row on, and no others.
        let mine = value("scope") == "my" ? heldNodeIds : nil
        let items = events.map(\.json).filter { json in
            if !slug.isEmpty && !json.contains("\"node_slug\":\"\(slug)\"") { return false }
            if let mine, !mine.contains(where: { json.contains("\"node_id\":\"\($0)\"") }) { return false }
            guard let range = json.range(of: "\"starts_at\":\"") else { return true }
            let rest = json[range.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { return true }
            let startsAt = String(rest[..<end])
            if !from.isEmpty && startsAt < from { return false }
            if !to.isEmpty && startsAt > to { return false }
            return true
        }
        return "{\"items\":[\(items.joined(separator: ","))],\"next_cursor\":\"\"}"
    }

    // MARK: The signed-in half

    /// Whether the fictional reader is signed in. In preview there is no
    /// cookie jar to consult, so this stands in for the cookie itself — set by
    /// a verified code, cleared by signing out, and gone at the next launch,
    /// which is what a fixture should be.
    static var signedIn = false
    /// The account the fixtures name. `auth/signup` replaces it with the
    /// username the person chose, so the menu shows their word and not ours.
    static var account = #"{"id":"demo-user","username":"samplereader","display_name":"Sample Reader","role":"member"}"#
    private static let sampleAccount = account

    /// The two patches a membership can be held on offline, with the facts the
    /// relationship rules read: whether it is public, and how it takes
    /// members. Common Thread approves; the Listening Room admits anyone.
    private static let holdable: [(slug: String, id: String, name: String, blurb: String, visibility: String, policy: String)] = [
        ("common-thread", "demo-patch", "Common Thread Studio",
         "A place to make things and meet your neighbors.", "public", "approval_required"),
        ("listening-room", "demo-patch-2", "The Listening Room",
         "Independent music in good company.", "public", "open"),
    ]

    /// The membership set the writes mutate and `me/nodes`, `nodes/{slug}` and
    /// `events?scope=my` all read back. A signed-in reader starts out
    /// following the Listening Room and nothing else: enough for the Dashboard
    /// to have something in it on arrival, and every other act still to make.
    private static var held: [String: (role: String, status: String)] = [:]

    static func signOut() {
        signedIn = false
        account = sampleAccount
        held = [:]
        notifications = []
    }
    private static func startSession() {
        signedIn = true
        held = ["listening-room": (role: "follower", status: "active")]
        notifications = Self.freshNotifications
    }

    // MARK: The bell

    /// One row of the notifications list, as the fixtures hold it. A row is
    /// mutable here because the writes actually mutate it: marking one read,
    /// dismissing it and clearing the lot all change what the next `GET`
    /// answers, which is the only way the badge's arithmetic can be exercised
    /// with no network.
    private struct Notif {
        let id: String
        let type: String
        let title: String
        let body: String
        let link: String
        /// How long ago it arrived, so the relative column reads as a column
        /// rather than as six copies of the same word.
        let minutesAgo: Int
        var read: Bool
    }

    /// Six rows across the categories, newest first — the order the server
    /// serves them in (`ORDER BY id DESC`). Two are unread, one points at a
    /// patch, one at an event, one at a proposal, one at a charter, one at
    /// the noticeboard (which this client does not draw, so it is an exit to
    /// the website), and the warning carries no link at all, because there is
    /// nowhere in this app to send somebody about one.
    private static var freshNotifications: [Notif] {
        [
            Notif(id: "notif-6", type: "proposal.voting_opened",
                  title: "A proposal needs your vote",
                  body: "Add a Tuesday evening session — voting closes on the 24th.",
                  link: "/patches/common-thread/governance/proposals/demo-proposal",
                  minutesAgo: 4, read: false),
            Notif(id: "notif-5", type: "event.reminder",
                  title: "Saturday open studio is tomorrow",
                  body: "Common Thread Studio, 12 Example Street, 6pm.",
                  link: "/events/demo-event",
                  minutesAgo: 3 * 60, read: false),
            Notif(id: "notif-4", type: "membership.request_approved",
                  title: "You’re a member of Common Thread Studio",
                  body: "Rowan Hale approved your request to join.",
                  link: "/patches/common-thread",
                  minutesAgo: 2 * 24 * 60, read: true),
            Notif(id: "notif-3", type: "governance.document_amended",
                  title: "“How we decide” was amended",
                  body: "Common Thread Studio published version 3 of its charter.",
                  link: "/patches/common-thread/governance/docs/demo-doc",
                  minutesAgo: 5 * 24 * 60, read: true),
            Notif(id: "notif-2", type: "notice.posted",
                  title: "A new notice on Common Thread Studio’s board",
                  body: "The kiln is out of action until the part arrives.",
                  link: "/patches/common-thread/noticeboard/x",
                  minutesAgo: 9 * 24 * 60, read: true),
            Notif(id: "notif-1", type: "account.warned",
                  title: "A moderator sent you a warning",
                  body: "Warnings are read and answered on the quilt’s website.",
                  link: "",
                  minutesAgo: 40 * 24 * 60, read: true),
        ]
    }

    /// The set the writes mutate. Empty while signed out, which is what makes
    /// a signed-out fixture exactly what it was before this slice.
    private static var notifications: [Notif] = []

    /// The server's own category table (`internal/handler/notifications.go`).
    /// Moderation is the one that is not a single prefix, and it deliberately
    /// leaves `account.email_changed` out: an address change is account
    /// security, not a moderation outcome.
    private static func inCategory(_ category: String, _ row: Notif) -> Bool {
        switch category {
        case "proposals": return row.type.hasPrefix("proposal.")
        case "governance": return row.type.hasPrefix("governance.")
        case "membership": return row.type.hasPrefix("membership.")
        case "events": return row.type.hasPrefix("event.")
        case "moderation":
            return row.type.hasPrefix("report.")
                || ["account.warned", "account.suspended", "account.unsuspended"].contains(row.type)
        default: return false
        }
    }

    private static func json(_ row: Notif) -> String {
        let created = stamp(minutesAgo: row.minutesAgo)
        // Read rows carry `read_at`; unread rows carry no such key at all,
        // which is the server's shape and the one this client reads.
        let readAt = row.read ? ",\"read_at\":\"\(stamp(minutesAgo: max(0, row.minutesAgo - 1)))\"" : ""
        return "{\"id\":\"\(row.id)\",\"user_id\":\"demo-user\",\"type\":\"\(row.type)\"," +
            "\"title\":\"\(row.title)\",\"body\":\"\(row.body)\",\"link\":\"\(row.link)\"\(readAt)," +
            "\"created_at\":\"\(created)\"}"
    }

    private static func stamp(minutesAgo: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date().addingTimeInterval(TimeInterval(-minutesAgo * 60)))
    }

    /// `GET notifications`, with the three narrowings the list sends.
    private static func notificationsPage(_ query: [URLQueryItem]) -> String {
        let value = { (name: String) in query.first { $0.name == name }?.value ?? "" }
        let limit = Int(value("limit")) ?? 20
        var rows = notifications
        if value("unread") == "true" { rows = rows.filter { !$0.read } }
        let category = value("category")
        if !category.isEmpty { rows = rows.filter { inCategory(category, $0) } }
        // The server pages on `id < after`, newest first. The fixtures are
        // already in that order, so the cursor is the row after the one named.
        let after = value("after")
        if !after.isEmpty, let index = rows.firstIndex(where: { $0.id == after }) {
            rows = Array(rows.suffix(from: rows.index(after: index)))
        }
        let page = Array(rows.prefix(limit))
        let cursor = rows.count > limit ? (page.last?.id ?? "") : ""
        return "{\"items\":[\(page.map(json).joined(separator: ","))],\"next_cursor\":\"\(cursor)\"}"
    }

    /// The four writes the bell's sheet makes, against the set above. Nil
    /// means "not a notifications path", so the membership writes keep their
    /// own road through `post`.
    private static func notificationWrite(_ method: String, _ path: String) throws -> String? {
        guard path == "notifications" || path.hasPrefix("notifications/") else { return nil }
        guard signedIn else { throw APIError.unauthenticated }
        let parts = path.split(separator: "/").map(String.init)
        switch (method, parts.count) {
        case ("POST", 2) where parts[1] == "read-all":
            // Everything, not the page in view.
            notifications = notifications.map { row in
                var read = row
                read.read = true
                return read
            }
            return "{}"
        case ("PATCH", 3) where parts[2] == "read":
            guard let index = notifications.firstIndex(where: { $0.id == parts[1] }) else { throw APIError.status(404) }
            notifications[index].read = true
            return "{}"
        case ("DELETE", 2):
            guard notifications.contains(where: { $0.id == parts[1] }) else { throw APIError.status(404) }
            notifications.removeAll { $0.id == parts[1] }
            return "{}"
        case ("DELETE", 1):
            // Clears everything server-side, not just what is listed.
            notifications = []
            return "{}"
        default:
            throw APIError.status(404)
        }
    }

    /// `GET me/nodes`. Active and pending rows only, and a pending row carries
    /// no role — the server's own rule, kept here so the client is checked
    /// against it rather than against a convenience.
    private static var myNodes: String {
        let rows = holdable.compactMap { patch -> String? in
            guard let row = held[patch.slug] else { return nil }
            let role = row.status == "active" ? ",\"role\":\"\(row.role)\"" : ""
            return "{\"id\":\"membership-\(patch.slug)\",\"user_id\":\"demo-user\",\"node_id\":\"\(patch.id)\"\(role)," +
                "\"status\":\"\(row.status)\",\"visible\":true,\"joined_at\":\"2026-09-01T10:00:00Z\"," +
                "\"node_name\":\"\(patch.name)\",\"node_slug\":\"\(patch.slug)\",\"node_description\":\"\(patch.blurb)\"," +
                "\"node_visibility\":\"\(patch.visibility)\",\"membership_policy\":\"\(patch.policy)\",\"node_status\":\"active\"}"
        }
        return "{\"items\":[\(rows.joined(separator: ","))]}"
    }

    /// Which node ids the reader holds an active row on — what `scope=my`
    /// narrows the feed to.
    private static var heldNodeIds: Set<String> {
        Set(holdable.filter { held[$0.slug]?.status == "active" }.map(\.id))
    }

    /// One node's JSON with its relationship fields spliced in. The tree is
    /// left exactly as it was: the quilt's public shape is the same whoever
    /// is reading it.
    private static func node(_ json: String, slug: String) -> String {
        String(json.dropLast()) + relation(slug) + "}"
    }

    /// What `nodes/{slug}` adds. The policy is the patch's own and is always
    /// stated; the four relationship fields exist only where there is a
    /// session, which is exactly the server's shape — and is what keeps every
    /// signed-out fixture what it was.
    private static func relation(_ slug: String) -> String {
        guard let patch = holdable.first(where: { $0.slug == slug }) else { return "" }
        var fields = ",\"membership_policy\":\"\(patch.policy)\""
        guard signedIn else { return fields }
        let row = held[slug]
        let active = row?.status == "active"
        fields += ",\"is_banned\":false,\"is_member\":\(active),\"is_admin\":\(active && row?.role == "admin")"
        if active, let role = row?.role { fields += ",\"membership_role\":\"\(role)\"" }
        return fields
    }

    /// The three membership writes, against the set above. Every refusal is
    /// one the server actually makes, in the server's own words.
    private static func membershipPost(_ path: String, fields: [String: Any]) throws -> String {
        let parts = path.split(separator: "/")
        guard parts.count == 3, parts[0] == "nodes",
              let patch = holdable.first(where: { $0.slug == String(parts[1]) }) else { throw APIError.status(404) }
        guard signedIn else { throw APIError.unauthenticated }
        let slug = patch.slug
        switch parts[2] {
        case "join":
            if (fields["role"] as? String) == "follower" {
                guard patch.visibility == "public" else { throw APIError.message("can only follow public patches", status: 403) }
                guard held[slug] == nil else { throw APIError.message("already following", status: 409) }
                held[slug] = (role: "follower", status: "active")
                return "{\"status\":\"active\",\"membership_id\":\"membership-\(slug)\"}"
            }
            guard held[slug]?.status != "pending" else { throw APIError.message("a request is already pending", status: 409) }
            guard held[slug]?.role == nil || held[slug]?.role == "follower" else { throw APIError.message("already a member", status: 409) }
            // `approval_required` asks; `open` admits. A follower who joins is
            // upgraded in place rather than doubled.
            let status = patch.policy == "approval_required" ? "pending" : "active"
            held[slug] = (role: "member", status: status)
            return "{\"status\":\"\(status)\",\"membership_id\":\"membership-\(slug)\"}"
        case "leave":
            guard held[slug]?.status == "active" else { throw APIError.message("not a member", status: 400) }
            held[slug] = nil
            return #"{"status":"ok"}"#
        case "withdraw":
            guard held[slug]?.status == "pending" else { throw APIError.message("no pending request", status: 400) }
            held[slug] = nil
            return #"{"status":"ok"}"#
        default:
            throw APIError.status(404)
        }
    }

    /// The offline stand-in for every non-GET. The JSON is returned as text so
    /// a write with nothing to read (`auth/logout`, marking a notification
    /// read) runs the same path as one with a user in the answer.
    ///
    /// `PATCH` and `DELETE` arrived with the notifications list and belong to
    /// it alone, so they are answered first and everything else is still a
    /// `POST`.
    static func write(_ method: String, _ path: String, body: Data?) throws -> String {
        if let answer = try notificationWrite(method, path) { return answer }
        guard method == "POST" else { throw APIError.status(405) }
        return try post(path, body: body ?? Data())
    }

    private static func post(_ path: String, body: Data) throws -> String {
        let fields = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        switch path {
        case "auth/magic-link":
            return #"{"status":"ok"}"#
        case "auth/magic-link/verify":
            switch (fields["code"] as? String) ?? "" {
            case "123456":
                startSession()
                account = sampleAccount
                return account
            // The address with no account yet: the other half of the flow.
            case "654321":
                return #"{"status":"username_required","signup_token":"demo-signup"}"#
            default:
                throw APIError.message("invalid or expired code", status: 400)
            }
        case "auth/signup":
            let username = ((fields["username"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let display = ((fields["display_name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !username.isEmpty else { throw APIError.message("Choose a username.", status: 400) }
            startSession()
            account = "{\"id\":\"demo-user\",\"username\":\"\(username)\",\"display_name\":\"\(display)\",\"role\":\"member\"}"
            return account
        case "auth/logout":
            signOut()
            return "{}"
        default:
            return try membershipPost(path, fields: fields)
        }
    }

    static func response<T: Decodable>(_ path: String, query: [URLQueryItem] = []) throws -> T {
        let patch = #"{"id":"demo-patch","name":"Common Thread Studio","slug":"common-thread","description":"A place to make things and meet your neighbors. Open studio evenings, shared tools, and room for your next idea.","tags":["craft","community"],"member_count":12,"follower_count":34,"upcoming_event_count":4,"appearance":{"palette":"anthem","block":"ohioStar","rotation":90,"icon":"scissors"},"address":"12 Example Street","latitude":40.04,"longitude":-76.3,"website":"https://commonthread.example.org","links":[{"url":"https://makers.example.org/common-thread","label":"Our makers’ directory"}],"did":"did:web:commonthread.example.org","visibility":"public","public_member_list":"everyone","public_governance_record":"everyone"}"#
        let second = ##"{"id":"demo-patch-2","name":"The Listening Room","slug":"listening-room","description":"Independent music in good company.","tags":["music","venue"],"visibility":"public","public_member_list":"nobody","public_governance_record":"nobody","member_count":8,"follower_count":15,"appearance":{"block":{"grid":3,"colors":{"0,1":[1],"0,2":[2],"1,0":[1],"1,2":[1],"2,0":[2],"2,1":[1]}},"rotation":0,"bundle":["#2E7D5B","#204B4B","#D9D6AF","#D89E13"]}}"##
        let names = ["Community Garden", "Bike Kitchen", "Neighborhood Books", "River Walkers", "Pottery Circle", "Market Friends", "Repair Cafe", "Film Club", "Food Share", "Evening Choir"]
        let extras = names.enumerated().map { index, name in
            // One patch has left this quilt, so a list has something to wear
            // the Moved chip on (web ADR 090).
            let moved = index == 4 ? ",\"moved_to\":\"https://neighbor.example.org/patches/pottery-circle\"" : ""
            return "{\"id\":\"extra-\(index)\",\"name\":\"\(name)\",\"slug\":\"extra-\(index)\",\"tags\":[\"\(index % 2 == 0 ? "community" : "music")\"],\"member_count\":\(index + 1)\(index == 3 ? ",\"is_unclaimed\":true" : "")\(moved)}"
        }
        let members = #"{"items":[{"id":"m1","user_id":"u1","role":"admin","username":"rowan","display_name":"Rowan Hale"},{"id":"m2","user_id":"u2","role":"member","username":"imani","display_name":"Imani Osei"},{"id":"m3","user_id":"u3","role":"member","username":"theo"},{"id":"m4","user_id":"u4","role":"follower","username":"nobody-should-see-this"}],"next_cursor":"","member_count":12,"follower_count":34,"public_member_list":"everyone"}"#
        let withheldMembers = #"{"items":[],"next_cursor":"","member_count":8,"follower_count":15,"public_member_list":"nobody"}"#
        let document = #"{"id":"demo-doc","node_id":"demo-patch","title":"How we decide","body":"This patch keeps its own copy of the shared standards, and adds one paragraph of its own.\n\n## Open studio hours\n\nAnyone may use the studio during open hours. Tools go back where they were found, and whoever is last out locks the door.\n\n## Changing this\n\nAny member may propose a change. A majority carries it.","kind":"charter","visibility":"public","version":3,"created_at":"2026-04-02T10:00:00Z","updated_at":"2026-08-14T10:00:00Z"}"#
        let lining = #"{"id":"demo-lining","node_id":"demo-patch","title":"Community Standards","body":"Every patch on this quilt starts by agreeing to the lining. This patch amended it.\n\n## Keep each other safe\n\nNobody is harmed, excluded, or diminished for who they are.","kind":"lining","visibility":"public","version":2,"created_at":"2026-03-01T10:00:00Z","updated_at":"2026-07-21T10:00:00Z"}"#
        let proposal = #"{"id":"demo-proposal","title":"Add a Tuesday evening session","body":"Saturdays fill up. A second session on Tuesdays would let people who work weekends take part.","status":"open","state":"voting","proposal_type":"action","author_name":"Imani Osei","created_at":"2026-09-10T12:00:00Z","voting_ends_at":"2026-09-24T12:00:00Z","approve_count":5,"reject_count":1,"abstain_count":0}"#
        let lapsed = #"{"id":"demo-proposal-2","title":"Buy a second kiln","status":"rejected","state":"lapsed","proposal_type":"action","author_name":"Rowan Hale","created_at":"2026-06-01T12:00:00Z","approve_count":2,"reject_count":0,"abstain_count":0}"#
        let overview = #"{"rules":{"decision_method":"majority","quorum_percent":20,"default_vote_duration_hours":336,"leadership_model":"maintainer","leadership_venue":"patchwork","proposal_venue":"patchwork","inactivity_days":90,"max_admins":3},"admins":[{"user_id":"u1","username":"rowan","display_name":"Rowan Hale","joined_at":"2026-01-14T10:00:00Z"}],"admins_withheld":false,"proposals_withheld":false,"election":null,"seats":[],"next_term_end":"","next_contest_opens":"","membership_policy":"open","member_count":12,"document_count":2,"open_proposals":1,"passed_proposals":3,"rejected_proposals":1,"needs_vote":0}"#
        let withheldOverview = #"{"rules":{"decision_method":"admin","leadership_model":"maintainer","leadership_venue":"patchwork","proposal_venue":"patchwork"},"admins":[],"admins_withheld":true,"proposals_withheld":true,"election":null,"seats":[],"next_term_end":"","next_contest_opens":"","membership_policy":"invite_only","member_count":8,"document_count":0,"open_proposals":0,"passed_proposals":0,"rejected_proposals":0,"needs_vote":0}"#
        let record = #"{"items":[{"kind":"vote","at":"2026-08-14T12:00:00Z","title":"Amend the studio hours","link":"/patches/common-thread/governance/demo-proposal-3","outcome":"carried"},{"kind":"vote","at":"2026-06-08T12:00:00Z","title":"Buy a second kiln","outcome":"lapsed"},{"kind":"direct","at":"2026-04-02T12:00:00Z","title":"Publish the charter","outcome":"applied","actor":"Rowan Hale"}],"public_governance_record":"everyone"}"#
        let json: String
        switch path {
        case "instance": json = #"{"name":"Sample quilt","description":"A fictional quilt for exploring the native app.","geography":{"timezone":"America/New_York"},"neighbor_quilts":[{"name":"Neighbor quilt","url":"https://neighbor.example.org"}],"stats":{"node_count":12,"event_count":34,"member_count":5},"version":"v0.0.0-preview","submissions_enabled":true}"#
        case "label": json = ###"{"published":true,"stewards":[{"username":"samplesteward","display_name":"Sample Steward","avatar_url":"","blurb":"Keeps the lights on and answers the email."}],"prose":"## Why this exists\n\nThis quilt is fictional, and so is everything on this page. It is here so the app has something to draw.\n\n- No real money changes hands.\n- No real person is named.","cost_items":[{"service":"Sample Hosting","purpose":"the server (where all this lives)","why":"invented, for the preview","amount_minor":1200,"period":"monthly"},{"service":"Sample Domain","purpose":"the address","why":"also invented","amount_minor":1800,"period":"yearly"}],"currency":"USD","total_monthly_minor":1350,"stale":true,"stated_on":"2026-01-01","version":"v0.0.0-preview","federation":false,"multi_quilt":false,"support_url":"https://example.org/support","feedback_url":"https://example.org/feedback","seamripped_from_name":"","seamripped_from_url":""}"###
        case "instance/lining": json = ###"{"title":"Community Standards","body":"This fictional patch, like every patch on this fictional quilt, starts by agreeing to the lining.\n\n## Keep each other safe\n\nNobody is harmed, excluded, or diminished for who they are. We regulate actions, not identity.\n\n## Say what you are\n\nA patch describes itself honestly: who it is, what it does, and who it answers to.","version":1}"###
        case "legal/privacy": json = ###"{"doc":"privacy","title":"Privacy Policy","markdown":"## The short version\n\nNothing here is real, so nothing here is collected. This document exists so the app has a document to render.\n\n- No ads.\n- No trackers.","customized":true,"updated_at":"2026-01-01T00:00:00.000Z"}"###
        case "legal/terms": json = ###"{"doc":"terms","title":"User Agreement","markdown":"## The short version\n\nBe someone your community would vouch for. This fictional agreement has no force anywhere.","customized":false,"updated_at":"2026-01-01T00:00:00.000Z"}"###
        case "nodes/tree": json = "{\"tree\":{\"children\":[\(([patch, second] + extras).joined(separator: ","))]}}"
        // The node carries its own membership policy always, and who the
        // reader is to it only where there is a session (see `relation`).
        case "nodes/common-thread": json = "{\"node\":\(node(patch, slug: "common-thread")),\"is_unclaimed\":false,\"lining_status\":\"diverged\"}"
        case "nodes/listening-room": json = "{\"node\":\(node(second, slug: "listening-room")),\"is_unclaimed\":false,\"lining_status\":\"pristine\"}"
        case "me/nodes":
            guard signedIn else { throw APIError.unauthenticated }
            json = myNodes
        // The vocabulary answers with its own counts, which are the quilt's
        // whole-quilt public numbers rather than a tally of the tree in hand:
        // `craft` is worn by more patches than this fixture's tree holds, and
        // `archive` is a curated term nothing wears yet.
        case "auth/me":
            guard signedIn else { throw APIError.unauthenticated }
            json = account
        // The bell's two reads. Both are about the reader, so both are 401
        // while there is nobody to be about — a signed-out fixture makes
        // exactly the public reads it always did.
        case "notifications":
            guard signedIn else { throw APIError.unauthenticated }
            json = notificationsPage(query)
        case "notifications/count":
            guard signedIn else { throw APIError.unauthenticated }
            json = "{\"unread\":\(notifications.filter { !$0.read }.count)}"
        case "tags": json = #"[{"name":"craft","motif":"scissors","node_count":3},{"name":"music","motif":"musicNotes","node_count":6},{"name":"venue","motif":"buildings","node_count":1},{"name":"community","node_count":6},{"name":"archive","node_count":0}]"#
        case "events": json = eventsPage(query)
        case "nodes/common-thread/members": json = members
        case "nodes/listening-room/members": json = withheldMembers
        case "nodes/common-thread/governance": json = "{\"items\":[\(document),\(lining)],\"published_only\":true}"
        case "nodes/listening-room/governance": json = #"{"items":[],"published_only":true}"#
        case "nodes/common-thread/governance/overview": json = overview
        case "nodes/listening-room/governance/overview": json = withheldOverview
        case "nodes/common-thread/governance/record": json = record
        case "nodes/listening-room/governance/record": json = #"{"items":[],"public_governance_record":"nobody"}"#
        case "nodes/common-thread/proposals": json = "{\"items\":[\(proposal),\(lapsed)],\"next_cursor\":\"\",\"public_governance_record\":\"everyone\"}"
        case "nodes/listening-room/proposals": json = #"{"items":[],"next_cursor":"","public_governance_record":"nobody"}"#
        case "governance/demo-doc": json = document
        case "governance/demo-lining": json = lining
        case "proposals/demo-proposal": json = proposal
        case "proposals/demo-proposal-2": json = lapsed
        default:
            if let event = events.first(where: { "events/\($0.id)" == path }) { json = event.json }
            else if let index = Int(path.replacingOccurrences(of: "nodes/extra-", with: "")), extras.indices.contains(index) { json = "{\"node\":\(extras[index])}" }
            else { throw APIError.status(404) }
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }
}
#endif
