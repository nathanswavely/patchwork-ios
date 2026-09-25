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
- Search never narrows by typing (ADR 033). The field activates in place and lists patches and upcoming events under it; one row sets the search chip. The tab bar's Search button focuses the same field.
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
  `node_id` (falling back to `node_slug`) against `session.patches`. The two
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

**What it looks like.** The bell sits in `DiscoveryToolbar` before the account
menu, drawn only where `session.me != nil` — `bell.fill` with a count in the
one tint while there is one, `bell` while there is not, and "Notifications, N
unread" to VoiceOver. The sheet is a `NavigationStack` titled Notifications on
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
