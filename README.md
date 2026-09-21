# Patchwork for iOS

An open-source native client for [Patchwork](https://github.com/nathanswavely/patchwork). **Early browsing prototype, not an App Store release.**

SwiftUI, iOS 17+, no third-party code dependencies (the only bundled third-party material is a set of Phosphor motif glyphs). Connects directly to an explicitly selected quilt using its public `/api/v1` endpoints. Nearly everything it does is a public read: no passwords, no analytics, no central proxy. You can sign in to a quilt by asking it to email you a six-digit code, and the writes the app makes are all yours and all on that one quilt: asking for the code, answering it, choosing a username the first time, signing out, and following, joining, leaving or withdrawing a request on a patch. A session is a cookie the quilt sets, kept in the app's own cookie jar and sent only back to that quilt, so each saved quilt holds its own session and signing in to one tells no other quilt anything. A launch reads only the quilt you explicitly inspect or select, and asks nothing authenticated of a quilt you have not signed in to.

## Run

Open `Patchwork.xcodeproj` in Xcode, choose the Patchwork scheme and an iPhone simulator, and Run. The project is checked in; XcodeGen is only needed after changing `project.yml` (`xcodegen generate --spec project.yml` from the repository root).

For an actual device, choose your development team and a bundle identifier in Signing & Capabilities. The prototype identifier is not an App Store identity.

Normal launches use live APIs. Add `--preview` to the scheme's launch arguments for clearly labeled fictional, offline design data in Debug builds. Preview connections are never persisted. Remove that argument to return to real quilts.

## Implemented path

1. Choose a quilt from the small starter directory or enter its HTTPS origin.
2. Inspect the returned quilt identity and explicitly select Explore quilt.
3. Explore the interactive quilt — it runs under the bars — pinch to zoom, pan, and filter by the quilt's most-worn tags to repack it. Switch to map or list from the floating control; all three read the same filter.
4. Search patches and upcoming events from the top bar's field (or the tab bar's Search button); one explicit row narrows the quilt to the query.
5. Tap a patch to dock its profile at the head's height; pull up for its four glimpses — About, Events, Members, Governance — and open any of them by its heading. Read the whole calendar and subscribe to it, the roster the patch publishes, and the documents, proposals and record it publishes. Open an event, get directions, use native sharing, or follow a link to its website. A patch that has moved opens read-only on the quilt it moved to.
6. Narrow the Events tab by date — today, tomorrow, this weekend, this week, next week, this month, or a custom range — resolved in the quilt's own time zone. An event's detail adds the flyer, the map and Maps directions, “with X” links, the host patch as a door, tickets on the source's own site, and Add to calendar.
7. Ask Discover what you're drawn to and get the patches wearing those tags, soonest event first.
8. Read how the quilt is run: the account menu's About this quilt opens a stack — About, The Label, The Lining, how governance works, the Privacy Policy and the User Agreement — which the end of List mode and Discover also reach by a quiet footer row.
9. Choose how it looks to you from the account menu's Display: Theme (System/Light/Dark) and Colors (Default/Muted). Both are held on the device and need no account.
10. Hold the Quilt tab (or use the account menu) to switch quilts; connected quilts appear as doorways. Saved quilts are local to the device; no quilt is preselected at launch.
11. Sign in to a quilt from the account menu: give it your email, it sends a six-digit code, and you type the code (the link in the same email still works on the web). An address with no account yet is asked to choose a username. The menu then names you and offers Sign out, which ends that quilt's session and forgets its cookie. Each quilt is signed in to separately.
12. Follow or join a patch once you are signed in — from the heart on its card, or from the control in its profile's head: Follow a public patch, Join one that admits members (with an optional message where it approves them), and leave, unfollow or withdraw a request from the standing the head then wears. A Dashboard tab appears while you are signed in with what needs you, what you manage, what you are a member of, what you follow, and what you have asked for.

Lancaster is one directory entry, not the default. Direct connection does not depend on directory inclusion. HTTPS root origins only in this prototype; subpath hosting, invitations, registry URLs, QR codes, directory administration, and location discovery are not implemented.

## Mobile-to-native mapping

| Existing mobile surface | Native implementation |
| --- | --- |
| Quilt switcher (scope switcher) | First-run List, identity confirmation; the Quilt tab wears the quilt's icon and a hold opens the switcher; Connected quilts are doorways |
| Global bar | One top bar over the canvas: Filter (badged), a live glass search field, account menu (Sign in, About, Display, Switch) |
| Quilt browsing | Native pan/pinch canvas running under the bars; activity sizing, affinity packing, tag reflow |
| Search (ADR 033) | The field activates in place with patches and events listed under it; one "Show matches" row sets the search chip; the tab bar's Search button focuses it |
| Filter chips | Sheet of usage-ranked chips over a live canvas; search chip among them; Clear |
| Map and list | MapKit coordinates; quilt-order, name, and newest list sorts; the view pill floats at the foot |
| Docked profile (ADR 094) | Sheet at the head's height, full screen on the pull, the rooms fetched by the pull, ShareLink, Maps directions |
| Profile glimpses (ADR 042) | About · Events · Members · Governance, each heading the door into its own screen; state worn in the head (moved, unclaimed, amended lining) |
| Patch calendar and feeds (ADR 031) | Upcoming on open, earlier events on request (`include_past`); Subscribe hands out the ICS (`webcal:`) and RSS addresses on a public patch |
| Members (ADR 006, ADR 095) | Paged roster with roles; `public_member_list` honoured, counts stay public, a withheld list says so |
| Governance (ADR 036, ADR 055) | Overview, documents, proposals filtered by outcome, and the record; absent rather than empty where the patch publishes neither |
| Remote patch (ADR 024) | Read-only view of a patch on another quilt, sashed with that quilt, ending in "Visit on {quilt}" |
| Discovery mode (ADR 075) | Discover tab: most-worn tags with counts, patches wearing them, soonest event first; ends in the patch |
| Event list and detail | Native lists, push navigation, event-local time zones, cursor pagination; a Menu of the web's date presets, tier and community-submitted badges, MapKit and EventKit on the detail |
| Mobile navigation | System TabView: Quilt, Events, Discover, Search (a button), and Dashboard while signed in. Notifications still wait |
| Label, About, lining, governance, legal pages | One quilt-info stack on the account menu, plus a quiet footer row on the reading surfaces; fetched documents read as native markdown blocks |
| Display menu (ADR 112) | Display sheet: Theme and Colors, held per device, no account needed; Muted carries one hue onto a shared lightness ramp with chroma capped |
| Visual identity | Blue action tint, system surfaces and SF Symbols, patch/quilt vocabulary |

System typography and surfaces adapt to appearance and Dynamic Type. The quilt retains the web’s rearranging behavior with clean native blocks. Textile decoration and display fonts are intentionally omitted. Reduce Motion disables rearrangement animation; the list provides full text at accessibility sizes.

## API boundary

Reads `instance` (including `stats`, `submissions_enabled`, and `geography.timezone`, the zone the date presets resolve in), `instance/icon`, `instance/lining`, `nodes/tree` (including each patch's `appearance`), `nodes/{slug}` (node plus the `is_unclaimed` and `lining_status` envelope), `tags` (for tag motifs), `label`, `legal/{doc}` for `privacy` and `terms`, `events` (including `node_slug`, `after`, `limit`, `from`, `to`, and `include_past` — `from`/`to` always travel as instants, never bare dates, because the server compares `starts_at` as text), `events/{id}` (which adds `visibility`, `node_status`, `node_id`, `latitude`/`longitude`, `recurrence`, `image_url`/`image_alt`, `status`, `source_id`, `links[]` and `mentions[]`), and `events/{id}/event.ics`. No `scope=my` — every one of those reads is the public quilt, signed in or not.

Sign-in adds the only calls that are not reads: `POST auth/magic-link` (`{email}`), `POST auth/magic-link/verify` (`{email, code}`, which answers with either the user or `{"status":"username_required","signup_token"}`), `POST auth/signup` (`{token, username, display_name}`), `GET auth/me`, and `POST auth/logout`. Every non-GET sends `X-Patchwork-Request: true` and `Content-Type: application/json`, which the server requires. The session is the quilt's own `patchwork_session` cookie — there are no bearer tokens — kept in the app's `HTTPCookieStorage` so it survives a relaunch. Cookies are host-scoped, so each saved quilt holds its own session and no quilt is sent another's; `auth/me` is asked only where that host already has such a cookie, so a reader who has not signed in makes no authenticated request at all. Signing out posts `auth/logout` and then deletes that host's cookies.

Following and joining add the rest of the writes: `GET me/nodes` (the reader's own memberships, active and pending), `POST nodes/{slug}/join` with `{"role":"follower"}` to follow and with `{}` or `{"message"}` to join — which answers `active` or `pending` according to the patch's `membership_policy` — `POST nodes/{slug}/leave` for both Unfollow and Leave, `POST nodes/{slug}/withdraw` for a request nobody has answered yet, and `GET events?scope=my` for what is coming up on the patches the reader holds a row on. `GET nodes/{slug}` carries `is_member`, `is_admin`, `membership_role`, `is_banned` and `membership_policy` alongside the public node where there is a session, and the Dashboard's badges read `nodes/{slug}/members?status=pending` and `nodes/{slug}/proposals?status=open` for the patches the reader admins or belongs to. Every one of these is asked only while signed in; a signed-out launch makes exactly the public reads it always did, and a 401 from any of them means the session is gone.

The patch profile's rooms add `nodes/{slug}/members` (with `after`), `nodes/{slug}/governance`, `governance/{id}`, `nodes/{slug}/governance/overview`, `nodes/{slug}/governance/record`, `nodes/{slug}/proposals` (with `status`), and `proposals/{id}`. `nodes/{slug}/events.ics` and `nodes/{slug}/events.rss` are handed to the reader's own calendar or feed app rather than fetched. A patch on a connected quilt is read from that quilt's own `nodes/{slug}`, `events`, `instance`, and `instance/icon`.

Every one of the endpoints above the sign-in paragraph is a public read, and the app reads them the same way whether or not anyone is signed in: it asks for no member-only view of a patch, so a patch's own disclosure settings — `public_member_list`, `public_governance_record`, `visibility`, and the server's `published_only` / `admins_withheld` / `proposals_withheld` flags — are honoured as the server states them, and a withheld list is never rendered as an empty one. DTOs decode only fields this client uses; unknown fields are tolerated. The app's cookie jar is its own — no web view shares it, and nothing is forwarded from one quilt to another. Each selected quilt gets a new navigation subtree; old quilt content is discarded.

The client's direct visit to a selected quilt is not a cross-quilt blended read. It does not use `multi_quilt: false` as permission to blend data from other instances.

Following, joining, leaving and withdrawing are implemented natively; signing in by emailed code is implemented; passkeys are not, because associated domains must be declared per domain ahead of time and this client connects to any quilt by address. Notifications, invitations, the noticeboard, account deletion, member-only content, creating or editing patches and events, approving the requests the Dashboard counts, governance acts, and moderation are follow-on work. The web remains the explicit route to those. No disabled pretend buttons represent them, and no control appears for a reader who is not signed in.

## Verification

Run Product → Test in Xcode. Unit tests cover which control each kind of patch earns and for whom, the membership index and its decoding, the Dashboard's grouping and counts, the `scope=my` query, address validation, timestamp variants, optional API fields, explicit selection, layout parity, filter matching, canvas lifetime, the Label/lining/legal responses, markdown block splitting, the muted ramp against the web's own values, the date presets' boundary rules (ported from the web's `datetime.test.js`), the extended event's decoding, which links become “with X” chips, the calendar-entry mapping, the profile's rooms and their withheld states, the sign-in flow's every transition, the code and username rules, and that a session cookie is only ever seen by the host that set it. UI tests use fictional Debug data to exercise explicit quilt selection, pinch and fit, docked-profile return without changing the viewport, the filter sheet and its Clear, search that narrows only through its one row, map/list browsing, the profile's glimpses and their rooms, Discover's question and answer, quilt switching from the account menu, the quilt-info stack and Display's Muted, and the events calendar's date presets, the empty state a range earns, and the detail's map and add-to-calendar offer, signing in by code and out again — including the first sign-in that chooses a username — and following a patch from a card, finding it on the Dashboard and letting go of it from the profile, asking to join a patch that approves its members and withdrawing the request, and the signed-out heart that opens the sign-in sheet, with screenshot attachments. A separate UI check exercises the largest accessibility text size and dark appearance.

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
