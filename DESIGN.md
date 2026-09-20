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

Patchwork is a direct, native iOS reader for independently operated communities. It keeps the web quilt's spatial behavior and vocabulary while using system typography, semantic surfaces, SF Symbols, and familiar navigation. The native client has no textile patterns, stitching, fabric texture, hand lettering, or generated raster decoration.

The quilt, map, and list are one discovery instrument. Filtering repacks the matching patches, the list follows quilt placement by default, and a selected patch opens its profile without losing the active filter or viewport. The AccentColor asset supplies the light and dark tint for actions and selection.

**Key Characteristics:**

- Native `TabView`, `NavigationStack`, sheets, lists, and SF Symbols.
- SF Pro and Dynamic Type for all reading content and controls.
- Semantic system colors and materials in light and dark appearances.
- UIKit-backed quilt canvas with direct pinch and pan gestures.

## Colors

Use semantic system roles in SwiftUI/UIKit: `Color.accentColor`, `Color.primary`, `Color.secondary`, `Color(.systemGroupedBackground)`, `Color(.secondarySystemGroupedBackground)`, and `Color(.separator)`. The AccentColor asset has separate light and dark values.

### Primary

- **AccentColor light** (`{colors.accent-light}`) and **AccentColor dark** (`{colors.accent-dark}`): links, prominent actions, selected controls, and map/list selection through the asset-backed `Color.accentColor`.

### Neutral

- **Grouped surfaces:** use `systemGroupedBackground` and `secondarySystemGroupedBackground`.
- **Labels:** use `label` and `secondaryLabel`.
- **Separators:** use the system separator color only where grouped lists provide one.

**The One Tint Rule.** One tint communicates interaction. Meaning must remain available through text, shape, position, and VoiceOver state.

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

The Quilt/Map/List switch is a native segmented control floating over the foot of the canvas above the tab bar, in thumb reach. There is no fit or recentre control; the initial fit and pinch are enough. Quilt uses `QuiltCanvas`, a UIKit `UIScrollView` with zoom and pan; its minimum gesture zoom is 0.3 and its initial fit is clamped to at least 0.65. Filtering matches selected interests with OR semantics and intersects them with the search chip, case and diacritic insensitively over name and description. Matching patches repack from their original sizes, while clearing filters restores the baseline arrangement. Map uses actual coordinates and the same narrowed collection; List uses quilt placement order, Name, or Newest, and states the count in its header.

At initial fit, the smallest tile is at least 46.8pt wide. Manual zooming out can make tiles smaller; List provides conventional full-size targets. The canvas label is inset 8pt, capped at three lines with tail truncation, and counter-scales its caption font to a maximum of 18pt. The full patch name is the accessibility label and the tap opens its profile.

The canvas fills the available iPhone or iPad viewport. Profiles dock as native sheets on both device classes; a persistent side-by-side profile is not implemented.

## Elevation & Depth

Use grouped system backgrounds, separators, and native sheet/material presentation. Resting tiles and rows stay quiet; there is no custom shadow or glass system. Reduce Motion disables animated repacking and uses the platform's reduced transition behavior.

**The Live Surface Rule.** Opening a profile keeps the quilt's filter and viewport alive behind it. Filtering never dismisses the profile; changing quilts does. One temporary overlay at a time: a tap on the canvas behind the filter sheet closes the sheet first, then docks the patch.

## Shapes

Use system-rounded controls and native sheet corners; the only fixed project geometry is the 8pt quilt tile radius. Prefer grouped lists and system separators over bespoke card stacks. Keep tile geometry square and legible; do not add irregular textile edges or decorative seams.

## Components

### Buttons

- **Shape:** native button styles with a 44pt minimum hit area.
- **Primary:** `.borderedProminent` for Find quilt and Explore quilt using `Color.accentColor`.
- **Secondary:** `.bordered`, `.plain`, or `Link` for Cancel, Done, website, directions, and sharing.
- **State:** use system pressed, focus, disabled, and VoiceOver states; never rely on hover.

### Filters

- **Style:** the Filter button opens a sheet of chips — every tag the quilt wears, most-worn first, with the search chip among them — over the canvas, which repacks live behind it. Chips are plain: only Discover says how many patches wear a tag. Inactive chips are grey; the one tint marks the active ones.
- **State:** the active count badges the Filter button; Clear removes search and interests together. Map, Quilt, and List read the same state.

### Search

- **Style:** the centre field activates in place; results list under it, over the surface, as patches (by name or description) and upcoming events (by title), each a way through to the thing itself. Cancel leaves the surface as it was.
- **Rule:** typing never narrows the quilt. The last row — "Show matches on the quilt for …" — is the one act that sets the search chip.

### Quilt Tiles

- **Surface:** `secondarySystemGroupedBackground`, 8pt corner radius, and no image or texture.
- **Label:** bounded UILabel with 8pt inset, three lines, tail ellipsis, and counter-scaled caption text.
- **Interaction:** UIKit pinch/pan belongs to the canvas; tile taps are native buttons with full accessibility names and the hint “Opens patch details.”

### Docked Profile

The patch's own profile opens in a native sheet over the surface that opened it — quilt, map, list, search, or Discover. At rest the sheet is the profile's head — cover, name, counts worded as the web words them ("3 Following · 32 Upcoming Events"), tags, description — plus a 96pt cut of the first glimpse, which is the invitation to pull. Pulled up it is full screen, and the pull is what fetches the upcoming events; Find this patch, Apple Maps directions, the website links, and native sharing follow. Tapping behind dismisses at rest; Done and the handle work at any height. The underlying discovery state remains intact.

### Discover

Asks one question — "What are you drawn to?" — with the eight most-worn tags on this quilt (counts shown here and nowhere else) and a way to show all. The answer lists the patches wearing what was picked, the ones with something coming up first, read from the upcoming-events feed rather than claimed; each row opens the docked profile. Following stays on the website until sign-in exists here.

### Navigation

Use SF Symbols, `TabView`, `NavigationStack`, grouped `List`, `Map`, native sheets, and system materials. Quilt choice is always explicit; Lancaster is a directory entry, never an implicit launch selection. Quilts the instance names as neighbours appear in the switcher under Connected quilts as doorways to their own inspect-and-confirm.

## Do's and Don'ts

- **Do** use semantic colors, Dynamic Type, SF Symbols, VoiceOver labels, safe areas, and 44pt targets.
- **Do** preserve placement order, repack filtered subsets, and share one filter state across Quilt, Map, and List.
- **Do** honor Reduce Motion for repacking and native transitions.
- **Do** preserve the active viewport and filters while a profile is open.
- **Don't** add textile patterns, fabric artwork, stitching, hand lettering, generated raster assets, or a web icon set.
- **Don't** replace native controls with web-shaped buttons, custom global navigation, or hover-only affordances.
- **Don't** silently select a quilt or invent authenticated actions; joining, following, and governance remain website links in this browsing pass, and Dashboard and notifications wait for sign-in rather than standing in the shell as stubs.
