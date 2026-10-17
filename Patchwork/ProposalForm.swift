// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// The door to a new proposal, in a room's bottom bar, the way "New event"
/// sits in the calendar's and "Put up a notice" in the board's. Worded as
/// the outcome: "New change" for the admin of a patch whose admins decide.
struct ProposalDoorButton: View {
    let label: String
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(Font.pw.subheadlineSemibold)
                Text(label).font(Font.pw.subheadlineSemibold)
            }
            .foregroundStyle(Color.pwText)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier("proposalDoor")
    }
}

/// Raising a proposal (web `ProposalForm.svelte`), as a sheet over the room
/// it was opened from. One page, as on the web — there is no draft to come
/// back to (ADR 048) — with the act at the foot. What the act is called, and
/// whether a window is asked for at all, follow `ProposalPosting.outcome`,
/// which is the server's own switch.
struct ProposalFormSheet: View {
    let slug: String
    /// The patch's rules as the governance overview states them, its seats
    /// and its next contest, which say whether a nomination is offered and,
    /// on an elected patch, where the way onto the council is instead.
    let rules: GovernanceRules?
    var seats: [GovernanceSeat] = []
    var nextContestOpens: String? = nil
    let isPatchAdmin: Bool
    /// The proposal as the server made it.
    let onDone: (Proposal) -> Void

    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProposalDraft
    @State private var busy = false
    @State private var failure: String?
    /// The roster a nomination picks from, read once the type is chosen.
    @State private var members: [PatchMember]?

    init(slug: String, rules: GovernanceRules?, seats: [GovernanceSeat] = [], nextContestOpens: String? = nil,
         isPatchAdmin: Bool, onDone: @escaping (Proposal) -> Void) {
        self.slug = slug
        self.rules = rules
        self.seats = seats
        self.nextContestOpens = nextContestOpens
        self.isPatchAdmin = isPatchAdmin
        self.onDone = onDone
        _draft = State(initialValue: ProposalDraft(durationHours: ProposalPosting.defaultDuration(rules)))
    }

    private var chooses: Bool { ProposalPosting.adminChooses(rules, isPatchAdmin: isPatchAdmin) }
    private var outcome: ProposalPosting.Outcome {
        ProposalPosting.outcome(rules: rules, isPatchAdmin: isPatchAdmin, putToVote: chooses && draft.putToVote)
    }
    private var heading: String { chooses ? "New change" : "New proposal" }
    private var mayNominate: Bool { ProposalPosting.mayNominate(rules: rules, seats: seats, isPatchAdmin: isPatchAdmin) }
    private var ready: Bool { !busy && ProposalPosting.problem(draft) == nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(heading)
                            .font(Font.pw.displayTitle2).foregroundStyle(Color.pwText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("proposalFormHeading")
                        if let note = ProposalPosting.outcomeNote(outcome) {
                            Text(note)
                                .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("proposalFormNote")
                        }
                    }
                    field("Title") {
                        TextField("What should happen?", text: $draft.title, axis: .vertical)
                            .lineLimit(1...3)
                            .textInputAutocapitalization(.sentences)
                            .fieldStyle()
                            .accessibilityIdentifier("proposalTitle")
                    }
                    field("Description") {
                        MarkdownComposer(text: $draft.body, title: "Description",
                                         placeholder: "Explain it and why it matters. Use **bold**, *italic*, and - lists.",
                                         base: session.quilt.url, segmentsID: "proposalWritePreview",
                                         fieldID: "proposalBody", previewID: "proposalPreview")
                    }
                    typeField
                    if draft.kind == .membership && mayNominate { nomineeField }
                    if let note = ProposalPosting.councilNote(rules: rules, seats: seats, isPatchAdmin: isPatchAdmin, nextContestOpens: nextContestOpens) {
                        Text(note).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("proposalCouncilNote")
                    }
                    if chooses { decisionField }
                    if ProposalPosting.asksDuration(outcome) { durationField }
                    WebsiteOnlyNote(text: ProposalPosting.documentsNote)
                        .fixedSize(horizontal: false, vertical: true)
                    if let failure {
                        Label { Text(failure).font(Font.pw.footnote) } icon: {
                            Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
                        }
                        .foregroundStyle(Color.pwText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("proposalFormError")
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(busy)
            }
            .background(Color.pwGround.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
            }
            // The act rides the foot of the sheet, where a keyboard cannot
            // cover it and a long description cannot push it out of reach.
            .safeAreaInset(edge: .bottom) { foot }
        }
        .interactiveDismissDisabled(busy)
        // Signed out from under the form, there is nobody left to propose as.
        .onChange(of: session.me == nil) { _, gone in if gone { dismiss() } }
    }

    // MARK: The fields

    private var typeField: some View {
        field("Type") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Type", selection: $draft.kind) {
                    ForEach(ProposalPosting.kinds(mayNominate: mayNominate)) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("proposalType")
                Text(draft.kind.detail)
                    .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The member a nomination is about, from the patch's roster: plain
    /// members only, every page of them.
    private var nomineeField: some View {
        field("Nominate for admin", hint: members?.isEmpty == false ? ProposalPosting.nomineeHint(rules) : nil) {
            Group {
                if let members {
                    let people = ProposalPosting.nominatable(members)
                    if people.isEmpty {
                        Text(ProposalPosting.nobodyToNominate)
                            .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                            .accessibilityIdentifier("nobodyToNominate")
                    } else {
                        HStack {
                            Picker("Nominate for admin", selection: $draft.nomineeID) {
                                Text("Choose a member").tag("")
                                ForEach(people, id: \.id) { Text($0.name).tag($0.userId ?? "") }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .tint(Color.pwText)
                            .accessibilityIdentifier("nomineePicker")
                            Spacer(minLength: 0)
                        }
                        .fieldStyle()
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .task { await loadMembers() }
        }
    }

    private func loadMembers() async {
        guard members == nil else { return }
        members = (try? await session.api.electionMembers(slug: slug)) ?? []
    }

    /// The admin's two ways, as rows that tick: each needs its sentence
    /// beside it, which a segmented control has no room for.
    private var decisionField: some View {
        field("How this gets decided") {
            VStack(spacing: 8) {
                ForEach(ProposalPosting.choices(rules), id: \.identifier) { choice in
                    let on = draft.putToVote == choice.putToVote
                    Button { draft.putToVote = choice.putToVote } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(choice.label).font(Font.pw.headline).foregroundStyle(Color.pwText)
                                Text(choice.detail).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(on ? Color.pwAccent : Color.pwTextMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .fieldStyle()
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier(choice.identifier)
                }
            }
        }
    }

    private var durationField: some View {
        field(ProposalPosting.durationLabel(outcome), hint: ProposalPosting.durationHint(rules)) {
            HStack {
                Picker(ProposalPosting.durationLabel(outcome), selection: $draft.durationHours) {
                    ForEach(ProposalPosting.durationChoices(rules), id: \.hours) { Text($0.label).tag($0.hours) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(Color.pwText)
                .accessibilityIdentifier("proposalDuration")
                Spacer(minLength: 0)
            }
            .fieldStyle()
        }
    }

    private func field<Content: View>(_ title: String, hint: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
            content()
            if let hint {
                Text(hint).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var foot: some View {
        Button(action: submit) {
            Text(ProposalPosting.submitLabel(outcome, busy: busy)).font(Font.pw.headline)
                .frame(maxWidth: .infinity, minHeight: 28)
                .foregroundStyle(ready ? Color.pwOnAccent : Color.pwTextMuted)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.pwAccent)
        .controlSize(.large)
        .disabled(!ready)
        .accessibilityIdentifier("proposalFormSubmit")
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func submit() {
        guard !busy else { return }
        failure = nil
        if let problem = ProposalPosting.problem(draft) {
            failure = EventPosting.sentenceCased(problem)
            return
        }
        busy = true
        let body = ProposalBody(draft, rules: rules, isPatchAdmin: isPatchAdmin)
        Task {
            defer { busy = false }
            do {
                let made = try await session.api.propose(slug: slug, body: body)
                onDone(made)
                dismiss()
            } catch APIError.unauthenticated {
                session.signedOut()
            } catch {
                failure = ProposalDetailView.sentence(error, fallback: "Failed to create proposal")
            }
        }
    }
}
