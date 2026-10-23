# 05: Aresium widgets (medium: this month's spending line; small: two categories)

Status: merged 2026-10-23. 67 tests; widgets rendered in tests, not yet placed on a home screen.
Branch: `codex/05-aresium-widgets` · Worktree: `../empire-ios-05-aresium-widgets` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Two home-screen widgets, decided with Patrik on 2026-10-23:

- **Medium** (the horizontal rectangle): the current month's spending as a line that climbs through the month
  (`byMonth[current].dayExpenseRunning`), with the month and its total (`byMonth[current].expense`).
- **Small:** this month's spending in two categories, by default **Groceries** and **Drogerie**; both can be
  changed with Edit Widget (long press). Rent is not offered as a default.

No lock-screen widget. The widget never logs in and never calls the server: it shows a snapshot the app writes.

## Read first

- `AGENTS.md`, `CLAUDE.md` (always), the app as it is (`Aresium/Aresium/`), and the project setup Claude added for
  this brief (see "Project setup" below).
- `~/aresium/docs/API-DATA.md`: `byMonth[key].expense`, `.dayExpenseRunning`, `.categories`, `months` (the last one
  is the current month; `partial` and `days` = today for the running month).
- Apple's WidgetKit and App Intents docs as needed (`AppIntentConfiguration`, `AppEntity`, `EntityQuery`).

## Project setup (done by Claude; do not change the project file)

- Widget extension target `AresiumWidget` (folder `Aresium/AresiumWidget/`, synchronized), embedded in the app.
- Folder `Aresium/AresiumShared/` is compiled into **both** the app and the widget: put the snapshot model and
  anything both need there. `Theme.swift` and the fonts already live there, so the widget can use the same
  colours and fonts (register the fonts in the widget too).
- Both targets have the App Group `group.de.ares-empire.aresium` (entitlements files exist).

## Build

1. **Snapshot** (`AresiumShared/`): a small `Codable` value with what the widgets show: the current month's key,
   label, its full length in days, the running total so far, the month total, the date of the newest
   transaction, and for every spend category its name, icon, colour and this month's total (from
   `byMonth[current].categories`; a category missing there is 0). Only copied from the dashboard: no money is
   calculated (this rule is in `CLAUDE.md` and brief 01).
2. **The app writes it** to the App Group container after every successful dashboard load (and in sample mode
   from the sample), then calls `WidgetCenter.shared.reloadAllTimelines()`. Logging out deletes it.
3. **Medium widget:** month label and total at the top, the running line below with the x-axis spanning the
   whole month (so the line stops at today), Swift Charts, expenses colour of the current theme; a small "up to
   22 Oct" with the newest transaction's date. Tap opens the app on the start screen.
4. **Small widget:** two rows, each with the category's icon, name and this month's amount, in its colour, plus
   the month label. Configurable via an `AppIntentConfiguration` whose two parameters list the spend categories
   from the snapshot (`EntityQuery`); defaults Groceries and Drogerie (if a default is missing in the data, the
   biggest category this month that is not Rent). Tap on a row opens that category in the app (`widgetURL` /
   `Link` with an `aresium://category/<name>` URL that the app handles; extend the app's existing URL handling
   without breaking file imports).
5. **No snapshot yet** (never logged in): a quiet "Open Aresium to load your data".
6. **Theme:** dark, light or red as chosen in the app (store the choice where the widget can read it).
7. **Previews/sample:** widget previews from a sample snapshot built from the bundled sample dashboard.
8. **Tests:** building the snapshot from `AresiumTests/server-dashboard.sample.json` (values copied exactly,
   missing categories as 0, current month = last month); the default-category rule; the deep-link URL round trip
   (`aresium://category/<name with spaces/ä>`); logging out deletes the snapshot.

## Settled: do not re-open

- Snapshot written by the app; the widget makes no network calls and holds no token.
- The line is the server's `dayExpenseRunning`; never sum days in the app or widget.
- Medium = line of this month; small = two configurable categories, defaults Groceries + Drogerie.

## Out of scope

- Lock-screen and large widgets, Control Center controls, live activities, TestFlight and signing.

## Done when

- `xcodebuild test` passes on your own simulator, the existing tests too.
- Screenshots of both widgets on your simulator's home screen in dark mode, with sample data:
  `build/05-medium.png`, `build/05-small.png`, and the empty state `build/05-empty.png`. If placing widgets on the
  simulator's home screen cannot be automated, render the widget views to images in a test instead and say so.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots, what is missing or
doubtful.
