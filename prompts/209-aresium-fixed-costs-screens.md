# 209: Monthly average and fixed costs: the screens

Status: draft (starts when brief 208 is merged)
Branch: `claude/209-fixed-costs-screens` · Worktree: `../empire-ios-209-fixed-costs-screens` · Built by: a Claude agent
(the look and the flow) · Simulator: `claude-209` (create it: iPhone 17, iOS 27.0)

## Goal

Patrik (2026-11-02, after build 18), on Claude's two ideas: "lets do monthly and fixcost screen feature first because
thats actually a great idea and wont take that long", and on the plan: "Good plan, lets go". The plan: under the
Overview's total a quiet line with the average of the finished months ("Ø €1,940 a month") and, next to it, what of that
is fixed ("€860 fixed"); a tap opens the fixed costs: the monthly total on top, each one with its amount, how often, the
last payment and the next one due (a yearly one counts as a twelfth a month); one that stopped (a cancelled
subscription) under Ended; one counted by mistake taken out with a long press ("Not fixed"); on the income side the
same for regular money in (salary, a monthly transfer from the parents). Brief 208 built the numbers; this brief puts
them on screen. (The amounts here are made up.)

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Monthly average and fixed costs — data API", brief 208; the start screen and Overview,
  `SideTotal` and `StartPage`; "All payments of this name": the name's page and `DashboardRoute.name`; the quick sort's
  card on Not sorted for a quiet list card; the undo bar; "Languages"; "Light mode"; the Empire's design restraint:
  no slogans, gold only as an accent, Aresium is ink only).
- `prompts/208-aresium-fixed-costs-data.md`, `Model/FixedCosts.swift`, `Model/MonthlyAverage.swift`,
  `Screens/DashboardScreens.swift` (`SideTotal`, `StartPage`, `DashboardRoute`, `DashboardStack`),
  `Screens/NameScreen.swift`, `Screens/QuickSortScreens.swift` (`QuickSortListCard`).

## Build

1. **The Overview's line** (both sides, phone and server mode for the average; the fixed part only where
   `fixedCosts(side:)` has a running entry): under the total, one quiet line in the total's column, e.g. "Ø €1,940 a
   month · €860 fixed" / "Ø 1.940 € im Monat · davon 860 € fix" (income: "… · €1,300 regular" / "… · davon 1.300 €
   regelmäßig"); words, order and look are your call, short enough for German on an iPhone 17 without wrapping (or a
   deliberate second line). The fixed part opens the fixed costs (a tap target of 44 pt, VoiceOver a button). Nothing on
   Current's page (it is one month), nothing while the average is nil. The average must read as "per finished month":
   say it once where it fits (the page's top line, or VoiceOver), not with a footnote on the start screen.
2. **The fixed costs page** (a new `DashboardRoute`, pushed on the dashboard's stack like a name's page: the header with
   its arrow and gear, the back swipe): title "Fixed costs" / "Fixkosten" (income: "Regular income" / "Regelmäßige
   Einnahmen"); the monthly total as the page's big number with what it makes a year in a quiet line; then the running
   entries as rows in the lists' look: the category's tile, the name, a quiet line with how often and the next day due
   ("monthly · next 3 Dec" / "monatlich · nächste am 3. Dez.", brief 208's words), the amount on the right as a payment
   shows it; for one that is not monthly also its share a month in the quiet line ("yearly · next 3 May · €41.58 a
   month"). Then **Ended** / **Beendet** (muted, "last 3 Aug" / "zuletzt am 3. Aug."), then **Not counted** / **Nicht
   gezählt** (what the person took out). One quiet line says how they are found (about the same amount, at the same
   interval, monthly to yearly), once, at the top or the end. Empty: one calm line saying none were found yet and when
   one is (three payments at the same interval, a yearly one twice).
3. **Rows:** a tap opens the name's page (`DashboardRoute.name` for the entry's `newest` row, as "All with this name"
   does); a long press has **Not fixed** / **Nicht fix** (income: **Not regular** / **Nicht regelmäßig**) on running and
   ended rows, and **Count again** / **Wieder zählen** on taken-out rows (`setNotFixed`); then the undo bar with Undo
   (the `BatchUndo`), the total and the line on the Overview following.
4. **German** for every text (`scripts/strings.py`), light, dark and red mode, Reduce Motion, VoiceOver (each row read
   as one: name, amount, how often, next due; the total with "a month").
5. **The tour:** no change (brief 139 is moving the tour's pieces into `Shared/` right now; do not touch
   `TourModel.swift` or `TourScreens.swift`).
6. **DEBUG:** a made-up sample with fixed costs (`-samplePhone` plus a flag of yours, e.g. `-sampleFixedCosts`: a rent,
   a phone contract, two streaming subscriptions at one shop, a yearly insurance, a quarterly fee, a gym cancelled four
   months ago, a salary and a monthly transfer in; names like "Hausverwaltung Fiktiv", "Fiktiv Mobilfunk",
   "StreamFiktiv"), and launch arguments that open the page on either side and take one out, for screenshots.

## Settled: do not re-open

- Brief 208's detection and numbers (no second detection on screen; the screens read the API).
- Only the person's "Not fixed" as a correction; adding one by hand is not part of this brief.
- The Overview only; Current stays as it is.

## Out of scope

- The data (brief 208), the engine, the tour, the widget.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=claude-209'
  -derivedDataPath build/DerivedData` passes (tests for the new pure words and lines in both languages, the route).
- `python3 scripts/strings.py check`: 0 problems.
- **Real touches** (a temporary UI test in `Aresus/AresusUITests` driving Aresium, deleted after; 3 of 3 runs): the
  Overview's line on the expense side opens the fixed costs; the rows, Ended and the total as the sample says; a long
  press → Not fixed moves it to Not counted and the total falls; Undo brings it back; a row opens the name's page and
  back returns; the income side's line opens Regular income.
- Screenshots `build/209-*.png` in German and English, light and dark (red once): the Overview with the line on both
  sides, the fixed costs page, Regular income, the long press, the empty page.
- `CLAUDE.md` updated (a "Monthly average and fixed costs on screen" part after brief 208's).

## Final message

As in `AGENTS.md`: files changed, the exact test summary (count the "' passed on" and "' failed on" lines), the choices
you made and why, anything doubtful. Never commit, push or merge: Claude does.
