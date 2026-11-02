# 215: Aresium's first run, fixed before testers come

Status: merged 2026-11-02 (893 Aresium tests; the name search timing test failed under load and now takes the best of three rounds, 8 of 8 alone; real touches 6 of 6; Empire, Arestemis and Arestoteles build with the Settings change)
Branch: `claude/215-first-run-fixes` · Worktree: `../empire-ios-215-first-run-fixes` · Built by: a Claude agent (the
look and the flow) · Simulator: `claude-215` (create it: iPhone 17, iOS 27.0)

(Numbers 210–214 were taken by another session's briefs; this is Aresium's next.)

## Goal

Aresium goes to external TestFlight testers (friends with their own German banks) as soon as Apple's beta review
passes (build 18 submitted 2026-11-02). A Claude agent walked a fresh install as a newcomer would
(`docs/reviews/2026-11-02-aresium-first-run.md`, brief 207): the reviewer gets through, and a friend could use it "after
three small fixes". This brief makes those fixes and the cheap polish next to them, so build 19 is the one testers get.
The tour's findings (4, 8, 9, 13) wait: another session is moving the tour's code into `Shared/` (brief 139). The bank
guide's content (finding 6, missing banks) is a later brief.

## Read first

- `AGENTS.md`, `CLAUDE.md` (the first screen, imports and the category picker after an import, Current and Overview,
  the review month, the quick sort's offer and card, Aresium's messages' offer, Settings and the Ares account section,
  the Cash page, "Languages", "Light mode", the design restraint).
- `docs/reviews/2026-11-02-aresium-first-run.md`: every finding named below, with where it is and what happens.

## Build (the review's numbers)

1. **Done with nothing ticked** (finding 1, "blocks a tester"). Today a newcomer who taps Done on the category list
   after the first import ends with every payment Not sorted, and the quick sort offers only Own transfers and New
   category. Make the first run land somewhere useful:
   - Done with nothing ticked asks once (Apple's alert, in the app's words): use the categories the payments fit into
     (the list already counts each default's payments; tick those with a count), with the number, and that they can be
     changed any time in Settings → Categories; or not now.
   - While no category is chosen and payments exist, the dashboard says so in one quiet card that opens the category
     list (in the quick sort card's look), and the quick sort's offer and card wait until something is chosen (they
     cannot help before).
2. **The first look after an import early in a month** (finding 2). On the 1st–7th, Current shows a month of a day or
   two ("Rent" and a two-point graph after "74 new"). In the first days of a month let Current show last month, so the
   first look is a full month, and keep this month one tap away; look at the existing review month (`reviewMonth`,
   Aresium's messages) first and reuse it rather than adding a second rule. Say which month is shown where it is not
   obvious. This changes the start screen for everyone in those days, Patrik too: keep it calm and predictable (no
   jump while the app is open, the same rule every time).
3. **German "Entfernen" on the import result** (finding 3): the button only closes the notice; give it a key of its own
   with "Schließen" (English stays "Dismiss" or "Close", your call). Arestemis's "Dismiss" keeps "Entfernen".
4. **Settings → Ares account for testers** (finding 5): show the "Ares account" section only while an Ares login exists
   on the iPhone (Patrik is signed in through his other Ares apps); nobody else sees a sign-in they cannot use. Drop
   "One Ares account for all Ares apps" from Aresium's Sign in sheet (it went from the logins on 2026-10-31). Shared
   code is involved (`Shared/Design/SettingsScreen.swift`, `SignInSheet.swift`): change it only through Aresium's own
   settings (`SettingsApp`, `EmpireAppIdentity`), and check the other apps' Settings look as before.
5. **"activities"** (finding 7): English month lists say "Oct 2026 · activities" and "No activity"; say "payments",
   as everywhere else.
6. **The import icon** (finding 10): the header's `tray.and.arrow.up` reads as share/export; use the downward tray as
   the drop overlay does.
7. **Three cards after the first import** (finding 11): the reminders' offer ("Remind you to import new statements?")
   waits for a later launch (or the second import), so the first minute asks two things at most.
8. **Overview's graph at the running month** (finding 12): the line falls at the unfinished month and reads as "spent
   less". Draw the running month so it reads as unfinished (a dashed last stretch, or a lighter point), in light, dark
   and red mode, without a legend.
9. **The Cash row's "not accounted for"** (finding 14): with withdrawals and no receipts it reads like a warning. Say
   what it is in plain words (e.g. cash without receipts), in both languages.

## Settled: do not re-open

- No tour changes (brief 139 is moving `TourModel.swift` and `TourScreens.swift` into `Shared/`; do not touch them, nor
  `TourData.swift`).
- No change to sorting, counting or the engine.
- Another Claude agent is building brief 209 at the same time (the monthly average and fixed costs: a line under the
  Overview's total and a new page). Do not touch `SideTotal`'s line or the fixed costs files; expect the String Catalog
  to merge, and keep your catalog edits to your own keys.

## Out of scope

- The tour, the bank guide's content and its missing banks, the widget, Arestemis and the other apps (beyond keeping
  their Settings unchanged).

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=claude-215'
  -derivedDataPath build/DerivedData` passes (tests for the new rules: Done with nothing ticked, the dashboard's card
  and the quick sort waiting, which month Current shows on the 1st–7th and after, the reminders' offer's moment, the
  Ares account section's condition, the words in both languages).
- `python3 scripts/strings.py check`: 0 problems.
- **Real touches** (a temporary UI test in `Aresus/AresusUITests` driving Aresium, deleted after; 3 of 3): a fresh
  install, a made-up bank file imported (the engine's fixtures in `Aresium/AresiumTests/Engine/`, put into the
  simulator's Files app), Done with nothing ticked → the question → Use → payments sorted and the quick sort for what is
  left; again with Not now → the dashboard's card opens the category list; the result card's Schließen in German;
  Settings without a login shows no Ares account section.
- Screenshots `build/215-*.png` (German and English, light and dark) of each change.
- `CLAUDE.md` updated where these behaviours are described; the review file gets one line per finding saying what was
  done ("Fixed in build 19 (brief 215): …").

## Final message

As in `AGENTS.md`: files changed, the exact test summary (count the "' passed on" and "' failed on" lines; reruns
alone of the known flaky tests), the real touches, the choices you made and why, anything doubtful. Never commit,
push or merge: Claude does.
