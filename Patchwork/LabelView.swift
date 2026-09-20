// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// The Label (docs/adr/023): the quilt's public statement of how it is run
/// and paid for. Readable signed out — its most important reader has no
/// account yet.
///
/// Solo-first, the way the web leads: one steward and it opens with their
/// name and their own words; more and it opens with the roster. Same data,
/// the layout just leads with whoever is smallest in number.
struct LabelView: View {
    @EnvironmentObject private var session: QuiltSession
    @State private var label: QuiltLabel?
    @State private var failure: String?
    private var stewards: [QuiltLabel.Steward] { label?.stewards ?? [] }
    private var items: [QuiltLabel.CostItem] { label?.costItems ?? [] }
    var body: some View {
        DocumentScroll(failure: failure, ready: label != nil) {
            if let label, label.published == true {
                published(label)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No Label yet").font(.title.bold())
                    Text("Nobody has written this quilt’s Label yet.").foregroundStyle(Color.secondary)
                }
            }
        }
        .navigationTitle("The Label").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        guard label == nil else { return }
        do { label = try await session.api.get("label") }
        catch { failure = error.localizedDescription }
    }

    @ViewBuilder private func published(_ label: QuiltLabel) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("The Label").font(.caption.weight(.bold)).foregroundStyle(Color.accentColor).textCase(.uppercase)
                Text("How \(session.quilt.name) is run").font(.title.bold())
                Text("Quilts carry a label on the back that says who made them and when. This is ours.")
                    .font(.subheadline).foregroundStyle(Color.secondary)
            }
            if !stewards.isEmpty { stewardRoster }
            if let prose = label.prose, !prose.isEmpty { MarkdownText(source: prose, base: session.quilt.url) }
            costs(label)
            links(label)
            if let from = label.seamrippedFromName, !from.isEmpty { seamripped(label, from: from) }
            theDoor(label)
        }
        .accessibilityIdentifier("labelPage")
    }

    /// Stewards are people, not rows of metadata; a solo steward gets the
    /// whole width and their blurb reads as their own words.
    private var stewardRoster: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(stewards) { steward in
                HStack(alignment: .top, spacing: 12) {
                    StewardAvatar(steward: steward)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(steward.title).font(.headline)
                        Text("@" + steward.username).font(.subheadline).foregroundStyle(Color.secondary)
                        if let blurb = steward.blurb, !blurb.isEmpty { Text(blurb).font(.subheadline) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    /// What this runs on. Ungated: the software is a material whether or not
    /// the stewards have typed in what the services cost.
    @ViewBuilder private func costs(_ label: QuiltLabel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What this runs on").font(.title3.bold())
            if !items.isEmpty {
                if label.stale == true {
                    Label {
                        Text("These figures haven’t been reviewed since \(label.statedOn ?? "they were stated"). They may be out of date.")
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("labelStale")
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.service ?? "—").font(.headline)
                                Spacer(minLength: 8)
                                Text(QuiltLabel.money(item.amountMinor, label.currency) + item.periodWord)
                                    .font(.subheadline.monospacedDigit())
                            }
                            if let purpose = item.purpose, !purpose.isEmpty {
                                Text(purpose).font(.subheadline).foregroundStyle(Color.secondary)
                            }
                            if let why = item.why, !why.isEmpty {
                                Text(why).font(.footnote).foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("About \(QuiltLabel.money(label.totalMonthlyMinor, label.currency))/month to keep running").font(.headline)
                    Text("The stewards typed these numbers in themselves. Nobody audits this.")
                        .font(.footnote).foregroundStyle(Color.secondary)
                }
            }
            // The version and the two cross-quilt capabilities, each stated in
            // both directions (docs/adr/061): they are materials the quilt is
            // made of, not settings a reader is being offered.
            VStack(alignment: .leading, spacing: 4) {
                if let version = label.version, !version.isEmpty {
                    Text("Running Patchwork \(version).").font(.footnote).foregroundStyle(Color.secondary)
                }
                Text(label.federation == true
                     ? "Federating. Public patches here can be followed from Mastodon and other ActivityPub sites."
                     : "Not federating. Patches here can’t be followed from other sites.")
                    .font(.footnote).foregroundStyle(Color.secondary)
                Text(label.multiQuilt == true
                     ? "Readable by other quilts. Their sites can show this quilt’s public patches and events alongside their own."
                     : "Not readable by other quilts. They can link here, but people have to follow the link to see anything.")
                    .font(.footnote).foregroundStyle(Color.secondary)
            }
        }
    }

    @ViewBuilder private func links(_ label: QuiltLabel) -> some View {
        let support = label.supportUrl.flatMap(webLink)
        let feedback = label.feedbackUrl.flatMap(webLink)
        if support != nil || feedback != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let support { Link(destination: support) { Label("Support this quilt", systemImage: "cup.and.saucer") } }
                if let feedback { Link(destination: feedback) { Label("Send feedback", systemImage: "bubble.left.and.bubble.right") } }
            }
        }
    }

    @ViewBuilder private func seamripped(_ label: QuiltLabel, from: String) -> some View {
        Group {
            if let url = label.seamrippedFromUrl.flatMap(webLink) {
                VStack(alignment: .leading, spacing: 4) {
                    Link(from, destination: url)
                    Text("This quilt started as a fork of it.").font(.footnote).foregroundStyle(Color.secondary)
                }
            } else {
                Text("Seamripped from \(from). This quilt started as a fork of it.")
                    .font(.footnote).foregroundStyle(Color.secondary)
            }
        }
    }

    /// The door. Knowing what a quilt is made of is what makes leaving
    /// actionable — the Label always says where the exit is.
    @ViewBuilder private func theDoor(_ label: QuiltLabel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Label("If you don’t like how this is run", systemImage: "scissors").font(.title3.bold())
            Text("Real people run this, and real people sometimes run things poorly, so the exit is built in. Any member can export what they can already see and start the community over somewhere else, under different stewards.")
            if label.federation == true {
                Text("Only the community travels: members, events, charters, and the threads between patches. This quilt’s addresses do not. A patch that leaves keeps its people and starts over with the followers it had on other sites.")
                    .font(.footnote).foregroundStyle(Color.secondary)
            }
        }
    }

    /// A steward's link and a support link are the quilt's, not ours; only an
    /// https address is followed.
    private func webLink(_ value: String) -> URL? {
        guard !value.isEmpty, let url = URL(string: value), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }
}

/// A steward's avatar, or their initial when they have none. Loaded straight
/// from the quilt that named them and never from anywhere else.
private struct StewardAvatar: View {
    let steward: QuiltLabel.Steward
    var body: some View {
        Group {
            if let value = steward.avatarUrl, !value.isEmpty, let url = URL(string: value), url.scheme?.lowercased() == "https" {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    initial
                }
            } else {
                initial
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
    private var initial: some View {
        ZStack {
            Circle().fill(Color(.tertiarySystemGroupedBackground))
            Text(String(steward.title.replacingOccurrences(of: "@", with: "").prefix(1)).uppercased()).font(.headline)
        }
    }
}
