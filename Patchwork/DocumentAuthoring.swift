// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// Changing a governance document (web `AmendmentEditor.svelte`), as a sheet
/// over the document. The web's two steps — edit, then review — are one
/// page here, top to bottom: the text with Write / Preview, what changed
/// (a line count, and the lines themselves a tap away), the summary and the
/// reason, then how it gets decided and for how long, and the act at the
/// foot worded as the outcome. The web keeps an unsaved draft in the
/// browser; a sheet keeps it until it is cancelled, and cancelling a changed
/// text asks first.
struct DocumentAmendmentSheet: View {
    let slug: String
    let document: GovernanceDocument
    let rules: GovernanceRules?
    let isPatchAdmin: Bool
    let onDone: (Proposal) -> Void

    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var title: String
    @State private var why = ""
    @State private var putToVote = false
    @State private var hours: Int
    @State private var showsChanges = false
    @State private var confirmingDiscard = false
    @State private var busy = false
    @State private var failure: String?

    init(slug: String, document: GovernanceDocument, rules: GovernanceRules?, isPatchAdmin: Bool, onDone: @escaping (Proposal) -> Void) {
        self.slug = slug
        self.document = document
        self.rules = rules
        self.isPatchAdmin = isPatchAdmin
        self.onDone = onDone
        _text = State(initialValue: document.body ?? "")
        _title = State(initialValue: DocumentAmending.defaultTitle(document.title))
        _hours = State(initialValue: ProposalPosting.defaultDuration(rules))
    }

    private var original: String { document.body ?? "" }
    private var changedText: Bool { text != original }
    private var chooses: Bool { ProposalPosting.adminChooses(rules, isPatchAdmin: isPatchAdmin) }
    private var outcome: ProposalPosting.Outcome {
        ProposalPosting.outcome(rules: rules, isPatchAdmin: isPatchAdmin, putToVote: chooses && putToVote)
    }
    private var direct: Bool { outcome == .applied }
    private var diff: [LineDiff.Line] { LineDiff.lines(old: original, new: text) }
    private var ready: Bool { !busy && DocumentAmending.problem(title: title, original: original, proposed: text) == nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DocumentAmending.heading(direct: direct))
                            .font(Font.pw.captionSemibold).foregroundStyle(Color.pwTextMuted).textCase(.uppercase)
                        Text(document.title)
                            .font(Font.pw.displayTitle2).foregroundStyle(Color.pwText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("amendHeading")
                        if let version = document.version {
                            Text("Current version: v\(version)").font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                        }
                        if let note = ProposalPosting.outcomeNote(outcome) {
                            Text(note).font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                        }
                    }
                    FormField(title: "The document") {
                        MarkdownComposer(text: $text, title: "The document", placeholder: "The document’s text",
                                         base: session.quilt.url, hardBreaks: false, lines: 10...40,
                                         segmentsID: "amendWritePreview", fieldID: "amendText", previewID: "amendPreview")
                    }
                    changes
                    FormField(title: "Summary of changes") {
                        TextField("e.g. Update conflict resolution process", text: $title, axis: .vertical)
                            .lineLimit(1...3)
                            .textInputAutocapitalization(.sentences)
                            .fieldStyle()
                            .accessibilityIdentifier("amendTitle")
                    }
                    FormField(title: DocumentAmending.whyLabel(direct: direct)) {
                        TextField("Help others understand why this change matters.", text: $why, axis: .vertical)
                            .lineLimit(3...8)
                            .fieldStyle()
                            .accessibilityIdentifier("amendWhy")
                    }
                    if chooses {
                        FormField(title: "How this gets decided") {
                            DecisionChoices(choices: ProposalPosting.choices(rules), putToVote: $putToVote)
                        }
                    }
                    if ProposalPosting.asksDuration(outcome) {
                        FormField(title: ProposalPosting.durationLabel(outcome), hint: ProposalPosting.durationHint(rules)) {
                            VoteWindowPicker(outcome: outcome, rules: rules, hours: $hours)
                        }
                    }
                    if let failure {
                        Label { Text(failure).font(Font.pw.footnote) } icon: {
                            Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
                        }
                        .foregroundStyle(Color.pwText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("amendError")
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if changedText { confirmingDiscard = true } else { dismiss() } }.disabled(busy)
                }
            }
            .safeAreaInset(edge: .bottom) {
                SheetFootButton(title: ProposalPosting.submitLabel(outcome, busy: busy), ready: ready, identifier: "amendSubmit", action: submit)
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(busy || changedText)
        .onChange(of: session.me == nil) { _, gone in if gone { dismiss() } }
    }

    /// What has changed so far, as a count, with the lines themselves a tap
    /// away (the web's "Show diff preview").
    private var changes: some View {
        let lines = diff
        return FormField(title: "Changes") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(LineDiff.summary(lines)).font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwText)
                        .accessibilityIdentifier("amendSummary")
                    Spacer(minLength: 8)
                    if changedText {
                        Button(showsChanges ? "Hide changes" : "Show changes") { withAnimation { showsChanges.toggle() } }
                            .font(Font.pw.subheadlineMedium)
                            .tint(Color.pwText)
                            .tapTarget()
                            .accessibilityIdentifier("amendShowChanges")
                    }
                }
                if showsChanges && changedText { LineDiffList(lines: lines) }
            }
            .fieldStyle()
        }
    }

    private func submit() {
        guard !busy else { return }
        failure = nil
        if let problem = DocumentAmending.problem(title: title, original: original, proposed: text) {
            failure = EventPosting.sentenceCased(problem)
            return
        }
        busy = true
        let body = AmendmentBody(title: title, why: why, targetDoc: document.filename ?? document.title, documentTitle: document.title,
                                 proposed: text, rules: rules, isPatchAdmin: isPatchAdmin, putToVote: putToVote, durationHours: hours)
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

/// The changed lines with a little context, each marked + or −, and the
/// unchanged runs between them folded to a count. Monospaced, as the web's
/// editor is, so a moved word lines up with where it was.
struct LineDiffList: View {
    let lines: [LineDiff.Line]
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(LineDiff.rows(lines).enumerated()), id: \.offset) { _, row in
                switch row {
                case .folded(let count):
                    Text("⋯ \(count) unchanged line\(count == 1 ? "" : "s")")
                        .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                        .padding(.vertical, 2)
                case .line(let line):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(mark(line.kind)).font(.system(.footnote, design: .monospaced).weight(.semibold))
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(.footnote, design: .monospaced))
                            .strikethrough(line.kind == .removed)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(line.kind == .same ? Color.pwTextMuted : Color.pwText)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(fill(line.kind), in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoken(line))
                }
            }
        }
        .accessibilityIdentifier("lineDiff")
    }
    private func mark(_ kind: LineDiff.Kind) -> String {
        switch kind { case .added: return "+"; case .removed: return "−"; case .same: return " " }
    }
    /// The system's green and red, faint: data, as the tally's are.
    private func fill(_ kind: LineDiff.Kind) -> Color {
        switch kind { case .added: return .green.opacity(0.14); case .removed: return .red.opacity(0.12); case .same: return .clear }
    }
    private func spoken(_ line: LineDiff.Line) -> String {
        let text = line.text.isEmpty ? "blank line" : line.text
        switch line.kind { case .added: return "Added: \(text)"; case .removed: return "Removed: \(text)"; case .same: return text }
    }
}

/// What an amendment changes, on its proposal's screen (web `ProposalDetail`
/// Overview and Changes tabs): the document it modifies, the notice that the
/// ground moved where it did, and the lines. A members-only document's text
/// is withheld from a reader outside the room, and said to be.
struct DocumentChangesSection: View {
    let proposal: Proposal
    @State private var showsLines = false
    var body: some View {
        if let current = proposal.currentDocContent, let proposed = proposal.proposedBody {
            let lines = LineDiff.lines(old: current, new: proposed)
            Section {
                if proposal.groundMoved == true { groundMoved }
                VStack(alignment: .leading, spacing: 8) {
                    Text("This \(proposal.isDirectChange ? "change" : "proposal") modifies \(proposal.proposedTitle ?? proposal.targetDoc ?? "a document").")
                        .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(LineDiff.summary(lines)).font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwText)
                        .accessibilityIdentifier("proposalChangesSummary")
                }
                .padding(.vertical, 2)
                Button { withAnimation { showsLines.toggle() } } label: {
                    Text(showsLines ? "Hide changes" : "View changes").font(Font.pw.subheadlineMedium)
                        .tapTarget()
                }
                .buttonStyle(.plain)
                .inkAction(showsLines ? "chevron.up" : "chevron.down")
                .accessibilityIdentifier("proposalViewChanges")
                if showsLines { LineDiffList(lines: lines).padding(.vertical, 4) }
            } header: {
                Text("Changes").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted).textCase(nil)
            }
        } else if proposal.docTextHidden == true {
            Section {
                Text("This proposal modifies a members-only document. The text of the change is visible to members.")
                    .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var groundMoved: some View {
        let on = ProfileDate.day(proposal.groundMovedAt).map { " on \($0)" } ?? ""
        return Text("This document was adopted at a meeting\(on), after this was drafted. The changes below compare against the older text.")
            .font(Font.pw.footnote).foregroundStyle(Color.pwText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A document's versions, newest first (web `GovernanceVersionHistory`):
/// each with its message, who wrote it and when, and the change it made
/// against the one before, opened in place. The web's compare-any-two tool
/// stays on the website.
struct GovernanceVersionHistory: View {
    let quilt: Quilt
    let document: GovernanceDocument
    var close: (() -> Void)? = nil
    @State private var versions: [DocumentVersion] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var open: String?
    @State private var diffs: [String: DocumentDiff] = [:]
    @State private var diffFailed: Set<String> = []
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }

    var body: some View {
        List {
            Group {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.title).font(Font.pw.title2).foregroundStyle(Color.pwText).fixedSize(horizontal: false, vertical: true)
                    if loaded { Text(DocumentHistory.heading(versions.count)).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted) }
                }
                if let rebuilt = DocumentHistory.rebuiltOn(versions) {
                    Text("History rebuilt from the database on \(ProfileDate.day(rebuilt) ?? rebuilt). The current text is intact; versions from before the rebuild are not available.")
                        .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                Section { row(version, index: index) }
            }
            if !loaded && error == nil { ProgressView("Loading history…") }
            if let error {
                Section {
                    Text(error).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    Button("Try again") { Task { await load() } }
                        .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
                }
            }
            }.listRows()
        }
        .groundedList()
        .navigationTitle("History").navigationBarTitleDisplayMode(.inline)
        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
        .overlay {
            if loaded && error == nil && versions.isEmpty {
                ContentUnavailableView("No history yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("This document’s versions are not recorded on this quilt."))
            }
        }
        .task { if !loaded { await load() } }
        .refreshable { await load() }
    }

    @ViewBuilder private func row(_ version: DocumentVersion, index: Int) -> some View {
        let last = index == versions.count - 1
        Button {
            withAnimation { open = open == version.id ? nil : version.id }
            if open == version.id && !last { Task { await loadDiff(index) } }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("v\(version.versionNumber ?? versions.count - index)").font(Font.pw.headline).foregroundStyle(Color.pwText)
                    if index == 0 { Text("current").font(Font.pw.caption2Semibold).foregroundStyle(Color.pwTextMuted) }
                    if let repair = DocumentHistory.repairLabel(version.repair) {
                        Text(repair).font(Font.pw.caption2Semibold).foregroundStyle(Color.pwTextMuted)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 1))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: open == version.id ? "chevron.up" : "chevron.down")
                        .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                }
                Text((version.message ?? "").isEmpty ? "No description" : version.message!)
                    .font(Font.pw.subheadline).foregroundStyle(Color.pwText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text((version.authorName ?? "").isEmpty ? "System" : version.authorName!)
                    if let day = ProfileDate.day(version.date) { Text(day) }
                }
                .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("versionRow")
        if open == version.id { change(version, index: index, last: last) }
    }

    @ViewBuilder private func change(_ version: DocumentVersion, index: Int, last: Bool) -> some View {
        if last {
            Text(version.repair == "rebuilt"
                 ? "This is the oldest version available. It was written from the database when the document’s history was rebuilt, so there is nothing to compare it against."
                 : "This is the initial version.")
                .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
        } else if let diff = diffs[version.id] {
            WordDiffText(hunks: diff.hunks ?? [], unified: diff.unified)
        } else if diffFailed.contains(version.id) {
            Text("Diff not available.").font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
        } else {
            ProgressView()
        }
    }

    private func load() async {
        error = nil
        do {
            versions = try await api.documentVersions(document.id)
            loaded = true
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription; loaded = true }
        }
    }

    private func loadDiff(_ index: Int) async {
        let version = versions[index]
        guard diffs[version.id] == nil, index + 1 < versions.count else { return }
        do { diffs[version.id] = try await api.documentDiff(document.id, from: versions[index + 1].sha, to: version.sha) }
        catch { diffFailed.insert(version.id) }
    }
}

/// The server's word-level hunks as one run of text: insertions on green,
/// deletions struck through on red, the rest as it reads. The unified diff
/// is the fallback where no hunks came.
struct WordDiffText: View {
    let hunks: [DocumentDiff.Hunk]
    let unified: String?
    var body: some View {
        if hunks.isEmpty {
            Text(unified?.isEmpty == false ? unified! : "No changes in this version.")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Color.pwText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(Self.attributed(hunks))
                .font(Font.pw.footnote)
                .foregroundStyle(Color.pwText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("versionDiff")
        }
    }

    static func attributed(_ hunks: [DocumentDiff.Hunk]) -> AttributedString {
        var out = AttributedString()
        for hunk in hunks {
            var piece = AttributedString(hunk.text)
            switch hunk.type {
            case "insert": piece.backgroundColor = .green.opacity(0.2)
            case "delete":
                piece.backgroundColor = .red.opacity(0.16)
                piece.strikethroughStyle = .single
            default: break
            }
            out += piece
        }
        return out
    }
}
