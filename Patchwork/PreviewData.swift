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
    /// "Upcoming" section starting two days out. Clamped to 23:00 so tonight
    /// never slides into tomorrow.
    private static var tonightHour: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return min(max(18, calendar.component(.hour, from: Date()) + 1), 23)
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
        let items = events.map(\.json).filter { json in
            if !slug.isEmpty && !json.contains("\"node_slug\":\"\(slug)\"") { return false }
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
    static func signOut() { signedIn = false; account = sampleAccount }

    /// The offline stand-in for the three writes. The JSON is returned as text
    /// so a post with nothing to read (`auth/logout`) runs the same path as
    /// one with a user in the answer.
    static func post(_ path: String, body: Data) throws -> String {
        let fields = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        switch path {
        case "auth/magic-link":
            return #"{"status":"ok"}"#
        case "auth/magic-link/verify":
            switch (fields["code"] as? String) ?? "" {
            case "123456":
                signedIn = true
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
            signedIn = true
            account = "{\"id\":\"demo-user\",\"username\":\"\(username)\",\"display_name\":\"\(display)\",\"role\":\"member\"}"
            return account
        case "auth/logout":
            signOut()
            return "{}"
        default:
            throw APIError.status(404)
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
        case "nodes/common-thread": json = "{\"node\":\(patch),\"is_unclaimed\":false,\"lining_status\":\"diverged\"}"
        case "nodes/listening-room": json = "{\"node\":\(second),\"is_unclaimed\":false,\"lining_status\":\"pristine\"}"
        // The vocabulary answers with its own counts, which are the quilt's
        // whole-quilt public numbers rather than a tally of the tree in hand:
        // `craft` is worn by more patches than this fixture's tree holds, and
        // `archive` is a curated term nothing wears yet.
        case "auth/me":
            guard signedIn else { throw APIError.unauthenticated }
            json = account
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
