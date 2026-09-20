// SPDX-License-Identifier: MPL-2.0
import UIKit

/// The palette registry and the fabric wall, owned by the client the way the
/// web owns them in quiltTheme.js and fabricWall.js (docs/adr/004): the
/// backend stores opaque keys, and this decides what colour they are. The hash
/// is the web's, bit for bit, because a hash-assigned patch must wear the same
/// tile in the app as on the site.
enum QuiltTheme {
    struct Swatch: Hashable { let key: String; let name: String; let hex: String }

    /// The curated fabric wall (docs/adr/029): every bundle draws from it.
    static let wall: [Swatch] = [
        Swatch(key: "raw-cotton", name: "Raw Cotton", hex: "#F2EEE4"),
        Swatch(key: "parchment", name: "Parchment", hex: "#EFF1CE"),
        Swatch(key: "oatmeal", name: "Oatmeal", hex: "#E4E5C4"),
        Swatch(key: "flax", name: "Flax", hex: "#D9D6AF"),
        Swatch(key: "muslin-pink", name: "Muslin Pink", hex: "#F5CEC2"),
        Swatch(key: "dove", name: "Dove", hex: "#C9C2B2"),
        Swatch(key: "stone", name: "Stone", hex: "#8A8273"),
        Swatch(key: "taupe", name: "Taupe", hex: "#625749"),
        Swatch(key: "charcoal", name: "Charcoal", hex: "#2C2D29"),
        Swatch(key: "stage-black", name: "Stage Black", hex: "#0A0A0A"),
        Swatch(key: "espresso", name: "Espresso", hex: "#2D2619"),
        Swatch(key: "chestnut", name: "Chestnut", hex: "#5A2517"),
        Swatch(key: "saddle", name: "Saddle", hex: "#753C1E"),
        Swatch(key: "rust", name: "Rust", hex: "#A0430A"),
        Swatch(key: "caramel", name: "Caramel", hex: "#B1752C"),
        Swatch(key: "camel", name: "Camel", hex: "#D9A066"),
        Swatch(key: "oxblood", name: "Oxblood", hex: "#952117"),
        Swatch(key: "brick", name: "Brick", hex: "#C02624"),
        Swatch(key: "scarlet", name: "Scarlet", hex: "#EC341C"),
        Swatch(key: "tomato", name: "Tomato", hex: "#E85D4A"),
        Swatch(key: "coral", name: "Coral", hex: "#EF7674"),
        Swatch(key: "merlot", name: "Merlot", hex: "#7A1F2B"),
        Swatch(key: "punch", name: "Punch", hex: "#DA0956"),
        Swatch(key: "bubblegum", name: "Bubblegum", hex: "#E7658E"),
        Swatch(key: "rose", name: "Rose", hex: "#E1A4BC"),
        Swatch(key: "magenta", name: "Magenta", hex: "#B23282"),
        Swatch(key: "mulberry", name: "Mulberry", hex: "#8E2F5C"),
        Swatch(key: "peach", name: "Peach", hex: "#F7B79B"),
        Swatch(key: "violet", name: "Violet", hex: "#6A3FA0"),
        Swatch(key: "plum", name: "Plum", hex: "#4A2C6F"),
        Swatch(key: "aubergine", name: "Aubergine", hex: "#261922"),
        Swatch(key: "lilac", name: "Lilac", hex: "#9B7EBD"),
        Swatch(key: "navy", name: "Navy", hex: "#16324F"),
        Swatch(key: "ink-blue", name: "Ink Blue", hex: "#3A4E8A"),
        Swatch(key: "workwear", name: "Workwear", hex: "#1493CC"),
        Swatch(key: "sky", name: "Sky", hex: "#039BE6"),
        Swatch(key: "periwinkle", name: "Periwinkle", hex: "#7690C1"),
        Swatch(key: "faded-denim", name: "Faded Denim", hex: "#88ABD1"),
        Swatch(key: "chambray", name: "Chambray", hex: "#9FC3DA"),
        Swatch(key: "petrol", name: "Petrol", hex: "#0F4C5C"),
        Swatch(key: "spruce", name: "Spruce", hex: "#204B4B"),
        Swatch(key: "bottle-green", name: "Bottle Green", hex: "#2E7D5B"),
        Swatch(key: "seafoam", name: "Seafoam", hex: "#94CDBE"),
        Swatch(key: "sage", name: "Sage", hex: "#81AE7F"),
        Swatch(key: "fern", name: "Fern", hex: "#5E8258"),
        Swatch(key: "olive", name: "Olive", hex: "#3E5622"),
        Swatch(key: "moss", name: "Moss", hex: "#94AC0E"),
        Swatch(key: "slime", name: "Slime", hex: "#88DE16"),
        Swatch(key: "pistachio", name: "Pistachio", hex: "#C5D86D"),
        Swatch(key: "lemon", name: "Lemon", hex: "#F5EB06"),
        Swatch(key: "hi-vis", name: "Hi-Vis", hex: "#FCFD1B"),
        Swatch(key: "goldenrod", name: "Goldenrod", hex: "#F4CD2E"),
        Swatch(key: "mustard", name: "Mustard", hex: "#D89E13"),
        Swatch(key: "butterscotch", name: "Butterscotch", hex: "#F6C87F"),
        Swatch(key: "amber", name: "Amber", hex: "#E88D14"),
        Swatch(key: "safety-orange", name: "Safety Orange", hex: "#E3480B"),
    ]
    private static let wallByKey = Dictionary(uniqueKeysWithValues: wall.map { ($0.key, $0) })

    /// A pre-cut bundle: three fabrics, slot one the identity colour.
    struct Palette: Hashable {
        /// The registry key, or nil when the colours came from a patch's own bundle.
        let key: String?
        let name: String
        let primary: String
        let secondary: String
        let bg: String
        let slots: [String]
        init(key: String?, name: String, primary: String, secondary: String, bg: String, slots: [String]? = nil) {
            self.key = key; self.name = name; self.primary = primary; self.secondary = secondary; self.bg = bg
            self.slots = slots ?? [primary, secondary, bg]
        }
    }

    /// The album palettes, lifted from punk record sleeves, first.
    static let album: [Palette] = [
        Palette(key: "adolescents", name: "Adolescents", primary: "#039BE6", secondary: "#EC341C", bg: "#0a0a0a"),
        Palette(key: "pinkRazors", name: "Pink Razors", primary: "#DA0956", secondary: "#1493CC", bg: "#F5CEC2"),
        Palette(key: "greatestSongs", name: "Greatest Songs", primary: "#88DE16", secondary: "#88ABD1", bg: "#E4E5C4"),
        Palette(key: "allroysRevenge", name: "Allroy's Revenge", primary: "#B23282", secondary: "#FCFD1B", bg: "#0a0a0a"),
        Palette(key: "anthem", name: "Anthem", primary: "#C02624", secondary: "#D89E13", bg: "#261922"),
        Palette(key: "allTheShoes", name: "All the Shoes", primary: "#5A2517", secondary: "#E1A4BC", bg: "#EFF1CE"),
        Palette(key: "bottlesToTheGround", name: "Bottles to the Ground", primary: "#E3480B", secondary: "#94AC0E", bg: "#D9D6AF"),
        Palette(key: "liberalAnimation", name: "Liberal Animation", primary: "#952117", secondary: "#F4CD2E", bg: "#5E8258"),
    ]

    /// The wall cuts, in the web's order: primary, secondary, ground, by wall
    /// key. They exist because the album set clusters through red; together
    /// the hash covers the wheel.
    static let cuts: [(String, String, String)] = [
        ("punch", "butterscotch", "stage-black"),
        ("brick", "chambray", "parchment"),
        ("rust", "seafoam", "raw-cotton"),
        ("amber", "ink-blue", "charcoal"),
        ("mustard", "petrol", "flax"),
        ("goldenrod", "merlot", "charcoal"),
        ("moss", "muslin-pink", "espresso"),
        ("fern", "peach", "oatmeal"),
        ("bottle-green", "lemon", "aubergine"),
        ("seafoam", "mulberry", "stage-black"),
        ("spruce", "coral", "raw-cotton"),
        ("petrol", "butterscotch", "parchment"),
        ("workwear", "safety-orange", "oatmeal"),
        ("sky", "brick", "stage-black"),
        ("ink-blue", "camel", "dove"),
        ("violet", "hi-vis", "stage-black"),
        ("lilac", "spruce", "muslin-pink"),
        ("mulberry", "pistachio", "raw-cotton"),
    ]

    /// Every palette in registry order: the hash indexes this list, so the
    /// order is part of the contract.
    static let palettes: [Palette] = album + cuts.map { primary, secondary, ground in
        let p = wallByKey[primary]!, s = wallByKey[secondary]!, g = wallByKey[ground]!
        return Palette(key: cutKey(primary, secondary), name: p.name, primary: p.hex, secondary: s.hex, bg: g.hex)
    }
    static let byKey: [String: Palette] = Dictionary(uniqueKeysWithValues: palettes.map { ($0.key!, $0) })

    /// camelCase of the two fabrics that name a cut: "ink-blue" + "camel" → "inkBlueCamel".
    static func cutKey(_ primary: String, _ secondary: String) -> String {
        func camel(_ key: String) -> String {
            key.split(separator: "-").enumerated().map { i, part in i == 0 ? String(part) : part.prefix(1).uppercased() + part.dropFirst() }.joined()
        }
        let second = camel(secondary)
        return camel(primary) + second.prefix(1).uppercased() + second.dropFirst()
    }

    /// The web's `hashStr`: `(h << 5) - h + charCode`, wrapping at 32 bits,
    /// over UTF-16 code units.
    static func hash(_ text: String) -> Int32 {
        var h: Int32 = 0
        for unit in text.utf16 { h = (h &<< 5) &- h &+ Int32(unit) }
        return h
    }
    /// `Math.abs(hashStr(s)) % count`, safe at Int32.min.
    static func index(_ text: String, count: Int) -> Int { Int(abs(Int64(hash(text))) % Int64(count)) }

    /// The register the reader is drawing in (docs/adr/112). Held per device
    /// in `UserDefaults` and mirrored here, because the palette is resolved
    /// deep inside layer drawing where there is no view to observe from.
    /// `QuiltSession` sets it before the canvas is asked to draw.
    static var colorMode: ColorMode = DisplayDefaults.colorMode

    /// What a patch's tile draws with: its bundle wins, then a pinned known
    /// palette, then the hash. Slot zero is always the identity colour. When
    /// the reader asked for muted, that result is carried onto the shared ramp.
    static func palette(id: String, appearance: Appearance?) -> Palette {
        let base = chosen(id: id, appearance: appearance)
        guard colorMode == .muted else { return base }
        // The *count* of slots is carried over rather than filled out to six:
        // muted may take colour away and may not add structure, so a patch
        // whose bundle is one fabric keeps drawing one flat fabric here too.
        return muted(base, slots: mutedSlots(primary: base.primary, count: base.slots.count))
    }

    /// What the patch actually chose, before any viewer-side register.
    private static func chosen(id: String, appearance: Appearance?) -> Palette {
        let bundle = Array((appearance?.bundle ?? []).filter(isHex).prefix(6))
        if let first = bundle.first {
            return Palette(key: nil, name: "Bundle", primary: first, secondary: bundle.count > 1 ? bundle[1] : first,
                           bg: bundle.count > 2 ? bundle[2] : darken(first, 0.55), slots: bundle)
        }
        if let key = appearance?.palette, let pinned = byKey[key] { return pinned }
        return palettes[index(id, count: palettes.count)]
    }

    private static func muted(_ base: Palette, slots: [String]) -> Palette {
        Palette(key: base.key, name: base.name, primary: slots[0],
                secondary: slots.count > 1 ? slots[1] : slots[0],
                bg: slots.count > 2 ? slots[2] : darken(slots[0], 0.55), slots: slots)
    }

    static func palette(for patch: Patch) -> Palette { palette(id: patch.id, appearance: patch.appearance) }

    /// A palette for a filler tile, keyed off its index the way the web keys ghosts.
    static func ghost(_ index: Int) -> Palette {
        let base = palettes[abs(index * 7 + 3) % palettes.count]
        guard colorMode == .muted else { return base }
        return muted(base, slots: mutedSlots(primary: base.primary, count: 3))
    }

    /// The one colour that stands for a patch anywhere it is not a full tile.
    static func identityColor(for patch: Patch) -> UIColor { UIColor(hex: palette(for: patch).primary) ?? .label }

    /// Ink or paper for an arbitrary fill: WCAG luminance, with the threshold
    /// favouring ink on mid-tones the way the web does.
    static func textOnColor(_ hex: String) -> UIColor {
        guard let rgb = components(hex), hex.count >= 7 else { return .white }
        func channel(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let lum = 0.2126 * channel(rgb.r) + 0.7152 * channel(rgb.g) + 0.0722 * channel(rgb.b)
        return lum > 0.18 ? UIColor(hex: "#151820")! : .white
    }

    /// Multiply each channel by (1 − amount), as the web's `darken` does.
    static func darken(_ hex: String, _ amount: Double) -> String {
        guard let rgb = components(hex) else { return hex }
        func part(_ v: Double) -> String { String(format: "%02x", Int((v * 255 * (1 - amount)).rounded())) }
        return "#" + part(rgb.r) + part(rgb.g) + part(rgb.b)
    }

    /// `#rgb`, `#rrggbb` or `#rrggbbaa` — the shapes a bundle may carry.
    static func isHex(_ text: String) -> Bool {
        guard text.hasPrefix("#") else { return false }
        let digits = text.dropFirst()
        return [3, 6, 8].contains(digits.count) && digits.allSatisfy(\.isHexDigit)
    }

    static func components(_ hex: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        guard isHex(hex) else { return nil }
        var digits = String(hex.dropFirst())
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        if digits.count == 6 { digits += "ff" }
        guard let value = UInt32(digits, radix: 16) else { return nil }
        return (Double((value >> 24) & 0xff) / 255, Double((value >> 16) & 0xff) / 255, Double((value >> 8) & 0xff) / 255, Double(value & 0xff) / 255)
    }
}

/// Muted colours (docs/adr/112), ported from the web's `mutedColors.js`.
///
/// One rule, stated once: muted never adds a colour a patch didn't choose. It
/// takes away what it has to and keeps the rest. Hue is carried through
/// untouched, lightness is *set* to a step on a ramp every tile in the quilt
/// shares, and chroma is only ever **capped** — never raised. Capping rather
/// than setting is what makes that sentence true, and it dissolves the
/// achromatic case instead of answering it: Stage Black has no chroma to cap,
/// so it stays a grey ramp, because that patch genuinely chose to be
/// achromatic.
///
/// Normalising lightness is the part that does the work. The quilt shouts in
/// two channels — chroma, and value contrast — and value contrast is the one
/// that carries across a room.
extension QuiltTheme {
    /// OKLCH chroma ceiling. Colours above it come down; colours below stay put.
    static let chromaCap = 0.09
    /// Lightness per bundle slot, in OKLCH L. Indexed by slot rather than
    /// sorted: slot 0 is the identity colour and is mid-light, slot 1 the
    /// secondary is light, slot 2 the ground is dark, and 3–5 are drafted
    /// blocks only. No two adjacent slots are closer than 0.22, which is what
    /// keeps a drafted block's pieces separable by construction.
    static let slotLightness = [0.64, 0.86, 0.28, 0.50, 0.75, 0.38]

    private static func srgbToLinear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private static func linearToSrgb(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }

    /// Björn Ottosson's Oklab, hue in radians.
    static func oklch(_ hex: String) -> (L: Double, C: Double, h: Double)? {
        guard let rgb = components(hex) else { return nil }
        let r = srgbToLinear(rgb.r), g = srgbToLinear(rgb.g), b = srgbToLinear(rgb.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        return (L: L, C: (A * A + B * B).squareRoot(), h: atan2(B, A))
    }

    private static func oklchToLinearRgb(_ L: Double, _ C: Double, _ h: Double) -> [Double] {
        let A = C * cos(h), B = C * sin(h)
        let l_ = L + 0.3963377774 * A + 0.2158037573 * B
        let m_ = L - 0.1055613458 * A - 0.0638541728 * B
        let s_ = L - 0.0894841775 * A - 1.2914855480 * B
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s]
    }

    private static func inGamut(_ rgb: [Double]) -> Bool {
        let e = 1e-4
        return rgb.allSatisfy { $0 >= -e && $0 <= 1 + e }
    }

    /// OKLCH to hex, reducing chroma until the colour fits in sRGB. Lightness
    /// and hue are held and chroma gives way, for the same reason the cap
    /// exists: this may take colour away and may not invent it, and a hue
    /// shift to stay in gamut would be inventing one. Binary search rather
    /// than a clamp on the channels — clamping RGB shifts hue silently.
    static func oklchToHex(_ L: Double, _ C: Double, _ h: Double) -> String {
        var rgb = oklchToLinearRgb(L, C, h)
        if !inGamut(rgb) {
            var lo = 0.0, hi = C
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                if inGamut(oklchToLinearRgb(L, mid, h)) { lo = mid } else { hi = mid }
            }
            rgb = oklchToLinearRgb(L, lo, h)
        }
        return "#" + rgb.map { channel in
            String(format: "%02x", Int((min(1, max(0, linearToSrgb(channel))) * 255).rounded()))
        }.joined()
    }

    /// One fabric of a muted tile: the patch's identity colour, carried to the
    /// lightness this slot draws at, with its chroma capped. An unparseable
    /// hex comes back unchanged.
    static func mutedSlot(_ identityHex: String, _ slot: Int = 0) -> String {
        guard let c = oklch(identityHex) else { return identityHex }
        return oklchToHex(slotLightness[slot % slotLightness.count], min(c.C, chromaCap), c.h)
    }

    /// A whole muted bundle: `count` fabrics, all one hue, each at its own
    /// step. Injective on slots by construction — no two share a lightness, so
    /// a drafted block can never flatten. The bundle the patch actually stored
    /// is ignored rather than transformed: past slot 0 it says nothing about
    /// how muted should look.
    static func mutedSlots(primary: String, count: Int) -> [String] {
        let n = max(1, min(count, slotLightness.count))
        return (0..<n).map { mutedSlot(primary, $0) }
    }

    /// A single standalone colour — a tag chip, a map marker, a profile's
    /// identity — muted as slot 0, so it agrees with the tile the same patch
    /// draws.
    static func mutedColor(_ hex: String) -> String { mutedSlot(hex, 0) }
}

extension UIColor {
    convenience init?(hex: String) {
        guard let c = QuiltTheme.components(hex) else { return nil }
        self.init(red: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
}
