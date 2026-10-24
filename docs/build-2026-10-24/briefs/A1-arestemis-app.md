# A1: the Arestemis iPhone app

Read `COMMON.md` and `DESIGN.md` (same folder) first; DESIGN.md is binding. Worktree: `~/wt/empire-ios-arestemis`
(branch `arestemis-app`). Your simulator: `agent-arestemis` (already created, iOS 27.0, iPhone 17; boot it yourself).

## Goal

The complete Arestemis app on the simulator: set a flat search, start/pause the hunt, see matches and act on them,
get the application text, settings. Data from the Arestemis API (contract `~/Arestemis/docs/API.md`, samples in
`Arestemis/Arestemis/Samples/` = copies of `~/Arestemis/docs/samples/`). The server is being built in parallel; build
against the contract and the samples. Why and what: `~/ares-empire/docs/ARESTEMIS-APP.md`.

## Read first

- `~/Arestemis/docs/API.md` (every type and route), the samples, `~/ares-empire/docs/ARESTEMIS-APP.md`
- The Empire app as the **structure** reference: `Empire/Empire/API/EmpireAPI.swift`, `Model/EmpireStore.swift`,
  `Model/EmpireSamples.swift`, `ContentView.swift`, and its tests (`Empire/EmpireTests/`, fakes in `EmpireTestSupport.swift`)
- `Shared/Auth/EmpireSession.swift` (`EmpireAppIdentity.arestemis` exists), `Shared/API/HTTP.swift`, `Shared/Design/`
- The project is set up: `Arestemis/Arestemis.xcodeproj` (folder-synchronized: new files in `Arestemis/Arestemis/` and
  `Arestemis/ArestemisTests/` need no project edits; `Shared/` is included), icon, `Bust` image, accent colour, URL
  scheme `arestemis://`, entitlements. Don't edit `project.pbxproj`, the entitlements or `Shared/`.

## Build

**Data (no UI logic in views):** `API/ArestemisAPI.swift` (base `https://www.ares-empire.de/api/arestemis`, Bearer token
from the session, `checkResponse`; 401 → `session.handleAuthFailure`, 403 → the app's denied state), Codable models
mirroring the contract exactly (`Model/`), an `@Observable @MainActor` store per area or one `ArestemisStore` (overview,
hunt, matches by state, rejected, settings, places search with debounce, parse, application per match; optimistic state
changes with rollback on failure), `Model/ArestemisSamples.swift` (DEBUG `-sampleData`: everything from the bundled
samples, actions work in memory), formatting helpers with tests: money (`€980`, `€1,150`), m², relative times
("4 min ago", "yesterday 18:05"), dates ("1 Dec"), the **search summary** (two lines, see Hunt) and the push/notification
URL routing (`arestemis://match/<id>`, optional `?action=application`).

**Root:** restoring → `ProvinceLoading`; not signed in or denied → `ProvinceLogin(session:, name: "Arestemis", bust:
Image("Bust"), accent: .arestemis)`; signed in → a `TabView` (tint = accent) with three tabs: **Hunt**
(`scope`), **Listings** (`list.bullet.rectangle`), **Search** (`slider.horizontal.3`). `onOpenURL` routes deep links
(match → Listings tab, push its detail; `action=application` also opens the application sheet). Follow the shared login
like the other apps (`followSharedLogin()` on foreground; see Empire's ContentView).

**Hunt tab** (scroll, `ProvinceWall` behind):
1. Header row: bust 38 pt left, "Arestemis" centred (17 bold), right a `GlassIconButton` `gearshape` → Settings sheet.
2. Hero glass card (`raised`, accent edge): top line a status — accent dot (8 pt, soft pulse) + `StatusLabel("Hunting",
   .accent)`, or a grey dot + `StatusLabel("Paused", .inactive)`; then the search summary: line 1 (20 semibold, ink)
   the kinds ("Own flat or empty 2-person WG"), line 2 (14, secondary) places · rent · move-in ("München, Garching · up to
   €1,000 warm · from 1 Dec"); then one full-width button: **Start hunting** (accent fill, dark text, the screen's one
   accent button) or **Pause** (glass, ink). No hunt yet: "No search yet" + "Set up your search" (accent) → Search tab.
3. Three small figures in one glass card row: New · Today · Applied (number 22 mono over a tracked caps label 10),
   below it one muted line "Last scan 40 s ago" (mono 11).
4. `SectionHeading("Portals")` + one glass card with a row per portal: name, a 6 pt dot (green ok / red blocked or
   error / grey idle), the note in muted 12 at the right ("Only München").
5. `SectionHeading("Latest")` + up to 3 match rows (the Listings row component) + a quiet "All listings" link.
6. `WordmarkBand(word: "ARESTEMIS", width:)` at the end of the scroll content.
Pull to refresh reloads the overview.

**Listings tab:** title "Listings" (header style as above, bust left), a segmented picker **New · Saved · Applied ·
All**, then a `List` (plain style, clear row backgrounds, rows as glass cards with 12 pt spacing) of match rows:
- Row: left, the photo if `image_url` (56 pt, radius 11, `AsyncImage`, quiet placeholder) else nothing; the rent big
  (`€980` mono 20 bold) with "warm" (11 muted) after it; facts line (13 secondary): "42 m² · 2 rooms · Schwabing";
  bottom line (11 muted): "WG-Gesucht · 4 min ago"; an accent "new" dot (7 pt) at the top right for state `new`; chevron.
- Swipe: leading **Save** (accent tint) / trailing **Dismiss** (grey). Tap → detail.
- At the end a quiet row "Filtered out · 2" → sheet with the rejected listings (title, facts, the reason in muted 13,
  tap opens the portal page).
- Empty: "No listings yet. They appear here the moment they're found."

**Match detail** (pushed): hero: rent `€980` (mono 34 bold) + "warm", cold rent below if known ("€820 cold", muted
mono 13); title (17 semibold, 2 lines); a facts grid in a glass card (two columns of label/value pairs: Size, Rooms,
Kind, Move-in, Until, Furnished, District, Posted; only the known ones); a "Why it fits" glass card with the accent edge:
the reason (15) and warnings (each with `exclamationmark.triangle` in amber `#E0B15A`, 13); the description (14,
secondary, 6 lines, "More" expands). A bottom bar (safe-area inset): primary **Application** (accent) and secondary
**Open on WG-Gesucht** (glass, the source name). Toolbar menu (`ellipsis`): Save / Mark applied / Dismiss (current
state checked). Viewing a `new` match sets it to `saved`? No: keep `new` until the user acts; only the "new" dot fades.
**Application sheet** (`.medium/.large`): a label "Written by AI" or "Your text" (tracked caps), the text in a glass
card (selectable, 15, line spacing 5), buttons: **Copy and open listing** (accent; copies to the clipboard, then opens
the portal URL), **Copy**, and in AI mode **Write again** (regenerate, shows progress). After copying, a quiet
"Mark as applied" button appears.

**Search tab** (form in glass cards, one `SectionHeading` each; save at the bottom):
1. "Describe it": a multi-line field ("e.g. 2-room flat in Schwabing up to €1,000 warm from December") + **Fill in**
   (calls `/search/parse`, fills the fields below, shows `unclear` as muted notes). Optional; the fields are the truth.
2. **What:** toggle chips "Own flat", "Room in a WG", "Empty 2-person WG" (selected chip: accent edge + accent text on
   a faint accent fill `accent.opacity(0.14)`; unselected: glass + `Ink.line`).
3. **Where:** place chips (× to remove) + "Add place" → a sheet with a search field and suggestions from `/places`
   (name, region, and in muted 11 the portals that cover it); districts as chips with a small "Add district" field.
4. **Rent and size:** max warm rent (mono field with €), "Bigger flats may cost more": tier rows "from [40] m² up to
   [€1,200]" with add/remove; min size (m²); min rooms (Stepper; only if "Own flat" selected); max flatmates (Stepper;
   only if a WG kind selected).
5. **Move-in:** from / until (optional, `DatePicker` compact with a toggle each); sublets segmented "No sublets ·
   Include · Only"; furnished segmented "Any · Yes · No".
6. **Anything else:** a text field with the caption "Checked by the AI on every listing."
7. **Portals:** three toggles (accent tint), Immowelt's note "Only München".
8. **Save search** (accent, full width; disabled until valid: ≥ 1 kind, ≥ 1 place, ≥ 1 portal). With an active hunt,
   a muted note "Changes apply from the next scan." At the very bottom a quiet destructive "Delete search" (confirm).
No hunt yet → the same form, the button reads **Create search** (the hunt is created paused; the Hunt tab then offers
Start hunting).

**Settings sheet:** sections **Application** (segmented "Your text · AI per listing"; "Your text" editor; "About you"
editor with caption "Facts the AI may use. It never invents others."), **Notifications** (toggles "Push" and
"Time-sensitive" with caption "Shows even in Focus"), **Account** (the account name/email if known, **Log out**). Save on
dismiss (or a Done button that saves).

**Notifications (no PushCenter yet):** define the category `ARESTEMIS_MATCH` with actions "Open listing" and
"Application" in one place (`Model/Notifications.swift`) and the routing from a notification URL/action to the app's
navigation (tested). The lead wires `Shared/Push` (being built in parallel) after merging.

**Launch arguments (DEBUG)** for screenshots: `-sampleData`, `-tab hunt|listings|search`, `-openMatch <id>`,
`-openSheet settings|application|rejected|place`, `-sampleNoHunt` (no hunt yet), `-samplePaused`.

## Tests (Swift Testing, `ArestemisTests/`)

Decoding every sample file; formatting (money, sizes, relative time, search summary for several searches); API client
requests (paths, methods, bodies, Bearer header) with a fake transport; 401/403 handling; store actions incl. optimistic
state change + rollback; deep-link routing; search validation.

## Done when

- `xcodebuild test -project Arestemis/Arestemis.xcodeproj -scheme Arestemis -destination 'platform=iOS Simulator,name=agent-arestemis' -derivedDataPath build/DerivedData` passes.
- Screenshots in `build/screens/`: hunt (hunting), hunt (paused), hunt (no hunt), listings (new), listings (all),
  match detail, application sheet, rejected sheet, search (top), search (bottom), place search sheet, settings, login,
  loading. You looked at each and fixed what was off.
- Committed on `arestemis-app`. Final message as in COMMON.md, plus anything in Shared/ you would want (named, not built
  there) and any `CONTRACT ADDITION` you needed.
