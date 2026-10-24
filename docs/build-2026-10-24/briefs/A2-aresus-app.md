# A2: the Aresus iPhone app (Aresus + Aresync)

Read `COMMON.md` and `DESIGN.md` (same folder) first; DESIGN.md is binding. Worktree: `~/wt/empire-ios-aresus`
(branch `aresus-app`). Your simulator: `agent-aresus` (already created, iOS 27.0, iPhone 17; boot it yourself).

## Goal

The complete Aresus app on the simulator: the watchtower (every province with its state, the server, a province's
checks, deploy, uptime and incidents) and the Aresync tab (machines and their sync runs). Data from the Aresus API
(contract `~/aresus/docs/API.md`, samples in `Aresus/Aresus/Samples/` = copies of `~/aresus/docs/samples/`). The server is
being built in parallel; build against the contract and the samples. Why and what: `~/ares-empire/docs/ARESUS-APP.md`.

## Read first

- `~/aresus/docs/API.md` (every type and route), the samples, `~/ares-empire/docs/ARESUS-APP.md`
- The Empire app as the **structure** reference: `Empire/Empire/API/EmpireAPI.swift`, `Model/EmpireStore.swift`,
  `Model/EmpireSamples.swift`, `ContentView.swift`, its tests; and its **look**: `Screens/EmpireRing.swift` (`RingTab`:
  the province box Patrik likes), `Screens/EmpireSheets.swift` (province page)
- `Shared/Auth/EmpireSession.swift` (`EmpireAppIdentity.aresus` exists), `Shared/API/HTTP.swift`, `Shared/Design/`
  (`ProvinceMarks` loads a province's bust from the hub with the token: use it for the marks; in sample mode it returns
  nil, so marks show monograms)
- The project is set up: `Aresus/Aresus.xcodeproj` (folder-synchronized), icon (Zeus), images `Bust` (Zeus) and
  `SyncBust` (Janus), accent, URL scheme `aresus://`, entitlements. Don't edit `project.pbxproj`, the entitlements or
  `Shared/`.

## Build

**Data (no UI logic in views):** `API/AresusAPI.swift` (base `https://www.ares-empire.de/api/aresus`, Bearer from the
session, `checkResponse`; 401 → `session.handleAuthFailure`, 403 → denied), Codable models exactly as the contract
(`RunSummary | QuietDay` as one enum decoded by the `quiet` key), an `@Observable @MainActor` `AresusStore` (overview,
province details cached by slug, sync overview, run details; refresh on foreground and every 60 s while visible),
`Model/AresusSamples.swift` (DEBUG `-sampleData`), formatting helpers with tests: relative times ("12 s ago", "4 min ago",
"yesterday 23:57"), durations ("6 min", "2 h 10 min"), percentages, uptime, day headings ("Today", "Yesterday",
"Sat 19 Oct"), grouping of runs by day, and deep-link routing (`aresus://province/<slug>`, `aresus://sync/run/<id>`,
`aresus://server`).

**Root:** restoring → `ProvinceLoading(name: "Aresus", bust: Image("Bust"), accent: .aresus)`; not signed in / denied →
`ProvinceLogin(…, name: "Aresus", …)`; signed in → `TabView` (tint = accent) with **Aresus** (`binoculars`) and
**Aresync** (`arrow.triangle.2.circlepath`). `onOpenURL` routes deep links. Follow the shared login like the other apps.

**Aresus tab** (scroll, `ProvinceWall` behind, pull to refresh):
1. Header row: Zeus bust 38 pt left, "Aresus" centred (17 bold), right a `GlassIconButton` `ellipsis` menu with "Log out".
2. Summary painted on the wall (no card, like Aresium's "Expenses €935" header): `SectionHeading` with the date and time
   of the check ("SAT 24 OCT · 12:09"), then the summary big (26 bold): "Everything running" in ink, or "1 issue" in the
   issue red; after it a muted mono "checked 12 s ago".
3. Server card (glass): four figures side by side: Disk, Memory, Load, Up (label tracked caps 10 over value mono 17);
   under Disk and Memory a 3 pt capsule bar (accent; issue red when over the limit). If `server.issue`, one line in
   issue red below.
4. Sections **Issues** (only if any), **Active**, **Inactive**, each a `SectionHeading` with the count, then the
   province boxes, 12 pt apart.
   - **Province box** = the hub's ring tab, full width: glass card (radius 16, height ≈ 78), `ProvinceMarkView` 48 pt
     left, then the NAME in tracked caps (15 bold, **ink**, not gold) over the `StatusLabel` word (Active green / Issue
     red / Inactive or Planned grey), and the `line` (12, muted, one line) below; chevron right. Issue boxes get a faint
     red edge (`StatusTone.issue` at 0.35 instead of the glass edge); inactive boxes are quieter (content at 0.7 opacity).
   - Tap → **province detail** (pushed): the mark 88 pt centred, the name (26 bold), the status word, the line, `about`
     (14 secondary, centred); **Checks** (glass card, a row each: a small green `checkmark` or red `xmark`, the name,
     the detail in mono 12 right-aligned); **Last deploy** (commit mono, subject, date; "3 commits on GitHub not deployed"
     in muted amber `#E0B15A` when `behind > 0`); **14 days** (14 thin vertical bars across the width: accent for 100 %,
     the down share in issue red, grey for not watched; day initials under the first and last); **Incidents** (rows:
     date, duration or "ongoing" in red, summary). Empty sections are left out.
5. `WordmarkBand(word: "ARESUS", width:)` at the end of the scroll content.

**Aresync tab** (scroll, pull to refresh):
1. Header: Janus bust (`SyncBust`) 38 pt left, "Aresync" centred.
2. **Machines**: one glass card, a row per machine: SF Symbol by OS (`laptopcomputer` macOS, `pc` Windows,
   `server.rack` Linux) in muted ink, the name (15 semibold), "last sync 4 min ago" (12 muted mono), the
   `StatusLabel` right; open problems below the row in issue red (12, up to 2 lines).
3. **Runs**, grouped by day (`SectionHeading`: "Today", "Yesterday", "Sat 19 Oct"): rows inside one glass card per
   day, hairline separators (`Ink.line`): time (mono 13) · machine (13 semibold) · summary (13 secondary, 1 line) · the
   result word right (`OK` green / `FAILED` red, `StatusLabel` size 9.5). Quiet-day items are a single muted row
   "Server · 141 quiet runs", not tappable. Tap a run → **run sheet** (`.medium/.large`): machine, finished time and
   result in the header; the counts as small mono capsules ("pulled 3", "committed 1", "failed 1"; zeros left out);
   problems in issue red; the log lines in a mono block (JetBrains 11.5 on `Ink.card2`, radius 11): `FAIL` lines in
   issue red, `SKIP`/`WARN` muted, others ink.
4. Empty: "No sync reports yet. Each machine reports after its next run."

**Notifications (no PushCenter yet):** routing from a notification URL to the app's navigation (tested); the lead wires
`Shared/Push` (being built in parallel) after merging.

**Launch arguments (DEBUG)** for screenshots: `-sampleData`, `-tab aresus|aresync`, `-openProvince <slug>`,
`-openRun <id>`, `-sampleAllGood` (overview without issues: derive it from the sample by mapping the issue to active).

## Tests (Swift Testing, `AresusTests/`)

Decoding every sample; the run/quiet-day enum; formatting and grouping; API requests (paths, Bearer) with a fake
transport; 401/403; store refresh; deep-link routing.

## Done when

- `xcodebuild test -project Aresus/Aresus.xcodeproj -scheme Aresus -destination 'platform=iOS Simulator,name=agent-aresus' -derivedDataPath build/DerivedData` passes.
- Screenshots in `build/screens/`: aresus (with an issue), aresus (all good), aresus scrolled to the bottom (inactive +
  wordmark), province detail (issue), province detail (inactive), aresync, run sheet, login, loading. You looked at each
  and fixed what was off.
- Committed on `aresus-app`. Final message as in COMMON.md, plus anything you'd want in Shared/ (named, not built there)
  and any `CONTRACT ADDITION` you needed.
