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

    /// The feed: every event that is published, as the last edit left it.
    private static var events: [(id: String, json: String)] {
        everyEvent.filter { $0.json.contains("\"status\":\"active\"") }
    }

    /// Every event the fixtures hold — the fixed ones, then whatever `POST
    /// events` made this launch, pending ones included — with this launch's
    /// edits laid over them and its deletions gone.
    ///
    /// Two of them are the sample reader's own, on the Repair Cafe where
    /// they are a member: one they posted, which they may edit and delete,
    /// and one that arrived from the patch's calendar feed (`source_id`),
    /// which nobody edits here. The feed's event names the reader as its
    /// creator too, so the source is the only thing keeping Edit away —
    /// which is the rule the fixture is for.
    private static var everyEvent: [(id: String, json: String)] {
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
        let mine = """
        {"id":"demo-event-mine","node_id":"extra-6","created_by":"demo-user","title":"Toaster triage",\
        "description":"Bring the toaster. We will look at it together.","location":"Repair Cafe back room",\
        "starts_at":"\(instant(daysFromToday: 4))","ends_at":"\(instant(daysFromToday: 4, hour: 20))",\
        "timezone":"America/New_York","recurrence":"monthly","visibility":"public","status":"active",\
        "image_url":"","image_alt":"","event_url":"",\
        "node_name":"Repair Cafe","node_slug":"extra-6","node_status":"active"}
        """
        let imported = """
        {"id":"demo-event-imported","node_id":"extra-6","created_by":"demo-user","source_id":"demo-source",\
        "title":"Bike tune-up clinic","description":"From the Repair Cafe's shared calendar.","location":"Repair Cafe yard",\
        "starts_at":"\(instant(daysFromToday: 6))","timezone":"America/New_York","recurrence":"","visibility":"public",\
        "status":"active","image_url":"","image_alt":"","event_url":"",\
        "node_name":"Repair Cafe","node_slug":"extra-6","node_status":"active"}
        """
        // Two suggestions waiting on the Film Club's admins, kept to their
        // queue until one of them answers.
        let silent = """
        {"id":"suggest-silent","node_id":"extra-7","created_by":"rc2","title":"Silent film night",\
        "description":"Live piano under a 1920s comedy short. Bring a cushion.","location":"Library basement",\
        "starts_at":"\(instant(daysFromToday: 5, hour: 19))","ends_at":"\(instant(daysFromToday: 5, hour: 21))",\
        "timezone":"America/New_York","recurrence":"","visibility":"public","status":"pending_review",\
        "image_url":"","image_alt":"","event_url":"",\
        "node_name":"Film Club","node_slug":"extra-7","node_status":"active"}
        """
        let documentary = """
        {"id":"suggest-docs","node_id":"extra-7","created_by":"l2","title":"Documentary double bill",\
        "description":"Two short films about record shops.","location":"The Listening Room",\
        "starts_at":"\(instant(daysFromToday: 12, hour: 19))","timezone":"America/New_York","recurrence":"",\
        "visibility":"public","status":"pending_review","image_url":"","image_alt":"","event_url":"",\
        "node_name":"Film Club","node_slug":"extra-7","node_status":"active"}
        """
        let fixed = [("demo-event", tonight), ("demo-event-2", soon), ("demo-event-mine", mine),
                     ("demo-event-imported", imported), ("demo-event-3", later),
                     ("suggest-silent", silent), ("suggest-docs", documentary)]
        return (fixed + postedEvents.map { ($0.id, $0.json) })
            .filter { !deletedEvents.contains($0.0) }
            .map { (id: $0.0, json: edited($0.1, eventEdits[$0.0])) }
    }

    /// What `POST events` has made this launch. An active one joins the
    /// feed; a pending one is only ever answered by id, to its submitter.
    private static var postedEvents: [(id: String, json: String)] = []
    /// What `PATCH events/{id}` has written this launch, field by field
    /// (`NSNull` for a cleared one), and what `DELETE` has taken away.
    private static var eventEdits: [String: [String: Any]] = [:]
    private static var deletedEvents = Set<String>()

    /// An event's JSON with an edit laid over it. A null or empty zone, and
    /// a null end, are the server's clears: the key goes.
    private static func edited(_ json: String, _ edits: [String: Any]?) -> String {
        guard let edits, !edits.isEmpty,
              var object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return json }
        for (key, value) in edits {
            if value is NSNull || (key == "timezone" && (value as? String)?.isEmpty == true) { object[key] = nil }
            else { object[key] = value }
        }
        return serialize(object)
    }
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
    private static var holdable: [(slug: String, id: String, name: String, blurb: String, visibility: String, policy: String)] {
        fixedHoldable
            + madePatches.filter { $0.status == "active" }.map { ($0.slug, $0.id, $0.name, $0.description, "public", $0.policy) }
            + activated.keys.sorted().map { slug in (slug, slug, patchName(slug), "", "public", activated[slug] ?? "invite_only") }
    }
    private static let fixedHoldable: [(slug: String, id: String, name: String, blurb: String, visibility: String, policy: String)] = [
        ("common-thread", "demo-patch", "Common Thread Studio",
         "A place to make things and meet your neighbors.", "public", "approval_required"),
        ("listening-room", "demo-patch-2", "The Listening Room",
         "Independent music in good company.", "public", "open"),
        (memberSlug, memberSlug, extraNames[6], "", "public", "open"),
        (adminSlug, adminSlug, extraNames[7], "", "public", "open"),
        // The Food Share adds members by invitation only, so a
        // `--preview-invited` launch has a patch to have been asked into.
        (invitingSlug, invitingSlug, extraNames[8], "", "public", "invite_only"),
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
        if governanceAdmin { rows[adminSlug] = (role: "admin", status: "active") }
        if nominatorLaunch { rows[marketSlug] = (role: "admin", status: "active") }
        return rows
    }
    /// The extra a `--preview-admin` launch makes the reader an admin of: the
    /// Film Club, whose admins decide its proposals.
    static let adminSlug = "extra-7"
    /// The extra a `--preview-nominator` launch makes the reader an admin
    /// of: Market Friends, which votes by majority and ratifies its admins
    /// by nomination (the Collaborative template's leadership).
    static let marketSlug = "extra-5"
    private static let nominatorLaunch = ProcessInfo.processInfo.arguments.contains("--preview-nominator")
    /// The extra the fixture reader is a member of: the Repair Cafe.
    static let memberSlug = "extra-6"
    /// The invite-only extra, the Food Share, whose admins ask the reader in
    /// on a `--preview-invited` launch (web ADR 098).
    static let invitingSlug = "extra-8"
    private static let invitedLaunch = ProcessInfo.processInfo.arguments.contains("--preview-invited")
    /// The patches the reader has been asked into and not answered. Never
    /// rows in `held`: an invited row is not membership anywhere, and
    /// `me/nodes` does not serve it.
    private static var invited: Set<String> = []
    private static var freshInvited: Set<String> { invitedLaunch ? [invitingSlug] : [] }
    private static func patchName(_ slug: String) -> String {
        guard let index = Int(slug.dropFirst("extra-".count)), extraNames.indices.contains(index) else { return slug }
        return (nodeEdits[slug]?["name"] as? String) ?? extraNames[index]
    }
    /// The quilt's other ten patches, by name; `extra-N` is the Nth.
    private static let extraNames = ["Community Garden", "Bike Kitchen", "Neighborhood Books", "River Walkers", "Pottery Circle", "Market Friends", "Repair Cafe", "Film Club", "Food Share", "Evening Choir"]

    static func signOut() {
        signedIn = false
        account = sampleAccount
        held = [:]
        invited = []
        notifications = []
        stepUpOpen = false
        resetPeople()
    }
    private static func startSession() {
        signedIn = true
        held = freshHeld
        invited = freshInvited
        claims = freshClaims
        notifications = Self.freshNotifications
        sessionRows = freshSessionRows
        // A new sign-in is younger than whatever batch the account already
        // holds, so that batch can confirm from now on (web ADR 099).
        batchPredatesSession = true
        stepUpOpen = false
        resetPeople()
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
    /// a notice on the Repair Cafe's board (the patch the fixture reader is
    /// a member of, so the notice is theirs to read), and the warning
    /// carries no link at all, because there is nowhere in this app to send
    /// somebody about one.
    private static var freshNotifications: [Notif] {
        // The invitation's own row, the way the server words it, on a
        // launch that is asked into the Food Share.
        (invitedLaunch ? [Notif(id: "notif-7", type: "membership.invited",
                                title: "You're invited to join \(extraNames[8])", body: "",
                                link: "/patches/\(invitingSlug)", minutesAgo: 1, read: false)] : []) +
        // An admin of the Film Club is also told what is waiting on them.
        (governanceAdmin ? [
            Notif(id: "notif-8", type: "membership.request", title: "Membership request for Film Club",
                  body: "", link: "/patches/\(adminSlug)/members?status=pending", minutesAgo: 30, read: false),
            Notif(id: "notif-10", type: "event.suggested", title: "Event suggested: Silent film night",
                  body: "", link: "/patches/\(adminSlug)/events", minutesAgo: 60, read: true),
        ] : []) + [
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
                  title: "Soldering irons are back",
                  body: "Both irons are back from repair and on the bench by the window.",
                  link: "/patches/\(memberSlug)/noticeboard/notice-r1",
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
                "\"status\":\"\(row.status)\",\"visible\":\(!hiddenMemberships.contains(patch.slug)),\"joined_at\":\"2026-09-01T10:00:00Z\"," +
                "\"node_name\":\"\(patch.name)\",\"node_slug\":\"\(patch.slug)\",\"node_description\":\"\(patch.blurb)\"," +
                "\"node_visibility\":\"\(patch.visibility)\",\"membership_policy\":\"\(patch.policy)\",\"node_status\":\"active\"," +
                "\"contact_items_shared\":\(sharesCount(patch.slug))}"
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
            // A membership that ends takes its contact shares with it
            // (`DropContactSharesFor`): rejoining discloses nothing on its own.
            contactShares[slug] = nil
            return #"{"status":"ok"}"#
        case "withdraw":
            guard held[slug]?.status == "pending" else { throw APIError.message("no pending request", status: 400) }
            held[slug] = nil
            return #"{"status":"ok"}"#
        default:
            throw APIError.status(404)
        }
    }

    // MARK: Making and suggesting patches

    /// A patch made this launch: created (`POST nodes`, active, the reader
    /// its admin) or suggested (`POST submissions`, unclaimed or waiting
    /// for review). Held as fields so the tree, `nodes/{slug}` and the
    /// index all read the same one.
    private struct MadePatch {
        let id: String
        let slug: String
        var name: String
        var description: String
        var address: String
        var latitude: Double?
        var longitude: Double?
        var website: String
        var tags: [String]
        var policy: String
        var appearance: [String: Any]
        /// `active`, `unclaimed` or `pending_review`.
        var status: String
    }
    private static var madePatches: [MadePatch] = []
    /// The quilt's curated vocabulary, as `tags` serves it.
    private static let vocabulary = ["craft", "music", "venue", "community", "archive"]

    /// The server's `generateSlug`: lowercase, every run of anything that is
    /// not a letter or a digit becomes one hyphen, hyphens trimmed, at most
    /// sixty characters, and "node" for nothing at all.
    static func slug(for name: String) -> String {
        var text = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        text = text.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if text.count > 60 { text = String(text.prefix(60)) }
        return text.isEmpty ? "node" : text
    }
    /// Every slug the quilt holds, whatever its state.
    private static var knownSlugs: Set<String> {
        Set(["common-thread", "listening-room"] + extraNames.indices.map { "extra-\($0)" } + madePatches.map(\.slug))
    }
    /// `uniqueSlug`: the base, or the base with a suffix until it is free.
    private static func uniqueSlug(_ base: String) -> String {
        var candidate = base
        var serial = 0
        while knownSlugs.contains(candidate) {
            serial += 1
            candidate = String(format: "%@-%04x", base, serial)
        }
        return candidate
    }

    private static func madeJSON(_ p: MadePatch) -> String {
        var object: [String: Any] = [
            "name": p.name, "slug": p.slug, "description": p.description, "tags": p.tags,
            "member_count": p.status == "active" ? 1 : 0, "follower_count": 0, "upcoming_event_count": 0,
            "address": p.address, "website": p.website, "visibility": "public",
            "public_member_list": "nobody", "public_governance_record": "nobody",
            "timezone": "America/New_York", "accept_event_suggestions": false,
        ]
        if !p.appearance.isEmpty { object["appearance"] = p.appearance }
        if let latitude = p.latitude, let longitude = p.longitude { object["latitude"] = latitude; object["longitude"] = longitude }
        if p.status == "unclaimed" { object["is_unclaimed"] = true; object["status"] = "unclaimed" }
        // The id leads, as every fixture node's does: the tree's `scope=my`
        // narrowing finds a patch by the start of its JSON.
        return "{\"id\":\"\(p.id)\"," + serialize(object).dropFirst()
    }

    /// The node's JSON for the tree or the envelope: a made patch, or an
    /// extra with whatever a claim's setup has written over it.
    private static func treeMade() -> [String] {
        madePatches.filter { $0.status != "pending_review" }.map(madeJSON)
    }

    /// `POST nodes`, in `CreateNode`'s order and words. An omitted
    /// membership policy is the server's `open` — the default the form is
    /// built to avoid, kept here so a client that forgot would be seen to.
    private static func createNode(_ fields: [String: Any]) throws -> String {
        guard signedIn else { throw APIError.unauthenticated }
        let name = (fields["name"] as? String) ?? ""
        guard !name.isEmpty else { throw APIError.message("name is required", status: 400) }
        let visibility = (fields["visibility"] as? String) ?? "public"
        guard ["public", "private", "unlisted"].contains(visibility) else {
            throw APIError.message("visibility must be one of public, private, unlisted", status: 400)
        }
        let policy = (fields["membership_policy"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "open"
        guard ["open", "approval_required", "invite_only"].contains(policy) else {
            throw APIError.message("membership_policy must be one of open, approval_required, invite_only", status: 400)
        }
        if let latitude = fields["latitude"] as? Double, !(-90...90).contains(latitude) {
            throw APIError.message("latitude must be between -90 and 90", status: 400)
        }
        if let longitude = fields["longitude"] as? Double, !(-180...180).contains(longitude) {
            throw APIError.message("longitude must be between -180 and 180", status: 400)
        }
        let appearance = (fields["appearance"] as? [String: Any]) ?? [:]
        if let rotation = appearance["rotation"] as? Int, ![0, 90, 180, 270].contains(rotation) {
            throw APIError.message("appearance.rotation must be one of 0, 90, 180, 270", status: 400)
        }
        let tags = (fields["tags"] as? [String]) ?? []
        if let unknown = tags.first(where: { !vocabulary.contains($0) }) { throw APIError.message("unknown tag: \(unknown)", status: 400) }
        let slug = uniqueSlug(slug(for: name))
        let made = MadePatch(id: "made-\(madePatches.count + 1)", slug: slug, name: name,
                             description: (fields["description"] as? String) ?? "", address: (fields["address"] as? String) ?? "",
                             latitude: fields["latitude"] as? Double, longitude: fields["longitude"] as? Double,
                             website: (fields["website"] as? String) ?? "", tags: tags, policy: policy,
                             appearance: appearance, status: "active")
        madePatches.append(made)
        held[slug] = (role: "admin", status: "active")
        return madeJSON(made)
    }

    /// `POST submissions`, in `SubmitPatch`'s order and words: the name, the
    /// tags, then the collision with a patch already on the quilt — named in
    /// `existing_slug` — and then published at once only for a quilt-wide
    /// trusted contributor.
    private static func submit(_ fields: [String: Any]) throws -> String {
        guard signedIn else { throw APIError.unauthenticated }
        let name = (fields["name"] as? String) ?? ""
        guard !name.isEmpty else { throw APIError.message("name is required", status: 400) }
        let tags = (fields["tags"] as? [String]) ?? []
        if let unknown = tags.first(where: { !vocabulary.contains($0) }) { throw APIError.message("unknown tag: \(unknown)", status: 400) }
        let base = slug(for: name)
        if knownSlugs.contains(base) {
            throw refuse(409, "a patch with a similar name already exists", extra: ",\"existing_slug\":\"\(base)\"")
        }
        if let feed = fields["feed_url"] as? String, !feed.isEmpty {
            guard feed.hasPrefix("http://") || feed.hasPrefix("https://") else { throw APIError.message("feed url must be http(s)", status: 400) }
            guard feed.contains("calendar") || feed.hasSuffix(".ics") else {
                throw APIError.message("could not read a calendar at that address", status: 400)
            }
        }
        let trusted = accountFields["trusted_contributor"] as? Bool == true
        let made = MadePatch(id: "suggested-\(madePatches.count + 1)", slug: base, name: name,
                             description: (fields["description"] as? String) ?? "", address: (fields["address"] as? String) ?? "",
                             latitude: nil, longitude: nil, website: (fields["website"] as? String) ?? "", tags: tags,
                             policy: "invite_only", appearance: [:], status: trusted ? "unclaimed" : "pending_review")
        madePatches.append(made)
        if trusted {
            return serialize(["status": "unclaimed", "node": ["id": made.id, "slug": made.slug, "name": made.name]])
        }
        return serialize(["status": "pending_review", "message": "Submission sent for review", "id": made.id])
    }

    /// `GET gazetteer/suggest`: the fixtures' one street is known, and
    /// anything else is the polite miss.
    private static func gazetteer(_ query: [URLQueryItem]) -> String {
        let q = (query.first { $0.name == "q" }?.value ?? "").lowercased()
        guard q.contains("example street") else { return #"{"found":false,"available":true}"# }
        return #"{"found":true,"available":true,"place":{"latitude":40.0379,"longitude":-76.3055},"label":"12 Example Street, Sample Town"}"#
    }

    // MARK: Claiming

    /// One claim as the fixtures hold it (claims.go). Kept across a sign-in,
    /// because a claim is the account's, and started afresh with a session
    /// the way the rest of the reader's rows are.
    private struct FixtureClaim {
        let id: String
        let slug: String
        let method: String
        var status: String
        var email = ""
        var evidence = ""
        let createdMinutesAgo: Int
        /// Minutes from now until the setup window closes, once approved.
        var setupExpiresIn: Int?
        var sends = 1
    }
    /// The River Walkers' claim is approved and waiting to be set up; the
    /// Evening Choir is unclaimed with a vetted domain, so every method is
    /// open on it.
    private static var freshClaims: [FixtureClaim] {
        [FixtureClaim(id: "claim-river-walkers", slug: "extra-3", method: "email", status: "approved",
                      email: "walk@riverwalkers.example.org", createdMinutesAgo: 5 * day, setupExpiresIn: 9 * day)]
    }
    private static var claims: [FixtureClaim] = signedIn ? freshClaims : []
    /// The vetted domain each unclaimed listing carries, or none.
    private static let verificationDomains = ["extra-9": "eveningchoir.example.org"]
    /// The extras nobody runs: the River Walkers and the Evening Choir.
    private static let unclaimedExtras: Set<Int> = [3, 9]
    /// Listings a claim's setup has activated this launch, with the policy
    /// the claimant chose, and what `PATCH nodes/{slug}` wrote over them.
    private static var activated: [String: String] = [:]
    private static var nodeEdits: [String: [String: Any]] = [:]
    private static func isUnclaimedExtra(_ index: Int) -> Bool {
        unclaimedExtras.contains(index) && activated["extra-\(index)"] == nil
    }

    private static func claimInstructions(_ c: FixtureClaim, domain: String) -> [String: Any] {
        switch c.method {
        case "dns":
            return ["instructions": "Add a TXT record on \(domain) with the value: patchwork-verify=token-\(c.id)",
                    "record_value": "patchwork-verify=token-\(c.id)"]
        case "meta_tag":
            return ["instructions": "Add this tag to the <head> of https://\(domain): <meta name=\"patchwork-verify\" content=\"token-\(c.id)\">",
                    "meta_content": "token-\(c.id)"]
        case "did":
            return ["instructions": "Point the atproto handle \(domain) at a did:web identity, and have that DID document list at://\(domain) in alsoKnownAs."]
        case "email":
            return ["instructions": "We sent a verification link to \(c.email). It expires in 24 hours."]
        default:
            return ["instructions": "Your claim has been submitted for admin review. You'll be notified when it's resolved."]
        }
    }

    private static func claimJSON(_ c: FixtureClaim) -> [String: Any] {
        var fields: [String: Any] = ["id": c.id, "method": c.method, "evidence": c.evidence, "status": c.status,
                                     "email": c.email, "created_at": stamp(minutesAgo: c.createdMinutesAgo)]
        if let left = c.setupExpiresIn { fields["setup_expires_at"] = stamp(minutesAgo: -left) }
        for (key, value) in claimInstructions(c, domain: verificationDomains[c.slug] ?? "") { fields[key] = value }
        return fields
    }

    private static func claimableIndex(_ slug: String) -> Int? {
        guard slug.hasPrefix("extra-"), let index = Int(slug.dropFirst("extra-".count)), extraNames.indices.contains(index) else { return nil }
        return index
    }

    /// Leaving the app stands in for opening the emailed link: the browser
    /// is where that link goes, and coming back is when the app looks again.
    private static let browserStandIn: Void = {
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            for i in claims.indices where claims[i].method == "email" && claims[i].status == "pending" {
                claims[i].status = "approved"
                claims[i].setupExpiresIn = 14 * day
            }
        }
    }()

    private static func claimRead(_ path: String) throws -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 4, parts[0] == "nodes", parts[2] == "claims", parts[3] == "mine" else { return nil }
        guard signedIn else { throw APIError.unauthenticated }
        let slug = parts[1]
        let index = claimableIndex(slug)
        guard index != nil || holdable.contains(where: { $0.slug == slug }) || ["common-thread", "listening-room"].contains(slug) else {
            throw APIError.message("node not found", status: 404)
        }
        let domain = verificationDomains[slug] ?? ""
        let mine = claims.last { $0.slug == slug && ["pending", "approved"].contains($0.status) }
        return serialize([
            "claim": mine.map { claimJSON($0) as Any } ?? NSNull(),
            "methods": ["dns": !domain.isEmpty, "meta_tag": !domain.isEmpty, "did": !domain.isEmpty, "email": !domain.isEmpty, "admin": true],
            "verification_domain": domain,
            "node_status": index.map { isUnclaimedExtra($0) } == true ? "unclaimed" : "active",
        ])
    }

    /// The claim writes, in claims.go's order and words. Nil means "not one
    /// of these".
    private static func claimWrite(_ method: String, _ path: String, fields: [String: Any]) throws -> String? {
        let parts = path.split(separator: "/").map(String.init)
        let isRequest = parts.count == 3 && parts[0] == "nodes" && parts[2] == "claim"
        let isAct = parts.count == 3 && parts[0] == "claims"
        let isEdit = method == "PATCH" && parts.count == 2 && parts[0] == "nodes"
        guard isRequest || isAct || isEdit else { return nil }
        guard signedIn else { throw APIError.unauthenticated }

        if isEdit { return try updateNode(parts[1], fields: fields) }

        if isRequest {
            _ = browserStandIn
            let slug = parts[1]
            guard let index = claimableIndex(slug) else { throw APIError.message("node not found", status: 404) }
            guard isUnclaimedExtra(index) else { throw APIError.message("this patch is not available for claiming", status: 400) }
            if claims.contains(where: { $0.slug == slug && $0.status == "approved" }) {
                throw APIError.message("this patch has an approved claim awaiting setup", status: 409)
            }
            if claims.contains(where: { $0.slug == slug && $0.status == "pending" }) {
                throw APIError.message("you already have an open claim for this patch", status: 409)
            }
            let kind = (fields["method"] as? String) ?? ""
            guard ["dns", "meta_tag", "did", "email", "admin"].contains(kind) else {
                throw APIError.message("method must be dns, meta_tag, did, email, or admin", status: 400)
            }
            let domain = verificationDomains[slug] ?? ""
            if kind != "admin" && domain.isEmpty {
                throw APIError.message("this patch has no verified domain. Choose admin review", status: 400)
            }
            var email = ""
            if kind == "email" {
                email = ((fields["email"] as? String) ?? "").trimmingCharacters(in: .whitespaces).lowercased()
                let pieces = email.split(separator: "@", omittingEmptySubsequences: false)
                guard pieces.count == 2, !pieces[0].isEmpty, pieces[1].contains(".") else {
                    throw APIError.message("a valid email address is required for email verification", status: 400)
                }
                guard pieces[1] == domain else { throw APIError.message("the email must be at @\(domain)", status: 400) }
            }
            let claim = FixtureClaim(id: "claim-\(claims.count + 1)", slug: slug, method: kind, status: "pending",
                                     email: email, evidence: (fields["evidence"] as? String) ?? "", createdMinutesAgo: 0)
            claims.append(claim)
            var answer: [String: Any] = ["id": claim.id, "method": kind, "status": "pending"]
            for (key, value) in claimInstructions(claim, domain: domain) { answer[key] = value }
            return serialize(answer)
        }

        guard method == "POST", let index = claims.firstIndex(where: { $0.id == parts[1] }) else {
            throw APIError.message("claim not found", status: 404)
        }
        var claim = claims[index]
        switch parts[2] {
        case "verify":
            guard claim.status == "pending" else { throw APIError.message("claim is already \(claim.status)", status: 400) }
            let sentence: String
            switch claim.method {
            case "dns": sentence = "TXT record not found — it may take a few minutes to propagate"
            case "meta_tag": sentence = "verification tag not found on the site"
            case "did": sentence = "the handle does not resolve to a did:web identity on this domain"
            case "email": sentence = "check your inbox — email claims are completed via the emailed link"
            default: sentence = "admin claims are reviewed manually — you'll be notified"
            }
            return serialize(["status": "pending", "verified": false, "error": sentence])
        case "resend-email":
            guard claim.method == "email", claim.status == "pending" else {
                throw APIError.message("this claim has no email verification to resend", status: 400)
            }
            guard claim.sends < 3 else { throw APIError.message("resend limit reached", status: 429) }
            claim.sends += 1
            claims[index] = claim
            return #"{"status":"sent"}"#
        case "withdraw":
            guard claim.status == "pending" else { throw APIError.message("claim is already \(claim.status)", status: 400) }
            claim.status = "withdrawn"
            claims[index] = claim
            return #"{"status":"withdrawn"}"#
        case "setup":
            let policy = (fields["membership_policy"] as? String) ?? ""
            if !policy.isEmpty && !["open", "approval_required", "invite_only"].contains(policy) {
                throw APIError.message("membership_policy must be one of open, approval_required, invite_only", status: 400)
            }
            let template = (fields["template"] as? String) ?? ""
            if !template.isEmpty && !["minimal", "casual", "collaborative", "formal"].contains(template) {
                throw APIError.message("unknown governance template", status: 400)
            }
            guard claim.status == "approved" else { throw APIError.message("claim is \(claim.status), not approved", status: 400) }
            if let left = claim.setupExpiresIn, left < 0 {
                claim.status = "expired"
                claims[index] = claim
                throw APIError.message("this claim's setup window has expired. The patch is claimable again", status: 410)
            }
            guard let extra = claimableIndex(claim.slug), isUnclaimedExtra(extra) else {
                throw APIError.message("this patch is no longer unclaimed", status: 409)
            }
            activated[claim.slug] = policy.isEmpty ? "invite_only" : policy
            held[claim.slug] = (role: "admin", status: "active")
            claim.status = "completed"
            claims[index] = claim
            return "{\"status\":\"ok\",\"slug\":\"\(claim.slug)\"}"
        default:
            throw APIError.status(404)
        }
    }

    /// `UpdateNode`, in its order and its words: the patch's admin only, the
    /// checks that make a bad value a 400 rather than the database's 500,
    /// the question about events that follow the zone, and then every
    /// allowed field written over the fixture row. `null` clears.
    private static func updateNode(_ slug: String, fields: [String: Any]) throws -> String {
        guard holdable.contains(where: { $0.slug == slug }) || madePatches.contains(where: { $0.slug == slug }) else {
            throw APIError.message("node not found", status: 404)
        }
        guard role(slug) == "admin" || (accountFields["role"] as? String) == "admin" else {
            throw APIError.message("insufficient permissions", status: 403)
        }
        var edits = nodeEdits[slug] ?? [:]
        if let raw = fields["timezone"] {
            let zone = ((raw as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !zone.isEmpty && (TimeZone(identifier: zone) == nil || !zone.contains("/")) {
                throw APIError.message("timezone must be an IANA zone name for a place, like America/New_York or Europe/Berlin — a fixed-offset name like EST is an hour wrong for half the year", status: 400)
            }
            let stored = (edits["timezone"] as? String) ?? "America/New_York"
            // The club's calendar follows its zone, so a change asks first.
            let following = everyEvent.filter { $0.json.contains("\"node_slug\":\"\(slug)\"") && !deletedEvents.contains($0.id) }.count
            let mode = (fields["timezone_events"] as? String) ?? ""
            if zone != stored, following > 0, mode != "keep_clock", mode != "keep_instant" {
                let subject = following == 1 ? "event follows" : "events follow"
                throw refuse(409, "\(following) \(subject) this patch's timezone and would read as a different time. Say whether to keep their clock times or leave them where they are.",
                             code: "timezone_events_undecided")
            }
        }
        if let raw = fields["visibility"], !["public", "private"].contains((raw as? String) ?? "") {
            throw APIError.message("visibility must be one of public, private", status: 400)
        }
        if let raw = fields["notice_posting"], !["admins", "members"].contains((raw as? String) ?? "") {
            throw APIError.message("notice_posting must be admins or members", status: 400)
        }
        if let raw = fields["notice_replies_default"], !(raw is Bool) {
            throw APIError.message("notice_replies_default must be true or false", status: 400)
        }
        if fields["image_url"] != nil || fields["image_alt"] != nil {
            let url = (fields["image_url"] as? String) ?? (edits["image_url"] as? String) ?? ""
            let alt = (fields["image_alt"] as? String) ?? (edits["image_alt"] as? String) ?? ""
            if let problem = EventPosting.imageProblem(url: url, alt: alt) { throw APIError.message(problem, status: 400) }
        }
        if let tags = fields["tags"] {
            guard let names = tags as? [String] else { throw APIError.message("tags must be an array of tag names", status: 400) }
            if let unknown = names.first(where: { !vocabulary.contains($0) }) { throw APIError.message("unknown tag: \(unknown)", status: 400) }
        }
        let allowed = ["name", "description", "latitude", "longitude", "address", "timezone", "website", "links", "visibility",
                       "appearance", "accept_event_suggestions", "notice_posting", "notice_replies_default",
                       "public_member_list", "public_governance_record", "image_url", "image_alt", "tags"]
        let written = allowed.filter { fields[$0] != nil }
        guard !written.isEmpty || fields["suggest_tags"] != nil else { throw APIError.message("no valid fields to update", status: 400) }
        for key in written {
            let value = fields[key]!
            // An empty zone clears it back to the quilt's.
            if key == "timezone", (value as? String)?.isEmpty == true { edits[key] = NSNull() } else { edits[key] = value }
        }
        nodeEdits[slug] = edits
        lastNodeEdit = fields
        return #"{"status":"ok"}"#
    }
    /// The last `PATCH nodes/{slug}` body, so a test can see only what
    /// changed travelled.
    static var lastNodeEdit: [String: Any] = [:]

    // MARK: Account invite links

    /// `auth.ValidateInviteLink`'s sentences: one live link, one used up,
    /// and every other token unknown.
    private static func inviteProblem(_ token: String) -> String? {
        switch token {
        case "demo-invite": return nil
        case "used-invite": return "invite link has reached maximum uses"
        default: return "invalid invite token"
        }
    }

    // MARK: Answering an invitation

    /// `POST nodes/{slug}/invitations/accept|decline`, in the server's order
    /// and words (`invitations.go`). Accepting turns the invited row into an
    /// active membership; declining deletes it. Nil means "not one of these".
    private static func invitationWrite(_ method: String, _ path: String) throws -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 4, parts[0] == "nodes", parts[2] == "invitations",
              ["accept", "decline"].contains(parts[3]) else { return nil }
        guard method == "POST" else { throw APIError.status(405) }
        guard signedIn else { throw APIError.unauthenticated }
        let slug = parts[1]
        guard holdable.contains(where: { $0.slug == slug }) || slug.hasPrefix("extra-") else {
            throw APIError.message("node not found", status: 404)
        }
        guard invited.contains(slug) else { throw APIError.message("no invitation to answer", status: 400) }
        invited.remove(slug)
        if parts[3] == "decline" { return #"{"status":"declined"}"# }
        held[slug] = (role: "member", status: "active")
        return "{\"status\":\"active\",\"membership_id\":\"membership-\(slug)\"}"
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
        postedEvents.append((id: id, json: serialize(event)))
        return answer
    }

    // MARK: Editing and deleting an event

    /// `PATCH events/{id}` and `DELETE events/{id}`, decided by the server's
    /// `UpdateEvent` and `DeleteEvent` in their order and in their words —
    /// worked out again here rather than borrowed from the app's own rule,
    /// so a disagreement between the two shows up as a refusal offline.
    /// The fixture reader is trusted nowhere, so trust never opens the
    /// direct door.
    private static func eventWrite(_ method: String, _ path: String, fields: [String: Any]) throws -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts[0] == "events", method == "PATCH" || method == "DELETE" else { return nil }
        guard signedIn else { throw APIError.unauthenticated }
        let id = parts[1]
        guard let found = everyEvent.first(where: { $0.id == id }),
              let event = (try? JSONSerialization.jsonObject(with: Data(found.json.utf8))) as? [String: Any] else {
            throw APIError.message("event not found", status: 404)
        }
        let slug = (event["node_slug"] as? String) ?? ""
        let nodeStatus = (event["node_status"] as? String) ?? "active"
        let isCreator = (event["created_by"] as? String) == ((accountFields["id"] as? String) ?? me)
        let isInstanceAdmin = (accountFields["role"] as? String) == "admin"

        if method == "DELETE" {
            guard isInstanceAdmin || role(slug) == "admin" || isCreator else {
                throw APIError.message("insufficient permissions", status: 403)
            }
            deletedEvents.insert(id)
            return #"{"status":"ok"}"#
        }

        if (event["source_id"] as? String)?.isEmpty == false {
            throw APIError.message("this event comes from an event source. Edit it in the source calendar, or detach it first", status: 403)
        }
        let direct = isInstanceAdmin
            || (nodeStatus == "active" && role(slug) == "admin")
            || (nodeStatus == "active" && isCreator && role(slug) == "member")
        var reReview = false
        if direct {
        } else if isCreator && (event["status"] as? String) == "pending_review" {
        } else if isCreator && nodeStatus == "unclaimed" {
            reReview = true
        } else {
            throw APIError.message("insufficient permissions", status: 403)
        }
        let text = { (key: String) in (fields[key] as? String) ?? "" }
        if fields["recurrence"] != nil && !text("recurrence").trimmingCharacters(in: .whitespaces).isEmpty {
            throw APIError.message("this quilt does not expand recurring events — add each date as its own event, or attach the calendar as an event source in the patch's settings", status: 400)
        }
        if fields["visibility"] != nil {
            guard ["public", "followers", "members"].contains(text("visibility")) else {
                throw APIError.message("visibility must be public, followers, or members", status: 400)
            }
            if !direct && text("visibility") != "public" {
                throw APIError.message("a suggested event is public; the patch chooses its tier once it is approved", status: 403)
            }
        }
        // The image pair, judged against whichever half is already stored.
        if fields["image_url"] != nil || fields["image_alt"] != nil {
            let url = (fields["image_url"] as? String) ?? (event["image_url"] as? String) ?? ""
            let alt = (fields["image_alt"] as? String) ?? (event["image_alt"] as? String) ?? ""
            if let problem = EventPosting.imageProblem(url: url, alt: alt) { throw APIError.message(problem, status: 400) }
        }
        if fields["event_url"] != nil, let problem = EventPosting.linkProblem(text("event_url")) {
            throw APIError.message(problem, status: 400)
        }
        let allowed = ["title", "description", "location", "latitude", "longitude", "starts_at", "ends_at", "timezone",
                       "recurrence", "visibility", "image_url", "image_alt", "event_url"]
        var edits = eventEdits[id] ?? [:]
        let sent = allowed.filter { fields.keys.contains($0) }
        guard !sent.isEmpty else { throw APIError.message("no valid fields to update", status: 400) }
        for key in sent { edits[key] = key == "event_url" ? text(key).trimmingCharacters(in: .whitespaces) : fields[key] }
        if reReview { edits["status"] = "pending_review" }
        eventEdits[id] = edits
        // The 200 is the bare event: no patch name, slug, status or links.
        var answer = (try? JSONSerialization.jsonObject(with: Data(edited(found.json, edits).utf8))) as? [String: Any] ?? [:]
        for key in ["node_name", "node_slug", "node_status", "links", "mentions"] { answer[key] = nil }
        return serialize(answer)
    }

    /// A node's JSON with its id leading, as every fixture node's does: the
    /// tree's `scope=my` narrowing finds a patch by the start of its JSON,
    /// and an edit laid over a node re-sorts its keys.
    private static func idFirst(_ json: String) -> String {
        guard !json.hasPrefix("{\"id\""),
              var object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let id = object.removeValue(forKey: "id") as? String else { return json }
        return "{\"id\":\"\(id)\"," + serialize(object).dropFirst()
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
    /// `--preview-admin` holds an admin row on the Film Club, where the
    /// admins decide: the one place offline a change is applied directly.
    private static let governanceAdmin = ProcessInfo.processInfo.arguments.contains("--preview-admin")

    /// How each patch with rules decides, as its governance config states it
    /// — the three setups a new proposal can meet. Common Thread and the
    /// Listening Room vote by majority; the Bike Kitchen and the Film Club
    /// are decided by their admins; the Repair Cafe decides at meetings, so
    /// a proposal there opens for discussion with no ballot and no clock.
    private struct FixtureRules {
        var method = "majority"
        var venue = "patchwork"
        var quorum = 0
        var hours = 0
        var eligible = 5
        var leadership = "maintainer"
    }
    private static var fixtureRules: [String: FixtureRules] = [
        "common-thread": FixtureRules(quorum: 20, hours: 336, eligible: 12),
        "listening-room": FixtureRules(hours: 168),
        "extra-1": FixtureRules(method: "admin"),
        memberSlug: FixtureRules(venue: "elsewhere", hours: 168, eligible: 6),
        adminSlug: FixtureRules(method: "admin", hours: 48, eligible: 4),
        marketSlug: FixtureRules(hours: 72, eligible: 4, leadership: "meritocratic"),
    ]

    /// The overview of a patch whose rules are only the table's.
    private static func plainOverview(_ slug: String) -> String? {
        guard let rules = fixtureRules[slug] else { return nil }
        let object: [String: Any] = [
            "rules": ["decision_method": rules.method, "quorum_percent": rules.quorum,
                      "default_vote_duration_hours": rules.hours, "leadership_model": rules.leadership,
                      "leadership_venue": "patchwork", "proposal_venue": rules.venue] as [String: Any],
            "admins": [] as [Any], "admins_withheld": true, "proposals_withheld": false, "election": NSNull(),
            "seats": [] as [Any], "next_term_end": "", "next_contest_opens": "", "membership_policy": "open",
            "member_count": rules.eligible, "document_count": docs.filter { $0.slug == slug && mayRead($0) }.count,
            "open_proposals": 0, "passed_proposals": 0,
            "rejected_proposals": 0, "needs_vote": 0,
        ]
        return overviewJSON(slug, base: serialize(object))
    }
    private static var proposalSerial = 0
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
        /// An admin of an admin-decides patch asked the members first.
        var advisory = false
        /// Who declined it, by name (`declined_by`), and when it was made
        /// official. A direct change is stamped at its own creation; nil
        /// leaves a voted change applied a day after it was raised.
        var declinedBy = ""
        var appliedMinutesAgo: Int?
        /// The member a nomination is about, by name.
        var targetName = ""
        /// An amendment's document (its filename) and the text it proposes.
        var targetDoc = ""
        var proposedBody = ""
        var proposedTitle = ""
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
            // The Film Club's admins decide (a `--preview-admin` launch is
            // one of them): a member's request waiting on the maintainer,
            // and a vote the members carried before the club handed its
            // decisions to its admins, waiting to be made official.
            FixtureProposal(
                id: "club-proposal-1", slug: adminSlug, nodeId: adminSlug, title: "Subtitles at every screening",
                body: "Half of us watch with the subtitles on at home. The projector can show them.",
                author: "Lena Fox", authorId: "u-lena", state: "awaiting_admin",
                createdMinutesAgo: 2 * day, endsInMinutes: nil, eligible: 4, quorum: 0, method: "admin"),
            FixtureProposal(
                id: "club-proposal-2", slug: adminSlug, nodeId: adminSlug, title: "Move screenings to the library",
                body: "The library’s back room is free on Fridays and has a screen.",
                author: "Ollie Grant", authorId: "u-ollie", status: "approved", state: "approved",
                createdMinutesAgo: 20 * day, endsInMinutes: -17 * day,
                ballots: [FixtureBallot(userId: "u-juno", name: "Juno Park", username: "juno", value: "approve"),
                          FixtureBallot(userId: "u-lena", name: "Lena Fox", username: "lena", value: "approve"),
                          FixtureBallot(userId: "u-ollie", name: "Ollie Grant", username: "ollie", value: "approve")],
                eligible: 4, quorum: 0),
        ]
    }

    private static var freshThreads: [String: [FixtureComment]] {
        [
            "demo-proposal": [
                FixtureComment(id: "comment-1", body: "I’d come on Tuesdays. Could we start at **six**, so people can come *straight* from work?",
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
        fields["target_user_name"] = p.targetName
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
        // A direct change is stamped applied at the instant it was made, as
        // `settleApplied` is handed the creation time; anything else later.
        if let applied = p.appliedMinutesAgo {
            fields["applied_at"] = stamp(minutesAgo: applied)
        } else if p.state == "in_effect" {
            fields["applied_at"] = p.ballots.isEmpty ? fields["created_at"]! : stamp(minutesAgo: max(0, p.createdMinutesAgo - day))
        } else {
            fields["applied_at"] = ""
        }
        // Both from the proposal's frozen terms, as `GetProposal` answers.
        fields["advisory"] = p.method == "admin"
        fields["can_decide"] = p.method == "admin" && p.status == "open" && role(p.slug) == "admin"
        fields["declined_by"] = p.declinedBy
        if !p.targetDoc.isEmpty {
            fields["target_doc"] = p.targetDoc
            fields["proposed_body"] = p.proposedBody
            fields["proposed_title"] = p.proposedTitle
            fields["doc_text_hidden"] = false
            fields["current_doc_content"] = currentText(slug: p.slug, target: p.targetDoc)
        }
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
        return "{\"items\":[\(items.joined(separator: ","))],\"next_cursor\":\"\",\"public_governance_record\":\"everyone\",\"awaiting_your_vote\":\(awaitingVote(slug))}"
    }

    /// How many open proposals on a patch still wait on this reader's
    /// ballot — the overview's `needs_vote` and the list's
    /// `awaiting_your_vote`, one count as on the server.
    private static func awaitingVote(_ slug: String) -> Int {
        proposals.filter { $0.slug == slug }.filter { p in
            guard p.status == "open", p.state == "voting", inRoom(slug) else { return false }
            if p.isElection { return p.phase == "voting" && !p.candidates.contains { $0.approvers.contains(me) } && !p.abstainers.contains(me) }
            return !p.ballots.contains { $0.userId == me }
        }.count
    }

    /// The overview's live half: what is open, what needs this reader, and
    /// the contest taking names.
    private static func overviewJSON(_ slug: String, base: String) -> String {
        guard var object = (try? JSONSerialization.jsonObject(with: Data(base.utf8))) as? [String: Any] else { return base }
        let mine = proposals.filter { $0.slug == slug }
        object["open_proposals"] = mine.filter { $0.status == "open" }.count
        object["needs_vote"] = awaitingVote(slug)
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
        if method == "POST", parts.count == 3, parts[0] == "nodes", parts[2] == "proposals" {
            return try propose(slug: parts[1], fields: fields)
        }
        if method == "POST", parts.count == 3, parts[0] == "nodes", parts[2] == "governance" {
            return try createDocument(slug: parts[1], fields: fields)
        }
        guard parts.count >= 2, parts[0] == "proposals" || parts[0] == "comments" else { return nil }
        guard signedIn else { throw APIError.unauthenticated }
        if parts[0] == "proposals" {
            let index = try proposalIndex(parts[1])
            var p = proposals[index]
            switch (method, Array(parts.dropFirst(2))) {
            case ("DELETE", []):
                // `WithdrawProposal`, in its order.
                guard p.status == "open" else { throw APIError.message("can only withdraw open proposals", status: 400) }
                guard !p.isElection else {
                    throw APIError.message("an election cannot be withdrawn: the calendar opens it and the electorate closes it (docs/adr/051)", status: 409)
                }
                guard p.authorId == me || role(p.slug) == "admin" else { throw APIError.message("insufficient permissions", status: 403) }
                p.status = "withdrawn"
                p.state = "withdrawn"
                proposals[index] = p
                return #"{"status":"withdrawn"}"#
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
            case ("POST", ["decide"]):
                // `DecideProposal`: the body first, then `maintainerDecidable`.
                let decision = (fields["decision"] as? String) ?? ""
                guard ["approve", "decline"].contains(decision) else {
                    throw APIError.message("decision must be approve or decline", status: 400)
                }
                try maintainerDecidable(p)
                if decision == "approve" {
                    (p.status, p.state, p.appliedMinutesAgo) = ("approved", "in_effect", 0)
                    applyAmendment(p)
                } else {
                    (p.status, p.state, p.declinedBy) = ("rejected", "rejected", myName)
                }
                p.endsInMinutes = p.endsInMinutes.map { min($0, 0) }
                proposals[index] = p
                return decision == "approve" ? #"{"status":"approved","state":"in_effect"}"# : #"{"status":"rejected","state":"rejected"}"#
            case ("POST", ["open-vote"]):
                try maintainerDecidable(p)
                guard p.state == "awaiting_admin" else { throw APIError.message("a vote is already open on this proposal", status: 409) }
                guard p.endsInMinutes == nil else {
                    throw APIError.message("the members have already been asked; the tally is on the proposal", status: 409)
                }
                var hours = (fields["duration_hours"] as? Int) ?? 0
                if hours <= 0 { hours = fixtureRules[p.slug]?.hours ?? 0 }
                if hours <= 0 { hours = 72 }
                p.state = "voting"
                p.endsInMinutes = hours * 60
                p.advisory = true
                proposals[index] = p
                return #"{"status":"ok","state":"voting"}"#
            case ("POST", ["apply"]):
                // `ApplyProposal`, in its order and words.
                guard role(p.slug) == "admin" else {
                    throw APIError.message("only this patch's admins can make proposals official", status: 403)
                }
                let approved = p.state == "approved" || p.status == "approved"
                let maintainers = p.method == "admin" && p.status == "open" && ["voting", "awaiting_admin"].contains(p.state)
                guard approved || maintainers else {
                    if p.status == "open" {
                        throw APIError.message("this patch decides proposals by vote; wait for the window to close", status: 409)
                    }
                    throw APIError.message("proposal cannot be applied in its current state", status: 400)
                }
                (p.status, p.state, p.appliedMinutesAgo) = ("approved", "in_effect", 0)
                applyAmendment(p)
                proposals[index] = p
                return #"{"status":"ok","state":"in_effect"}"#
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

    /// Market Friends' roster, for a `--preview-nominator` launch: the
    /// reader and one other admin, three members and a follower.
    private static let marketRoster: [(id: String, name: String, username: String, role: String)] = [
        ("u-ines", "Ines Duarte", "ines", "admin"),
        ("u-hana", "Hana Sato", "hana", "member"),
        ("u-ravi", "Ravi Iyer", "ravi", "member"),
        ("u-cleo", "Cleo Marsh", "cleo", "member"),
        ("u-dot", "Dot Reyes", "dot", "follower"),
    ]
    private static var marketMembers: String {
        var rows: [[String: Any]] = []
        if let mine = held[marketSlug] {
            rows.append(["id": "ch00", "user_id": me, "role": mine.role, "username": "samplereader", "display_name": myName])
        }
        rows += marketRoster.filter { $0.role != "follower" }.enumerated().map { index, row in
            ["id": "ch0\(index + 1)", "user_id": row.id, "role": row.role, "username": row.username, "display_name": row.name]
        }
        return serialize(["items": rows, "next_cursor": "", "member_count": rows.count, "follower_count": 1, "public_member_list": "everyone"])
    }

    /// `validateNomination`, in its order and words, over the fixture rules
    /// and Market Friends' roster.
    private static func nominationProblem(slug: String, nominee: String) -> String? {
        let rules = fixtureRules[slug] ?? FixtureRules()
        guard rules.leadership == "meritocratic" else {
            return "nominating an admin is the meritocratic model's mechanic; this patch fills admin seats another way"
        }
        guard role(slug) == "admin" else { return "only an admin of this patch can nominate someone for admin" }
        let row = slug == marketSlug ? marketRoster.first { $0.id == nominee } : nil
        guard let row, row.role != "follower" else { return "a nominee must be an active member of this patch" }
        if row.role == "admin" { return "that person is already an admin of this patch" }
        return nil
    }

    // MARK: Documents

    /// A patch's governance documents and each one's versions, newest
    /// last, so an amendment that takes effect writes a version and the
    /// history and the diff read it back. Common Thread publishes its
    /// charter and its amended lining; the Film Club keeps its screening
    /// rules to its members.
    private struct FixtureDoc {
        let id: String
        let slug: String
        let nodeId: String
        var title: String
        var kind = "charter"
        var visibility = "public"
        var createdMinutesAgo: Int
        /// (text, message, author, minutes ago), oldest first.
        var versions: [(text: String, message: String, author: String, minutesAgo: Int)]
        var body: String { versions.last?.text ?? "" }
        var filename: String { PreviewData.filename(title) }
    }

    /// `governance.Filename`: lower-cased, spaces to hyphens, anything else
    /// that is not a letter, a digit or a hyphen dropped.
    static func filename(_ title: String) -> String {
        let name = title.lowercased().replacingOccurrences(of: " ", with: "-")
        return String(name.unicodeScalars.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }.map(Character.init)) + ".md"
    }

    private static var freshDocs: [FixtureDoc] {
        let charter = "This patch keeps its own copy of the shared standards, and adds one paragraph of its own.\n\n## Open studio hours\n\nAnyone may use the studio during open hours. Tools go back where they were found, and whoever is last out locks the door.\n\n## Changing this\n\nAny member may propose a change. A majority carries it."
        let earlier = charter.replacingOccurrences(of: "Tools go back where they were found, and whoever", with: "Whoever")
        let first = "## Open studio hours\n\nAnyone may use the studio during open hours. Whoever is last out locks the door."
        let lining = "Every patch on this quilt starts by agreeing to the lining. This patch amended it.\n\n## Keep each other safe\n\nNobody is harmed, excluded, or diminished for who they are."
        let screening = "## Screenings\n\nWe screen on the first Friday of the month. Doors open at seven.\n\n## Choosing films\n\nAny member may suggest a film. The admins choose from the suggestions."
        return [
            FixtureDoc(id: "demo-doc", slug: "common-thread", nodeId: "demo-patch", title: "How we decide", createdMinutesAgo: 200 * day, versions: [
                (first, "Create How we decide", "Rowan Hale", 200 * day),
                (earlier, "Add the paragraph on changing this", "Rowan Hale", 120 * day),
                (charter, "Ask for tools to go back where they were found", "Imani Osei", 64 * day),
            ]),
            FixtureDoc(id: "demo-lining", slug: "common-thread", nodeId: "demo-patch", title: "Community Standards", kind: "lining",
                       createdMinutesAgo: 230 * day, versions: [
                (lining.replacingOccurrences(of: " This patch amended it.", with: ""), "Adopt the lining", "System", 230 * day),
                (lining, "Amend the lining", "Rowan Hale", 88 * day),
            ]),
            FixtureDoc(id: "club-doc", slug: adminSlug, nodeId: adminSlug, title: "Screening rules", visibility: "members",
                       createdMinutesAgo: 150 * day, versions: [(screening, "Create Screening rules", "Juno Park", 150 * day)]),
        ]
    }
    private static var docs: [FixtureDoc] = freshDocs
    private static var docSerial = 0

    private static func docJSON(_ d: FixtureDoc) -> [String: Any] {
        ["id": d.id, "node_id": d.nodeId, "title": d.title, "body": d.body, "kind": d.kind, "visibility": d.visibility,
         "version": d.versions.count, "created_by": "u1", "created_at": stamp(minutesAgo: d.createdMinutesAgo),
         "updated_at": stamp(minutesAgo: d.versions.last?.minutesAgo ?? d.createdMinutesAgo), "filename": d.filename]
    }

    /// Who may read a members-only document: its patch's members and admins.
    private static func mayRead(_ d: FixtureDoc) -> Bool { d.visibility == "public" || inRoom(d.slug) }

    /// The text an amendment would replace, as the repository holds it now.
    private static func currentText(slug: String, target: String) -> String {
        if target == "governance-rules.json" || target == "Governance Rules" { return rulesText(slug) }
        return docs.first { $0.slug == slug && ($0.filename == target || $0.title == target) }?.body ?? ""
    }

    /// An amendment taking effect: its document gains a version, or is
    /// written where the patch had no such document (`DirectEdit`'s rule).
    private static func applyAmendment(_ p: FixtureProposal, by author: String? = nil, message: String? = nil) {
        guard p.type == "amendment", !p.targetDoc.isEmpty else { return }
        if p.targetDoc == "governance-rules.json" { applyRules(p); return }
        let entry = (text: p.proposedBody, message: message ?? p.title, author: author ?? p.author, minutesAgo: 0)
        if let index = docs.firstIndex(where: { $0.slug == p.slug && ($0.filename == p.targetDoc || $0.title == p.targetDoc) }) {
            docs[index].versions.append(entry)
        }
    }

    // MARK: Rules

    /// Each patch's rules file, whole, as `GetGovernanceRules` answers it:
    /// every field, the ones nobody edits included, so the rules form has
    /// something to carry through.
    private static var ruleFiles: [String: [String: Any]] = [:]

    private static func rulesFile(_ slug: String) -> [String: Any]? {
        if let file = ruleFiles[slug] { return file }
        guard let rules = fixtureRules[slug] else { return nil }
        return [
            "decision_method": rules.method, "quorum_percent": rules.quorum, "default_vote_duration_hours": rules.hours,
            "amendment_threshold": "majority", "amendment_auto_apply": true, "min_voting_tenure_days": 0, "subject_recusal": false,
            "leadership_model": rules.leadership, "leadership_venue": "patchwork", "proposal_venue": rules.venue,
            "nomination_days": 0, "succession_method": "", "succession_policy": "longest_tenure", "admin_term_months": 0,
            "max_admins": 3, "inactivity_days": 90, "membership_policy": "open",
            "follower_permissions": ["events": true, "proposals": true, "charters": false, "members": true],
        ]
    }

    private static func rulesText(_ slug: String) -> String {
        guard let file = rulesFile(slug), let data = try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// A rules change taking effect: the file is replaced whole, and the
    /// rules the fixtures decide by follow it (`SyncRulesToDB`).
    private static func applyRules(_ p: FixtureProposal) {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(p.proposedBody.utf8))) as? [String: Any] else { return }
        ruleFiles[p.slug] = object
        var rules = fixtureRules[p.slug] ?? FixtureRules()
        rules.method = (object["decision_method"] as? String) ?? rules.method
        rules.venue = (object["proposal_venue"] as? String) ?? rules.venue
        rules.quorum = (object["quorum_percent"] as? Int) ?? rules.quorum
        rules.hours = (object["default_vote_duration_hours"] as? Int) ?? rules.hours
        rules.leadership = (object["leadership_model"] as? String) ?? rules.leadership
        fixtureRules[p.slug] = rules
    }

    /// `GET nodes/{slug}/governance/rules` and `…/electorate`.
    private static func rulesRead(_ path: String) throws -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 4, parts[0] == "nodes", parts[2] == "governance" else { return nil }
        switch parts[3] {
        case "rules":
            guard let file = rulesFile(parts[1]) else { throw APIError.message("node not found", status: 404) }
            return serialize(file)
        case "electorate":
            guard signedIn, inRoom(parts[1]) else { throw APIError.message("only this patch's members can see who votes here", status: 403) }
            let count = fixtureRules[parts[1]]?.eligible ?? 5
            let tenures = (0..<count).map { max(0, 400 - $0 * 37) }
            return serialize(["members": count, "tenure_days": tenures, "patch_age_days": 420])
        default:
            return nil
        }
    }

    /// The document reads: a patch's list, one document, its versions and a
    /// diff between two of them.
    private static func documentRead(_ path: String, query: [URLQueryItem]) throws -> String? {
        let parts = path.split(separator: "/").map(String.init)
        if parts.count == 3, parts[0] == "nodes", parts[2] == "governance", docs.contains(where: { $0.slug == parts[1] }) {
            let listed = docs.filter { $0.slug == parts[1] && mayRead($0) }
            return serialize(["items": listed.map(docJSON), "published_only": !inRoom(parts[1])])
        }
        guard parts.count >= 2, parts[0] == "governance", let d = docs.first(where: { $0.id == parts[1] }) else { return nil }
        guard mayRead(d) else { throw APIError.message("governance doc not found", status: 404) }
        if parts.count == 2 { return serialize(docJSON(d)) }
        let shas = d.versions.indices.map { "\(d.id)-v\($0 + 1)" }
        if parts[2] == "versions" {
            let items = d.versions.enumerated().reversed().map { index, v -> [String: Any] in
                ["sha": shas[index], "message": v.message, "author_name": v.author, "author_email": "",
                 "date": stamp(minutesAgo: v.minutesAgo), "version_number": index + 1]
            }
            return serialize(["items": items, "filename": d.filename])
        }
        if parts[2] == "diff" {
            let value = { (name: String) in query.first { $0.name == name }?.value ?? "" }
            guard let from = shas.firstIndex(of: value("from")), let to = shas.firstIndex(of: value("to")) else {
                throw APIError.message("version not found", status: 404)
            }
            let hunks = LineDiff.lines(old: d.versions[from].text, new: d.versions[to].text).map { line -> [String: Any] in
                ["type": line.kind == .added ? "insert" : (line.kind == .removed ? "delete" : "equal"), "text": line.text + "\n"]
            }
            return serialize(["from_sha": shas[from], "to_sha": shas[to], "filename": d.filename, "hunks": hunks, "unified": ""])
        }
        return nil
    }

    /// `POST nodes/{slug}/governance`: `CreateGovernanceDoc`, in its order
    /// and words.
    private static func createDocument(slug: String, fields: [String: Any]) throws -> String {
        guard signedIn else { throw APIError.unauthenticated }
        let known = ["common-thread", "listening-room"] + extraNames.indices.map { "extra-\($0)" }
        guard known.contains(slug) else { throw APIError.message("node not found", status: 404) }
        guard role(slug) == "admin" else { throw APIError.message("admin access required", status: 403) }
        let title = (fields["title"] as? String) ?? ""
        guard !title.isEmpty else { throw APIError.message("title is required", status: 400) }
        var visibility = (fields["visibility"] as? String) ?? ""
        if visibility.isEmpty { visibility = "members" }
        guard ["public", "members"].contains(visibility) else { throw APIError.message("visibility must be public or members", status: 400) }
        guard filename(title) != filename("Community Standards") else {
            throw APIError.message("that title is reserved for the lining", status: 400)
        }
        docSerial += 1
        let nodeId = slug == "common-thread" ? "demo-patch" : (slug == "listening-room" ? "demo-patch-2" : slug)
        let d = FixtureDoc(id: "new-doc-\(docSerial)", slug: slug, nodeId: nodeId, title: title, visibility: visibility,
                           createdMinutesAgo: 0, versions: [((fields["body"] as? String) ?? "", "Create \(title)", myName, 0)])
        docs.append(d)
        return serialize(docJSON(d))
    }

    /// `maintainerDecidable`'s refusals, in its order and words.
    private static func maintainerDecidable(_ p: FixtureProposal) throws {
        guard role(p.slug) == "admin" else {
            throw APIError.message("only this patch's admins can decide its proposals", status: 403)
        }
        guard p.method == "admin" else {
            throw APIError.message("this patch decides proposals by vote, not by its admins", status: 409)
        }
        guard !p.isElection else {
            throw APIError.message("an election is closed by the electorate, not by an admin (docs/adr/051)", status: 409)
        }
        guard p.status == "open", ["voting", "awaiting_admin"].contains(p.state) else {
            throw APIError.message("this proposal is not open for a decision", status: 409)
        }
    }

    /// `POST nodes/{slug}/proposals`: the server's refusals in its order and
    /// words, then its switch for the state a proposal is born in. Answered
    /// with the bare proposal, as the server answers.
    private static func propose(slug: String, fields: [String: Any]) throws -> String {
        guard signedIn else { throw APIError.unauthenticated }
        let known = ["common-thread", "listening-room"] + extraNames.indices.map { "extra-\($0)" }
        guard known.contains(slug) else { throw APIError.message("node not found", status: 404) }
        guard inRoom(slug) else { throw APIError.message("must be member of node", status: 403) }
        let title = (fields["title"] as? String) ?? ""
        guard !title.isEmpty else { throw APIError.message("title is required", status: 400) }
        var type = (fields["proposal_type"] as? String) ?? ""
        if type.isEmpty { type = "other" }
        guard ["amendment", "membership", "action", "other"].contains(type) else { throw APIError.message("invalid proposal_type", status: 400) }
        let target = (fields["target_user_id"] as? String) ?? ""
        if !target.isEmpty && type != "membership" {
            throw APIError.message("a proposal about a person must be of type membership", status: 400)
        }
        if type == "membership" && target.isEmpty {
            throw APIError.message("a membership proposal has to name the person it is about", status: 400)
        }
        if !target.isEmpty, let problem = nominationProblem(slug: slug, nominee: target) {
            throw APIError.message(problem, status: 409)
        }
        let targetDoc = (fields["target_doc"] as? String) ?? ""
        let rules = fixtureRules[slug] ?? FixtureRules()
        var hours = (fields["duration_hours"] as? Int) ?? 0
        if hours <= 0 { hours = rules.hours > 0 ? rules.hours : 72 }
        let isAdmin = role(slug) == "admin"
        let putToVote = (fields["put_to_vote"] as? Bool) ?? false
        let adminDecides = rules.method == "admin"
        let rulesDoc = targetDoc == "governance-rules.json" || targetDoc == "Governance Rules"
        if rules.venue == "elsewhere" && rulesDoc && !isAdmin {
            throw APIError.message("this patch decides at meetings, and the governance rules are not something a meeting adopts. Ask an admin to apply the change directly (docs/adr/053).", status: 409)
        }
        var (status, state) = ("open", "voting")
        if adminDecides && isAdmin && !putToVote { (status, state) = ("approved", "in_effect") }
        else if rules.venue == "elsewhere" && rulesDoc { (status, state) = ("approved", "in_effect") }
        else if rules.venue == "elsewhere" { state = "elsewhere" }
        else if adminDecides && !isAdmin { state = "awaiting_admin" }
        proposalSerial += 1
        let nodeId = slug == "common-thread" ? "demo-patch" : (slug == "listening-room" ? "demo-patch-2" : slug)
        let p = FixtureProposal(
            id: "new-proposal-\(proposalSerial)", slug: slug, nodeId: nodeId, title: title,
            body: (fields["body"] as? String) ?? "", type: type, author: myName, authorId: me,
            status: status, state: state, createdMinutesAgo: 0,
            endsInMinutes: state == "voting" ? hours * 60 : nil,
            eligible: rules.eligible, quorum: rules.quorum, method: rules.method,
            advisory: adminDecides && isAdmin && putToVote,
            targetName: marketRoster.first { $0.id == target }?.name ?? "",
            targetDoc: type == "amendment" ? targetDoc : "",
            proposedBody: type == "amendment" ? ((fields["proposed_body"] as? String) ?? "") : "",
            proposedTitle: type == "amendment" ? ((fields["proposed_title"] as? String) ?? "") : "")
        if state == "in_effect" { applyAmendment(p, by: myName, message: (fields["change_summary"] as? String) ?? title) }
        proposals.append(p)
        var answer = listFields(p)
        answer["duration_hours"] = hours
        answer.removeValue(forKey: "author_name")
        return serialize(answer)
    }

    /// The governance reads that are not fixed text.
    private static func governanceRead(_ path: String, query: [URLQueryItem]) throws -> String? {
        if let answer = try documentRead(path, query: query) { return answer }
        if let answer = try rulesRead(path) { return answer }
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


    // MARK: The noticeboard

    /// Two boards (web ADR 081). Common Thread's is the full one — members
    /// put up notices there, and the fixture reader is in that room only on
    /// a `--preview-member` launch. The Repair Cafe's is the one a plain
    /// sign-in lands in: its admins put up the notices, so a member reads
    /// and replies and is offered nothing to post with.
    private struct FixtureNotice {
        let id: String
        let slug: String
        let authorId: String
        let authorName: String
        let authorUsername: String
        var title: String
        var body: String
        var imageURL = ""
        var imageAlt = ""
        var repliesOpen = true
        var membersTold = false
        let createdMinutesAgo: Int
        var editedMinutesAgo: Int?
    }

    private struct FixtureReply {
        let id: String
        let noticeId: String
        let authorId: String
        let authorName: String
        let authorUsername: String
        var body: String
        let createdMinutesAgo: Int
    }

    private static let fixedBoards: [String: (nodeId: String, posting: String, repliesDefault: Bool)] = [
        "common-thread": ("demo-patch", "members", true),
        memberSlug: (memberSlug, "admins", true),
        adminSlug: (adminSlug, "members", true),
    ]
    /// The boards as `PATCH nodes/{slug}` has left them: the two settings
    /// live on the patch's row, so an edit there is what the board reads.
    private static var boards: [String: (nodeId: String, posting: String, repliesDefault: Bool)] {
        fixedBoards.reduce(into: [:]) { result, entry in
            let edits = nodeEdits[entry.key] ?? [:]
            result[entry.key] = (entry.value.nodeId,
                                 (edits["notice_posting"] as? String) ?? entry.value.posting,
                                 (edits["notice_replies_default"] as? Bool) ?? entry.value.repliesDefault)
        }
    }

    /// Newest first, the order the server serves them in. One was put up
    /// by the reader, one has its replies switched off with one kept, and
    /// one outlived its author's account.
    private static var notices: [FixtureNotice] = [
        FixtureNotice(id: "notice-4", slug: "common-thread", authorId: "u1", authorName: "Rowan Hale", authorUsername: "rowan",
                      title: "The kiln is out of action",
                      body: "The element went on Thursday. A new one is **on order** and should be here *next week*.\n\nUntil then:\n\n- Bisque firings are paused.\n- Leave finished pieces on the left-hand shelf, labelled with your name.\n\nRowan\nStudio desk, most evenings",
                      membersTold: true, createdMinutesAgo: 3 * 60),
        FixtureNotice(id: "notice-3", slug: "common-thread", authorId: me, authorName: "Sample Reader", authorUsername: "samplereader",
                      title: "Spare fabric on the back shelf",
                      body: "Two boxes of offcuts, free to whoever can use them.",
                      createdMinutesAgo: 2 * day),
        FixtureNotice(id: "notice-2", slug: "common-thread", authorId: "u2", authorName: "Imani Osei", authorUsername: "imani",
                      title: "Keys for Tuesday evenings",
                      body: "Sorted. Thank you, everyone who offered.",
                      repliesOpen: false, createdMinutesAgo: 6 * day),
        FixtureNotice(id: "notice-1", slug: "common-thread", authorId: "gone", authorName: "Deleted account", authorUsername: "",
                      title: "Welcome to the board",
                      body: "Notices for the people who use the studio. Nobody outside it reads them.",
                      createdMinutesAgo: 40 * day),
        FixtureNotice(id: "notice-r1", slug: memberSlug, authorId: "rc1", authorName: "Dee Marsh", authorUsername: "deemarsh",
                      title: "Soldering irons are back",
                      body: "Both irons are back from repair and on the bench by the window.\n\nPlease switch them off at the wall when you finish.",
                      membersTold: true, createdMinutesAgo: 9 * day),
        // The Film Club's board, which its admin keeps on a
        // `--preview-admin` launch: one notice reported, and one whose
        // reply was.
        FixtureNotice(id: "notice-f2", slug: adminSlug, authorId: "u-lena", authorName: "Lena Fox", authorUsername: "lena",
                      title: "Cheap DVDs, message me",
                      body: "Boxes of them. Five for a tenner, collection only.",
                      createdMinutesAgo: 5 * 60),
        FixtureNotice(id: "notice-f1", slug: adminSlug, authorId: "u-juno", authorName: "Juno Park", authorUsername: "juno",
                      title: "Projector bulb ordered",
                      body: "The bulb went during the second reel on Friday. A new one arrives on Wednesday.",
                      createdMinutesAgo: 3 * day),
    ]

    /// Oldest first, as the server serves them.
    private static var noticeReplies: [FixtureReply] = [
        FixtureReply(id: "reply-1", noticeId: "notice-2", authorId: "u1", authorName: "Rowan Hale", authorUsername: "rowan",
                     body: "I can hold a set.", createdMinutesAgo: 5 * day),
        FixtureReply(id: "reply-2", noticeId: "notice-4", authorId: "u2", authorName: "Imani Osei", authorUsername: "imani",
                     body: "Thanks for chasing it. Is the small kiln still fine for glaze tests?", createdMinutesAgo: 150),
        FixtureReply(id: "reply-3", noticeId: "notice-4", authorId: me, authorName: "Sample Reader", authorUsername: "samplereader",
                     body: "I can drive over and collect the part if that is quicker.", createdMinutesAgo: 90),
        FixtureReply(id: "reply-r1", noticeId: "notice-r1", authorId: "rc2", authorName: "Kofi Adu", authorUsername: "kofi",
                     body: "Good news. I will bring the spare tips on Saturday.", createdMinutesAgo: 8 * day),
        FixtureReply(id: "reply-f1", noticeId: "notice-f1", authorId: "u-ollie", authorName: "Ollie Grant", authorUsername: "ollie",
                     body: "Typical. Whoever broke it should be made to pay for it.", createdMinutesAgo: 2 * day),
    ]
    private static var noticeSerial = 100
    private static var reportSerial = 0

    /// The Film Club's report queue (`content_reports` with its `node_id`):
    /// three waiting — one about a notice, one about a reply, and one about
    /// a notice its author has since taken down — and one each already
    /// resolved and dismissed.
    private struct FixtureReport {
        let id: String
        let entityType: String
        let entityId: String
        let reason: String
        let details: String
        let reporterId: String
        let reporterName: String
        var status = "pending"
        var note = ""
        let minutesAgo: Int
    }
    private static var freshReports: [FixtureReport] {
        [
            FixtureReport(id: "report-f1", entityType: "notice", entityId: "notice-f2", reason: "Spam or scam",
                          details: "The same post is on three other boards.", reporterId: "u-juno", reporterName: "Juno Park",
                          minutesAgo: 3 * 60),
            FixtureReport(id: "report-f2", entityType: "reply", entityId: "reply-f1", reason: "Harassment or intimidation",
                          details: "", reporterId: "u-lena", reporterName: "Lena Fox", minutesAgo: day),
            FixtureReport(id: "report-f3", entityType: "notice", entityId: "notice-f0", reason: "Something else",
                          details: "It had the wrong date on it.", reporterId: "u-ollie", reporterName: "Ollie Grant",
                          minutesAgo: 2 * day),
            FixtureReport(id: "report-f4", entityType: "notice", entityId: "notice-f1", reason: "Something else",
                          details: "No date for the next screening.", reporterId: "u-ollie", reporterName: "Ollie Grant",
                          status: "resolved", note: "Asked Juno to add the date.", minutesAgo: 6 * day),
            FixtureReport(id: "report-f5", entityType: "reply", entityId: "reply-f1", reason: "Spam or scam",
                          details: "", reporterId: "u-juno", reporterName: "Juno Park", status: "dismissed", minutesAgo: 7 * day),
        ]
    }
    private static var reports: [FixtureReport] = freshReports

    /// A queue row as `ListPatchReports` serves it, with the reported thing
    /// quoted from the board as it stands now.
    private static func reportJSON(_ r: FixtureReport) -> [String: Any] {
        var target = ""
        var noticeId = ""
        var gone = true
        if r.entityType == "notice", let n = notices.first(where: { $0.id == r.entityId }) {
            target = n.title; noticeId = n.id; gone = false
        } else if r.entityType == "reply", let reply = noticeReplies.first(where: { $0.id == r.entityId }) {
            target = reply.body; noticeId = reply.noticeId; gone = false
        } else if r.entityType == "notice" {
            noticeId = r.entityId
        }
        return [
            "id": r.id, "reporter_id": r.reporterId, "entity_type": r.entityType, "entity_id": r.entityId,
            "reason": r.reason, "details": r.details, "status": r.status, "resolution_note": r.note,
            "created_at": stamp(minutesAgo: r.minutesAgo), "updated_at": stamp(minutesAgo: r.minutesAgo),
            "node_id": adminSlug, "reporter_name": r.reporterName, "target": target, "notice_id": noticeId, "gone": gone,
        ]
    }

    /// `ListPatchReports`: the patch's own admin only — an instance admin
    /// with no role here is answered 404, like the room.
    private static func reportsRead(_ slug: String, query: [URLQueryItem]) throws -> String {
        guard signedIn else { throw APIError.unauthenticated }
        guard role(slug) == "admin" else { throw APIError.message("not found", status: 404) }
        let status = query.first { $0.name == "status" }?.value.flatMap { $0.isEmpty ? nil : $0 } ?? "pending"
        let rows = slug == adminSlug ? reports.filter { $0.status == status } : []
        let answer = page(rows, id: \.id, query: query)
        return serialize(["items": answer.rows.map(reportJSON), "next_cursor": answer.next])
    }

    /// `UpdatePatchReport`, in its order and its words.
    private static func reportAct(_ slug: String, id: String, fields: [String: Any]) throws -> String {
        guard signedIn else { throw APIError.unauthenticated }
        guard role(slug) == "admin" else { throw APIError.message("not found", status: 404) }
        guard slug == adminSlug, let index = reports.firstIndex(where: { $0.id == id }) else {
            throw APIError.message("report not found", status: 404)
        }
        guard reports[index].status == "pending" else { throw APIError.message("this report has already been reviewed", status: 400) }
        let report = reports[index]
        var status = "resolved"
        switch (fields["action"] as? String) ?? "" {
        case "dismiss":
            status = "dismissed"
        case "remove":
            if report.entityType == "notice" {
                notices.removeAll { $0.id == report.entityId }
                noticeReplies.removeAll { $0.noticeId == report.entityId }
            } else {
                noticeReplies.removeAll { $0.id == report.entityId }
            }
        case "close_replies":
            let noticeId = report.entityType == "reply"
                ? noticeReplies.first { $0.id == report.entityId }?.noticeId ?? report.entityId : report.entityId
            if let n = notices.firstIndex(where: { $0.id == noticeId }) { notices[n].repliesOpen = false }
        default:
            throw APIError.message("action must be dismiss, remove, or close_replies", status: 400)
        }
        reports[index].status = status
        reports[index].note = (fields["resolution_note"] as? String) ?? ""
        return "{\"status\":\"\(status)\"}"
    }

    private static func noticeJSON(_ n: FixtureNotice) -> [String: Any] {
        [
            "id": n.id, "node_id": boards[n.slug]?.nodeId ?? "", "author_id": n.authorId,
            "title": n.title, "body": n.body, "image_url": n.imageURL, "image_alt": n.imageAlt,
            "replies_open": n.repliesOpen, "members_told": n.membersTold,
            "created_at": stamp(minutesAgo: n.createdMinutesAgo),
            "updated_at": stamp(minutesAgo: n.editedMinutesAgo ?? n.createdMinutesAgo),
            "author_username": n.authorUsername, "author_display_name": n.authorName,
            "reply_count": noticeReplies.filter { $0.noticeId == n.id }.count,
        ]
    }

    private static func replyJSON(_ r: FixtureReply) -> [String: Any] {
        [
            "id": r.id, "notice_id": r.noticeId, "author_id": r.authorId, "body": r.body,
            "created_at": stamp(minutesAgo: r.createdMinutesAgo), "updated_at": stamp(minutesAgo: r.createdMinutesAgo),
            "author_username": r.authorUsername, "author_display_name": r.authorName,
        ]
    }

    /// One page of rows after a cursor, and the cursor after it: the id of
    /// the last row served, or empty on the last page.
    private static func page<Row>(_ rows: [Row], id: (Row) -> String, query: [URLQueryItem]) -> (rows: [Row], next: String) {
        let asked = Int(query.first { $0.name == "limit" }?.value ?? "") ?? 20
        let limit = asked <= 0 ? 20 : min(asked, 100)
        let after = query.first { $0.name == "after" }?.value ?? ""
        let start = after.isEmpty ? 0 : (rows.firstIndex { id($0) == after }.map { $0 + 1 } ?? rows.count)
        let slice = Array(rows.dropFirst(start).prefix(limit))
        let more = start + slice.count < rows.count
        return (slice, more ? (slice.last.map(id) ?? "") : "")
    }

    /// The notice, for a reader in its room. Anybody else — and a notice
    /// that is not there — gets the same 404, as the server answers.
    private static func noticeIndex(_ id: String) throws -> Int {
        guard let index = notices.firstIndex(where: { $0.id == id }), inRoom(notices[index].slug) else {
            throw APIError.message("notice not found", status: 404)
        }
        return index
    }

    private static func noticeboardRead(_ path: String, query: [URLQueryItem]) throws -> String? {
        let parts = path.split(separator: "/").map(String.init)
        if parts.count == 3, parts[0] == "nodes", parts[2] == "notices" {
            guard signedIn else { throw APIError.unauthenticated }
            guard let board = boards[parts[1]], inRoom(parts[1]) else { throw APIError.message("not found", status: 404) }
            let answer = page(notices.filter { $0.slug == parts[1] }, id: { $0.id }, query: query)
            return serialize([
                "items": answer.rows.map(noticeJSON), "next_cursor": answer.next,
                "may_post": board.posting == "members" || role(parts[1]) == "admin",
                "replies_default": board.repliesDefault, "notice_posting": board.posting,
            ])
        }
        guard parts.first == "notices", parts.count == 2 || (parts.count == 3 && parts[2] == "replies") else { return nil }
        guard signedIn else { throw APIError.unauthenticated }
        let n = notices[try noticeIndex(parts[1])]
        if parts.count == 2 {
            return serialize([
                "notice": noticeJSON(n), "node_slug": n.slug,
                "may_edit": n.authorId == me, "may_manage": n.authorId == me || role(n.slug) == "admin",
            ])
        }
        let answer = page(noticeReplies.filter { $0.noticeId == n.id }, id: { $0.id }, query: query)
        return serialize(["items": answer.rows.map(replyJSON), "next_cursor": answer.next])
    }

    private static func noticeDraft(_ fields: [String: Any], over n: FixtureNotice? = nil) -> NoticeDraft {
        func text(_ key: String, _ old: String?) -> String {
            ((fields[key] as? String) ?? old ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return NoticeDraft(title: text("title", n?.title), body: text("body", n?.body),
                           imageURL: text("image_url", n?.imageURL), imageAlt: text("image_alt", n?.imageAlt))
    }

    /// The noticeboard's writes, in the server's order of refusals. Nil
    /// means "not one of these".
    private static func noticeboardWrite(_ method: String, _ path: String, fields: [String: Any]) throws -> String? {
        let parts = path.split(separator: "/").map(String.init)
        let isCreate = parts.count == 3 && parts[0] == "nodes" && parts[2] == "notices"
        guard isCreate || ["notices", "replies", "reports"].contains(parts.first ?? "") else { return nil }
        guard signedIn else { throw APIError.unauthenticated }

        if isCreate {
            guard method == "POST" else { throw APIError.status(405) }
            let slug = parts[1]
            guard let board = boards[slug], inRoom(slug) else { throw APIError.message("not found", status: 404) }
            if board.posting == "admins" && role(slug) != "admin" {
                throw APIError.message("this patch's admins put up its notices", status: 403)
            }
            let draft = noticeDraft(fields)
            if let problem = Noticeboard.problem(draft) { throw APIError.message(problem, status: 400) }
            noticeSerial += 1
            let notice = FixtureNotice(
                id: "notice-\(noticeSerial)", slug: slug, authorId: me, authorName: myName,
                authorUsername: (accountFields["username"] as? String) ?? "samplereader",
                title: draft.title, body: draft.body, imageURL: draft.imageURL,
                imageAlt: draft.imageURL.isEmpty ? "" : draft.imageAlt,
                repliesOpen: (fields["replies_open"] as? Bool) ?? board.repliesDefault,
                membersTold: (fields["tell_members"] as? Bool) ?? false, createdMinutesAgo: 0)
            notices.insert(notice, at: 0)
            return serialize(noticeJSON(notice))
        }

        if parts[0] == "reports" {
            guard method == "POST", parts.count == 1 else { throw APIError.status(405) }
            let kind = (fields["entity_type"] as? String) ?? ""
            let id = (fields["entity_id"] as? String) ?? ""
            let reason = ((fields["reason"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !kind.isEmpty, !id.isEmpty, !reason.isEmpty else {
                throw APIError.message("entity_type, entity_id, and reason are required", status: 400)
            }
            // A person: any account the quilt has a row for, as the server
            // checks it, and to the instance admins' queue.
            if kind == "user" {
                guard people.contains(where: { $0.id == id }) || id == me else {
                    throw APIError.message("target entity not found", status: 404)
                }
                reportSerial += 1
                return "{\"id\":\"report-\(reportSerial)\",\"status\":\"ok\"}"
            }
            let noticeId = kind == "reply" ? noticeReplies.first { $0.id == id }?.noticeId : (kind == "notice" ? id : nil)
            guard let noticeId, (try? noticeIndex(noticeId)) != nil else {
                throw APIError.message("target entity not found", status: 404)
            }
            reportSerial += 1
            return "{\"id\":\"report-\(reportSerial)\",\"status\":\"ok\"}"
        }

        if parts[0] == "replies" {
            guard parts.count == 2, let index = noticeReplies.firstIndex(where: { $0.id == parts[1] }) else {
                throw APIError.message("reply not found", status: 404)
            }
            let reply = noticeReplies[index]
            let slug = notices[try noticeIndex(reply.noticeId)].slug
            guard method == "DELETE" else { throw APIError.status(405) }
            guard reply.authorId == me || role(slug) == "admin" else { throw APIError.message("insufficient permissions", status: 403) }
            noticeReplies.remove(at: index)
            return #"{"status":"deleted"}"#
        }

        // notices/{id}[/replies]
        guard parts.count >= 2 else { return nil }
        let index = try noticeIndex(parts[1])
        var notice = notices[index]
        let mine = notice.authorId == me
        let manages = mine || role(notice.slug) == "admin"

        if parts.count == 3, parts[2] == "replies", method == "POST" {
            guard notice.repliesOpen else { throw APIError.message("replies are off on this notice", status: 403) }
            let body = (fields["body"] as? String) ?? ""
            if let problem = Noticeboard.replyProblem(body) { throw APIError.message(problem, status: 400) }
            noticeSerial += 1
            let reply = FixtureReply(id: "reply-\(noticeSerial)", noticeId: notice.id, authorId: me, authorName: myName,
                                     authorUsername: (accountFields["username"] as? String) ?? "samplereader",
                                     body: body.trimmingCharacters(in: .whitespacesAndNewlines), createdMinutesAgo: 0)
            noticeReplies.append(reply)
            return serialize(replyJSON(reply))
        }
        guard parts.count == 2 else { throw APIError.status(405) }
        switch method {
        case "PATCH":
            if ["title", "body", "image_url", "image_alt"].contains(where: { fields[$0] != nil }) {
                guard mine else { throw APIError.message("only the author can edit a notice", status: 403) }
                let draft = noticeDraft(fields, over: notice)
                if let problem = Noticeboard.problem(draft) { throw APIError.message(problem, status: 400) }
                notice.title = draft.title; notice.body = draft.body
                notice.imageURL = draft.imageURL; notice.imageAlt = draft.imageURL.isEmpty ? "" : draft.imageAlt
                notice.editedMinutesAgo = 0
            }
            if let open = fields["replies_open"] as? Bool {
                guard manages else { throw APIError.message("insufficient permissions", status: 403) }
                notice.repliesOpen = open
            }
            notices[index] = notice
            return serialize(noticeJSON(notice))
        case "DELETE":
            guard manages else { throw APIError.message("insufficient permissions", status: 403) }
            notices.remove(at: index)
            noticeReplies.removeAll { $0.noticeId == notice.id }
            return #"{"status":"deleted"}"#
        default:
            throw APIError.status(405)
        }
    }

    // MARK: People: the contact card, visibility, claims, preferences

    /// One item on the fixture reader's contact card. The card starts empty,
    /// so the page's empty states are what a first visit sees, and every
    /// item on it is one a test added.
    private struct FixtureContact {
        let id: String
        var kind: String
        var value: String
        var label: String
        var position: Int
    }
    private static var contactItems: [FixtureContact] = []
    private static var contactSerial = 0
    /// Slug → the item ids that patch reads, in the order they were given.
    private static var contactShares: [String: [String]] = [:]
    /// The slugs whose membership the reader has hidden (web ADR 006).
    private static var hiddenMemberships: Set<String> = []
    /// Type → channel → enabled: the rows a `PUT` wrote. A type with no row
    /// sits on its default and is not `decided`.
    private static var preferenceRows: [String: [String: Bool]] = [:]

    private static func resetPeople() {
        contactItems = []
        contactShares = [:]
        hiddenMemberships = []
        preferenceRows = [:]
        clubRoster = freshClubRoster
    }

    private static func sharesCount(_ slug: String) -> Int {
        (contactShares[slug] ?? []).filter { id in contactItems.contains { $0.id == id } }.count
    }

    private static func contactJSON(_ item: FixtureContact, extra: [String: Any] = [:]) -> [String: Any] {
        var fields: [String: Any] = ["id": item.id, "kind": item.kind, "value": item.value, "position": item.position]
        // `omitempty`, as the server writes them.
        if !item.label.isEmpty { fields["label"] = item.label }
        for (key, value) in extra { fields[key] = value }
        return fields
    }

    /// The server's own checks, in its order and its words (`contact_items.go`).
    private static func validateContact(kind: String, value: String, label: String) throws {
        guard ["phone", "email", "handle", "note"].contains(kind) else {
            throw APIError.message("kind must be phone, email, handle or note", status: 400)
        }
        guard !value.isEmpty else { throw APIError.message("an item needs a value — delete it instead of emptying it", status: 400) }
        switch kind {
        case "phone" where value.utf8.count > 60: throw APIError.message("phone must be 60 characters or fewer", status: 400)
        case "email" where value.utf8.count > 254: throw APIError.message("email must be 254 characters or fewer", status: 400)
        case "email" where !value.contains("@") || value.contains(where: { $0 == " " || $0 == "\t" || $0 == "\n" }):
            throw APIError.message("that doesn't look like an email address", status: 400)
        case "handle" where value.utf8.count > 100: throw APIError.message("handle must be 100 characters or fewer", status: 400)
        case "note" where value.utf8.count > 200: throw APIError.message("note must be 200 characters or fewer", status: 400)
        default: break
        }
        guard label.utf8.count <= 40 else { throw APIError.message("label must be 40 characters or fewer", status: 400) }
    }

    /// The registry's shape, cut down: every category, a few types in each,
    /// and the server's defaults — in-app on, email on for the urgent ones,
    /// and the monthly bulletin off everywhere until asked for.
    private static let preferenceCatalog: [(id: String, label: String, description: String, types: [(type: String, label: String, high: Bool)])] = [
        ("proposals", "Proposals", "New proposals, voting updates, deadlines", [
            ("proposal.new", "New proposal in your patch", false),
            ("proposal.voting", "Voting has started", false),
            ("proposal.approved", "Proposal approved", true),
            ("proposal.deadline", "Voting ends in 24 hours and you have not voted", true),
            ("proposal.comment", "Comment on a proposal you're in", false),
        ]),
        ("governance", "Governance", "Document and rules changes", [
            ("governance.doc_updated", "Document updated", false),
            ("governance.rules_changed", "Rules changed", false),
        ]),
        ("membership", "Membership", "Join/leave notifications for admins", [
            ("membership.joined", "New member joined", false),
            ("membership.request", "Membership request pending", true),
            ("membership.approved", "Your membership was approved", true),
        ]),
        ("events", "Events", "Submissions, links, and program offers", [
            ("event.suggested", "Event suggested to your patch", true),
            ("event.submission_approved", "Your event was approved", true),
        ]),
        ("admin", "Admin", "Claim requests, submissions, suggested tags", [
            ("admin.claim_request", "New patch claim request", true),
            ("claim.approved", "Your claim was approved", true),
        ]),
        ("noticeboard", "Noticeboard", "A notice whose author chose to tell members, replies on notices you're in, and reports for admins", [
            ("notice.posted", "A notice for your patch", false),
            ("notice.reply", "Reply on a notice you're in", false),
            ("notice.reported", "A notice or reply was reported", true),
        ]),
        ("quilt", "The quilt", "A monthly note naming the patches that joined. Off unless you ask for it, and the one notification here that is not about you.", [
            ("quilt.bulletin", "New patches this month", false),
        ]),
    ]
    private static let preferenceChannels = ["in_app", "email"]

    private static func preferencesJSON() -> String {
        let categories: [[String: Any]] = preferenceCatalog.map { category in
            let types: [[String: Any]] = category.types.map { kind in
                var channels: [String: Bool] = [:]
                for channel in preferenceChannels {
                    let fallback = kind.type == "quilt.bulletin" ? false : (channel == "in_app" ? true : kind.high)
                    channels[channel] = preferenceRows[kind.type]?[channel] ?? fallback
                }
                return ["type": kind.type, "label": kind.label, "channels": channels, "decided": preferenceRows[kind.type] != nil]
            }
            return ["id": category.id, "label": category.label, "description": category.description, "types": types]
        }
        return serialize(["channels": preferenceChannels, "categories": categories])
    }

    private static func peopleRead(_ path: String, query: [URLQueryItem]) throws -> String? {
        let parts = path.split(separator: "/").map(String.init)
        switch path {
        case "users/me/contact-items":
            guard signedIn else { throw APIError.unauthenticated }
            let items = contactItems.map { item -> [String: Any] in
                let count = contactShares.values.filter { $0.contains(item.id) }.count
                return contactJSON(item, extra: count > 0 ? ["shared_with": count] : [:])
            }
            return serialize(["items": items])
        case "users/me/invitations":
            guard signedIn else { throw APIError.unauthenticated }
            let items = invited.sorted().map { slug -> [String: Any] in
                let facts = patchFacts(slug)
                return ["id": "invite-\(slug)", "node_id": facts.id, "node_slug": slug, "node_name": facts.name,
                        "status": "invited", "invited_at": stamp(minutesAgo: 1)]
            }
            return serialize(["items": items])
        case "users/me/claims":
            guard signedIn else { throw APIError.unauthenticated }
            // Only claims on a patch still unclaimed, newest first, as `MyClaims` serves them.
            let items = claims.filter { c in
                ["pending", "approved"].contains(c.status) && claimableIndex(c.slug).map(isUnclaimedExtra) == true
            }
            .sorted { $0.createdMinutesAgo < $1.createdMinutesAgo }
            .map { c -> [String: Any] in
                var row: [String: Any] = ["id": c.id, "method": c.method, "status": c.status,
                                          "created_at": stamp(minutesAgo: c.createdMinutesAgo),
                                          "node_slug": c.slug, "node_name": patchName(c.slug)]
                if let left = c.setupExpiresIn { row["setup_expires_at"] = stamp(minutesAgo: -left) }
                return row
            }
            return serialize(["items": items])
        case "me/nodes" where query.contains { $0.name == "status" && $0.value == "archived" }:
            guard signedIn else { throw APIError.unauthenticated }
            // A duplicate of the Repair Cafe, archived by its admin — the
            // same name as the live one, which is why the row shows its address.
            return "{\"items\":[{\"id\":\"membership-annex\",\"user_id\":\"demo-user\",\"node_id\":\"repair-cafe-annex\",\"role\":\"admin\"," +
                "\"status\":\"active\",\"visible\":true,\"joined_at\":\"2025-11-02T10:00:00Z\",\"node_name\":\"\(extraNames[6])\"," +
                "\"node_slug\":\"repair-cafe-2\",\"node_description\":\"\",\"node_visibility\":\"public\",\"membership_policy\":\"open\"," +
                "\"node_status\":\"archived\",\"contact_items_shared\":0}],\"next_cursor\":\"\"}"
        case "notifications/preferences":
            guard signedIn else { throw APIError.unauthenticated }
            return preferencesJSON()
        default:
            break
        }
        if parts.count == 3, parts[0] == "nodes", parts[2] == "contact-shares" {
            guard signedIn else { throw APIError.unauthenticated }
            guard holdable.contains(where: { $0.slug == parts[1] }) else { throw APIError.message("patch not found", status: 404) }
            let shared = Set(contactShares[parts[1]] ?? [])
            return serialize([
                "items": contactItems.map { contactJSON($0, extra: ["shared": shared.contains($0.id)]) },
                "can_share": inRoom(parts[1]),
            ])
        }
        return nil
    }

    private static func peopleWrite(_ method: String, _ path: String, fields: [String: Any]) throws -> String? {
        let parts = path.split(separator: "/").map(String.init)
        let isCard = parts.count >= 3 && parts[0] == "users" && parts[1] == "me" && parts[2] == "contact-items"
        let isVisibility = parts.count == 4 && parts[0] == "users" && parts[1] == "me" && parts[2] == "memberships"
        let isShares = parts.count == 3 && parts[0] == "nodes" && parts[2] == "contact-shares"
        let isPreferences = path == "notifications/preferences"
        guard isCard || isVisibility || isShares || isPreferences else { return nil }
        guard signedIn else { throw APIError.unauthenticated }
        func text(_ key: String) -> String? { (fields[key] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }

        if isCard {
            switch (method, parts.count) {
            case ("POST", 3):
                let kind = (fields["kind"] as? String) ?? ""
                let value = text("value") ?? "", label = text("label") ?? ""
                try validateContact(kind: kind, value: value, label: label)
                guard contactItems.count < 12 else { throw APIError.message("a contact card holds 12 items at most", status: 400) }
                contactSerial += 1
                let item = FixtureContact(id: "contact-\(contactSerial)", kind: kind, value: value, label: label,
                                          position: (contactItems.map(\.position).max() ?? -1) + 1)
                contactItems.append(item)
                return serialize(contactJSON(item))
            case (_, 4), (_, 5):
                guard let index = contactItems.firstIndex(where: { $0.id == parts[3] }) else {
                    throw APIError.message("contact item not found", status: 404)
                }
                if parts.count == 5 {
                    guard method == "DELETE", parts[4] == "shares" else { throw APIError.status(405) }
                    let id = contactItems[index].id
                    var from = 0
                    for slug in contactShares.keys where contactShares[slug]?.contains(id) == true {
                        contactShares[slug]?.removeAll { $0 == id }
                        from += 1
                    }
                    return "{\"unshared_from\":\(from)}"
                }
                switch method {
                case "PATCH":
                    var item = contactItems[index]
                    if let kind = fields["kind"] as? String {
                        guard ["phone", "email", "handle", "note"].contains(kind) else {
                            throw APIError.message("kind must be phone, email, handle or note", status: 400)
                        }
                        item.kind = kind
                    }
                    if let value = text("value") { item.value = value }
                    if let label = text("label") { item.label = label }
                    try validateContact(kind: item.kind, value: item.value, label: item.label)
                    contactItems[index] = item
                    return serialize(contactJSON(item))
                case "DELETE":
                    let id = contactItems[index].id
                    contactItems.remove(at: index)
                    for slug in contactShares.keys { contactShares[slug]?.removeAll { $0 == id } }
                    return ""
                default:
                    throw APIError.status(405)
                }
            default:
                throw APIError.status(405)
            }
        }
        if isVisibility {
            guard method == "PATCH" else { throw APIError.status(405) }
            guard let visible = fields["visible"] as? Bool else { throw APIError.message("body must include visible: true|false", status: 400) }
            guard let patch = holdable.first(where: { $0.id == parts[3] }), held[patch.slug] != nil else {
                throw APIError.message("membership not found", status: 404)
            }
            if visible { hiddenMemberships.remove(patch.slug) } else { hiddenMemberships.insert(patch.slug) }
            return "{\"node_id\":\"\(patch.id)\",\"visible\":\(visible)}"
        }
        if isShares {
            guard method == "PUT" else { throw APIError.status(405) }
            guard let patch = holdable.first(where: { $0.slug == parts[1] }) else { throw APIError.message("patch not found", status: 404) }
            guard inRoom(patch.slug) else {
                throw APIError.message("only this patch's members and admins can share contact details with it", status: 403)
            }
            guard let ids = fields["item_ids"] as? [String] else { throw APIError.message("body must include item_ids", status: 400) }
            for id in ids where !contactItems.contains(where: { $0.id == id }) {
                throw APIError.message("that contact item is not yours", status: 403)
            }
            contactShares[patch.slug] = ids
            return serialize(["node_id": patch.id, "item_ids": ids])
        }
        // Preferences: every row as sent, no validation — the server's way.
        guard method == "PUT" else { throw APIError.status(405) }
        guard let rows = fields["preferences"] as? [[String: Any]] else { throw APIError.message("invalid request body", status: 400) }
        for row in rows {
            guard let type = row["type"] as? String, let channel = row["channel"] as? String else { continue }
            preferenceRows[type, default: [:]][channel] = (row["enabled"] as? Bool) ?? false
        }
        return #"{"status":"ok"}"#
    }

    // MARK: Patch admin

    /// The Film Club's membership, which a `--preview-admin` launch keeps:
    /// two members and a second admin, three requests waiting (two with a
    /// note), one invitation out, one person removed and one follower. The
    /// reader's own admin row is added from `held`, so the club's roster and
    /// the membership index never disagree. Every write below mutates this,
    /// and is decided by the server's rule in its order and its words.
    private struct ClubRow {
        let id: String
        let userId: String
        let username: String
        let name: String
        var role: String
        var status: String
        var minutesAgo: Int
        var message = ""
    }
    private static var freshClubRoster: [ClubRow] {
        [
            ClubRow(id: "fc01", userId: "u-juno", username: "juno", name: "Juno Park", role: "admin", status: "active", minutesAgo: 200 * 24 * 60),
            ClubRow(id: "fc02", userId: "u-lena", username: "lena", name: "Lena Fox", role: "member", status: "active", minutesAgo: 90 * 24 * 60),
            ClubRow(id: "fc03", userId: "u-ollie", username: "ollie", name: "Ollie Grant", role: "member", status: "active", minutesAgo: 40 * 24 * 60),
            ClubRow(id: "fc04", userId: "u-max", username: "max", name: "Max Stone", role: "member", status: "banned", minutesAgo: 30 * 24 * 60),
            ClubRow(id: "fc05", userId: "u-priya", username: "priya", name: "Priya Nair", role: "member", status: "pending", minutesAgo: 2 * 24 * 60,
                    message: "I run the projector at the library and would love to help on screening nights."),
            ClubRow(id: "fc06", userId: "u-tom", username: "tom", name: "Tom Reyes", role: "member", status: "pending", minutesAgo: 5 * 60,
                    message: "Saw the poster at the Repair Cafe."),
            ClubRow(id: "fc07", userId: "u-bea", username: "bea", name: "Bea Cole", role: "member", status: "pending", minutesAgo: 30),
            ClubRow(id: "fc08", userId: "u-ivy", username: "ivy", name: "Ivy Chen", role: "member", status: "invited", minutesAgo: 3 * 24 * 60),
            ClubRow(id: "fc09", userId: "u-rue", username: "rue", name: "Rue Bianchi", role: "follower", status: "active", minutesAgo: 10 * 24 * 60),
        ]
    }
    private static var clubRoster: [ClubRow] = freshClubRoster
    /// Accounts an admin may invite who hold nothing on the club yet.
    private static let invitable: [(userId: String, username: String, name: String)] = [
        ("u-noor", "noor", "Noor Haddad"), ("rc2", "kofi", "Kofi Adu"), ("u2", "imani", "Imani Osei"),
    ]

    /// The club as the server's tables hold it: the fixture rows and the
    /// reader's own, oldest first (`ORDER BY m.id`).
    private static var clubRows: [ClubRow] {
        var rows = clubRoster
        if let mine = held[adminSlug] {
            rows.insert(ClubRow(id: "fc00", userId: (accountFields["id"] as? String) ?? me,
                                username: (accountFields["username"] as? String) ?? "samplereader", name: myName,
                                role: mine.role, status: mine.status, minutesAgo: 60 * 24 * 60), at: 0)
        }
        return rows
    }

    private static func clubJSON(_ row: ClubRow, message: Bool) -> [String: Any] {
        var object: [String: Any] = [
            "id": row.id, "user_id": row.userId, "node_id": adminSlug, "role": row.role, "status": row.status,
            "joined_at": stamp(minutesAgo: row.minutesAgo), "username": row.username, "display_name": row.name, "avatar_url": "",
        ]
        if message && !row.message.isEmpty { object["join_message"] = row.message }
        return object
    }

    /// `GET nodes/{slug}/members` on the club, by `ListMembers`' rules:
    /// `pending` and `banned` only for its admins (everyone else is quietly
    /// given the active list), the membership unless followers are asked for
    /// by name, `join_message` only on the queue, the count of the whole
    /// listing under its status, and `invited` for the patch's admins only.
    private static func clubMembers(_ query: [URLQueryItem]) -> String {
        let value = { (name: String) in query.first { $0.name == name }?.value ?? "" }
        let admin = role(adminSlug) == "admin"
        var status = value("status")
        if !["pending", "banned"].contains(status) || !admin { status = "active" }
        let followers = value("role") == "follower"
        let listed = clubRows.filter { $0.status == status && (followers ? $0.role == "follower" : $0.role != "follower") }
        let (rows, next) = page(listed, id: \.id, query: query)
        let all = clubRows.filter { $0.status == status }
        var payload: [String: Any] = [
            "items": rows.map { clubJSON($0, message: status == "pending") }, "next_cursor": next,
            "member_count": all.filter { $0.role != "follower" }.count,
            "follower_count": all.filter { $0.role == "follower" }.count, "public_member_list": "everyone",
        ]
        if admin {
            payload["invited"] = clubRows.filter { $0.status == "invited" }.map { row -> [String: Any] in
                ["id": row.id, "user_id": row.userId, "username": row.username, "display_name": row.name,
                 "avatar_url": "", "invited_at": stamp(minutesAgo: row.minutesAgo)]
            }
        }
        return serialize(payload)
    }

    /// The suggestions waiting on a patch, as `ListNodeEventSubmissions`
    /// serves them: newest first, the submitter beside each, and the four
    /// columns its query does not read left blank.
    private static func submissions(_ slug: String) throws -> String {
        guard signedIn else { throw APIError.unauthenticated }
        guard role(slug) == "admin" || (accountFields["role"] as? String) == "admin" else {
            throw APIError.message("insufficient permissions", status: 403)
        }
        let rows = everyEvent.reversed().compactMap { entry -> [String: Any]? in
            guard var event = (try? JSONSerialization.jsonObject(with: Data(entry.json.utf8))) as? [String: Any],
                  event["status"] as? String == "pending_review", event["node_slug"] as? String == slug else { return nil }
            for key in ["timezone", "image_url", "image_alt", "event_url"] { event[key] = "" }
            let by = people.first { $0.id == (event["created_by"] as? String) }
            event["submitter_username"] = by?.username ?? ""
            event["submitter_display_name"] = by?.name ?? ""
            return event
        }
        return serialize(["items": rows])
    }

    private static func adminRead(_ path: String, query: [URLQueryItem]) throws -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 3, parts[0] == "nodes" else { return nil }
        if parts[1] == adminSlug && parts[2] == "members" { return clubMembers(query) }
        if parts[2] == "reports" { return try reportsRead(parts[1], query: query) }
        if parts[2] == "event-submissions" { return try submissions(parts[1]) }
        return nil
    }

    /// The writes a patch's admin makes: a member's status, an invitation
    /// sent or taken back, and a suggestion reviewed.
    private static func adminWrite(_ method: String, _ path: String, fields: [String: Any]) throws -> String? {
        let parts = path.split(separator: "/").map(String.init)
        if method == "PATCH", parts.count == 3, parts[0] == "events", parts[2] == "review" {
            return try review(parts[1], fields: fields)
        }
        guard parts.count >= 3, parts[0] == "nodes" else { return nil }
        let slug = parts[1]
        switch (method, parts.count, parts[2]) {
        case ("PATCH", 4, "members"):
            return try updateMember(slug, userId: parts[3], fields: fields)
        case ("PATCH", 4, "reports"):
            return try reportAct(slug, id: parts[3], fields: fields)
        case ("POST", 3, "invitations"):
            return try invite(slug, fields: fields)
        case ("DELETE", 4, "invitations"):
            guard signedIn else { throw APIError.unauthenticated }
            guard slug == adminSlug, role(slug) == "admin" else { throw APIError.message("not found", status: 404) }
            guard let index = clubRoster.firstIndex(where: { $0.userId == parts[3] && $0.status == "invited" }) else {
                throw APIError.message("no invitation to rescind", status: 404)
            }
            clubRoster.remove(at: index)
            return #"{"status":"rescinded"}"#
        default:
            return nil
        }
    }

    /// `UpdateMember`'s status half, in its order.
    private static func updateMember(_ slug: String, userId: String, fields: [String: Any]) throws -> String {
        guard signedIn else { throw APIError.unauthenticated }
        guard holdable.contains(where: { $0.slug == slug }) else { throw APIError.message("node not found", status: 404) }
        guard role(slug) == "admin" || (accountFields["role"] as? String) == "admin" else {
            throw APIError.message("insufficient permissions", status: 403)
        }
        let mine = (accountFields["id"] as? String) ?? me
        guard slug == adminSlug, let row = clubRows.first(where: { $0.userId == userId }) else {
            throw APIError.message("membership not found", status: 404)
        }
        // The reader's own row is `held`'s; every other is the roster's.
        func set(_ status: String) {
            if userId == mine { held[adminSlug]?.status = status; return }
            if let index = clubRoster.firstIndex(where: { $0.userId == userId }) {
                clubRoster[index].status = status
                if status != "pending" { clubRoster[index].message = "" }
            }
        }
        if let role = fields["role"] as? String {
            return try changeRole(row, to: role, mine: mine)
        }
        guard let status = fields["status"] as? String else { throw APIError.message("invalid request body", status: 400) }
        switch status {
        case "active":
            guard row.status == "pending" else { throw APIError.message("can only approve pending members", status: 400) }
            set("active")
        case "banned":
            guard row.status == "active" else { throw APIError.message("can only ban active members", status: 400) }
            guard userId != mine else { throw APIError.message("cannot ban yourself", status: 400) }
            if row.role == "admin", clubRows.filter({ $0.role == "admin" && $0.status == "active" }).count <= 1 {
                throw APIError.message("cannot ban the last admin", status: 409)
            }
            set("banned")
        case "left":
            guard row.status == "pending" || row.status == "banned" else {
                throw APIError.message("can only reject pending or reinstate banned members", status: 400)
            }
            set("left")
        default:
            throw APIError.message("invalid status value", status: 400)
        }
        var answer = clubJSON(clubRows.first { $0.userId == userId } ?? row, message: false)
        for key in ["username", "display_name", "avatar_url"] { answer[key] = nil }
        return serialize(answer)
    }

    /// `UpdateMember`'s role half, in its order and its words. The club is
    /// run by a maintainer, so a promotion is honoured; the governance
    /// refusals the server makes elsewhere (decided elsewhere, ratified by
    /// proposal, an elected council) are read from the rules by the app
    /// before it offers the act at all.
    private static func changeRole(_ row: ClubRow, to role: String, mine: String) throws -> String {
        guard ["member", "follower", "admin"].contains(role) else { throw APIError.message("invalid role value", status: 400) }
        if row.status == "invited" { throw APIError.message("they have not accepted the invitation yet", status: 400) }
        if row.role == "follower" && role != "follower" {
            throw APIError.message("they follow this patch: invite them to join, or let them become a member themselves", status: 409)
        }
        if row.role == "admin" && role != "admin",
           clubRows.filter({ $0.role == "admin" && $0.status == "active" }).count <= 1 {
            throw APIError.message("cannot demote the last admin", status: 409)
        }
        if row.userId == mine {
            held[adminSlug]?.role = role
        } else if let index = clubRoster.firstIndex(where: { $0.userId == row.userId }) {
            clubRoster[index].role = role
        }
        var answer = clubJSON(clubRows.first { $0.userId == row.userId } ?? row, message: false)
        for key in ["username", "display_name", "avatar_url"] { answer[key] = nil }
        return serialize(answer)
    }

    /// `InviteMember`, in its order and its words.
    private static func invite(_ slug: String, fields: [String: Any]) throws -> String {
        guard signedIn else { throw APIError.unauthenticated }
        guard slug == adminSlug, role(slug) == "admin" else { throw APIError.message("not found", status: 404) }
        var username = ((fields["username"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if username.hasPrefix("@") { username.removeFirst() }
        guard !username.isEmpty else { throw APIError.message("username is required", status: 400) }
        let known = clubRows.map { ($0.userId, $0.username, $0.name) } + invitable.map { ($0.userId, $0.username, $0.name) }
        guard let person = known.first(where: { $0.1 == username }) else {
            throw APIError.message("no account with that username", status: 404)
        }
        if let row = clubRows.first(where: { $0.userId == person.0 }) {
            switch row.status {
            case "active": throw APIError.message("already in this patch", status: 409)
            case "pending": throw APIError.message("they have already asked to join: approve their request instead", status: 409)
            case "invited": throw APIError.message("already invited", status: 409)
            case "banned": throw APIError.message("removed from this patch: reinstate them first", status: 409)
            default:
                if let index = clubRoster.firstIndex(where: { $0.userId == person.0 }) {
                    clubRoster[index].status = "invited"
                    clubRoster[index].role = "member"
                    clubRoster[index].minutesAgo = 0
                    clubRoster[index].message = ""
                }
            }
        } else {
            clubRoster.append(ClubRow(id: "fc\(10 + clubRoster.count)", userId: person.0, username: person.1, name: person.2,
                                      role: "member", status: "invited", minutesAgo: 0))
        }
        let id = clubRoster.first { $0.userId == person.0 }?.id ?? ""
        return "{\"status\":\"invited\",\"membership_id\":\"\(id)\",\"user_id\":\"\(person.0)\"}"
    }

    /// `ReviewEventSubmission`, in its order and its words. Approving
    /// publishes the suggestion; declining deletes it.
    private static func review(_ id: String, fields: [String: Any]) throws -> String {
        guard signedIn else { throw APIError.unauthenticated }
        let action = (fields["action"] as? String) ?? ""
        guard action == "approve" || action == "reject" else {
            throw APIError.message("action must be 'approve' or 'reject'", status: 400)
        }
        guard let found = everyEvent.first(where: { $0.id == id }),
              let event = (try? JSONSerialization.jsonObject(with: Data(found.json.utf8))) as? [String: Any] else {
            throw APIError.message("event not found", status: 404)
        }
        guard event["status"] as? String == "pending_review" else {
            throw APIError.message("event is not awaiting review", status: 400)
        }
        let slug = (event["node_slug"] as? String) ?? ""
        let instanceAdmin = (accountFields["role"] as? String) == "admin"
        let allowed = (event["node_status"] as? String) == "unclaimed" ? instanceAdmin : (instanceAdmin || role(slug) == "admin")
        guard allowed else { throw APIError.message("insufficient permissions", status: 403) }
        if action == "approve" {
            eventEdits[id, default: [:]]["status"] = "active"
        } else {
            deletedEvents.insert(id)
            lastDeclineNote = (fields["note"] as? String) ?? ""
        }
        return #"{"status":"ok"}"#
    }
    /// What the last decline said to its submitter, so a test can see the
    /// note travelled.
    static var lastDeclineNote = ""

    // MARK: People

    /// Everybody the other fixtures name with a username — the members
    /// room, the slate and the ballots, the noticeboard, the governance
    /// overview and the Label — so every door opens on somebody. Rowan runs
    /// the studio and is a member of the Repair Cafe, so a plain sign-in
    /// (which is in the Repair Cafe) is shown his contact card; Imani's card
    /// goes only to the studio, so it waits for a `--preview-member` launch;
    /// Theo has hidden his membership and has nothing to show; Sam has moved.
    /// Wren is in the studio's members room but her account is suspended,
    /// which the profile answers with the same 404 as a name nobody holds.
    private struct FixturePerson {
        let id: String
        let username: String
        let name: String
        var bio = ""
        var links: [(url: String, label: String)] = []
        var movedTo = ""
        var since = "2026-01-14T10:00:00Z"
        /// slug and role, admins first as the server orders them.
        var memberships: [(slug: String, role: String)] = []
        /// kind, value, label — and only ever shown to somebody in one of
        /// the patches it was shared into.
        var contact: [(kind: String, value: String, label: String)] = []
        var sharedInto: Set<String> = []
    }

    private static let people: [FixturePerson] = [
        FixturePerson(id: "u1", username: "rowan", name: "Rowan Hale",
                      bio: "Runs the studio desk most evenings. Ask me about the kiln.",
                      links: [("https://rowan.example.org", ""), ("https://www.makers.example.org/rowan", "Makers’ directory")],
                      memberships: [("common-thread", "admin"), (memberSlug, "member")],
                      contact: [("phone", "+1 717 555 0100, evenings only", "mobile"), ("email", "rowan@example.org", ""),
                                ("handle", "@rowan@social.example", "fediverse"), ("note", "Usually at the studio desk on Tuesdays", "")],
                      sharedInto: ["common-thread", memberSlug]),
        FixturePerson(id: "u2", username: "imani", name: "Imani Osei", bio: "Keeps the studio calendar honest.",
                      since: "2026-02-03T10:00:00Z", memberships: [("common-thread", "member")],
                      contact: [("email", "imani@example.org", "")], sharedInto: ["common-thread"]),
        FixturePerson(id: "u3", username: "theo", name: "", since: "2026-03-02T10:00:00Z"),
        FixturePerson(id: "u5", username: "mara", name: "Mara Quinn", since: "2026-03-20T10:00:00Z",
                      memberships: [("common-thread", "member")]),
        FixturePerson(id: "u9", username: "sam", name: "Sam Ortiz", movedTo: "https://neighbor.example.org/users/sam",
                      since: "2025-11-08T10:00:00Z"),
        FixturePerson(id: "l1", username: "dee", name: "Dee Ramos", bio: "Books the listening nights.",
                      memberships: [("listening-room", "admin")]),
        FixturePerson(id: "l2", username: "ade", name: "Ade Bello", memberships: [("listening-room", "member")]),
        FixturePerson(id: "rc1", username: "deemarsh", name: "Dee Marsh", bio: "Fixes things, mostly toasters.",
                      memberships: [(memberSlug, "admin")]),
        FixturePerson(id: "rc2", username: "kofi", name: "Kofi Adu", memberships: [(memberSlug, "member")],
                      contact: [("handle", "kofi on the Repair Cafe group chat", "")], sharedInto: [memberSlug]),
        // The Film Club's, for the admin's queues (see `clubRoster`).
        FixturePerson(id: "u-juno", username: "juno", name: "Juno Park", bio: "Picks the films.", memberships: [(adminSlug, "admin")]),
        FixturePerson(id: "u-lena", username: "lena", name: "Lena Fox", memberships: [(adminSlug, "member")]),
        FixturePerson(id: "u-ollie", username: "ollie", name: "Ollie Grant", memberships: [(adminSlug, "member")]),
        FixturePerson(id: "u-max", username: "max", name: "Max Stone"),
        FixturePerson(id: "u-priya", username: "priya", name: "Priya Nair", bio: "Projectionist at the library."),
        FixturePerson(id: "u-tom", username: "tom", name: "Tom Reyes"),
        FixturePerson(id: "u-bea", username: "bea", name: "Bea Cole"),
        FixturePerson(id: "u-ivy", username: "ivy", name: "Ivy Chen"),
        FixturePerson(id: "u-rue", username: "rue", name: "Rue Bianchi"),
        FixturePerson(id: "u-noor", username: "noor", name: "Noor Haddad"),
        FixturePerson(id: "steward", username: "samplesteward", name: "Sample Steward",
                      bio: "Keeps the lights on and answers the email.", since: "2025-09-01T10:00:00Z",
                      memberships: [("extra-0", "member")]),
    ]

    /// A patch's id and name, for a membership row.
    private static func patchFacts(_ slug: String) -> (id: String, name: String) {
        if let row = holdable.first(where: { $0.slug == slug }) { return (row.id, row.name) }
        if slug.hasPrefix("extra-"), let index = Int(slug.dropFirst("extra-".count)), extraNames.indices.contains(index) {
            return (slug, extraNames[index])
        }
        return (slug, slug)
    }

    private static func membershipJSON(_ slug: String, _ role: String) -> [String: Any] {
        let facts = patchFacts(slug)
        return ["node_id": facts.id, "node_slug": slug, "node_name": facts.name, "role": role,
                "joined_at": "2026-02-01T10:00:00Z"]
    }

    /// `GET users/{username}`. The reader's own profile is built from the
    /// account and the membership set the writes mutate, so it says what
    /// Settings and the Dashboard say; anybody else is a fixture. An
    /// unknown name is the server's 404, in its words.
    private static func personRead(_ path: String) throws -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts[0] == "users", parts[1] != "me" else { return nil }
        let username = parts[1]
        let mine = (accountFields["username"] as? String) ?? "samplereader"
        if username == mine {
            let fields = accountFields
            // A hidden membership is hidden from its holder's own profile too
            // (web ADR 006), and the card shows what the reader has shared.
            let rows = held.filter { ["member", "admin"].contains($0.value.role) && $0.value.status == "active" && !hiddenMemberships.contains($0.key) }
                .sorted { ($0.value.role == "admin" ? 0 : 1, $0.key) < ($1.value.role == "admin" ? 0 : 1, $1.key) }
                .map { membershipJSON($0.key, $0.value.role) }
            return serialize([
                "id": (fields["id"] as? String) ?? me, "username": mine,
                "display_name": (fields["display_name"] as? String) ?? "", "bio": (fields["bio"] as? String) ?? "",
                "avatar_url": "", "links": (fields["links"] as? [[String: Any]]) ?? [], "moved_to": "",
                "created_at": "2026-02-01T10:00:00Z", "memberships": signedIn ? rows : [],
                "contact": signedIn ? contactItems.filter { item in contactShares.values.contains { $0.contains(item.id) } }.map { contactJSON($0) } : [],
            ])
        }
        guard let person = people.first(where: { $0.username == username }) else {
            throw APIError.message("user not found", status: 404)
        }
        // Somebody in a patch the person gave their card to, and signed in.
        let shares = signedIn && !person.sharedInto.filter(inRoom).isEmpty
        return serialize([
            "id": person.id, "username": person.username, "display_name": person.name, "bio": person.bio,
            "avatar_url": "", "links": person.links.map { ["url": $0.url, "label": $0.label] },
            "moved_to": person.movedTo, "created_at": person.since,
            "memberships": person.memberships.map { membershipJSON($0.slug, $0.role) },
            "contact": shares ? person.contact.enumerated().map { index, item -> [String: Any] in
                var row: [String: Any] = ["id": "\(person.id)-contact-\(index)", "kind": item.kind, "value": item.value, "position": index]
                // `label` is omitempty on the server.
                if !item.label.isEmpty { row["label"] = item.label }
                return row
            } : [],
        ])
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
        let fields = (try? JSONSerialization.jsonObject(with: body ?? Data())) as? [String: Any] ?? [:]
        if let answer = try invitationWrite(method, path) { return answer }
        if let answer = try claimWrite(method, path, fields: fields) { return answer }
        if let answer = try adminWrite(method, path, fields: fields) { return answer }
        if let answer = try eventWrite(method, path, fields: fields) { return answer }
        if let answer = try peopleWrite(method, path, fields: fields) { return answer }
        if let answer = try notificationWrite(method, path) { return answer }
        if let answer = try governanceWrite(method, path, fields: fields) { return answer }
        if let answer = try noticeboardWrite(method, path, fields: fields) { return answer }
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
            // A new account belongs nowhere and has heard nothing yet.
            held = [:]
            notifications = []
            account = "{\"id\":\"demo-user\",\"username\":\"\(username)\",\"display_name\":\"\(display)\",\"role\":\"member\"}"
            return account
        case "auth/invite":
            // `RedeemInviteLink`, in its order and words. The fixture quilt
            // sends mail, so the address is required.
            let token = (fields["token"] as? String) ?? ""
            let username = ((fields["username"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, !username.isEmpty else { throw APIError.message("token and username are required", status: 400) }
            let email = ((fields["email"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !email.isEmpty else { throw APIError.message("email is required so you can sign in again later", status: 400) }
            if email == "taken@example.org" { throw APIError.message("an account with this email already exists — sign in instead", status: 400) }
            if let problem = inviteProblem(token) { throw APIError.message(problem, status: 400) }
            startSession()
            held = [:]
            notifications = []
            let display = ((fields["display_name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            account = serialize(["id": "invited-user", "username": username, "display_name": display, "role": "member"])
            return account
        case "auth/logout":
            signOut()
            return "{}"
        case "events":
            return try eventPost(fields)
        case "nodes":
            return try createNode(fields)
        case "submissions":
            return try submit(fields)
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
            return "{\"id\":\"extra-\(index)\",\"name\":\"\(name)\",\"slug\":\"extra-\(index)\",\"tags\":[\"\(index % 2 == 0 ? "community" : "music")\"],\"member_count\":\(index + 1)\(isUnclaimedExtra(index) ? ",\"is_unclaimed\":true" : "")\(moved)\(record)\(posting)}"
        }.enumerated().map { index, json in idFirst(edited(json, nodeEdits["extra-\(index)"])) }
        let members = #"{"items":[{"id":"m1","user_id":"u1","role":"admin","username":"rowan","display_name":"Rowan Hale"},{"id":"m2","user_id":"u2","role":"member","username":"imani","display_name":"Imani Osei"},{"id":"m3","user_id":"u3","role":"member","username":"theo"},{"id":"m5","user_id":"u7","role":"member","username":"wren","display_name":"Wren Adler"},{"id":"m4","user_id":"u4","role":"follower","username":"nobody-should-see-this"}],"next_cursor":"","member_count":12,"follower_count":34,"public_member_list":"everyone"}"#
        let withheldMembers = #"{"items":[],"next_cursor":"","member_count":8,"follower_count":15,"public_member_list":"nobody"}"#
        let overview = #"{"rules":{"decision_method":"majority","quorum_percent":20,"default_vote_duration_hours":336,"leadership_model":"maintainer","leadership_venue":"patchwork","proposal_venue":"patchwork","inactivity_days":90,"max_admins":3},"admins":[{"user_id":"u1","username":"rowan","display_name":"Rowan Hale","joined_at":"2026-01-14T10:00:00Z"}],"admins_withheld":false,"proposals_withheld":false,"election":null,"seats":[],"next_term_end":"","next_contest_opens":"","membership_policy":"open","member_count":12,"document_count":2,"open_proposals":1,"passed_proposals":3,"rejected_proposals":1,"needs_vote":0}"#
        let listeningOverview = #"{"rules":{"decision_method":"majority","quorum_percent":0,"default_vote_duration_hours":168,"leadership_model":"maintainer","leadership_venue":"patchwork","proposal_venue":"patchwork"},"admins":[],"admins_withheld":true,"proposals_withheld":false,"election":null,"seats":[],"next_term_end":"","next_contest_opens":"","membership_policy":"open","member_count":8,"document_count":0,"open_proposals":1,"passed_proposals":0,"rejected_proposals":0,"needs_vote":0}"#
        let withheldOverview = #"{"rules":{"decision_method":"admin","leadership_model":"maintainer","leadership_venue":"patchwork","proposal_venue":"patchwork"},"admins":[],"admins_withheld":true,"proposals_withheld":true,"election":null,"seats":[],"next_term_end":"","next_contest_opens":"","membership_policy":"invite_only","member_count":8,"document_count":0,"open_proposals":0,"passed_proposals":0,"rejected_proposals":0,"needs_vote":0}"#
        let record = #"{"items":[{"kind":"vote","at":"2026-08-14T12:00:00Z","title":"Amend the studio hours","link":"/patches/common-thread/governance/demo-proposal-3","outcome":"carried"},{"kind":"vote","at":"2026-06-08T12:00:00Z","title":"Buy a second kiln","outcome":"lapsed"},{"kind":"direct","at":"2026-04-02T12:00:00Z","title":"Publish the charter","outcome":"applied","actor":"Rowan Hale"}],"public_governance_record":"everyone"}"#
        let json: String
        if let governed = try adminRead(path, query: query) ?? governanceRead(path, query: query) ?? noticeboardRead(path, query: query) ?? peopleRead(path, query: query) ?? personRead(path) ?? claimRead(path) { json = governed } else {
        switch path {
        case "instance": json = #"{"name":"Sample quilt","description":"A fictional quilt for exploring the native app.","geography":{"timezone":"America/New_York","latitude":40.04,"longitude":-76.3},"neighbor_quilts":[{"name":"Neighbor quilt","url":"https://neighbor.example.org"}],"stats":{"node_count":12,"event_count":34,"member_count":5},"version":"v0.0.0-preview","submissions_enabled":true,"email_enabled":true}"#
        case "label": json = ###"{"published":true,"stewards":[{"username":"samplesteward","display_name":"Sample Steward","avatar_url":"","blurb":"Keeps the lights on and answers the email."}],"prose":"## Why this exists\n\nThis quilt is fictional, and so is everything on this page. It is here so the app has something to draw.\n\nThe figures below are **made up**, and *nobody* is billed for them. Even `code` and ***both at once*** are only here to be looked at.\n\n- No real money changes hands.\n- No real person is named.","cost_items":[{"service":"Sample Hosting","purpose":"the server (where all this lives)","why":"invented, for the preview","amount_minor":1200,"period":"monthly"},{"service":"Sample Domain","purpose":"the address","why":"also invented","amount_minor":1800,"period":"yearly"}],"currency":"USD","total_monthly_minor":1350,"stale":true,"stated_on":"2026-01-01","version":"v0.0.0-preview","federation":false,"multi_quilt":false,"support_url":"https://example.org/support","feedback_url":"https://example.org/feedback","seamripped_from_name":"","seamripped_from_url":""}"###
        case "instance/lining": json = ###"{"title":"Community Standards","body":"This fictional patch, like every patch on this fictional quilt, starts by agreeing to the lining.\n\n## Keep each other safe\n\nNobody is harmed, excluded, or diminished for who they are. We regulate actions, not identity.\n\n## Say what you are\n\nA patch describes itself honestly: who it is, what it does, and who it answers to.","version":1}"###
        case "legal/privacy": json = ###"{"doc":"privacy","title":"Privacy Policy","markdown":"## The short version\n\nNothing here is real, so nothing here is collected. This document exists so the app has a document to render.\n\n- No ads.\n- No trackers.","customized":true,"updated_at":"2026-01-01T00:00:00.000Z"}"###
        case "legal/terms": json = ###"{"doc":"terms","title":"User Agreement","markdown":"## The short version\n\nBe someone your community would vouch for. This fictional agreement has no force anywhere.","customized":false,"updated_at":"2026-01-01T00:00:00.000Z"}"###
        case "nodes/tree":
            // `scope=my` narrows the tree the way it narrows the feed: to the
            // patches the reader holds an active row on. Signed out there is
            // nobody for it to be about, so it answers an empty quilt.
            var children = [patch, second] + extras + treeMade()
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
        case _ where path.hasPrefix("auth/invite/") && path.hasSuffix("/validate"):
            let token = String(path.dropFirst("auth/invite/".count).dropLast("/validate".count))
            if let problem = inviteProblem(token) { throw APIError.message(problem, status: 404) }
            json = #"{"valid":true}"#
        case "gazetteer/suggest":
            guard signedIn else { throw APIError.unauthenticated }
            json = gazetteer(query)
        case "tags": json = #"[{"name":"craft","motif":"scissors","node_count":3},{"name":"music","motif":"musicNotes","node_count":6},{"name":"venue","motif":"buildings","node_count":1},{"name":"community","node_count":6},{"name":"archive","node_count":0}]"#
        case "events": json = eventsPage(query)
        case "nodes/common-thread/members": json = members
        case "nodes/\(marketSlug)/members": json = marketMembers
        case "nodes/listening-room/members": json = withheldMembers
        case "nodes/listening-room/governance": json = #"{"items":[],"published_only":true}"#
        case "nodes/common-thread/governance/overview": json = overviewJSON("common-thread", base: overview)
        case "nodes/listening-room/governance/overview": json = overviewJSON("listening-room", base: listeningOverview)
        case "nodes/extra-1/governance/overview": json = withheldOverview
        case "nodes/\(memberSlug)/governance/overview", "nodes/\(adminSlug)/governance/overview", "nodes/\(marketSlug)/governance/overview":
            json = plainOverview(String(path.split(separator: "/")[1])) ?? "{}"
        case "nodes/extra-1/governance": json = #"{"items":[],"published_only":true}"#
        case "nodes/extra-1/governance/record": json = #"{"items":[],"public_governance_record":"nobody"}"#
        case "nodes/extra-1/proposals": json = #"{"items":[],"next_cursor":"","public_governance_record":"nobody"}"#
        case "nodes/common-thread/governance/record": json = record
        case "nodes/listening-room/governance/record": json = #"{"items":[],"public_governance_record":"everyone"}"#
        default:
            if let event = events.first(where: { "events/\($0.id)" == path }) { json = event.json }
            // A pending suggestion is readable by its submitter and nobody
            // else, and it is on no list (the server's `GetEvent` rule).
            else if let event = everyEvent.first(where: { "events/\($0.id)" == path }), signedIn { json = event.json }
            else if let made = madePatches.first(where: { "nodes/\($0.slug)" == path && $0.status != "pending_review" }) {
                json = "{\"node\":\(node(madeJSON(made), slug: made.slug)),\"is_unclaimed\":\(made.status == "unclaimed"),\"lining_status\":\"pristine\",\"viewer_trusted\":false}"
            }
            else if let made = madePatches.first(where: { "nodes/\($0.slug)/members" == path && $0.status == "active" }) {
                // The founder, as the one admin a new patch has, and nobody
                // waiting to be let in.
                let me = accountFields
                let pending = query.contains { $0.name == "status" && $0.value == "pending" }
                json = pending ? #"{"items":[],"next_cursor":"","member_count":0,"follower_count":0}"# : serialize(["items": [["id": "m-\(made.slug)", "user_id": (me["id"] as? String) ?? "demo-user", "role": "admin",
                                             "username": (me["username"] as? String) ?? "samplereader",
                                             "display_name": (me["display_name"] as? String) ?? ""]],
                                  "next_cursor": "", "member_count": 1, "follower_count": 0, "public_member_list": "nobody"])
            }
            else if let index = Int(path.replacingOccurrences(of: "nodes/extra-", with: "")), extras.indices.contains(index) {
                json = "{\"node\":\(node(extras[index], slug: "extra-\(index)")),\"is_unclaimed\":\(isUnclaimedExtra(index)),\"viewer_trusted\":false}"
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
