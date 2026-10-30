# 39: The category picker scrolls smoothly, also right after ticking

Status: merged 2026-10-30 (Aresium 372 tests + 2 opt-in timing; main-thread time after a burst of ticks 404 → 0.2 ms at 5,000 payments, 86 → 0.1 ms at 1,000)
Branch: `codex/39-picker-scroll` · Worktree: `../empire-ios-39-picker-scroll` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Patrik tested build 2 on his iPhone 17 (120 Hz: a frame is 8.3 ms; `docs/reviews/2026-10-30-aresium-phone-test.md`,
"Second round", finding 8): scrolling the category picker is sometimes jerky, most of all after ticking some. After
this brief nothing that runs after a tap or after the taps settle blocks the main thread long enough to drop frames
while the person scrolls, and the numbers prove it. **Measure first:** if a suspect below turns out cheap, leave it.

## Read first

- `AGENTS.md`, `CLAUDE.md` (the "Aresium phone mode" entry: the picker, its numbers, `CategoryPickerModel.settle`)
- `Aresium/Aresium/Model/PhoneSettingsModels.swift` (`CategoryPickerModel`: `toggle`, `selectionChanged`,
  `flushPending`, `work`), `Model/PhoneBackend.swift` (`@MainActor`; `sort`, `choose`, `refresh`, `categories`,
  `categoryCounts`, `dashboard(auth:)`), `Model/PhoneLedger.swift` (an actor: `sortingSnapshot`, `payments`,
  `summary`), `Model/AresiumEngine.swift` (an actor), `Model/PhoneCategories.swift` (`PhoneCategoryList`: what
  `groups` costs per access), `Screens/PhoneScreens.swift` (`CategoryPickerScreen`: a plain `VStack` in a `ScrollView`,
  `model.groups`, `showsCounts`, `row`), the `DashboardStore` (what `changed()` rebuilds and re-renders) and where
  the picker is shown (Settings → Categories, after an import, the tour's Settings): which views stay alive under it.
- Timing data: `AresiumTests` resources `timing-source-5000.json`, `timing-vr-5000.csv` (see `EngineTests`).

## Build

1. **Measure where the main thread goes**, with phone mode's sample (`-samplePhone`) and with 1,000 and 5,000
   payments in the store: (a) one tap (tick and untick), (b) the settled flush (`sort` → `refresh` → `loadCounts` →
   `changed()` and whatever re-renders after it), (c) closing the picker (Done / Back). Use `os_signpost` intervals
   (subsystem `de.ares-empire.aresium`, category `picker`) around each step, and Instruments on your simulator
   (`xcrun xctrace record --template 'Time Profiler'` or `'Animation Hitches'`, part of Xcode) or a timing test that
   records how long the main actor is busy per step. Report a table: step, on the main thread or not, ms at each size.
   The simulator runs on a fast Mac: treat anything over about 4 ms on the main thread there as over budget.
2. **Suspects from reading the code** (confirm or clear each with the numbers):
   - `PhoneBackend` is `@MainActor`, so its own work runs on the main thread: `dashboard(auth:)` builds the engine's
     input from every payment there (`PhoneDashboard.input`), `categoryCounts` and `sort` build lists there; only the
     engine and the ledger are off it.
   - `changed()` rebuilds the dashboard after every settled burst while the picker is open; the dashboard is not
     visible then, but the views under the picker re-render on the main thread.
   - Each tap sets `list` twice (the optimistic tick, then `phone.categories()`), `refresh()` sets `summary`, and
     `counts` is replaced: Observation notifies on every set, even of an equal value, so every row of the non-lazy
     list and every view reading `summary` re-renders.
   - `groups` / `showsCounts` may be computed on each access from the catalog (localised names, looks).
3. **Fix what is over budget.** Rules: pure work moves off the main actor (a `nonisolated` function, the ledger actor,
   or the engine actor), not behind a `Task.detached` that copies the same work; a value is set only when it changed;
   the dashboard is brought up to date before it is seen again (the picker's Done/Back flush keeps its promise:
   whatever opens next shows sorted payments, the result line counted again, the fresh dashboard); a `LazyVStack` only
   if the numbers show the rows' layout matters (`-scrollToCategory` must still work). The results must not change:
   the same dashboard, the same counts, the same sort.
4. **Tests** (made-up data): the existing picker tests keep passing (`PhonePickerBatchTests`, `CategoryCountsTests`,
   `ImportThenCategoriesTests`, `PhoneBackendTests`); new ones for what you change (for example: a burst of taps does
   not rebuild the dashboard until the flush that closes the picker, if you choose that; an equal value is not set
   again; the dashboard built off the main actor equals the one built before).
5. **Measure again** with the same steps and sizes and report the table before and after.

## Settled: do not re-open

- No change to the look of the picker or the dashboard; the rows stay tappable during work (brief 35).
- No store schema change, no engine change.
- The half-second settle stays (`CategoryPickerModel.settle`).

## Out of scope

- `Screens/DashboardScreens.swift`, `ContentView.swift`'s header and navigation, `Shared/` navigation: brief 38 runs in
  parallel there (the back swipe). If a fix needs a change in them, describe it in your final message instead.
- Server mode.

## Done when

- `xcodebuild test -scheme Aresium` passes on your own simulator (`codex-39`, commands in `AGENTS.md`), with the new
  tests.
- The before/after table is in your final message, with how each number was measured.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the before/after table, which suspects were
real and which were not, what is missing or doubtful.
