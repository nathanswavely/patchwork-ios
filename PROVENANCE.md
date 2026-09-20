# Source and asset provenance

Initial review: 2026-09-19.

## Origin of this prototype

The initial SwiftUI implementation, tests, fictional preview data, and project configuration were created with OpenAI Codex during the maintainer's iOS prototyping session. They were initially untracked files in the Patchwork server checkout's `ios/` directory. No existing Git history or third-party contributions to those files were found in that checkout.

The maintainer selected MPL 2.0 for the separately published native client. The repository's LICENSE and per-file notices record that choice. This is not a relicensing of the Patchwork server or web application.

## Relationship to Patchwork

The existing Go/Svelte project was consulted for API routes, JSON response shapes, vocabulary, interaction requirements, and individual color values. The native client implements these interactions in newly written Swift. No Go/Svelte implementations, web fonts, illustrations, photographs, or community datasets are included here.

The quilt mark uses the system square.grid.2x2.fill symbol. The asset catalog contains color definitions and an empty AppIcon placeholder; it contains no third-party image files. System icons are requested through Apple's SF Symbols APIs, not redistributed as extracted artwork.

## Dependencies and data

- App imports: Apple Foundation, SwiftUI, UIKit, and MapKit. Tests also use XCTest.
- No Swift Package Manager packages, CocoaPods, Carthage frameworks, or vendored libraries are included.
- XcodeGen generated the checked-in Xcode project from `project.yml`; it is a development tool, not an app dependency.
- Preview and automated-test community content is fictional and was written for this prototype.
- Live public API responses were used for local contract verification; downloaded responses are not committed.
- Signing keys, provisioning profiles, Apple account details, simulator results, and personal Xcode state are excluded.

This records the files and workflow inspected, not a legal opinion about copyright ownership. Future contributions, dependencies, and assets must be reviewed on their own terms; an MPL header does not override a third party's rights.

## Native quilt behavior

The Swift layout implementation was written for this client after consulting the web engine at server commit cc74376 for its functional rules. This is not a clean-room claim. The JavaScript implementation is not bundled or redistributed here. `docs/native-quilt.md` records the behavioral contract. `PatchworkTests/layout-fixtures.json` contains only synthetic inputs and numeric reference outputs generated locally from that engine; it contains no community data or web source. The native views, gesture bridge, and tests were written in this prototyping session.
