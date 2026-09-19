// SPDX-License-Identifier: MPL-2.0

#if DEBUG
import Foundation

/// Fictional, offline design fixtures. Only enabled by an explicit debug launch argument.
enum PreviewData {
    static func response<T: Decodable>(_ path: String) throws -> T {
        let patch = #"{"id":"demo-patch","name":"Common Thread Studio","slug":"common-thread","description":"A place to make things and meet your neighbors. Open studio evenings, shared tools, and room for your next idea.","tags":["craft","community"],"member_count":12,"follower_count":34,"address":"12 Example Street"}"#
        let second = #"{"id":"demo-patch-2","name":"The Listening Room","slug":"listening-room","description":"Independent music in good company.","tags":["music","venue"]}"#
        let event = #"{"id":"demo-event","title":"Saturday open studio","description":"Bring something you’re working on, or try something new. There will be fabric, paper, and a pot of coffee. Everyone is welcome; no experience needed.","location":"Common Thread Studio","starts_at":"2026-09-26T14:00:00Z","ends_at":"2026-09-26T17:00:00Z","timezone":"America/New_York","node_name":"Common Thread Studio","node_slug":"common-thread"}"#
        let json: String
        switch path {
        case "instance": json = #"{"name":"Sample quilt","description":"A fictional quilt for exploring the native app.","geography":{"timezone":"America/New_York"}}"#
        case "nodes/tree": json = "{\"tree\":{\"children\":[\(patch),\(second)]}}"
        case "nodes/common-thread": json = "{\"node\":\(patch)}"
        case "nodes/listening-room": json = "{\"node\":\(second)}"
        case "events": json = "{\"items\":[\(event)],\"next_cursor\":\"\"}"
        case "events/demo-event": json = event
        default: throw APIError.status(404)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }
}
#endif
