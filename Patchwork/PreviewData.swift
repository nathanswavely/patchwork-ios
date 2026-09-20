// SPDX-License-Identifier: MPL-2.0

#if DEBUG
import Foundation

/// Fictional, offline design fixtures. Only enabled by an explicit debug launch argument.
enum PreviewData {
    static func response<T: Decodable>(_ path: String) throws -> T {
        let patch = #"{"id":"demo-patch","name":"Common Thread Studio","slug":"common-thread","description":"A place to make things and meet your neighbors. Open studio evenings, shared tools, and room for your next idea.","tags":["craft","community"],"member_count":12,"follower_count":34,"upcoming_event_count":1,"appearance":{"palette":"anthem","block":"ohioStar","rotation":90,"icon":"scissors"},"address":"12 Example Street","latitude":40.04,"longitude":-76.3}"#
        let second = ##"{"id":"demo-patch-2","name":"The Listening Room","slug":"listening-room","description":"Independent music in good company.","tags":["music","venue"],"appearance":{"block":{"grid":3,"colors":{"0,1":[1],"0,2":[2],"1,0":[1],"1,2":[1],"2,0":[2],"2,1":[1]}},"rotation":0,"bundle":["#2E7D5B","#204B4B","#D9D6AF","#D89E13"]}}"##
        let names = ["Community Garden", "Bike Kitchen", "Neighborhood Books", "River Walkers", "Pottery Circle", "Market Friends", "Repair Cafe", "Film Club", "Food Share", "Evening Choir"]
        let extras = names.enumerated().map { index, name in
            "{\"id\":\"extra-\(index)\",\"name\":\"\(name)\",\"slug\":\"extra-\(index)\",\"tags\":[\"\(index % 2 == 0 ? "community" : "music")\"],\"member_count\":\(index + 1)\(index == 3 ? ",\"is_unclaimed\":true" : "")}"
        }
        let event = #"{"id":"demo-event","title":"Saturday open studio","description":"Bring something you’re working on, or try something new. There will be fabric, paper, and a pot of coffee. Everyone is welcome; no experience needed.","location":"Common Thread Studio","starts_at":"2026-09-26T14:00:00Z","ends_at":"2026-09-26T17:00:00Z","timezone":"America/New_York","node_name":"Common Thread Studio","node_slug":"common-thread"}"#
        let json: String
        switch path {
        case "instance": json = #"{"name":"Sample quilt","description":"A fictional quilt for exploring the native app.","geography":{"timezone":"America/New_York"},"neighbor_quilts":[{"name":"Neighbor quilt","url":"https://neighbor.example.org"}],"stats":{"node_count":12,"event_count":34,"member_count":5},"version":"v0.0.0-preview","submissions_enabled":true}"#
        case "label": json = ###"{"published":true,"stewards":[{"username":"samplesteward","display_name":"Sample Steward","avatar_url":"","blurb":"Keeps the lights on and answers the email."}],"prose":"## Why this exists\n\nThis quilt is fictional, and so is everything on this page. It is here so the app has something to draw.\n\n- No real money changes hands.\n- No real person is named.","cost_items":[{"service":"Sample Hosting","purpose":"the server (where all this lives)","why":"invented, for the preview","amount_minor":1200,"period":"monthly"},{"service":"Sample Domain","purpose":"the address","why":"also invented","amount_minor":1800,"period":"yearly"}],"currency":"USD","total_monthly_minor":1350,"stale":true,"stated_on":"2026-01-01","version":"v0.0.0-preview","federation":false,"multi_quilt":false,"support_url":"https://example.org/support","feedback_url":"https://example.org/feedback","seamripped_from_name":"","seamripped_from_url":""}"###
        case "instance/lining": json = ###"{"title":"Community Standards","body":"This fictional patch, like every patch on this fictional quilt, starts by agreeing to the lining.\n\n## Keep each other safe\n\nNobody is harmed, excluded, or diminished for who they are. We regulate actions, not identity.\n\n## Say what you are\n\nA patch describes itself honestly: who it is, what it does, and who it answers to.","version":1}"###
        case "legal/privacy": json = ###"{"doc":"privacy","title":"Privacy Policy","markdown":"## The short version\n\nNothing here is real, so nothing here is collected. This document exists so the app has a document to render.\n\n- No ads.\n- No trackers.","customized":true,"updated_at":"2026-01-01T00:00:00.000Z"}"###
        case "legal/terms": json = ###"{"doc":"terms","title":"User Agreement","markdown":"## The short version\n\nBe someone your community would vouch for. This fictional agreement has no force anywhere.","customized":false,"updated_at":"2026-01-01T00:00:00.000Z"}"###
        case "nodes/tree": json = "{\"tree\":{\"children\":[\(([patch, second] + extras).joined(separator: ","))]}}"
        case "nodes/common-thread": json = "{\"node\":\(patch)}"
        case "nodes/listening-room": json = "{\"node\":\(second)}"
        case "tags": json = #"[{"name":"craft","motif":"scissors","node_count":1},{"name":"music","motif":"musicNotes","node_count":6},{"name":"venue","motif":"buildings","node_count":1},{"name":"community","node_count":6}]"#
        case "events": json = "{\"items\":[\(event)],\"next_cursor\":\"\"}"
        case "events/demo-event": json = event
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
