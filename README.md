# Patchwork for iOS

An open-source native client for [Patchwork](https://github.com/nathanswavely/patchwork). **Early browsing prototype, not an App Store release.**

SwiftUI, iOS 17+, no third-party dependencies. Connects directly to an explicitly selected quilt using its public `/api/v1` endpoints. No account credentials, writes, analytics, or central proxy. A normal launch reads only the quilt you explicitly inspect or select.

## Run

Open `Patchwork.xcodeproj` in Xcode, choose the Patchwork scheme and an iPhone simulator, and Run. The project is checked in; XcodeGen is only needed after changing `project.yml` (`xcodegen generate --spec project.yml` from the repository root).

For an actual device, choose your development team and a bundle identifier in Signing & Capabilities. The prototype identifier is not an App Store identity.

Normal launches use live APIs. Add `--preview` to the scheme's launch arguments for clearly labeled fictional, offline design data in Debug builds. Preview connections are never persisted. Remove that argument to return to real quilts.

## Implemented path

1. Choose a quilt from the small starter directory or enter its HTTPS origin.
2. Inspect the returned quilt identity and explicitly select Explore quilt.
3. Explore the interactive quilt, pinch to zoom, pan, and search/filter to repack it. Switch to map or list using the same filters.
4. Open a patch in a native sheet and browse its upcoming events.
5. Open an event, use native sharing, or follow a link to its website.
6. Switch quilts from the toolbar. Saved quilts are local to the device; no quilt is preselected at launch.

Lancaster is one directory entry, not the default. Direct connection does not depend on directory inclusion. HTTPS root origins only in this prototype; subpath hosting, invitations, registry URLs, QR codes, directory administration, and location discovery are not implemented.

## Mobile-to-native mapping

| Existing mobile surface | Native implementation |
| --- | --- |
| Quilt switcher | First-run List, identity confirmation, toolbar sheet |
| Quilt browsing and search | Native pan/pinch canvas; activity sizing, affinity packing, search and tag reflow |
| Map and list | MapKit coordinates; quilt-order, name, and newest list sorts |
| Patch profile | Dismissible sheet, NavigationStack, grouped sections, ShareLink, Maps directions |
| Event list and detail | Native lists, push navigation, event-local time zones, cursor pagination |
| Mobile navigation | System TabView with separate Quilt and Events stacks |
| Visual identity | Blue action tint, system surfaces and SF Symbols, patch/quilt vocabulary |

System typography and surfaces adapt to appearance and Dynamic Type. The quilt retains the web’s rearranging behavior with clean native blocks. Textile decoration and display fonts are intentionally omitted. Reduce Motion disables rearrangement animation; the list provides full text at accessibility sizes.

## API boundary

Reads `instance`, `nodes/tree`, `nodes/{slug}`, `events` (including `node_slug` and `after`), and `events/{id}`. DTOs decode only fields this client uses; unknown fields are tolerated. An ephemeral URLSession does not retain cookies or forward web sessions between quilts. Each selected quilt gets a new navigation subtree; old quilt content is discarded.

The client's direct visit to a selected quilt is not a cross-quilt blended read. It does not use `multi_quilt: false` as permission to blend data from other instances.

Authentication, passkey associated domains, mutations, notifications, account deletion, authenticated content, and moderation are follow-on work. The web remains the explicit route to joining, following, and governance. No disabled pretend buttons represent these actions.

## Verification

Run Product → Test in Xcode. Unit tests cover address validation, timestamp variants, optional API fields, explicit selection, layout parity, filter matching, and canvas lifetime. UI tests use fictional Debug data to exercise explicit quilt selection, pinch and fit, patch-sheet return without changing the viewport, tag filtering and restoration, map/list browsing, events, and quilt switching, with screenshot attachments. A separate UI check exercises the largest accessibility text size and dark appearance.

```sh
xcodebuild -project Patchwork.xcodeproj -scheme Patchwork \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test CODE_SIGNING_ALLOWED=NO
```

## Distribution and licensing

The source code, project configuration, documentation, and original assets in this repository are licensed under the **Mozilla Public License 2.0 (MPL-2.0)**. See [LICENSE](LICENSE) and [PROVENANCE.md](PROVENANCE.md). This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.

Distributed modifications to MPL-covered files must remain available under MPL 2.0. Independently written files can use other licenses, subject to the license's terms. The separate Patchwork server retains its AGPLv3 license; this client communicates with it over HTTP and does not include the server or web implementation.

The quilt chooser includes links to this source repository and the license. For each future binary release, publish the corresponding source under an immutable release tag and provide that source link with the release. Include source changes and preserve license notices when redistributing. Apple's SDKs and system frameworks remain governed by Apple's terms; they are not relicensed by this repository.

The software license does not grant trademark rights or imply that a fork is an official Patchwork app. App Store distribution still requires a review of the actual binary, dependencies, disclosures, and applicable store terms.

The layout test suite compares 24 synthetic full/filtered layouts with numeric results from the web engine, including placement order, coordinates, and sizes. Public Lancaster instance, tree, event-list, patch-detail, and event-detail responses decoded with the client models. This does not replace a device or VoiceOver audit.

Before release: complete feature scope, accessibility review on devices, privacy disclosures, native authentication and moderation requirements, app icon, and App Store metadata. The project does not configure signing, upload, or publish anything.
