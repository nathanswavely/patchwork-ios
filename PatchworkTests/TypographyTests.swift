// SPDX-License-Identifier: MPL-2.0
import XCTest
import UIKit
import CoreText
@testable import Patchwork

/// The two bundled faces. A font that fails to register is invisible at
/// runtime — the app simply draws SF Pro and nobody notices the packaging
/// broke — so the registration itself is asserted here.
final class TypographyTests: XCTestCase {
    func testBothFacesRegister() {
        XCTAssertTrue(PWType.isAvailable(.text), "Space Grotesk did not register: check UIAppFonts and the bundled TTF")
        XCTAssertTrue(PWType.isAvailable(.display), "Shantell Sans did not register")
        XCTAssertFalse(UIFont.fontNames(forFamilyName: "Space Grotesk").isEmpty)
        XCTAssertFalse(UIFont.fontNames(forFamilyName: "Shantell Sans").isEmpty)
        print("PW families:", UIFont.familyNames.filter { $0.contains("Grotesk") || $0.contains("Shantell") })
        print("PW text names:", UIFont.fontNames(forFamilyName: "Space Grotesk"))
        print("PW display names:", UIFont.fontNames(forFamilyName: "Shantell Sans"))
    }

    /// A weight is a coordinate on the variable axis, not another file. If the
    /// axis is not being applied, every weight comes back the same width, and
    /// the app renders entirely in the fonts' default Light.
    func testWeightMovesOnTheVariableAxis() {
        let light = PWType.baseFont(.text, size: 17, weight: 300)
        let bold = PWType.baseFont(.text, size: 17, weight: 700)
        let attribute = NSAttributedString(string: "Patchwork", attributes: [.font: light]).size().width
        let heavier = NSAttributedString(string: "Patchwork", attributes: [.font: bold]).size().width
        XCTAssertGreaterThan(heavier, attribute, "Bold must be wider than Light — the wght axis is not being set")
    }

    /// Out-of-range coordinates come back as the default instance, which is
    /// the silent version of the same failure.
    func testWeightIsClampedToTheAxisRange() {
        let top = PWType.baseFont(.text, size: 17, weight: 700)
        let beyond = PWType.baseFont(.text, size: 17, weight: 900)
        XCTAssertEqual(NSAttributedString(string: "Patchwork", attributes: [.font: beyond]).size().width,
                       NSAttributedString(string: "Patchwork", attributes: [.font: top]).size().width,
                       accuracy: 0.5)
    }

    func testTheScaleGrowsWithDynamicType() {
        let base = PWType.baseFont(.text, size: 17, weight: 400)
        XCTAssertEqual(base.pointSize, 17, accuracy: 0.01, "The scale starts at the system's own size for the style")
        let accessible = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: base, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
        XCTAssertGreaterThan(accessible.pointSize, base.pointSize * 1.5,
                             "The accessibility sizes must reach this face too")
    }

    // MARK: - Emphasis inside a block

    /// The shear a font draws its glyphs through; zero for an upright.
    private func slant(_ font: UIFont) -> CGFloat { CTFontGetMatrix(font as CTFont).c }

    private func width(_ font: UIFont) -> CGFloat {
        NSAttributedString(string: "Patchwork", attributes: [.font: font]).size().width
    }

    /// Strong emphasis is the block's own face at the block's own size, moved
    /// along the weight axis — not the system's bold at the system's size.
    func testStrongEmphasisKeepsTheFaceAndSize() {
        let plain = PWTextSetting.body.uiFont()
        let strong = PWTextSetting.body.uiFont(strong: true)
        XCTAssertEqual(strong.familyName, "Space Grotesk")
        XCTAssertEqual(strong.familyName, plain.familyName)
        XCTAssertEqual(strong.pointSize, plain.pointSize, accuracy: 0.01)
        XCTAssertGreaterThan(width(strong), width(plain), "Strong must be heavier than the text around it")
        XCTAssertEqual(width(strong), width(PWType.uiFont(.text, size: 17, weight: 700, style: .body)), accuracy: 0.5)
    }

    /// Emphasis is the same face and size through a shear, since neither
    /// font has an italic of its own.
    func testEmphasisKeepsTheFaceAndSizeAndSlants() {
        let plain = PWTextSetting.body.uiFont()
        let emphasized = PWTextSetting.body.uiFont(emphasized: true)
        XCTAssertEqual(emphasized.familyName, "Space Grotesk")
        XCTAssertEqual(emphasized.pointSize, plain.pointSize, accuracy: 0.01)
        XCTAssertEqual(width(emphasized), width(plain), accuracy: 0.5, "The shear must not change the weight")
        XCTAssertGreaterThan(slant(emphasized), 0, "The slant did not survive scaling")
        XCTAssertEqual(slant(plain), 0, accuracy: 0.001)

        let both = PWTextSetting.body.uiFont(strong: true, emphasized: true)
        XCTAssertGreaterThan(slant(both), 0)
        XCTAssertGreaterThan(width(both), width(plain))
    }

    /// A heading that is already at the top of the axis stays there, at the
    /// heading's size rather than the body's.
    func testEmphasisFollowsTheBlockItIsIn() {
        let heading = PWTextSetting.title2.uiFont()
        let strong = PWTextSetting.title2.uiFont(strong: true)
        XCTAssertEqual(strong.pointSize, heading.pointSize, accuracy: 0.01)
        XCTAssertEqual(width(strong), width(heading), accuracy: 0.5)
        XCTAssertGreaterThan(width(PWTextSetting.headline.uiFont(strong: true)), width(PWTextSetting.headline.uiFont()))
    }

    func testEmphasisGrowsWithDynamicType() {
        let large = UITraitCollection(preferredContentSizeCategory: .large)
        let accessible = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        for (strong, emphasized) in [(true, false), (false, true), (true, true)] {
            let plain = PWTextSetting.body.uiFont(compatibleWith: accessible)
            let small = PWTextSetting.body.uiFont(strong: strong, emphasized: emphasized, compatibleWith: large)
            let grown = PWTextSetting.body.uiFont(strong: strong, emphasized: emphasized, compatibleWith: accessible)
            XCTAssertEqual(small.pointSize, 17, accuracy: 0.01)
            XCTAssertGreaterThan(grown.pointSize, small.pointSize * 1.5)
            XCTAssertEqual(grown.pointSize, plain.pointSize, accuracy: 0.01, "Emphasis must stay the size of its sentence")
            XCTAssertEqual(grown.familyName, "Space Grotesk")
            if emphasized { XCTAssertGreaterThan(slant(grown), 0, "The slant did not survive scaling") }
        }
    }
}
