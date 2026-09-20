# Patchwork for iOS

An open-source native client for [Patchwork](https://github.com/nathanswavely/patchwork). **Early browsing prototype, not an App Store release.**

SwiftUI, iOS 17+, no third-party code dependencies (the only bundled third-party material is a set of Phosphor motif glyphs). Connects directly to an explicitly selected quilt using its public `/api/v1` endpoints. No account credentials, writes, analytics, or central proxy. A normal launch reads only the quilt you explicitly inspect or select.

## Run

Open `Patchwork.xcodeproj` in Xcode, choose the Patchwork scheme and an iPhone simulator, and Run. The project is checked in; XcodeGen is only needed after changing `project.yml` (`xcodegen generate --spec project.yml` from the repository root).

For an actual device, choose your development team and a bundle identifier in Signing & Capabilities. The prototype identifier is not an App Store identity.

Normal launches use live APIs. Add `--preview` to the scheme's launch arguments for clearly labeled fictional, offline design data in Debug builds. Preview connections are never persisted. Remove that argument to return to real quilts.

## Implemented path

1. Choose a quilt from the small starter directory or enter its HTTPS origin.
2. Inspect the returned quilt identity and explicitly select Explore quilt.
3. Explore the interactive quilt — it runs under the bars — pinch to zoom, pan, and filter by the quilt's most-worn tags to repack it. Switch to map or list from the floating control; all three read the same filter.
4. Search patches and upcoming events from the top bar's field (or the tab bar's Search button); one explicit row narrows the quilt to the query.
5. Tap a patch to dock its profile at the head's height; pull up for its upcoming events, directions, and links. Open an event, use native sharing, or follow a link to its website.
6. Ask Discover what you're drawn to and get the patches wearing those tags, soonest event first.
7. Read how the quilt is run: the account menu's About this quilt opens a stack — About, The Label, The Lining, how governance works, the Privacy Policy and the User Agreement — which the end of List mode and Discover also reach by a quiet footer row.
8. Choose how it looks to you from the account menu's Display: Theme (System/Light/Dark) and Colors (Default/Muted). Both are held on the device and need no account.
9. Hold the Quilt tab (or use the account menu) to switch quilts; connected quilts appear as doorways. Saved quilts are local to the device; no quilt is preselected at launch.

Lancaster is one directory entry, not the default. Direct connection does not depend on directory inclusion. HTTPS root origins only in this prototype; subpath hosting, invitations, registry URLs, QR codes, directory administration, and location discovery are not implemented.

## Mobile-to-native mapping

| Existing mobile surface | Native implementation |
| --- | --- |
| Quilt switcher (scope switcher) | First-run List, identity confirmation; the Quilt tab wears the quilt's icon and a hold opens the switcher; Connected quilts are doorways |
| Global bar | One top bar over the canvas: Filter (badged), a live glass search field, account menu (web sign-in, About, Switch) |
| Quilt browsing | Native pan/pinch canvas running under the bars; activity sizing, affinity packing, tag reflow |
| Search (ADR 033) | The field activates in place with patches and events listed under it; one "Show matches" row sets the search chip; the tab bar's Search button focuses it |
| Filter chips | Sheet of usage-ranked chips over a live canvas; search chip among them; Clear |
| Map and list | MapKit coordinates; quilt-order, name, and newest list sorts; the view pill floats at the foot |
| Docked profile (ADR 094) | Sheet at the head's height, full screen on the pull, events fetched by the pull, ShareLink, Maps directions |
| Discovery mode (ADR 075) | Discover tab: most-worn tags with counts, patches wearing them, soonest event first; ends in the patch |
| Event list and detail | Native lists, push navigation, event-local time zones, cursor pagination |
| Mobile navigation | System TabView: Quilt, Events, Discover, Search (a button). Dashboard and notifications wait for sign-in |
| Label, About, lining, governance, legal pages | One quilt-info stack on the account menu, plus a quiet footer row on the reading surfaces; fetched documents read as native markdown blocks |
| Display menu (ADR 112) | Display sheet: Theme and Colors, held per device, no account needed; Muted carries one hue onto a shared lightness ramp with chroma capped |
| Visual identity | Blue action tint, system surfaces and SF Symbols, patch/quilt vocabulary |

System typography and surfaces adapt to appearance and Dynamic Type. The quilt retains the web’s rearranging behavior with clean native blocks. Textile decoration and display fonts are intentionally omitted. Reduce Motion disables rearrangement animation; the list provides full text at accessibility sizes.

## API boundary

Reads `instance` (including `stats` and `submissions_enabled`), `instance/icon`, `instance/lining`, `nodes/tree` (including each patch's `appearance`), `nodes/{slug}`, `tags` (for tag motifs), `label`, `legal/{doc}` for `privacy` and `terms`, `events` (including `node_slug`, `after`, and `limit`), and `events/{id}`. All of them are public and readable signed out. DTOs decode only fields this client uses; unknown fields are tolerated. An ephemeral URLSession does not retain cookies or forward web sessions between quilts. Each selected quilt gets a new navigation subtree; old quilt content is discarded.

The client's direct visit to a selected quilt is not a cross-quilt blended read. It does not use `multi_quilt: false` as permission to blend data from other instances.

Authentication, passkey associated domains, mutations, notifications, account deletion, authenticated content, and moderation are follow-on work. The web remains the explicit route to joining, following, and governance. No disabled pretend buttons represent these actions.

## Verification

Run Product → Test in Xcode. Unit tests cover address validation, timestamp variants, optional API fields, explicit selection, layout parity, filter matching, canvas lifetime, the Label/lining/legal responses, markdown block splitting, and the muted ramp against the web's own values. UI tests use fictional Debug data to exercise explicit quilt selection, pinch and fit, docked-profile return without changing the viewport, the filter sheet and its Clear, search that narrows only through its one row, map/list browsing, the profile's pull to events, Discover's question and answer, quilt switching from the account menu, and the quilt-info stack and Display's Muted, with screenshot attachments. A separate UI check exercises the largest accessibility text size and dark appearance.

```sh
xcodebuild -project Patchwork.xcodeproj -scheme Patchwork \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test CODE_SIGNING_ALLOWED=NO
```

## Distribution and licensing

The motif glyphs under `Patchwork/Assets.xcassets/Motifs` are [Phosphor Icons](https://phosphoricons.com) (MIT; see `docs/third-party/phosphor-icons-LICENSE.txt`). The source code, project configuration, documentation, and original assets in this repository are licensed under the **Mozilla Public License 2.0 (MPL-2.0)**. See [LICENSE](LICENSE) and [PROVENANCE.md](PROVENANCE.md). This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.

Distributed modifications to MPL-covered files must remain available under MPL 2.0. Independently written files can use other licenses, subject to the license's terms. The separate Patchwork server retains its AGPLv3 license; this client communicates with it over HTTP and does not include the server or web implementation.

The quilt chooser includes links to this source repository and the license. For each future binary release, publish the corresponding source under an immutable release tag and provide that source link with the release. Include source changes and preserve license notices when redistributing. Apple's SDKs and system frameworks remain governed by Apple's terms; they are not relicensed by this repository.

The software license does not grant trademark rights or imply that a fork is an official Patchwork app. App Store distribution still requires a review of the actual binary, dependencies, disclosures, and applicable store terms.

The layout test suite compares 24 synthetic full/filtered layouts with numeric results from the web engine, including placement order, coordinates, and sizes. Public Lancaster instance, tree, event-list, patch-detail, and event-detail responses decoded with the client models. This does not replace a device or VoiceOver audit.

Before release: complete feature scope, accessibility review on devices, privacy disclosures, native authentication and moderation requirements, app icon, and App Store metadata. The project does not configure signing, upload, or publish anything.
