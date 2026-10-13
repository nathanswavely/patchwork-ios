// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import Patchwork

/// A person's profile as values: what `users/{username}` decodes to, what
/// each contact item dials or writes to, which names are doors, and what a
/// report about a person sends.
final class PeopleTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
    private func person(_ json: String) throws -> Person {
        try decoder().decode(Person.self, from: Data(json.utf8))
    }

    // MARK: Decoding

    /// The server's own shape (`internal/handler/users.go`), signed in and
    /// sharing a patch: every kind of contact item, and a label left out
    /// where it is empty, as `omitempty` leaves it.
    func testAProfileDecodesWhole() throws {
        let profile = try person("""
        {"id":"8a1f","username":"rowan","display_name":"Rowan Hale","bio":"Runs the desk.","avatar_url":"",
         "links":[{"url":"https://www.rowan.example.org/","label":""},{"url":"https://makers.example.org","label":"Makers"}],
         "moved_to":"","created_at":"2026-01-14T10:00:00Z",
         "memberships":[{"node_id":"p1","node_slug":"common-thread","node_name":"Common Thread Studio","role":"admin","joined_at":"2026-01-14T10:00:00Z"},
                        {"node_id":"p2","node_slug":"repair-cafe","node_name":"Repair Cafe","role":"member","joined_at":"2026-02-01T10:00:00Z"}],
         "contact":[{"id":"c1","kind":"phone","value":"+1 717 555 0100, evenings","label":"mobile","position":0},
                    {"id":"c2","kind":"email","value":"rowan@example.org","position":1},
                    {"id":"c3","kind":"handle","value":"@rowan@social.example","position":2},
                    {"id":"c4","kind":"note","value":"Tuesdays at the desk","position":3}]}
        """)
        XCTAssertEqual(profile.id, "8a1f")
        XCTAssertEqual(profile.name, "Rowan Hale")
        XCTAssertEqual(profile.initial, "R")
        XCTAssertNil(profile.avatar, "an empty address is no avatar")
        XCTAssertEqual(profile.runs.map(\.nodeSlug), ["common-thread"])
        XCTAssertEqual(profile.memberOf.map(\.title), ["Repair Cafe"])
        XCTAssertEqual(profile.contact.map(\.kind), ["phone", "email", "handle", "note"])
        XCTAssertEqual(profile.contact[0].label, "mobile")
        XCTAssertEqual(profile.contact[1].label, "", "an absent label is an empty one")
        XCTAssertEqual(profile.contact[3].position, 3)
        XCTAssertEqual(profile.openableLinks.map(\.title), ["rowan.example.org", "Makers"], "a label, or the host without www.")
        XCTAssertFalse(profile.isEmpty)
        XCTAssertTrue(profile.handleLine.hasPrefix("@rowan · here since "))
        XCTAssertTrue(profile.handleLine.contains("2026"))
    }

    /// Signed out: the identity and the patches, and no card at all. A
    /// quilt a version behind, missing whole fields, is still read.
    func testAThinProfileIsStillRead() throws {
        let profile = try person(#"{"id":"u3","username":"theo","links":[{"url":"https://theo.example"}]}"#)
        XCTAssertEqual(profile.name, "theo", "no display name falls back to the handle")
        XCTAssertEqual(profile.handleLine, "@theo", "no date, no 'here since'")
        XCTAssertTrue(profile.memberships.isEmpty)
        XCTAssertTrue(profile.contact.isEmpty)
        XCTAssertEqual(profile.links.first?.label, "", "a link with no label keeps its address")
        XCTAssertFalse(profile.isEmpty, "a link is something")
        XCTAssertTrue(try person(#"{"id":"u3","username":"theo","bio":"  "}"#).isEmpty, "a blank bio is nothing")
    }

    /// A role the web gives no heading — a follower, if one ever arrived —
    /// is in neither list, and leaves the profile empty.
    func testOnlyAdminsAndMembersAreListed() throws {
        let profile = try person(#"{"id":"u","username":"x","memberships":[{"node_slug":"a","node_name":"A","role":"follower"}]}"#)
        XCTAssertTrue(profile.runs.isEmpty)
        XCTAssertTrue(profile.memberOf.isEmpty)
        XCTAssertTrue(profile.isEmpty)
    }

    func testAMoveIsReadAsAHost() {
        let moved = People.moved("https://www.neighbor.example.org/users/sam")
        XCTAssertEqual(moved?.host, "neighbor.example.org")
        XCTAssertEqual(People.movedLine("neighbor.example.org"), "This person has moved to neighbor.example.org.")
        XCTAssertNil(People.moved(""), "empty is not moved")
        XCTAssertNil(People.moved("not a link"))
    }

    // MARK: Contact items

    func testAPhoneDialsItsDigitsOnly() {
        let phone = ContactItem(id: "c", kind: "phone", value: "+1 (717) 555-0100, Signal only")
        XCTAssertEqual(phone.link?.absoluteString, "tel:+17175550100")
        XCTAssertEqual(phone.word, "Phone")
        XCTAssertEqual(phone.symbol, "phone")
        XCTAssertNil(ContactItem(id: "c", kind: "phone", value: "ask at the desk").link, "no digits, nothing to dial")
    }

    func testAnEmailWritesToItsAddress() {
        XCTAssertEqual(ContactItem(id: "c", kind: "email", value: " rowan@example.org ").link?.absoluteString, "mailto:rowan@example.org")
        XCTAssertEqual(ContactItem(id: "c", kind: "email", value: "a+b@example.org").link?.absoluteString, "mailto:a+b@example.org")
        XCTAssertEqual(ContactItem(id: "c", kind: "email", value: "a b@example.org").link?.absoluteString, "mailto:a%20b@example.org",
                       "a stray space is escaped rather than refused")
        XCTAssertNil(ContactItem(id: "c", kind: "email", value: "  ").link)
    }

    func testAHandleAndANoteAreOnlyRead() {
        XCTAssertNil(ContactItem(id: "c", kind: "handle", value: "@rowan@social.example").link)
        XCTAssertNil(ContactItem(id: "c", kind: "note", value: "Tuesdays").link)
        XCTAssertEqual(ContactItem(id: "c", kind: "handle", value: "x").word, "Handle")
        XCTAssertEqual(ContactItem(id: "c", kind: "note", value: "x").word, "Note")
        let unknown = ContactItem(id: "c", kind: "pager", value: "123")
        XCTAssertEqual(unknown.word, "pager", "an unknown kind is shown as the server spelled it")
        XCTAssertNil(unknown.symbol)
        XCTAssertNil(unknown.link)
    }

    // MARK: Doors

    /// A deleted account, a hidden member and a withheld chair all arrive
    /// with a blank username, and none of them is a door.
    func testABlankUsernameIsNeverADoor() {
        XCTAssertEqual(People.door("rowan"), "rowan")
        XCTAssertEqual(People.door(" rowan "), "rowan")
        XCTAssertNil(People.door(""))
        XCTAssertNil(People.door("   "))
        XCTAssertNil(People.door(nil))
    }

    func testANotificationCanPointAtAPerson() {
        XCTAssertEqual(NotificationLink.route("/users/rowan"), .person(username: "rowan"))
        XCTAssertEqual(NotificationLink.route("/users/rowan/"), .person(username: "rowan"))
        XCTAssertEqual(NotificationLink.route("/users/"), .website(path: "/users/"))
        XCTAssertEqual(NotificationLink.route("/users/rowan/settings"), .website(path: "/users/rowan/settings"))
    }

    // MARK: Reporting

    func testAReportAboutAPersonSendsTheirId() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = String(decoding: try encoder.encode(ReportBody(entityType: .user, entityId: "8a1f", reason: "Impersonation", details: "")), as: UTF8.self)
        XCTAssertEqual(body, #"{"details":"","entity_id":"8a1f","entity_type":"user","reason":"Impersonation"}"#)
    }

    func testAReportAboutAPersonGoesToTheQuiltsAdmins() {
        let target = ReportTarget(kind: .user, id: "8a1f", subject: "Rowan Hale")
        XCTAssertEqual(target.heading, "Report this person")
        XCTAssertEqual(target.named, "Rowan Hale")
        XCTAssertEqual(target.destination, "Reports go to the instance admins, who review them against the community lining.")
        XCTAssertEqual(ReportTarget(kind: .user, id: "x", subject: " ").named, "this person")
        XCTAssertEqual(ReportTarget(kind: .notice, id: "n", subject: "Kiln").destination, Noticeboard.reportDestination,
                       "a notice still goes to its patch's admins")
    }
}
