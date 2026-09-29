# Native quilt and profiles

## Scope and direction contract

Mode: Operate. Platform: iOS/iPadOS. The user explicitly pinned the existing web quilt's behavior and requested clean native styling without textile decoration. This extends the native prototype; no alternate visual concepts or raster comps are needed.

THESIS: The same rearranging quilt, rendered as legible native blocks. Filtering removes nonmatches and packs the remaining patches together; it never merely dims a fixed overview.
OWN-WORLD: System surfaces, San Francisco, one action tint, and SF Symbols around a quilt that is the patches' own — their palettes, blocks, rotations and motifs, seam ink between tiles, corner marks on them — drawn as the web draws it. No hand lettering or decorative filler of the app's own. (Revised 2026-09-20: the first cut drew restrained block fills and ruled out stitches and fabric; the user then asked for the web's quilt designs to be pulled in. The cloth — lattice wobble, batting, weave, folds — is still not drawn.)
STORY: Choose a quilt, explore by touch or search/interests, switch between quilt/map/list, open a patch, and find its next events or directions.
FIRST VIEWPORT: One top bar — Filter, the live search field, the account menu — painting nothing over a canvas that runs under the status bar, the bar and the tab bar; the Quilt/Map/List segmented control floats at the foot. The tab bar reads Quilt (the quilt's own icon; hold to switch), Events, Discover, and a Search button that focuses the field. Patch profiles dock as a native sheet at the head's height and pull up to full screen. (Revised 2026-09-20 to align with the mobile web shell; the first cut put the segmented control under the title.)
FORM: User-pinned native adaptation, not a new visual-world selection. No seed or generated comp. Native pan/zoom and animated repacking carry the experience; Reduce Motion suppresses the slide.
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.

## Behavioral reference

Reference server/web commit: cc74376. The web implementation is consulted as behavioral evidence, not bundled in this MPL client.

- Square grid sizes follow activity floors and competition-rank caps. Quiet quilts remain equal-sized.
- Placement uses the API's affinity strengths; positions are not geographic coordinates.
- A selected interest matches any selected tag. A text query matches a patch's name OR description, case- and diacritic-insensitively. Text and interests intersect.
- Filtered subsets are repacked with original placed sizes as the starting sizes, with the layout's fit flexibility. Clearing filters restores the full quilt.
- The list's default order follows the current quilt's placement order. Name and recently-added sorts are also available.
- Native map uses actual patch coordinates and the same narrowed patch set.
- Selecting a patch opens its profile while keeping the quilt's filter and viewport intact behind it.

Account operations, remote blended My Quilt regions, and full web-product parity are outside this browsing pass. No authenticated state is fabricated.

## Verification — 2026-09-20

Nine unit tests and three iPhone simulator UI tests pass. The complete browsing and gesture flow also passes on iPad. Layout fixtures compare 24 synthetic full/filtered examples with the web reference; a local check of Lancaster’s current 59 patches matched positions, sizes, and placement order. No live community data is checked in.

The independent native finish reviewer returned **ship** for the three reviewed corrections: bounded Dynamic Type labels, intentional small-tile truncation, and verified pinch/tap behavior. The gesture regression check ensures a pinch never opens a profile; tapping opens it, and dismissal preserves the quilt position and scale. Simulator review does not substitute for a physical-device or VoiceOver audit.

## Shell alignment — 2026-09-20

The shell was aligned with the mobile web's decisions (web CONTEXT.md "Shell & navigation" and "Docked profile"; ADRs 033, 074, 075, 078, 094) and then reshaped for a native app that owns its chrome:

- One top bar on every discovery surface: Filter (badged) · search pill · account menu. Notifications and the user's own entries belong in the account menu once sign-in exists; the web's bottom-shelf search moved up here.
- The tab bar is Quilt · Events · Discover. The Quilt item wears the quilt's icon, and a hold on it opens the switcher. Dashboard is deliberately absent until there is an account to dash.
- Search never narrows by typing (ADR 033). The field activates in place and lists patches and upcoming events under it; one row sets the search chip. The tab bar's Search tab is a place: choosing it keeps the pill selected with the same field live in its bar, and the X returns to the tab the reader came from.
- Filter chips are ranked by how many patches wear them and live in a sheet the quilt repacks behind.
- A tap hands back the patch's own profile, docked (ADR 094): head at rest, full screen on the pull, events fetched by the pull.
- Discover is ADR 075 without the follow: the question, the eight most-worn tags with counts, the patches wearing them with the soonest event first.
- `QuiltSession` holds one quilt's patches and filter state so the quilt, Discover, and search read the same thing.

## Quilt appearance — 2026-09-20

The quilt now draws what each patch chose. No API change was needed: `nodes/tree` already carries `appearance` (palette, block as a curated slug or an inline drafted block, rotation, bundle, icon) on every patch that set one, `tags` carries each tag's `motif`, and `instance/icon` was already read. What the client had to add was the frontend-owned registries the web keeps out of the backend on purpose (docs/adr/004): the fabric wall and the 26 palettes, the twelve curated blocks, the drafted-block engine (docs/adr/029), the 34-motif set, and the web's `hashStr` — ported bit for bit and checked against node runs of the web modules in `QuiltAppearanceTests` (hash values, palette order and cut keys, drafted faces for three live Lancaster drafts, resolution order chosen → tag → quilt mark).

Rendering: each tile is a unit-square `CALayer` scaled and rotated to its frame, one `CAShapeLayer` per fabric with a hairline seal stroke; seams are one deduplicated path on the board (0.6pt) with the outer edge as a 2.4pt binding, both counter-scaled on every zoom tick; corner marks are anchored on their corner and counter-scaled so the inset holds in screen points; name badges live in a screen-space layer over the canvas, clipped to the safe area, planned each scroll/zoom tick by `QuiltBadges.plan` with the web's thresholds (52/44pt, 32→26pt gap over 52→80pt, 8.5em cap, three balanced lines) and hysteresis. A tap on a badge hands the touch to the badge's patch while the pan still belongs to the scroll view.

Not yet drawn, deliberately: the cloth (docs/adr/066 — the wandering lattice, block warp, bevel, doming, weave, folds, topstitch), Muted colours (docs/adr/112 — a viewer setting the app has no Display menu for), the viewer's role mark (needs sign-in), and hover dim (desktop only). Motif glyphs are Phosphor Icons' fill weight, generated into `Assets.xcassets/Motifs` from the web's dependency; MIT licence in `docs/third-party/phosphor-icons-LICENSE.txt`.

## Quilt info and Display — 2026-09-20

The quilt's public account of itself, and the reader's own two settings. Both hang off the account menu, and neither needs an account, which is the point: the reader these surfaces exist for is the one deciding whether to join.

**The info stack.** "About this quilt" is no longer one sheet — it is a grouped list headed by the quilt's identity that pushes to About, The Label, The Lining, Governance, the Privacy Policy and the User Agreement. Four endpoints were added to the boundary: `label`, `instance/lining`, `legal/privacy` and `legal/terms`, plus `stats.node_count` and `submissions_enabled` on `instance`. The two prose surfaces the project owns rather than the instance — About's orientation copy and Governance's four sections — are bundled in the client, adapted from About.svelte and Governance.svelte to read in an app, because they are the project's claim about what the software does and an instance that could edit them could narrate behaviour it does not control (web docs/adr/049). Everything else is fetched and rendered as markdown by a block reader (`Markdown.swift`): blocks are split here — headings, paragraphs, bullets, numbers, quotes, rules — and each block's inline run goes to `AttributedString(markdown:)`, which keeps links and emphasis and lets the whole document grow with Dynamic Type. A whole-document `AttributedString` would flatten exactly the structure these documents use to be readable. Relative links (`/label`, `/lining`) resolve against the quilt they came from. The web's footer strip becomes one quiet centred row — The Label · About · Privacy · Terms — in the footer slot of List mode's and Discover's last section, opening its page as its own sheet. Two other shapes were tried and rejected against the live app: a row of `NavigationLink`s wears a list row's chrome, so the strip read as four chevroned menu items, and a `navigationDestination` on a discovery surface re-forms the toolbar that hosts the live search field, which silently cost the field its focus mid-typing.

**Display (web docs/adr/112).** Theme (System/Light/Dark) and Colors (Default/Muted), both in `UserDefaults` via `@AppStorage`, both per device and neither on an account. `mutedColors.js` is ported into `QuiltTheme` as `mutedSlots(primary:count:)` over an Oklab conversion, checked against node runs of the web module for six slots of four identity colours, the achromatic case, the short-hex case, the count clamp and the OKLCH decomposition itself. It applies inside `QuiltTheme.palette(id:appearance:)` and `ghost(_:)`, so every existing reader of a palette — the canvas's cuts, the motif disc's identity colour, `identityColor(for:)` — is muted without knowing the setting exists. The mode rides through `QuiltSession` and `QuiltCanvas` as a value and is part of `QuiltTileView.configure`'s identity check, which is what makes the quilt recut in place when the setting changes rather than only on the next repack. The block drafter is the web's one exception and has no counterpart here.

**Deliberately not built:** a native submission form. Where `submissions_enabled` is true, the search's nothing-found state offers one link to the website's `/submit`; suggesting a patch needs an account, and no disabled button pretends otherwise. Tag chips and map markers still wear the action tint rather than a patch's identity colour, so muted has nothing to reach in them yet; when they take identity colour, they will get it through `QuiltTheme` and be muted already.

## Profile depth — 2026-09-20

The docked profile grew the rest of the web's public patch face, in the web's organisation and none of its styling. The detent mechanics are untouched: the sheet still rests at head-plus-96pt and the pull is still what costs the fetches — there are now four of them, one per room, and About needs none, which is why About leads.

- **Glimpses in the web's order** (ADR 042): About · Events · Members · Governance, each heading a `NavigationLink` into its own screen. No door is named for a container.
- **State in the head** (ADR 037, ADR 042, ADR 090): the `moved_to` banner, the unclaimed notice, the "Amended lining" badge. `is_unclaimed` and `lining_status` ride the `nodes/{slug}` *envelope*, not the node, so `PatchResponse` unpacks both — read off the node they are always nil and the badge silently drops on the one patch that must wear it.
- **Events** carry `from=<now>` in the glimpse, with `upcoming_event_count` supplying the "N more upcoming" the capped list owes the head's number. The calendar screen drops that bound in two halves rather than one: `events` orders oldest first and pages forward, so a single `include_past=true` asked Tellus360 for its whole calendar and got last July — a screen that opened on history. Upcoming is fetched on open (`from=now`); what already happened is an explicit second request (`include_past=true&to=now`), labelled oldest-first because that is the only order the endpoint has. Subscribe hands out `nodes/{slug}/events.ics` over `webcal:` and `…/events.rss`, and only where `visibility == "public"` (ADR 031).
- **Members** (ADR 006, ADR 095): a signed-out reader is always outside the room, so `public_member_list` decides alone. `everyone` lists, `admins` lists the admins and says so once, `nobody` withholds — and the counts stay public at every rung, because the quilt sizes the tile by them. The withheld screen says the patch doesn't publish its list; it never says there are no members.
- **Governance** (ADR 036, ADR 039, ADR 041, ADR 051, ADR 055, ADR 097, ADR 100): overview (rules narrated only where they are actually run, `admins_withheld` read before the admin list's length, the council's chairs each saying what is true of *it*), documents (`published_only` decides which kind of empty; the room lists every published document, the lining included, and only the glimpse drops a pristine one so the door's count and the list agree), proposals (Open · Approved · Rejected · Not decided · All, with the outcome word read off `state` before `status` so a lapse is never printed as a rejection), and the record. Proposals and the record are absent rather than empty where `public_governance_record == "nobody"`. An unclaimed patch carries no governance at all.
- **Remote patches** (ADR 024): a read-only view of a patch on another quilt from its own public API, sashed "On {quilt}, another quilt", ending in "Visit on {quilt}". Its one entry point today is the `moved_to` banner, which is the only place this client currently holds another quilt's patch address; the switcher's Connected quilts stays a doorway into that quilt's own inspect-and-confirm.
- **Nothing authenticated is drawn.** No join, follow, vote, claim or notice button, enabled or disabled. The noticeboard is members-only on the web and is not built here.

## Events parity — 2026-09-20

The Events tab and an event's detail were brought level with the web's public
(signed-out) calendar, with the native wins the web has no way to offer.

- **Flat, soonest first, with the web's date presets.** No day grouping: a
  gathering is one row among the next ones. `EventFilters.swift` ports
  `eventDateRange` from `web/src/lib/datetime.js` — Monday-start weeks, a
  weekend that is this week's and never next week's, Sunday as the end of its
  week, a `to` that is the day's last whole second — and resolves it in the
  quilt's own zone (`instance.geography.timezone`) rather than the reader's,
  so "tonight" on a Lancaster calendar means Lancaster's night. The bounds go
  out as `from`/`to` instants; `PatchworkAPI.events` also speaks
  `include_past` for a patch's whole calendar.
- **Tags and the search chip narrow through the host patch**, as they do on
  the web: an event has no tags of its own, so the filter resolves
  `node_id` (falling back to `node_slug`) against `session.patches`, and the
  top bar's Filter button is on the Events tab as well (added 2026-09-28). The two
  silences stay distinct — "No events match your filter" with a Clear beside
  it, against "No upcoming events", which is nobody's mistake.
- **Rows** state when, what, where and whose, wear "Community-submitted"
  where the patch is unclaimed, and wear a tier chip — words, never a colour
  — only where the event is not everyone's.
- **The detail** adds the `ends_at` range (same-day reads as one date, judged
  in the event's own zone rather than by slicing the UTC string), the flyer,
  the recurrence caveat, "with X" chips for confirmed links, cross-quilt
  mentions as plain doorways, and "Tickets & details on {host}" for http/https
  only. "Hosted by X" is a door: the patch the session already knows opens
  straight away, and one it does not is fetched by slug first.
- **Add to calendar** builds the `EKEvent` from the event's own fields and
  hands it to `EKEventEditViewController`, so the calendar, alert and
  invitees are chosen where a person already knows how to choose them. The
  quilt's `events/{id}/event.ics` is still fetched, unparsed, for the share
  fallback. Write-only access
  (`NSCalendarsWriteOnlyAccessUsageDescription`): the app puts one night in
  and never reads what else is there. Withheld while a submission is in
  review, where the endpoint 404s.
- **The place, on a map** — a still, non-interactive `Map` with a marker
  where the event carries coordinates, and Open in Maps / Directions handed
  to `MKMapItem`. The web has no equivalent; it stays modest.
- **A patch's own calendar** offers the standing subscriptions from its
  events screen: `webcal://{host}/api/v1/nodes/{slug}/events.ics` and the
  `.rss` feed.

Nothing authenticated is stubbed: no submit, no edit, no RSVP (the web has
none either), and no `scope=my`.

## Discover and search — 2026-09-20

Discovery mode and the search field were brought level with the web's public
(signed-out) organisation of the same two acts.

- **The answer is two halves** (`DiscoverAnswer.split`, checked as a value).
  What wears the picked tags leads — soonest event first, then quilt order —
  and the rest of the quilt is folded behind one counted disclosure rather
  than dropped. A shortlist that silently hid four fifths of a quilt would be
  a verdict rather than an answer, which is exactly the thing discovery mode
  exists not to be. "Show me everything instead" stays one list.
- **Counts come from the quilt** (`tags` → `node_count`, kept whole on the
  session as `tagTerms`; the motif map is now one reader of it rather than
  the reason it is fetched). `node_count` is the quilt's own whole-quilt
  public number; the tree this client holds approximates it, so where the
  server has spoken it wins, term by term, and locally derived counts are the
  fallback for a quilt that will not serve the vocabulary at all. Ordering is
  the web's — count descending, ties A to Z. One deviation, deliberate: a
  term nothing wears is dropped rather than printed as a zero, because here
  the same ranking is also the filter sheet's chips (Lancaster has 11 such
  terms today), and a chip that can only empty the quilt is worse than an
  absent one. The filter sheet itself still prints no counts, as web ADR 022
  requires — a whole-quilt count on a chip that narrows a scoped surface is a
  different quantity.
- **The Moved chip** (web ADR 090) on a Discover row whose patch has a
  `moved_to`, so a patch the community has left is legible in the list rather
  than only on its own page.
- **Search's exit carries the name**: `Suggest “X” as a patch` →
  `{base}/submit?name=X`, gated on `submissions_enabled`, still a website
  link and still not a native form. The narrowing rule is untouched: typing
  finds, and "Show matches on the quilt" is the one act that narrows.
- **Follow is signposted, not stubbed.** The web offers anonymous visitors a
  Follow button that routes to `/login`; a button that only ever goes
  somewhere else is a stub here, so the existing sentence became the link
  instead — Discover's footer to `{base}/login`, and the docked profile's
  line to `{base}/login?redirect=/patches/{slug}` so signing in lands back on
  the patch being read (`PatchworkAPI.loginURL(returningTo:)` /
  `suggestURL(name:)`, added as an extension in `QuiltSession.swift`).
- **One orientation card** (web ADR 040, `Orientation.swift`), the first time
  a quilt opens: an overlay on the foot of the quilt, not a sheet — a modal
  would have to be dismissed before the quilt could be looked at, which is
  backwards for a card that says reading costs nothing. About or a worded
  decline, both answers, remembered per quilt in `UserDefaults` and never
  shown again. The UI tests say which side of that they are testing
  (`--forget-intro` / `--skip-intro`), because `UserDefaults` outlives a
  launch and "the first time" would otherwise be whichever test ran first.

Still nothing authenticated: no Follow, join, or suggest control, enabled or
disabled, and no native submission form.

## App identity — 2026-09-20

The app was native and anonymous: iOS blue on iOS grey, with the quilt the only
thing in it that looked like Patchwork. It now has a room of its own, without
becoming a second copy of the web's textile theme system.

**A palette of five neutrals and one tint, all from the web's tokens.** They
live as colour sets in `Assets.xcassets/Palette`, each with light, dark and
**Increase Contrast** variants, and are reached only through the `Color`
extension in `Palette.swift`: `pwGround` (`#F4F0E8` / `#151820` — `--lt-canvas`,
raw cotton and raw denim, which is also `--color-bg`), `pwSurface` (`#FAF6EE` /
`#1C2028`), `pwBorder` (`#DDD8CC` / `#2A2E38`, the unbleached-thread family the
quilt's own `QuiltInk.thread` draws from), `pwText` (`#2A2520` / `#E0DBD4`) and
`pwTextMuted` (`#6B655C` / `#9B958C`). `AccentColor` was already the web's
`--color-primary` (`#0272B5` / `#39B4F6`) and stays the only tint. Body text
measures 13.4:1 light and 12.9:1 dark against the ground, muted 5.1:1 and
6.0:1, accent-as-text 4.8:1 and 7.0:1 — AA at both ends, with Increase Contrast
only ever moving further from the ground. Nothing branches on the setting: the
asset catalog answers it. The ground reaches the quilt canvas (which had been
`systemGroupedBackground` under a quilt whose ink was taken from this very
colour), List, Events, the picker, the info-stack sheets and the docked
profile; a grouped `List` that stays a list is re-grounded rather than
restyled (`View.groundedList()`), and every material, sheet and system control
is left alone.

**The patch list is the web's card list.** `QuiltBrowser`'s List mode was a
grouped `List` of `PatchRow`s — chevrons and system rows, which read as
settings where the web reads as patches. It is now a `LazyVStack` of
`PatchCard`s on the ground, with the web's anatomy (SocialHome's cards pane,
ADR 078): a 60pt tile miniature drawn from `QuiltBlocks.cuts` and
`QuiltTheme.palette` — the *same* drawing the canvas makes, rotation and
hairline seal included, with the motif disc and the unclaimed mark on the
canvas's own `min(22, side × 0.3)` rule — then the name, `N Members · N Events`
(`N Following · N Events` on a community listing, and the all-time event figure
the card asks for rather than the head's upcoming one), a `Moved` chip, and
three lines of description. The follow heart is a `Link` to
`{quilt}/login?redirect=/patches/{slug}`: signed out is the only state this
client has, so it is an exit rather than a control with a state to fake. The
header carries "Patches", `N results` (or `N of M` while the quilt is narrowed)
and the order menu under the web's names — **Quilt order**, **Recently added**,
**A→Z** — replacing "Name" and "Newest", which were the same two orders under
names nobody would recognise from the site. Quilt order still reads the
placement the canvas is drawing (ADR 074), and a patch with no tile keeps the
tail. Empty states follow the web: "No patches match your filter" with **Clear
filter** and, where `submissions_enabled`, **Suggest a patch**; "No patches here
yet" otherwise. The footer strip still ends the list, and `patchRow` is still
the identifier the browsing UI test taps.

`PatchCard` and `TileMiniature` are their own views so Discover rows and search
results can adopt the language later. They were **not** applied there in this
pass: `Discover.swift` and `SearchResults.swift` were being edited in parallel
and are untouched here.

### Revised the same day, after review

Three things were wrong with the first cut, and the fixes are what the section
above now describes.

**The tint was still a blue.** `--color-primary` is the site's blue, and a blue
tint over a near-white list is stock iOS however carefully it is chosen. The one
tint is now the site's `--color-accent` — rust `#C43D07` light, `#E8734A` dark —
which belongs to the same fabric wall as the tiles. Two failures were found
underneath it. The asset was never actually in force: `Color.accentColor` in
SwiftUI answers with whatever tint the environment carries, and until something
sets it that is the system's blue, so the app had been drawing `#0088FF` while
the asset said otherwise; every reader now names the asset as `Color.pwAccent`.
And the tint was doing a job that is not a tint's: **colouring text**. Links,
"Get directions", "Visit patch website", "N more upcoming", the order menu, the
footer strip and the fine-print eyebrows were all coloured phrases. The rule is
now stated in DESIGN.md and carried by two modifiers: `exitLink()` — ink plus a
small arrow, for a link that leaves the app — and `inkRow()` — ink plus the
platform's chevron, for a text door inside it. A link inside prose is underlined
by `Markdown.inline` rather than coloured. The tint fills controls: the selected
segment, the tab bar's selection, a prominent button, the follow heart, a live
state chip. An event row's date, which used to be tinted, is ink at semibold:
emphasis is weight, and the tint means "you can press this".

**The app had no typeface of its own.** Both of the site's faces are bundled
under `Patchwork/Fonts` as their single variable TTF and registered through
`UIAppFonts` in `Patchwork/Info.plist` (an explicit `INFOPLIST_FILE` that the
generated plist merges onto, since the `INFOPLIST_KEY_*` settings have no
spelling for that key): **Space Grotesk** (`wght` 300–700, PostScript
`SpaceGrotesk-Light`) for body and UI, and **Shantell Sans** (`wght` 300–800,
`ShantellSans-Light`) for display only — the large navigation titles, "Patches",
the quilt's name in the picker and the info stack, and the patch name in the
profile's head. That is the web's own division (`--font` and `--font-display`,
"for big headings where it's personality, not strain"). Both are OFL 1.1, texts
in `docs/third-party/`. `Typography.swift` holds the scale: a weight is a
coordinate on the `wght` axis via `kCTFontVariationAttribute`, clamped to the
axis range because an out-of-range coordinate silently returns the default
instance — Light for both, which is how a whole app can quietly render thin.
Sizes are the system's own per text style and are scaled by `UIFontMetrics`, so
Dynamic Type reaches these faces as it reaches SF Pro; a face that fails to
register falls back to SF Pro at the same style and weight, so nothing can crash
or disappear. `PWType.install()` puts the faces on the two surfaces SwiftUI does
not reach — the navigation bar's titles and the tab bar's labels — and the
quilt's name badges take Space Grotesk through `PWType.baseFont`, as the web
sets them. The root sets the body face as the environment's default, which is
how it reaches the two files this slice may not edit.

**The cards were an iOS row wearing a card's clothes.** They are now the web's
`.patch-card`: a 100pt cover strip of the patch's own block, rendered square and
cropped centre the way `PatchTile.svelte` slices it, with the unclaimed mark on
its top-left and the follow heart in a material chip on its top-right; then a
10 × 12pt body whose name carries an 18pt motif disc inline before it, counts at
12/600 in ink, and two lines of description. The card itself is `pwSurface`, a
1pt `pwBorder` border, the site's 6pt `--radius`, and the site's
`0 2px 10px var(--color-shadow)`, kept faint in light and near-absent in dark;
cards stack with 12pt between them. `TileMiniature` grew a `Fit` so the same
drawing serves the square tile and the cropped strip. On a phone the card is
full width where the web's is half a pane, so the centre crop is tighter than
the site's — the fit rule is the same one, seen through a wider window.

One more thing surfaced while checking: `listRowBackground` applied to a `List`
does not reach its rows, so every re-grounded list had kept iOS's white rows
under the cotton ground. Each now wraps its sections in `Group { … }.listRows()`,
which does propagate, and the event detail joined the grounded screens.

**Re-verified.** 105 unit tests (4 new on the fonts: both faces register, the
weight axis actually moves, it is clamped, and the scale grows with Dynamic
Type) and 5 UI tests, including the accessibility-XXXL pass, on an iPhone 17 Pro
simulator. Captured against Lancaster live in light and dark. Not grounded yet,
deliberately left for a pass that owns those files: the patch calendar,
governance, members, the Label and Display sheets still sit on the system's
grouped background, and `Discover.swift` and `SearchResults.swift` keep the
system type scale and the tint on their own link text.

**Verification.** 101 unit tests (11 new, covering the card's counts wording,
the head's differing one, and the three orders including the unplaced tail and
the A→Z collation) and 5 UI tests pass on an iPhone 17 Pro simulator. Launched
against Lancaster's live 59 patches in light and dark: cards read as one
surface on the textile ground in both, the miniatures match the tiles behind
them, and the profile's head now shares the card's clothes. Not verified: a
physical device, VoiceOver, iPad, and Increase Contrast beyond the declared
values.

## Identity finish — 2026-09-20

Slices D and F landed in parallel, so F could not touch the two surfaces D had
open. This pass closed that gap and then swept the rest: Discover, search
results, the orientation card, the filter sheet, Display, the quilt info stack,
the Label, members, governance, the patch calendar, the remote patch and the
quilt picker are all on `Font.pw.*`, the palette tokens and the ink rules, and
every grouped `List` in the app is now re-grounded.

**The compact card.** Discover's answer and the search results are ranked
shortlists, not the quilt read back, so the full card's 100pt cover strip was
the wrong instrument: eight of them turn an answer into a scroll, and in search
they bury the one row that narrows the quilt. `CompactPatchCard` (PatchCard.swift)
keeps everything the card says — the motif disc before the name, the counts in
the web's own wording, the `Moved` chip — and turns the cover into the quilt's
own 44pt square, `TileMiniature` at its `.tile` fit with both corner marks,
beside the body rather than above it. Only the cloth gets smaller, and a patch
still wears one drawing everywhere it is named. Each surface passes its own
accessibility identifier, so `patchRow`, `discoverRow` and `searchPatch` stay
three names for the same shape.

**One new display moment.** "What are you drawn to?" is now Shantell. It is not
a screen naming itself, which is the face's usual job, but it is the one
sentence the app says in its own voice, it is five words nobody reads at
length, and asking it is the whole reason the surface exists. Everything under
it — the answer's headings included — stays Space Grotesk.

**A third ink rule.** `exitLink()` and `inkRow()` cover a way out and a door.
The sweep turned up a third kind of coloured word the tint had been doing the
work for: an act that is neither — "Try again", "Load more", "Show all tags",
"Show what already happened", "Show the rest of the quilt". `inkAction(_:)`
gives those ink and their own leading glyph. `inkRow()` gained the `fills`
parameter `exitLink()` already had, for a door that shares its line.

**Two things the grounding taught.** A `.plain` list pins its section headers,
and a pinned header sliding over a stack of cards is exactly what a card stack
must not do — Discover and search are `.listStyle(.grouped)` with `plainRow()`
rows (clear background, no rule, 16pt gutter) so the cards sit on the ground
with nothing drawn under them. And the quilt mark lost the tint: it stands in
for the quilt's own icon, and identity is never what a tint means.

**Leftovers, before and after.** `.foregroundStyle(.tint)` 1 → 0,
`Color.accentColor` 0 → 0, `.blue` 0 → 0, `Color(.separator)` as a decorative
border 6 → 0, `Color.secondary`/`.secondary` 78 → 0, `Color.primary` 9 → 0,
system text-style fonts on reading text 15 → 0, and default-coloured `Link` or
`NavigationLink` text 15 → 1. The one that stays is the "Join or sign in on the
web" row inside the account `Menu`: a system menu owns its own colours, the way
the tab bar and the segmented pill do. Six `.font(.footnote)`/`.subheadline`
calls also remain on purpose — four are SF Symbol glyph sizes inside the ink
modifiers and the follow heart, and two are the monospaced variants DESIGN.md
reserves for a technical origin (an atproto handle) and for money read against
money.

**Verification.** 119 unit tests and 6 UI tests pass on an iPhone 17 Pro
simulator, with no test changed. Contrast sampled by pixel on every screen this
pass touched, in light and dark: ink 12.9–14.1:1, muted 5.1–6.0:1, the active
filter chip 5.2:1 light and 7.0:1 dark — AA throughout. Not verified: a physical
device, VoiceOver, iPad, and Increase Contrast beyond the declared values.

## Sign-in — 2026-09-20

The client could read a quilt and nothing else. It can now sign in to one.

**What was built.** One sheet (`SignIn.swift`) with three steps, driven by
`SignInFlow` — a value with a `Step` enum (`.email` → `.code(email)` →
`.username(token, email)` → `.done(User)`), an `Event` enum for what the server
answered, and one `apply(_:)` that is the only thing allowed to move between
steps. Every transition is checked in `PatchworkTests/SignInTests.swift` with
no window open. The account menu in `DiscoveryToolbar` lost "Join or sign in on
the web" and gained **Sign in** when signed out, and when signed in a disabled
row naming the person (display name over `@username`, both in one accessibility
label, because a menu row's label is otherwise its title alone) followed by
**Sign out**. About, Display and Switch quilt are untouched.

**The contract, as the server states it.** All under `api/v1/`. Every non-GET
carries `X-Patchwork-Request: true` and a JSON content type or the quilt
answers 403. `POST auth/magic-link` takes `{email}` and answers 200 whether or
not the address has an account — it will not tell a stranger who is registered
— and 400 with a sentence only when the address is not an address. `POST
auth/magic-link/verify` takes `{email, code}` and answers with either the user
or `{"status":"username_required","signup_token":…}`; every failure is the same
400, and five wrong codes burn the code. `POST auth/signup` takes
`{token, username, display_name}` and answers with the user. `GET auth/me` is
the user or 401. `POST auth/logout` is 200. The username rule
(`^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$`) is mirrored client-side for the inline
hint only; the quilt still has the last word.

**The cookie decision.** Sessions are a cookie (`patchwork_session`, HttpOnly,
Secure, SameSite=Lax) and there are no bearer tokens, so the app's `URLSession`
stopped being `.ephemeral` with `httpShouldSetCookies = false` and became
`URLSessionConfiguration.default` over `HTTPCookieStorage.shared` — the
system's own jar, private to this app, shared with no web view. That is what
lets a session survive a relaunch. It also settles multi-quilt sessions for
free: cookies are host-scoped by the cookie standard, so a reader signed in to
two saved quilts keeps two sessions, one quilt's cookie is never sent to
another, and clearing one cannot touch the other. Nothing in the client indexes
sessions by quilt, and the host scoping is checked in a test with its own
`HTTPCookieStorage`. `auth/me` is asked only when a `patchwork_session` cookie
exists for that host, so a reader who has never signed in still makes exactly
the public reads they always did — a signed-out launch is unchanged. Signing
out clears the cookie whether or not the POST succeeded: a 401 means the
session was already gone, and anything else means the quilt could not be
reached, which is not a reason to stay signed in on the device.

**What stays on the web.** Joining a patch, following, suggesting a patch,
posting, governance and editing an event are still website links, and the
profile footer and Discover links were left alone. The dashboard and
notifications still wait. Passkeys wait too: they need an associated-domains
entitlement per quilt, and a client that connects to any quilt by address
cannot declare that list ahead of time — the six-digit code is the flow that
works for an unbounded set of hosts.

**Offline.** `PreviewData.post` answers the three writes: code `123456` signs
in the sample reader, `654321` hands back a signup token, anything else is the
server's own "invalid or expired code". `PreviewData.signedIn` stands in for
the cookie, so the whole flow runs with no network.

**Verification.** 129 unit tests and 8 UI tests on an iPhone 17 Pro simulator;
the flow was also driven by hand in preview and read in light mode. Two things
that only showed up on screen: SwiftUI parses a placeholder string literal as
Markdown and drew `you@example.org` as a blue link (now `Text(verbatim:)`), and
a `TextField` whose binding rewrites the text as it is typed shows one thing
while holding another, so the code is normalised when it is sent rather than
under the cursor. Not verified: a live quilt, a physical device, VoiceOver, the
five-wrong-codes lockout, and cookie persistence across a real relaunch.

## Following — 2026-09-20

Sign-in landed and the account did nothing. This slice makes the web's first
authenticated acts native: follow, join, leave, unfollow, withdraw — and the
Dashboard the tab bar has been leaving a space for since the shell was drawn.

**One decision, as a value.** `Relationship.swift` holds the whole of what the
web keeps in `PatchRelationship.svelte`, with no view in it:
`Relationship.resolve(node:standing:)` answers `.none` (banned, or moved —
the moved notice already explains it), `.holding(role)`, `.requested`, or
`.offering(Offer)` with Follow and Join as independent offers. The rules are
the server's, in the server's order:

| Patch | Follow | Join |
| --- | --- | --- |
| public, claimed, `open` | yes | "Join" |
| public, claimed, `approval_required` | yes | "Request to join" |
| public, claimed, `invite_only` | yes | no — the patch does the asking |
| public, unclaimed | yes | no — there is nobody to be a member of |
| private, claimed, `open` | no | "Join" |
| private, unclaimed | no | no (no control at all) |
| moved, or the reader banned | no | no |

Active rows wear a mark instead — Following with a heart, Member with people,
Admin with a wrench — over a menu holding one exit: Unfollow for a follower,
Leave for the other two, with the server's "cannot leave as the only admin"
printed as the server words it. A pending row is "Membership requested" with
"Withdraw request", because withdrawing is not leaving (web ADR 088).

**One index.** `QuiltSession` gained `memberships`, filled by `me/nodes` after
`refreshAccount` succeeds and again after every act, cleared by `signedOut()`,
and read by `standing(for:)`. The acts — `follow`, `unfollow`, `join(_:message:)`,
`leave`, `withdraw` — all return the server's own `status` and all end by asking
the index again, which is what stops the profile, a card and the Dashboard from
holding three different opinions about the same patch. A 401 anywhere is a
state, not a failure: `signedOut()`, and the signed-out rendering is already
correct.

**The contract.** `GET me/nodes` (`{"items":[Membership]}`, and a bare array is
read the same way), `GET nodes/{slug}` now also carrying `is_member`,
`is_admin`, `membership_role`, `is_banned` and `membership_policy` where there
is a session, `POST nodes/{slug}/join` with `{"role":"follower"}` or with
`{}`/`{"message":…}` answering `active` or `pending`, `POST nodes/{slug}/leave`,
`POST nodes/{slug}/withdraw`, and `GET events?scope=my&from=…&limit=20` — the
first read this client makes that is about the reader rather than about the
quilt. Every POST carries the CSRF header the existing `post` already sent.

**Where the controls are.** In the profile's head, under the counts they
change, with the accent filling them because they are controls and a standing
in ink because it is a fact. On a card, the heart stopped being a link to the
website and became the control it looks like: signed out it opens the sign-in
sheet, a stranger gets the outline heart, a follower the filled one with a
confirm behind it, a member or admin their role's mark and no act at all, and a
pending request nothing. While the call is out the chip holds a spinner — a
card must not fill a heart before the quilt has answered it. The chip is laid
over the card after the card has been combined into one accessibility element,
so the patch still reads as one thing and the heart is still its own control at
its own 44pt target.

**The three website doors closed.** The profile's "Joining, following, and
posting are available on this quilt's website…", Discover's
"Following needs an account — reading never does." and the card's heart were
all `{quilt}/login` links. The first two are now the native sheet ("Sign in to
follow or join." on the profile) and the third is the control. "Visit patch
website" stays: that one is still the website's.

**The Dashboard** arrives with the account and leaves with it, between Discover
and Search, in both the iOS 18 `Tab` form and the fallback; a signed-out
selection falls back to Quilt. It reads: the welcome, **Attention needed** (the
next things happening on the reader's own patches, from `scope=my`, first three
with "See all N"), then Managing · Member of · Following · Requested, each a
stack of `CompactPatchCard`s built from the membership rows — the patch from
the quilt's own tree where it is there, so the row wears the cloth the canvas
draws, and a name-only card where it is not, rather than an invented tile.
Pending requests per patch the reader admins and open proposals per patch they
are in ride the rows as ink badges, both best effort and both simply absent
where the read failed; a full page of twenty with a cursor behind it says
"20+" rather than printing a number it would have to be wrong about.

**Still the web's, and not stubbed here:** invitations, the noticeboard and
notices, RSVP (the web has none either), creating patches and events, editing
an event, approving or declining the requests the Dashboard counts, voting,
claiming, moderation and notifications. No disabled control stands in for any
of them.

**One thing the keyboard taught.** The join sheet's primary button sat at the
end of its scroll, which on one OS version put it behind the keyboard the
sheet's own field had just raised — the act was unreachable exactly when it was
wanted. It now rides the foot of the sheet in a bar, above whatever comes up,
and the scroll dismisses the keyboard interactively.

**Verification.** 151 unit tests (22 new: every branch of `resolve`, the
membership index including a pending row's absent role, `me/nodes` as both an
object and a bare array, the envelope-or-node reading of the reader's own
standing, the Dashboard's grouping and its "20+", and the `scope=my` query) and
11 UI tests (3 new: the signed-out heart opening the sheet, follow from a card
through the Dashboard and out again from the profile's standing, and
request-to-join then withdraw). Not verified: a live quilt, a physical device,
VoiceOver, the Managing and Member-of sections (the offline fixtures grant a
reader no admin row by design), the badge reads, and every server refusal —
the 409s and the only-admin sentence are rendered but were not provoked. The
three new UI tests also pass on an iPhone 18 Pro (iOS 27) simulator, which is
where the keyboard above found the sheet's button.

## Notifications — 2026-09-21

The shell had left a space for the bell since it was drawn, and the README
has said "Notifications still wait" since the first cut. This slice ends the
wait: the web's bell and its notifications page, native, for a signed-in
reader, and nothing at all for anyone else.

**The count is the session's.** `QuiltSession` gained
`@Published private(set) var unread`, filled after `refreshAccount` and
`signedIn` succeed, cleared by `signedOut()`, and read by the bell and by one
row on the Dashboard — one number, so two surfaces cannot disagree. Its
arithmetic is a value, `UnreadTally`: reading one subtracts and floors at
zero, dismissing one subtracts *only if it was unread*, and mark-all-read and
clear-all both go to zero rather than down by the rows on screen, because both
empty the whole table server-side. The sixty-second poll is reconciliation and
nothing else — the web learned that the hard way (issue #55: a badge that moved
only on the poll sat there for up to a minute after the thing had been read,
which reads as broken). The poll is a `Task` the session owns, started when a
reader signs in, stopped by `signedOut()` and by leaving the foreground, and
driven from `QuiltHome`'s `scenePhase` because that is the one view there is
exactly one of — the discovery toolbar is on four surfaces at once and would
have started four polls. Coming back to the app reads the count again on the
way in. Every read of it is silent on failure: a stale badge beats an error
nobody asked for.

**The contract.** `GET notifications?limit=20[&after][&unread=true][&category=]`
→ `{"items":[…],"next_cursor":""}`; `GET notifications/count` → `{"unread":N}`;
`PATCH notifications/{id}/read`; `POST notifications/read-all`;
`DELETE notifications/{id}`; `DELETE notifications` (everything, not the page in
view). A row is `id, user_id, type, title, body, link, read_at?, created_at`,
and **unread is the absence of `read_at`** — not a null, not a flag. `PATCH` and
`DELETE` are the first two verbs this client has needed beyond `GET` and
`POST`; they arrived as `patchVoid`/`deleteVoid` sharing `postData`'s own body,
because the quilt's CSRF gate refuses a request without `X-Patchwork-Request`
whatever the method is and a second copy of that request would drift. `All` is
the *absence* of the category parameter rather than a value of it: the server
rejects a category it does not know rather than answering with an empty list,
and a mistyped filter must not read as "you have nothing".

**Where a link goes.** `NotificationLink.route` is a pure function over the
site-relative path the server builds in `internal/weblink`, and it is the whole
of the slice's routing: `/patches/{slug}` docks the patch, `…/events` is the
calendar, `…/members` (with or without `?status=pending`) the roster,
`…/governance` the overview, `…/governance/docs/{id}` a charter, `/events/{id}`
an event, and `/quilts/{host}/patches/{slug}` the read-only remote patch.
Everything else — setup, the noticeboard, the submission form, a quilt's admin
pages, anything unknown — is an exit to the website through
`webURL(_:query:)`, which is the same rule the rest of this app follows about
surfaces it has not built: an exit, never a stub.

One thing the spec for this slice and the live server disagree about, and the
client honours both: the spec calls a proposal
`/patches/{slug}/governance/proposals/{id}`, and `weblink.Proposal` actually
emits `/patches/{slug}/governance/{id}` with no word in front of the id — the
`docs/` segment is the *only* thing separating a charter from a proposal. Both
shapes route to `ProposalDetailView`, and both are tested. Reading only the
spec's shape would have sent every vote notification on a live quilt out to
the browser.

Native destinations are pushed inside the sheet's own `NavigationStack`, and
they carry the object rather than the id, because every detail screen in this
app takes what its caller already knows and reads the rest back — so a
proposal is fetched from `proposals/{id}`, a charter from `governance/{id}`, an
event from `events/{id}` and a patch from the quilt's own tree (or `nodes/{slug}`
where the tree does not carry it) before the push. Docking a patch is the
shell's job, not the stack's, so that one closes the sheet first.

**What it looks like.** The bell is a row of the account menu in
`DiscoveryToolbar` — "Notifications", with "N unread" under it while there is
a count — drawn only where `session.me != nil`, and the count rides the
account glyph as a badge so a reader sees it without opening the menu. It
was first a second bar button beside the account, which squeezed the search
field on a phone; the field is the bar's one wide thing and keeps its width.
The account button says "Account, N unread" to VoiceOver. The sheet is a `NavigationStack` titled Notifications on
the app's ground: the web's own chips in the web's own order plus an
"Unread only" toggle, then a stack of cards — the type's mark from the web's
`NotifIcon` table in SF Symbols, the title, two lines of body, the relative
time worded exactly as the web's `timeAgo` ("just now", "5m ago", "3h ago",
"2d ago", then the app's own short day), and the unread dot in the accent.
Tapping a row marks it read and then opens it; a swipe or the row's own menu
dismisses it; the toolbar's menu holds Mark all read and a Clear all behind a
confirmation that says out loud that it clears the quilt and not the page.
"Load more" while there is a cursor, pull to refresh, and an empty state that
names the filter it is empty under — "Nothing unread under Governance", not
"you're all caught up", which would be a lie to somebody who has narrowed the
list. The Dashboard gains one row at the top while there is anything unread,
opening the same sheet.

**Two things the screen taught.** The chips were a horizontal scroller and the
one pushed off the end was "Unread only" — the only chip on the row that is not
a category, and the one most likely to be wanted; they wrap now, in the
`FlowLayout` the filter sheet already uses. And the Filter button's badge is
offset out past its glyph, which works at the bar's leading edge and does not
beside the account menu: the bell shares a capsule with it, and the overhanging
badge was clipped square down its right-hand side. It is hung on a frame given
room for it instead, with the balance put back by the opposite padding, and the
padding is unconditional so the bell does not shift when the count arrives.

**Offline.** `PreviewData` answers both reads and all four writes against an
in-memory set of six rows seeded at sign-in and emptied at sign-out — one per
category, two unread, one pointing at a patch, one at an event, one at a
proposal, one at a charter, one at the noticeboard (which must leave for the
website) and one warning with no link at all, because a warning has nowhere in
this app to send anybody. The set honours `unread=true`, `category=` and
`after=`, the count is read off it, and the writes mutate it. Nothing a
signed-out fixture answers changed: both reads are 401 without a session.

**Still the web's, and not stubbed here:** notification preferences, the
noticeboard, invitations, RSVP, creating or editing anything, approving the
requests the Dashboard counts, voting, claiming and moderation. A warning is
rendered and read; it is answered on the website.

**Verification.** 174 unit tests (23 new: every link shape including the bare
governance id and the unknown path, the exit's query splitting, the icon table
prefix by prefix and the unknown type's bell, `timeAgo` at every boundary and
past a month, the badge's arithmetic in all four directions, the chips and the
query they build, the empty line per filter, and a row decoded with and without
`read_at`) and 13 UI tests (2 new: the badge showing 2, a row opening the event
inside the sheet and the badge dropping to 1; and mark-all-read emptying the
badge with the filtered empty state on the way). Screenshots of the badged
bell, the sheet and a filtered empty state were read for clipped text and for
iOS blue. Not verified: a live quilt, a physical device, VoiceOver, the poll's
sixty seconds actually elapsing, the foreground transition, paging past twenty
(the fixtures hold six), `99+`, and every server refusal — the 404s and 401s
are handled but were not provoked.

## My Quilt and the switcher — 2026-09-28

The quilt gained its third lens, and holding the Quilt tab opens a card
instead of the full picker.

- **Scope is the server's.** `QuiltSession.scope` is `.whole` or `.my`.
  Changing it reloads the tree with `scope=my` (`QuiltScope.query`), and the
  Events tab's quilt-wide list sends the same value through
  `PatchworkAPI.eventsQuery(…, scope:)`. A patch's own calendar never does.
  The filter and the search chip are left alone when the scope moves (web ADR
  022); an answer that arrives after the reader has switched again is dropped
  rather than drawn under the wrong lens.
- **The whole quilt is where everything starts.** Nothing persists the scope
  and there is no "start on My Quilt" setting yet (web ADR 035 makes that an
  account preference, which this client does not have). Signing out, or a
  launch with no session, puts the scope back to the whole quilt.
- **What is not scoped.** Discover asks about the whole quilt and the search
  field finds across it, so both read `wholeQuilt` — the unscoped tree, kept
  beside the scoped one — and Discover breaks its ties by the whole quilt's
  placement. The tag ranking is read off the whole tree too. The Dashboard is
  unchanged.
- **The events filter reads the whole tree.** `scope=my` admits a night hosted
  by a patch the reader does not hold when a followed patch is a confirmed
  link on it (web ADR 032, and the server's `events.go`). The filter resolves
  that host's tags against the whole quilt, or it would drop the night the
  moment any chip was on.
- **The card.** A sheet at the medium detent: this quilt's two lenses with a
  checkmark on the live one (My Quilt only for a signed-in reader; a muted
  line otherwise), the other saved quilts, which connect directly, and Find a
  quilt, which closes the card and opens the picker as its own sheet once the
  card has gone. Pushing the picker inside the card was tried on paper and
  rejected: its Done would have popped back to the card instead of closing,
  and Explore on the quilt already open would have left the card up.
- **The tab says which lens is on**: "Quilt" or "My Quilt", both branches of
  the tab builder, with `quiltTab` as a stable identifier.
- **Empty states name the lens.** "Nothing in My Quilt yet" (Show the whole
  quilt; Find patches in Discover), "No patches match your filter in My
  Quilt" (Clear filter; Show the whole quilt), and on Events "No events in My
  Quilt" and "No events match your filter in My Quilt". The whole-quilt
  wording is unchanged.

**Offline.** `nodes/tree?scope=my` answers only the patches in `heldNodeIds`
— after sign-in, the Listening Room — and an empty tree while signed out. The
feed's existing `scope=my` also admits the studio's open night, because the
Listening Room is a link on it, which is the server's rule too.

**Verification.** 176 unit tests and 14 UI tests pass on the iPhone 17 Pro
simulator. Two unit tests are new (`scope=my` on the events query only
when asked for; `QuiltScope`'s query and value) and one new UI test: signed
out, the card offers no My Quilt; signed in, My Quilt shows the Listening
Room's tile and not the studio's, the tab reads "My Quilt", Events lists the
Listening Room's night and the linked open studio but not the studio's own
circle, the whole quilt comes back from the card, and Find a quilt reaches the
picker and explores the quilt again. The card is opened by holding the tab
(`press(forDuration: 0.8)`), which XCUITest drives on the iOS 26 simulator.
`testBrowsePatchEventAndSwitchQuilt` now reaches the picker through the card.
Not verified: a live quilt, a saved second quilt in the card (the fixtures do
not save quilts), VoiceOver, and the My Quilt empty states on screen (the
fixture reader always holds one patch).

## Account settings and deletion — 2026-09-28

A signed-in reader has Settings now, and can delete their account from it.
Reference: the web's `AccountSettings.svelte`, `SecuritySettings.svelte`,
`StepUpPrompt.svelte` and `lib/stepUp.js`, the handlers behind them
(`auth.go`'s `UpdateMe`, `StepUpStatus`, `StepUpRecovery`; `recovery.go`;
`sessions.go`; `account_deletion.go`; `middleware.WriteSudoRequired`), and web
ADRs 017, 035, 086 and 099.

- **Shape.** A gear row in the account menu, between Notifications and Sign
  out, opens a sheet holding a `NavigationStack`: the reader's name and handle,
  then Profile · When you open Patchwork · Discovery · Security · Your data as
  rows, and Delete account alone at the foot in the system red. Each row
  pushes one page. This is the web's own phone layout since PR #363 — one
  level on screen at a time, the rare things last, the decision within reach
  without scrolling past explanation, finger-sized targets, actions wrapped
  under what they act on — and it is also simply how an iOS settings screen
  is built. The web's moving, contact card, personal feed and steward listing
  are not here; they stay the website's, and nothing stands in for them.
- **Only what changed.** Profile's Save (in the bar) sends `PATCH auth/me`
  with the fields that differ from the account and nothing else, links
  trimmed and a link with no address dropped; an untouched page cannot be
  saved. `ProfileDraft.changes(from:)` is the whole rule, as a value. After
  any save the account is read back (`refreshAccount`), so the menu and the
  index say what the quilt now holds. `User` gained `links`,
  `startOnMyQuilt` and `hideAmendedLinings`, all optional and defaulted so a
  sign-in answer, which carries none of them, is still a user.
- **Start on My Quilt, once.** Web ADR 035: the preference fires at a cold
  load and never re-asserts. `LaunchLens` holds the rule — the first answer
  about the account in a session object's life decides (a person with it on
  opens on My Quilt; with it off, or nobody signed in, the question is
  settled all the same), a failed read decides nothing, and a sign-in from
  the sheet is never a cold load. So switching it on changes the next launch
  and the page says so; switching it off mid-launch leaves the lens alone.
- **Discovery.** `hide_amended_linings` is applied by the server to the
  tree, strictest-wins against the quilt's own policy and never to
  `scope=my` (`tree.go`, `lining_update.go`). The toggle saves, then reloads
  the tree — the whole tree too, even under My Quilt, since Discover and
  search read it.
- **Refusals with names.** `APIError` kept only a sentence. It now has
  `.refused(Refusal, status:)` for a body that carries a `code` — the
  sentence, the code, and `patches` where a deletion is blocked — while a
  body with only `{"error"}` is still `.message`, so every refusal already
  handled reads exactly as before. `errorDescription` is still the server's
  sentence.
- **Step-up.** `StepUpGate.run` does the act; on a 403 coded
  `sudo_required` or `passkey_required` it presents the Confirm sheet and,
  once the sheet reports the window open, does the act once more — once,
  because a second refusal means something is wrong. The sheet answers
  after it has gone (its `onDismiss` resumes the act), so whatever follows —
  dismissing Settings, signing out — never races a sheet on its way down.
  The sheet reads `auth/step-up` first; if a window is already open it
  closes without asking (a recovery sign-in opens one on arrival); otherwise
  `StepUp.decide` picks one of three states: a code field when
  `recovery_ready > 0`; "sign out, then sign back in with one of them" when
  the account holds unused codes that are all newer than this sign-in; and
  "you have none yet", with a door to making a set, otherwise. "Holds" is
  counted as unused codes rather than codes ever made, because a spent set
  cannot sign anybody back in. The four failures (`no_recovery_codes`,
  `recovery_codes_too_new`, `invalid_code`, 429) are four sentences, and the
  two that no other code will fix carry their door under the sentence. A
  spend that leaves two or fewer stops to say so. The code is normalised as
  `NormalizeRecoveryCode` does it — trimmed, lowercased, hyphens and spaces
  out — rather than uppercased: the server's alphabet is lowercase. Passkeys
  are not offered or mentioned on the sheet; Security says in one muted line
  that this build has none.
- **Deletion.** Its page says what is erased, what stays and why, that the
  username is retired, and that none of it can be undone; the button is armed
  only by the exact username and asks once more in a confirmation dialog.
  `sole_admin` lists the patches as doors that dock them on the quilt;
  `last_instance_admin` shows the quilt's sentence. On `{"status":"deleted"}`
  the cookie is cleared, Settings closes, and only then is the session
  signed out (which takes the Dashboard tab with it) and the alert "Your
  account has been deleted." shown on the quilt. The same order carries a
  sign-out chosen on the Confirm sheet. How Settings was left
  (`SettingsExit`) is acted on in the presenting toolbar's `onDismiss`,
  because a sheet cannot present over a sheet that is leaving and the
  Dashboard's own toolbar may be the one that presented it.
- **Recovery sign-in.** The email step ends in "Use a recovery code
  instead": a username and a code, `POST auth/recovery`. The server gives one
  sentence for every wrong pair so a stranger learns nothing about which
  usernames exist, and the sheet does the same; the rate limit gets its own.
  `SignInFlow` has a `.recovery` step and three new events, walked in the
  same tests as the rest.
- **Security and data.** Recovery codes show "N of M remaining" or "No
  recovery codes yet"; a new set is shown once, monospaced, with Copy
  (`UIPasteboard`) and Share (a share sheet of the codes as text) under it.
  Devices are listed with "This device" tagged, Sign out under every other
  row and on its swipe, and Sign out other devices behind a confirmation.
  The export and the seamrip are fetched with a new `download(_:)` that
  keeps the response headers, written under the file name the quilt gave in
  `Content-Disposition` (path stripped) and handed to the share sheet.
- **One visual fix in passing.** A prominent button's label was drawing in
  ink, not white, because the app's root sets ink on every descendant; the
  sign-in sheet's buttons had the same fault. Every filled button these
  sheets draw now sets its white itself (DESIGN.md, `primary-action`).

**Offline.** `PreviewData.write` answers `PATCH`, `PUT` and `DELETE` as well
as `POST`. The fixture reader holds `PreviewData.recoveryCodes`, ten fixed
codes treated as older than any preview session; a set generated during a
session counts as too new until the next sign-in, which is how the second
state can be reached. `auth/step-up` counts only usable codes, a code opens a
window flag, `DELETE users/me` answers the passkey-less 403
(`passkey_required`, which is what the server sends an account with no
passkey) until that flag is set and 400 unless `confirm_username` is
`samplereader`, and then signs the fixture out and resets its memberships and
notifications. `auth/recovery` takes `samplereader` and any unused fixture
code and arrives with the window open. Two sessions (this device and a
laptop), the export (JSON) and the seamrip (a zip's magic number) round it
out. Every preview launch writes its session and account to `UserDefaults`,
and only a launch with `--preview-resume` reads them back — the one way to
see a cold launch honour Start on My Quilt; every other test still starts
signed out.

**Verification.** 202 unit tests and 17 UI tests pass on the iPhone 17 Pro
simulator. The 26 new unit tests: what a profile save sends (untouched sends
nothing, only the changed field, links trimmed and addressless ones dropped,
an emptied bio sent empty, one field per switch) and the account's new
fields decoding; the launch rule (fires once, a reader with it off settles
the launch, a signed-out launch and a sheet sign-in never fire); the Confirm
sheet's three states including a spent set; the code's normalisation, and
that the fixture codes are all in the alphabet; four distinct failure
sentences and the running-low line; `APIError` with a code, with `patches`,
without a code and with an empty one; the file name from
`Content-Disposition`; session times in both of the server's spellings; and
the recovery sign-in steps, their refusals and events out of turn. The three
new UI tests (`AccountTests`): Settings saves a display name the account menu
then wears, Start on My Quilt leaves this launch on the whole quilt and a
resumed launch opens on My Quilt (and it is switched off again); Delete
account is armed only by the exact username, the dialog stands before the
call, the Confirm sheet refuses a wrong code in its own sentence and takes a
fixture code, and the reader ends on the quilt signed out with the alert and
no Dashboard; and a recovery-code sign-in refuses a wrong pair, lands signed
in with a Dashboard, and Security then shows 9 of 10 remaining with this
device tagged. Screenshots of the index, Profile, the deletion page, the
Confirm sheet and the goodbye were read for clipped text and colour. Not
verified: a live quilt, a real recovery code against a real step-up window,
the too-new and no-codes states on screen (they are unit-tested and reachable
offline, but no UI test walks them), the `sole_admin` and
`last_instance_admin` refusals on screen, the share sheet's destinations, a
seamrip of real size, VoiceOver, and a physical device.

## Posting and suggesting events — 2026-09-28

A signed-in reader can add an event to a patch, the way the web's
`/events/new?node=slug` door does, and the app says whether it will publish
or wait for review before anybody fills the form. Reference: the web's
`EventForm.svelte`, `patchWorkspace.js` (`eventPostingRight`),
`PatchBarMenu.svelte`, `PatchEvents.svelte` and `datetime.js`; the server's
`CreateEvent`, `GetEvent`, `validateRecurrence`, `validEventVisibility`,
`validateImageRef`, `validateEventURL` and `writeMovedAway`; and web ADRs
026, 045, 067, 079, 090, 093, 2026-09-18 and 2026-09-19.

- **The rule is a value.** `EventPosting.right` is `eventPostingRight`,
  line for line, with the web's defaults: signed out or banned, nothing;
  the instance admin, direct; a moved patch refuses strangers but keeps
  its own members and admins; an unclaimed patch is direct for a trusted
  contributor (`viewer_trusted`, a field the `PatchResponse` envelope now
  keeps) and a suggestion for everybody else while the quilt's
  `submissions_enabled` holds; a claimed patch is direct for a member or an
  admin and a suggestion only where it says `accept_event_suggestions`.
  "Member or admin" is the membership index's active role — a follower is a
  visitor and a pending request is not a membership, which is the bug the
  web's own test names. `Patch` gained `timezone`,
  `accept_event_suggestions` and `follower_permissions` (only `events` is
  decoded).
- **Two doors, one decision.** `QuiltSession.eventDoor(for:envelope:)`
  reads the rule's inputs and answers none, the sign-in sheet, or the form
  with its right. The calendar fetches `nodes/{slug}` for itself (and again
  when the reader changes), because the tree row carries neither the
  envelope nor the patch's switches; the profile already has the envelope.
  The labels are the web's: "New event" and "Suggest an event".
- **Signed out, a door where a stranger would be taken.** The web draws
  none. Here the door is the sign-in sheet, labelled "Suggest an event", on
  exactly the patches a signed-in stranger could suggest to — so the sheet
  never leads to a form that refuses — and a member who signs in through it
  finds "New event" in its place.
- **The calendar's door is in the bottom bar.** It was first a top-bar
  button beside Subscribe and Done, and the system drew it as a bare plus:
  the one control whose words are the point said nothing. The bottom bar
  holds a plus and the words, under the calendar it adds to. The profile's
  door is an ink row under the Events glimpse.
- **The form** is a sheet in the step pattern (heading, sentence, fields,
  refusal, filled act at the foot), with the web's sentences under the
  heading and the web's field order: title, description, who can see this
  (direct only), location, event page, image address, the description of
  the image once there is an address, starts, and an end behind a switch.
  The act is disabled until there is a title. `EventDraft.problem()` says,
  before sending, what the server would refuse — the image rule and the
  link rule in the server's order and words (lengths in bytes, as Go
  counts them), then the title, then an end that is not after its start —
  and the server's own sentence is shown for anything else, first letter
  raised. A disabled filled button's white label vanished on the system's
  grey; a disabled one is muted ink now.
- **Time belongs to the place.** The pickers carry the patch's zone
  (`timezone`, else the quilt's) through `\.timeZone`, the start opens on
  the next whole hour on that clock, and "Times are in …, this patch's
  timezone." appears only where that clock differs from the device's, by
  the web's `sameZoneAsViewer` test (a name match, else the same offset and
  abbreviation now). The instants travel in the web's `toISOString()` shape,
  to the minute, and no `timezone` is sent, so the event inherits its
  patch's zone (ADR 045) rather than freezing a copy of it.
- **What travels.** `EventDraft.body` trims every field, leaves out every
  empty one (the server reads absence and `""` alike), leaves out `ends_at`
  without an end, drops an image description once its address is gone,
  never sends `timezone` or `recurrence`, and sends `visibility` only when
  posting directly — a suggestion is public whatever it asks for, so the
  control is absent and nothing is sent.
- **The ending is the server's.** A 201 whose `status` is `active` closes
  the form and opens `EventDetail` from where the door was (a push once the
  sheet has gone), with the calendar or the glimpse and the head's count
  read again. `pending_review` replaces the form with the web's card —
  "Submitted for review", "The patch admins (or quilt admins) will look at
  it…" — and one Done. The status decides, not the door's prediction. A
  pending suggestion is on no list; nothing tries to list it. No
  notification is involved either way (ADR 093).
- **Refusals.** A 403 in the server's words ("this patch does not accept
  event suggestions", "community submissions are disabled on this
  instance"), a 400's validation sentence, and the moved-away 403, whose
  `moved_to` rides beside the sentence: `Refusal` keeps it and `APIError`
  now treats a body carrying it as a named refusal, so the form offers the
  new home as an exit link. A 401 signs the session out and the form closes
  with it.

**Offline.** `PreviewData` answers `POST events` with `CreateEvent`'s own
order and sentences: the image and link checks, recurrence, the required
three, the tier's spelling, the patch, then who posts directly. The fixture
reader now starts as a follower of the Listening Room (which says
`accept_event_suggestions: true`) and a member of the Repair Cafe
(`extra-6`), whose node answers `is_member`/`membership_role` and whose
`follower_permissions.events` is false, so the ceiling shows offline; the
studio says `accept_event_suggestions: false` and a non-member's suggestion
there is refused in the server's sentence. The membership sits on an extra
so the follow and join tests, which read the studio and the Listening Room,
are untouched. Every node fixture carries `timezone` and the envelope's
`viewer_trusted: false`. An active post joins the fixture feed (now sorted
by `starts_at`, as the server orders it); a pending one is answered only by
`events/{id}`, to a signed-in reader.

**Verification.** 233 unit tests and 20 UI tests pass on the iPhone 17
Pro simulator. The 30 new unit tests (`EventPostingTests`): the posting
rule through every branch — signed out, banned (over every other right),
the instance admin, trust on an unclaimed patch and its worthlessness on a
claimed one, the submissions switch (which never gates a member), the
patch's own switch, a moved patch refusing strangers and keeping its own,
and the follower and the pending request who are not members; the door
signed in and signed out; what a draft sends (trimmed, empties absent, no
end, no tier on a suggestion, a tier on every direct post, no zone, no
recurrence, an orphaned image description dropped, the instant to the
minute); the image and link rules in the server's sentences, bytes
counted as Go counts them, and the draft's checks in the server's order;
an end after its start; the reviewers' words; the zone chosen, said only
where it differs (New York and Detroit agree), and the next whole hour on
the patch's clock, Kolkata's half hour included; the tier's ceiling; the
node's new fields decoding; and a moved patch's refusal keeping its
address. The three new UI tests (`EventPostingFlowTests`): signed in, the
Listening Room's calendar says "Suggest an event", the form says it will
be reviewed and offers no tier, the button waits for a title, and a title
and the default start end on "Submitted for review" with the patch admins
named, and Done returns to a calendar that does not list it; the Repair
Cafe, reached from the Dashboard, wears "New event" under its glimpse and
on its calendar, its form offers Public and Members only with the ceiling's
line, and a post opens the event's page and then sits in Upcoming; signed
out, the Listening Room's door opens the sign-in sheet. Every existing test
passes unchanged. Screenshots of both doors, both forms, the times, the
card, the posted event and the calendar after it were read for clipped
text and colour. Not verified: a live quilt (the server's `CreateEvent`
was read, not called), the moved-away and submissions-disabled refusals on
screen (both are answered by the fixtures and unit-tested, but no UI test
walks them), posting from the profile glimpse's own row through to the
pushed event page (the calendar's door is the one the UI test posts
through), a trusted contributor and an instance admin (the fixture reader
is neither), the zone note on screen (the simulator keeps New York time,
as the fixtures do), a 401 mid-form, VoiceOver, Dynamic Type at the
accessibility sizes on this form, and a physical device.

## Voting, ballots and discussion — 2026-09-29

A member can take part in a patch's decisions natively: vote on a
proposal and change the vote, cast an election's ballot, stand or put
somebody forward while nominations are open, and discuss any proposal.
Reference: the web's `ProposalDetail.svelte`, `VoteSection.svelte`,
`StickyVoteBar.svelte`, `ProposalStatusBanner.svelte`, `ElectionPanel.svelte`,
`CommentThread.svelte` and `ProposalList.svelte` (origin/main c30f99d, with
the Sept 28 mobile pass as the phone layout); the server's `proposals.go`,
`elections.go`, `election_view.go`, `comments.go` and the overview in
`templates.go`; and web ADRs 041, 044, 047, 048, 050, 051, 092, 097, 098,
106, 107, 109 and 117.

- **The boundary grew by nine writes and two reads.** `POST
  proposals/{id}/vote`, `PUT proposals/{id}/ballot`, `POST
  proposals/{id}/candidates`, `DELETE proposals/{id}/candidates/me`, `GET`
  and `POST proposals/{id}/comments`, `PATCH` and `DELETE comments/{id}`,
  `POST comments/{id}/reactions` and `DELETE
  comments/{id}/reactions/{emoji}`; and `nodes/{slug}/members` paged for the
  nominee picker. `PUT` is new to this client. `Proposal` now decodes the
  whole detail payload (every key optional, so a list row is still a
  proposal; `voting_ends_at` and `election_turnout` may be JSON null), and
  `GovernanceRules` the whole frozen `voting_terms`.
- **The rules are values.** `VoteRules` (banner, time left in the web's
  three spellings, quorum, threshold, terms and the tenure in force, who
  owes a ballot, the ballot's gate, the election's words) and `Discussion`
  (the six reactions and their order, who may comment, edit and delete) are
  pure and tested; the screen only draws them.
- **A write's path is escaped once.** `appendingPathComponent` escaped the
  `%` of an already-encoded emoji a second time, so every write's URL is
  now built from the path as encoded text (`PatchworkAPI.requestURL`): an
  escaped heart stays `%E2%9D%A4%EF%B8%8F`, and anything unescaped is
  escaped.
- **The bar at the foot** stands in for the vote card's buttons once they
  have scrolled away. `onScrollVisibilityChange` was tried first and does
  not work inside a `List`: it reports a row arriving but never its cell
  being recycled, so the bar never came back. The row reports its frame
  (`onGeometryChange`, back-deployed to iOS 16, so iOS 17 gets the same bar)
  and its disappearance instead.
- **Web bugs deliberately not copied.** `CommentThread` gates Edit and
  Delete on an `is_mine` field the server never sends, so on the web an
  author cannot edit or delete their own comment; here it is `author_id`
  against the signed-in user, and a patch admin (or a quilt admin) may also
  delete. The web's Discussion badge reads a `comment_count` the server
  never sends; here the count is the items plus their replies, worked out
  on the device. The web's nominee picker pages with `cursor=`, which the
  server ignores, so past a hundred members it re-reads page one forever;
  here it pages with `after=`. The web does not pre-check a follower's
  `follower_permissions.proposals` and answers a composer with a 403; here
  a follower's composer and reaction chips wait for the switch and are
  absent where it is off.
- **Decisions on the contract's open questions.** Edit and delete your own:
  yes (a web bug, not a product decision). No "edited" marker, as on the
  web. Deleting a comment with replies says "Its n replies go with it." in
  the confirmation, because the server cascades and keeps no tombstone.
  A reader who can see an open vote but not cast it is told: signed out,
  one quiet "Sign in to vote" door under the terms; a follower, "Become a
  member to vote." with no door; a member inside the tenure bar, the terms
  line's own date and nothing more; a refused vote, the server's sentence
  where the buttons were. The ballot closes on the device once
  `voting_ends_at` has passed, whatever the sweep has not got to. The home
  trusts `needs_vote` as the server counts it (it still counts an
  election the reader abstained in; that is the server's to fix, and the
  number is the server's). No "you changed your vote" message: the filled
  button moving is the answer. Reactions are drawn in the fixed web order,
  zero-count chips only to somebody who may react. The heart is always
  sent as U+2764 U+FE0F, and a bare heart from anywhere is read as it.
- **Who is in the room.** A patch that keeps its record to the room
  (`public_governance_record: nobody`, the default) still shows its members
  their proposals: the governance home now trusts the overview's
  `proposals_withheld`, which the server answers for the reader, once it
  has arrived, and the profile's glimpse treats rows it was sent as not
  withheld. Before, a member of a closed-record patch was told their own
  proposals were not public.
- **Out of scope, still the website's:** proposing, withdrawing, an admin's
  approve / decline / apply / ask the members, revisions and History, and
  the amendment's Changes. The room's note now reads "Proposing a change
  happens on this quilt's website."; the proposal screen's note is gone.

**Offline.** `PreviewData` holds proposals, elections and threads as
values the writes mutate, and works every viewer field out for whoever is
reading, the way `GetProposal` does. Common Thread has the open vote
(`demo-proposal`: majority, 20% quorum, twelve eligible, six ballots, one of
them no longer counted and one a hidden member), a lapsed one, one carried
by a vote, a direct change, an election in its voting phase with three
candidates and the reader's ballot already in, and one still taking names.
The Listening Room now publishes its record, keeps followers out of its
proposals (`follower_permissions.proposals: false`) and has one open vote
with a comment; the Bike Kitchen (`extra-1`) keeps its record to the room
and is the "not public" case. The writes refuse in the server's words
(`demo-proposal-2` is "proposal is not open for voting"). A launch with
`--preview-member` signs the fixture reader in as a member of Common
Thread too; without it, the follow, join and My Quilt tests find the
studio as they always did.

**Verification.** 264 unit tests and 25 UI tests pass on the iPhone 17
Pro simulator. The 31 new unit tests (`GovernanceTests`): the whole
detail payload decoding with a null clock and a null turnout, an
election's slate and turnout, and the comments payload with replies and
reactions; time left at its boundaries and in its three spellings; the
banner for every state, "Cast your vote below." only with a vote below,
and an election still taking names; the quorum sentences and
`ceil(eligible × q ÷ 100)`; the amendment threshold only on an
amendment; the terms line with the eligible day (a calendar day, not the
day before) and the tenure in force; where the tally and the buttons
appear; the sole voter; the bar's fills and compact tally; who owes a
ballot, ordinary and election; direct-change detection with and without
voters; the ballot's gate, the election's words and the seated fallback;
a statement counted in runes; who can be put forward; the ballot,
candidacy and comment bodies; the heart surviving the reaction path,
escaped once; the picker paging by `after`; a `text/plain` refusal read
as the server's sentence; the reactions' fixed order; who may discuss,
edit and delete; and the home's and the rows' words. The five new UI
tests (`GovernanceFlowTests`): a member told a vote is owed, voting,
changing the vote with the counts moving, the voters with one not
counted, and the bar taking over below; an election ballot updated as a
whole set, then standing with a statement and withdrawing; a reaction
counted and a comment posted into the thread; signed out, no buttons and
one door to the sign-in sheet; and a follower of a patch that keeps
followers out, reading without a composer or a reaction to press.

**Live, against a local server.** The v0.31.0 server (built from the
`patchwork-native-auth` worktree, whose tree is the tag's; run from a
copy of its data under the scratchpad), behind a TLS proxy on
`localhost:8443` with its certificate trusted on the iPhone 17 Pro
simulator, signed in as a member by the emailed code read from the
server log. On Code & Coffee (majority, a 20% quorum, its record kept to
the room): the room said "2 proposals need your vote"; a vote was cast,
changed, and read back from `GET proposals/{id}` as `reject` with the
tally 1 · 2 · 0; the voters and the bar at the foot were seen; a
comment was posted, a reply posted and then deleted through the
confirmation, the comment edited, a heart added and taken off again
(`DELETE comments/{id}/reactions/%E2%9D%A4%EF%B8%8F`, answered and read
back) and a thumbs-up left on; an election ballot was saved, replaced by
"take part without approving anyone" and then updated to two names, and
the server's `approved_by_me`, `i_abstained` and turnout agreed; the
reader stood in a contest still taking names, withdrew, and put another
member forward. On First Friday (a 30-day bar in force, the reader
joined yesterday) the terms said "You can vote here from October 28" and
no buttons were drawn, and `curl` got the server's own 403 ("must be a
member for at least 30 days to vote"). On Tellus360 (followed, followers
kept out of proposals) the screen said "Become a member to vote." and
drew no composer, and the server refused a follower's vote and comment
in the words the contract gives. The contract held: refusals arrive as
`text/plain` JSON, a bare U+2764 is "invalid emoji", `voting_ends_at` is
`null` while nominations are open, and `needs_vote` counted the voting
election as well as the ordinary vote. No governance act was made
against lancasterpatchwork.org. Not verified: VoiceOver, Dynamic Type at
the accessibility sizes on these screens, an advisory vote and a sole
voter against a live server, `sole_admin`-style refusals on comments, a
nominee picker past a hundred members, and a physical device. Twice
while the live probe was being written the app stopped answering the
test runner for 30 seconds (main thread busy) on the way into the
followed patch; it did not recur in six further runs through the same patches,
and the spindump taken was unsymbolicated, so it is reported here
rather than fixed.
