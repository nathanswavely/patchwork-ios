// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// The docked profile: the patch's own profile, over the surface that opened
/// it. At rest the sheet shows the head and a cut of the first glimpse;
/// pulled up it shows everything, and the pull is what fetches the rooms.
///
/// The glimpses are the web's, in the web's order — About, Events, Members,
/// Governance (ADR 042) — and each heading is itself the door into that room.
/// There is no door named for a container: no "Manage", no "Governance" pill
/// over a section that is already called Governance. About is the one heading
/// that names identity rather than a room, so it stays inert.
struct PatchSheet: View {
    @EnvironmentObject private var session: QuiltSession
    let initial: Patch
    @State private var envelope: PatchResponse?
    @State private var events: [PatchworkEvent]?
    @State private var roster: MemberRoster?
    @State private var documents: [GovernanceDocument]?
    @State private var documentsPublishedOnly = false
    @State private var proposals: [Proposal]?
    @State private var recordWithheld = false
    @State private var glimpsesAsked = false
    @State private var roomsAnswered = false
    @State private var error: String?
    @State private var rest: CGFloat = 320
    @State private var detent = PresentationDetent.height(320)
    @State private var headBottom: CGFloat = 0
    @State private var sheetTop: CGFloat = 0
    /// How much of the first glimpse shows under the head at rest: enough for
    /// its rule, its title and a line of it, cut off. The cut is the invitation.
    private let peek: CGFloat = 96
    private var patch: Patch { envelope?.node ?? initial }
    private var api: PatchworkAPI { session.api }
    private var cover: URL? { patch.imageUrl.flatMap { URL(string: $0, relativeTo: session.quilt.url) } }
    /// The envelope's word, with the tree row's as the first frame's answer.
    private var isUnclaimed: Bool { envelope?.isUnclaimed ?? patch.communityListing }
    /// Whether this patch's lining is its own writing (web ADR 037).
    private var liningDiverged: Bool { envelope?.liningStatus == "diverged" }
    private var moved: MovedElsewhere? { MovedElsewhere(patch.movedTo) }
    private var atprotoHandle: String? { AtprotoHandle.from(patch.did) }
    private var patchLinks: [PatchLink] { patch.links ?? [] }
    private var hasAbout: Bool {
        !(patch.website ?? "").isEmpty || !patchLinks.isEmpty || !(patch.address ?? "").isEmpty || atprotoHandle != nil
    }
    /// A withheld roster collapses the glimpse rather than showing an empty
    /// one (web ADR 095): the door it would be is the members screen, and
    /// that screen is the place that says why.
    /// A room this quilt would not answer about is left out rather than
    /// reported empty: "no members" is a claim, and a failed request is not
    /// entitled to make it.
    private var showsMembers: Bool {
        !isUnclaimed && roster?.withheld != true && !(roomsAnswered && roster == nil)
    }
    /// An unclaimed patch carries no governance at all (web ADR 039):
    /// absence, not an empty room.
    private var showsGovernance: Bool {
        !isUnclaimed && !(roomsAnswered && documents == nil && proposals == nil)
    }
    private func close() { session.docked = nil }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    head.background(GeometryReader { proxy in Color.clear.preference(key: HeadBottomKey.self, value: proxy.frame(in: .global).maxY) })
                    glimpses
                }
            }
            .background(Color.pwGround)
            .navigationTitle("Patch").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ShareLink(item: api.webURL("patches/\(patch.slug)")) }
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) }
            }
        }
        .background(GeometryReader { proxy in Color.clear.preference(key: SheetTopKey.self, value: proxy.frame(in: .global).minY) })
        .onPreferenceChange(HeadBottomKey.self) { headBottom = $0; measure() }
        .onPreferenceChange(SheetTopKey.self) { sheetTop = $0; measure() }
        .presentationDetents([.height(rest), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: detent) { _, now in if now == .large && !glimpsesAsked { Task { await loadGlimpses() } } }
        .task { await load() }
    }
    /// The rest height is measured from the sheet's top edge to the foot of the
    /// head, not from the head's own height, so the bar above it is counted.
    private func measure() {
        guard detent != .large, headBottom > sheetTop else { return }
        let height = min((headBottom - sheetTop + peek).rounded(), UIScreen.main.bounds.height * 0.8)
        guard abs(height - rest) > 1 else { return }
        rest = height
        detent = .height(height)
    }
    /// The head is the sheet's own face, the way a place card is in Maps:
    /// edge to edge, the sheet's rounded top as its only corners, and a
    /// hairline underneath where the glimpses begin. It keeps the list's
    /// surface and hairline so the card a reader touched and the profile it
    /// opens are still one thing, but it is no longer a card floating inside
    /// another card.
    private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cover {
                AsyncImage(url: cover) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.pwGround }
                    .frame(height: 160).frame(maxWidth: .infinity).clipped()
                    .accessibilityLabel(patch.imageAlt ?? "")
            }
            VStack(alignment: .leading, spacing: 8) {
                // The patch saying its own name — a display moment, in the
                // face the web keeps for them.
                Text(patch.name).font(Font.pw.displayTitle).foregroundStyle(Color.pwText).fixedSize(horizontal: false, vertical: true)
                Text(patch.countsLabel).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                // Follow, Join, or the standing already held. It sits under
                // the counts it changes: what the reader is to this patch is
                // part of the patch's own head, not an afterword at the foot.
                RelationshipControl(patch: patch, banned: envelope?.banned ?? false) { await load() }
                if let tags = patch.tags, !tags.isEmpty { Text(tags.joined(separator: " · ")).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted) }
                notices
                if let description = patch.description, !description.isEmpty { Text(description).foregroundStyle(Color.pwText).textSelection(.enabled) }
            // The glimpses under the head keep a 20pt margin; the head's
            // text sits on the same line so the name and "About" align.
            }.padding(.horizontal, 20).padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pwSurface)
        .overlay(alignment: .bottom) { Color.pwBorder.frame(height: PatchworkCard.hairline) }
    }
    /// State is worn in the head, never disguised as an action. Each of these
    /// is a fact about the patch, and none of them is a button this client
    /// could honour: claiming a patch happens on the website.
    @ViewBuilder private var notices: some View {
        if let moved {
            VStack(alignment: .leading, spacing: 6) {
                Label("This patch has moved to \(moved.host).", systemImage: "arrow.uturn.right")
                    .font(Font.pw.subheadline).fixedSize(horizontal: false, vertical: true)
                NavigationLink { RemotePatchView(host: moved.host, slug: moved.slug, close: close) } label: {
                    Text("See it on \(moved.host)").inkRow()
                }.accessibilityIdentifier("movedTo")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        } else if let raw = patch.movedTo, let url = URL(string: raw), url.scheme == "https" {
            Link(destination: url) { Label("This patch has moved to \(url.host() ?? raw).", systemImage: "arrow.uturn.right") }.exitLink()
                .font(Font.pw.subheadline)
        }
        if isUnclaimed {
            Text("No one runs this patch yet. The community added it; if it’s yours, you can claim it on this quilt’s website.")
                .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("unclaimedNotice")
        } else if liningDiverged {
            // Public by design (web ADR 037): this patch amended the shared
            // baseline, and the divergence is worn, not whispered.
            Label("Amended lining", systemImage: "seal")
                .font(Font.pw.captionSemibold)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color(.secondarySystemFill), in: Capsule())
                .accessibilityIdentifier("amendedLining")
                .accessibilityHint("This patch changed the shared community standards every patch starts with. Its version is in Governance.")
        }
    }
    private var glimpses: some View {
        VStack(alignment: .leading, spacing: 24) {
            if hasAbout { about }
            eventsGlimpse
            if showsMembers { membersGlimpse }
            if showsGovernance { governanceGlimpse }
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Link(destination: api.webURL("patches/\(patch.slug)")) { Label("Visit patch website", systemImage: "safari") }.exitLink()
                // The sentence used to be a door out to the website, because
                // following was the website's. It is now a door into the
                // sheet: the act is native, so the invitation is too. Signed
                // in, there is nothing to say here — the control is in the
                // head, where the counts it changes are.
                if session.me == nil { SignInAction(text: "Sign in to follow or join.") }
            }
            if let error {
                Text(error).foregroundStyle(Color.pwTextMuted)
                Button("Reload patch") { Task { await load() } }
            }
        }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 32)
    }
    /// About says what this patch *is*, and the events under it read
    /// differently once you know. It needs no fetch, so it is the glimpse a
    /// sheet at rest can show whole.
    private var about: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            StaticHeading(title: "About")
            if let site = patch.website, let url = URL(string: site), url.scheme == "https" || url.scheme == "http" {
                Link(destination: url) { Label(url.host() ?? site, systemImage: "link") }.exitLink()
            }
            ForEach(patchLinks, id: \.self) { link in
                if let url = patchLink(link) {
                    Link(destination: url) { Label(linkLabel(link), systemImage: "arrow.up.forward") }.exitLink()
                }
            }
            if let address = patch.address, !address.isEmpty {
                Label(address, systemImage: "mappin.and.ellipse").fixedSize(horizontal: false, vertical: true)
                if let url = mapsURL { Link("Get directions", destination: url).exitLink() }
            }
            if let handle = atprotoHandle {
                // Past tense on purpose (web ADR 062): the binding was checked
                // once, when the claim was verified, and nothing re-checks it.
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(handle)").font(.subheadline.monospaced())
                    Text("atproto handle, proved when this patch was claimed")
                        .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                }
            }
        }
    }
    private var eventsGlimpse: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            GlimpseHeading(title: "Events") { PatchCalendar(quilt: session.quilt, patch: patch, close: close) }
            if let events {
                if events.isEmpty { Text("No upcoming events.").foregroundStyle(Color.pwTextMuted) }
                ForEach(events.prefix(3)) { event in
                    NavigationLink { EventDetail(quilt: session.quilt, initial: event, close: close) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title).foregroundStyle(Color.pwText)
                            Text(event.dateLabel).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityIdentifier("eventRow")
                }
                // The head states the patch's whole upcoming count and this
                // list is capped at three, so the glimpse has to admit it is
                // a glimpse rather than let the two numbers fight.
                if moreEvents > 0 {
                    NavigationLink { PatchCalendar(quilt: session.quilt, patch: patch, close: close) } label: {
                        Text("\(moreEvents) more upcoming").font(Font.pw.subheadline).inkRow()
                    }
                }
            } else { Text("Pull up to see what’s coming.").foregroundStyle(Color.pwTextMuted) }
        }
    }
    private var moreEvents: Int {
        let shown = events?.prefix(3).count ?? 0
        return max(0, (patch.upcomingEventCount ?? shown) - shown)
    }
    private var membersGlimpse: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            GlimpseHeading(title: roster?.title ?? "Members", trailing: memberTrailing) {
                PatchMemberList(quilt: session.quilt, slug: patch.slug, close: close)
            }
            if let roster {
                if roster.members.isEmpty {
                    Text(roster.emptyMessage).foregroundStyle(Color.pwTextMuted)
                } else {
                    ForEach(roster.members.prefix(4)) { member in
                        PersonRow(name: member.name, initial: member.initial, avatar: member.avatar, role: member.role)
                            .accessibilityIdentifier("memberChip")
                    }
                }
            } else { Text("Pull up to see who’s here.").foregroundStyle(Color.pwTextMuted) }
        }
    }
    /// The total belongs beside a heading that says Members. Beside "Admins"
    /// it would count people the list below deliberately omits.
    private var memberTrailing: String? {
        guard let roster, !roster.adminsOnly, roster.memberCount > roster.members.prefix(4).count else { return nil }
        return String(roster.memberCount)
    }
    private var governanceGlimpse: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            GlimpseHeading(title: "Governance") {
                PatchGovernanceHome(quilt: session.quilt, patch: patch, close: close)
            }
            let docs = documents ?? []
            let open = recordWithheld ? [] : (proposals ?? [])
            if documents == nil && proposals == nil {
                Text("Pull up to see how this patch decides.").foregroundStyle(Color.pwTextMuted)
            } else if docs.isEmpty && open.isEmpty {
                // Two kinds of empty, three sentences. A reader shown only
                // what a patch published must not take it for the whole record.
                Text(governanceEmptyLine).foregroundStyle(Color.pwTextMuted)
            } else {
                ForEach(docs.prefix(3)) { document in
                    NavigationLink { GovernanceDocumentDetail(quilt: session.quilt, initial: document, close: close) } label: {
                        HStack {
                            Text(document.title).foregroundStyle(Color.pwText)
                            Spacer()
                            if let version = document.version { Text("v\(version)").font(Font.pw.caption).foregroundStyle(Color.pwTextMuted) }
                        }
                    }.accessibilityIdentifier("documentChip")
                }
                ForEach(open.prefix(3)) { proposal in
                    NavigationLink { ProposalDetailView(quilt: session.quilt, initial: proposal, close: close) } label: {
                        HStack {
                            Text(proposal.title).foregroundStyle(Color.pwText)
                            Spacer()
                            OutcomeBadge(proposal: proposal)
                        }
                    }.accessibilityIdentifier("proposalChip")
                }
            }
        }
    }
    private var governanceEmptyLine: String {
        if recordWithheld { return "Proposals and decisions here are not public." }
        if documentsPublishedOnly { return "Nothing published yet." }
        return "Nothing recorded yet."
    }
    private func patchLink(_ link: PatchLink) -> URL? {
        // Either column may hold the address: the web renders `url` as the
        // href and `label` as the text, and real patches have filled the two
        // in the other order. Whichever parses as a link is the link.
        for candidate in [link.url, link.label] {
            if let url = URL(string: candidate), url.scheme == "https" || url.scheme == "http", url.host() != nil { return url }
        }
        return nil
    }
    private func linkLabel(_ link: PatchLink) -> String {
        guard let url = patchLink(link) else { return link.label }
        let other = url.absoluteString == link.url ? link.label : link.url
        let trimmed = other.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (url.host() ?? link.url) : trimmed
    }
    private var mapsURL: URL? {
        var parts = URLComponents(string: "https://maps.apple.com/")!
        parts.queryItems = [URLQueryItem(name: "daddr", value: patch.address)]
        return parts.url
    }
    private func load() async {
        error = nil
        do { envelope = try await api.get("nodes/\(initial.slug)") }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    /// What the pull costs: one request per room, and none for About. The
    /// events one carries `from=now`, so a section headed Upcoming can only
    /// hold what is.
    private func loadGlimpses() async {
        glimpsesAsked = true
        let slug = patch.slug
        let claimed = !isUnclaimed
        async let eventPage = try? api.events(slug: slug, limit: 3, from: Date())
        async let memberPage: MemberPage? = claimed ? try? api.get("nodes/\(slug)/members", query: [URLQueryItem(name: "limit", value: "12")]) : nil
        async let documentPage: GovernanceDocumentPage? = claimed ? try? api.get("nodes/\(slug)/governance") : nil
        async let proposalPage: ProposalPage? = claimed ? try? api.get("nodes/\(slug)/proposals", query: [URLQueryItem(name: "limit", value: "3")]) : nil
        let (eventResult, memberResult, documentResult, proposalResult) = await (eventPage, memberPage, documentPage, proposalPage)
        guard !Task.isCancelled else { return }
        events = eventResult?.items ?? []
        if claimed {
            roster = memberResult.map(MemberRoster.init(page:))
            documentsPublishedOnly = documentResult?.publishedOnly ?? false
            documents = documentResult.map { page in (page.items ?? []).filter { liningDiverged || $0.kind != "lining" } }
            recordWithheld = proposalResult?.publicGovernanceRecord == "nobody" || patch.publicGovernanceRecord == "nobody"
            proposals = proposalResult.map { $0.items ?? [] }
        }
        roomsAnswered = true
    }
}

private struct HeadBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct SheetTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
