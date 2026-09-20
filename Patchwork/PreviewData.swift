// SPDX-License-Identifier: MPL-2.0

#if DEBUG
import Foundation

/// Fictional, offline design fixtures. Only enabled by an explicit debug launch argument.
///
/// The two demo patches are deliberately opposite readers: Common Thread
/// publishes its roster and its record, and The Listening Room withholds both
/// — which is how the withheld wording ("doesn't publish its member list",
/// "not public") stays exercised offline rather than only on a quilt that
/// happens to be configured that way.
enum PreviewData {
    static func response<T: Decodable>(_ path: String) throws -> T {
        let patch = #"{"id":"demo-patch","name":"Common Thread Studio","slug":"common-thread","description":"A place to make things and meet your neighbors. Open studio evenings, shared tools, and room for your next idea.","tags":["craft","community"],"member_count":12,"follower_count":34,"upcoming_event_count":4,"appearance":{"palette":"anthem","block":"ohioStar","rotation":90,"icon":"scissors"},"address":"12 Example Street","latitude":40.04,"longitude":-76.3,"website":"https://commonthread.example.org","links":[{"url":"https://makers.example.org/common-thread","label":"Our makers’ directory"}],"did":"did:web:commonthread.example.org","visibility":"public","public_member_list":"everyone","public_governance_record":"everyone"}"#
        let second = ##"{"id":"demo-patch-2","name":"The Listening Room","slug":"listening-room","description":"Independent music in good company.","tags":["music","venue"],"visibility":"public","public_member_list":"nobody","public_governance_record":"nobody","member_count":8,"follower_count":15,"appearance":{"block":{"grid":3,"colors":{"0,1":[1],"0,2":[2],"1,0":[1],"1,2":[1],"2,0":[2],"2,1":[1]}},"rotation":0,"bundle":["#2E7D5B","#204B4B","#D9D6AF","#D89E13"]}}"##
        let names = ["Community Garden", "Bike Kitchen", "Neighborhood Books", "River Walkers", "Pottery Circle", "Market Friends", "Repair Cafe", "Film Club", "Food Share", "Evening Choir"]
        let extras = names.enumerated().map { index, name in
            "{\"id\":\"extra-\(index)\",\"name\":\"\(name)\",\"slug\":\"extra-\(index)\",\"tags\":[\"\(index % 2 == 0 ? "community" : "music")\"],\"member_count\":\(index + 1)\(index == 3 ? ",\"is_unclaimed\":true" : "")}"
        }
        let event = #"{"id":"demo-event","title":"Saturday open studio","description":"Bring something you’re working on, or try something new. There will be fabric, paper, and a pot of coffee. Everyone is welcome; no experience needed.","location":"Common Thread Studio","starts_at":"2026-09-26T14:00:00Z","ends_at":"2026-09-26T17:00:00Z","timezone":"America/New_York","node_name":"Common Thread Studio","node_slug":"common-thread"}"#
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
        case "instance": json = #"{"name":"Sample quilt","description":"A fictional quilt for exploring the native app.","geography":{"timezone":"America/New_York"},"neighbor_quilts":[{"name":"Neighbor quilt","url":"https://neighbor.example.org"}]}"#
        case "nodes/tree": json = "{\"tree\":{\"children\":[\(([patch, second] + extras).joined(separator: ","))]}}"
        // The envelope carries what the node object cannot: whether anybody
        // runs this patch, and whether its lining is its own writing.
        case "nodes/common-thread": json = "{\"node\":\(patch),\"is_unclaimed\":false,\"lining_status\":\"diverged\"}"
        case "nodes/listening-room": json = "{\"node\":\(second),\"is_unclaimed\":false,\"lining_status\":\"pristine\"}"
        case "tags": json = #"[{"name":"craft","motif":"scissors","node_count":1},{"name":"music","motif":"musicNotes","node_count":6},{"name":"venue","motif":"buildings","node_count":1},{"name":"community","node_count":6}]"#
        case "events": json = "{\"items\":[\(event)],\"next_cursor\":\"\"}"
        case "events/demo-event": json = event
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
            if let index = Int(path.replacingOccurrences(of: "nodes/extra-", with: "")), extras.indices.contains(index) { json = "{\"node\":\(extras[index])}" }
            else { throw APIError.status(404) }
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }
}
#endif
