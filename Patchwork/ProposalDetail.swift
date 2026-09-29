// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// One proposal, and everything a member does with it: the status banner,
/// what it proposes, the vote (or an election's ballot), and the discussion.
///
/// The web splits this into tabs; a phone reads it top to bottom as cards on
/// the ground, with the decision within reach — the three buttons are in the
/// vote card, and once that card has scrolled away they ride a bar at the
/// foot, the web's sticky vote bar. Creating, withdrawing, deciding and
/// applying a proposal, its revisions and the amendment's diff stay the
/// website's, and nothing stands in for them here.
///
/// Who sees what is the server's answer (`can_vote`) plus the reader's
/// standing on the patch from the membership index. Nothing authenticated
/// is drawn without a session, and a reader who is not signed in to this
/// quilt is offered only the sign-in sheet.
struct ProposalDetailView: View {
    @EnvironmentObject private var session: QuiltSession
    let quilt: Quilt
    let initial: Proposal
    var close: (() -> Void)? = nil

    @State private var detail: Proposal?
    @State private var error: String?
    /// A closed record read from outside the room: the server answers 404.
    @State private var notPublic = false
    @State private var comments: [ProposalComment]?
    @State private var commentsError: String?
    /// The patch's `follower_permissions`, read only for a follower, whose
    /// composer depends on it.
    @State private var followerPermissions: FollowerPermissions?
    @State private var permissionsRead = false

    @State private var voteBusy = false
    @State private var voteFailure: String?
    /// Where the vote card's buttons are, and where the list is, in the
    /// window. The bar at the foot stands in for the buttons while they are
    /// not on screen.
    @State private var buttonsFrame: CGRect?
    @State private var listFrame: CGRect = .zero
    @State private var showVoters = false
    @State private var signingIn = false

    // The discussion's own state: one composer, one inline reply or edit at
    // a time, and one comment waiting on its confirmation.
    @State private var draft = ""
    @State private var replyingTo: String?
    @State private var replyText = ""
    @State private var editing: String?
    @State private var editText = ""
    @State private var commentBusy = false
    @State private var commentFailure: String?
    @State private var deleting: ProposalComment?
    @State private var reacting: Set<String> = []
    /// Which of the discussion's fields has the keyboard. The bar steps
    /// aside while one does: over a keyboard it would cover what is typed.
    @FocusState private var typing: String?

    private var proposal: Proposal { detail ?? initial }
    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }

    // MARK: Who the reader is here

    /// The quilt this proposal is on is the one the reader is signed in to.
    /// A proposal read from anywhere else takes no act from here.
    private var sameQuilt: Bool { quilt.url == session.quilt.url }
    private var acting: Bool { sameQuilt && session.me != nil }
    private var meID: String? { acting ? session.me?.id : nil }
    private var isInstanceAdmin: Bool { acting && session.me?.role == "admin" }
    private var membership: Membership? {
        guard acting, let node = proposal.nodeId, !node.isEmpty else { return nil }
        return session.memberships.first { $0.nodeId == node }
    }
    private var standing: Standing? { membership?.standing }
    private var slug: String? {
        if let slug = membership?.nodeSlug, !slug.isEmpty { return slug }
        guard let node = proposal.nodeId else { return nil }
        return (session.wholeQuilt + session.patches).first { $0.id == node }?.slug
    }
    /// Standing to comment and react. A follower's waits for the patch's own
    /// switch to be read, so a composer never appears and then vanishes.
    private var canDiscuss: Bool {
        guard acting else { return false }
        if standing == .active(.follower) && !permissionsRead { return false }
        return Discussion.canDiscuss(standing: standing, followerPermissions: followerPermissions, isInstanceAdmin: isInstanceAdmin)
    }
    private var canNominate: Bool { acting && EventPosting.isMemberOrAdmin(standing) }

    // MARK: The screen

    var body: some View {
        List {
            // One Group so every section's rows take the card surface: the
            // modifier does not reach them from the List itself.
            Group {
            if notPublic && detail == nil {
                Section {
                    Label("Proposals and decisions here are not public.", systemImage: "lock")
                        .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                        .accessibilityIdentifier("proposalNotPublic")
                }
            } else {
                if let banner = VoteRules.banner(proposal) {
                    Section {
                        Text(banner)
                            .font(Font.pw.body).foregroundStyle(Color.pwText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("proposalBanner")
                    }
                }
                header
                if let body = proposal.body, !body.isEmpty {
                    Section { DocumentBody(text: body) } header: { heading("Why this change") }
                }
                if let error {
                    Section {
                        Text(error).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                        Button("Try again") { Task { await load() } }
                            .buttonStyle(.plain)
                            .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
                    }
                }
                if detail != nil {
                    if proposal.isElection {
                        ElectionPanel(
                            proposal: proposal, api: api, acting: acting, signedOut: sameQuilt && session.me == nil,
                            isFollower: standing == .active(.follower), meID: meID,
                            canNominate: canNominate, slug: slug,
                            signIn: { signingIn = true },
                            reload: { await load() },
                            unauthenticated: { session.signedOut() }
                        )
                    } else if VoteRules.showsVoteSection(proposal) {
                        voteSection
                    }
                    discussion
                }
            }
            }.listRows()
        }
        .groundedList()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { listFrame = $0 }
        .navigationTitle("Proposal").navigationBarTitleDisplayMode(.inline)
        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
        .safeAreaInset(edge: .bottom) { if showsBar { voteBar } }
        .animation(.easeInOut(duration: 0.2), value: showsBar)
        .confirmationDialog("Delete this comment?", isPresented: deletingBinding, titleVisibility: .visible, presenting: deleting) { comment in
            Button("Delete", role: .destructive) { remove(comment) }
            Button("Cancel", role: .cancel) {}
        } message: { comment in
            if let line = Discussion.deleteMessage(comment) { Text(line) }
        }
        .signInGate($signingIn)
        .task { await load(); await loadComments() }
        .refreshable { await load(); await loadComments() }
        // Signing in changes who is asking: `can_vote`, `my_vote` and every
        // `me` on a reaction are answered again for the new reader.
        .onChange(of: session.me?.id) { _, _ in Task { await load(); await loadComments() } }
        .onChange(of: standing) { _, _ in Task { await readPermissions() } }
    }

    private var deletingBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted).textCase(nil)
    }

    /// Title, outcome, who opened it and when, and what it touches — one
    /// card, because it is one fact: what this is.
    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                if !proposal.title.isEmpty {
                    Text(proposal.title).font(Font.pw.title2).foregroundStyle(Color.pwText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                if detail != nil || !proposal.title.isEmpty { OutcomeBadge(proposal: proposal) }
                VStack(alignment: .leading, spacing: 2) {
                    if let byline { Text(byline).font(Font.pw.subheadline) }
                    if let created = ProfileDate.day(proposal.createdAt) { Text(created).font(Font.pw.caption) }
                }
                .foregroundStyle(Color.pwTextMuted)
                if let target = proposal.targetDoc, !target.isEmpty {
                    Label("\(proposal.isDirectChange ? "Change" : "Amendment") to \(target)", systemImage: "doc.text")
                        .font(Font.pw.subheadline)
                }
                if let type = proposal.proposalType, !type.isEmpty, type != "other", !proposal.isElection {
                    Label(type.capitalized, systemImage: "tag").font(Font.pw.subheadline)
                }
                if detail == nil && error == nil && !notPublic {
                    ProgressView("Loading proposal…")
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// The election calendar opened an election, not a person (web ADR 109).
    private var byline: String? {
        if proposal.isElection { return "Opened by this patch’s election calendar" }
        guard let author = proposal.authorName, !author.isEmpty else { return nil }
        return "\(proposal.isDirectChange ? "Applied by" : "Proposed by") \(author)"
    }

    // MARK: The vote

    private var showsButtons: Bool { acting && VoteRules.showsButtons(proposal) }

    /// The web's sticky bar: only while the card's own buttons are off
    /// screen. `onScrollVisibilityChange` was the first choice, and inside a
    /// `List` it says when a row arrives but not when its cell is recycled,
    /// so the bar never came back; the row's own frame against the list's,
    /// and its disappearance, say both.
    private var showsBar: Bool {
        guard showsButtons, detail != nil, typing == nil else { return false }
        guard let buttonsFrame else { return true }
        return !listFrame.insetBy(dx: 0, dy: 24).intersects(buttonsFrame)
    }

    @ViewBuilder private var voteSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                TallyBar(proposal: proposal)
                Text(VoteRules.countsLine(proposal))
                    .font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwText)
                    .accessibilityIdentifier("voteCounts")
                Text(VoteRules.quorumLine(proposal))
                    .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("voteQuorum")
            }
            .padding(.vertical, 4)
            if VoteRules.soleVoter(proposal) {
                Text("You’re the only eligible voter, so your vote decides this immediately.")
                    .font(Font.pw.footnote).foregroundStyle(Color.pwText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsButtons {
                VStack(alignment: .leading, spacing: 8) {
                    VoteButtons(current: VoteRules.myVote(proposal), pastTense: true, busy: voteBusy, identified: true, cast: cast)
                    if let voteFailure { refusal(voteFailure, id: "voteFailure") }
                }
                .padding(.vertical, 4)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { buttonsFrame = $0 }
                .onDisappear { buttonsFrame = nil }
            } else if let voteFailure {
                refusal(voteFailure, id: "voteFailure")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(VoteRules.thresholdLine(proposal))
                if let terms = VoteRules.termsLine(proposal) {
                    Text(terms).accessibilityIdentifier("voteTerms")
                }
            }
            .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
            .fixedSize(horizontal: false, vertical: true)
            if VoteRules.isVoting(proposal) && proposal.canVote != true {
                outsiderLine
            }
            voters
        } header: {
            heading(proposal.advisory == true ? "Advisory vote" : "Vote")
        }
    }

    /// What a reader with no buttons is told, and only where a vote is open.
    /// Signed out: one quiet door. A follower: one sentence, and no door —
    /// joining lives on the profile. Anybody else is answered by the terms
    /// line already.
    @ViewBuilder private var outsiderLine: some View {
        if sameQuilt && session.me == nil {
            Button { signingIn = true } label: {
                Text("Sign in to vote").font(Font.pw.subheadlineMedium)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .inkAction("person.badge.key")
            .accessibilityIdentifier("signInToVote")
        } else if standing == .active(.follower) {
            Text("Become a member to vote.")
                .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                .accessibilityIdentifier("becomeAMember")
        }
    }

    @ViewBuilder private var voters: some View {
        let list = proposal.voters ?? []
        if !list.isEmpty {
            Button { withAnimation { showVoters.toggle() } } label: {
                Text("\(showVoters ? "Hide" : "Show") voters (\(list.count))").font(Font.pw.subheadlineMedium)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .inkAction(showVoters ? "chevron.up" : "chevron.down")
            .accessibilityIdentifier("showVoters")
            if showVoters {
                ForEach(Array(list.enumerated()), id: \.offset) { _, ballot in
                    HStack(spacing: 8) {
                        Text(ballot.name).font(Font.pw.subheadline).foregroundStyle(ballot.isCounted ? Color.pwText : Color.pwTextMuted)
                        if !ballot.isCounted {
                            Text("not counted").font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                        }
                        Spacer(minLength: 8)
                        ValueBadge(value: ballot.value ?? "")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("voterRow")
                }
                if list.contains(where: { !$0.isCounted }) {
                    Text("Not counted: cast by someone who has since left this patch or is no longer a member.")
                        .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var voteBar: some View {
        VStack(spacing: 8) {
            Text(VoteRules.compactTally(proposal))
                .font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwText)
                .frame(maxWidth: .infinity)
            VoteButtons(current: VoteRules.myVote(proposal), pastTense: false, busy: voteBusy, identified: false, cast: cast)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.pwSurface)
        .overlay(alignment: .top) { Rectangle().fill(Color.pwBorder).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voteBar")
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func refusal(_ text: String, id: String) -> some View {
        Label { Text(text).font(Font.pw.footnote) } icon: {
            Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
        }
        .foregroundStyle(Color.pwText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier(id)
    }

    /// Changing a vote needs no confirmation: the filled button moving is
    /// the confirmation, and there is no toast. The proposal is read again
    /// after every vote, because a sole voter settles it inside the POST.
    private func cast(_ value: VoteRules.Value) {
        guard !voteBusy, VoteRules.myVote(proposal) != value else { return }
        voteBusy = true
        voteFailure = nil
        Task {
            do {
                try await api.vote(proposal: proposal.id, value: value)
                await load()
            } catch APIError.unauthenticated {
                session.signedOut()
            } catch {
                voteFailure = Self.sentence(error, fallback: "Your vote was not recorded.")
                await load()
            }
            voteBusy = false
        }
    }

    /// The server's own sentence, first letter raised; the fallback where
    /// the quilt said nothing a person could read.
    static func sentence(_ error: Error, fallback: String) -> String {
        switch error {
        case APIError.message(let text, _): return EventPosting.sentenceCased(text)
        case APIError.refused(let refusal, _) where !refusal.error.isEmpty: return EventPosting.sentenceCased(refusal.error)
        default: return fallback
        }
    }

    // MARK: The discussion

    @ViewBuilder private var discussion: some View {
        let items = comments ?? []
        Section {
            if comments == nil && commentsError == nil {
                ProgressView("Loading comments…")
            }
            if let commentsError {
                Text(commentsError).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                Button("Try again") { Task { await loadComments() } }
                    .buttonStyle(.plain)
                    .font(Font.pw.subheadlineMedium).inkAction("arrow.clockwise")
            }
            if comments != nil && items.isEmpty {
                Text("No comments yet.").font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
            }
            ForEach(items) { comment in
                commentCard(comment, reply: false)
                ForEach(comment.replies ?? []) { reply in commentCard(reply, reply: true) }
            }
            if canDiscuss { composer }
        } header: {
            heading(comments == nil ? "Discussion" : "Discussion (\(Discussion.count(items)))")
                .accessibilityIdentifier("discussionHeading")
        }
    }

    private func commentCard(_ comment: ProposalComment, reply: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(comment.author).font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwText)
                Spacer(minLength: 8)
                Text(NotificationTime.ago(comment.createdAt)).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
            }
            if editing == comment.id {
                inlineField("Edit your comment", text: $editText, id: "commentEditField")
                inlineActions(primary: "Save", enabled: !editText.trimmed.isEmpty, id: "commentEditSave") {
                    save(comment)
                } cancel: { editing = nil; editText = "" }
            } else {
                MarkdownText(source: comment.body, base: quilt.url)
                    .font(Font.pw.body).foregroundStyle(Color.pwText)
            }
            reactions(comment)
            commentActions(comment, reply: reply)
            if replyingTo == comment.id {
                inlineField("Write a reply…", text: $replyText, id: "replyField")
                inlineActions(primary: "Reply", enabled: !replyText.trimmed.isEmpty, id: "replyPost") {
                    post(replyText, parent: comment.id)
                } cancel: { replyingTo = nil; replyText = "" }
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, reply ? 16 : 0)
        .overlay(alignment: .leading) {
            if reply { Rectangle().fill(Color.pwBorder).frame(width: 2) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(reply ? "replyRow" : "commentRow")
    }

    @ViewBuilder private func reactions(_ comment: ProposalComment) -> some View {
        let chips = Discussion.chips(comment.reactions, canReact: canDiscuss)
        if !chips.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(chips, id: \.emoji) { chip in
                    let key = comment.id + chip.emoji
                    Button { toggle(chip, on: comment) } label: {
                        HStack(spacing: 4) {
                            Text(chip.emoji)
                            if chip.count > 0 {
                                Text("\(chip.count)").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwText)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .background(chip.me ? Color.pwAccent.opacity(0.14) : Color.pwGround, in: Capsule())
                        .overlay(Capsule().strokeBorder(chip.me ? Color.pwAccent : Color.pwBorder, lineWidth: 1))
                        .opacity(reacting.contains(key) ? 0.5 : 1)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canDiscuss || reacting.contains(key))
                    .accessibilityLabel("\(Discussion.name(chip.emoji)), \(chip.count)")
                    .accessibilityValue(chip.me ? "Yours" : "")
                    .accessibilityIdentifier("reaction-\(chip.emoji)")
                }
            }
        }
    }

    @ViewBuilder private func commentActions(_ comment: ProposalComment, reply: Bool) -> some View {
        let canReply = canDiscuss && !reply
        let canEdit = acting && Discussion.canEdit(comment, me: meID)
        let canDelete = acting && Discussion.canDelete(comment, me: meID, standing: standing, isInstanceAdmin: isInstanceAdmin)
        if canReply || canEdit || canDelete {
            HStack(spacing: 18) {
                if canReply {
                    smallAct("Reply", id: "commentReply") {
                        replyingTo = comment.id; replyText = ""; editing = nil
                        focusSoon("replyField")
                    }
                }
                if canEdit {
                    smallAct("Edit", id: "commentEdit") {
                        editing = comment.id; editText = comment.body; replyingTo = nil
                        focusSoon("commentEditField")
                    }
                }
                if canDelete {
                    smallAct("Delete", id: "commentDelete") { deleting = comment }
                }
                Spacer(minLength: 0)
            }
            .disabled(commentBusy)
        }
    }

    /// The inline field opens with the keyboard up, after the row that holds
    /// it has been laid out.
    private func focusSoon(_ field: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            typing = field
        }
    }

    private func smallAct(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwText)
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func inlineField(_ prompt: String, text: Binding<String>, id: String) -> some View {
        TextField(prompt, text: text, axis: .vertical)
            .lineLimit(2...8)
            .fieldStyle()
            .focused($typing, equals: id)
            .accessibilityIdentifier(id)
    }

    private func inlineActions(primary: String, enabled: Bool, id: String, act: @escaping () -> Void, cancel: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: act) {
                Group {
                    if commentBusy { ProgressView().tint(.white) } else { Text(primary).font(Font.pw.subheadlineSemibold) }
                }
                .foregroundStyle(enabled && !commentBusy ? Color.white : Color.pwTextMuted)
                .frame(minWidth: 64, minHeight: 30)
            }
            .buttonStyle(.borderedProminent).tint(Color.pwAccent)
            .disabled(!enabled || commentBusy)
            .accessibilityIdentifier(id)
            Button(action: cancel) {
                Text("Cancel").font(Font.pw.subheadlineSemibold).frame(minHeight: 30)
            }
            .buttonStyle(.bordered).tint(Color.pwText)
            .disabled(commentBusy)
            Spacer(minLength: 0)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Add a comment…", text: $draft, axis: .vertical)
                .lineLimit(2...8)
                .fieldStyle()
                .focused($typing, equals: "commentField")
                .accessibilityIdentifier("commentField")
            HStack {
                Spacer(minLength: 0)
                Button { post(draft, parent: nil) } label: {
                    Group {
                        if commentBusy && replyingTo == nil && editing == nil { Text("Posting…") } else { Text("Comment") }
                    }
                    .font(Font.pw.subheadlineSemibold)
                    .foregroundStyle(draftReady ? Color.white : Color.pwTextMuted)
                    .frame(minHeight: 30)
                }
                .buttonStyle(.borderedProminent).tint(Color.pwAccent)
                .disabled(!draftReady)
                .accessibilityIdentifier("commentPost")
            }
            if let commentFailure { refusal(commentFailure, id: "commentFailure") }
        }
        .padding(.vertical, 4)
    }

    private var draftReady: Bool { !draft.trimmed.isEmpty && !commentBusy }

    // MARK: Acts on the thread

    /// Every write ends in the thread read again: the server keeps no
    /// tombstone and sends no count, so what it now holds is the only truth.
    private func run(_ act: @escaping () async throws -> Void, done: @escaping () -> Void = {}) {
        guard !commentBusy else { return }
        commentBusy = true
        commentFailure = nil
        Task {
            do {
                try await act()
                done()
            } catch APIError.unauthenticated {
                session.signedOut()
            } catch {
                commentFailure = Self.sentence(error, fallback: "That did not go through. Try again.")
            }
            await loadComments()
            commentBusy = false
        }
    }

    private func post(_ text: String, parent: String?) {
        let body = text.trimmed
        guard !body.isEmpty else { return }
        run({ try await api.comment(proposal: proposal.id, body: body, parentID: parent) }) {
            if parent == nil { draft = "" } else { replyingTo = nil; replyText = "" }
        }
    }

    private func save(_ comment: ProposalComment) {
        let body = editText.trimmed
        guard !body.isEmpty else { return }
        run({ try await api.editComment(id: comment.id, body: body) }) { editing = nil; editText = "" }
    }

    private func remove(_ comment: ProposalComment) {
        deleting = nil
        run({ try await api.deleteComment(id: comment.id) })
    }

    private func toggle(_ chip: Discussion.Chip, on comment: ProposalComment) {
        let key = comment.id + chip.emoji
        guard canDiscuss, !reacting.contains(key) else { return }
        reacting.insert(key)
        Task {
            do {
                if chip.me { try await api.unreact(comment: comment.id, emoji: chip.emoji) }
                else { try await api.react(comment: comment.id, emoji: chip.emoji) }
            } catch APIError.unauthenticated {
                session.signedOut()
            } catch {
                commentFailure = Self.sentence(error, fallback: "That reaction did not go through.")
            }
            await loadComments()
            reacting.remove(key)
        }
    }

    // MARK: Reads

    private func load() async {
        do {
            let answer: Proposal = try await api.get("proposals/\(initial.id)")
            detail = answer
            error = nil
            notPublic = false
            await readPermissions()
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            guard !Task.isCancelled else { return }
            if (error as? APIError)?.httpStatus == 404 { notPublic = true } else if detail == nil { self.error = error.localizedDescription }
        }
    }

    private func loadComments() async {
        do {
            comments = try await api.comments(proposal: initial.id)
            commentsError = nil
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            guard !Task.isCancelled else { return }
            if (error as? APIError)?.httpStatus == 404 { comments = []; notPublic = detail == nil }
            else if comments == nil { commentsError = "The discussion could not be loaded." }
        }
    }

    /// A follower's composer hangs on the patch's own switch, which rides
    /// `nodes/{slug}`. Nobody else's does, so nobody else asks.
    private func readPermissions() async {
        guard standing == .active(.follower), let slug else {
            permissionsRead = true
            return
        }
        if let answer: PatchResponse = try? await api.get("nodes/\(slug)") {
            followerPermissions = answer.node.followerPermissions
        }
        permissionsRead = true
    }
}

// MARK: - Parts

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// The three buttons, equal width and at least 44pt tall. The current vote
/// is the filled one; the other two are outlined, and tapping one changes
/// the vote. In the card the filled one says what happened ("Approved"); in
/// the bar at the foot every button keeps its present tense, as the web's
/// does. Where the three will not fit side by side they stack, rather than
/// folding a word.
struct VoteButtons: View {
    let current: VoteRules.Value?
    let pastTense: Bool
    let busy: Bool
    /// The card's buttons carry the identifiers; the bar's are its own.
    let identified: Bool
    let cast: (VoteRules.Value) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons }
            VStack(spacing: 8) { buttons }
        }
    }

    @ViewBuilder private var buttons: some View {
        ForEach(VoteRules.Value.allCases) { value in
            let filled = current == value
            let title = filled && pastTense ? value.past : value.present
            Button { cast(value) } label: {
                Group {
                    if busy { ProgressView().tint(filled ? .white : Color.pwText) }
                    else { Text(title).font(Font.pw.subheadlineSemibold).lineLimit(1).fixedSize() }
                }
                .foregroundStyle(filled ? Color.white : Color.pwText)
                .frame(maxWidth: .infinity, minHeight: 30)
            }
            .modifier(VoteButtonStyle(filled: filled))
            .controlSize(.large)
            .disabled(busy)
            .accessibilityLabel(title)
            .accessibilityValue(filled ? "Your vote" : "")
            .accessibilityIdentifier(identified ? value.identifier : "bar-" + value.identifier)
        }
    }
}

/// Filled in the one tint for the vote that is in, whatever its value;
/// outlined for the other two. The value's own colour belongs to the tally,
/// which is data, never to a control.
private struct VoteButtonStyle: ViewModifier {
    let filled: Bool
    func body(content: Content) -> some View {
        if filled { content.buttonStyle(.borderedProminent).tint(Color.pwAccent) }
        else { content.buttonStyle(.bordered).tint(Color.pwAccent) }
    }
}

/// Approve and reject over the whole count, abstentions included, with a
/// thin mark at the quorum. The fills are the system's green and red because
/// they are data, as the web's are.
struct TallyBar: View {
    let proposal: Proposal
    var body: some View {
        let fills = VoteRules.fills(proposal)
        let quorum = Double(proposal.votingTerms?.quorumPercent ?? 0) / 100
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.pwBorder)
                HStack(spacing: 0) {
                    Rectangle().fill(Color.green).frame(width: width * fills.approve)
                    Rectangle().fill(Color.red).frame(width: width * fills.reject)
                }
                .clipShape(Capsule())
                if quorum > 0 && proposal.advisory != true {
                    Rectangle().fill(Color.pwText).frame(width: 2, height: 14)
                        .offset(x: min(width - 2, width * quorum))
                }
            }
        }
        .frame(height: 8)
        .padding(.vertical, 3)
        .accessibilityElement()
        .accessibilityLabel(VoteRules.countsLine(proposal))
    }
}

/// A voter's value, as a word in its colour. Data, like the bar.
struct ValueBadge: View {
    let value: String
    var body: some View {
        Text(value)
            .font(Font.pw.caption2Semibold)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
    private var tint: Color {
        switch value {
        case "approve": return .green
        case "reject": return .red
        default: return .secondary
        }
    }
}

// MARK: - The election

/// An election's panel in place of the vote (web `ElectionPanel`): the
/// slate, and — by phase — the nominating acts or the ballot. Approval
/// voting: tick as many as you like, and the whole set is sent each save.
/// The box is the only vote control; the name beside it is only a name
/// (web ADR 109).
struct ElectionPanel: View {
    let proposal: Proposal
    let api: PatchworkAPI
    let acting: Bool
    let signedOut: Bool
    let isFollower: Bool
    let meID: String?
    let canNominate: Bool
    let slug: String?
    let signIn: () -> Void
    let reload: () async -> Void
    let unauthenticated: () -> Void

    @State private var approved: Set<String> = []
    @State private var busy = false
    @State private var failure: String?
    @State private var statement = ""
    @State private var nominee = ""
    @State private var members: [PatchMember] = []

    private var candidates: [Candidate] { proposal.candidates ?? [] }
    private var ballotOpen: Bool { acting && VoteRules.ballotOpen(proposal) }
    private var mine: Set<String> { Set(candidates.filter { $0.approvedByMe == true }.map(\.id)) }
    private var ballotIn: Bool { !mine.isEmpty }
    private var standingInIt: Bool { candidates.contains { $0.userId != nil && $0.userId == meID } }
    private var nominating: Bool { proposal.electionPhase == "nominating" }
    /// The seed: what the server says this reader approved.
    private var seedKey: String { proposal.id + "|" + mine.sorted().joined(separator: ",") }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                if let lede = VoteRules.electionLede(proposal) {
                    Text(lede).font(Font.pw.body).foregroundStyle(Color.pwText)
                }
                if !nominating, let day = ProfileDate.day(proposal.nominationsCloseAt) {
                    Text("Standing closed \(day).").font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                }
                if let turnout = VoteRules.turnoutLine(proposal) {
                    Text(turnout).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                        .accessibilityIdentifier("electionTurnout")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)
            if candidates.isEmpty {
                Text(nominating ? "Nobody has stood yet." : "Nobody stood.")
                    .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
            }
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                row(candidate, index: index)
            }
            if ballotOpen && !candidates.isEmpty { ballotControls }
            if proposal.electionPhase == "voting" && proposal.canVote != true { outsiderLine }
            if nominating && canNominate { nominatingActions }
            if let failure {
                Label { Text(failure).font(Font.pw.footnote) } icon: {
                    Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
                }
                .foregroundStyle(Color.pwText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("electionFailure")
            }
        } header: {
            HStack {
                Text(VoteRules.electionHeading(proposal))
                Spacer()
                Text(VoteRules.seatsLabel(proposal.seatsContested ?? 0))
            }
            .font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted).textCase(nil)
        }
        .task(id: seedKey) { approved = mine }
        .task(id: "\(proposal.electionPhase ?? "")|\(canNominate)|\(slug ?? "")") { await loadMembers() }
    }

    private func row(_ candidate: Candidate, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if ballotOpen {
                let on = approved.contains(candidate.id)
                Button {
                    if on { approved.remove(candidate.id) } else { approved.insert(candidate.id) }
                } label: {
                    Image(systemName: on ? "checkmark.square.fill" : "square")
                        .font(Font.pw.title3)
                        .foregroundStyle(on ? Color.pwAccent : Color.pwTextMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityLabel("Approve \(candidate.name)")
                .accessibilityValue(on ? "Ticked" : "Not ticked")
                .accessibilityAddTraits(.isToggle)
                .accessibilityIdentifier("ballotTick-\(candidate.id)")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.name).font(Font.pw.headline).foregroundStyle(Color.pwText)
                HStack(spacing: 8) {
                    if !nominating {
                        let n = candidate.approvals ?? 0
                        Text("\(n) approval\(n == 1 ? "" : "s")")
                            .accessibilityIdentifier("approvals-\(candidate.id)")
                    }
                    if VoteRules.isSeated(candidate, at: index, in: proposal) {
                        Tag(text: "seated")
                    } else if proposal.electionPhase == "closed" {
                        Tag(text: "not seated")
                    }
                }
                .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                if let statement = candidate.statement, !statement.isEmpty {
                    Text(statement).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, ballotOpen ? 8 : 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("candidateRow")
    }

    @ViewBuilder private var ballotControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { save(abstain: false) } label: {
                Text(busy ? "Saving…" : (ballotIn ? "Update my ballot" : "Save my ballot"))
                    .font(Font.pw.headline)
                    .foregroundStyle(saveEnabled ? Color.white : Color.pwTextMuted)
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent).tint(Color.pwAccent)
            .controlSize(.large)
            .disabled(!saveEnabled)
            .accessibilityIdentifier("ballotSave")
            Text(ballotIn ? "Your ballot is in. You can change it until voting closes." : "You can change this until voting closes.")
                .font(Font.pw.footnote).foregroundStyle(ballotIn ? Color.pwText : Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(ballotIn ? "ballotIn" : "ballotHint")
        }
        .padding(.vertical, 4)
        VStack(alignment: .leading, spacing: 4) {
            if proposal.iAbstained == true {
                Text("You are counted as taking part and approving nobody. Ticking a name and saving replaces that.")
                    .font(Font.pw.footnote).foregroundStyle(Color.pwText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ballotAbstained")
            } else {
                Button { save(abstain: true) } label: {
                    Text("Take part without approving anyone").font(Font.pw.subheadlineMedium)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .inkAction("hand.raised")
                .disabled(busy)
                .accessibilityIdentifier("ballotAbstain")
                Text("Counts toward the turnout this election needs, the way an abstention counts on an ordinary proposal.")
                    .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Something to send: a changed set, or a first ballot with a name on it.
    private var saveEnabled: Bool {
        guard !busy else { return false }
        if approved == mine { return !ballotIn && !approved.isEmpty }
        return true
    }

    @ViewBuilder private var outsiderLine: some View {
        if signedOut {
            Button(action: signIn) {
                Text("Sign in to vote").font(Font.pw.subheadlineMedium)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .inkAction("person.badge.key")
            .accessibilityIdentifier("signInToVote")
        } else if isFollower {
            Text("Become a member to vote.").font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                .accessibilityIdentifier("becomeAMember")
        }
    }

    @ViewBuilder private var nominatingActions: some View {
        if standingInIt {
            HStack {
                Text("You are standing in this election.").font(Font.pw.body).foregroundStyle(Color.pwText)
                Spacer(minLength: 8)
                Button { run { try await api.withdrawCandidacy(proposal: proposal.id) } } label: {
                    Text(busy ? "Withdrawing…" : "Withdraw").font(Font.pw.subheadlineSemibold).frame(minHeight: 30)
                }
                .buttonStyle(.bordered).tint(Color.pwAccent)
                .disabled(busy)
                .accessibilityIdentifier("withdrawCandidacy")
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Why you are standing (optional)").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
                TextField("A few lines the other members will see beside your name on the ballot.", text: $statement, axis: .vertical)
                    .lineLimit(3...6)
                    .fieldStyle()
                    .onChange(of: statement) { _, now in
                        let clipped = VoteRules.clipStatement(now)
                        if clipped != now { statement = clipped }
                    }
                    .accessibilityIdentifier("candidateStatement")
                HStack {
                    Text("\(VoteRules.charactersLeft(statement)) characters left")
                        .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    Spacer(minLength: 8)
                    Button { run({ try await api.stand(proposal: proposal.id, statement: statement) }) { statement = "" } } label: {
                        Text(busy ? "Standing…" : "Stand for election").font(Font.pw.subheadlineSemibold)
                            .foregroundStyle(busy ? Color.pwTextMuted : Color.white)
                            .frame(minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent).tint(Color.pwAccent)
                    .disabled(busy)
                    .accessibilityIdentifier("standForElection")
                }
            }
            .padding(.vertical, 4)
        }
        let others = VoteRules.nominatable(members, me: meID, candidates: candidates)
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Put another member forward").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
                HStack {
                    Picker("Choose a member", selection: $nominee) {
                        Text("Choose a member").tag("")
                        ForEach(others, id: \.id) { member in Text(member.name).tag(member.userId ?? "") }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(Color.pwText)
                    .accessibilityIdentifier("nomineePicker")
                    Spacer(minLength: 8)
                    Button { run({ try await api.nominate(proposal: proposal.id, userID: nominee) }) { nominee = "" } } label: {
                        Text(busy ? "Adding…" : "Put forward").font(Font.pw.subheadlineSemibold).frame(minHeight: 30)
                    }
                    .buttonStyle(.bordered).tint(Color.pwAccent)
                    .disabled(busy || nominee.isEmpty)
                    .accessibilityIdentifier("putForward")
                }
                Text("They go on the ballot straight away, and can withdraw themselves until nominations close.")
                    .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    private func save(abstain: Bool) {
        let chosen = approved
        run {
            try await api.castBallot(proposal: proposal.id, candidateIDs: abstain ? [] : Array(chosen), abstain: abstain)
        }
    }

    private func run(_ act: @escaping () async throws -> Void, done: @escaping () -> Void = {}) {
        guard !busy else { return }
        busy = true
        failure = nil
        Task {
            do {
                try await act()
                done()
            } catch APIError.unauthenticated {
                unauthenticated()
            } catch {
                failure = ProposalDetailView.sentence(error, fallback: "That did not go through. Try again.")
            }
            await reload()
            busy = false
        }
    }

    private func loadMembers() async {
        guard nominating, canNominate, let slug else { members = []; return }
        members = (try? await api.electionMembers(slug: slug)) ?? []
    }
}

/// A quiet outlined word: `seated`, `not seated`.
private struct Tag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Font.pw.caption2Semibold)
            .foregroundStyle(Color.pwTextMuted)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 1))
    }
}
