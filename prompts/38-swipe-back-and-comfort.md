# 38: Swipe back on Aresium's dashboard; every screen's way out and the comfort gaps, for Patrik to choose

Status: running
Branch: `claude/38-swipe` · Worktree: `../empire-ios-38-swipe` · Built by: a Claude agent (flow and the feel)

## Goal

Patrik tested build 2 on his iPhone 17 (`docs/reviews/2026-10-30-aresium-phone-test.md`, "Second round", finding 9):
on the dashboard, Expenses → Groceries, a swipe to the right does not go back; only the header's arrow does. After this
brief the usual back swipe works on every dashboard screen that has a back arrow, and Patrik has a short list of the
other places in Aresium where the usual gesture or a common iPhone comfort is missing, to choose from.

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules: Apple's own controls and gestures where they exist; "Light mode")
- `Aresium/Aresium/Screens/DashboardScreens.swift` (`DashboardStack`: `.toolbar(.hidden, for: .navigationBar)` on the
  root and on every pushed screen), `Screens/Components.swift` (`ScreenHeader`, its `back`), `ContentView.swift`
  (`header(_:)`, `back(_:)`: the person's dashboard removes the last screen, the tour's goes through `tour.update`),
  `Screens/TourScreens.swift` and `Model/TourModel.swift` (the tour's own `DashboardStack` and how it moves it),
  `Screens/CategoryScreen` / `TransactionsScreen` (whatever reads horizontal drags there: the graph, page swipes).

## Build

1. **The cause:** the dashboard draws its own header and hides the system navigation bar on every screen, and
   `UINavigationController` turns off its interactive pop gesture whenever its bar is hidden. Arestemis, Aresus and
   Arestoteles hide the bar on their tab roots too, so make the fix reusable (`Shared/`), opt-in per navigation stack.
2. **A shared way to keep the system's back swipe on a stack whose screens hide the bar.** Requirements:
   - It is the system's own gesture (`interactivePopGestureRecognizer`, and on iOS 26 the content swipe
     `interactiveContentPopGestureRecognizer` if it is off for the same reason), with its own animation and its own
     interactive cancel, not a hand-made `DragGesture`.
   - Opt-in for one stack; no global override of `UINavigationController` (no `viewDidLoad` override in an extension),
     so system sheets, the share sheet and other stacks are untouched.
   - It begins only when there is a screen to go back to, and a screen can turn it off (a screen whose header shows no
     back arrow, or where leaving must wait).
   - Horizontal gestures inside a screen keep working: the start page's Expenses/Income page swipe (root, so no pop
     there), the graph's scrubbing, any horizontal scroll. If the content swipe takes them over, keep the content swipe
     off on that screen and the edge swipe on; say which you chose and why.
3. **Apply it to `DashboardStack`.** The rule: **the swipe does exactly what the header's back arrow does on that
   screen; where the header shows no arrow, no swipe.** For the person's dashboard the path shrinks as with the arrow
   (`place.path`, and whatever else the arrow resets, such as an open payment or the graph). For the tour, the swipe must
   end up in `tour.update` like the arrow does (or be off while the tour leads, if the tour cannot follow it: decide by
   reading `TourModel`, and say which). Nothing else about the header or the dashboard changes.
4. **Check it on the simulator** (your own: `claude-38`, commands in `AGENTS.md`), server mode's sample (`-sample`) and
   phone mode's (`-samplePhone`): Expenses → a category → a month, swipe back twice; a half swipe let go returns to the
   same screen; the graph still scrubs. If you find no way to drive a swipe on the simulator without installing anything
   and without editing `project.pbxproj`, unit-test the gesture's decision (begins / does not begin) and say so; Patrik
   checks on the phone. Save a screenshot mid-swipe if you can (`build/38-swipe.png`).
5. **The list for Patrik (do not build it): Aresium only** (another agent checks the other four apps). Write
   `docs/reviews/2026-10-30-swipe-and-comfort.md` with a section "Aresium":
   - **Ways out:** every screen and sheet a person can reach (server mode and phone mode: the dashboard and its
     screens, a payment's detail, Settings and its pages, the import flow, the file check, the bank guide, the category
     picker, the change sheet, receipts, cash, the tour, the app lock, the account screens from `Shared/`): how one
     leaves it, whether the usual gesture works (back swipe for a pushed screen, swipe down for a sheet), and if not,
     whether it should. A sheet that blocks swipe-down on purpose (unsaved text, a save under way) is right: say so in a
     word, do not list it as a gap. One table, the gaps first.
   - **Comfort:** the things an iPhone user expects and would miss here, found by using the app on the simulator and by
     reading the screens: for example a tap on the current tab or the status bar to scroll up, pull to refresh where the
     data comes from the server, swipe actions or a long press on rows where they would save a step, the keyboard's
     Return doing the next sensible thing, tap targets under 44 pt, a list that jumps or loses its place, a step that
     needs more taps than it should, a wait without a sign. Only what a person would notice; at most about 12, ranked by
     how often someone would hit it, each with the screen, what is wrong, the fix in one line, and the size (S/M/L).
     No new looks or features dressed up as comfort.

## Settled: do not re-open

- The header stays Aresium's own (no switch to the system navigation bar).
- The swipe mirrors the arrow; it never goes somewhere the arrow would not.

## Out of scope

- The category picker and its model (`CategoryPickerScreen`, `CategoryPickerModel`, `PhoneBackend`): brief 39 runs in
  parallel there (its scroll lag); leave those files alone.
- The other four apps' screens (the shared piece may be used there later, once Patrik chooses).
- Building anything from the list in item 5.

## Done when

- `xcodebuild test -scheme Aresium` passes on `claude-38`; the other apps still build (`Empire`, `Arestoteles`,
  `Arestemis`, `Aresus`) if you changed `Shared/`.
- The swipe works on the dashboard's screens as in item 4 (or its decision is unit-tested, with the reason).
- `docs/reviews/2026-10-30-swipe-and-comfort.md` has the Aresium section.

## Final message

Files changed, the exact build and test summary lines, how the swipe was checked, the screenshots' paths, the list's
gaps in short, what is missing or doubtful. Never commit, push or merge: Claude does.
