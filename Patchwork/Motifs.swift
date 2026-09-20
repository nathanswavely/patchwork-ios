// SPDX-License-Identifier: MPL-2.0
import UIKit

/// The curated motif set (patchIcons.js): the small mark that stands for a
/// patch, worn as its top-left corner mark. Glyphs are Phosphor's fill weight,
/// bundled as template image sets under Assets.xcassets/Motifs (MIT; see
/// docs/third-party). Motifs are marks, never uploaded images.
enum Motifs {
    /// Picker order, which is also the registry: an `appearance.icon` outside
    /// this set is unknown and falls through to the tag-derived mark.
    static let keys = ["quilt", "palette", "paintBrush", "images", "camera", "filmSlate", "musicNotes", "guitar",
                       "micStage", "vinyl", "radio", "maskHappy", "sneaker", "bookOpen", "stamp", "scissors", "hammer",
                       "buildings", "storefront", "forkKnife", "coffee", "usersThree", "megaphone", "gradCap", "code",
                       "soccerBall", "bicycle", "heartbeat", "flower", "butterfly", "globe", "star", "skull", "lightning"]
    private static let known = Set(keys)
    /// The pre-feature default: the quilt mark.
    static let fallback = "quilt"

    /// chosen (if known) → first motif-bearing tag, in the patch's stored
    /// order → the quilt mark. Unknown slugs never error.
    static func key(for patch: Patch, tagMotifs: [String: String]) -> String {
        if let chosen = patch.appearance?.icon, known.contains(chosen) { return chosen }
        for tag in patch.tags ?? [] {
            if let slug = tagMotifs[tag], known.contains(slug) { return slug }
        }
        return fallback
    }

    static func image(_ key: String) -> UIImage? { UIImage(named: "motif-\(known.contains(key) ? key : fallback)") }
    /// The broken chain link that marks an unclaimed patch (docs/adr/030).
    static var unclaimed: UIImage? { UIImage(named: "mark-unclaimed") }
}
