# 77: Search and a day's page: the screens

Status: running (a Claude agent, 2026-11-01)
Branch: `claude/77-search-day` · Worktree: `../empire-ios-77-search-day` · Built by: a Claude agent (the look and flow)
· Simulator: `claude-77`

## Goal

Patrik (2026-11-01, after build 9): "Search expenses and filter by day. The graph already allows to see day by day
expenses / income and months are clickable. Lets make days clickable too and lead to a screen with that days expenses
and income (in two tabs with swipe). For search: A small search icon. Im thinking search by names which uses own given
and also original names organized by best match."

Brief 76 gave the data: `NameSearch` (names ranked by best match, through own names and the bank's original lines),
`DashboardStore.day(_:)` (a day's rows and totals per side) and `dayDate(atChartIndex:scope:)`; and one shown name per
shop. This brief draws the search and the day's page, and adds both to the tour.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Languages", "Light mode", and in "Aresium phone mode": the header and the graph of brief
  56 (hold to read, a tap opens a month; a month's page with its dots), the name's page of briefs 44 and 55, the rows'
  tap, long press and swipe (`PaymentList`, `PaymentRow`), the tour of brief 59, and brief 76's API).
- `prompts/76-aresium-one-name-search-day-data.md` and Codex's final message (`codex-runs/76-names-search-day.md`).
- `Screens/DashboardScreens.swift` (`ScreenHeader`, `HeaderButtonLook`, `SeriesChart`'s `onPick`, `DashboardPages`,
  `MonthScreen`), `Screens/NameScreen.swift`, `Screens/PaymentList.swift`, `Model/TourModel.swift`,
  `Screens/TourScreens.swift`.

## Build

1. **A day's page.** On every day graph (the start screen's Current page and a month's page) a short tap on a day
   opens that day; holding and sliding still reads the graph as now. The page:
   - **A sheet**, not a pushed page: Patrik wants the two sides "in two tabs with swipe", and on a pushed page a swipe
     right is the back swipe (brief 56 gave the month's page dots only for that reason). In a sheet a sideways swipe
     turns the side and a swipe down closes it.
   - Its title is the day written out ("Mittwoch, 14. Oktober 2026" / "Wednesday, 14 October 2026"); the two sides
     Ausgaben / Einnahmen with the start screen's dots (the same look and words as `DashboardPages`), opening on the
     side of the graph that was tapped; a swipe or a dot turns it.
   - Each side: the day's total in the start screen's number style, then the day's rows as the month lists draw them
     (`PaymentRow`: tap opens the payment's page, long press, the swipe's All; no Add up), each saying its category
     (the category is not implied here as it is in a category's list). An empty side says so in one quiet line
     ("Keine Einnahmen an diesem Tag.").
   - After a row's page or change window closes, the day's page shows the store's new state (as the name's month page
     follows, brief 55).
2. **Search.** A small magnifying glass (`magnifyingglass`) in the start screen's header, in `HeaderButtonLook`, beside
   the import button (phone mode only; server rows have no names). A tap opens the search:
   - A pushed page on the dashboard's stack (the arrow and the back swipe work), its field at the top with the keyboard
     up at once, Apple's search field look in the app's ink ("Name suchen" / "Search names", or your words).
   - Results as the person types (`NameSearch`, best match first): each row the shown name, a quiet line with the count,
     the newest payment's date and its category, the money out and in in the list's colours, and when the match was on
     another name, that name in a second quiet line ("Bankname: MGP Vinted - Kleiderkreisel" or the own name). A tap
     opens the name's page (`DashboardRoute.name`), back returns to the search with the query kept.
   - Before typing: something useful and calm (for example the names of the newest payments, or one quiet line saying
     what can be searched); your choice, say why. No match: one quiet line.
3. **The tour** (brief 59; it explains everything): one new step for the search icon (in the order the screen is
   walked; the ring on the icon, a card in the tour's words; the tour's search runs on the tour's store), and the
   graph step's words say that a tap opens a day as well as a month where the graph shows days. `TourTests` follow
   (the count and each step's target; 19 steps, 18 without the graph).
4. **German** for every new text (`scripts/strings.py`), checked on screen.

## Settled: do not re-open

- The day's page is a sheet with swipeable sides; the month's page stays as it is.
- Search finds names (brief 76's ranking) and opens the name's page; it does not list single payments.
- Apple's controls where they fit (search field, menus); the app's ink, never system blue.

## Out of scope

- The data and ranking (brief 76), the engine, server mode's search.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=claude-77'
  -derivedDataPath build/DerivedData` passes, with tests for what the screens decide (which tap opens a day and on
  which side, the day page's words and empty side, the search icon only in phone mode, the result rows' lines, the
  tour's new step).
- `scripts/strings.py check`: 0 problems.
- Real touches (a temporary UI test, deleted after): a tap on a day point opens the day, a hold-and-slide still reads
  the graph and opens nothing, a sideways swipe in the day's page turns the side, the search field takes the keyboard
  and a result opens the name's page.
- Screenshots `build/77-*.png` in German and English, light and dark (red mode once): a day's page on both sides and
  an empty side; the search before typing, with results (one found through the bank's other name), with no match; the
  tour's new step. DEBUG launch arguments for these states as other briefs did, listed in `CLAUDE.md`.
- `CLAUDE.md` updated.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, your choices and why,
what is missing or doubtful. Never commit, push or merge: Claude does.
