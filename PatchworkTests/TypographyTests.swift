// SPDX-License-Identifier: MPL-2.0
import XCTest
import UIKit
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
}
