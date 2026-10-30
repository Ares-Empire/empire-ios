# 42: Aresium's graph stays on (a setting), and the header loses the sun and graph buttons

Status: merged 2026-10-30 (Aresium tests pass with brief 43, 0 failed; "Diagramm" in Settings → Dashboard, graph 235 pt above a category's months)
Branch: `claude/42-graph-setting` · Worktree: `../empire-ios-42-graph-setting` · Built by: a Claude agent (the look)

## Goal

Patrik, testing build 3 (2026-10-30): "if I activate the graph, close the app, open it, the Graph isn't activated
anymore. I actually think the app looks better with the Graph on so I think we make it default on and move the light /
dark mode Button into settings (toggle) as well as the Graph Button (toggle). That makes room on the normal screen."

After this brief the graph is a setting (on by default, kept across launches), the start screen's and a category's
graph buttons are gone, and the header's sun button is gone (light and dark are already Settings → General →
Appearance, shared by every app). The dashboard looks the same as today with the graph on, with less in its header.

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules; "Languages"; "Light mode"; "Settings (every app)"; the "Aresium phone mode"
  entry: the tour)
- `Aresium/Aresium/Screens/DashboardScreens.swift` (`DashboardPlace.graph`, `StartScreen`'s and `CategoryScreen`'s
  `IconButton` "Toggle graph", the `SeriesChart`s), `Screens/Components.swift` (`ScreenHeader`: arrow, sun/X, gear;
  `toggleTheme`), `ContentView.swift` (the header's `toggleTheme`: red mode's X vs `Appearance.toggled`; the Settings
  sheet and its `appSection`: `PhoneSettingsSection`, `LockSettingsSection`), `Model/ThemeState.swift`,
  `Shared/Design/SettingsScreen.swift` (General → Appearance), `Model/TourModel.swift` and `Screens/TourScreens.swift`
  (the `.graph` step: "The trend as a graph.", `tourAnchor(.graph)`, `place.graph`).

## Build

1. **The graph is a setting.** A toggle "Graph" (German "Grafik"; pick a better word if one reads more naturally in
   both languages, and say which) in Aresium's own part of Settings, on by default, stored with `@AppStorage` under
   an `aresium.` key. Where in Aresium's Settings: next to what it belongs with; one line of note under it only if
   needed. Server mode and phone mode alike; the sample (demo) follows it too.
2. **Start screen:** the graph shows when the setting is on, exactly as it does today with the toggle on; the
   graph button next to Import goes. The row keeps Current/Overview and Import.
3. **A category's page:** today the graph *replaces* the list of months. With the graph on by default that would hide
   every month's total, so show both: the graph above the months list (as on the start screen), at a height that leaves
   months visible on an iPhone 17, its tap on a month still opening that month. Setting off: the list alone, as today.
   The graph button above it goes. Check VoiceOver still reaches the months (the chart's
   `accessibilityRepresentation` can go once the list is always there).
4. **Header:** the sun/moon button goes. Red mode (entered through the band) keeps its X in the same place: it is the
   way out. Settings → General → Appearance is where light and dark are chosen (it exists; nothing to build). Keep
   the header's balance: say what you did with the freed space (nothing is fine).
5. **The tour:** its graph step asked for a tap on the graph button. Make it point at the graph itself and say what
   it shows and that Settings can hide it (or, if the step adds nothing now, drop it and renumber cleanly). The tour's
   own dashboard shows the graph on whatever the person's setting is. Keep the tour's tests passing; change those
   that tested the button.
6. **German** for every new text (`scripts/strings.py`); "Toggle graph" and "Toggle theme" leave the catalog if
   unused.

## Settled: do not re-open

- Graph on by default; light/dark only in Settings → Appearance (no second toggle for it in Aresium's section).
- No other change to the header, the graph's drawing or the rows.

## Out of scope

- Renaming payments and the "all from this shop" page: briefs 43 (data, Codex, in parallel; it does not touch
  `Screens/`) and 44 (screens, after both). Leave `DashboardStore`'s data and `Model/Phone*.swift` alone.
- The other apps.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium` passes on your own simulator (`claude-42`,
  commands in `AGENTS.md`), with tests where there is logic (the setting's default is on; the tour step).
- The widget and the other apps build if you touch `Shared/` (you should not need to).
- `scripts/strings.py check`: 0 problems.
- Looked at on the simulator in English and German, light and dark: screenshots `build/42-*.png` (start screen with
  the graph, a category with graph and months, the setting, the header in red mode with its X, the tour's graph step).
- The setting survives a relaunch (quit the app on the simulator and open it again).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, your choices (the
setting's word and place, the category page's graph height, the tour step), what is missing or doubtful. Never
commit, push or merge: Claude does.
