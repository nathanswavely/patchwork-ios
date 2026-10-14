// SPDX-License-Identifier: MPL-2.0

import Foundation

// Patch invitations, the invitee's half (web ADR 098). An admin of an
// invite-only patch asks an existing account into it by username, and the
// person answers. There is no link and no token: the reader learns of it from
// the "You're invited to join X" notification, which names the patch, and
// answers on the patch's own profile, where Accept and Decline stand in the
// place Follow would. Sending and rescinding invitations are the admin's, and
// live elsewhere.

/// One unanswered invitation, from `GET users/me/invitations`.
struct Invitation: Decodable, Identifiable, Hashable {
    let id: String
    let nodeId: String?
    let nodeSlug: String
    let nodeName: String?
    /// Always `invited`. The server sends it so a client reading this beside
    /// `me/nodes` can tell the two kinds of row apart by the same field.
    let status: String?
    let invitedAt: String?
    var name: String { (nodeName?.isEmpty == false) ? nodeName! : nodeSlug }
}

/// `{"items":[…]}`, filtered to invited rows even though the endpoint serves
/// nothing else — the web's own guard, so a server or a stub that answered
/// with membership rows could not turn a membership into an invitation.
struct InvitationPage: Decodable {
    let items: [Invitation]
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rows = try container.decodeIfPresent([Invitation].self, forKey: .items) ?? []
        items = rows.filter { ($0.status ?? "invited") == "invited" && !$0.nodeSlug.isEmpty }
    }
    private enum CodingKeys: String, CodingKey { case items }
}

extension PatchworkAPI {
    func invitations() async throws -> [Invitation] {
        let page: InvitationPage = try await get("users/me/invitations")
        return page.items
    }
}

/// A sentence waiting for a patch's profile to dock: what the sheet that
/// sent the reader there would have toasted on the web. The profile shows it
/// in the place the head's own acts report, once, and lets it go.
struct ArrivalNote: Equatable {
    let slug: String
    let text: String
}
