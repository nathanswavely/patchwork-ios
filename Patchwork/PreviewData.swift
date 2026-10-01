// SPDX-License-Identifier: MPL-2.0

#if DEBUG
import Foundation
import UIKit

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
            + postedEvents.filter(\.active).map { (id: $0.id, json: $0.json) }
    }

    /// What `POST events` has made this launch. An active one joins the
    /// feed; a pending one is only ever answered by id, to its submitter.
    private static var postedEvents: [(id: String, json: String, active: Bool)] = []
    private static let extraMovedTo = "https://neighbor.example.org/patches/pottery-circle"

    /// `starts_at` as the feed compares it: text.
    private static func startsAt(_ json: String) -> String {
        guard let range = json.range(of: "\"starts_at\":\"") else { return "" }
        let rest = json[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return "" }
        return String(rest[..<end])
    }

    /// The fictional quilt's icon, drawn rather than shipped: a pinwheel
    /// block in the app's rust on cloth, at the side `instance/icon` serves.
    static func icon() -> Data {
        let side: CGFloat = 50, half: CGFloat = 25
        let cloth = UIColor(red: 0.96, green: 0.94, blue: 0.90, alpha: 1)
        let rust = UIColor(red: 0.72, green: 0.29, blue: 0.10, alpha: 1)
        let ink = UIColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1)
        let blades: [(CGPoint, CGPoint, CGPoint, UIColor)] = [
            (CGPoint(x: 0, y: 0), CGPoint(x: half, y: 0), CGPoint(x: half, y: half), rust),
            (CGPoint(x: half, y: 0), CGPoint(x: side, y: 0), CGPoint(x: side, y: half), ink),
            (CGPoint(x: side, y: half), CGPoint(x: side, y: side), CGPoint(x: half, y: side), rust),
            (CGPoint(x: 0, y: half), CGPoint(x: half, y: side), CGPoint(x: 0, y: side), ink),
        ]
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).pngData { context in
            cloth.setFill(); context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            for (a, b, c, color) in blades {
                let path = UIBezierPath()
                path.move(to: a); path.addLine(to: b); path.addLine(to: c); path.close()
                color.setFill(); path.fill()
            }
        }
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
            let startsAt = startsAt(json)
            if startsAt.isEmpty { return true }
            if !from.isEmpty && startsAt < from { return false }
            if !to.isEmpty && startsAt > to { return false }
            return true
        }
        // Ascending, as the server orders them, now that a posted event can
        // arrive after the fixtures that are later than it.
        .sorted { startsAt($0) < startsAt($1) }
        return "{\"items\":[\(items.joined(separator: ","))],\"next_cursor\":\"\"}"
    }

    // MARK: The signed-in half

    /// Whether the fictional reader is signed in. In preview there is no
    /// cookie jar to consult, so this stands in for the cookie itself — set by
    /// a verified code, cleared by signing out, and gone at the next launch,
    /// which is what a fixture should be.
    ///
    /// The one exception is a launch that asks for it: `--preview-resume`
    /// picks up the session and account the previous preview launch left,
    /// because "start on My Quilt" is a rule about a cold launch and a cold
    /// launch is the only place it can be seen. Every preview launch writes
    /// the snapshot; only a resuming one reads it, so no other test starts
    /// anywhere but signed out.
    static var signedIn = (resumed?["signedIn"] as? Bool) ?? false { didSet { persist() } }
    /// The account the fixtures name. `auth/signup` replaces it with the
    /// username the person chose, so the menu shows their word and not ours,
    /// and `PATCH auth/me` edits it in place.
    static var account = (resumed?["account"] as? String) ?? sampleAccount { didSet { persist() } }
    private static let sampleAccount = #"{"id":"demo-user","username":"samplereader","display_name":"Sample Reader","role":"member"}"#
    private static let snapshotKey = "preview-account-snapshot"
    private static let resumed: [String: Any]? = {
        guard ProcessInfo.processInfo.arguments.contains("--preview-resume") else { return nil }
        return UserDefaults.standard.dictionary(forKey: snapshotKey)
    }()
    private static func persist() {
        UserDefaults.standard.set(["signedIn": signedIn, "account": account], forKey: snapshotKey)
    }
    /// The account's fields as a dictionary, for the writes that edit them.
    private static var accountFields: [String: Any] {
        get { (try? JSONSerialization.jsonObject(with: Data(account.utf8))) as? [String: Any] ?? [:] }
        set {
            guard let data = try? JSONSerialization.data(withJSONObject: newValue, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else { return }
            account = text
        }
    }

    /// The patches a membership can be held on offline, with the facts the
    /// relationship rules read: whether it is public, and how it takes
    /// members. Common Thread approves; the Listening Room and the Repair
    /// Cafe admit anyone.
    private static let holdable: [(slug: String, id: String, name: String, blurb: String, visibility: String, policy: String)] = [
        ("common-thread", "demo-patch", "Common Thread Studio",
         "A place to make things and meet your neighbors.", "public", "approval_required"),
        ("listening-room", "demo-patch-2", "The Listening Room",
         "Independent music in good company.", "public", "open"),
        (memberSlug, memberSlug, extraNames[6], "", "public", "open"),
    ]

    /// The membership set the writes mutate and `me/nodes`, `nodes/{slug}` and
    /// `events?scope=my` all read back. A signed-in reader starts out
    /// following the Listening Room and a member of the Repair Cafe: enough
    /// for the Dashboard to have something in it on arrival, a patch the
    /// reader can only suggest an event to and one they post to directly,
    /// and every other act still to make. The membership is on one of the
    /// extras so the follow and join tests, which read the studio and the
    /// Listening Room, find both exactly as they were.
    private static var held: [String: (role: String, status: String)] = signedIn ? freshHeld : [:]
    private static var freshHeld: [String: (role: String, status: String)] {
        var rows: [String: (role: String, status: String)] = [
            "listening-room": (role: "follower", status: "active"),
            memberSlug: (role: "member", status: "active"),
        ]
        if governanceMember { rows["common-thread"] = (role: "member", status: "active") }
        return rows
    }
    /// The extra the fixture reader is a member of: the Repair Cafe.
    static let memberSlug = "extra-6"
    /// The quilt's other ten patches, by name; `extra-N` is the Nth.
    private static let extraNames = ["Community Garden", "Bike Kitchen", "Neighborhood Books", "River Walkers", "Pottery Circle", "Market Friends", "Repair Cafe", "Film Club", "Food Share", "Evening Choir"]

    static func signOut() {
        signedIn = false
        account = sampleAccount
        held = [:]
        notifications = []
        stepUpOpen = false
    }
    private static func startSession() {
        signedIn = true
        held = freshHeld
        notifications = Self.freshNotifications
        sessionRows = freshSessionRows
        // A new sign-in is younger than whatever batch the account already
        // holds, so that batch can confirm from now on (web ADR 099).
        batchPredatesSession = true
        stepUpOpen = false
    }

    // MARK: The account's own security

    /// The fixture reader's recovery codes: a set made before any preview
    /// session began, so every one of them can confirm a step-up and sign
    /// in. Printed the way the server prints them.
    static let recoveryCodes = [
        "abcd-efgh-jkm2", "npqr-stuv-wxy3", "zabc-defg-hjk4", "mnpq-rstu-vwx5", "yzab-cdef-ghj6",
        "kmnp-qrst-uvw7", "xyza-bcde-fgh8", "jkmn-pqrs-tuv9", "wxyz-abcd-efg2", "hjkm-npqr-stu3",
    ]
    /// The batch the account holds, normalised, and which of it is spent.
    /// Kept across sign-out, because on a quilt the codes are the account's
    /// and outlive any one session; reset only when the account is deleted.
    private static var batch = recoveryCodes.map(RecoveryCode.normalize)
    private static var spent = Set<String>()
    /// Whether the batch was made before the current session began. A batch
    /// generated during a preview session is too new to confirm anything
    /// until the next sign-in, exactly as on a quilt.
    private static var batchPredatesSession = true
    /// The five-minute window, as a flag.
    private static var stepUpOpen = false
    private static var unusedCodes: Int { batch.filter { !spent.contains($0) }.count }

    /// Two sessions: this one and a laptop.
    private static let freshSessionRows: [(id: String, label: String, current: Bool)] = [
        ("session-this", "iPhone", true),
        ("session-laptop", "Firefox on Linux", false),
    ]
    private static var sessionRows = freshSessionRows

    /// A refusal in the server's own shape, read the way a real one is.
    private static func refuse(_ status: Int, _ error: String, code: String? = nil, extra: String = "") -> APIError {
        let codeField = code.map { ",\"code\":\"\($0)\"" } ?? ""
        return APIError.from(status: status, data: Data("{\"error\":\"\(error)\"\(codeField)\(extra)}".utf8))
    }

    /// The account's writes: the profile, the codes, step-up, the session
    /// list, deletion and the recovery sign-in. Nil means "not one of
    /// these", so every other write keeps its own road.
    private static func accountWrite(_ method: String, _ path: String, fields: [String: Any]) throws -> String? {
        switch (method, path) {
        case ("POST", "auth/recovery"):
            // One sentence for every failure, as the server gives it.
            let username = ((fields["username"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let code = RecoveryCode.normalize((fields["code"] as? String) ?? "")
            guard username == "samplereader", batch.contains(code), !spent.contains(code) else {
                throw APIError.message("invalid username or recovery code", status: 400)
            }
            spent.insert(code)
            startSession()
            account = sampleAccount
            // Redeeming a code is itself the proof: the window opens on arrival.
            stepUpOpen = true
            return account
        default:
            break
        }
        let ours = path == "auth/me" || path == "users/me" || path.hasPrefix("auth/recovery-codes")
            || path.hasPrefix("auth/step-up") || path.hasPrefix("auth/sessions")
        guard ours else { return nil }
        guard signedIn else { throw APIError.unauthenticated }
        switch (method, path) {
        case ("PATCH", "auth/me"):
            var current = accountFields
            for key in ["display_name", "bio", "links", "start_on_my_quilt", "hide_amended_linings"] {
                if let value = fields[key] { current[key] = value }
            }
            accountFields = current
            return account
        case ("POST", "auth/recovery-codes"):
            let alphabet = Array(RecoveryCode.alphabet)
            let codes = (0..<10).map { _ in
                (0..<3).map { _ in String((0..<4).map { _ in alphabet.randomElement()! }) }.joined(separator: "-")
            }
            batch = codes.map(RecoveryCode.normalize)
            spent = []
            batchPredatesSession = false
            return "{\"codes\":[\(codes.map { "\"\($0)\"" }.joined(separator: ","))]}"
        case ("POST", "auth/step-up/recovery"):
            let code = RecoveryCode.normalize((fields["code"] as? String) ?? "")
            guard unusedCodes > 0 else {
                throw refuse(400, "this account has no unused recovery codes", code: "no_recovery_codes")
            }
            guard batchPredatesSession else {
                throw refuse(400, "these codes were made during this sign-in", code: "recovery_codes_too_new")
            }
            guard batch.contains(code), !spent.contains(code) else {
                throw refuse(400, "that recovery code is not one of yours, or has been used", code: "invalid_code")
            }
            spent.insert(code)
            stepUpOpen = true
            return "{\"active\":true,\"expires_at\":\"\(stamp(minutesAgo: -5))\",\"codes_remaining\":\(unusedCodes),\"used_recovery_code\":true}"
        case ("POST", "auth/sessions/revoke-others"):
            sessionRows = sessionRows.filter(\.current)
            return #"{"status":"ok"}"#
        case ("DELETE", "users/me"):
            // The route is step-up gated, and this reader has no passkey, so
            // the server's own refusal is the passkey-less one.
            guard stepUpOpen else {
                throw refuse(403, "This action needs a passkey. Enroll one in Security settings first.", code: "passkey_required")
            }
            let username = (accountFields["username"] as? String) ?? ""
            guard ((fields["confirm_username"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == username else {
                throw APIError.message("type your username exactly to confirm", status: 400)
            }
            signOut()
            batch = recoveryCodes.map(RecoveryCode.normalize)
            spent = []
            batchPredatesSession = true
            return #"{"status":"deleted"}"#
        default:
            if method == "DELETE", path.hasPrefix("auth/sessions/") {
                let id = String(path.dropFirst("auth/sessions/".count))
                guard sessionRows.contains(where: { $0.id == id }) else { throw APIError.message("session not found", status: 404) }
                sessionRows.removeAll { $0.id == id }
                return "{\"status\":\"ok\",\"was_current\":\(id == "session-this")}"
            }
            throw APIError.status(405)
        }
    }

    /// The two files a reader takes away, with the names the server gives them.
    static func download(_ path: String) throws -> Download {
        guard signedIn else { throw APIError.unauthenticated }
        switch path {
        case "users/me/export":
            let body = "{\"format\":\"patchwork-personal-export\",\"user\":\(account),\"memberships\":\(myNodes)}"
            return Download(data: Data(body.utf8), headers: ["content-disposition": #"attachment; filename="patchwork-samplereader.json""#])
        case "users/me/seamrip":
            // A zip's magic number and nothing else: enough to be a file a
            // share sheet can hand on, which is all the offline path checks.
            return Download(data: Data([0x50, 0x4B, 0x05, 0x06] + [UInt8](repeating: 0, count: 18)),
                            headers: ["content-disposition": #"attachment; filename="patchwork-member-seamrip.zip""#])
        default:
            throw APIError.status(404)
        }
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
    private static var notifications: [Notif] = signedIn ? freshNotifications : []

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

    // MARK: Posting an event

    /// What `CreateEvent` needs to know about the patch an event is for.
    private static func postingFacts(_ nodeId: String) -> (slug: String, name: String, unclaimed: Bool, accepts: Bool, movedTo: String)? {
        switch nodeId {
        case "demo-patch": return ("common-thread", "Common Thread Studio", false, false, "")
        case "demo-patch-2": return ("listening-room", "The Listening Room", false, true, "")
        default:
            guard nodeId.hasPrefix("extra-"), let index = Int(nodeId.dropFirst("extra-".count)),
                  extraNames.indices.contains(index) else { return nil }
            return (nodeId, extraNames[index], index == 3, true, index == 4 ? extraMovedTo : "")
        }
    }

    /// `POST events`, decided by the server's own rule in the server's own
    /// order: the image and the link, recurrence, the required three, the
    /// tier's spelling, the patch, then who may post directly. Everybody
    /// else's event is a suggestion — refused where the patch has moved or
    /// does not take them, and public whatever tier it asked for.
    private static func eventPost(_ fields: [String: Any]) throws -> String {
        guard signedIn else { throw APIError.unauthenticated }
        let text = { (key: String) in (fields[key] as? String) ?? "" }
        if let problem = EventPosting.imageProblem(url: text("image_url"), alt: text("image_alt")) { throw APIError.message(problem, status: 400) }
        if let problem = EventPosting.linkProblem(text("event_url")) { throw APIError.message(problem, status: 400) }
        if !text("recurrence").trimmingCharacters(in: .whitespaces).isEmpty {
            throw APIError.message("this quilt does not expand recurring events — add each date as its own event, or attach the calendar as an event source in the patch's settings", status: 400)
        }
        let nodeId = text("node_id"), title = text("title"), starts = text("starts_at")
        guard !nodeId.isEmpty, !title.isEmpty, !starts.isEmpty else {
            throw APIError.message("node_id, title, and starts_at are required", status: 400)
        }
        var visibility = text("visibility")
        if visibility.isEmpty { visibility = "public" }
        guard ["public", "followers", "members"].contains(visibility) else {
            throw APIError.message("visibility must be public, followers, or members", status: 400)
        }
        guard let target = postingFacts(nodeId) else { throw APIError.message("node not found", status: 404) }
        let role = held[target.slug].flatMap { $0.status == "active" ? $0.role : nil }
        // Members and admins of a claimed patch, the instance admin anywhere,
        // and a trusted contributor on an unclaimed one — which the fixture
        // reader is not. A follower is not a member.
        let direct = (accountFields["role"] as? String) == "admin"
            || (!target.unclaimed && (role == "member" || role == "admin"))
        var status = "active"
        if !direct {
            if !target.movedTo.isEmpty {
                throw refuse(403, "this patch has moved. Take part at its new home instead.", extra: ",\"moved_to\":\"\(target.movedTo)\"")
            }
            if !target.unclaimed && !target.accepts {
                throw APIError.message("this patch does not accept event suggestions", status: 403)
            }
            status = "pending_review"
            visibility = "public"
        }
        let id = "posted-\(postedEvents.count + 1)"
        var event: [String: Any] = [
            "id": id, "node_id": nodeId, "created_by": "demo-user", "title": title,
            "description": text("description"), "location": text("location"),
            "starts_at": starts, "timezone": "America/New_York", "recurrence": "", "visibility": visibility,
            "image_url": text("image_url").trimmingCharacters(in: .whitespaces),
            "image_alt": text("image_alt").trimmingCharacters(in: .whitespaces),
            "event_url": text("event_url").trimmingCharacters(in: .whitespaces), "status": status,
        ]
        if let ends = fields["ends_at"] as? String { event["ends_at"] = ends }
        // The 201 is the bare event; the list and `events/{id}` add the
        // patch's name, slug and status beside it.
        let answer = serialize(event)
        event["node_name"] = target.name
        event["node_slug"] = target.slug
        event["node_status"] = target.unclaimed ? "unclaimed" : "active"
        postedEvents.append((id: id, json: serialize(event), active: status == "active"))
        return answer
    }

    private static func serialize(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Governance

    /// A launch that asks for it (`--preview-member`) signs the fixture
    /// reader in holding a member row on Common Thread as well, which is
    /// where the proposals, the election and the discussion are. It is a
    /// switch rather than the default because the follow, join and My Quilt
    /// tests read the studio as a patch the reader is not in.
    private static let governanceMember = ProcessInfo.processInfo.arguments.contains("--preview-member")
    private static let me = "demo-user"
    private static var myName: String { (accountFields["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Sample Reader" }

    private struct FixtureBallot {
        var userId: String
        var name: String
        var username: String
        var value: String
        var counted = true
    }

    private struct FixtureCandidate {
        let id: String
        let userId: String
        let username: String
        let name: String
        var statement: String
        var approvers: Set<String>
    }

    /// One proposal as the fixtures hold it: the facts, the ballots, and for
    /// an election the slate. Every viewer field is worked out when it is
    /// read, for whoever is reading, the way `GetProposal` works it out.
    private struct FixtureProposal {
        let id: String
        let slug: String
        let nodeId: String
        let title: String
        let body: String
        var type = "action"
        let author: String
        let authorId: String
        var status = "open"
        var state = "voting"
        var createdMinutesAgo: Int
        /// Minutes from now; negative is past, nil is no clock at all.
        var endsInMinutes: Int?
        var ballots: [FixtureBallot] = []
        var eligible = 12
        var quorum = 20
        var method = "majority"
        var seats = 0
        var phase = ""
        var nominationsCloseInMinutes: Int?
        var candidates: [FixtureCandidate] = []
        var abstainers: Set<String> = []
        var isElection: Bool { seats > 0 }
    }

    private struct FixtureComment {
        let id: String
        var body: String
        let authorId: String
        let authorName: String
        let createdMinutesAgo: Int
        var editedMinutesAgo: Int?
        let parentId: String?
        var reactions: [String: Set<String>]
    }

    private static let day = 24 * 60

    private static var freshProposals: [FixtureProposal] {
        [
            FixtureProposal(
                id: "demo-proposal-7", slug: "common-thread", nodeId: "demo-patch", title: "Publish the charter",
                body: "The charter the founding members wrote, published as it stands.",
                author: "Rowan Hale", authorId: "u1", status: "approved", state: "in_effect",
                createdMinutesAgo: 180 * day, endsInMinutes: nil, method: "admin"),
            FixtureProposal(
                id: "demo-proposal-2", slug: "common-thread", nodeId: "demo-patch", title: "Buy a second kiln",
                body: "The kiln is booked solid. A second one would halve the wait.",
                author: "Rowan Hale", authorId: "u1", status: "rejected", state: "lapsed",
                createdMinutesAgo: 120 * day, endsInMinutes: -106 * day,
                ballots: [FixtureBallot(userId: "u1", name: "Rowan Hale", username: "rowan", value: "approve"),
                          FixtureBallot(userId: "u2", name: "Imani Osei", username: "imani", value: "approve")]),
            FixtureProposal(
                id: "demo-proposal-3", slug: "common-thread", nodeId: "demo-patch", title: "Amend the studio hours",
                body: "Open at ten on Saturdays rather than nine: nobody comes before ten.",
                author: "Imani Osei", authorId: "u2", status: "approved", state: "in_effect",
                createdMinutesAgo: 60 * day, endsInMinutes: -46 * day,
                ballots: [FixtureBallot(userId: "u1", name: "Rowan Hale", username: "rowan", value: "approve"),
                          FixtureBallot(userId: "u2", name: "Imani Osei", username: "imani", value: "approve"),
                          FixtureBallot(userId: "u3", name: "theo", username: "theo", value: "approve"),
                          FixtureBallot(userId: "u5", name: "Mara Quinn", username: "mara", value: "reject")]),
            FixtureProposal(
                id: "demo-proposal-5", slug: "common-thread", nodeId: "demo-patch", title: "Treasurer election",
                body: "The treasurer’s seat comes up for its yearly contest.",
                author: "Rowan Hale", authorId: "u1", createdMinutesAgo: 1 * day, endsInMinutes: nil,
                seats: 1, phase: "nominating", nominationsCloseInMinutes: 6 * day,
                candidates: [FixtureCandidate(id: "cand-rowan", userId: "u1", username: "rowan", name: "Rowan Hale",
                                              statement: "I have kept the books since the studio opened.", approvers: [])]),
            FixtureProposal(
                id: "demo-proposal-4", slug: "common-thread", nodeId: "demo-patch", title: "Studio council election",
                body: "Two council seats are up. The members approve as many candidates as they like, and the two most approved take the seats.",
                author: "Rowan Hale", authorId: "u1", createdMinutesAgo: 9 * day, endsInMinutes: 5 * day,
                seats: 2, phase: "voting", nominationsCloseInMinutes: -2 * day,
                candidates: [
                    FixtureCandidate(id: "cand-imani", userId: "u2", username: "imani", name: "Imani Osei",
                                     statement: "I have held the studio’s keys for two years and would like to keep the calendar honest.",
                                     approvers: ["u1", "u5", me]),
                    FixtureCandidate(id: "cand-mara", userId: "u5", username: "mara", name: "Mara Quinn",
                                     statement: "", approvers: ["u1", "u5"]),
                    FixtureCandidate(id: "cand-theo", userId: "u3", username: "theo", name: "theo",
                                     statement: "Tools, mostly.", approvers: ["u2"]),
                ]),
            FixtureProposal(
                id: "demo-proposal", slug: "common-thread", nodeId: "demo-patch", title: "Add a Tuesday evening session",
                body: "Saturdays fill up. A second session on Tuesdays would let people who work weekends take part.\n\n## What it costs\n\nNothing but a second set of keys.",
                author: "Imani Osei", authorId: "u2", createdMinutesAgo: 3 * day, endsInMinutes: 4 * day - 90,
                ballots: [FixtureBallot(userId: "u1", name: "Rowan Hale", username: "rowan", value: "approve"),
                          FixtureBallot(userId: "u2", name: "Imani Osei", username: "imani", value: "approve"),
                          FixtureBallot(userId: "u3", name: "theo", username: "theo", value: "approve"),
                          FixtureBallot(userId: "", name: "Hidden member", username: "", value: "approve"),
                          FixtureBallot(userId: "u5", name: "Mara Quinn", username: "mara", value: "reject"),
                          FixtureBallot(userId: "u9", name: "Sam Ortiz", username: "sam", value: "approve", counted: false)]),
            FixtureProposal(
                id: "demo-proposal-6", slug: "listening-room", nodeId: "demo-patch-2", title: "Move the listening night to Thursdays",
                body: "Wednesdays clash with the choir. Thursdays are free.",
                author: "Dee Ramos", authorId: "l1", createdMinutesAgo: 2 * day, endsInMinutes: 5 * day,
                ballots: [FixtureBallot(userId: "l1", name: "Dee Ramos", username: "dee", value: "approve"),
                          FixtureBallot(userId: "l2", name: "Ade Bello", username: "ade", value: "approve")],
                eligible: 5, quorum: 0),
        ]
    }

    private static var freshThreads: [String: [FixtureComment]] {
        [
            "demo-proposal": [
                FixtureComment(id: "comment-1", body: "I’d come on Tuesdays. Could we start at six, so people can come straight from work?",
                               authorId: "u2", authorName: "Imani Osei", createdMinutesAgo: 2 * day, parentId: nil,
                               reactions: ["\u{1F44D}": ["u1"], Discussion.heart: [me, "u3"]]),
                FixtureComment(id: "comment-2", body: "Happy to open up on the first few Tuesdays.",
                               authorId: me, authorName: "Sample Reader", createdMinutesAgo: 30 * 60, parentId: nil,
                               reactions: ["\u{1F389}": ["u2"]]),
                FixtureComment(id: "comment-3", body: "That would be a great help. Thank you.",
                               authorId: "u2", authorName: "Imani Osei", createdMinutesAgo: 20 * 60, parentId: "comment-2",
                               reactions: [:]),
            ],
            "demo-proposal-6": [
                FixtureComment(id: "comment-6", body: "Thursdays work for the regulars I’ve asked.",
                               authorId: "l2", authorName: "Ade Bello", createdMinutesAgo: 1 * day, parentId: nil,
                               reactions: ["\u{1F44D}": ["l1"]]),
            ],
        ]
    }

    private static var proposals: [FixtureProposal] = freshProposals
    private static var threads: [String: [FixtureComment]] = freshThreads
    private static var commentSerial = 100

    /// The reader's active role on a patch, or nothing.
    private static func role(_ slug: String) -> String? {
        guard signedIn, let row = held[slug], row.status == "active" else { return nil }
        return row.role
    }
    private static func inRoom(_ slug: String) -> Bool { ["member", "admin"].contains(role(slug) ?? "") }
    /// `follower_permissions.proposals`, as the node fixtures state it.
    private static func followersTakePart(_ slug: String) -> Bool { slug != "listening-room" }

    private static func instant(minutesFromNow minutes: Int?) -> Any {
        guard let minutes else { return NSNull() }
        return stamp(minutesAgo: -minutes)
    }

    /// The whole detail payload, for whoever is reading.
    private static func detailFields(_ p: FixtureProposal) -> [String: Any] {
        var fields = listFields(p)
        let reader = signedIn ? me : ""
        let open = p.status == "open" && p.state == "voting"
        fields["target_user_id"] = ""
        fields["target_user_name"] = ""
        fields["seats_contested"] = p.seats
        fields["nominations_close_at"] = p.isElection ? (instant(minutesFromNow: p.nominationsCloseInMinutes) as? String ?? "") : ""
        fields["election_phase"] = p.isElection ? (open ? p.phase : "closed") : ""
        fields["candidates"] = p.candidates
            .enumerated()
            .sorted { ($0.element.approvers.count, -$0.offset) > ($1.element.approvers.count, -$1.offset) }
            .map { _, c -> [String: Any] in
                var row: [String: Any] = ["id": c.id, "user_id": c.userId, "username": c.username, "display_name": c.name,
                                          "approvals": c.approvers.count, "approved_by_me": !reader.isEmpty && c.approvers.contains(reader),
                                          "seated": false]
                if !c.statement.isEmpty { row["statement"] = c.statement }
                return row
            }
        if p.isElection {
            let voted = p.candidates.reduce(into: p.abstainers) { $0.formUnion($1.approvers) }.count
            let needed = VoteRules.quorumNeeded(eligible: p.eligible, percent: p.quorum)
            fields["election_turnout"] = ["voted": voted, "eligible": p.eligible, "needed": needed, "met": voted >= needed]
        } else {
            fields["election_turnout"] = NSNull()
        }
        fields["i_abstained"] = !reader.isEmpty && p.abstainers.contains(reader)
        fields["voters"] = p.ballots.map { b -> [String: Any] in
            ["user_id": b.userId, "display_name": b.name, "username": b.username, "value": b.value, "counted": b.counted]
        }
        fields["my_vote"] = p.ballots.first { !reader.isEmpty && $0.userId == reader }?.value ?? ""
        fields["eligible_voters"] = p.eligible
        fields["can_vote"] = open && inRoom(p.slug)
        fields["voting_terms"] = [
            "decision_method": p.method, "quorum_percent": p.quorum, "default_vote_duration_hours": 168,
            "amendment_threshold": "", "amendment_auto_apply": false, "succession_policy": "", "min_voting_tenure_days": 0,
        ] as [String: Any]
        fields["tenure_days"] = 0
        fields["vote_eligible_at"] = ""
        fields["applied_at"] = p.state == "in_effect" ? stamp(minutesAgo: p.createdMinutesAgo - day) : ""
        fields["advisory"] = false
        fields["can_decide"] = false
        fields["declined_by"] = ""
        return fields
    }

    /// A list row: no viewer fields and no election's slate, as the list sends.
    private static func listFields(_ p: FixtureProposal) -> [String: Any] {
        let counted = p.ballots.filter(\.counted)
        return [
            "id": p.id, "node_id": p.nodeId, "author_id": p.authorId, "title": p.title, "body": p.body,
            "status": p.status, "state": p.state, "proposal_type": p.type, "duration_hours": 168,
            "voting_ends_at": instant(minutesFromNow: p.endsInMinutes),
            "created_at": stamp(minutesAgo: p.createdMinutesAgo), "updated_at": stamp(minutesAgo: p.createdMinutesAgo),
            "author_name": p.author,
            "approve_count": counted.filter { $0.value == "approve" }.count,
            "reject_count": counted.filter { $0.value == "reject" }.count,
            "abstain_count": counted.filter { $0.value == "abstain" }.count,
        ]
    }

    /// `GET nodes/{slug}/proposals`, filtered the server's way and newest first.
    private static func proposalPage(_ slug: String, _ query: [URLQueryItem]) -> String {
        let filter = query.first { $0.name == "status" }?.value ?? ""
        let rows = proposals.filter { $0.slug == slug }.filter { p in
            switch filter {
            case "", "all": return true
            case "open": return p.status == "open"
            case "approved": return p.status == "approved"
            case "rejected": return p.status == "rejected" && !["lapsed", "unsettled"].contains(p.state)
            case "not_decided": return ["lapsed", "unsettled"].contains(p.state)
            default: return p.status == filter
            }
        }
        .sorted { $0.createdMinutesAgo < $1.createdMinutesAgo }
        let limit = Int(query.first { $0.name == "limit" }?.value ?? "") ?? 20
        let items = rows.prefix(limit).map { serialize(listFields($0)) }
        return "{\"items\":[\(items.joined(separator: ","))],\"next_cursor\":\"\",\"public_governance_record\":\"everyone\"}"
    }

    /// The overview's live half: what is open, what needs this reader, and
    /// the contest taking names.
    private static func overviewJSON(_ slug: String, base: String) -> String {
        guard var object = (try? JSONSerialization.jsonObject(with: Data(base.utf8))) as? [String: Any] else { return base }
        let mine = proposals.filter { $0.slug == slug }
        object["open_proposals"] = mine.filter { $0.status == "open" }.count
        object["needs_vote"] = mine.filter { p in
            guard p.status == "open", p.state == "voting", inRoom(slug) else { return false }
            if p.isElection { return p.phase == "voting" && !p.candidates.contains { $0.approvers.contains(me) } && !p.abstainers.contains(me) }
            return !p.ballots.contains { $0.userId == me }
        }.count
        if let election = mine.first(where: { $0.isElection && $0.phase == "nominating" && $0.status == "open" }) {
            object["election"] = ["id": election.id, "phase": "nominating", "seats": election.seats,
                                  "nominations_close_at": instant(minutesFromNow: election.nominationsCloseInMinutes),
                                  "candidates": election.candidates.count] as [String: Any]
        }
        return serialize(object)
    }

    private static func commentJSON(_ c: FixtureComment, replies: [FixtureComment]) -> [String: Any] {
        let reader = signedIn ? me : ""
        let reactions = Discussion.emoji.compactMap { emoji -> [String: Any]? in
            guard let holders = c.reactions[emoji], !holders.isEmpty else { return nil }
            return ["emoji": emoji, "count": holders.count, "me": !reader.isEmpty && holders.contains(reader)]
        }
        return [
            "id": c.id, "body": c.body, "author_name": c.authorName, "author_id": c.authorId,
            "created_at": stamp(minutesAgo: c.createdMinutesAgo),
            "updated_at": stamp(minutesAgo: c.editedMinutesAgo ?? c.createdMinutesAgo),
            "parent_id": c.parentId.map { $0 as Any } ?? NSNull(),
            "replies": replies.map { commentJSON($0, replies: []) },
            "reactions": reactions,
        ]
    }

    private static func threadJSON(_ id: String) -> String {
        let all = threads[id] ?? []
        let top = all.filter { $0.parentId == nil }
        let items = top.map { c in serialize(commentJSON(c, replies: all.filter { $0.parentId == c.id })) }
        return "{\"items\":[\(items.joined(separator: ","))]}"
    }

    /// A proposal a reader outside the room cannot read answers 404, as
    /// `GetProposal` does for a closed record.
    private static func readable(_ p: FixtureProposal) -> Bool { p.slug != "extra-1" }

    private static func proposalIndex(_ id: String) throws -> Int {
        guard let index = proposals.firstIndex(where: { $0.id == id }) else { throw APIError.message("proposal not found", status: 404) }
        return index
    }

    private static func commentLocation(_ id: String) throws -> (proposal: String, index: Int) {
        for (proposal, rows) in threads {
            if let index = rows.firstIndex(where: { $0.id == id }) { return (proposal, index) }
        }
        throw APIError.message("comment not found", status: 404)
    }

    /// Who may comment and react: an active role, and a follower only where
    /// the patch lets followers take part.
    private static func mayDiscuss(_ slug: String) throws {
        guard let role = role(slug) else { throw APIError.message("must be member of node", status: 403) }
        if role == "follower" && !followersTakePart(slug) {
            throw APIError.message("this patch does not include followers in its proposals", status: 403)
        }
    }

    /// The governance writes, in the server's order of refusals. Nil means
    /// "not one of these".
    private static func governanceWrite(_ method: String, _ path: String, fields: [String: Any]) throws -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "proposals" || parts[0] == "comments" else { return nil }
        guard signedIn else { throw APIError.unauthenticated }
        if parts[0] == "proposals" {
            let index = try proposalIndex(parts[1])
            var p = proposals[index]
            switch (method, Array(parts.dropFirst(2))) {
            case ("POST", ["vote"]):
                guard p.status == "open" else { throw APIError.message("proposal is not open for voting", status: 400) }
                guard inRoom(p.slug) else { throw APIError.message("must be member of node to vote", status: 403) }
                let value = (fields["value"] as? String) ?? ""
                guard ["approve", "reject", "abstain"].contains(value) else {
                    throw APIError.message("value must be approve, reject, or abstain", status: 400)
                }
                p.ballots.removeAll { $0.userId == me }
                p.ballots.append(FixtureBallot(userId: me, name: myName, username: "samplereader", value: value))
                proposals[index] = p
                return "{\"status\":\"ok\",\"vote_id\":\"vote-\(p.ballots.count)\"}"
            case ("PUT", ["ballot"]):
                guard p.isElection else { throw APIError.message("election not found", status: 404) }
                guard p.status == "open" else { throw APIError.message("this election has closed", status: 409) }
                guard p.phase == "voting" else { throw APIError.message("nominations are still open; voting has not started", status: 409) }
                guard inRoom(p.slug) else { throw APIError.message("must be member of node to vote", status: 403) }
                let ids = (fields["candidate_ids"] as? [String]) ?? []
                let abstain = (fields["abstain"] as? Bool) ?? false
                if abstain && !ids.isEmpty {
                    throw APIError.message("a ballot either approves candidates or approves nobody, not both", status: 400)
                }
                for i in p.candidates.indices {
                    if ids.contains(p.candidates[i].id) { p.candidates[i].approvers.insert(me) } else { p.candidates[i].approvers.remove(me) }
                }
                if abstain { p.abstainers.insert(me) } else { p.abstainers.remove(me) }
                proposals[index] = p
                return "{\"approved\":\(ids.count),\"abstain\":\(abstain)}"
            case ("POST", ["candidates"]):
                guard p.isElection else { throw APIError.message("election not found", status: 404) }
                guard p.phase == "nominating" else { throw APIError.message("nominations have closed", status: 409) }
                guard inRoom(p.slug) else { throw APIError.message("must be a member of this patch to nominate", status: 403) }
                let nominee = ((fields["user_id"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
                let statement = ((fields["statement"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard statement.unicodeScalars.count <= VoteRules.statementLimit else {
                    throw APIError.message("a candidate's statement is at most 500 characters", status: 400)
                }
                let people: [String: (String, String)] = ["u1": ("rowan", "Rowan Hale"), "u2": ("imani", "Imani Osei"), "u3": ("theo", "theo")]
                let (id, username, name): (String, String, String)
                if nominee.isEmpty || nominee == me {
                    (id, username, name) = (me, "samplereader", myName)
                } else if let person = people[nominee] {
                    (id, username, name) = (nominee, person.0, person.1)
                } else {
                    throw APIError.message("a candidate must be an active member of this patch", status: 400)
                }
                if !p.candidates.contains(where: { $0.userId == id }) {
                    p.candidates.append(FixtureCandidate(id: "cand-\(id)", userId: id, username: username, name: name,
                                                         statement: id == me ? statement : "", approvers: []))
                }
                proposals[index] = p
                return "{\"user_id\":\"\(id)\"}"
            case ("DELETE", ["candidates", "me"]):
                guard p.isElection else { throw APIError.message("election not found", status: 404) }
                guard p.phase == "nominating" else {
                    throw APIError.message("nominations have closed: the slate is what people are voting on", status: 409)
                }
                guard p.candidates.contains(where: { $0.userId == me }) else {
                    throw APIError.message("you are not standing in this election", status: 404)
                }
                p.candidates.removeAll { $0.userId == me }
                proposals[index] = p
                return ""
            case ("POST", ["comments"]):
                guard readable(p) else { throw APIError.message("proposal not found", status: 404) }
                try mayDiscuss(p.slug)
                let body = (fields["body"] as? String) ?? ""
                guard !body.isEmpty else { throw APIError.message("body is required", status: 400) }
                let parent = fields["parent_id"] as? String
                if let parent, !(threads[p.id] ?? []).contains(where: { $0.id == parent }) {
                    throw APIError.message("parent comment not found or belongs to different proposal", status: 400)
                }
                commentSerial += 1
                let comment = FixtureComment(id: "comment-\(commentSerial)", body: body, authorId: me, authorName: myName,
                                             createdMinutesAgo: 0, parentId: parent, reactions: [:])
                threads[p.id, default: []].append(comment)
                return serialize(commentJSON(comment, replies: []))
            default:
                throw APIError.status(405)
            }
        }
        // comments/{id}[/reactions[/{emoji}]]
        let (proposalID, index) = try commentLocation(parts[1])
        let slug = proposals.first { $0.id == proposalID }?.slug ?? ""
        var comment = threads[proposalID]![index]
        switch (method, parts.count) {
        case ("PATCH", 2):
            guard comment.authorId == me else { throw APIError.message("only the author can edit this comment", status: 403) }
            let body = (fields["body"] as? String) ?? ""
            guard !body.isEmpty else { throw APIError.message("body is required", status: 400) }
            comment.body = body
            comment.editedMinutesAgo = 0
            threads[proposalID]![index] = comment
            return serialize(commentJSON(comment, replies: []))
        case ("DELETE", 2):
            guard comment.authorId == me || role(slug) == "admin" else { throw APIError.message("insufficient permissions", status: 403) }
            // The replies and the reactions go with it: there is no tombstone.
            threads[proposalID]!.removeAll { $0.id == comment.id || $0.parentId == comment.id }
            return #"{"status":"deleted"}"#
        case ("POST", 3) where parts[2] == "reactions":
            try mayDiscuss(slug)
            let emoji = (fields["emoji"] as? String) ?? ""
            // Byte for byte: a bare heart is not the heart.
            guard Discussion.emoji.contains(where: { $0.unicodeScalars.elementsEqual(emoji.unicodeScalars) }) else {
                throw APIError.message("invalid emoji", status: 400)
            }
            comment.reactions[emoji, default: []].insert(me)
            threads[proposalID]![index] = comment
            return #"{"status":"ok"}"#
        case ("DELETE", 4) where parts[2] == "reactions":
            try mayDiscuss(slug)
            let emoji = parts[3].removingPercentEncoding ?? parts[3]
            if let key = comment.reactions.keys.first(where: { $0.unicodeScalars.elementsEqual(emoji.unicodeScalars) }) {
                comment.reactions[key]?.remove(me)
            }
            threads[proposalID]![index] = comment
            return #"{"status":"ok"}"#
        default:
            throw APIError.status(405)
        }
    }

    /// The governance reads that are not fixed text.
    private static func governanceRead(_ path: String, query: [URLQueryItem]) throws -> String? {
        let parts = path.split(separator: "/").map(String.init)
        if parts.count == 2 || parts.count == 3, parts[0] == "proposals" {
            let p = proposals[try proposalIndex(parts[1])]
            guard readable(p) else { throw APIError.message("proposal not found", status: 404) }
            if parts.count == 2 { return serialize(detailFields(p)) }
            if parts[2] == "comments" { return threadJSON(p.id) }
            return nil
        }
        if parts.count == 3, parts[0] == "nodes", parts[2] == "proposals", parts[1] != "extra-1" {
            return proposalPage(parts[1], query)
        }
        return nil
    }

    /// The offline stand-in for every non-GET. The JSON is returned as text so
    /// a write with nothing to read (`auth/logout`, marking a notification
    /// read) runs the same path as one with a user in the answer.
    ///
    /// `PATCH` and `DELETE` arrived with the notifications list; the
    /// account's settings brought more of both (and a `PUT` would take the
    /// same road). The notifications and account paths are answered first,
    /// and everything else is still a `POST`.
    static func write(_ method: String, _ path: String, body: Data?) throws -> String {
        if let answer = try notificationWrite(method, path) { return answer }
        let fields = (try? JSONSerialization.jsonObject(with: body ?? Data())) as? [String: Any] ?? [:]
        if let answer = try governanceWrite(method, path, fields: fields) { return answer }
        if let answer = try accountWrite(method, path, fields: fields) { return answer }
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
        case "events":
            return try eventPost(fields)
        default:
            return try membershipPost(path, fields: fields)
        }
    }

    static func response<T: Decodable>(_ path: String, query: [URLQueryItem] = []) throws -> T {
        let patch = #"{"id":"demo-patch","name":"Common Thread Studio","slug":"common-thread","description":"A place to make things and meet your neighbors. Open studio evenings, shared tools, and room for your next idea.","tags":["craft","community"],"member_count":12,"follower_count":34,"upcoming_event_count":4,"appearance":{"palette":"anthem","block":"ohioStar","rotation":90,"icon":"scissors"},"address":"12 Example Street","latitude":40.04,"longitude":-76.3,"website":"https://commonthread.example.org","links":[{"url":"https://makers.example.org/common-thread","label":"Our makers’ directory"}],"did":"did:web:commonthread.example.org","visibility":"public","public_member_list":"everyone","public_governance_record":"everyone","timezone":"America/New_York","accept_event_suggestions":false,"follower_permissions":{"events":true,"proposals":true,"charters":false,"members":true}}"#
        let second = ##"{"id":"demo-patch-2","name":"The Listening Room","slug":"listening-room","description":"Independent music in good company.","tags":["music","venue"],"visibility":"public","public_member_list":"nobody","public_governance_record":"everyone","member_count":8,"follower_count":15,"appearance":{"block":{"grid":3,"colors":{"0,1":[1],"0,2":[2],"1,0":[1],"1,2":[1],"2,0":[2],"2,1":[1]}},"rotation":0,"bundle":["#2E7D5B","#204B4B","#D9D6AF","#D89E13"]},"timezone":"America/New_York","accept_event_suggestions":true,"follower_permissions":{"events":true,"proposals":false,"charters":false,"members":true}}"##
        let extras = extraNames.enumerated().map { index, name in
            // One patch has left this quilt, so a list has something to wear
            // the Moved chip on (web ADR 090).
            let moved = index == 4 ? ",\"moved_to\":\"\(extraMovedTo)\"" : ""
            // One patch keeps its record to the room, so "not public" has
            // somewhere to be seen now the Listening Room publishes its own.
            let record = index == 1 ? ",\"public_governance_record\":\"nobody\"" : ""
            // Every extra keeps New York time and takes suggestions; the
            // Repair Cafe keeps its non-public events from followers, so
            // the tier's ceiling has somewhere to be seen offline.
            let posting = ",\"timezone\":\"America/New_York\",\"accept_event_suggestions\":true,\"follower_permissions\":{\"events\":\(index != 6),\"proposals\":true,\"charters\":false,\"members\":true}"
            return "{\"id\":\"extra-\(index)\",\"name\":\"\(name)\",\"slug\":\"extra-\(index)\",\"tags\":[\"\(index % 2 == 0 ? "community" : "music")\"],\"member_count\":\(index + 1)\(index == 3 ? ",\"is_unclaimed\":true" : "")\(moved)\(record)\(posting)}"
        }
        let members = #"{"items":[{"id":"m1","user_id":"u1","role":"admin","username":"rowan","display_name":"Rowan Hale"},{"id":"m2","user_id":"u2","role":"member","username":"imani","display_name":"Imani Osei"},{"id":"m3","user_id":"u3","role":"member","username":"theo"},{"id":"m4","user_id":"u4","role":"follower","username":"nobody-should-see-this"}],"next_cursor":"","member_count":12,"follower_count":34,"public_member_list":"everyone"}"#
        let withheldMembers = #"{"items":[],"next_cursor":"","member_count":8,"follower_count":15,"public_member_list":"nobody"}"#
        let document = #"{"id":"demo-doc","node_id":"demo-patch","title":"How we decide","body":"This patch keeps its own copy of the shared standards, and adds one paragraph of its own.\n\n## Open studio hours\n\nAnyone may use the studio during open hours. Tools go back where they were found, and whoever is last out locks the door.\n\n## Changing this\n\nAny member may propose a change. A majority carries it.","kind":"charter","visibility":"public","version":3,"created_at":"2026-04-02T10:00:00Z","updated_at":"2026-08-14T10:00:00Z"}"#
        let lining = #"{"id":"demo-lining","node_id":"demo-patch","title":"Community Standards","body":"Every patch on this quilt starts by agreeing to the lining. This patch amended it.\n\n## Keep each other safe\n\nNobody is harmed, excluded, or diminished for who they are.","kind":"lining","visibility":"public","version":2,"created_at":"2026-03-01T10:00:00Z","updated_at":"2026-07-21T10:00:00Z"}"#
        let overview = #"{"rules":{"decision_method":"majority","quorum_percent":20,"default_vote_duration_hours":336,"leadership_model":"maintainer","leadership_venue":"patchwork","proposal_venue":"patchwork","inactivity_days":90,"max_admins":3},"admins":[{"user_id":"u1","username":"rowan","display_name":"Rowan Hale","joined_at":"2026-01-14T10:00:00Z"}],"admins_withheld":false,"proposals_withheld":false,"election":null,"seats":[],"next_term_end":"","next_contest_opens":"","membership_policy":"open","member_count":12,"document_count":2,"open_proposals":1,"passed_proposals":3,"rejected_proposals":1,"needs_vote":0}"#
        let listeningOverview = #"{"rules":{"decision_method":"majority","quorum_percent":0,"default_vote_duration_hours":168,"leadership_model":"maintainer","leadership_venue":"patchwork","proposal_venue":"patchwork"},"admins":[],"admins_withheld":true,"proposals_withheld":false,"election":null,"seats":[],"next_term_end":"","next_contest_opens":"","membership_policy":"open","member_count":8,"document_count":0,"open_proposals":1,"passed_proposals":0,"rejected_proposals":0,"needs_vote":0}"#
        let withheldOverview = #"{"rules":{"decision_method":"admin","leadership_model":"maintainer","leadership_venue":"patchwork","proposal_venue":"patchwork"},"admins":[],"admins_withheld":true,"proposals_withheld":true,"election":null,"seats":[],"next_term_end":"","next_contest_opens":"","membership_policy":"invite_only","member_count":8,"document_count":0,"open_proposals":0,"passed_proposals":0,"rejected_proposals":0,"needs_vote":0}"#
        let record = #"{"items":[{"kind":"vote","at":"2026-08-14T12:00:00Z","title":"Amend the studio hours","link":"/patches/common-thread/governance/demo-proposal-3","outcome":"carried"},{"kind":"vote","at":"2026-06-08T12:00:00Z","title":"Buy a second kiln","outcome":"lapsed"},{"kind":"direct","at":"2026-04-02T12:00:00Z","title":"Publish the charter","outcome":"applied","actor":"Rowan Hale"}],"public_governance_record":"everyone"}"#
        let json: String
        if let governed = try governanceRead(path, query: query) { json = governed } else {
        switch path {
        case "instance": json = #"{"name":"Sample quilt","description":"A fictional quilt for exploring the native app.","geography":{"timezone":"America/New_York"},"neighbor_quilts":[{"name":"Neighbor quilt","url":"https://neighbor.example.org"}],"stats":{"node_count":12,"event_count":34,"member_count":5},"version":"v0.0.0-preview","submissions_enabled":true}"#
        case "label": json = ###"{"published":true,"stewards":[{"username":"samplesteward","display_name":"Sample Steward","avatar_url":"","blurb":"Keeps the lights on and answers the email."}],"prose":"## Why this exists\n\nThis quilt is fictional, and so is everything on this page. It is here so the app has something to draw.\n\nThe figures below are **made up**, and *nobody* is billed for them. Even `code` and ***both at once*** are only here to be looked at.\n\n- No real money changes hands.\n- No real person is named.","cost_items":[{"service":"Sample Hosting","purpose":"the server (where all this lives)","why":"invented, for the preview","amount_minor":1200,"period":"monthly"},{"service":"Sample Domain","purpose":"the address","why":"also invented","amount_minor":1800,"period":"yearly"}],"currency":"USD","total_monthly_minor":1350,"stale":true,"stated_on":"2026-01-01","version":"v0.0.0-preview","federation":false,"multi_quilt":false,"support_url":"https://example.org/support","feedback_url":"https://example.org/feedback","seamripped_from_name":"","seamripped_from_url":""}"###
        case "instance/lining": json = ###"{"title":"Community Standards","body":"This fictional patch, like every patch on this fictional quilt, starts by agreeing to the lining.\n\n## Keep each other safe\n\nNobody is harmed, excluded, or diminished for who they are. We regulate actions, not identity.\n\n## Say what you are\n\nA patch describes itself honestly: who it is, what it does, and who it answers to.","version":1}"###
        case "legal/privacy": json = ###"{"doc":"privacy","title":"Privacy Policy","markdown":"## The short version\n\nNothing here is real, so nothing here is collected. This document exists so the app has a document to render.\n\n- No ads.\n- No trackers.","customized":true,"updated_at":"2026-01-01T00:00:00.000Z"}"###
        case "legal/terms": json = ###"{"doc":"terms","title":"User Agreement","markdown":"## The short version\n\nBe someone your community would vouch for. This fictional agreement has no force anywhere.","customized":false,"updated_at":"2026-01-01T00:00:00.000Z"}"###
        case "nodes/tree":
            // `scope=my` narrows the tree the way it narrows the feed: to the
            // patches the reader holds an active row on. Signed out there is
            // nobody for it to be about, so it answers an empty quilt.
            var children = [patch, second] + extras
            if query.contains(where: { $0.name == "scope" && $0.value == "my" }) {
                let held = signedIn ? heldNodeIds : []
                children = children.filter { json in held.contains { json.hasPrefix("{\"id\":\"\($0)\"") } }
            } else if signedIn, accountFields["hide_amended_linings"] as? Bool == true {
                // The reader's own discovery filter (web ADR 037), which never
                // narrows My Quilt: the studio is the patch whose lining diverged.
                children.removeAll { $0.hasPrefix("{\"id\":\"demo-patch\"") }
            }
            json = "{\"tree\":{\"children\":[\(children.joined(separator: ","))]}}"
        // The node carries its own membership policy always, and who the
        // reader is to it only where there is a session (see `relation`).
        // `viewer_trusted` is always stated and only ever true on an unclaimed
        // patch; the fixture reader holds no trusted-contributor grant.
        case "nodes/common-thread": json = "{\"node\":\(node(patch, slug: "common-thread")),\"is_unclaimed\":false,\"lining_status\":\"diverged\",\"viewer_trusted\":false}"
        case "nodes/listening-room": json = "{\"node\":\(node(second, slug: "listening-room")),\"is_unclaimed\":false,\"lining_status\":\"pristine\",\"viewer_trusted\":false}"
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
        case "auth/recovery-codes":
            guard signedIn else { throw APIError.unauthenticated }
            json = "{\"total\":\(batch.count),\"remaining\":\(unusedCodes)}"
        case "auth/step-up":
            guard signedIn else { throw APIError.unauthenticated }
            json = "{\"has_passkey\":false,\"active\":\(stepUpOpen),\"window_secs\":300,\"recovery_ready\":\(batchPredatesSession ? unusedCodes : 0)}"
        case "auth/sessions":
            guard signedIn else { throw APIError.unauthenticated }
            let rows = sessionRows.enumerated().map { index, row in
                "{\"id\":\"\(row.id)\",\"label\":\"\(row.label)\",\"created_at\":\"\(stamp(minutesAgo: (index + 1) * 3 * 24 * 60))\"," +
                    "\"last_used_at\":\"\(stamp(minutesAgo: index * 26 * 60))\",\"current\":\(row.current)}"
            }
            json = "[\(rows.joined(separator: ","))]"
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
        case "nodes/common-thread/governance/overview": json = overviewJSON("common-thread", base: overview)
        case "nodes/listening-room/governance/overview": json = overviewJSON("listening-room", base: listeningOverview)
        case "nodes/extra-1/governance/overview": json = withheldOverview
        case "nodes/extra-1/governance": json = #"{"items":[],"published_only":true}"#
        case "nodes/extra-1/governance/record": json = #"{"items":[],"public_governance_record":"nobody"}"#
        case "nodes/extra-1/proposals": json = #"{"items":[],"next_cursor":"","public_governance_record":"nobody"}"#
        case "nodes/common-thread/governance/record": json = record
        case "nodes/listening-room/governance/record": json = #"{"items":[],"public_governance_record":"everyone"}"#
        case "governance/demo-doc": json = document
        case "governance/demo-lining": json = lining
        default:
            if let event = events.first(where: { "events/\($0.id)" == path }) { json = event.json }
            // A pending suggestion is readable by its submitter and nobody
            // else, and it is on no list (the server's `GetEvent` rule).
            else if let event = postedEvents.first(where: { "events/\($0.id)" == path }), signedIn { json = event.json }
            else if let index = Int(path.replacingOccurrences(of: "nodes/extra-", with: "")), extras.indices.contains(index) {
                json = "{\"node\":\(node(extras[index], slug: "extra-\(index)")),\"is_unclaimed\":\(index == 3),\"viewer_trusted\":false}"
            }
            else { throw APIError.status(404) }
        }
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }
}
#endif
