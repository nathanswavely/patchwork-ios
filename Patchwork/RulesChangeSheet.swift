// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// Changing the rules (web `RulesProposalEditor.svelte`), as a sheet over
/// the Governance room: the rules the web's editor lets a member propose
/// changing, each as its native control set to what is in force; what moved,
/// current → proposed, as it moves; the summary and the reason; how it gets
/// decided; and, before the act, a sentence saying what pressing it does.
/// The web's two steps — edit, then review — are one page, and its saved
/// draft is the open sheet, which asks before a changed draft is thrown away.
struct RulesChangeSheet: View {
    let slug: String
    let isPatchAdmin: Bool
    let onDone: (Proposal) -> Void

    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    @State private var current: RulesDocument?
    @State private var initial = RulesChange.Draft()
    @State private var draft = RulesChange.Draft()
    @State private var electorate: RulesChange.Electorate?
    @State private var loadError: String?
    @State private var title = ""
    /// The summary follows what moved until somebody writes their own.
    @State private var titleEdited = false
    @State private var why = ""
    @State private var putToVote = false
    @State private var hours = 72
    @State private var confirmingDiscard = false
    @State private var busy = false
    @State private var failure: String?

    private var rules: GovernanceRules? { current?.governanceRules }
    private var chooses: Bool { ProposalPosting.adminChooses(rules, isPatchAdmin: isPatchAdmin, rulesDoc: true) }
    private var outcome: ProposalPosting.Outcome {
        ProposalPosting.outcome(rules: rules, isPatchAdmin: isPatchAdmin, putToVote: chooses && putToVote, rulesDoc: true)
    }
    private var direct: Bool { outcome == .applied }
    private var proposed: RulesDocument? { current.map { draft.applied(to: $0) } }
    private var changed: Bool { draft != initial }
    private var ready: Bool { !busy && changed && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(direct ? "Changing" : "Proposing changes to")
                                .font(Font.pw.captionSemibold).foregroundStyle(Color.pwTextMuted).textCase(.uppercase)
                            Text("Governance Rules").font(Font.pw.displayTitle2).foregroundStyle(Color.pwText)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("rulesHeading")
                        }
                        .padding(.vertical, 4)
                    }
                    if current != nil { fields } else if let loadError {
                        Section {
                            Text(loadError).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                            Button("Try again") { Task { await load() } }
                                .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
                        }
                    } else {
                        Section { ProgressView("Loading rules…") }
                    }
                }
                .listRowBackground(Color.pwSurface)
            }
            .scrollContentBackground(.hidden)
            .background(Color.pwGround.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .disabled(busy)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if changed { confirmingDiscard = true } else { dismiss() } }.disabled(busy)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if current != nil {
                    SheetFootButton(title: ProposalPosting.submitLabel(outcome, busy: busy), ready: ready, identifier: "rulesSubmit", action: submit)
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(busy || changed)
        .task { if current == nil { await load() } }
        .onChange(of: draft) { _, _ in retitle() }
        .onChange(of: session.me == nil) { _, gone in if gone { dismiss() } }
    }

    // MARK: The rules

    @ViewBuilder private var fields: some View {
        Section {
            menu("Decision Method", selection: $draft.decisionMethod, options: RulesChange.decisionOptions, id: "rulesDecisionMethod",
                 hint: RulesChange.decisionHints[draft.decisionMethod])
            if !draft.adminDecides {
                VStack(alignment: .leading, spacing: 4) {
                    Stepper(value: $draft.quorumPercent, in: 0...100, step: 5) {
                        Text("Quorum: \(draft.quorumPercent)%").font(Font.pw.body)
                    }
                    .accessibilityIdentifier("rulesQuorum")
                    hintText(RulesChange.quorumHint(electorate, quorum: draft.quorumPercent, tenureDays: draft.tenureDays))
                }
                Picker("Default Voting Period", selection: $draft.periodHours) {
                    ForEach(RulesChange.periodChoices(draft.periodHours), id: \.hours) { Text($0.label).tag($0.hours) }
                }
                .accessibilityIdentifier("rulesPeriod")
                menu("Amendment Threshold", selection: $draft.amendmentThreshold, options: RulesChange.thresholdOptions, id: "rulesThreshold")
                Toggle("Auto-Apply Amendments", isOn: $draft.autoApply).accessibilityIdentifier("rulesAutoApply")
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("People don’t vote on proposals about themselves", isOn: $draft.subjectRecusal)
                        .accessibilityIdentifier("rulesRecusal")
                    if draft.subjectRecusal { hintText(RulesChange.recusalHint) }
                }
            }
        } header: { heading("How proposals are decided") }
        Section {
            menu("Where admins are chosen", selection: $draft.leadershipVenue, options: RulesChange.venueOptions, id: "rulesLeadershipVenue",
                 hint: draft.leadershipVenue == "elsewhere" ? RulesChange.leadershipVenueHint : nil)
            menu("Where proposals are decided", selection: $draft.proposalVenue, options: RulesChange.venueOptions, id: "rulesProposalVenue",
                 hint: draft.proposalVenue == "elsewhere" ? RulesChange.proposalVenueHint : nil)
        } header: { heading("Where things are decided") }
        Section {
            let succession = RulesChange.successionChoices(draft.successionPolicy)
            menu("Succession Policy", selection: $draft.successionPolicy, options: succession, id: "rulesSuccession",
                 hint: succession.first { $0.value == draft.successionPolicy }?.hint)
            if !draft.adminDecides {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Minimum Voting Tenure", selection: $draft.tenureDays) {
                        ForEach(RulesChange.tenureChoices(draft.tenureDays), id: \.days) { Text($0.label).tag($0.days) }
                    }
                    .accessibilityIdentifier("rulesTenure")
                    hintText(RulesChange.tenureHint(electorate, tenureDays: draft.tenureDays))
                }
            }
            menu("Membership Policy", selection: $draft.membershipPolicy, options: RulesChange.membershipOptions, id: "rulesMembership")
        } header: { heading("Leadership and membership") }
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Events", isOn: $draft.followerEvents)
                hintText(RulesChange.followerEventsHint)
            }
            Toggle("Proposals", isOn: $draft.followerProposals)
            Toggle("Charters", isOn: $draft.followerCharters)
            Toggle("Members", isOn: $draft.followerMembers)
        } header: { heading("Follower Permissions") }
        changes
        Section {
            FormField(title: "Summary of changes") {
                TextField("Update governance rules", text: titleBinding, axis: .vertical)
                    .lineLimit(1...3)
                    .accessibilityIdentifier("rulesTitle")
            }
            FormField(title: DocumentAmending.whyLabel(direct: direct)) {
                TextField("Help others understand why this change matters.", text: $why, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityIdentifier("rulesWhy")
            }
        } header: { heading(direct ? "Describe this change" : "Describe your proposal") }
        if chooses {
            Section {
                DecisionChoices(choices: ProposalPosting.choices(rules), putToVote: $putToVote)
            } header: { heading("How this gets decided") }
        }
        if ProposalPosting.asksDuration(outcome) {
            Section {
                VoteWindowPicker(outcome: outcome, rules: rules, hours: $hours)
            } header: { heading(ProposalPosting.durationLabel(outcome)) } footer: {
                Text(ProposalPosting.durationHint(rules))
            }
        }
        Section {
            Text(RulesChange.consequence(outcome, hours: hours))
                .font(Font.pw.subheadline).foregroundStyle(Color.pwText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("rulesConsequence")
            if let failure {
                Label { Text(failure).font(Font.pw.footnote) } icon: {
                    Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
                }
                .foregroundStyle(Color.pwText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("rulesError")
            }
        }
    }

    /// Current → proposed, for every key that moved (web
    /// `StructuredRulesDiff`).
    @ViewBuilder private var changes: some View {
        if let current, let proposed {
            let diff = RulesChange.diff(current: current, proposed: proposed)
            Section {
                if !changed || diff.rows.isEmpty {
                    Text("No changes to governance rules.").font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                } else {
                    RulesDiffRows(rows: diff.rows)
                    if diff.unchanged > 0 {
                        Text(RulesChange.unchangedLine(diff.unchanged)).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                    }
                }
            } header: { heading("Changes") }
        }
    }

    private var titleBinding: Binding<String> {
        Binding(get: { title }, set: { title = $0; titleEdited = true })
    }

    private func retitle() {
        guard !titleEdited, let current, let proposed else { return }
        title = changed ? RulesChange.title(current: current, proposed: proposed) : ""
    }

    private func menu(_ label: String, selection: Binding<String>, options: [RulesChange.Option], id: String, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(label, selection: selection) {
                ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
            }
            .accessibilityIdentifier(id)
            hintText(hint)
        }
    }

    @ViewBuilder private func hintText(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            Text(text).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted).textCase(nil)
    }

    // MARK: Reads and the write

    private func load() async {
        loadError = nil
        do {
            let document = try await session.api.governanceRules(slug: slug)
            current = document
            initial = RulesChange.Draft(document)
            draft = initial
            hours = ProposalPosting.defaultDuration(document.governanceRules)
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            if !Task.isCancelled { loadError = ProposalDetailView.sentence(error, fallback: "Failed to load rules") }
        }
        // Best effort, and never fatal: the form works without the sentences.
        electorate = try? await session.api.electorate(slug: slug)
    }

    private func submit() {
        guard !busy, let proposed else { return }
        failure = nil
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            failure = "Title is required"
            return
        }
        busy = true
        let body = AmendmentBody(title: title, why: why, targetDoc: DocumentAmending.rulesFile, documentTitle: "Governance Rules",
                                 proposed: proposed.text(), rules: rules, isPatchAdmin: isPatchAdmin, putToVote: putToVote, durationHours: hours)
        Task {
            defer { busy = false }
            do {
                let made = try await session.api.propose(slug: slug, amendment: body)
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

/// Each moved rule: its name, then what it was struck through and what it
/// becomes.
struct RulesDiffRows: View {
    let rows: [RulesChange.DiffRow]
    var body: some View {
        ForEach(rows) { row in
            VStack(alignment: .leading, spacing: 3) {
                Text(row.label).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.from).strikethrough().foregroundStyle(Color.pwTextMuted)
                    Image(systemName: "arrow.right").font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                        .accessibilityHidden(true)
                    Text(row.to).foregroundStyle(Color.pwText)
                }
                .font(Font.pw.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(row.label): \(row.from), becomes \(row.to)")
            .accessibilityIdentifier("rulesDiffRow-\(row.key)")
        }
    }
}

/// A rules change on its proposal's screen: the same rows, from the two
/// files the payload carries.
struct RulesChangesSection: View {
    let proposal: Proposal
    var body: some View {
        if let currentText = proposal.currentDocContent, let proposedText = proposal.proposedBody,
           let current = RulesDocument(json: currentText), let proposed = RulesDocument(json: proposedText) {
            let diff = RulesChange.diff(current: current, proposed: proposed)
            Section {
                if diff.rows.isEmpty {
                    Text("No changes to governance rules.").font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                } else {
                    RulesDiffRows(rows: diff.rows)
                    if diff.unchanged > 0 {
                        Text(RulesChange.unchangedLine(diff.unchanged)).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                    }
                }
            } header: {
                Text("Proposed rule changes").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted).textCase(nil)
            }
        }
    }
}
