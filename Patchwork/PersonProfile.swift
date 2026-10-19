// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// A person's profile (web `UserProfile`), pushed from wherever somebody is
/// named with a username: the members room, a slate, a ballot, a notice, the
/// council, the Label's stewards. The web's order, top to bottom — who they
/// are, where they moved, the one act (Edit profile on your own, Report on
/// anybody else's), how to reach them, their links, the patches they run,
/// the patches they belong to — and the web's empty state where there is
/// none of it.
///
/// A patch named here opens as every patch does, docked over the quilt; a
/// screen presented in a sheet of its own says how through `patchDoor`.
struct PersonProfile: View {
    @EnvironmentObject private var session: QuiltSession
    @Environment(\.patchDoor) private var patchDoor
    let quilt: Quilt
    let username: String
    var close: (() -> Void)? = nil

    @State private var person: Person?
    @State private var loading = false
    /// The server's 404, in its own words: unknown, suspended or deleted,
    /// which it deliberately does not tell apart.
    @State private var notFound: String?
    @State private var error: String?
    @State private var reporting: ReportTarget?

    private var api: PatchworkAPI { PatchworkAPI(base: quilt.url) }
    /// Signed in to the quilt this person is on. A profile read from another
    /// quilt is the public one, and takes no act from here.
    private var signedIn: Bool { quilt.url == session.quilt.url && session.me != nil }
    private var isSelf: Bool { signedIn && session.me?.username == username }

    var body: some View {
        List {
            // One Group so every section's rows take the card surface.
            Group {
            if let person {
                head(person)
                if !person.contact.isEmpty { reach(person) }
                let links = person.openableLinks
                if !links.isEmpty {
                    Section {
                        ForEach(links, id: \.self) { link in
                            Link(destination: link.url) { Text(link.title).font(Font.pw.body) }
                                .exitLink()
                                .accessibilityIdentifier("personLink")
                        }
                    } header: { heading("Links") }
                }
                if !person.runs.isEmpty { patches("Runs", person.runs) }
                if !person.memberOf.isEmpty { patches("Member of", person.memberOf) }
                if person.isEmpty { empty }
            } else if loading {
                ProgressView("Loading…")
            }
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
        .overlay {
            if let notFound {
                ContentUnavailableView {
                    Label(People.notFoundTitle, systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text(notFound).font(Font.pw.body)
                }
                .accessibilityIdentifier("personNotFound")
            }
        }
        .navigationTitle(person?.name ?? username).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: api.webURL("users/\(username)")).accessibilityIdentifier("sharePerson")
            }
        }
        .sheet(item: $reporting) { ReportSheet(target: $0, api: api) }
        .task { if person == nil { await load() } }
        .refreshable { await load() }
        // Signing in or out changes the contact card and the acts.
        .onChange(of: session.me?.id) { _, _ in Task { await load() } }
    }

    // MARK: The head

    private func head(_ person: Person) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                AvatarMark(initial: person.initial, avatar: person.avatar, side: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(person.name).font(Font.pw.title2).foregroundStyle(Color.pwText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("personName")
                    Text(person.handleLine).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                        .accessibilityIdentifier("personHandle")
                }
                let bio = person.bio.trimmingCharacters(in: .whitespacesAndNewlines)
                if !bio.isEmpty {
                    Text(bio).font(Font.pw.body).foregroundStyle(Color.pwText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("personBio")
                }
            }
            .padding(.vertical, 6)
            if let moved = People.moved(person.movedTo) { movedNotice(moved) }
            act(person)
        }
    }

    /// Their own pointer, independent of any patch they belong to. A
    /// pointer at a patch on another quilt also opens that patch here, as
    /// the web's does; a person's pointer seldom is one.
    @ViewBuilder private func movedNotice(_ moved: (url: URL, host: String)) -> some View {
        Link(destination: moved.url) {
            Label(People.movedLine(moved.host), systemImage: "arrow.uturn.right").font(Font.pw.subheadline)
        }
        .exitLink()
        .accessibilityIdentifier("personMoved")
        if let patch = MovedElsewhere(moved.url.absoluteString) {
            NavigationLink { RemotePatchView(host: patch.host, slug: patch.slug, close: close) } label: {
                Text("Open the new patch here").font(Font.pw.subheadline)
            }
            .accessibilityIdentifier("personMovedPatch")
        }
    }

    /// One act, the web's: your own profile is edited in Settings' own
    /// Profile page, pushed here; anybody else's can be reported, by a
    /// reader who is signed in.
    @ViewBuilder private func act(_ person: Person) -> some View {
        if isSelf {
            NavigationLink { ProfileSettings() } label: {
                Label("Edit profile", systemImage: "pencil").font(Font.pw.subheadlineMedium).foregroundStyle(Color.pwText)
            }
            .accessibilityIdentifier("personEdit")
        } else if signedIn, !person.id.isEmpty {
            Button {
                reporting = ReportTarget(kind: .user, id: person.id, subject: person.name)
            } label: {
                Text("Report").font(Font.pw.subheadlineMedium).inkAction("flag")
                    .frame(minHeight: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Report this person")
            .accessibilityIdentifier("personReport")
        }
    }

    // MARK: Reaching them

    /// Absent entirely for a reader who is shown nothing: an empty heading
    /// would tell the world a card exists.
    private func reach(_ person: Person) -> some View {
        Section {
            Text(People.reachExplanation(isSelf: isSelf))
                .font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(person.contact) { item in contactRow(item) }
        } header: {
            heading(People.reachHeading(person.name)).accessibilityIdentifier("personReach")
        }
    }

    private func contactRow(_ item: ContactItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Group {
                if let symbol = item.symbol { Label(item.word, systemImage: symbol) } else { Text(item.word) }
            }
            .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if let url = item.link {
                    Link(destination: url) { Text(item.value).font(Font.pw.body).underline() }
                        .foregroundStyle(Color.pwText)
                } else {
                    Text(item.value).font(Font.pw.body).foregroundStyle(Color.pwText).textSelection(.enabled)
                }
                if !item.label.isEmpty {
                    Text(" · \(item.label)").font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("contactRow")
    }

    // MARK: Their patches

    private func patches(_ title: String, _ rows: [PersonMembership]) -> some View {
        Section {
            ForEach(rows) { membership in
                Button { open(membership.nodeSlug) } label: {
                    HStack(spacing: 8) {
                        Text(membership.title).font(Font.pw.body).foregroundStyle(Color.pwText)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Text(membership.role)
                            .chipFace()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Color.pwTextMuted)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(membership.nodeSlug.isEmpty)
                .accessibilityLabel("\(membership.title), \(membership.role)")
                .accessibilityHint("Opens this patch’s profile")
                .accessibilityIdentifier("personPatch-\(membership.nodeSlug)")
            }
        } header: { heading(title) }
    }

    private func open(_ slug: String) {
        guard !slug.isEmpty else { return }
        if let patchDoor { patchDoor(slug) } else { Task { await session.openFromProfile(slug: slug) } }
    }

    // MARK: Nothing here

    private var empty: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(People.emptyLine).font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                    .accessibilityIdentifier("personEmpty")
                if isSelf {
                    // Plain text rather than a door: the page that hides and
                    // shows memberships is Settings' own, and it is reached
                    // from there.
                    Text(People.hiddenHint).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("personHiddenHint")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted).textCase(nil)
    }

    // MARK: Reading

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            person = try await api.person(username)
            notFound = nil
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            if (error as? APIError)?.httpStatus == 404 {
                person = nil
                notFound = ProposalDetailView.sentence(error, fallback: "There is nobody here by that name.")
            } else if person == nil {
                self.error = "This profile could not be loaded."
            }
        }
    }
}
