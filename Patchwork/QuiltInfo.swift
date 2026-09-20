// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// The quilt's information stack, reached from the account menu. The web
/// spreads these over /about, /label, /lining, /governance, /privacy and
/// /terms and links them from a footer on every page; here they are one
/// grouped list a reader can walk, with the quilt's own identity at the head
/// of it. Everything in it is public and readable signed out, which is the
/// whole point — its reader is usually deciding whether to join.
struct QuiltInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            QuiltInfoList()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// The pages of the stack, named once, so a link in one of them can push
/// another without either owning the other's view, and so the footer row
/// pushes the same page from Discover or the list as the stack does. They are
/// destination links rather than values on a path: a `navigationDestination`
/// on a discovery surface re-forms the toolbar that hosts the live search
/// field, and the field loses focus mid-typing.
enum InfoPage: Hashable, Identifiable {
    var id: Self { self }
    case about, label, lining, governance, privacy, terms
    var title: String {
        switch self {
        case .about: return "About"
        case .label: return "The Label"
        case .lining: return "The Lining"
        case .governance: return "How governance works"
        case .privacy: return "Privacy Policy"
        case .terms: return "User Agreement"
        }
    }
    var symbol: String {
        switch self {
        case .about: return "info.circle"
        case .label: return "tag"
        case .lining: return "text.book.closed"
        case .governance: return "building.columns"
        case .privacy: return "hand.raised"
        case .terms: return "doc.plaintext"
        }
    }
    /// A stable name for the row that opens this page, for the UI tests.
    var identifier: String {
        switch self {
        case .about: return "infoAbout"
        case .label: return "infoLabel"
        case .lining: return "infoLining"
        case .governance: return "infoGovernance"
        case .privacy: return "infoPrivacy"
        case .terms: return "infoTerms"
        }
    }
    @ViewBuilder var view: some View {
        switch self {
        case .about: AboutQuiltView()
        case .label: LabelView()
        case .lining: LiningView()
        case .governance: GovernanceView()
        case .privacy: LegalView(doc: .privacy)
        case .terms: LegalView(doc: .terms)
        }
    }
}

struct QuiltInfoList: View {
    @EnvironmentObject private var session: QuiltSession
    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    if let icon = session.icon {
                        Image(uiImage: icon).resizable().aspectRatio(contentMode: .fill).frame(width: 42, height: 42).clipped()
                    } else {
                        QuiltMark()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.quilt.name).font(.headline)
                        Text(session.quilt.url.host() ?? session.quilt.id).font(.subheadline).foregroundStyle(Color.secondary)
                    }
                }.padding(.vertical, 4)
                if let description = session.instance?.description, !description.isEmpty {
                    Text(description).foregroundStyle(Color.secondary)
                }
            }
            Section {
                ForEach([InfoPage.about, .label, .lining, .governance], id: \.self) { page in
                    NavigationLink { page.view } label: { Label(page.title, systemImage: page.symbol) }
                        .accessibilityIdentifier(page.identifier)
                }
            } header: {
                Text("How this quilt is run")
            }
            Section {
                ForEach([InfoPage.privacy, .terms], id: \.self) { page in
                    NavigationLink { page.view } label: { Label(page.title, systemImage: page.symbol) }
                        .accessibilityIdentifier(page.identifier)
                }
            } header: {
                Text("The fine print")
            }
            Section {
                Link(destination: session.quilt.url) { Label("Open quilt website", systemImage: "safari") }
            } footer: {
                if let count = session.instance?.stats?.nodeCount {
                    Text("\(count) \(count == 1 ? "patch" : "patches") on this quilt.")
                }
            }
        }
        .navigationTitle("About this quilt")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The quiet row at the foot of a reading surface, standing in for the web's
/// footer strip on every page. It lives in a list's footer slot and opens its
/// page as a sheet of its own, which is what keeps it a footer: a row of
/// `NavigationLink`s wears a list row's chrome and four chevrons, and a
/// `navigationDestination` on a discovery surface re-forms the toolbar that
/// hosts the live search field.
struct QuiltInfoFooter: View {
    private let pages: [(page: InfoPage, title: String)] =
        [(.label, "The Label"), (.about, "About"), (.privacy, "Privacy"), (.terms, "Terms")]
    @State private var opened: InfoPage?
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(pages.enumerated()), id: \.offset) { index, entry in
                if index > 0 { Text("·").foregroundStyle(Color.secondary) }
                Button(entry.title) { opened = entry.page }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("footer-" + entry.page.identifier)
            }
        }
        .font(.footnote)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 12)
        .textCase(nil)
        .sheet(item: $opened) { page in
            NavigationStack { page.view.modifier(SheetDone()) }
        }
    }
}

/// A pushed page opened straight from a footer has no stack behind it to go
/// back to, so it carries its own way out.
private struct SheetDone: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View {
        content.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

/// Orientation, not disclosure: what a Patchwork is and how this one works,
/// handing off to the Label for who runs it and what it costs. The prose is
/// the project's, the same on every quilt; the only thing the quilt says in
/// its own voice is its description, which is quoted as its own.
struct AboutQuiltView: View {
    @EnvironmentObject private var session: QuiltSession
    private let whatIsThis = """
        A Patchwork is a hyper-local-by-design platform built to enable discovery, connection, and \
        community building without relying on billionaire owned, algorithm powered, \
        attention-economy-buttressed apps and social media sites. Patchwork is an open source \
        codebase that can be hosted by anyone. No ads and no monetization strategy.
        """
    private let howItWorks = """
        Every community, group, or entity on the quilt is a patch. It could be a music venue, a food \
        bank, a local union chapter, an artist, a coalition, a band — you get the picture. Every patch \
        is equal in its ability to use the features of the platform and in its discoverability, though \
        some patches may grow or move depending on their activity or their relationships to other patches.

        You can interact with patches in a few ways:

        - Follow a patch to see events and public notifications from it in your own personal quilt.
        - Join a patch as a member to be involved in non-public activities.
        - Create or manage a patch to update members, document policies, and even run internal elections and governance.

        Patches are arranged on the quilt near other patches that share members, followers, and events. \
        Patchwork also has a robust governance system that lets patches elect leaders, vote on policies, \
        and attest to shared values.
        """
    private let whereFrom = """
        Patches are created either by their owner or as "unclaimed" by an admin or a community \
        suggestion. Unclaimed patches can be acquired and verified by their owners. However, any claimed \
        patch must make a choice: adopt the lining, or adopt and then publicly dissent. The lining is the \
        baseline commitment that Patchwork expects, and any dissent or modification of it will not result \
        in a ban, but instead a brand. Patchwork was designed to be a community building tool, and \
        therefore has intentional biases towards fostering community according to values held by the \
        contributors. Neighbors with differing values are welcome to use the tools, as they are welcome to \
        participate in society and use shared public infrastructure, but the admins will take steps to \
        enforce rules or remove individuals and entities if a significant breach occurs.

        A patch's presence on this quilt does not indicate an endorsement by this Patchwork or the people \
        who run it. It only means the person, place, or group exists and that somebody recorded it, like a \
        modern phone book. Nothing reaches your personal quilt except the patches you choose to follow, and \
        anything that has no business being here at all can be reported to the admins.
        """
    private let different = """
        - No ads, and no data collection beyond what the platform needs to function.
        - No algorithm that decides what you should see.
        - Run by community members.
        - Creating a patch requires adopting the lining, and amendments to it for your community are public.
        - Leaving is made intentionally easy. If this place is not for you, but you like some of it, take it \
        with you and start another quilt. It's open source, and this quilt's data can be exported whole and \
        stood up somewhere else.
        """
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What is \(session.quilt.name)?").font(.title.bold())
                    if let count = session.instance?.stats?.nodeCount, count > 0 {
                        Text("\(count) \(count == 1 ? "patch" : "patches") on the quilt right now.")
                            .font(.subheadline).foregroundStyle(Color.secondary)
                    }
                }
                section("What is this?") {
                    MarkdownText(source: whatIsThis)
                    // The instance's own words, and the only place on this page
                    // a quilt speaks for itself — attributed rather than blended
                    // into the project's prose, so a reader can tell which is which.
                    if let description = session.instance?.description, !description.isEmpty {
                        Text("This quilt describes itself as:").font(.subheadline).foregroundStyle(Color.secondary)
                        Text(description)
                            .padding(.leading, 12)
                            .overlay(alignment: .leading) { Rectangle().frame(width: 3).foregroundStyle(Color(.separator)) }
                    }
                }
                section("How does it work?") {
                    MarkdownText(source: howItWorks)
                    NavigationLink("How governance works") { InfoPage.governance.view }
                }
                section("Where do patches come from?") {
                    MarkdownText(source: whereFrom)
                    NavigationLink("Read the lining") { InfoPage.lining.view }
                }
                section("What makes Patchwork different") {
                    MarkdownText(source: different)
                }
                LabelGist()
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    Link("Patchwork is open source. Start your own quilt", destination: URL(string: "https://github.com/nathanswavely/patchwork")!)
                        .font(.footnote)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("About").navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            content()
        }
    }
}

/// The Label's gist on the About page: who stewards this quilt and roughly
/// what it costs, with the way through to the full statement. It renders
/// nothing until a Label is published — an empty disclosure is not worth chrome.
struct LabelGist: View {
    @EnvironmentObject private var session: QuiltSession
    @State private var label: QuiltLabel?
    var body: some View {
        Group {
            if let label, label.published == true {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Who runs this").font(.headline)
                    Text(stewardLine(label)).font(.subheadline).foregroundStyle(Color.secondary)
                    if let total = label.totalMonthlyMinor, total > 0 {
                        Text("About \(QuiltLabel.money(total, label.currency))/month to keep running")
                            .font(.subheadline).foregroundStyle(Color.secondary)
                    }
                    NavigationLink("Read the Label") { InfoPage.label.view }.font(.subheadline)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .task { if label == nil { label = try? await session.api.get("label") } }
    }
    private func stewardLine(_ label: QuiltLabel) -> String {
        let stewards = label.stewards ?? []
        guard let first = stewards.first else { return "Stewarded by this quilt's admins" }
        let name = "@" + first.username
        return stewards.count == 1 ? "Stewarded by \(name)" : "Stewarded by \(name) +\(stewards.count - 1)"
    }
}

/// The lining, fetched from `instance/lining` and read as markdown.
struct LiningView: View {
    @EnvironmentObject private var session: QuiltSession
    @State private var lining: Lining?
    @State private var failure: String?
    var body: some View {
        DocumentScroll(failure: failure, ready: lining != nil) {
            VStack(alignment: .leading, spacing: 16) {
                Text(lining?.title ?? "The Lining").font(.title.bold())
                Text("The shared baseline every patch on this quilt starts from. A patch can amend its copy; amendments are public, and a patch that diverges is flagged publicly.")
                    .font(.subheadline).foregroundStyle(Color.secondary)
                if let body = lining?.body, !body.isEmpty { MarkdownText(source: body, base: session.quilt.url) }
            }
        }
        .navigationTitle("The Lining").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        guard lining == nil else { return }
        do { lining = try await session.api.get("instance/lining") }
        catch { failure = error.localizedDescription }
    }
}

/// A legal document. The server always has something to serve — a default
/// ships with the software and the stewards can replace it — so this has a
/// loading and an error state and no empty one.
struct LegalView: View {
    enum Doc: String { case privacy, terms }
    let doc: Doc
    @EnvironmentObject private var session: QuiltSession
    @State private var document: LegalDocument?
    @State private var failure: String?
    private var fallbackTitle: String { doc == .privacy ? "Privacy Policy" : "User Agreement" }
    var body: some View {
        DocumentScroll(failure: failure, ready: document != nil) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("The fine print").font(.caption.weight(.bold)).foregroundStyle(Color.accentColor).textCase(.uppercase)
                    Text(document?.title ?? fallbackTitle).font(.title.bold())
                    // Only a document the stewards actually replaced has an
                    // update worth dating; the shipped default's timestamp
                    // would be the software's, not this quilt's.
                    if let day = document?.updatedDay {
                        Text("Last updated \(day).").font(.subheadline).foregroundStyle(Color.secondary)
                    }
                }
                if let markdown = document?.markdown, !markdown.isEmpty {
                    MarkdownText(source: markdown, base: session.quilt.url)
                }
                Divider()
                HStack(spacing: 6) {
                    Text("Also see the").font(.footnote).foregroundStyle(Color.secondary)
                    NavigationLink(doc == .privacy ? "User Agreement" : "Privacy Policy") {
                        (doc == .privacy ? InfoPage.terms : InfoPage.privacy).view
                    }.font(.footnote)
                }
            }
        }
        .navigationTitle(fallbackTitle).navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        guard document == nil else { return }
        do { document = try await session.api.get("legal/\(doc.rawValue)") }
        catch { failure = error.localizedDescription }
    }
}

/// The scroll every fetched document wears, with its loading and failure states.
struct DocumentScroll<Content: View>: View {
    let failure: String?
    let ready: Bool
    @ViewBuilder let content: () -> Content
    var body: some View {
        Group {
            if let failure {
                ContentUnavailableView {
                    Label("Couldn’t load this", systemImage: "doc.questionmark")
                } description: { Text(failure) }
            } else if !ready {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    content().padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// How governance works: the project's own prose, fixed and shipped, the
/// lining's model rather than the legal documents'. A description of what the
/// software does is the project's claim, and an instance that could edit it
/// could narrate behaviour it does not control. The spine is the three axes a
/// patch configures — who decides, how a decision is made, who leads — and
/// then what every patch starts from.
struct GovernanceView: View {
    private let standfirst = """
        Every patch runs itself. A band never has to think about any of this, and a coalition of forty \
        people can hold real votes with a real record. Both are the same software; what differs is how \
        much of it a patch switches on.
        """
    private let whoDecides = """
        A patch's electorate is its active admins and members, once they have been there as long as that \
        patch asks. Followers are not in it. Following is meant to be frictionless and costs nothing, so \
        it carries no say in what the patch does, and becoming a member is the step that changes that.

        A patch can let its followers read along with proposals and comment on them. It cannot give them a vote.
        """
    private let howDecided = """
        Patches sit in one of three places, and they are genuinely different.

        **An admin decides.** The change is applied the moment it is made. It still lands in the patch's \
        governance history where members can see it, but nobody was asked. Most small patches live here \
        and should.

        **The patch votes.** A proposal opens for voting the moment it is raised, and discussion happens \
        alongside the vote rather than in a stage before it. When voting opens, the rules the vote runs \
        under are fixed for its whole life: who may vote, how many of them have to turn out, and what \
        carries it. A patch can change its rules while a vote is running, and that vote still finishes \
        under the rules it started with. You do not get to use the new rules to pass the change to the new rules.

        What carries a proposal is the patch's own setting: a majority, a two-thirds supermajority, or full consensus.

        **The decision happens somewhere else.** Some communities decide at a meeting, on a show of hands, \
        in a room with no software in it. A patch can say so, and then record what was decided as an \
        attestation: the membership decided this, elsewhere, on this date. Patchwork cannot check that \
        claim and does not pretend to. It records who asserted what, in public, and a mistaken record is \
        corrected by a later one rather than quietly edited.
        """
    private let whoLeads = """
        Admins run a patch. How someone becomes one is the patch's third choice, and each answer brings \
        its own mechanics.

        **A maintainer** keeps the patch and names their own successor. **Meritocratic** patches follow \
        the open source pattern: admins nominate from active members when the patch needs another, and \
        the community ratifies. **Elected** patches are the only ones with seats and terms, filled by an \
        election that comes round on a calendar. An election is an ordinary proposal underneath, with the \
        same electorate and the same rules fixed at open; the electorate approves as many candidates as \
        it likes and the most-approved take the open seats.

        A term running out never removes anyone. The seat shows publicly that it is overdue and its \
        holder keeps serving until a successor is elected, because a clock should not be able to leave a \
        community leaderless.
        """
    private let startsFrom = """
        Whatever it chooses, a patch begins by adopting the lining, the baseline this whole quilt shares. \
        A patch can write its own charters on top of it and can amend its copy of the lining itself, and \
        if it does, that is public on the patch and it wears a badge saying so.

        Charters are the community's own words, and they can promise things no software enforces. That is \
        legitimate and it is where such promises belong. This page only describes what Patchwork itself does.
        """
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("How governance works").font(.title.bold())
                    Text(standfirst).foregroundStyle(Color.secondary)
                }
                section("Who decides", standfirst: whoDecides)
                section("How a decision gets made", standfirst: howDecided)
                section("Who leads", standfirst: whoLeads)
                VStack(alignment: .leading, spacing: 12) {
                    Text("What every patch starts from").font(.title3.bold())
                    MarkdownText(source: startsFrom)
                    NavigationLink("Read the lining") { InfoPage.lining.view }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    Text("This is about how the patches here govern themselves. For who runs this quilt and what it costs to keep on, read the Label.")
                        .font(.footnote).foregroundStyle(Color.secondary)
                    NavigationLink("The Label") { InfoPage.label.view }.font(.footnote)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Governance").navigationBarTitleDisplayMode(.inline)
    }
    private func section(_ title: String, standfirst: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            MarkdownText(source: standfirst)
        }
    }
}
