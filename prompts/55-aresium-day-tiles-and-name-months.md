# 55: A day's tile reads as a date; the name's page opens its months as pages

Status: draft
Branch: `claude/55-name-months` · Worktree: `../empire-ios-55-name-months` · Built by: a Claude agent (the look and the
feel) · Simulator: `claude-55`

## Goal

Patrik's fifth round (2026-10-31, build 5 on his iPhone; `docs/reviews/2026-10-30-aresium-phone-test.md` → "Fifth
round", items 1 and 2):

1. "Currently summed up says 44× and normal is 44, which looks slightly confusing next to each other. I'd say we make
   it '44.' to show it's a date." A payment's day tile shows "4"; brief 53's summed row shows "3×" in the same tile.
2. "In the 'Alle' screen of expenses the expenses per month are just listed below. That's very weird. Let's make each
   month just as the other months so that you click on it and it opens the screen with the expenses in that month.
   Swipe to get back." Today the name's page (`Screens/NameScreen.swift`) shows its months as bars ending in
   `chevron.down`; a tap scrolls down to that month's payments, which follow below all the months.

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules; "Languages"; "Light mode"; the "Aresium phone mode" entry: "Renaming and the
  name's page", "Adding up names in a category's list", "The back swipe's distance")
- `Aresium/Aresium/Screens/NameScreen.swift`, `Model/PaymentNames.swift` (`PaymentNameGroup`, its `months`), the
  `NamePage` model, `Screens/DashboardScreens.swift` (`DashboardRoute`, `DashboardStack`, `TransactionsScreen`: a
  category's month list, which the new page should look and behave like), `Screens/PaymentList.swift` (`PaymentRow`,
  `PaymentRowLabel`), `Screens/Components.swift` (`DayTile`, `ValueRow`), `Screens/SummedRows.swift` (`StackTile`),
  `Screens/CashScreens.swift` and `Screens/ReceiptCheckView.swift` (their day tiles), `Model/ReceiptPage.swift`
  (`ReceiptPageWording.dayNumber`).

## Build

1. **The day's number** in every day tile that shows a date (a payment row, the Cash page's movements, the receipt
   check's payments, the file check's payments, and any other you find): written as the app's language writes a day
   alone: German "4." (Patrik's ask), English "4" (English puts no dot after a day; the summed tile stays apart by its
   stack and its ×). One function for all of them (a model function with `language: AppLanguage = .current`, tested in
   both languages), not a format per screen. Check that "31." fits the tile at every text size (brief 53 made the day
   shrink inside its tile at the largest sizes, never "…").
2. **The name's page, months as pages.** Under the totals, the add-up switch and the graph: the months as rows exactly
   like a category's months (`ValueRow` with the chevron to the right, newest or oldest first as a category's page
   orders them), each opening a page pushed on the dashboard's stack: that name's payments in that month. The payments
   no longer follow below the months. The new page:
   - its header: the name as title, the month as the line under it (as a category's month list: "Okt. 2026 ·
     Buchungen"-style; your words), the back arrow; the back swipe works as everywhere (Apple's own rule, measured in
     brief 47; do not change `BackSwipe`);
   - its rows: `PaymentRow` as on a category's month list (tap opens the payment's page, long press, the row swipe with
     **All**; the rows of a name's page add no Add up, since every row is the same name);
   - a payment renamed or moved from there: the page follows as the name's page does today (`PaymentNameRoute.following`)
     or, when the month has no payments of the name left, goes back one page;
   - an empty month (no payments of the name in it) has no row on the name's page, as today's months list.
   The graph's tap on a month (`SeriesChart.onPick`) opens the same page (brief 56 adds sliding over the graph to read
   the numbers in parallel; keep `onPick` as the one hook). A new route case or field on `DashboardRoute` (a name plus
   a month), handled in `DashboardStack` like the others; the tour never reaches it but must still compile and behave.
3. **German** for every new text (`scripts/strings.py`); the month line and the accessibility hint ("Shows this month's
   payments below" goes).

## Settled: do not re-open

- German writes "4.", English "4".
- The name's page keeps its totals, its add-up switch and its graph; only the months open pages now.
- No new setting.

## Out of scope

- The start screen, the graph's look and its new sliding (brief 56, a Claude agent, in parallel: it changes
  `SeriesChart`, the header's buttons and the start screen; avoid restyling them).
- Adding up's choices (`Model/PaymentSums.swift`: Claude fixes the category icon in parallel, fix 58).
- The tour's steps (brief 59 comes after).

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=claude-55'
  -derivedDataPath build/DerivedData` passes, with tests for the day's number (both languages, 1 to 31), the name's
  months and the new page's rows (a name over three months, a month with a refund, a month without the name), the route,
  and the page following a rename.
- `scripts/strings.py check`: 0 problems.
- Screenshots `build/55-*.png`, German and English, light and dark (one in red mode): a category's list with single
  rows and a summed row (the tiles side by side), the Cash page's tiles, the name's page with its months, the new page,
  the largest text size for the tile with "31." and for the new page. Sample: `-samplePhone -sampleLongName` (three
  payments of one name in Clothes this month), `-openName <text>` opens a name's page; add a DEBUG argument that opens
  the new page (e.g. `-openNameMonth <YYYY-MM>`). The rows of the REWE name's page in the sample span several months.
- A real-touch check (a temporary UI test, deleted afterwards, as brief 47 did): the new page's back swipe from the edge
  and from the middle goes back; a row's swipe still opens All.
- `CLAUDE.md` updated (the "Renaming and the name's page" part of "Aresium phone mode").

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, your choices (words,
the order of the months, the new page's header), what is missing or doubtful. Never commit, push or merge: Claude does.
