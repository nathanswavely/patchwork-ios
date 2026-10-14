// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// The contact card (web ADR 083): the ways a person is willing to be reached,
// kept once, as typed items. Nothing on it is public and nothing is shared by
// adding it. This page owns the items; which patch may read which item is
// decided patch by patch, on My Patches, because granting is patch-first —
// you decide to be reachable standing in a room with people, not while
// editing a form. The one sharing act here is taking an item back.

// MARK: - The item, as the quilt serves it

/// The four kinds the server accepts (`model.ValidContactKind`). A closed set:
/// the kind is what lets a surface dial or mail a value without guessing at
/// it, so a new channel is the server's decision, not something typed into a
/// note.
enum ContactKind: String, CaseIterable, Identifiable {
    case phone, email, handle, note
    var id: String { rawValue }

    /// The web's word for it (`CONTACT_KIND_WORD`).
    var word: String {
        switch self {
        case .phone: return "Phone"
        case .email: return "Email"
        case .handle: return "Handle"
        case .note: return "Note"
        }
    }

    var symbol: String {
        switch self {
        case .phone: return "phone"
        case .email: return "envelope"
        case .handle: return "at"
        case .note: return "note.text"
        }
    }

    /// The web's placeholders, which double as the only instructions a field
    /// gets: what a value of this kind looks like.
    var placeholder: String {
        switch self {
        case .phone: return "+1 717 555 0100"
        case .email: return "reach@example.com"
        case .handle: return "@you on Signal"
        case .note: return "Text before calling"
        }
    }

    /// The server's limits per kind (`contact_items.go`), in the bytes Go
    /// counts. The field stops there rather than letting the quilt refuse it.
    var limit: Int {
        switch self {
        case .phone: return 60
        case .email: return 254
        case .handle: return 100
        case .note: return 200
        }
    }

    var keyboard: UIKeyboardType {
        switch self {
        case .phone: return .phonePad
        case .email: return .emailAddress
        case .handle, .note: return .default
        }
    }
}

/// One way to reach somebody (web ADR 083, `model.ContactItem`), and one item
/// on the card. The same shape answers four reads: the owner's own list
/// (`shared_with`, the number of patches it is shared into, absent when
/// none), a patch's sharing view (`shared`, whether *this* patch reads it),
/// and the items a profile shows a viewer who shares a patch with its owner
/// (neither). Nothing here ever names the patch an item was shared through:
/// that membership may be private or hidden, and naming it would put on the
/// profile what ADR 006 keeps off it.
struct ContactItem: Decodable, Identifiable, Hashable {
    let id: String
    var kind: String = ""
    var value: String = ""
    /// The person's own word for it — "work", "Signal only". Absent on the
    /// wire when empty, and empty here.
    var label: String = ""
    var position: Int = 0
    var sharedWith: Int? = nil
    var shared: Bool? = nil

    init(id: String, kind: String, value: String, label: String = "", position: Int = 0) {
        self.id = id; self.kind = kind; self.value = value; self.label = label; self.position = position
    }
    private enum CodingKeys: String, CodingKey { case id, kind, value, label, position, sharedWith, shared }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? "" }
        id = try c.decode(String.self, forKey: .id)
        kind = text(.kind); value = text(.value); label = text(.label)
        position = ((try? c.decodeIfPresent(Int.self, forKey: .position)) ?? nil) ?? 0
        sharedWith = (try? c.decodeIfPresent(Int.self, forKey: .sharedWith)) ?? nil
        shared = (try? c.decodeIfPresent(Bool.self, forKey: .shared)) ?? nil
    }

    var contactKind: ContactKind? { ContactKind(rawValue: kind) }
    /// The kind as a word, which leads the row: a bare string of digits
    /// reads as nothing until it is called a phone. A kind this client does
    /// not know is shown as the server spelled it, as the web's is.
    var word: String { contactKind?.word ?? kind }
    /// The kind's mark, beside the word rather than instead of it. None for
    /// a kind this client does not know.
    var symbol: String? { contactKind?.symbol }
    var patchesSharedWith: Int { sharedWith ?? 0 }

    /// "Shared with 2 patches", worded as the web words it.
    var sharingLine: String {
        switch patchesSharedWith {
        case 0: return "Not shared with any patch"
        case 1: return "Shared with 1 patch"
        default: return "Shared with \(patchesSharedWith) patches"
        }
    }

    /// What the value dials or writes to, or nothing (web `contactHref`). A
    /// phone is stripped to its digits and a leading plus, because the value
    /// is the person's own prose — "+1 717 555 0100, Signal only" is how
    /// people fill in a phone field — and a `tel:` address cannot carry the
    /// prose. A handle and a note have no scheme to open and stay text.
    var link: URL? {
        switch kind {
        case "phone":
            let digits = value.filter { $0 == "+" || ("0"..."9").contains($0) }
            return digits.isEmpty ? nil : URL(string: "tel:" + digits)
        case "email":
            let address = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty,
                  let escaped = address.addingPercentEncoding(withAllowedCharacters: People.mailtoAllowed) else { return nil }
            return URL(string: "mailto:" + escaped)
        default:
            return nil
        }
    }
}

/// `GET users/me/contact-items`.
struct ContactItemList: Decodable {
    let items: [ContactItem]
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([ContactItem].self, forKey: .items) ?? []
    }
    private enum CodingKeys: String, CodingKey { case items }
}

/// `GET nodes/{slug}/contact-shares`: every item on the reader's card, each
/// flagged with whether this patch reads it, and whether the reader may share
/// into this patch at all — a follower may not, and the server says so
/// rather than leaving the option to vanish.
struct ContactShares: Decodable {
    let items: [ContactItem]
    let canShare: Bool
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([ContactItem].self, forKey: .items) ?? []
        canShare = try container.decodeIfPresent(Bool.self, forKey: .canShare) ?? false
    }
    private enum CodingKeys: String, CodingKey { case items, canShare }
    var sharedIDs: Set<String> { Set(items.filter { $0.shared == true }.map(\.id)) }
}

/// What "Stop sharing everywhere" answers: how many patches it was taken from.
struct UnshareAnswer: Decodable { let unsharedFrom: Int? }

/// The body of an add or an edit. All three fields always travel: the server
/// reads an absent field as "leave it", so sending them all is what makes an
/// emptied label an emptied label.
struct ContactItemBody: Encodable, Equatable {
    let kind: String
    let value: String
    let label: String
}

/// `PUT nodes/{slug}/contact-shares`: the whole set this patch may read,
/// replaced at once. A partial update of a disclosure set is a request to get
/// it half-applied, so there is no other shape.
struct ContactShareSet: Encodable { let itemIds: [String] }

/// The editor's fields, held apart from the item until Add or Save.
struct ContactDraft: Equatable {
    var kind: ContactKind
    var value: String
    var label: String

    static let labelLimit = 40
    /// A card is a way to be reached, not a page (`maxContactItems`).
    static let maxItems = 12

    init(kind: ContactKind = .phone, value: String = "", label: String = "") {
        self.kind = kind; self.value = value; self.label = label
    }
    init(item: ContactItem) {
        kind = item.contactKind ?? .note
        value = item.value
        label = item.label
    }

    var body: ContactItemBody {
        ContactItemBody(kind: kind.rawValue,
                        value: value.trimmingCharacters(in: .whitespacesAndNewlines),
                        label: label.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    /// An item needs a value; the server says "delete it instead of emptying it".
    var hasValue: Bool { !body.value.isEmpty }
    /// Whether an edit says anything the item does not already.
    func differs(from item: ContactItem) -> Bool {
        body != ContactItemBody(kind: item.kind, value: item.value, label: item.label)
    }
    /// A field stops at its limit, the way the web's `maxlength` does.
    static func clamp(_ text: String, to limit: Int) -> String {
        guard text.utf8.count > limit else { return text }
        var kept = ""
        var bytes = 0
        for character in text {
            let size = String(character).utf8.count
            guard bytes + size <= limit else { break }
            kept.append(character)
            bytes += size
        }
        return kept
    }
}

extension PatchworkAPI {
    func contactItems() async throws -> [ContactItem] {
        let list: ContactItemList = try await get("users/me/contact-items")
        return list.items
    }
    /// A new item is born shared with nothing (web ADR 083 decision 5).
    @discardableResult func addContactItem(_ body: ContactItemBody) async throws -> ContactItem {
        try await post("users/me/contact-items", body: body)
    }
    /// Editing keeps every share the item has: sharing is a pairing, not a
    /// copy, so a new number reaches the same rooms.
    @discardableResult func updateContactItem(_ id: String, _ body: ContactItemBody) async throws -> ContactItem {
        try await patch("users/me/contact-items/\(id)", body: body)
    }
    /// Its shares go with it.
    func removeContactItem(_ id: String) async throws { try await deleteVoid("users/me/contact-items/\(id)") }
    /// The one item-first write, and it can only reduce exposure.
    func unshareEverywhere(_ id: String) async throws -> Int {
        let answer: UnshareAnswer = try await send("DELETE", "users/me/contact-items/\(id)/shares", body: NoBody())
        return answer.unsharedFrom ?? 0
    }
    func contactShares(slug: String) async throws -> ContactShares { try await get("nodes/\(slug)/contact-shares") }
    func setContactShares(slug: String, itemIDs: [String]) async throws {
        try await sendVoid("PUT", "nodes/\(slug)/contact-shares", body: ContactShareSet(itemIds: itemIDs))
    }
}

// MARK: - One item, as a row

/// The kind's mark and word, muted; the value; the person's own label after
/// a middle dot — the web's `ContactItems` row, which never names a patch.
struct ContactItemLine: View {
    let item: ContactItem
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: item.contactKind?.symbol ?? "questionmark.circle")
                .font(Font.pw.footnote)
                .foregroundStyle(Color.pwTextMuted)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.word).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                (Text(verbatim: item.value).foregroundStyle(Color.pwText)
                 + Text(verbatim: item.label.isEmpty ? "" : " · \(item.label)").foregroundStyle(Color.pwTextMuted))
                    .font(Font.pw.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The page

struct ContactCardSettings: View {
    @EnvironmentObject private var session: QuiltSession
    @State private var items: [ContactItem]?
    @State private var failure: String?
    @State private var note: String?
    @State private var busy = false
    @State private var editing: Editing?

    /// What the editor sheet is open on: a new item, or one already held.
    enum Editing: Identifiable {
        case new
        case item(ContactItem)
        var id: String { if case .item(let item) = self { return item.id } else { return "new" } }
    }

    var body: some View {
        List {
            Group {
                Section {
                    if let items {
                        if items.isEmpty {
                            Text("Nothing on your card yet.")
                                .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                                .accessibilityIdentifier("contactCardEmpty")
                        }
                        ForEach(items) { item in row(item) }
                        if items.count < ContactDraft.maxItems {
                            Button { editing = .new } label: {
                                Text("Add contact item").font(Font.pw.body).inkAction("plus.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(busy)
                            .accessibilityIdentifier("contactAdd")
                        } else {
                            Text("A contact card holds \(ContactDraft.maxItems) items at most.")
                                .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                        }
                    } else if failure == nil {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                } header: {
                    settingsHeading("Contact card")
                } footer: {
                    settingsFootnote("The ways you are willing to be reached. Nothing here is public and nothing is shared by adding it. You give each item to one patch at a time, in My Patches. A patch’s admins and members can then see it; its followers cannot.")
                }
                if let failure {
                    Section { Text(failure).font(Font.pw.footnote).foregroundStyle(Color.pwText).accessibilityIdentifier("contactError") }
                } else if let note {
                    Section {
                        Label(note, systemImage: "checkmark").font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                            .accessibilityIdentifier("contactNote")
                    }
                }
            }
            .listRows()
        }
        .groundedList()
        .navigationTitle("Contact card")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editing) { target in
            ContactItemEditor(target: target) { said in
                note = said
                failure = nil
                Task { await load() }
            }
            .environmentObject(session)
        }
    }

    private func row(_ item: ContactItem) -> some View {
        Button { editing = .item(item) } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    ContactItemLine(item: item)
                    Text(item.sharingLine)
                        .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                        .padding(.leading, 26)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Color.pwTextMuted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityIdentifier("contactItem")
        .accessibilityHint("Edits this item.")
        // The web removes without asking, and so does a swipe: the item is
        // the reader's own and can be typed again.
        .swipeActions {
            Button(role: .destructive) { Task { await remove(item) } } label: { Label("Remove", systemImage: "trash") }
            if item.patchesSharedWith > 0 {
                Button { Task { await unshare(item) } } label: { Label("Stop sharing", systemImage: "eye.slash") }
                    .tint(Color.pwTextMuted)
            }
        }
        .contextMenu {
            Button { editing = .item(item) } label: { Label("Edit", systemImage: "pencil") }
            if item.patchesSharedWith > 0 {
                Button { Task { await unshare(item) } } label: { Label("Stop sharing everywhere", systemImage: "eye.slash") }
            }
            Button(role: .destructive) { Task { await remove(item) } } label: { Label("Remove", systemImage: "trash") }
        }
    }

    private func load() async {
        do { items = try await session.api.contactItems(); failure = nil }
        catch APIError.unauthenticated { session.signedOut() }
        catch { failure = sentenceCased(SignInModel.sentence(error)) }
    }

    private func remove(_ item: ContactItem) async {
        busy = true
        defer { busy = false }
        do {
            try await session.api.removeContactItem(item.id)
            note = "Contact item removed"
            failure = nil
            await load()
            // A removed item takes its shares with it, so every "Reachable
            // by" count it was part of is now one smaller.
            await session.refreshMemberships()
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            failure = sentenceCased(SignInModel.sentence(error))
        }
    }

    private func unshare(_ item: ContactItem) async {
        busy = true
        defer { busy = false }
        do {
            let count = try await session.api.unshareEverywhere(item.id)
            note = ContactWording.unshared(count)
            failure = nil
            await load()
            await session.refreshMemberships()
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            failure = sentenceCased(SignInModel.sentence(error))
        }
    }
}

/// The page's sentences, as values.
enum ContactWording {
    /// Deliberately not "revoked": this stops the surface, not the knowing.
    static func unshared(_ count: Int) -> String {
        "No longer shown to \(count == 1 ? "1 patch" : "\(count) patches")"
    }
    /// What a patch's sharing control says on its face.
    static func reach(_ count: Int) -> String { count > 0 ? "Reachable by \(count)" : "Not reachable" }
    /// What a saved share set turned out to be.
    static func shareOutcome(patch: String, count: Int) -> String {
        count == 0 ? "\(patch) can no longer reach you"
            : "\(patch) can reach you by \(count == 1 ? "1 item" : "\(count) items")"
    }
}

// MARK: - The editor

/// Adding or editing one item. The kind is a segmented choice of four; the
/// value's keyboard follows it. The sheet makes its own call and stays open
/// on a refusal, so what was typed is still there to fix.
struct ContactItemEditor: View {
    let target: ContactCardSettings.Editing
    let done: (String) -> Void
    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ContactDraft()
    @State private var busy = false
    @State private var failure: String?

    private var item: ContactItem? { if case .item(let item) = target { return item } else { return nil } }
    private var canSave: Bool {
        guard draft.hasValue, !busy else { return false }
        if let item { return draft.differs(from: item) }
        return true
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        Picker("Kind", selection: $draft.kind) {
                            ForEach(ContactKind.allCases) { Text($0.word).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("contactKind")
                    } header: { settingsHeading("Kind") }
                    Section {
                        TextField(text: $draft.value, prompt: Text(verbatim: draft.kind.placeholder)) { Text("Value") }
                            .keyboardType(draft.kind.keyboard)
                            .textContentType(draft.kind == .phone ? .telephoneNumber : draft.kind == .email ? .emailAddress : nil)
                            .textInputAutocapitalization(draft.kind == .note ? .sentences : .never)
                            .autocorrectionDisabled(draft.kind != .note)
                            .accessibilityIdentifier("contactValue")
                            .onChange(of: draft.value) { _, now in
                                let clamped = ContactDraft.clamp(now, to: draft.kind.limit)
                                if clamped != now { draft.value = clamped }
                            }
                        TextField("Label (optional)", text: $draft.label)
                            .accessibilityIdentifier("contactLabel")
                            .onChange(of: draft.label) { _, now in
                                let clamped = ContactDraft.clamp(now, to: ContactDraft.labelLimit)
                                if clamped != now { draft.label = clamped }
                            }
                    } header: {
                        settingsHeading(draft.kind.word)
                    } footer: {
                        if draft.kind == .email {
                            settingsFootnote("Separate from the address you sign in with. That one is never shared.")
                        } else if let item {
                            settingsFootnote(item.patchesSharedWith > 0
                                             ? "Saving keeps its sharing: the patches you share it with see the new value."
                                             : "Not shared with any patch. Choose who can see it in My Patches.")
                        }
                    }
                    if let failure {
                        Section {
                            Label { Text(failure).font(Font.pw.footnote) } icon: {
                                Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
                            }
                            .foregroundStyle(Color.pwText)
                            .accessibilityIdentifier("contactEditorError")
                        }
                    }
                    if let item {
                        Section {
                            if item.patchesSharedWith > 0 {
                                Button { Task { await unshare(item) } } label: {
                                    Text("Stop sharing everywhere").font(Font.pw.body).inkAction("eye.slash")
                                }
                                .disabled(busy)
                                .accessibilityIdentifier("contactUnshare")
                            }
                            // Removed at once, as the web removes it: the item is
                            // the reader's own and can be typed again.
                            Button(role: .destructive) { Task { await remove(item) } } label: {
                                Text("Remove from card").font(Font.pw.body)
                            }
                            .disabled(busy)
                            .accessibilityIdentifier("contactRemove")
                        } footer: {
                            if item.patchesSharedWith > 0 {
                                settingsFootnote("\(item.sharingLine). Stopping takes it off every patch at once; it stays on your card.")
                            }
                        }
                    }
                }
                .listRows()
            }
            .groundedList()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(item == nil ? "New contact item" : "Contact item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button(item == nil ? "Add" : "Save") { Task { await save() } }
                            .disabled(!canSave)
                            .accessibilityIdentifier("contactSave")
                    }
                }
            }
            .onAppear { if let item { draft = ContactDraft(item: item) } }
            .onChange(of: draft) { _, _ in failure = nil }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            if let item {
                try await session.api.updateContactItem(item.id, draft.body)
                finish(item.patchesSharedWith > 0 ? "Saved. The patches you share it with see the new value" : "Saved")
            } else {
                try await session.api.addContactItem(draft.body)
                finish("Contact item added")
            }
        } catch APIError.unauthenticated {
            session.signedOut()
            dismiss()
        } catch {
            failure = sentenceCased(SignInModel.sentence(error))
        }
    }

    private func remove(_ item: ContactItem) async {
        busy = true
        defer { busy = false }
        do {
            try await session.api.removeContactItem(item.id)
            await session.refreshMemberships()
            finish("Contact item removed")
        } catch APIError.unauthenticated {
            session.signedOut()
            dismiss()
        } catch {
            failure = sentenceCased(SignInModel.sentence(error))
        }
    }

    private func unshare(_ item: ContactItem) async {
        busy = true
        defer { busy = false }
        do {
            let count = try await session.api.unshareEverywhere(item.id)
            await session.refreshMemberships()
            finish(ContactWording.unshared(count))
        } catch APIError.unauthenticated {
            session.signedOut()
            dismiss()
        } catch {
            failure = sentenceCased(SignInModel.sentence(error))
        }
    }

    private func finish(_ said: String) {
        done(said)
        dismiss()
    }
}
