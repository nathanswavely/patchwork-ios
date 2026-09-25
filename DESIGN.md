---
name: Patchwork for iOS
description: Clean native browsing for independently operated community quilts.
colors:
  accent-light: "#C43D07"
  accent-dark: "#E8734A"
  ground-light: "#F4F0E8"
  ground-dark: "#151820"
  surface-light: "#FAF6EE"
  surface-dark: "#1C2028"
  border-light: "#DDD8CC"
  border-dark: "#2A2E38"
  text-light: "#2A2520"
  text-dark: "#E0DBD4"
  text-muted-light: "#6B655C"
  text-muted-dark: "#9B958C"
typography:
  display:
    fontFamily: "Shantell Sans, SF Pro Display, -apple-system, sans-serif"
  headline:
    fontFamily: "Space Grotesk, SF Pro Text, -apple-system, sans-serif"
  body:
    fontFamily: "Space Grotesk, SF Pro Text, -apple-system, sans-serif"
  label:
    fontFamily: "Space Grotesk, SF Pro Text, -apple-system, sans-serif"
rounded:
  tile: "8pt"
  card: "6pt"
spacing:
  sm: "8pt"
  card: "14pt"
components:
  primary-action:
    backgroundColor: "{colors.accent-light}"
    textColor: "#FFFFFF"
  filter-control:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.text-light}"
  patch-card:
    backgroundColor: "{colors.surface-light}"
    borderColor: "{colors.border-light}"
    textColor: "{colors.text-light}"
    rounded: "{rounded.card}"
    padding: "10pt 12pt"
    coverHeight: "100pt"
  patch-tile:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.text-light}"
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

The app is native but not anonymous. Its six colours are the site's, not iOS's defaults: the quilt is the patches' own (see Fabric), and this is the room it hangs in. Five neutrals plus one tint, all asset-backed in `Assets.xcassets/Palette` with light, dark and Increase Contrast variants, and reached only through the `Color` extension in `Palette.swift` — never as a literal at a call site.

### Primary

- **AccentColor light** (`{colors.accent-light}`) and **AccentColor dark** (`{colors.accent-dark}`): the web's `--color-accent`, a rust that belongs to the same fabric wall as the tiles (Rust `#A0430A`, Safety Orange `#E3480B`). It replaced the site's primary blue, because a blue tint on a white-ish list is indistinguishable from stock iOS however carefully it is chosen. Read it as `Color.pwAccent`, which names the asset: `Color.accentColor` answers with whatever tint the environment is carrying, and until something sets it that is the system's own blue — the app was drawing iOS blue for exactly that reason.

**The tint is for controls, not for words.** It marks a selected segment, a toggle, a prominent button, the follow heart, a chip standing for a live state. Interactive *text* is ink in all three of its forms: a link reads as `pwText` with a small exit arrow (`View.exitLink()`), a text door within the app reads as ink with the platform's chevron (`View.inkRow()`), an act that is neither — "Try again", "Load more", "Show all tags", "Show the rest of the quilt" — reads as ink with its own leading glyph (`View.inkAction(_:)`), and a link inside prose is underlined rather than coloured. `exitLink` and `inkRow` take `fills: false` where the word shares its line with something else. Colouring every tappable phrase is what made the app read as a web page in iOS clothing, and a page full of coloured phrases stops saying anything at all.

### Neutral

Each is lifted from a web token, so a reader who knows the site recognises the app.

| token | light | dark | from |
| --- | --- | --- | --- |
| `Color.pwGround` | `{colors.ground-light}` | `{colors.ground-dark}` | `--lt-canvas` raw cotton / raw denim, which is also `--color-bg` |
| `Color.pwSurface` | `{colors.surface-light}` | `{colors.surface-dark}` | `--color-surface`, one step off the ground |
| `Color.pwBorder` | `{colors.border-light}` | `{colors.border-dark}` | `--color-border`, the unbleached-thread family `QuiltInk.thread` draws from |
| `Color.pwText` | `{colors.text-light}` | `{colors.text-dark}` | `--color-text` |
| `Color.pwTextMuted` | `{colors.text-muted-light}` | `{colors.text-muted-dark}` | `--color-text-muted` |

The ground reaches the quilt canvas, List, Events, Discover, the quilt picker, the info stack and the docked profile; the surface is what a card, a row and the profile's head are made of. Increase Contrast moves each further from the ground (light `#F7F4ED` / `#FFFFFF` / `#A9A294` / `#1A1510` / `#4E483F`; dark `#0E1016` / `#242A33` / `#4A5060` / `#F5F2EC` / `#BAB4AA`), which is the asset catalog's job rather than a branch in code.

Contrast (WCAG, against the ground): text 13.4:1 light and 12.9:1 dark; muted 5.1:1 light and 6.0:1 dark; accent as text on the surface 4.8:1 light and 7.0:1 dark — AA for body text at both ends. The hairline is decorative and is not asked to carry meaning.

System materials stay system: the top bar's glass controls, the view-switcher pill, sheets and the tab bar are the platform's, and semantic colours stay wherever a system component owns them (`.separator` on a system list's own rules, `.red` on an error, the system's own selection).

**The One Tint Rule.** One tint communicates interaction. Meaning must remain available through text, shape, position, and VoiceOver state. The five neutrals are not tints: none of them may stand for a state.

### Display settings

Two standing choices belong to the reader, not to the quilt, and neither needs an account (docs/adr/112). They live in a **Display** sheet on the account menu and are held in `UserDefaults` on the device: nothing about them is sent anywhere, so the preference never becomes user data.

- **Theme** — System, Light, or Dark, applied as `preferredColorScheme` at the app's root. System is the default and follows the device.
- **Colors** — Default or Muted. Default is the default on every quilt and no quilt setting moves it: loud is the intent and muted is the accommodation.

**Muted.** Muted never adds a colour a patch didn't choose; it takes away what it has to and keeps the rest. A tile's identity colour carries its hue through untouched, its lightness is *set* to a step on a ramp every tile in the quilt shares (`0.64, 0.86, 0.28, 0.50, 0.75, 0.38` in OKLCH L, indexed by bundle slot), and its chroma is only ever capped at `0.09`, never raised. Capping rather than setting is what keeps that sentence true, and it dissolves the achromatic case instead of answering it: Stage Black has no chroma to cap, so a patch that chose to be achromatic stays a grey ramp. Normalising lightness is the part that does the work — the quilt shouts in chroma and in value contrast, and value contrast is the one that carries across a room. The slot *count* is preserved rather than filled out to six, because muted may take colour away and may not add structure. Out-of-gamut results lose chroma by binary search, never hue. Muted reaches every colour that stands for something — tiles, ghost fills, motif discs, and any identity colour a surface reads — and the quilt recuts in place when it changes.

### Fabric

The quilt's colours are the patches', never the app's. A tile draws from its **bundle** (up to six fabrics off the curated fabric wall), else its pinned **palette** (eight album palettes and eighteen wall cuts, in the web's registry order), else the palette the web's `hashStr` assigns from the patch id — bit for bit the same hash, so a patch wears the same tile here as on the site. Slot one is the **identity colour**, the one colour that stands for the patch anywhere it is not a full tile (its motif disc). Ink on a fabric is `#151820` or white by WCAG luminance, threshold 0.18, as the web decides it.

Ink around the fabric follows the web's textile tokens and flips with the theme: seam ink `rgba(28,24,18,0.55)` light / `rgba(0,0,0,0.72)` dark; thread `#c8c0b0` / `#2e3240` (badge border); heavy thread `#7a746a` / `#4a5060` (mark rings); badge fill `rgba(250,246,238,0.45)` / `rgba(0,0,0,0.5)` with text `#2a2520` / `#e8e6e3`. Status discs are `rgba(0,0,0,0.55)` in both themes, so a tile's own colour never means "unclaimed". The canvas ground is `pwGround` — the textile canvas the ink was taken from, not iOS grouped grey.

## Typography

The site's two typefaces, bundled and registered (`Patchwork/Fonts`, `UIAppFonts` in `Patchwork/Info.plist`), reached only through `Font.pw.*` / `PWType` (`Typography.swift`).

**Body/UI Font:** **Space Grotesk** (variable, `wght` 300–700; PostScript `SpaceGrotesk-Light`) — everything a person reads or operates.
**Display Font:** **Shantell Sans** (variable, `wght` 300–800; PostScript `ShantellSans-Light`) — the hand-lettered voice, and only where a screen or a patch says its own name: the large navigation titles, "Patches", the quilt's name in the picker and the info stack, the patch name in the profile's head.
**Mono:** a monospaced system variant, only for technical origins (an atproto handle).

Both are SIL Open Font Licence 1.1; the texts are in `docs/third-party/`. Both are shipped as their single variable TTF, so a weight is a coordinate on the `wght` axis rather than another file, applied through `kCTFontVariationAttribute` and clamped to the axis range — an out-of-range coordinate silently returns the font's default instance, which is Light for both. Every size is the system's own for its text style at the Large content size and is then scaled by `UIFontMetrics`, so Dynamic Type reaches the bundled faces exactly as it reaches SF Pro, up to the accessibility sizes. If a face fails to register, every call falls back to SF Pro at the same style and weight: the app is legible with no bundled fonts at all.

The UIKit chrome SwiftUI does not reach — navigation bar titles, tab bar labels, the quilt's name badges — is set once through `PWType.install()` and `PWType.baseFont`.

Use `Font.pw.largeTitle`, `.title2`, `.headline`, `.body`, `.subheadline`, `.caption` and their semibold variants; Dynamic Type and the operating system still control their metrics.

### Hierarchy

- **Display** (Shantell Sans, 700): a screen or a patch naming itself — the large navigation titles, "Patches", the quilt's name, the profile head's patch name.
- **Headline** (Space Grotesk 600): patch and event names in a list.
- **Title** (Space Grotesk 700): sheet introductions and section titles that are not a name.
- **Body** (regular, Body system style): descriptions and explanatory copy.
- **Label** (medium, Caption or Footnote system style): dates, hosts, filters, and metadata.

**The Scaling Rule.** Reading views grow with Dynamic Type. Spatial tile labels use intentional tail truncation; the full name remains available to VoiceOver, in List, and in the profile.

## Layout

Controls stay inside safe areas; the canvas itself runs under the status bar, the top bar and the tab bar, the way Apple Maps does, and the top bar paints nothing over it — each control carries its own glass. Top-level browsing is a three-item `TabView` — Quilt, Events, Discover — with a `NavigationStack` in each tab, plus a fourth, Dashboard, that arrives with an account and leaves with it. The Quilt tab's item wears the quilt's own icon (read from `instance/icon` and rasterised when it is SVG), and holding it opens the quilt switcher, the way a profile tab switches accounts; the account menu offers the same switch for anyone who cannot hold. A badged bell sits beside the account menu wherever there is an account, and opens the notifications sheet.

One top bar sits on every discovery surface: **Filter** leading (badged with the active count; present only where the surface narrows), the **search field** in the centre — a frosted capsule (thick material with a hairline border, not Liquid Glass: the quilt under it is too dense for glass to keep a placeholder legible, and Apple's materials remain the supported answer for a control that must carry text over unpredictable content) that is the field itself, not a door to one — and the **account** menu trailing (Sign in, or the person's name and Sign out; About this quilt; Display; Switch quilt), which gives way to Cancel while the field is live. The tab bar's Search button focuses that field. Detail screens use inline navigation titles and preserve the edge-swipe back gesture.

The Quilt/Map/List switch is a native segmented control floating over the foot of the canvas above the tab bar, in thumb reach. There is no fit or recentre control; the initial fit and pinch are enough. Quilt uses `QuiltCanvas`, a UIKit `UIScrollView` with zoom and pan; its gesture zoom runs 0.3–6, and on a viewport 700pt wide or narrower the initial fit is floored so a 1×1 tile is at least 60pt (the badge threshold plus 8) and capped at 2.4 — a quilt fitted whole into a phone is anonymous confetti, so it starts legible and lets the person pan. Filtering matches selected interests with OR semantics and intersects them with the search chip, case and diacritic insensitively over name and description. Matching patches repack from their original sizes, while clearing filters restores the baseline arrangement. Map uses actual coordinates and the same narrowed collection; List is a stack of patch cards, ordered by Quilt order, Recently added, or A→Z — the web's own three names — and states the count in its header.

At initial fit on a phone, the smallest tile is at least 60pt wide. Manual zooming out can make tiles smaller; List provides conventional full-size targets. Names are not painted on tiles: they float as name badges that appear as tiles earn room (see Quilt Tiles). The full patch name is the tile's accessibility label and the tap opens its profile.

The canvas fills the available iPhone or iPad viewport. Profiles dock as native sheets on both device classes; a persistent side-by-side profile is not implemented.

## Elevation & Depth

Depth is stated by surface and hairline, with the one soft shadow the web itself carries. A card is `pwSurface` on `pwGround`, cut out with a 1pt `pwBorder` stroke at the site's 6pt radius and lifted by its `0 2px 10px var(--color-shadow)` — faint in light, all but absent in dark. That is the whole elevation system. There is no other custom shadow or glass beyond the quilt's own ink — a corner mark's one-point drop shadow and the seam stroke between tiles are the quilt's, not the app's — and the system's materials are used unaltered where the system presents them. Where a grouped `List` remains, it is re-grounded rather than restyled: `scrollContentBackground(.hidden)` over `pwGround` with `pwSurface` rows (`View.groundedList()`). Reduce Motion disables animated repacking and uses the platform's reduced transition behavior.

**The Live Surface Rule.** Opening a profile keeps the quilt's filter and viewport alive behind it. Filtering never dismisses the profile; changing quilts does. One temporary overlay at a time: a tap on the canvas behind the filter sheet closes the sheet first, then docks the patch.

## Shapes

Use system-rounded controls and native sheet corners. Tiles are square and meet edge to edge; the only line between them is the seam ink drawn on top, never a gap or a per-tile outline. Corner marks are discs of 22pt; badges are pills with a half-em radius. Cards are 6pt continuous-radius rectangles — the site's `--radius` — with a 1pt border, a 100pt cover strip and a 10 × 12pt body; a standalone tile miniature is an 8pt-radius square, the same corner the quilt's tiles wear. Prefer a re-grounded system list wherever the content is a setting or a document; a card is for a thing that could move to another surface — a patch, an event, a member. The web's wandering lattice and raw-edge wobble are not drawn yet — when they are, the seam still belongs to the boundary, not to either tile.

## Components

### Buttons

- **Rule:** the tint fills a control; it never colours a word (see Colors).
- **Shape:** native button styles with a 44pt minimum hit area.
- **Primary:** `.borderedProminent` for Find quilt and Explore quilt using `Color.accentColor`.
- **Secondary:** `.bordered`, `.plain`, or `Link` for Cancel, Done, website, directions, and sharing.
- **State:** use system pressed, focus, disabled, and VoiceOver states; never rely on hover.

### Forms

The app asks for almost nothing, and sign-in is the first thing it asks for at all (`SignIn.swift`). A bare `TextField` on the textile ground has no edge, so every field wears one modifier — `View.fieldStyle()` (`FieldStyle`, Palette.swift): `pwSurface`, a 1pt `pwBorder` hairline, a 10pt continuous radius (the card's materials at a smaller corner, because a field is a smaller thing than a card), 12pt padding and a 44pt minimum height. The tint stays out of it; a field is not an act.

- **A step** is a heading in the display face, one sentence in `pwTextMuted`, the field, the refusal, then one `.borderedProminent` button in the accent taking the full width. Anything secondary beside it is an `inkAction`, never a coloured word.
- **A refusal** sits under the field it is about, never at the foot of the step, and it is the server's own sentence wherever the server wrote one.
- **A rule the client can check** (the username) is a muted hint while it is being typed and a correction only once the person has left the field or pressed the button. Editing clears it.
- **Placeholders** are `Text(verbatim:)`. A string literal shaped like an email address is parsed as Markdown and drawn as a blue link — in the field whose whole job is to hold one.

### Filters

- **Style:** the Filter button opens a sheet of chips — every tag the quilt wears, most-worn first, with the search chip among them — over the canvas, which repacks live behind it. Chips are plain: only Discover says how many patches wear a tag, and the number it says is the quilt's own (`tags` → `node_count`), so both surfaces rank by one thing. Inactive chips are grey; the one tint marks the active ones.
- **State:** the active count badges the Filter button; Clear removes search and interests together. Map, Quilt, and List read the same state.

### Badges and the bell

- **The idiom:** a count on a bar button is a small accent capsule, `minWidth` 16, the caption2 semibold numeral in the system background colour, hung on the glyph's top-trailing corner. Two controls wear it — the Filter button's active-filter count and the bell's unread count — and they are the same badge, because a count is a count wherever it sits. Past ninety-nine it says `99+`: three digits in a 16pt capsule is not a number anybody reads.
- **Room for it:** the Filter button offsets its badge out past its glyph, which works at the bar's leading edge. The bell cannot — it shares a capsule with the account menu, and an overhanging badge is clipped square down its right-hand side — so it pads the glyph first, hangs the badge inside the padded frame, and puts the balance back with the opposite padding. The padding is unconditional: the bell must not shift when the count arrives.
- **Only while there is an account:** the bell is not drawn at all for a signed-out reader, and the count is zero rather than unknown.

### Notifications

- **Style:** a sheet, a `NavigationStack`, cards on the ground — not a stock list. Chips across the top in the web's order (All · Proposals · Governance · Membership · Events · Moderation) plus an Unread-only toggle, wrapping in the same `FlowLayout` the filter sheet uses rather than scrolling sideways, because the chip that gets pushed off the end is the one that is not a category.
- **A row:** the type's mark in muted ink at the leading edge (the web's `NotifIcon` table, in SF Symbols), the title, two lines of body, the relative time, and an unread dot in the accent — the one thing on the screen about to be acted on. The whole card is the door; Dismiss is a swipe and a row menu, never a second button inside the card.
- **Acts:** Mark all read and Clear all live in the bar's menu, and Clear all asks first and says out loud that it clears the quilt rather than the page. "Load more" is an ink act while there is a cursor.
- **Empty:** "Nothing here yet." with a muted line that names the filter it is empty under. "You're all caught up" is a lie to somebody who has narrowed the list.

### Search

- **Style:** the centre field activates in place; results list under it, on the ground, as patches (by name or description) and upcoming events (by title), each a way through to the thing itself. A found patch is a compact patch card, so the card a reader taps here and the card they tap in List are visibly one shape; an event takes the same surface with the platform's chevron, because that one is a push. "Show matches" is an ink act and the suggest row is an exit link. Cancel leaves the surface as it was.
- **Nothing found:** where the quilt says it takes suggestions (`submissions_enabled`), the empty result offers one link to the website's submission form — "Suggest “X” as a patch", carrying the typed name as `?name=X` so the form arrives already about the thing that was looked for. There is no native form; suggesting needs an account.
- **Rule:** typing never narrows the quilt. The last row — "Show matches on the quilt for …" — is the one act that sets the search chip.

### Patch Card

The one shape in the app that is not a system row. A card is "a bordered surface holding something that could move" (web CONTEXT.md), and a patch is exactly that, so List is a scrolling stack of cards on `pwGround` rather than a grouped list — which read as settings where the web reads as patches.

- **The card:** `pwSurface`, a 1pt `pwBorder` border, the site's own `--radius` of 6pt, and the site's soft `0 2px 10px var(--color-shadow)` — faint in light, all but gone in dark, where there is nothing for a shadow to fall on. Cards stack vertically with 12pt between them inside a 16pt gutter. The whole card is the door into the docked profile.
- **Cover strip** (`.card-image`): 100pt tall, full width, filled with the patch's own block — the same `QuiltBlocks.cuts` over `QuiltTheme.palette` the canvas draws, rotated about the centre and hairline-sealed, rendered square and cropped centre (`xMidYMid slice`). The unclaimed mark rides its top-left as the quilt's own 22pt dark disc with the white broken link; the follow chip takes the top-right, as it does on the web.
- **Body** (`.card-body`, 10pt × 12pt): the name at 15/700 with an 18pt **motif disc** inline before it — identity colour, ink or white glyph by luminance — then the counts at 12/600 in `pwText`, a `Moved` chip where the patch left, then up to two lines of the patch's own description in `pwTextMuted`. The card is one accessibility element: it already names the patch, so the drawing is decorative to VoiceOver.
- **Counts:** `N Members · N Events`, or `N Following · N Events` on a community listing, worded as the web's card words it. The event figure is every active event the patch owns — not the head's upcoming count, which answers a different question.
- **Follow:** a heart in a material chip on the strip's top-right, and it is a control wearing the state the server gave it. Signed out it opens the sign-in sheet; a stranger gets the outline heart; a follower the filled one, with a confirm behind it; a member or an admin their role's mark and no act, because leaving a patch is not something to do from a list; a pending request nothing. While the call is out the chip holds a spinner — the heart never fills before the quilt has answered — and it is withheld from a patch that has moved. It is one of the few places the tint belongs: a control, not a phrase.
- **`TileMiniature`** draws either fit — the square `.tile` with both corner marks, or the `.cover` strip — so anywhere else that names a patch gets the same drawing rather than a second decoration of it.
- **The compact card** (`CompactPatchCard`) is the same card for a *ranked* list — Discover's answer and the search results — where the cover strip is the wrong instrument: eight hundred-point covers turn an answer into a scroll, and in search they bury the row that narrows the quilt. The strip becomes the quilt's own 44pt square (`TileMiniature` at `.tile`, both marks) beside the body instead of above it; the motif disc, the counts wording and the `Moved` chip are unchanged, and each surface passes its own accessibility identifier. Only the cloth gets smaller. A card stack inside a `List` is `.listStyle(.grouped)` with `View.plainRow()` rows — a `.plain` list pins its section headers, and a header sliding over a card is the one thing this stack must not do.
- **Header:** "Patches", then `N results` — or `N of M` while the quilt is narrowed, so the filter's work is visible — and a `Menu` of the web's three orders: **Quilt order** (the placement the canvas is drawing, read back), **Recently added** (arrival, else listing, ties A to Z), **A→Z**.
- **Empty states:** a filter that empties the list says "No patches match your filter" with **Clear filter**, plus **Suggest a patch** to the website where `submissions_enabled`; an empty quilt says "No patches here yet" and offers only the suggestion. The list ends in the quiet footer strip.
- **Reuse:** `PatchCard` and `TileMiniature` live in `PatchCard.swift` so Discover rows and search results can adopt the same language.

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

The patch's own profile opens in a native sheet over the surface that opened it — quilt, map, list, search, or Discover. At rest the sheet is the profile's head — cover, name, counts worded as the web words them ("3 Following · 32 Upcoming Events"), tags, the state the patch wears, description — laid out as the web's own head and set edge to edge as the sheet's face, the way a place card is in Maps. The patch's design is a cover band (its block cropped the way the card strip crops it, at least 160pt, growing with a long name) under a scrim rising from the foot, with the name and counts in white on the scrim; the acts ride the cover in Liquid Glass — the overflow (website, share) as a glass disc at the top corner, Follow and Join as glass capsules under the counts, the one that leads tinted in the accent — because glass is what lets a control sit on a busy design without a band behind it (a material stands in where the system has no glass). Everything read rather than pressed sits under the band on the surface, with a hairline where the glimpses begin. The sheet's rounded top is its only corner; plus a 96pt cut of the first glimpse, which is the invitation to pull. Pulled up it is full screen, and the pull is what fetches the rooms. Tapping behind dismisses at rest; the glass close at the cover's top-left and the handle work at any height. There is no bar and no title: the cover says what this is. The underlying discovery state remains intact.

The head wears state, never a button standing in for it: a moved patch's forwarding address (which opens the read-only remote view when it names a patch on another quilt), "No one runs this patch yet" on a community listing, and an "Amended lining" badge on a patch whose lining is its own writing. Following and joining are native controls under the counts (see "Following" below); claiming and voting stay on the website — there are no disabled pretend controls for them.

Below the head are four glimpses in the web's order — About, Events, Members, Governance (ADR 042) — and each heading is itself the door into that room. There is no door named for a container. About is the one heading that names identity rather than a room, so it stays inert: website, the patch's own links, its address with Apple Maps directions, and the atproto handle its claim proved, written past tense. Events shows three, bounded by `from=now` so a section headed Upcoming can only hold what is, and admits the rest as "N more upcoming"; its screen opens on Upcoming and offers what already happened as a second, explicit request, with a Subscribe sheet offering the ICS (`webcal:`) and RSS addresses on a public patch. Members shows a few people and their roles; a withheld roster collapses the glimpse and its screen says the patch doesn't publish its list — never that it has no members — while the counts stay public. Governance shows published documents and recent proposals over an overview of how the patch decides, who leads, and its council's chairs; proposals and the record are absent, not empty, where the patch publishes neither. Every empty state distinguishes "nothing yet" from "not published".

### Discover

Asks one question — "What are you drawn to?" — with the eight most-worn tags on this quilt (counts shown here and nowhere else) and "Show all tags (N more)". The counts are the quilt's own `node_count` from the `tags` vocabulary, which is whole-quilt and public; where that endpoint does not answer they are derived from the patches in hand, so a shortlist is never blank. Ranking is count descending, ties A to Z. A curated term no patch wears is dropped rather than printed as a zero — the same array is the filter sheet's vocabulary, and a chip that can only empty the quilt is worse than an absent one.

The answer has two halves, as the web's does. **Patches you might like** lists what wears the picked tags, the ones with something coming up first — read from the upcoming-events feed rather than claimed — then in quilt order. Under it, **Show the rest of the quilt (N)** folds everything else away behind one disclosure, counted and ordered the same way: the answer is a shortlist, not a verdict on the rest. "Show me everything instead" is one list with no remainder. A row is a compact patch card — the patch's own tile, its motif disc and name, its counts, its tags, its next event, and a **Moved** chip where the patch has a `moved_to`, so the fact is visible before anyone walks into an address that has moved. Each row opens the docked profile.

The question itself is the one place outside a name where the display face is allowed: it is not a screen naming itself, but it is the single sentence the app says in its own voice, it is five words nobody reads at length, and asking it is the whole reason the surface exists. The answer's headings stay Space Grotesk.

Following is native, and the sentence that used to send people away is the way in: signed out, "Following needs an account — reading never does." opens the sign-in sheet rather than the quilt's `/login`, and the docked profile's equivalent line is "Sign in to follow or join." Signed in, neither sentence appears — the heart on each row is the offer, and the profile's own control sits in its head.

### Orientation

One card, over the foot of the quilt, the first time a quilt is opened: what a quilt is, what this one promises, **What is Patchwork?** into the About page, and "I'll lurk for now" as a worded decline. It is an overlay, never a sheet — a modal would have to be dismissed before the quilt could be looked at, which is backwards for a card whose content is that reading costs nothing. It is the one card made of material rather than `pwSurface`, for the same reason: it floats over a quilt that pans and opens underneath it, and an opaque panel over moving cloth reads as the modal it exists in order not to be. Its hairline is still `pwBorder`, and the quilt names itself on it in the display face. It may sit over the canvas, never over a control, and the quilt pans and opens underneath it. Either answer is an answer: the card is offered once per quilt, remembered in `UserDefaults`, and never shown again.

### Events

- **The list:** one flat, grouped `List`, soonest first — no day headers, which made a quiet week read as a wall of empty headings. Each row is when (the event's own zone, accent-tinted), what, where, and whose, with "Community-submitted" beside the patch name where the patch is unclaimed. A cursor "Load more events" sits at the foot; pull to refresh.
- **The date filter:** one row at the head of the list opens a `Menu` holding a `Picker` of the web's presets — Any date, Today, Tomorrow, This weekend, This week, Next week, This month — with the live one checked, and a Custom range… that opens a sheet of two system `DatePicker`s. The presets resolve in the quilt's own time zone, not the reader's. The quilt's tag chips and search chip narrow the calendar too, through the event's host patch.
- **Empty states:** two, and they say different things. A filter that empties the list is standing state — "No events match your filter" with a **Clear filter** button beside it. An empty calendar is not a mistake and gets "No upcoming events" with no action.
- **Badges:** a tier chip (`Followers`, `Members only`) and `Community-submitted` are quiet outlined capsules in caption-2 semibold, secondary foreground, `Color(.separator)` border. A public event wears nothing — a chip on every row says nothing at all. Status wears words, never a colour.
- **The detail:** title, "Hosted by {patch}" as a door into the docked profile, badges, then "with X" capsules for confirmed links and cross-quilt mentions as external doorways. When and where carry the `ends_at` range (same-day reads as one date), the event's zone, the recurrence caveat, and the location. A flyer is a full-bleed `AsyncImage` row; coordinates earn a still, non-interactive `Map` with a marker plus **Open in Maps** and **Directions**. Actions close the page: Add to calendar, "Tickets & details on {host}" where the source says so, and the quilt's own web page. Nothing authenticated appears — no submit, edit, or RSVP.
- **Add to calendar:** a `Menu`, so opening it commits to nothing; the calendar is only asked for once **Add to Calendar** is chosen, which presents the system `EKEventEditViewController`. **Share calendar file** hands the quilt's `.ics` to a share sheet for a reader who keeps their calendar elsewhere. Hidden while a submission is awaiting review.
- **Subscribe:** a patch's own events screen carries a Subscribe menu in the bar — the `webcal:` calendar subscription and the RSS feed.

### Navigation

Use SF Symbols, `TabView`, `NavigationStack`, a re-grounded `List`, a card stack where the content is patches, `Map`, native sheets, and system materials. Quilt choice is always explicit; Lancaster is a directory entry, never an implicit launch selection. Quilts the instance names as neighbours appear in the switcher under Connected quilts as doorways to their own inspect-and-confirm.

## Do's and Don'ts

- **Do** use the `Palette` tokens for ground, surface, hairline and text, and semantic system colours wherever a system component owns them; use Dynamic Type, SF Symbols, VoiceOver labels, safe areas, and 44pt targets.
- **Do** reach a colour through `Color.pwGround` / `.pwSurface` / `.pwBorder` / `.pwText` / `.pwTextMuted` / `.pwAccent`, never a literal, `Color.accentColor`, or a second definition of the same value.
- **Do** set type through `Font.pw.*`, so a screen grows with Dynamic Type in the bundled faces and falls back to SF Pro as one piece if they are ever missing.
- **Do** give a patch its tile wherever it is named outside the quilt: the miniature is the same drawing, not a second decoration of it.
- **Do** preserve placement order, repack filtered subsets, and share one filter state across Quilt, Map, and List.
- **Do** honor Reduce Motion for repacking and native transitions.
- **Do** preserve the active viewport and filters while a profile is open.
- **Don't** invent appearance: a tile is what the patch chose or what the hash assigned, and an unknown key falls back rather than being guessed at. Don't paint names onto fabric, scale marks or seam ink with the quilt, or add hand lettering or generated raster assets.
- **Don't** mean status with colour: identity wears the patch's own colour, status wears a neutral disc. Identity is not a tint either — the quilt mark that stands in for a missing icon is ink.
- **Don't** replace native controls with web-shaped buttons, custom global navigation, or hover-only affordances. A card is not a licence to restyle the system: materials, sheets, the tab bar and the segmented pill stay the platform's.
- **Don't** add gradients or a second elevation step beyond the card's one soft shadow; a surface and a hairline do the work. Don't tint a neutral: one tint means action, and nothing else may.
- **Don't** colour interactive text. A link is ink with an exit arrow, a text door is ink with a chevron, and a link inside prose is underlined — the tint fills controls.
- **Don't** set Shantell Sans on anything a person has to read at length; it is a name's voice, not a paragraph's.
- **Don't** silently select a quilt, and don't draw an authenticated control for a reader who is not signed in: Follow, Join, the standing marks and their exits, and the Dashboard tab appear only when there is a session, and every place that used to be a door out to the website's sign-in is now a door into the native sheet. What the server has no call for is still not drawn at all — suggesting a patch, posting, governance, invitations, notices, RSVP and creating or editing an event remain website links or nothing, and notifications are read, dismissed and cleared natively now, while the preferences behind them stay the website's.
