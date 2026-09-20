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

**Verification.** 101 unit tests (11 new, covering the card's counts wording,
the head's differing one, and the three orders including the unplaced tail and
the A→Z collation) and 5 UI tests pass on an iPhone 17 Pro simulator. Launched
against Lancaster's live 59 patches in light and dark: cards read as one
surface on the textile ground in both, the miniatures match the tiles behind
them, and the profile's head now shares the card's clothes. Not verified: a
physical device, VoiceOver, iPad, and Increase Contrast beyond the declared
values.
