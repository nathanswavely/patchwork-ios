// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// Suggesting a patch somebody else runs (web `/submit`, SubmitPatch.svelte;
// the server's `SubmitPatch`). It joins the quilt as an unclaimed listing —
// at once for a quilt-wide trusted contributor or a quilt that approves
// everything, and after an instance admin's review for everybody else — and
// the people who run it can claim it later.

/// What the form holds.
struct SuggestionDraft: Equatable {
    struct LinkRow: Equatable, Identifiable {
        let id = UUID()
        var url = ""
        var label = ""
        static func == (a: LinkRow, b: LinkRow) -> Bool { a.url == b.url && a.label == b.label }
    }
    var name = ""
    var description = ""
    var website = ""
    var feedURL = ""
    var links: [LinkRow] = [LinkRow()]
    var address = ""
    /// Curated words only: a suggestion coins none.
    var tags: [String] = []

    func problem() -> String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Name is required" : nil
    }

    private static func filled(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `POST submissions`, as the web sends it: the description always (the
    /// server takes an empty one), everything else only where it was filled,
    /// and a link only where it has an address.
    var body: SubmissionBody {
        let rows = links.compactMap { row -> SubmissionBody.Link? in
            guard let url = Self.filled(row.url) else { return nil }
            return SubmissionBody.Link(url: url, label: Self.filled(row.label))
        }
        return SubmissionBody(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                              description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                              website: Self.filled(website), links: rows.isEmpty ? nil : rows,
                              address: Self.filled(address), feedUrl: Self.filled(feedURL),
                              tags: tags.isEmpty ? nil : tags)
    }
}

struct SubmissionBody: Encodable, Equatable {
    struct Link: Encodable, Equatable {
        let url: String
        let label: String?
    }
    let name: String
    let description: String
    let website: String?
    let links: [Link]?
    let address: String?
    let feedUrl: String?
    let tags: [String]?
}

/// The 201: published at once, with the listing; or waiting for review.
struct SubmissionAnswer: Decodable, Equatable {
    struct Node: Decodable, Equatable {
        let id: String?
        let slug: String
        let name: String?
    }
    let status: String?
    let node: Node?
    let message: String?
    let id: String?
    var published: Bool { node != nil }
}

/// The form's sentences, as values.
enum SuggestionRules {
    static let published = "Patch added to the quilt!"
    static let waiting = "Suggested. An admin will review it and you'll be notified."
    static let similarName = "A patch with a similar name already exists."
    /// The note under the form, which says what will happen before it does.
    static func reviewNote(trusted: Bool) -> String {
        trusted
            ? "As a trusted contributor, your suggestion joins the quilt at once."
            : "An instance admin reviews suggestions. Once it's approved, you can add its events without review until its owner claims it."
    }
    /// A refusal: the web's sentence for the collision, and the server's for
    /// everything else.
    static func sentence(_ error: Error) -> String {
        if (error as? APIError)?.httpStatus == 409 { return similarName }
        return sentenceCased(ProposalDetailView.sentence(error, fallback: "Something went wrong."))
    }
}

extension PatchworkAPI {
    func suggestPatch(_ body: SubmissionBody) async throws -> SubmissionAnswer { try await post("submissions", body: body) }
}

// MARK: - The form

struct SuggestPatchForm: View {
    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SuggestionDraft
    @State private var busy = false
    @State private var failure: String?
    /// The patch a 409 named, offered as a door.
    @State private var existing: String?
    @State private var existingMissing = false
    /// Waiting for review: the form gives way to the web's sentence.
    @State private var waiting = false

    init(name: String = "") {
        var draft = SuggestionDraft()
        draft.name = name
        _draft = State(initialValue: draft)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if waiting { waitingCard } else { form }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.pwGround.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if !waiting { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
        }
        .safeAreaInset(edge: .bottom) { foot }
        .interactiveDismissDisabled(busy)
    }

    @ViewBuilder private var form: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suggest a patch")
                .font(Font.pw.displayTitle2).foregroundStyle(Color.pwText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("suggestHeading")
            Text("Know a place or group that should be on the map? Suggest it here and the real owner can claim it later.")
                .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        field("Name", required: true) {
            TextField("e.g. Gallery Row", text: $draft.name)
                .textInputAutocapitalization(.words)
                .fieldStyle()
                .accessibilityIdentifier("suggestName")
                .onChange(of: draft.name) { _, _ in existing = nil; existingMissing = false }
        }
        field("Description") {
            TextField("What is this place/group about?", text: $draft.description, axis: .vertical)
                .lineLimit(3...6)
                .fieldStyle()
                .accessibilityIdentifier("suggestDescription")
        }
        field("Website") { urlField("Website", text: $draft.website, identifier: "suggestWebsite") }
        field("Events feed", optional: true,
              hint: "A calendar Patchwork can read: an ICS address, a Squarespace events page, or a page with event markup. Checked when you submit.") {
            urlField("Events feed", text: $draft.feedURL, identifier: "suggestFeed")
        }
        field("Links") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach($draft.links) { $row in
                    VStack(alignment: .leading, spacing: 6) {
                        urlField("Link", text: $row.url, identifier: "suggestLinkURL")
                        TextField("Label (optional)", text: $row.label)
                            .fieldStyle()
                            .accessibilityIdentifier("suggestLinkLabel")
                        if draft.links.count > 1 {
                            Button { draft.links.removeAll { $0.id == row.id } } label: {
                                Text("Remove link").font(Font.pw.subheadline)
                            }
                            .buttonStyle(.plain)
                            .inkAction("minus.circle")
                        }
                    }
                }
                Button { draft.links.append(.init()) } label: { Text("Add link").font(Font.pw.subheadline) }
                    .buttonStyle(.plain)
                    .inkAction("plus.circle")
                    .accessibilityIdentifier("suggestAddLink")
            }
        }
        field("Address", optional: true) {
            TextField("123 Main St, Lancaster, PA", text: $draft.address)
                .textContentType(.fullStreetAddress)
                .fieldStyle()
                .accessibilityIdentifier("suggestAddress")
        }
        field("Tags", optional: true) {
            TagPicker(picked: $draft.tags, suggested: .constant([]), vocabulary: session.tagTerms, allowSuggesting: false)
        }
        if let failure {
            VStack(alignment: .leading, spacing: 8) {
                Label { Text(failure).font(Font.pw.footnote) } icon: {
                    Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
                }
                .foregroundStyle(Color.pwText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("suggestError")
                if let existing {
                    // The 409 names the patch it collided with: a door to it,
                    // because the thing the reader wanted to add may be there.
                    Button { Task { await open(existing) } } label: {
                        Text("Open the patch that already exists").font(Font.pw.subheadline)
                    }
                    .buttonStyle(.plain)
                    .inkAction("arrow.right.circle")
                    .accessibilityIdentifier("openExistingPatch")
                    if existingMissing {
                        Text("That patch isn’t on the quilt yet. It may still be waiting for review.")
                            .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                            .accessibilityIdentifier("existingPatchMissing")
                    }
                }
            }
        }
        Text(SuggestionRules.reviewNote(trusted: session.me?.trustedContributor == true))
            .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("suggestReviewNote")
    }

    private var waitingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Suggested", systemImage: "clock.badge.questionmark")
                .font(Font.pw.title3).foregroundStyle(Color.pwText)
                .accessibilityAddTraits(.isHeader)
            Text(SuggestionRules.waiting)
                .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("suggestWaiting")
        }
        .cardSurface()
    }

    private func urlField(_ title: String, text: Binding<String>, identifier: String) -> some View {
        TextField(text: text, prompt: Text(verbatim: "https://...")) { Text(title) }
            .keyboardType(.URL).textContentType(.URL)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .fieldStyle()
            .accessibilityIdentifier(identifier)
    }

    private func field<Content: View>(_ title: String, required: Bool = false, optional: Bool = false, hint: String? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title + (required ? " *" : "") + (optional ? " (optional)" : ""))
                .font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
                .accessibilityAddTraits(.isHeader)
            content()
            if let hint {
                Text(hint).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var foot: some View {
        Button { if waiting { dismiss() } else { submit() } } label: {
            Group {
                if busy { ProgressView().tint(.white) } else { Text(waiting ? "Done" : "Submit").font(Font.pw.headline) }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .foregroundStyle(busy ? Color.pwTextMuted : Color.white)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.pwAccent)
        .controlSize(.large)
        .disabled(busy)
        .accessibilityIdentifier(waiting ? "suggestDone" : "suggestSubmit")
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func submit() {
        guard !busy else { return }
        failure = nil
        existing = nil
        existingMissing = false
        if let problem = draft.problem() { failure = problem; return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let answer = try await session.api.suggestPatch(draft.body)
                if let node = answer.node {
                    // On the quilt already: read it again and land on it.
                    await session.loadTree(refreshingWhole: true)
                    session.arrival = ArrivalNote(slug: node.slug, text: SuggestionRules.published)
                    session.dock(afterSheet: node.slug)
                    dismiss()
                } else {
                    withAnimation { waiting = true }
                }
            } catch APIError.unauthenticated {
                session.signedOut()
            } catch {
                failure = SuggestionRules.sentence(error)
                existing = (error as? APIError)?.existingSlug
            }
        }
    }

    /// A patch waiting for its own review is on no list and cannot be read,
    /// so the door is tried before the sheet goes.
    private func open(_ slug: String) async {
        do {
            let _: PatchResponse = try await session.api.get("nodes/\(slug)")
            session.dock(afterSheet: slug)
            dismiss()
        } catch {
            existingMissing = true
        }
    }
}

/// A door that needs an account: the sign-in sheet for a reader without one,
/// the suggestion form for a reader with one. Used where the website's
/// `/submit` link used to be.
struct SuggestPatchDoor<Label: View>: View {
    @EnvironmentObject private var session: QuiltSession
    var name: String = ""
    @ViewBuilder let label: () -> Label
    @State private var signIn = false
    @State private var suggesting = false
    var body: some View {
        Button(action: { if session.me == nil { signIn = true } else { suggesting = true } }, label: label)
            .signInGate($signIn)
            .sheet(isPresented: $suggesting, onDismiss: {
                // Landing on a patch ends the search that led here, the way
                // a found patch's own card does.
                if session.patchWaiting { session.endSearch() }
                session.sheetDismissed()
            }) {
                NewPatchSheet(start: .suggest(name: name))
            }
    }
}
