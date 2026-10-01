// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// One notice and its replies (web `NoticeDetail`). The notice is read whole
// — title, who and when, the one image, the body — then the acts this
// reader has over it, then the replies, oldest first, and the box to add
// one while replies are on.
//
// Every right here is the server's answer rather than a guess: `may_edit`
// and `may_manage` arrive with the notice, and the room itself is whoever
// the server does not answer 404. Removing a reply is the one right worked
// out here (its author, or a patch admin), the way the web works it out.

struct NoticeDetailView: View {
    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    let quilt: Quilt
    /// What the row already knew. From a notification it is an id and
    /// nothing else, and the screen reads the rest.
    let initial: Notice
    /// What just happened to bring the reader here: "Notice put up".
    var note: String? = nil
    var close: (() -> Void)? = nil
    /// The board behind this screen is out of date.
    var changed: () -> Void = {}

    @State private var loadedNotice: Notice?
    @State private var slug = ""
    @State private var mayEdit = false
    @State private var mayManage = false
    /// The server's 404: taken down, or a room this reader is not in.
    @State private var gone = false
    @State private var error: String?

    @State private var replies: [NoticeReply] = []
    @State private var repliesLoaded = false
    @State private var replyCursor = ""
    @State private var repliesError: String?
    @State private var loadingMore = false

    @State private var draft = ""
    @State private var replyBusy = false
    @State private var replyFailure: String?
    @State private var manageBusy = false
    @State private var manageFailure: String?
    /// The last act's own sentence, in place of the web's toast.
    @State private var status: String?
    @State private var editing = false
    @State private var confirmingTakeDown = false
    @State private var removing: NoticeReply?
    @State private var reporting: ReportTarget?
    @FocusState private var typing: Bool

    private var notice: Notice { loadedNotice ?? initial }
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    private var meID: String? { quilt.url == session.quilt.url ? session.me?.id : nil }
    private var standing: Standing? { slug.isEmpty ? nil : session.standing(for: slug) }
    private var replyTotal: Int {
        Noticeboard.replyTotal(notice: notice, loaded: replies.count, allLoaded: repliesLoaded && replyCursor.isEmpty)
    }

    var body: some View {
        List {
            // One Group so every section's rows take the card surface.
            Group {
            if gone {
                Section {
                    Label("This notice isn’t on the board. It may have been taken down, or the board is for this patch’s members.",
                          systemImage: "lock")
                        .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("noticeGone")
                }
            } else {
                if let line = status ?? note {
                    Section {
                        Label(line, systemImage: "checkmark.circle")
                            .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("noticeStatus")
                    }
                }
                article
                if let error {
                    Section {
                        Text(error).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                        Button("Try again") { Task { await load() } }
                            .buttonStyle(.plain)
                            .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
                    }
                }
                if loadedNotice != nil {
                    acts
                    thread
                }
            }
            }.listRows()
        }
        .groundedList()
        .navigationTitle("Notice").navigationBarTitleDisplayMode(.inline)
        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog("Take this notice down?", isPresented: $confirmingTakeDown, titleVisibility: .visible) {
            Button("Take it down", role: .destructive) { takeDown() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let line = Noticeboard.takeDownMessage(replies: replyTotal) { Text(line) }
        }
        .confirmationDialog("Remove this reply?", isPresented: removingBinding, titleVisibility: .visible, presenting: removing) { reply in
            Button("Remove", role: .destructive) { remove(reply) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $editing) {
            NoticeFormSheet(mode: .edit(notice)) { updated, _ in
                loadedNotice = updated
                status = "Notice updated"
                changed()
            }
        }
        .sheet(item: $reporting) { ReportSheet(target: $0, api: api) }
        .task { await load(); await loadReplies() }
        .refreshable { await load(); await loadReplies() }
    }

    private var removingBinding: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    // MARK: The notice

    @ViewBuilder private var article: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                if !notice.title.isEmpty {
                    Text(notice.title).font(Font.pw.title2).foregroundStyle(Color.pwText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("noticeTitleText")
                }
                if loadedNotice != nil || !notice.createdAt.isEmpty {
                    Text(byline(author: notice.author, at: notice.createdAt))
                        .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                }
                if notice.membersTold || !notice.repliesOpen {
                    HStack(spacing: 8) {
                        if notice.membersTold { NoticePill(text: "members told") }
                        if !notice.repliesOpen { NoticePill(text: "replies off").accessibilityIdentifier("repliesOffPill") }
                    }
                }
                if loadedNotice == nil && error == nil && notice.title.isEmpty { ProgressView("Loading…") }
            }
            .padding(.vertical, 4)
            if let image = notice.image { picture(image) }
            if !notice.body.isEmpty {
                MarkdownText(source: notice.body, base: quilt.url, hardBreaks: true)
                    .foregroundStyle(Color.pwText)
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
            }
        }
    }

    /// The one image, pointed at rather than kept (web ADR 079's rule,
    /// borrowed by the noticeboard). The description is required where the
    /// address is set, so a host that stops serving the file leaves words.
    private func picture(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel(notice.imageAlt.isEmpty ? "Image" : notice.imageAlt)
            case .empty:
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            default:
                Label(notice.imageAlt.isEmpty ? "An image its host is no longer serving." : notice.imageAlt, systemImage: "photo")
                    .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                    .padding(.vertical, 10)
            }
        }
        .accessibilityIdentifier("noticeImage")
    }

    private func byline(author: String, at stamp: String) -> String {
        let when = NotificationTime.ago(stamp)
        return when.isEmpty ? author : "\(author) · \(when)"
    }

    // MARK: The acts

    @ViewBuilder private var acts: some View {
        let canReport = Noticeboard.canReport(authorId: notice.authorId, me: meID)
        if mayEdit || mayManage || canReport {
            Section {
                if mayEdit {
                    act("Edit", symbol: "pencil", id: "noticeEdit") { editing = true }
                }
                if mayManage {
                    act(notice.repliesOpen ? "Switch replies off" : "Switch replies on",
                        symbol: notice.repliesOpen ? "bubble.left" : "bubble.left.fill", id: "noticeRepliesSwitch") {
                        switchReplies(open: !notice.repliesOpen)
                    }
                    act("Take down", symbol: "trash", id: "noticeTakeDown") { confirmingTakeDown = true }
                }
                if canReport {
                    act("Report", symbol: "flag", id: "noticeReport") {
                        reporting = ReportTarget(kind: .notice, id: notice.id, subject: notice.title)
                    }
                }
                if let manageFailure { refusal(manageFailure, id: "noticeActFailure") }
            }
            .disabled(manageBusy)
        }
    }

    private func act(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Font.pw.subheadlineMedium).inkAction(symbol)
                .frame(minHeight: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func refusal(_ text: String, id: String) -> some View {
        Label { Text(text).font(Font.pw.footnote) } icon: {
            Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
        }
        .foregroundStyle(Color.pwText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier(id)
    }

    // MARK: The replies

    @ViewBuilder private var thread: some View {
        Section {
            if !repliesLoaded && repliesError == nil { ProgressView("Loading replies…") }
            if let repliesError {
                Text(repliesError).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                Button("Try again") { Task { await loadReplies() } }
                    .buttonStyle(.plain)
                    .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
            }
            ForEach(replies) { reply in replyCard(reply) }
            if !replyCursor.isEmpty {
                Button { Task { await loadMoreReplies() } } label: {
                    Text(loadingMore ? "Loading…" : "More replies")
                        .font(Font.pw.subheadlineMedium).inkAction("arrow.down")
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(loadingMore)
                .accessibilityIdentifier("moreReplies")
            }
            if notice.repliesOpen {
                composer
            } else {
                Text(Noticeboard.repliesOffLine)
                    .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    .accessibilityIdentifier("repliesOffLine")
            }
        } header: {
            Text(Noticeboard.repliesHeading(replyTotal))
                .font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
                .textCase(nil)
                .accessibilityIdentifier("repliesHeading")
        }
    }

    private func replyCard(_ reply: NoticeReply) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(reply.author).font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwText)
                Spacer(minLength: 8)
                Text(NotificationTime.ago(reply.createdAt)).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
            }
            MarkdownText(source: reply.body, base: quilt.url, hardBreaks: true)
                .foregroundStyle(Color.pwText)
            let canRemove = Noticeboard.canRemove(reply, me: meID, standing: standing)
            let canReport = Noticeboard.canReport(authorId: reply.authorId, me: meID)
            if canRemove || canReport {
                HStack(spacing: 18) {
                    if canRemove { smallAct("Remove", id: "replyRemove") { removing = reply } }
                    if canReport {
                        smallAct("Report", id: "replyReport") {
                            reporting = ReportTarget(kind: .reply, id: reply.id, subject: "")
                        }
                    }
                    Spacer(minLength: 0)
                }
                .disabled(replyBusy)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("noticeReplyRow")
    }

    private func smallAct(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwText)
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Reply to this notice", text: $draft, axis: .vertical)
                .lineLimit(2...8)
                .fieldStyle()
                .focused($typing)
                .accessibilityIdentifier("noticeReplyField")
            HStack {
                Spacer(minLength: 0)
                Button(action: sendReply) {
                    Text(replyBusy ? "Sending…" : "Reply")
                        .font(Font.pw.subheadlineSemibold)
                        .foregroundStyle(draftReady ? Color.white : Color.pwTextMuted)
                        .frame(minHeight: 30)
                }
                .buttonStyle(.borderedProminent).tint(Color.pwAccent)
                .disabled(!draftReady)
                .accessibilityIdentifier("noticeReplyPost")
            }
            if let replyFailure { refusal(replyFailure, id: "noticeReplyFailure") }
        }
        .padding(.vertical, 4)
    }

    private var draftReady: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !replyBusy }

    // MARK: Writes

    /// The web's rule: nothing is drawn before the server has answered, and
    /// what it answered is what is drawn.
    private func sendReply() {
        guard draftReady else { return }
        if let problem = Noticeboard.replyProblem(draft) {
            replyFailure = EventPosting.sentenceCased(problem)
            return
        }
        replyBusy = true
        replyFailure = nil
        let text = draft
        Task {
            defer { replyBusy = false }
            do {
                let reply = try await api.reply(notice: notice.id, body: text)
                replies = Noticeboard.appending([reply], to: replies)
                bumpCount(1)
                draft = ""
                typing = false
                changed()
            } catch APIError.unauthenticated {
                session.signedOut()
            } catch {
                replyFailure = ProposalDetailView.sentence(error, fallback: "Could not reply.")
                // "Replies are off" is news about the notice, not the reply.
                await load()
            }
        }
    }

    private func remove(_ reply: NoticeReply) {
        removing = nil
        guard !replyBusy else { return }
        replyBusy = true
        replyFailure = nil
        Task {
            defer { replyBusy = false }
            do {
                try await api.removeReply(id: reply.id)
                replies.removeAll { $0.id == reply.id }
                bumpCount(-1)
                changed()
            } catch APIError.unauthenticated {
                session.signedOut()
            } catch {
                replyFailure = ProposalDetailView.sentence(error, fallback: "Could not remove the reply.")
                await loadReplies()
            }
        }
    }

    private func bumpCount(_ by: Int) {
        guard var current = loadedNotice else { return }
        current.replyCount = max(0, current.replyCount + by)
        loadedNotice = current
    }

    private func switchReplies(open: Bool) {
        manage(fallback: "Could not change replies.") {
            let updated = try await api.setReplies(notice: notice.id, open: open)
            loadedNotice = updated
            status = Noticeboard.repliesSwitchLine(open: updated.repliesOpen)
        }
    }

    private func takeDown() {
        manage(fallback: "Could not take the notice down.") {
            try await api.takeDown(notice: notice.id)
            dismiss()
        }
    }

    private func manage(fallback: String, _ act: @escaping () async throws -> Void) {
        guard !manageBusy else { return }
        manageBusy = true
        manageFailure = nil
        Task {
            defer { manageBusy = false }
            do {
                try await act()
                changed()
            } catch APIError.unauthenticated {
                session.signedOut()
            } catch {
                manageFailure = ProposalDetailView.sentence(error, fallback: fallback)
            }
        }
    }

    // MARK: Reads

    private func load() async {
        do {
            let answer = try await api.notice(id: initial.id)
            loadedNotice = answer.notice
            slug = answer.nodeSlug
            mayEdit = answer.mayEdit
            mayManage = answer.mayManage
            gone = false
            error = nil
        } catch APIError.unauthenticated {
            session.signedOut()
            gone = true
        } catch {
            guard !Task.isCancelled else { return }
            if (error as? APIError)?.httpStatus == 404 { gone = true }
            else if loadedNotice == nil { self.error = "This notice could not be loaded." }
        }
    }

    private func loadReplies() async {
        guard !gone else { return }
        do {
            let page = try await api.replies(notice: initial.id)
            replies = page.items
            replyCursor = page.nextCursor
            repliesLoaded = true
            repliesError = nil
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            guard !Task.isCancelled else { return }
            if (error as? APIError)?.httpStatus == 404 { gone = true }
            else if !repliesLoaded { repliesError = "The replies could not be loaded." }
        }
    }

    private func loadMoreReplies() async {
        guard !replyCursor.isEmpty, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await api.replies(notice: initial.id, after: replyCursor)
            replies = Noticeboard.appending(page.items, to: replies)
            replyCursor = page.nextCursor
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            guard !Task.isCancelled else { return }
            replyFailure = "More replies could not be loaded."
        }
    }
}

// MARK: - Reporting

/// What is being reported: a notice by its title, or a reply.
struct ReportTarget: Identifiable, Hashable {
    let kind: ReportBody.Kind
    let id: String
    /// The notice's title. A reply has none, and is called "this reply".
    let subject: String
    var heading: String { kind == .notice ? "Report this notice" : "Report this reply" }
    var named: String {
        let title = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return kind == .notice && !title.isEmpty ? "“\(title)”" : (kind == .notice ? "this notice" : "this reply")
    }
}

/// The web's report dialog as a sheet: a reason from its list, room to say
/// more, and where the report goes — which, for this room, is the patch's
/// own admins.
struct ReportSheet: View {
    let target: ReportTarget
    let api: PatchworkAPI

    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    @State private var reason = Noticeboard.reportReasons[0]
    @State private var details = ""
    @State private var busy = false
    @State private var failure: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if sent {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Report submitted", systemImage: "checkmark.circle")
                                .font(Font.pw.title3).foregroundStyle(Color.pwText)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("reportSentHeading")
                            Text("An admin will review it.")
                                .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                        }
                        .cardSurface()
                    } else {
                        form
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.pwGround.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                if !sent { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
            }
            .safeAreaInset(edge: .bottom) { foot }
        }
        .interactiveDismissDisabled(busy)
    }

    @ViewBuilder private var form: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(target.heading)
                .font(Font.pw.displayTitle2).foregroundStyle(Color.pwText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("reportHeading")
            Text("\(Noticeboard.reportDestination) You’re reporting \(target.named).")
                .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Reason").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
            // A menu wearing the field's clothes: a stock picker's label is
            // set in the system face, which no other word on this sheet is.
            Menu {
                Picker("Reason", selection: $reason) {
                    ForEach(Noticeboard.reportReasons, id: \.self) { Text($0).tag($0) }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(reason).font(Font.pw.body).foregroundStyle(Color.pwText)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Color.pwTextMuted)
                        .accessibilityHidden(true)
                }
                .fieldStyle()
            }
            .accessibilityLabel("Reason")
            .accessibilityValue(reason)
            .accessibilityIdentifier("reportReason")
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Details (optional)").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
            TextField("Anything that helps an admin understand what happened.", text: $details, axis: .vertical)
                .lineLimit(3...8)
                .fieldStyle()
                .accessibilityIdentifier("reportDetails")
        }
        if let failure {
            Label { Text(failure).font(Font.pw.footnote) } icon: {
                Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
            }
            .foregroundStyle(Color.pwText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("reportFailure")
        }
    }

    private var foot: some View {
        Button {
            if sent { dismiss() } else { submit() }
        } label: {
            Group {
                if busy { ProgressView().tint(.white) }
                else { Text(sent ? "Done" : "Submit report").font(Font.pw.headline) }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .foregroundStyle(busy ? Color.pwTextMuted : Color.white)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.pwAccent)
        .controlSize(.large)
        .disabled(busy)
        .accessibilityIdentifier(sent ? "reportDone" : "reportSubmit")
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func submit() {
        guard !busy else { return }
        busy = true
        failure = nil
        Task {
            defer { busy = false }
            do {
                try await api.report(target.kind, id: target.id, reason: reason, details: details)
                withAnimation { sent = true }
            } catch APIError.unauthenticated {
                session.signedOut()
                dismiss()
            } catch {
                failure = ProposalDetailView.sentence(error, fallback: "Could not submit report.")
            }
        }
    }
}
