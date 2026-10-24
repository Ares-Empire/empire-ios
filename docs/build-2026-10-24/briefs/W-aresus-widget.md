# W: Aresus home-screen and lock-screen widget

Read `COMMON.md` and `DESIGN.md` (same folder) first; DESIGN.md is binding (the look is the point; the accent stays an
accent). Worktree: `~/wt/empire-ios-widget` (branch `aresus-widget`). Your simulator: `agent-widget` (create it with
`xcrun simctl create agent-widget com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-27-0`;
never touch the device named "iPhone 17").

## Goal

The Aresus app (`Aresus/`, merged today) gets widgets so Patrik sees the empire's state without opening the app:
"All running" in green, or "1 issue · Arestemis" in red, always with how fresh the check is.

## Read first

- `Aresus/` (the app: `Model/AresusModels.swift`, `AresusStore.swift`, `AresusDisplay.swift`, `AresusFormat.swift`,
  `API/AresusAPI.swift`, `Screens/`), `~/aresus/docs/API.md` (`GET /overview`)
- How Aresium does widgets (the template for the target setup): `Aresium/AresiumWidget/` (bundle, providers, views,
  Info.plist), `Aresium/AresiumShared/` (compiled into app AND widget), `Aresium/Aresium.xcodeproj/project.pbxproj`
  (the `AresiumWidgetExtension` target, its folder groups, the embed phase, entitlements), `Aresium/*.entitlements`
- `Shared/` (compiled into every app and widget: `EmpireSession`, `TokenKeychain`, `HTTP.swift`, `Design/`, `AppFont`)

## Build

- **Target** `AresusWidgetExtension` in `Aresus/Aresus.xcodeproj`, built like Aresium's: folder-synchronized group
  `Aresus/AresusWidget/` (widget only), a new `Aresus/AresusShared/` compiled into app and widget (move only what both
  need, e.g. the overview models and formatting, out of `Aresus/Aresus/Model/`; no copies), `../Shared` in the widget too,
  embedded in the app, bundle id `de.ares-empire.aresus.widget`, `AresusWidget.entitlements` with the same App Group
  (`group.de.ares-empire.shared`) and Keychain group as the app. **You may edit `project.pbxproj` for this** (carefully,
  modelled on the Aresium widget target; keep the project opening and building).
- **Data:** the widget is a status light, so it must not show stale state as current.
  - The timeline provider fetches `GET /api/aresus/overview` itself with the shared Empire token from the Keychain
    (`TokenKeychain` in Shared; the widget never logs in or renews; a 401/403 means "Log in in the app"), maps it to a
    small Codable `WidgetStatus` (summary, state, the issue provinces with name + line, counts per state, the server
    issue if any, Aresync's line, `checked`), saves it in the App Group (atomic file, like Aresium's snapshot store) and
    shows it. Refresh every 15 minutes (`.after(now + 15 min)`).
  - Offline or the server unreachable: show the saved status with its `checked` time (the age then makes clear it is old).
  - The app also saves the `WidgetStatus` whenever it loads the overview and calls `WidgetCenter.reloadAllTimelines()`.
    Logging out deletes it.
- **Widgets** (one `WidgetBundle`, kind `AresusStatus`), background `ProvinceWall(accent: .aresus)` via
  `containerBackground`, fonts via `AppFont.register()` in the bundle's init (as Aresium does):
  - **Small:** top row: the Zeus bust (`Bust` image; add it to the widget's asset catalog) 22 pt + "ARESUS" tracked caps
    9 pt muted. Middle: all good → a 7 pt green dot + "All running" (text 18 semibold, ink, may wrap); issues → "1 issue" /
    "2 issues" (text 22 bold, issue red) and under it the first province name (13 semibold ink) and its line (11 muted,
    2 lines). Bottom: "checked 4 min ago" (mono 10 muted; use `Text(date, style: .relative)`-like live text so it ages
    by itself). Tap → `aresus://`.
  - **Medium:** left half as the small one; right half: issues → up to 3 rows (name 12 semibold + line 10.5 muted), each
    a `Link` to `aresus://province/<slug>`; all good → the counts ("5 active", "8 inactive", in mono 12 with their tone
    colours) and Aresync's line ("Aresync · last sync 4 min ago", 11 muted). A thin `Ink.line` divider between halves.
  - **Lock screen** `accessoryRectangular`: "ARESUS" (caps 10) / "All running" or "1 issue · Arestemis" / "checked 4 min
    ago"; `accessoryCircular`: a gauge-like ring with the number of issues (0 = a checkmark).
  - Logged out / never loaded: "Open Aresus to log in" (12 muted), the bust, nothing else.
- **Screenshots without a home screen:** a DEBUG launch argument `-widgetGallery` in the Aresus app shows the widget views
  (small, medium, rectangular, circular; all good, 1 issue, 3 issues, logged out) rendered at their real sizes on the
  wall, for screenshots. Use the bundled samples (`Aresus/Aresus/Samples/`) for the states.
- **Tests:** `WidgetStatus` from an overview (all good, issues, server issue, ordering), the store (save/read/delete,
  missing/corrupt file), the provider's choice between live and saved status (fake fetch), age formatting.

## Done when

- `xcodebuild test -project Aresus/Aresus.xcodeproj -scheme Aresus -destination 'platform=iOS Simulator,name=agent-widget' -derivedDataPath build/DerivedData` passes, and the app with its widget builds.
- Screenshots in `build/screens/`: `widget-gallery-good.png`, `widget-gallery-issues.png`, `widget-gallery-loggedout.png`;
  you looked at each and fixed what was off (alignment, sizes, crowding, accent overuse).
- Committed on `aresus-widget`. Final message as in COMMON.md.
