// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import UIKit

// Whether AI made a post (web ADR 2026-10-20, "A post says whether AI made
// it"). The surfaces that publish — events, patches, proposals, notices —
// ask one question with three answers, and an image is asked on its own,
// because a flyer's artwork and its words are often made by different hands.
// Nothing is preselected and silence is never an answer (web ADR 082): an
// unanswered question is nil, and nil is sent as nothing at all. Only
// `generated` is ever shown to readers.
//
// The quilt's switch decides whether the question is asked. `off` asks and
// sends nothing; `optional` asks and blocks nothing; `required` asks, and the
// server refuses a create without an answer — so the form says so first,
// with the button still live: a button greyed for a reason nobody can see is
// a form that does not say what it wants.

/// One answer to "Did you use AI?". `none` is a real answer, never
/// `Optional.none`: spell it `AIUse.none` wherever an `AIUse?` is near.
enum AIUse: String, CaseIterable, Identifiable, Equatable {
    case none, assisted, generated
    var id: String { rawValue }

    /// The web's labels (`AI_USE_OPTIONS`). `assisted` is recorded and not
    /// shown: a translator or a grammar tool is an honest answer that is not
    /// the generated label.
    var label: String {
        switch self {
        case .none: return "No AI"
        case .assisted: return "AI helped (editing, cleanup, translation)"
        case .generated: return "AI made this"
        }
    }

    /// A stored answer, read leniently: nil, empty or a word this client
    /// does not know is unanswered rather than a refusal to decode.
    init?(stored: String?) {
        guard let stored, let answer = AIUse(rawValue: stored) else { return nil }
        self = answer
    }

    /// The only answer a reader is shown.
    static func generated(_ stored: String?) -> Bool { stored == AIUse.generated.rawValue }
}

/// The quilt's `ai_disclosure` switch.
enum AIDisclosure: String, Equatable {
    case off, optional, required

    /// Absent is a quilt from before the question, which asks nothing.
    init(_ stored: String?) { self = stored.flatMap(AIDisclosure.init(rawValue:)) ?? .off }

    var asks: Bool { self != .off }

    /// What a create sends for one answer: nothing while the quilt has the
    /// question off, whatever the draft holds — a claim's draft is seeded
    /// from the listing's stored answer — and nothing for unanswered.
    func sent(_ answer: AIUse?) -> String? { asks ? answer?.rawValue : nil }

    /// The web's `aiAnswerMissing` sentence.
    static let missingLine = "Say whether AI was used before posting."

    /// The sentence, where the quilt requires an answer and one of the
    /// questions on screen has none. Pass only the questions shown: the
    /// image is not asked about without an image.
    func missing(_ answers: AIUse?...) -> String? { missing(answers) }
    func missing(_ answers: [AIUse?]) -> String? {
        self == .required && answers.contains(where: { $0 == nil }) ? Self.missingLine : nil
    }
}

extension QuiltSession {
    var aiDisclosure: AIDisclosure { AIDisclosure(instance?.aiDisclosure) }
}

/// What an edit sends for one answer: the new one where it changed, else
/// nothing, so an edit leaves the stored answer alone (`checkPatchedAIAnswer`
/// reads absent as "keep"). There is no un-picking, so a changed answer is
/// never a withdrawn one.
func aiAnswerChange(_ now: AIUse?, from was: AIUse?) -> String? {
    now == was ? nil : now?.rawValue
}

/// The patch-level declaration (decision 6), in the web's words. A
/// declaration rather than a label: it says what the patch *is*, and its
/// posts are still asked one by one.
enum AIWork {
    static let question = "Does the work this patch makes or publishes rely heavily on AI-generated content?"
    static let hint = "For example: a newsletter written by a model, generated music or art, or listings a model writes. Yes shows an \u{201C}AI work\u{201D} badge on this patch."
    static let later = "You can change this later under Edit patch."
    /// The workspace's one-time prompt: the patch's own admin, on a patch
    /// somebody runs (an unclaimed listing carries no declaration — web ADR
    /// 039 — and the server refuses one), until it has been answered either way.
    static func prompts(runs: Bool, unclaimed: Bool, aiWork: Bool?) -> Bool {
        runs && !unclaimed && aiWork == nil
    }
}

// MARK: - The question

/// A set of full-width radio rows in one card: the glyph `ChoiceCard` uses,
/// one row per answer, 44pt each, hairlines between. Bound to an optional
/// that starts nil; pressing the picked row again keeps it, because an
/// answer taken back is silence, and silence is not an answer here.
struct RadioRows<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String, id: String)]
    @Binding var selection: Value?
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                if index > 0 { Color.pwBorder.frame(height: PatchworkCard.hairline).padding(.leading, 12) }
                let on = selection == option.value
                Button { selection = option.value } label: {
                    HStack(spacing: 10) {
                        Image(systemName: on ? "largecircle.fill.circle" : "circle")
                            .font(Font.pw.body)
                            .foregroundStyle(on ? Color.pwAccent : Color.pwTextMuted)
                            .accessibilityHidden(true)
                        Text(option.label).font(Font.pw.body).foregroundStyle(Color.pwText)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier(option.id)
            }
        }
        .background(Color.pwSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.pwBorder, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// "Did you use AI to write this?", as the web's `AIUseQuestion`. The form
/// wraps it in its own field, so the heading and its asterisk read like
/// every other field's; it draws nothing on a quilt that has the question off.
struct AIUseQuestion: View {
    static let title = "Did you use AI to write this?"
    static let imageTitle = "Was AI used to make this image?"
    let mode: AIDisclosure
    var title: String = AIUseQuestion.title
    @Binding var answer: AIUse?
    /// The rows are `\(identifier)-none` and so on; the field wearing it is
    /// scrolled to by the same name.
    var identifier = "aiUse"
    var body: some View {
        if mode.asks {
            RadioRows(title: title, options: AIUse.allCases.map { (value: $0, label: $0.label, id: "\(identifier)-\($0.rawValue)") },
                      selection: $answer)
        }
    }
}

/// The declaration's Yes and No, in the same card. Neither is preselected:
/// unanswered stays nil rather than reading as No.
struct AIWorkQuestion: View {
    @Binding var answer: Bool?
    var body: some View {
        RadioRows(title: AIWork.question, options: [(true, "Yes", "aiWork-yes"), (false, "No", "aiWork-no")], selection: $answer)
    }
}

/// Where a form scrolls when the quilt requires an answer it has not had:
/// the question left unanswered. A counter, so a second tap scrolls again.
struct ScrollNudge: Equatable {
    private(set) var target = ""
    private(set) var count = 0
    mutating func to(_ id: String) { target = id; count += 1 }
}

extension View {
    /// Scrolls to the question a refusal names. The keyboard goes first: a
    /// focused field keeps itself in view, so with the title still being
    /// typed the form would scroll straight back and the tap would seem to
    /// do nothing.
    func follows(_ nudge: ScrollNudge, in proxy: ScrollViewProxy) -> some View {
        onChange(of: nudge) { _, now in
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation { proxy.scrollTo(now.target, anchor: .center) }
            }
        }
    }

    /// Takes the "say whether AI was used" line down once the question it
    /// pointed at is answered, rather than leaving it under an answer until
    /// the next tap. Any other failure stays where it is.
    func clearsMissingAnswer(_ failure: Binding<String?>, answers: [AIUse?]) -> some View {
        onChange(of: answers) { _, _ in
            guard let shown = failure.wrappedValue,
                  shown == AIDisclosure.missingLine || shown == EventPosting.sentenceCased(AIDisclosure.missingLine) else { return }
            failure.wrappedValue = nil
        }
    }
}

// MARK: - The tag

/// "Made with AI": words only, in the same quiet outline every other status
/// wears here. Never a glyph or a tint — a sparkle would be a judgement, and
/// this is a fact the author gave.
struct MadeWithAITag: View {
    var image = false
    var body: some View {
        EventBadge(text: image ? "Image made with AI" : "Made with AI")
            .accessibilityIdentifier(image ? "imageMadeWithAI" : "madeWithAI")
    }
}
