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
    ///
    /// `hardBreaks` is for what a person typed into a box rather than wrote
    /// as a document — a notice, a reply. The web renders those with
    /// `breaks: true`, so a single return is a line of its own there, and a
    /// three-line address must not arrive here as one run-on sentence.
    static func blocks(_ source: String, hardBreaks: Bool = false) -> [Block] {
        let joiner = hardBreaks ? "\n" : " "
        var blocks: [Block] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbers: [String] = []
        var quote: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: joiner))); paragraph = [] }
            if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
            if !numbers.isEmpty { blocks.append(.numbers(numbers)); numbers = [] }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: joiner))); quote = [] }
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
    ///
    /// Emphasis is set here rather than left to `Text`. Given an emphasised
    /// run, `Text` asks its font for a bold or italic version of itself, and
    /// the bundled variable fonts have neither to give: the run comes back in
    /// the system face at the system's size. So each emphasised run carries
    /// its own font — the block's face and size, at the strong weight or
    /// through the italic shear — and the intent that would make `Text` try
    /// again is taken off it.
    static func inline(_ text: String, base: URL? = nil, setting: PWTextSetting = .body) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard var parsed = try? AttributedString(markdown: text, options: options, baseURL: base) else {
            return AttributedString(text)
        }
        // A link inside a sentence is ink like the sentence, so the underline
        // is what marks it. Colour would put the app back where it started:
        // tinted phrases scattered through prose.
        for run in parsed.runs where run.link != nil {
            parsed[run.range].underlineStyle = .single
        }
        for run in parsed.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            let strong = intent.contains(.stronglyEmphasized)
            let emphasized = intent.contains(.emphasized)
            guard strong || emphasized else { continue }
            parsed[run.range].font = Font(setting.uiFont(strong: strong, emphasized: emphasized))
            let rest = intent.subtracting([.stronglyEmphasized, .emphasized])
            parsed[run.range].inlinePresentationIntent = rest.isEmpty ? nil : rest
        }
        return parsed
    }

    /// The scale a heading is set in, by its level.
    static func setting(forHeading level: Int) -> PWTextSetting {
        level <= 1 ? .title2 : (level == 2 ? .title3 : .headline)
    }
}

/// A markdown document as native reading text.
struct MarkdownText: View {
    let source: String
    var base: URL?
    /// A single return is a line break (see `Markdown.blocks`).
    var hardBreaks = false
    /// Read so the document is set again when the text size changes: the
    /// emphasised runs carry fonts of their own, sized when they are made.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var blocks: [Markdown.Block] { Markdown.blocks(source, hardBreaks: hardBreaks) }
    var body: some View {
        let _ = dynamicTypeSize
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    let setting = Markdown.setting(forHeading: level)
                    Text(Markdown.inline(text, base: base, setting: setting))
                        .font(setting.font)
                        .foregroundStyle(Color.pwText)
                        .padding(.top, 4)
                case .paragraph(let text):
                    Text(Markdown.inline(text, base: base)).font(Font.pw.body)
                case .bullets(let items):
                    itemList(items) { _ in Text("•") }
                case .numbers(let items):
                    itemList(items) { index in Text("\(index + 1).") }
                case .quote(let text):
                    Text(Markdown.inline(text, base: base))
                        .font(Font.pw.body)
                        .foregroundStyle(Color.pwTextMuted)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) { Rectangle().frame(width: 3).foregroundStyle(Color.pwBorder) }
                case .rule:
                    Divider().overlay(Color.pwBorder)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A link inside prose cannot carry an arrow of its own, so it is
        // ink like the rest of the sentence and underlined where it runs.
        .tint(Color.pwText)
    }
    @ViewBuilder private func itemList(_ items: [String], marker: @escaping (Int) -> Text) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(index).font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                    // Inside a `List` row a bullet is offered one line and
                    // takes it, ending in an ellipsis, unless it is told its
                    // height is its own to decide.
                    Text(Markdown.inline(item, base: base)).font(Font.pw.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
