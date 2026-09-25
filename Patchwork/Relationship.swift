// SPDX-License-Identifier: MPL-2.0

import Foundation

/// What a reader *is* to a patch, and what a patch will accept from them.
///
/// The web keeps this in one component (`PatchRelationship.svelte`) so the
/// profile, the cards and the dashboard cannot disagree about who you are.
/// Here it is a value with no view in it at all: the rules below are the
/// server's, read off the node payload and the membership index, and they are
/// checked in `RelationshipTests` without a window open. Nothing in this file
/// invents an act — every branch corresponds to a call the server accepts, and
/// the branches that correspond to none show no control.

/// The three roles an *active* row can hold. The server sends no role at all
/// on a pending one, which is why `Standing` carries the role rather than
/// `Membership` handing one out.
enum MembershipRole: String, Codable, Hashable, CaseIterable {
    case admin, member, follower

    /// The standing mark's word, as the web writes it.
    var mark: String {
        switch self {
        case .admin: return "Admin"
        case .member: return "Member"
        case .follower: return "Following"
        }
    }

    /// The mark's glyph: a heart for following, people for a member, a wrench
    /// for whoever holds the spanner.
    var symbol: String {
        switch self {
        case .admin: return "wrench.and.screwdriver"
        case .member: return "person.2"
        case .follower: return "heart.fill"
        }
    }

    /// The one way out, in the word the act is called by. Following is left by
    /// unfollowing; a membership is left by leaving. Both are `…/leave`.
    var exit: String { self == .follower ? "Unfollow" : "Leave" }
}

/// Where a reader stands with one patch: in it, or waiting to be let in.
/// Anything else is no standing at all, which is `nil`.
enum Standing: Equatable {
    case active(MembershipRole)
    case pending

    /// The patch's own answer about the reader, which `GET nodes/{slug}`
    /// carries when there is a session. It is the first frame's answer — the
    /// membership index is the one every surface reads — but it is the
    /// server's word either way, so a profile opened before the index came
    /// back is right rather than blank.
    static func from(node: Patch) -> Standing? {
        guard node.isMember == true || node.isAdmin == true else { return nil }
        if let role = node.membershipRole.flatMap(MembershipRole.init(rawValue:)) { return .active(role) }
        return .active(node.isAdmin == true ? .admin : .member)
    }
}

/// One row of `GET me/nodes`: a patch this reader holds something on, with
/// enough of the patch travelling alongside it that a dashboard can name the
/// patch without asking the quilt about it again.
struct Membership: Decodable, Identifiable, Hashable {
    let id: String
    let userId: String?
    let nodeId: String?
    /// Absent unless the row is active (the server's own rule).
    let role: String?
    /// `active` or `pending`. Nothing else is served.
    let status: String?
    let visible: Bool?
    let joinedAt: String?
    let nodeName: String?
    let nodeSlug: String?
    let nodeDescription: String?
    let nodeVisibility: String?
    let membershipPolicy: String?
    let nodeStatus: String?

    var slug: String { nodeSlug ?? "" }
    var name: String { (nodeName?.isEmpty == false) ? nodeName! : slug }

    /// The row read as a standing. A role that does not parse on an active row
    /// is read as plain membership: the server does not send one, and the
    /// alternative — dropping the row — would hide a membership the reader has.
    var standing: Standing? {
        switch status {
        case "active": return .active(MembershipRole(rawValue: role ?? "") ?? .member)
        case "pending": return .pending
        default: return nil
        }
    }
}

/// `GET me/nodes`, which answers `{"items":[…]}` — and a bare array is read
/// the same way rather than thrown out, because the quilt is the authority on
/// its own envelope and this client only needs the rows.
struct MembershipPage: Decodable {
    let items: [Membership]
    init(from decoder: Decoder) throws {
        if let array = try? [Membership](from: decoder) { items = array; return }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Membership].self, forKey: .items) ?? []
    }
    private enum CodingKeys: String, CodingKey { case items }
}

/// What `…/join`, `…/leave` and `…/withdraw` answer with.
struct MembershipAct: Decodable {
    let status: String?
    let membershipId: String?
}

/// The body of a join. `role: "follower"` is following; no role is joining,
/// with an optional message the patch's admins read. Both nil encodes as `{}`,
/// which is exactly what the server wants for a plain join.
struct JoinRequest: Encodable {
    var role: String?
    var message: String?
}

/// The one decision: given a patch and where the reader stands with it, which
/// control belongs on screen.
enum Relationship: Equatable {
    /// No control at all. A banned reader has nothing to press, and a patch
    /// that has moved is read-only — the moved notice already explains it.
    case none
    /// A standing to wear, and one exit out of it.
    case holding(MembershipRole)
    /// A request the patch has not answered yet.
    case requested
    /// A stranger, and what this patch will take from one.
    case offering(Offer)

    /// Follow and Join are independent offers: a public unclaimed listing can
    /// be followed and not joined, an invite-only public patch can be followed
    /// and not joined, and a claimed private patch can be joined and not
    /// followed.
    struct Offer: Equatable {
        var follow = false
        var join: Join?
        var isEmpty: Bool { !follow && join == nil }
    }

    /// The policy, read aloud on the button. `approval_required` asks; `open`
    /// admits.
    enum Join: Equatable {
        case now
        case request
        var title: String { self == .request ? "Request to join" : "Join" }
    }

    /// The web's rules, in the web's order. Every guard above the offers is a
    /// state the server would refuse an act in.
    static func resolve(node: Patch, standing: Standing?) -> Relationship {
        if node.isBanned == true { return .none }
        if node.movedTo?.isEmpty == false { return .none }
        switch standing {
        case .active(let role): return .holding(role)
        case .pending: return .requested
        case nil: break
        }
        var offer = Offer()
        // Following is a public act on a public patch and nothing else. A
        // patch that states no visibility is one the tree served, and the
        // tree serves only public patches (its SQL says so and sends no
        // `visibility` key); the node endpoint always states it, so a private
        // patch reached directly still says "private" and is refused here.
        offer.follow = (node.visibility ?? "public") == "public"
        // Joining needs somebody to join: an unclaimed listing has no members
        // to be one of, and an invite-only patch does the asking itself.
        if !node.communityListing, node.membershipPolicy != "invite_only" {
            offer.join = node.membershipPolicy == "approval_required" ? .request : .now
        }
        return offer.isEmpty ? .none : .offering(offer)
    }

    /// What a join turned out to be, said in the web's words. It is read off
    /// the status the server answered with rather than off the policy the
    /// button was drawn from: the policy can change between the two.
    static func joinOutcome(status: String?) -> String {
        status == "pending" ? "Membership request sent" : "You are now a member"
    }
}
