# Parity with the web

What the web app does that this app also does, what it leaves to the website on
purpose, and what it doesn't do yet. The web is the reference: the server and
the web app ship as one image, so whatever the web does is what the API
supports. This app aims for parity of function and layout on public-facing
features first, then member actions, in a native iOS feel rather than the web's
styling.

**Last checked:** web `v0.35.2` (origin/main `9b4b4bf`) against app main
`ef158ad`, on 2026-11-11.

## Keeping it current

At every web release:

1. Read the release's **For client developers** section in
   `release-notes/vX.Y.Z.md` (required from v0.36.0, see web
   `docs/adr/2026-11-11-a-release-says-what-it-means-for-clients.md`). If
   `client_breaking` is true, fix that first. A broken post or a misread field
   comes before any new feature.
2. Compare the web's route table (`addRoute` in `web/src/App.svelte`) and the
   rest of the release notes against this file. Add rows for anything new, and
   move rows whose status changed.
3. Update **Last checked** above.

When this app learns a route that a link should open, change `Links.swift`
and the web's `appleLinkComponents` (`internal/handler/native_apps.go`)
together. The web test `TestApplinksClaimMatchesTheClientsRoutes` holds the
two to each other.

**Statuses:**
- **Built:** the app does what the web does.
- **Partial:** the app does part of it; the note says what's missing.
- **Not yet:** missing, and wanted.
- **Website:** left to the website on purpose; the app links out or doesn't offer it.
- **Redirect:** an old address the web forwards; the app follows the same forwarding.

## Pages

| Web route | Status | In the app | Notes |
|---|---|---|---|
| `/`, `/patches`, `/my` | Built | `QuiltHome`, `QuiltBrowser`, `QuiltCanvas` | Quilt, My Quilt, list mode |
| `/map`, `/map/my` | Built | `QuiltMap` | Zoom buttons and the in-view lens left out |
| `/events`, `/events/my` | Built | `Events`, `EventFilters` | Date presets, tag filter. No search inside a patch's calendar yet (below) |
| `/events/:id` | Partial | `Events` (detail) | No "detach" for an imported event (`POST events/{id}/detach`) |
| `/events/new`, `/events/:id/edit` | Built | `EventForm`, `EventPosting`, `EventEditing` | Opened from the patch, not as a bare page |
| `/discover` | Built | `Discover` | |
| `/dashboard` | Built | `Dashboard` | Attention needed, Add a patch |
| `/notifications` | Partial | `Notifications` | Rows don't name the sender (`node_name`). The web dropped its category chips; the app keeps them |
| `/activity` | Not yet | | What's New feed, `GET /api/v1/activity`. The web has no link to it yet either |
| `/about`, `/label`, `/lining`, `/governance`, `/privacy`, `/terms` | Built | `QuiltInfo` | One info stack on the account menu |
| `/ai` | Not yet | | Patchwork & AI page, `GET /api/v1/ai`. Belongs in the `QuiltInfo` stack and in `Links.swift` |
| `/patches/:slug` | Built | `PatchProfile`, `PatchProfileParts` | Docked profile and four glimpses. No nonprofit badge yet (below) |
| `/patches/:slug/events` | Built | `PatchCalendar` | ICS and RSS subscribe |
| `/patches/:slug/members` | Built | `PatchMembers` | |
| `/patches/:slug/governance` and below: docs, history, propose, proposals, record, rules, new | Built | `Governance`, `PatchGovernance`, `GovernanceDocuments`, `DocumentAuthoring`, `ProposalDetail`, `ProposalForm`, `RulesChange*` | The interim-admin offer has no Accept or Decline (below) |
| `/patches/:slug/noticeboard`, `/:id`, `/new` | Built | `PatchNoticeboard`, `NoticeDetail`, `Noticeboard` | |
| `/patches/:slug/claim`, `/setup` | Built | `Claiming`, `PatchCreation` | |
| `/patches/:slug/settings/info`, `/appearance` | Built | `PatchForm` (edit mode), `PatchSettings` | Edit patch, from the profile's ⋯ menu |
| `/patches/:slug/settings/members`, `/noticeboard` | Built | `PatchAdmin`, `JoinRequests`, `NoticeReports` | Doors at the head of the admin's rooms |
| `/patches/:slug/settings/intro`, `/sources`, `/notifications`, `/verification`, `/danger` | Website | | Admin-only. The edit form links out |
| `/patches/new`, `/submit` | Built | `PatchCreation`, `PatchSuggestion` | |
| `/quilts/:host/patches/:slug` | Partial | `RemotePatch` | Read-only; no Follow for a patch on another quilt (`users/me/remote-follows`) |
| `/users/:username` | Built | `PersonProfile` | |
| `/invite/:token` | Built | `AccountInvites` | |
| `/login`, `/signup/complete`, `/welcome` | Built | `SignIn`, `Welcome`, `Passkeys` | Code sign-in and passkeys |
| `/login/link/:token`, `/claims/verify-email` | Website | | Email links. They stay in the browser and aren't claimed by app links |
| `/settings`, `/settings/notifications`, `/settings/patches`, `/settings/security` | Built | `Settings`, `NotificationPreferences`, `MyPatches`, `Passkeys` | |
| `/settings/quilts` | Not yet | `QuiltSwitcher` (device only) | Connected quilts synced with the account (`users/me/quilts`) |
| `/admin`, `/admin/*` | Website | | Instance administration |
| `/patches/:slug/` + `manage*`, `charters*`, `proposals*`, `events/:id`, `governance-setup` | Redirect | `Links.swift` | |

## Features that span pages

| Feature | Status | In the app | Notes |
|---|---|---|---|
| AI disclosure: the question on every form that posts, the "Made with AI" tag, the patch's AI work badge, the reader's hide switch, the `unlabelled_ai` report reason | Built | `AIUse`, the posting forms, `Events`, `NoticeDetail`, `ProposalDetail`, `PatchCard`, `Settings` | Web ADR 2026-10-20. Follows the quilt's `ai_disclosure`; on `required` a post is refused in the form, before the server would refuse it |
| Interim-admin offer (`membership.interim_offer`) | Not yet | | Accept or Decline on the governance overview: `POST nodes/{slug}/interim-offer/accept` and `/decline` |
| Nonprofit badge (`nodes.nonprofit`) | Not yet | | Shown on the patch head; set on create, on suggest and in Edit patch |
| Search inside a patch | Not yet | | `search=` on `/events`, `/nodes/{slug}/proposals`, `/nodes/{slug}/members`, as `.searchable` |
| Filter chips (web ADR 2026-10-29) | Partial | `FilterSheet` | The web shows one row of chips on the canvas, plus a find field; the app shows every chip in a sheet |
| Event co-hosts | Not yet | | Web #438, not merged |
| Bell dropdown | Built | `Notifications` | Desktop-only on the web; a phone gets the page, like the app's sheet |
| Long lists past page one | Built | `MembershipPage`, `PatchCalendar` | Cursors followed |
