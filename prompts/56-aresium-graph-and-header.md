# 56: Read the graph by sliding over it, the graph moves away while scrolling, the header's buttons without boxes

Status: draft
Branch: `claude/56-graph-header` · Worktree: `../empire-ios-56-graph-header` · Built by: a Claude agent (the look and
the feel) · Simulator: `claude-56`

## Goal

Patrik's fifth round (2026-10-31, build 5 on his iPhone; `docs/reviews/2026-10-30-aresium-phone-test.md` → "Fifth
round", items 5, 6 and 7), in his words:

- "Can we add that with slowly sliding over the graph it shows each month's number and clicking on a month opens it?
  It's done like that on the web version. Not sure if click to open works on the phone, we don't have to do it."
- "When scrolling up in the categories under the graph, the graph should move up so categories get more space
  basically. This can be deactivated in settings via toggle."
- "I would also make the settings and import button onto one level and remove their block outline, just have them on
  the background unless you disagree." Claude agrees, and the other header buttons follow, so every header looks alike.

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules; "Languages"; "Light mode"; "Settings"; the "Aresium phone mode" entry, in
  particular "Comfort on the dashboard", "Adding up names in a category's list" (the icon), "The back swipe's
  distance", the tour)
- `~/ares-empire/EMPIRE.md` → design language; memory of the owner's taste: gold only as an accent, classy, no
  decoration for its own sake.
- The website's graph, which Patrik means: `~/aresium/web/public/app/chart.jsx` (the hover guide line, the dot on the
  line, the chip with the month and the amount, `clickable` hit areas) and `app.jsx` (`onIndexClick`: Overview's
  graph opens that month's screen, a category's graph that category's month; the day graphs only show, they open
  nothing).
- `Aresium/Aresium/Screens/Components.swift` (`SeriesChart` with `onPick`, `ScreenHeader`, `IconButton`),
  `Screens/DashboardScreens.swift` (`StartScreen`: the range picker and `ImportButton` row, the fixed graph, the page
  dots, the `TabView` of the two pages, each a `WordmarkScrollView`; `DashboardRoute`, `DashboardStack`; the category
  page's graph and months; `DashboardSettingsSection`), `Screens/ImportControls.swift` (`ImportButton`, its menu and
  busy state), `Screens/SummedRows.swift` (`SumCategoryButton`), `Model/GraphSetting.swift`,
  `Model/DashboardStore.swift` (`showReview(month:)`, `currentMonth`, `rows(side:current:)`, `startChart`),
  `Shared/Design/BackSwipe.swift`, `Model/TourModel.swift` and `Screens/TourScreens.swift` (anchors: `.importButton`,
  `.settings`, `.graph`, `.range`, `.pageDots`).

## Build

1. **Sliding over a graph** (every `SeriesChart`: the start screen's day and month graphs, a category's months, a
   name's months): while a finger slides slowly over the plot, a guide line and a dot follow the nearest point and a
   small chip shows its label and amount (the month or day, `Money.precise` or as you see fit), as the website's
   tooltip; letting go hides it. It must not take the page's own gestures: a vertical scroll that starts on the graph
   (the category and name pages scroll with their graph), the back swipe from the edge and from the middle, and a short
   tap all keep working. Choose how a slide is told apart (Apple's Stocks and Health hold briefly, then follow the
   finger; a slow horizontal move may be enough where nothing else scrolls sideways) and check it with real touches.
   A haptic tick per point is your call. VoiceOver: the graph's points are already read out; keep that.
2. **A tap on a month opens it** (as the website): a category's graph opens that month's payments (as today's
   `onPick`), a name's graph opens the name's month (brief 55, in parallel, makes that page; keep `onPick` as the hook
   and call it), **Overview's graph opens that month's page**, new: pushed on the dashboard's stack, the back arrow and
   the back swipe return to Overview; it shows that month as Current shows this month (its days' graph, the range line
   with the month, Expenses and Income with the dots, its categories; a category opens that month's payments), built
   from the start screen's pieces, not a copy of them (a route for a month; `DashboardStore` serving rows, totals and
   the chart for a given month; `showReview(month:)` already focuses a month for the review notification: share what
   fits). The day graphs open nothing.
3. **The graph moves away while scrolling the start screen's categories:** scrolling the categories up moves the graph
   (and what belongs to it) up out of the way, so the categories fill the screen; scrolling back to the top brings it
   back. The range picker, the header and the page dots: your design (they may go with the graph or stay; the
   Expenses/Income dots must stay reachable or come back with a small scroll). Both pages (Expenses and Income) and
   Current and Overview; switching pages while the graph is away must not jump. No jank: measure that a scroll keeps
   the frame rate (Instruments or a signpost run; no work per frame beyond the offset). Reduce Motion: fine as a plain
   scroll. A switch in Settings → Dashboard under Graph, on by default, says what it does (e.g. "Graph moves away when
   scrolling", German yours, one line beside the switch); off, the graph stays where it is today. Kept like the Graph
   setting (`aresium.*` defaults); not in the export.
4. **The header's buttons without boxes.** The start screen: the gear and the import button side by side on the title
   row (Hermes' bust left, "Aresium" in the middle), the range picker on its own row below. Every header button (the
   back arrow, the gear, the import button, red mode's X, the category's add-up icon) drawn on the wall without the card
   and its outline, at a size that reads, with the 44 pt tap area kept (`minimumTapArea`). The add-up icon's on and off
   must stay clearly different in light, dark and red mode without its filled box (e.g. a filled symbol in full ink
   for on, the outline symbol in muted ink for off); VoiceOver unchanged. The import button keeps its menu and its busy
   state. The tour's anchors (`.importButton`, `.settings`) still ring the buttons; check the tour's import and lock
   steps.
5. **German** for every new text (`scripts/strings.py`).

## Settled: do not re-open

- All header buttons lose their boxes, not only the start screen's.
- The day graphs only show their numbers; months open.
- The graph's moving away is on by default, with a switch to turn it off.

## Out of scope

- The name's page's months and the day tile (brief 55, a Claude agent, in parallel: it adds a route for a name's month
  and changes `NameScreen.swift`; avoid restyling its rows).
- Adding up's choices (`Model/PaymentSums.swift`: Claude fixes the icon's logic in parallel, fix 58; you change only
  how `SumCategoryButton` looks).
- The tour's steps and texts (brief 59 comes after; only keep the tour working).

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=claude-56'
  -derivedDataPath build/DerivedData` passes, with tests for the chip's text and the nearest point (a model, not the
  view), the month page's rows, totals and chart, the new setting (default, kept), and the route.
- `scripts/strings.py check`: 0 problems.
- A real-touch check (a temporary UI test, deleted afterwards, as brief 47 did): sliding over the start graph shows the
  chip and changes its month; a vertical drag starting on a category page's graph scrolls and shows no chip; the back
  swipe from the edge and from the middle of a category's page still goes back; a tap on Overview's graph opens the
  month; scrolling the start screen's categories moves the graph away and back.
- Screenshots `build/56-*.png`, German and English, light and dark, one in red mode: the start screen at rest (the new
  header), with the chip on the day graph and on Overview's month graph, halfway and fully scrolled with the graph away,
  the month page, a category's page header with the add-up icon on and off, Settings → Dashboard with the new switch,
  the tour's import step, the largest text size for the header.
- `CLAUDE.md` updated (Aresium's dashboard parts; the setting next to the Graph's).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, your choices (how a
slide is told apart, what moves with the graph, the icon's on and off, the setting's words), what is missing or
doubtful. Never commit, push or merge: Claude does.
