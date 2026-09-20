// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// The small pieces the profile's rooms share, so a patch has one face and it
/// cannot drift between the glimpse and the screen it opens.

/// A glimpse's heading, which is itself the door into the room (web ADR 042).
/// There is never a separate pill named for the container.
struct GlimpseHeading<Destination: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder var destination: () -> Destination
    var body: some View {
        NavigationLink(destination: destination) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Font.pw.headline).foregroundStyle(Color.pwText)
                if let trailing { Text(trailing).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted) }
                Spacer()
                Image(systemName: "chevron.right").font(Font.pw.footnoteSemibold).foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .accessibilityIdentifier("glimpseDoor-\(title)")
    }
}

/// A heading that names identity rather than a room, so it stays inert.
struct StaticHeading: View {
    let title: String
    var body: some View { Text(title).font(Font.pw.headline) }
}

/// One person, rendered the same way wherever they are named.
struct PersonRow: View {
    let name: String
    let initial: String
    let avatar: URL?
    var role: String? = nil
    var detail: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            AvatarMark(initial: initial, avatar: avatar)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                if let detail { Text(detail).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted) }
            }
            Spacer(minLength: 8)
            if let role, !role.isEmpty {
                Text(role.capitalized)
                    .font(Font.pw.caption2Semibold)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(.secondarySystemFill), in: Capsule())
                    .foregroundStyle(Color.pwTextMuted)
                    .accessibilityLabel("Role: \(role)")
            }
        }
        .padding(.vertical, 2)
    }
}

struct AvatarMark: View {
    let initial: String
    let avatar: URL?
    var side: CGFloat = 34
    var body: some View {
        Group {
            if let avatar {
                AsyncImage(url: avatar) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { placeholder }
            } else { placeholder }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Text(initial).font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwTextMuted)
        }
    }
}

/// A proposal's outcome in one word. Red is reserved for a decision the patch
/// actually made; a lapse or an unsettled contest is an absence and keeps the
/// muted default (web ADR 097).
struct OutcomeBadge: View {
    let proposal: Proposal
    var body: some View {
        Text(proposal.outcome)
            .font(Font.pw.caption2Semibold)
            .textCase(.uppercase)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
    private var tint: Color {
        if proposal.outcomeIsDecision { return .red }
        if proposal.outcomeIsOpen { return .pwAccent }
        return .secondary
    }
}

/// A governance document's body. Enough Markdown to read a charter — the
/// headings it is written with and its paragraphs — and nothing that pretends
/// to be a full renderer.
struct DocumentBody: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block.level {
                case 1: Text(block.text).font(Font.pw.title3)
                case 2: Text(block.text).font(Font.pw.headline)
                case 3: Text(block.text).font(Font.pw.subheadlineSemibold)
                default: Text(block.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private struct Block { let level: Int; let text: String }
    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        func flush() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { result.append(Block(level: 0, text: joined)) }
            paragraph = []
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#") {
                flush()
                let hashes = line.prefix { $0 == "#" }.count
                result.append(Block(level: min(hashes, 3), text: String(line.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)))
                continue
            }
            paragraph.append(line)
        }
        flush()
        return result
    }
}

/// The line this app keeps honest: nothing here signs anyone in, so nothing
/// here offers to.
struct WebsiteOnlyNote: View {
    let text: String
    var body: some View {
        Text(text).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
    }
}
