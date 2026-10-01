// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// A patch's noticeboard as a room of the profile (web `PatchNoticeboard`,
// the fourth workspace tab): the board newest first, the line that says who
// reads it, and — for whoever may — the door to put up a notice. There is no
// sort, no filter and no unread mark, because the web has none and the
// decision behind it (ADR 081) is that a board waits for people to walk in.

/// A small fact about a notice, worn on its row and under its title:
/// "members told", "replies off". Muted, because it is not an act.
struct NoticePill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Font.pw.caption2Semibold)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color(.secondarySystemFill), in: Capsule())
            .foregroundStyle(Color.pwTextMuted)
    }
}

struct PatchNoticeboard: View {
    @EnvironmentObject private var session: QuiltSession
    let quilt: Quilt
    let patch: Patch
    var close: (() -> Void)? = nil
    /// The board changed: whoever shows a cut of it is out of date.
    var changed: () -> Void = {}

    @State private var notices: [Notice] = []
    @State private var cursor = ""
    @State private var mayPost = false
    @State private var repliesDefault = true
    @State private var posting = "members"
    @State private var loading = false
    @State private var loaded = false
    @State private var loadingMore = false
    /// The server's 404: this reader is not in the room. It is the same
    /// answer for a patch that does not exist, and it is worded as the
    /// likelier of the two.
    @State private var outside = false
    @State private var error: String?
    @State private var composing = false
    /// A notice just put up, waiting for the form to leave before it opens.
    @State private var putUp: (notice: Notice, line: String)?
    @State private var opened: Opened?
    /// Something on the board changed while a notice was open.
    @State private var stale = false

    private struct Opened: Hashable {
        let notice: Notice
        let line: String?
    }

    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    private var signedIn: Bool { quilt.url == session.quilt.url && session.me != nil }

    var body: some View {
        List {
            // One Group so every section's rows take the card surface: the
            // modifier does not reach them from the List itself.
            Group {
            if loaded && !outside {
                Section {
                    Text(Noticeboard.hint(posting: posting))
                        .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("noticeboardHint")
                }
                if !notices.isEmpty {
                    Section {
                        ForEach(notices) { notice in
                            NavigationLink {
                                NoticeDetailView(quilt: quilt, initial: notice, close: close) { stale = true; changed() }
                            } label: { NoticeRow(notice: notice) }
                            .accessibilityIdentifier("noticeRow")
                        }
                        if !cursor.isEmpty {
                            Button { Task { await loadMore() } } label: {
                                Text(loadingMore ? "Loading…" : "Older notices")
                                    .font(Font.pw.subheadlineMedium).inkAction("arrow.down")
                                    .frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(loadingMore)
                            .accessibilityIdentifier("olderNotices")
                        }
                    }
                }
            }
            if loading && !loaded { ProgressView("Loading the noticeboard…") }
            if let error {
                Section {
                    Text(error).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(.plain)
                        .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
                }
            }
            }.listRows()
        }
        .groundedList()
        .navigationTitle("Noticeboard").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mayPost && !outside {
                ToolbarItem(placement: .bottomBar) {
                    Button { composing = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(Font.pw.subheadlineSemibold)
                            Text("Put up a notice").font(Font.pw.subheadlineSemibold)
                        }
                        .foregroundStyle(Color.pwText)
                    }
                    .accessibilityLabel("Put up a notice")
                    .accessibilityIdentifier("putUpNotice")
                }
            }
            if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
        }
        .overlay {
            if outside {
                ContentUnavailableView {
                    Label(Noticeboard.outsideTitle, systemImage: "lock")
                } description: {
                    Text(Noticeboard.outsideDetail)
                }
                .accessibilityIdentifier("noticeboardOutside")
            } else if loaded && error == nil && notices.isEmpty {
                ContentUnavailableView {
                    Label("Nothing on the board yet.", systemImage: "rectangle.on.rectangle.angled")
                } description: {
                    if mayPost { Text("Put up the first notice.") }
                }
                .accessibilityIdentifier("noticeboardEmpty")
            }
        }
        .navigationDestination(item: $opened) { opened in
            NoticeDetailView(quilt: quilt, initial: opened.notice, note: opened.line, close: close) { stale = true; changed() }
        }
        .sheet(isPresented: $composing, onDismiss: {
            if let putUp {
                opened = Opened(notice: putUp.notice, line: putUp.line)
                self.putUp = nil
            }
        }) {
            NoticeFormSheet(mode: .new(slug: patch.slug, patchName: patch.name), repliesDefault: repliesDefault) { notice, draft in
                putUp = (notice, Noticeboard.putUpLine(toldMembers: draft.tellMembers))
                stale = true
                changed()
            }
        }
        .task { if !loaded { await load() } }
        .onAppear { if stale { stale = false; Task { await load() } } }
        .refreshable { await load() }
        // Whoever is asking changed, so what they may read did.
        .onChange(of: session.me?.id) { _, _ in Task { await load() } }
    }

    private func load() async {
        // Signed out there is nobody to be a member: the server would say
        // 401, and the sentence for it is the same one.
        guard signedIn else { outside = true; loaded = true; return }
        loading = true
        defer { loading = false }
        do {
            let page = try await api.notices(slug: patch.slug)
            notices = page.items
            cursor = page.nextCursor
            mayPost = page.mayPost
            repliesDefault = page.repliesDefault
            posting = page.noticePosting
            outside = false
            error = nil
            loaded = true
        } catch APIError.unauthenticated {
            session.signedOut()
            outside = true
            loaded = true
        } catch {
            guard !Task.isCancelled else { return }
            if (error as? APIError)?.httpStatus == 404 {
                outside = true
                notices = []
                loaded = true
            } else if !loaded || notices.isEmpty {
                self.error = "The noticeboard could not be loaded."
            }
        }
    }

    private func loadMore() async {
        guard !cursor.isEmpty, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await api.notices(slug: patch.slug, after: cursor)
            notices = Noticeboard.appending(page.items, to: notices)
            cursor = page.nextCursor
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "Older notices could not be loaded."
        }
    }
}

/// One notice on the board: its title, who put it up and when, and what it
/// says about replies. No excerpt and no image — the board is a list of
/// headings, and the notice is a tap away.
struct NoticeRow: View {
    let notice: Notice
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(notice.title).font(Font.pw.headline).foregroundStyle(Color.pwText)
                .fixedSize(horizontal: false, vertical: true)
            Text(byline).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
            HStack(spacing: 8) {
                if notice.membersTold { NoticePill(text: "members told") }
                if notice.repliesOpen {
                    Text(Noticeboard.repliesLabel(notice)).font(Font.pw.captionSemibold).foregroundStyle(Color.pwTextMuted)
                } else {
                    NoticePill(text: Noticeboard.repliesLabel(notice))
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
    private var byline: String {
        let when = NotificationTime.ago(notice.createdAt)
        return when.isEmpty ? notice.author : "\(notice.author) · \(when)"
    }
}

// MARK: - The form

/// Putting up a notice, and rewriting one (web `/noticeboard/new`, and the
/// edit form on a notice's own page). One sheet for both, because they are
/// the same four fields; the two switches belong to a new notice only —
/// replies have their own switch on the notice afterwards, and members
/// cannot be told twice.
struct NoticeFormSheet: View {
    enum Mode {
        case new(slug: String, patchName: String)
        case edit(Notice)
    }
    let mode: Mode
    /// The patch's starting position for "Take replies".
    var repliesDefault = true
    /// The notice as the server now holds it, and the draft that made it.
    let onDone: (Notice, NoticeDraft) -> Void

    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NoticeDraft
    @State private var previewing = false
    @State private var busy = false
    @State private var failure: String?

    init(mode: Mode, repliesDefault: Bool = true, onDone: @escaping (Notice, NoticeDraft) -> Void) {
        self.mode = mode
        self.repliesDefault = repliesDefault
        self.onDone = onDone
        switch mode {
        case .new: _draft = State(initialValue: NoticeDraft(repliesOpen: repliesDefault))
        case .edit(let notice): _draft = State(initialValue: NoticeDraft(editing: notice))
        }
    }

    private var isNew: Bool { if case .new = mode { return true } else { return false } }
    private var hasImage: Bool { !draft.imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var ready: Bool { !busy && !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heading
                    field("Title") {
                        TextField("Notice title", text: $draft.title, axis: .vertical)
                            .lineLimit(1...3)
                            .textInputAutocapitalization(.sentences)
                            .fieldStyle()
                            .accessibilityIdentifier("noticeTitle")
                    }
                    field("Notice") {
                        Picker("Notice", selection: $previewing) {
                            Text("Write").tag(false)
                            Text("Preview").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("noticeWritePreview")
                        if previewing { preview } else {
                            TextField("Markdown is supported.", text: $draft.body, axis: .vertical)
                                .lineLimit(6...16)
                                .fieldStyle()
                                .accessibilityIdentifier("noticeBody")
                        }
                    }
                    field("Image address", hint: "Link a flyer or photo you already have online. Patchwork points at it and never keeps a copy.") {
                        TextField(text: $draft.imageURL, prompt: Text(verbatim: "https://…")) { Text("Image address") }
                            .keyboardType(.URL).textContentType(.URL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .fieldStyle()
                            .accessibilityIdentifier("noticeImageURL")
                    }
                    // Asked for only once there is something to describe.
                    if hasImage {
                        field("Describe the image", hint: "Read aloud by screen readers, and shown if the image stops loading.") {
                            TextField("Alt text for the image", text: $draft.imageAlt)
                                .fieldStyle()
                                .accessibilityIdentifier("noticeImageAlt")
                        }
                    }
                    if isNew { switches }
                    if let failure {
                        Label { Text(failure).font(Font.pw.footnote) } icon: {
                            Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
                        }
                        .foregroundStyle(Color.pwText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("noticeFormError")
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.pwGround.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
            }
            // The act rides the foot of the sheet, where a keyboard cannot
            // cover it and a long notice cannot push it out of reach.
            .safeAreaInset(edge: .bottom) { foot }
        }
        .interactiveDismissDisabled(busy)
        // Signed out from under the form, there is nobody left to post as.
        .onChange(of: session.me == nil) { _, gone in if gone { dismiss() } }
    }

    @ViewBuilder private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isNew ? "Put up a notice" : "Edit notice")
                .font(Font.pw.displayTitle2).foregroundStyle(Color.pwText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("noticeFormHeading")
            if case .new(_, let name) = mode {
                Text("For \(name)’s members and admins, and nobody else.")
                    .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var preview: some View {
        let text = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        Group {
            if text.isEmpty {
                Text("Nothing to preview").font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
            } else {
                MarkdownText(source: text, base: session.quilt.url, hardBreaks: true).foregroundStyle(Color.pwText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .padding(12)
        .background(Color.pwSurface, in: RoundedRectangle(cornerRadius: FieldStyle.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FieldStyle.radius, style: .continuous).strokeBorder(Color.pwBorder, lineWidth: 1))
        .accessibilityIdentifier("noticePreview")
    }

    private var switches: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $draft.repliesOpen) { Text("Take replies").font(Font.pw.body) }
                    .tint(Color.pwAccent)
                    .fieldStyle()
                    .accessibilityIdentifier("noticeTakeReplies")
                Text("You or an admin can switch this off later. Existing replies stay.")
                    .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $draft.tellMembers) { Text("Tell members").font(Font.pw.body) }
                    .tint(Color.pwAccent)
                    .fieldStyle()
                    .accessibilityIdentifier("noticeTellMembers")
                Text("Rings the bell for every member of this patch. Off, the notice waits here for people to walk in.")
                    .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            Group {
                if busy { ProgressView().tint(.white) }
                else { Text(isNew ? "Put up notice" : "Save").font(Font.pw.headline) }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .foregroundStyle(ready ? Color.white : Color.pwTextMuted)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.pwAccent)
        .controlSize(.large)
        .disabled(!ready)
        .accessibilityIdentifier("noticeFormSubmit")
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func submit() {
        guard !busy else { return }
        failure = nil
        if let problem = Noticeboard.problem(draft) {
            failure = EventPosting.sentenceCased(problem)
            return
        }
        busy = true
        let sent = draft
        Task {
            defer { busy = false }
            do {
                let notice: Notice
                switch mode {
                case .new(let slug, _): notice = try await session.api.putUp(slug: slug, draft: sent)
                case .edit(let old): notice = try await session.api.editNotice(id: old.id, draft: sent)
                }
                onDone(notice, sent)
                dismiss()
            } catch APIError.unauthenticated {
                session.signedOut()
            } catch {
                failure = ProposalDetailView.sentence(error, fallback: isNew ? "Could not put up the notice." : "Could not save.")
            }
        }
    }
}
