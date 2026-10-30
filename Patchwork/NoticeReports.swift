// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// The noticeboard as its admins keep it (web `PatchSettingsNoticeboard`,
// ADR 081): the report queue, and the board's two settings. Both are doors
// from the board itself, drawn only for the patch's own admin — the queue
// quotes the room, and the server answers anybody else, a quilt admin with
// no role here among them, 404.

/// The queue, a tab per state as the web keeps it: what is waiting, and what
/// was resolved or dismissed with the note it was left with.
struct NoticeReportsView: View {
    @EnvironmentObject private var session: QuiltSession
    let slug: String
    var close: (() -> Void)? = nil

    @State private var tab = NoticeReports.Status.pending
    @State private var reports: [NoticeReport] = []
    @State private var cursor = ""
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    @State private var outcome: AdminOutcome?
    @State private var reviewing: NoticeReport?
    @State private var opened: Notice?

    private var runs: Bool { PatchAdmin.runs(session.standing(for: slug)) }

    var body: some View {
        List {
            Group {
                if !runs {
                    Section { WebsiteOnlyNote(text: "Only this patch’s admins read its reports.") }
                } else {
                    Section {
                        Picker("Reports", selection: $tab) {
                            ForEach(NoticeReports.Status.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("reportTabs")
                    } footer: {
                        Text(NoticeReports.intro).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted).textCase(nil)
                    }
                    if let outcome { Section { AdminOutcomeLine(outcome: outcome, id: "reportsOutcome") } }
                    if !reports.isEmpty {
                        Section {
                            ForEach(reports) { row($0) }
                            if !cursor.isEmpty {
                                Button { Task { await load(after: cursor) } } label: {
                                    Text("Load more").font(Font.pw.subheadlineMedium).inkAction("arrow.down.circle")
                                }
                                .buttonStyle(.borderless)
                                .disabled(loading)
                                .accessibilityIdentifier("reportsMore")
                            }
                        }
                    }
                    if let error {
                        Section {
                            Text(error).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                            Button("Try again") { Task { await load() } }
                                .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
                        }
                    }
                }
            }
            .listRows()
        }
        .groundedList()
        .navigationTitle("Reports").navigationBarTitleDisplayMode(.inline)
        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
        .overlay {
            if runs && loaded && !loading && error == nil && reports.isEmpty {
                ContentUnavailableView(tab.empty, systemImage: "flag")
                    .accessibilityIdentifier("reportsEmpty")
            } else if runs && !loaded {
                ProgressView()
            }
        }
        .sheet(item: $reviewing) { report in
            ReviewReportSheet(report: report) { action, note in Task { await act(action, note: note, on: report) } }
        }
        .navigationDestination(item: $opened) { NoticeDetailView(quilt: session.quilt, initial: $0, close: close) }
        .task { if !loaded { await load() } }
        .onChange(of: tab) { _, _ in outcome = nil; Task { await load() } }
        .refreshable { await load() }
    }

    private func row(_ report: NoticeReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NoticeReports.head(report)).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
            if report.gone || report.noticeId.isEmpty {
                Text(report.gone ? NoticeReports.gone : report.target)
                    .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
            } else {
                // What was reported, as a door to the notice it is on.
                Button { opened = Notice(id: report.noticeId) } label: {
                    Text(report.target).font(Font.pw.headline).multilineTextAlignment(.leading).lineLimit(4)
                        .inkRow(fills: false).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Opens the notice")
                .accessibilityIdentifier("reportOpen-\(report.id)")
            }
            Text(report.reason).font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwText)
                .accessibilityIdentifier("reportReason-\(report.id)")
            if !report.details.isEmpty {
                Text(report.details).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if report.status == "pending" {
                Button { reviewing = report } label: {
                    Text("Review").font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwOnAccent).frame(minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.pwAccent)
                .padding(.top, 2)
                .accessibilityLabel("Review the report about \(report.target)")
                .accessibilityIdentifier("reportReview-\(report.id)")
            } else if !report.resolutionNote.isEmpty {
                Text("Note: \(report.resolutionNote)").font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private func load(after: String? = nil) async {
        guard runs else { loaded = true; return }
        loading = true; error = nil
        defer { loading = false; loaded = true }
        let asked = tab
        do {
            let page = try await session.api.noticeReports(slug: slug, status: asked, after: after)
            guard asked == tab else { return }
            if after == nil { reports = page.items } else {
                let known = Set(reports.map(\.id))
                reports += page.items.filter { !known.contains($0.id) }
            }
            cursor = page.nextCursor
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    /// Off the queue at once; back where it was, with the quilt's sentence,
    /// if the quilt says no — "this report has already been reviewed" when
    /// another admin got there first.
    private func act(_ action: NoticeReports.Action, note: String, on report: NoticeReport) async {
        guard let index = reports.firstIndex(of: report) else { return }
        withAnimation { _ = reports.remove(at: index) }
        outcome = nil
        do {
            try await session.api.actOnReport(slug: slug, id: report.id, action, note: note)
            outcome = AdminOutcome(text: NoticeReports.done)
            UIAccessibility.post(notification: .announcement, argument: NoticeReports.done)
            session.adminChanged()
        } catch {
            if case APIError.unauthenticated = error { session.signedOut() }
            withAnimation { reports.insert(report, at: min(index, reports.count)) }
            outcome = AdminOutcome(text: ProposalDetailView.sentence(error, fallback: NoticeReports.failed), refused: true)
        }
    }
}

/// The web's inline review form as a sheet: what was reported, the three
/// things that can be done about it with what each one does, and the note.
/// Removing asks once more, because it cannot be undone.
struct ReviewReportSheet: View {
    let report: NoticeReport
    let decide: (NoticeReports.Action, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var action = NoticeReports.Action.dismiss
    @State private var note = ""
    @State private var confirmingRemoval = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Review this report")
                            .font(Font.pw.displayTitle2).foregroundStyle(Color.pwText)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("reviewReportHeading")
                        Text(report.gone ? NoticeReports.gone : "“\(report.target)”")
                            .font(Font.pw.body).foregroundStyle(Color.pwText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(report.reason) · \(NoticeReports.head(report))")
                            .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Action").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(NoticeReports.actions(for: report)) { option in
                            ChoiceCard(title: option.title(report.thing), detail: option.consequence(report.thing),
                                       selected: action == option, identifier: "reportAction-\(option.rawValue)") { action = option }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Note").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
                            .accessibilityAddTraits(.isHeader)
                        TextField("Optional", text: $note, axis: .vertical)
                            .lineLimit(2...5)
                            .fieldStyle()
                            .accessibilityLabel("Note")
                            .accessibilityIdentifier("reportNote")
                        Text("Kept with the report for this patch’s admins. Whoever reported it is not shown it.")
                            .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.pwGround.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button(role: action.destructive ? .destructive : nil) {
                    if action.destructive { confirmingRemoval = true } else { finish() }
                } label: {
                    Text("Confirm").font(Font.pw.headline).frame(maxWidth: .infinity, minHeight: 28)
                        .foregroundStyle(Color.pwOnAccent)
                }
                .buttonStyle(.borderedProminent)
                .tint(action.destructive ? Color.pwDestructive : Color.pwAccent)
                .controlSize(.large)
                .accessibilityIdentifier("reportConfirm")
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .confirmationDialog("Are you sure?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button("Yes, remove it", role: .destructive) { finish() }
                    .accessibilityIdentifier("reportConfirmRemoval")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(NoticeReports.Action.remove.consequence(report.thing))
            }
        }
    }

    private func finish() {
        decide(action, note)
        dismiss()
    }
}

/// The board's two settings, each saved the moment it is changed, as the
/// web's controls are; a refusal puts the control back and says why.
struct NoticeboardSettingsView: View {
    @EnvironmentObject private var session: QuiltSession
    let slug: String
    @State var posting: NoticeboardSettings.Posting
    @State var repliesDefault: Bool
    var close: (() -> Void)? = nil
    @State private var outcome: AdminOutcome?
    /// What the controls held when last saved, to go back to on a refusal
    /// without the change handlers sending it again.
    @State private var savedPosting: NoticeboardSettings.Posting?
    @State private var savedReplies: Bool?
    @State private var reverting = false

    private var runs: Bool { PatchAdmin.runs(session.standing(for: slug)) }

    var body: some View {
        List {
            Group {
                if !runs {
                    Section { WebsiteOnlyNote(text: "Only this patch’s admins change its noticeboard.") }
                } else {
                    Section {
                        Picker("Who puts up notices", selection: $posting) {
                            ForEach(NoticeboardSettings.Posting.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("noticePosting")
                    } header: {
                        Text("Who puts up notices").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted).textCase(nil)
                    } footer: {
                        Text(NoticeboardSettings.postingDetail).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    }
                    Section {
                        Toggle("New notices take replies", isOn: $repliesDefault)
                            .font(Font.pw.body)
                            .tint(Color.pwAccent)
                            .accessibilityIdentifier("noticeRepliesDefault")
                    } footer: {
                        Text(NoticeboardSettings.repliesDetail).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    }
                    if let outcome { Section { AdminOutcomeLine(outcome: outcome, id: "noticeSettingsOutcome") } }
                }
            }
            .listRows()
        }
        .groundedList()
        .navigationTitle("Noticeboard settings").navigationBarTitleDisplayMode(.inline)
        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
        .onAppear { if savedPosting == nil { savedPosting = posting; savedReplies = repliesDefault } }
        .onChange(of: posting) { _, now in
            guard !reverting else { reverting = false; return }
            Task { await save(NoticeboardSettings.body(posting: now), done: NoticeboardSettings.saved(posting: now)) }
        }
        .onChange(of: repliesDefault) { _, now in
            guard !reverting else { reverting = false; return }
            Task { await save(NoticeboardSettings.body(repliesDefault: now), done: NoticeboardSettings.saved(repliesDefault: now)) }
        }
    }

    private func save(_ body: NoticeboardSettings.Body, done: String) async {
        outcome = nil
        do {
            try await session.api.saveNoticeboardSettings(slug: slug, body)
            savedPosting = posting
            savedReplies = repliesDefault
            outcome = AdminOutcome(text: done)
            UIAccessibility.post(notification: .announcement, argument: done)
            session.adminChanged()
        } catch {
            if case APIError.unauthenticated = error { session.signedOut() }
            reverting = true
            if body.noticePosting != nil, let savedPosting { posting = savedPosting }
            if body.noticeRepliesDefault != nil, let savedReplies { repliesDefault = savedReplies }
            outcome = AdminOutcome(text: ProposalDetailView.sentence(error, fallback: "Failed to save"), refused: true)
        }
    }
}
