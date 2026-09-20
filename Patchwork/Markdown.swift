// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// The small block-level reader the quilt's own documents are written for:
/// headings, paragraphs, lists, quotes and rules. Blocks are split here and
/// each one's inline run — emphasis, code and links — is handed to
/// `AttributedString(markdown:)`, which is also what makes a document grow
/// with Dynamic Type instead of being one pre-sized wall of text.
///
/// A whole-document `AttributedString` would flatten every heading and bullet
/// into one paragraph, which is exactly the structure these documents use to
/// be readable. Block splitting is the part worth owning; inline parsing is
/// not.
enum Markdown {
    enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullets([String])
        case numbers([String])
        case quote(String)
        case rule
    }

    /// Split a document into blocks. A blank line ends whatever was open;
    /// consecutive plain lines are one paragraph, the way markdown wraps.
    static func blocks(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbers: [String] = []
        var quote: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
            if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
            if !numbers.isEmpty { blocks.append(.numbers(numbers)); numbers = [] }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: " "))); quote = [] }
        }
        for rawLine in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if isRule(line) { flush(); blocks.append(.rule); continue }
            if let heading = heading(line) { flush(); blocks.append(heading); continue }
            if let item = listItem(line, markers: ["- ", "* ", "+ "]) {
                if !paragraph.isEmpty || !numbers.isEmpty || !quote.isEmpty { flush() }
                bullets.append(item)
                continue
            }
            if let item = numberedItem(line) {
                if !paragraph.isEmpty || !bullets.isEmpty || !quote.isEmpty { flush() }
                numbers.append(item)
                continue
            }
            if line.hasPrefix(">") {
                if !paragraph.isEmpty || !bullets.isEmpty || !numbers.isEmpty { flush() }
                quote.append(line.dropFirst().trimmingCharacters(in: .whitespaces))
                continue
            }
            if !bullets.isEmpty || !numbers.isEmpty || !quote.isEmpty { flush() }
            paragraph.append(line)
        }
        flush()
        return blocks
    }

    private static func isRule(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        return ["-", "*", "_"].contains { marker in line.allSatisfy { $0 == Character(marker) } }
    }

    private static func heading(_ line: String) -> Block? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") else { return nil }
        return .heading(level: hashes, text: line.dropFirst(hashes).trimmingCharacters(in: .whitespaces))
    }

    private static func listItem(_ line: String, markers: [String]) -> String? {
        for marker in markers where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numberedItem(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    /// One block's inline run. A relative link — these documents link to
    /// `/label` and `/lining` — resolves against the quilt it came from.
    static func inline(_ text: String, base: URL? = nil) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options, baseURL: base)) ?? AttributedString(text)
    }
}

/// A markdown document as native reading text.
struct MarkdownText: View {
    let source: String
    var base: URL?
    private var blocks: [Markdown.Block] { Markdown.blocks(source) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    Text(Markdown.inline(text, base: base))
                        .font(level <= 1 ? .title2.bold() : (level == 2 ? .title3.bold() : .headline))
                        .padding(.top, 4)
                case .paragraph(let text):
                    Text(Markdown.inline(text, base: base))
                case .bullets(let items):
                    itemList(items) { _ in Text("•") }
                case .numbers(let items):
                    itemList(items) { index in Text("\(index + 1).") }
                case .quote(let text):
                    Text(Markdown.inline(text, base: base))
                        .foregroundStyle(Color.secondary)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) { Rectangle().frame(width: 3).foregroundStyle(Color(.separator)) }
                case .rule:
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(Color.accentColor)
    }
    @ViewBuilder private func itemList(_ items: [String], marker: @escaping (Int) -> Text) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(index).foregroundStyle(Color.secondary)
                    Text(Markdown.inline(item, base: base)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
