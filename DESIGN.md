---
name: Patchwork for iOS
description: Clean native browsing for independently operated community quilts.
colors:
  accent-light: "#0272B5"
  accent-dark: "#39B4F6"
typography:
  display:
    fontFamily: "SF Pro Display, SF Pro, -apple-system, sans-serif"
  headline:
    fontFamily: "SF Pro Display, SF Pro, -apple-system, sans-serif"
  body:
    fontFamily: "SF Pro Text, SF Pro, -apple-system, sans-serif"
  label:
    fontFamily: "SF Pro Text, SF Pro, -apple-system, sans-serif"
rounded:
  tile: "8pt"
spacing:
  sm: "8pt"
components:
  primary-action:
    backgroundColor: "{colors.accent-light}"
    textColor: "#FFFFFF"
  filter-control:
    backgroundColor: "UIColor.secondarySystemGroupedBackground"
    textColor: "Color.primary"
  patch-tile:
    backgroundColor: "UIColor.secondarySystemGroupedBackground"
    textColor: "Color.primary"
    rounded: "{rounded.tile}"
    padding: "{spacing.sm}"
---

# Design System: Patchwork for iOS

## Overview

**Creative North Star: "The Quiet Public Map"**

Patchwork is a direct, native iOS reader for independently operated communities. It keeps the web quilt's spatial behavior and vocabulary while using system typography, semantic surfaces, SF Symbols, and familiar navigation. The quilt itself is the patches' own: each tile is drawn from the palette, block, rotation and motif its admins chose (or the hash assigned), with seam ink between tiles and corner marks on them, exactly as the web draws it. The chrome around the quilt stays system; the app adds no hand lettering or generated raster decoration of its own, and it does not yet draw the web's cloth (the wandering lattice, batting, weave and folds).

The quilt, map, and list are one discovery instrument. Filtering repacks the matching patches, the list follows quilt placement by default, and a selected patch opens its profile without losing the active filter or viewport. The AccentColor asset supplies the light and dark tint for actions and selection.

**Key Characteristics:**

- Native `TabView`, `NavigationStack`, sheets, lists, and SF Symbols.
- SF Pro and Dynamic Type for all reading content and controls.
- Semantic system colors and materials in light and dark appearances.
- UIKit-backed quilt canvas with direct pinch and pan gestures.
- Vector tiles from the shared palette and block registries; seam ink, corner marks and name badges that hold their size on screen at any zoom.

## Colors

Use semantic system roles in SwiftUI/UIKit: `Color.accentColor`, `Color.primary`, `Color.secondary`, `Color(.systemGroupedBackground)`, `Color(.secondarySystemGroupedBackground)`, and `Color(.separator)`. The AccentColor asset has separate light and dark values.

### Primary

- **AccentColor light** (`{colors.accent-light}`) and **AccentColor dark** (`{colors.accent-dark}`): links, prominent actions, selected controls, and map/list selection through the asset-backed `Color.accentColor`.

### Neutral

- **Grouped surfaces:** use `systemGroupedBackground` and `secondarySystemGroupedBackground`.
- **Labels:** use `label` and `secondaryLabel`.
- **Separators:** use the system separator color only where grouped lists provide one.

**The One Tint Rule.** One tint communicates interaction. Meaning must remain available through text, shape, position, and VoiceOver state.

### Display settings

Two standing choices belong to the reader, not to the quilt, and neither needs an account (docs/adr/112). They live in a **Display** sheet on the account menu and are held in `UserDefaults` on the device: nothing about them is sent anywhere, so the preference never becomes user data.

- **Theme** — System, Light, or Dark, applied as `preferredColorScheme` at the app's root. System is the default and follows the device.
- **Colors** — Default or Muted. Default is the default on every quilt and no quilt setting moves it: loud is the intent and muted is the accommodation.

**Muted.** Muted never adds a colour a patch didn't choose; it takes away what it has to and keeps the rest. A tile's identity colour carries its hue through untouched, its lightness is *set* to a step on a ramp every tile in the quilt shares (`0.64, 0.86, 0.28, 0.50, 0.75, 0.38` in OKLCH L, indexed by bundle slot), and its chroma is only ever capped at `0.09`, never raised. Capping rather than setting is what keeps that sentence true, and it dissolves the achromatic case instead of answering it: Stage Black has no chroma to cap, so a patch that chose to be achromatic stays a grey ramp. Normalising lightness is the part that does the work — the quilt shouts in chroma and in value contrast, and value contrast is the one that carries across a room. The slot *count* is preserved rather than filled out to six, because muted may take colour away and may not add structure. Out-of-gamut results lose chroma by binary search, never hue. Muted reaches every colour that stands for something — tiles, ghost fills, motif discs, and any identity colour a surface reads — and the quilt recuts in place when it changes.

### Fabric

The quilt's colours are the patches', never the app's. A tile draws from its **bundle** (up to six fabrics off the curated fabric wall), else its pinned **palette** (eight album palettes and eighteen wall cuts, in the web's registry order), else the palette the web's `hashStr` assigns from the patch id — bit for bit the same hash, so a patch wears the same tile here as on the site. Slot one is the **identity colour**, the one colour that stands for the patch anywhere it is not a full tile (its motif disc). Ink on a fabric is `#151820` or white by WCAG luminance, threshold 0.18, as the web decides it.

Ink around the fabric follows the web's textile tokens and flips with the theme: seam ink `rgba(28,24,18,0.55)` light / `rgba(0,0,0,0.72)` dark; thread `#c8c0b0` / `#2e3240` (badge border); heavy thread `#7a746a` / `#4a5060` (mark rings); badge fill `rgba(250,246,238,0.45)` / `rgba(0,0,0,0.5)` with text `#2a2520` / `#e8e6e3`. Status discs are `rgba(0,0,0,0.55)` in both themes, so a tile's own colour never means "unclaimed". The canvas ground stays `systemGroupedBackground`.

## Typography

**Display Font:** SF Pro Display through system text styles
**Body Font:** SF Pro Text through system text styles
**Label/Mono Font:** SF Pro Text; use a monospaced system variant only for technical origins.

Use `largeTitle`, `title2`, `headline`, `body`, `subheadline`, and `caption`; Dynamic Type and the operating system control their metrics.

### Hierarchy

- **Display** (bold, Large Title system style): patch and event detail titles.
- **Headline** (semibold, Headline system style): patch and event names.
- **Title** (bold, Title 2 system style): quilt identity and sheet introductions.
- **Body** (regular, Body system style): descriptions and explanatory copy.
- **Label** (medium, Caption or Footnote system style): dates, hosts, filters, and metadata.

**The Scaling Rule.** Reading views grow with Dynamic Type. Spatial tile labels use intentional tail truncation; the full name remains available to VoiceOver, in List, and in the profile.

## Layout

Controls stay inside safe areas; the canvas itself runs under the status bar, the top bar and the tab bar, the way Apple Maps does, and the top bar paints nothing over it — each control carries its own glass. Top-level browsing is a three-item `TabView` — Quilt, Events, Discover — with a `NavigationStack` in each tab. The Quilt tab's item wears the quilt's own icon (read from `instance/icon` and rasterised when it is SVG), and holding it opens the quilt switcher, the way a profile tab switches accounts; the account menu offers the same switch for anyone who cannot hold. Dashboard and notifications join the shell when sign-in does; nothing stands in for them.

One top bar sits on every discovery surface: **Filter** leading (badged with the active count; present only where the surface narrows), the **search field** in the centre — a glass capsule that is the field itself, not a door to one — and the **account** menu trailing (join or sign in on the web, About this quilt, Switch quilt), which gives way to Cancel while the field is live. The tab bar's Search button focuses that field. Detail screens use inline navigation titles and preserve the edge-swipe back gesture.

The Quilt/Map/List switch is a native segmented control floating over the foot of the canvas above the tab bar, in thumb reach. There is no fit or recentre control; the initial fit and pinch are enough. Quilt uses `QuiltCanvas`, a UIKit `UIScrollView` with zoom and pan; its gesture zoom runs 0.3–6, and on a viewport 700pt wide or narrower the initial fit is floored so a 1×1 tile is at least 60pt (the badge threshold plus 8) and capped at 2.4 — a quilt fitted whole into a phone is anonymous confetti, so it starts legible and lets the person pan. Filtering matches selected interests with OR semantics and intersects them with the search chip, case and diacritic insensitively over name and description. Matching patches repack from their original sizes, while clearing filters restores the baseline arrangement. Map uses actual coordinates and the same narrowed collection; List uses quilt placement order, Name, or Newest, and states the count in its header.

At initial fit on a phone, the smallest tile is at least 60pt wide. Manual zooming out can make tiles smaller; List provides conventional full-size targets. Names are not painted on tiles: they float as name badges that appear as tiles earn room (see Quilt Tiles). The full patch name is the tile's accessibility label and the tap opens its profile.

The canvas fills the available iPhone or iPad viewport. Profiles dock as native sheets on both device classes; a persistent side-by-side profile is not implemented.

## Elevation & Depth

Use grouped system backgrounds, separators, and native sheet/material presentation. Rows stay quiet; there is no custom shadow or glass system beyond the quilt's own ink — a corner mark's one-point drop shadow and the seam stroke between tiles are the quilt's, not the app's. Reduce Motion disables animated repacking and uses the platform's reduced transition behavior.

**The Live Surface Rule.** Opening a profile keeps the quilt's filter and viewport alive behind it. Filtering never dismisses the profile; changing quilts does. One temporary overlay at a time: a tap on the canvas behind the filter sheet closes the sheet first, then docks the patch.

## Shapes

Use system-rounded controls and native sheet corners. Tiles are square and meet edge to edge; the only line between them is the seam ink drawn on top, never a gap or a per-tile outline. Corner marks are discs of 22pt; badges are pills with a half-em radius. Prefer grouped lists and system separators over bespoke card stacks. The web's wandering lattice and raw-edge wobble are not drawn yet — when they are, the seam still belongs to the boundary, not to either tile.

## Components

### Buttons

- **Shape:** native button styles with a 44pt minimum hit area.
- **Primary:** `.borderedProminent` for Find quilt and Explore quilt using `Color.accentColor`.
- **Secondary:** `.bordered`, `.plain`, or `Link` for Cancel, Done, website, directions, and sharing.
- **State:** use system pressed, focus, disabled, and VoiceOver states; never rely on hover.

### Filters

- **Style:** the Filter button opens a sheet of chips — every tag the quilt wears, most-worn first, with the search chip among them — over the canvas, which repacks live behind it. Chips are plain: only Discover says how many patches wear a tag, and the number it says is the quilt's own (`tags` → `node_count`), so both surfaces rank by one thing. Inactive chips are grey; the one tint marks the active ones.
- **State:** the active count badges the Filter button; Clear removes search and interests together. Map, Quilt, and List read the same state.

### Search

- **Style:** the centre field activates in place; results list under it, over the surface, as patches (by name or description) and upcoming events (by title), each a way through to the thing itself. Cancel leaves the surface as it was.
- **Nothing found:** where the quilt says it takes suggestions (`submissions_enabled`), the empty result offers one link to the website's submission form — "Suggest “X” as a patch", carrying the typed name as `?name=X` so the form arrives already about the thing that was looked for. There is no native form; suggesting needs an account.
- **Rule:** typing never narrows the quilt. The last row — "Show matches on the quilt for …" — is the one act that sets the search chip.

### Quilt Tiles

- **Block:** one of the twelve curated blocks (Pinwheel, Ohio Star, Broken Dishes, Flying Geese, Four Patch, Nine Patch, Hourglass, Sawtooth Star, Rail Fence, Log Cabin, Bear's Paw, Windmill) or the patch's drafted block (a grid, seams between wall anchors, pieces coloured by bundle slot), rotated 0/90/180/270 about the tile centre. Every piece cut from one fabric is one shape layer, sealed with a hairline stroke of its own colour so no ground shows between two fabrics. A filler cell is a ghost block at 15% opacity, never named, never tappable. Unknown palette, block or motif keys degrade to the hash-assigned tile rather than erroring.
- **Seams:** 0.6pt of seam ink along every unique boundary segment, stroked once however many tiles share it; the quilt's outer edge wears a 2.4pt binding. Both are screen pixels — they read the same at 0.3× and 6×. While a repack animates, the ink waits for the tiles to land rather than morphing.
- **Corner marks:** the **motif** (top-left, on the patch's identity colour) on every tile, and the **unclaimed mark** (top-right, a broken chain link on a neutral disc) on community listings. A disc is 22pt, inset 6pt, with a 1.5pt heavy-thread ring and a 1pt shadow; the glyph is 14pt Phosphor fill. One size per tile — `min(22, tile × zoom × 0.3)` — so a tile's marks appear and vanish together, and below 9pt they go. The motif resolves chosen → first motif-bearing tag (from the quilt's `tags` vocabulary) → quilt mark.
- **Name badge:** the name, centred, and nothing else, in a frosted pill (caption size semibold, bounded at 17pt, 1.3 line height, 0.2em/0.4em padding, half-em radius, thread border) floating in screen space. A tile earns a badge at 52pt on screen and an incumbent holds its badge down to 44pt; a new badge owes its neighbours 32pt of visible quilt and an incumbent 26pt on an 80pt tile, sliding toward the full gap near the floor. Incumbents are placed first, then larger tiles. A name sits flat until its neighbours leave no room, then stacks to two or three balanced lines (width cap 8.5em); only a name that fits at no depth gives up its badge. Badges clip at the safe area rather than reshaping, and are never drawn under the status bar or the tab bar.
- **Interaction:** UIKit pinch/pan belongs to the canvas; tiles are native controls with full accessibility names and the hint “Opens patch details.” A tap on a badge opens that badge's patch, even where the pill overhangs a neighbour; the quilt still pans under it. Badges are not accessibility elements — the tile is.

### Quilt Info

The quilt's public account of itself, which the web spreads over /about, /label, /lining, /governance, /privacy and /terms and links from a footer strip on every page. Here it is one grouped list on the account menu's **About this quilt**, headed by the quilt's icon, name, host and its own description, then pushing to:

- **About** — the project's own orientation prose (What is this? / How does it work? / Where do patches come from? / What makes Patchwork different), the same on every quilt, with the quilt's description quoted as the quilt's own words rather than blended into it, and the Label's gist — who stewards this and roughly what it costs — as the handoff.
- **The Label** (`label`) — solo-first: one steward leads with the person, more lead with the roster. The stewards' prose, what this runs on with each service's purpose and why, the monthly total with the note that nobody audits it, a stale banner when the figures have not been reviewed since the date they were stated, the version and the two cross-quilt capabilities stated in both directions, support and feedback links, where it was seamripped from, and the door: where the exit is.
- **The Lining** (`instance/lining`) and the shipped **Governance** prose — the baseline every patch adopts, and how patches decide, in the project's own fixed words.
- **Privacy Policy** and **User Agreement** (`legal/{doc}`), dated only where the stewards replaced the shipped default.

Fetched documents are markdown, read as native blocks — headings, paragraphs, lists, quotes, rules — with each block's inline run parsed by `AttributedString(markdown:)` so links and emphasis work and everything grows with Dynamic Type. A relative link resolves against the quilt it came from. List mode and Discover end in one quiet centred row — The Label · About · Privacy · Terms — in the last section's footer, opening its page as a sheet. That is the footer strip's whole job here; it is not a web footer, and it is not a menu, so it wears no list-row chrome.

### Docked Profile

The patch's own profile opens in a native sheet over the surface that opened it — quilt, map, list, search, or Discover. At rest the sheet is the profile's head — cover, name, counts worded as the web words them ("3 Following · 32 Upcoming Events"), tags, the state the patch wears, description — plus a 96pt cut of the first glimpse, which is the invitation to pull. Pulled up it is full screen, and the pull is what fetches the rooms. Tapping behind dismisses at rest; Done and the handle work at any height. The underlying discovery state remains intact.

The head wears state, never a button standing in for it: a moved patch's forwarding address (which opens the read-only remote view when it names a patch on another quilt), "No one runs this patch yet" on a community listing, and an "Amended lining" badge on a patch whose lining is its own writing. Claiming, joining, following and voting stay on the website — there are no disabled pretend controls for them.

Below the head are four glimpses in the web's order — About, Events, Members, Governance (ADR 042) — and each heading is itself the door into that room. There is no door named for a container. About is the one heading that names identity rather than a room, so it stays inert: website, the patch's own links, its address with Apple Maps directions, and the atproto handle its claim proved, written past tense. Events shows three, bounded by `from=now` so a section headed Upcoming can only hold what is, and admits the rest as "N more upcoming"; its screen opens on Upcoming and offers what already happened as a second, explicit request, with a Subscribe sheet offering the ICS (`webcal:`) and RSS addresses on a public patch. Members shows a few people and their roles; a withheld roster collapses the glimpse and its screen says the patch doesn't publish its list — never that it has no members — while the counts stay public. Governance shows published documents and recent proposals over an overview of how the patch decides, who leads, and its council's chairs; proposals and the record are absent, not empty, where the patch publishes neither. Every empty state distinguishes "nothing yet" from "not published".

### Discover

Asks one question — "What are you drawn to?" — with the eight most-worn tags on this quilt (counts shown here and nowhere else) and "Show all tags (N more)". The counts are the quilt's own `node_count` from the `tags` vocabulary, which is whole-quilt and public; where that endpoint does not answer they are derived from the patches in hand, so a shortlist is never blank. Ranking is count descending, ties A to Z. A curated term no patch wears is dropped rather than printed as a zero — the same array is the filter sheet's vocabulary, and a chip that can only empty the quilt is worse than an absent one.

The answer has two halves, as the web's does. **Patches you might like** lists what wears the picked tags, the ones with something coming up first — read from the upcoming-events feed rather than claimed — then in quilt order. Under it, **Show the rest of the quilt (N)** folds everything else away behind one disclosure, counted and ordered the same way: the answer is a shortlist, not a verdict on the rest. "Show me everything instead" is one list with no remainder. A row states its patch's name, its tags, its next event, and a **Moved** chip where the patch has a `moved_to` — the fact is visible before anyone walks into an address that has moved. Each row opens the docked profile.

Following stays on the website, and the sentence that says so is the door: "Following needs an account — reading never does." links to the quilt's `/login`, and the docked profile's equivalent line carries `?redirect=/patches/{slug}` so a reader lands back on the patch they were reading. No Follow button, enabled or disabled, appears anywhere.

### Orientation

One card, over the foot of the quilt, the first time a quilt is opened: what a quilt is, what this one promises, **What is Patchwork?** into the About page, and "I'll lurk for now" as a worded decline. It is an overlay, never a sheet — a modal would have to be dismissed before the quilt could be looked at, which is backwards for a card whose content is that reading costs nothing. It may sit over the canvas, never over a control, and the quilt pans and opens underneath it. Either answer is an answer: the card is offered once per quilt, remembered in `UserDefaults`, and never shown again.

### Events

- **The list:** one flat, grouped `List`, soonest first — no day headers, which made a quiet week read as a wall of empty headings. Each row is when (the event's own zone, accent-tinted), what, where, and whose, with "Community-submitted" beside the patch name where the patch is unclaimed. A cursor "Load more events" sits at the foot; pull to refresh.
- **The date filter:** one row at the head of the list opens a `Menu` holding a `Picker` of the web's presets — Any date, Today, Tomorrow, This weekend, This week, Next week, This month — with the live one checked, and a Custom range… that opens a sheet of two system `DatePicker`s. The presets resolve in the quilt's own time zone, not the reader's. The quilt's tag chips and search chip narrow the calendar too, through the event's host patch.
- **Empty states:** two, and they say different things. A filter that empties the list is standing state — "No events match your filter" with a **Clear filter** button beside it. An empty calendar is not a mistake and gets "No upcoming events" with no action.
- **Badges:** a tier chip (`Followers`, `Members only`) and `Community-submitted` are quiet outlined capsules in caption-2 semibold, secondary foreground, `Color(.separator)` border. A public event wears nothing — a chip on every row says nothing at all. Status wears words, never a colour.
- **The detail:** title, "Hosted by {patch}" as a door into the docked profile, badges, then "with X" capsules for confirmed links and cross-quilt mentions as external doorways. When and where carry the `ends_at` range (same-day reads as one date), the event's zone, the recurrence caveat, and the location. A flyer is a full-bleed `AsyncImage` row; coordinates earn a still, non-interactive `Map` with a marker plus **Open in Maps** and **Directions**. Actions close the page: Add to calendar, "Tickets & details on {host}" where the source says so, and the quilt's own web page. Nothing authenticated appears — no submit, edit, or RSVP.
- **Add to calendar:** a `Menu`, so opening it commits to nothing; the calendar is only asked for once **Add to Calendar** is chosen, which presents the system `EKEventEditViewController`. **Share calendar file** hands the quilt's `.ics` to a share sheet for a reader who keeps their calendar elsewhere. Hidden while a submission is awaiting review.
- **Subscribe:** a patch's own events screen carries a Subscribe menu in the bar — the `webcal:` calendar subscription and the RSS feed.

### Navigation

Use SF Symbols, `TabView`, `NavigationStack`, grouped `List`, `Map`, native sheets, and system materials. Quilt choice is always explicit; Lancaster is a directory entry, never an implicit launch selection. Quilts the instance names as neighbours appear in the switcher under Connected quilts as doorways to their own inspect-and-confirm.

## Do's and Don'ts

- **Do** use semantic colors, Dynamic Type, SF Symbols, VoiceOver labels, safe areas, and 44pt targets.
- **Do** preserve placement order, repack filtered subsets, and share one filter state across Quilt, Map, and List.
- **Do** honor Reduce Motion for repacking and native transitions.
- **Do** preserve the active viewport and filters while a profile is open.
- **Don't** invent appearance: a tile is what the patch chose or what the hash assigned, and an unknown key falls back rather than being guessed at. Don't paint names onto fabric, scale marks or seam ink with the quilt, or add hand lettering or generated raster assets.
- **Don't** mean status with colour: identity wears the patch's own colour, status wears a neutral disc.
- **Don't** replace native controls with web-shaped buttons, custom global navigation, or hover-only affordances.
- **Don't** silently select a quilt or invent authenticated actions; joining, following, suggesting a patch, governance, and submitting or editing an event remain website links in this browsing pass, and Dashboard and notifications wait for sign-in rather than standing in the shell as stubs.
