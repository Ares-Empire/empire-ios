# 57: Aresium's Settings without lag: measure, then take the work off the main thread

Status: merged 2026-10-31 (all Aresium tests pass; Claude dropped the lazy shared Settings change: little gain, all five apps; the app's own work per step ≤ 1.4 ms at 1,250 payments, the rest is iOS drawing the sheet)
Branch: `codex/57-settings-smooth` · Worktree: `../empire-ios-57-settings-smooth` · Model: `gpt-6.1-sol`, effort `high`
· Simulator: `codex-57` · No look changes.

## Goal

Patrik (2026-10-31, build 5 on his iPhone 17, his own data: about 1,250 payments, 9 months): "At times settings felt
laggy, could be my phone or me but check please." Find what makes Aresium's Settings sheet stutter (opening it,
scrolling it, flipping its switches, opening and closing its pages, closing it) and fix the causes, with numbers before
and after. The same standard as brief 39 (the category picker: a settled burst held the main thread 404 ms at 5,000
payments, then 0.2 ms; `CLAUDE.md` → "Off the main thread").

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Settings", the "Aresium phone mode" entry, especially "Off the main thread", the ledger's
  own executor `PhoneLedgerExecutor`, `PickerTiming` signposts and `PickerTimingTests`, "Local messages", "The lock")
- `Shared/Design/SettingsScreen.swift` (the sheet every app shares), `Aresium/Aresium/ContentView.swift` (the
  `.sheet(isPresented: $showsSettings)` and what the dashboard under it observes), `Screens/PhoneScreens.swift`
  (`PhoneSettingsSection`, `OwnNamesSetting`, `PhoneDataModel`), `Screens/MessagesSettings.swift` and
  `Model/AresiumMessages.swift` (`refresh`, authorization), `Screens/LockSettings.swift` and `Model/AppLock.swift`
  (Keychain, `LAContext`), `Screens/DashboardScreens.swift` (`DashboardSettingsSection`: Graph, Add up same names),
  `Model/PaymentSums.swift`, `Model/DashboardStore.swift`, `Model/GraphSetting.swift`, `Shared/Settings/Appearance.swift`.

## Build

1. **Measure first, on the simulator with a store the size of Patrik's and five times it** (1,250 and 5,000 made-up
   payments over a year; add a DEBUG launch argument that fills the phone sample's store to a given size, e.g.
   `-sampleSize 5000`, if none exists; made-up names and amounts only). For each step: open Settings, scroll to the end
   and back, open and close each page (Categories, Receipts, Messages, Own code, Language, Appearance, Fonts &
   licences), flip each switch (Own names, Messages and its switches, Face ID if the simulator offers it, Graph, Add up
   same names), close Settings. Record the main thread's longest stall per step (Instruments' Time Profiler or
   Hangs/Animation Hitches with `xcrun xctrace`, or `os_signpost` spans like `PickerTiming`, or both). Write the table
   into your final message.
2. **Fix every cause that holds the main thread over one frame (16 ms) at 1,250 payments, and say what is left at
   5,000.** Likely places to look (check, don't assume): a section's `body` doing store, Keychain, `LAContext`,
   notification-center or file work; the dashboard behind the sheet rebuilding or re-rendering on every change made in
   Settings (Own names rebuilds the dashboard; Graph and Add up change what it draws); `PhoneDataModel` or
   `PhoneBackend.summary` counted on the main thread; `AresiumMessages.refresh()` on appear; observation that makes the
   whole sheet re-evaluate for a change one row shows. Work moves to the existing workers (the ledger's executor,
   `MessageScheduler`) or is cached and updated only when it changes; nothing new on the main actor that can block.
3. **Same behaviour:** every switch still does what it did, at once where it did (the dashboard under the sheet still
   follows Graph and Add up); the existing tests stay green; add tests for anything you move (a value now computed off
   the main thread arrives and is right; a cached value updates after its change).
4. `Shared/Design/SettingsScreen.swift` is every app's: change it only where the cause is there, keep every app
   compiling (build Empire, Arestemis, Aresus and Arestoteles too), and say what changed for the other apps.

## Settled: do not re-open

- No change to how Settings looks or what it offers.
- Measurements on the iOS 27.0 simulator are the evidence (no device here); report them as such.

## Out of scope

- The dashboard's own screens (briefs 55 and 56, Claude agents, run in parallel and change `DashboardScreens.swift`'s
  start screen, the header, `NameScreen.swift` and `SeriesChart`; keep your edits there to what the lag needs, and list
  them).
- `Model/PaymentSums.swift`'s choices (Claude fixes the category icon there in parallel, fix 58).
- `project.pbxproj`.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=codex-57'
  -derivedDataPath build/DerivedData` passes; the four other apps build.
- The before/after table (every step above, 1,250 and 5,000 payments, longest main-thread stall), the tool you used,
  and the traces' paths under `build/57-*`.
- `CLAUDE.md` gets a short note under "Off the main thread" (what Settings does off the main thread now, how to measure).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the table, each cause found and its fix, what
is still over a frame and why, what is doubtful. Never commit, push or merge: Claude does.
