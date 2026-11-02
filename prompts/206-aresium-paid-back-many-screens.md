# 206: Money paid back for several payments at once: the screens

Status: running
Branch: `claude/206-paid-back-many` · Worktree: `../empire-ios-206-paid-back-many` · Built by: a Claude agent (the look
and the flow) · Simulator: `claude-206` (create it: iPhone 17, iOS 27.0)

## Goal

Patrik (2026-11-02, on build 17): "I love it the connecting is great! Let's add that for multiple payments at once. So
if I select many statements I can then select income that payed them back and it just goes expense by expense until
it's empty. Then let's also add the other direction that it's possible to do it from income to expenses if you know
what I mean. It was great that it worked that I can't over use income, good catch."

Brief 205 gives the data: a group of payments on one side, one or more picked on the other, the euros poured expense by
expense in date order, one undo. This brief puts it on screen in the two places it starts: **a selection** (briefs 82,
200) and **one payment's page** (brief 203), with one window for both.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Money paid back", briefs 201–203; "Several payments at once on screen", brief 82, and
  brief 200's motion and slide; the undo bar; the Empire's design restraint).
- `prompts/205-aresium-paid-back-many-data.md` (the API) and brief 203's prompt.
- `Screens/SelectionScreens.swift` (`SelectionBar`, `SelectionBarState`, `BottomBar`/`BarItem`), `Screens/PaybackScreens.swift`
  (`PaybackSheet`, `PaybackSection`), `Model/PaybackPage.swift`, `Screens/DashboardScreens.swift` (where selecting
  ends after an action), `Model/TourModel.swift`.

## Build

1. **The selection's bar** gets a third item for linking: on an expense list it picks the payments that paid them
   back, on an income list the expenses they pay back (words, symbol and placement your call; short enough for three
   items in German; the `link` symbol fits brief 203). Off (muted) while `paybackGroup` is nil for the selection, as
   the bar's other items are off; it says nothing about rows left out until the window opens.
2. **One window for both starts** (brief 203's `PaybackSheet`, grown, not a copy): the group at the top (one payment as
   today; several as "3 expenses · €240.00" with what was left out in one quiet line, for example "1 receipt left out"),
   the question, the search, the suggestions, and now **several can be ticked** on the other side (rows with the
   selection's circle, ticked in its look). While anything is ticked, a summary shows how the money goes, in brief
   205's order: each expense with what it gets back, and what stays open or stays income, in brief 205's words. Link
   saves (`setPaybacks`), closes the window, ends selecting, and the undo bar says it with Undo (one undo for all).
   **One payment on each side** keeps brief 203's amount step (the typed amount); with several on either side the
   amounts are poured, and each link's amount can still be changed afterwards on a payment's page (brief 203's pen).
   Make clear before Link when money stays income or an expense stays open (Patrik liked that income cannot be used
   twice; let him see it).
3. **One payment's page:** its action opens the same window, so one payment in can be poured over several expenses
   (and one expense can take several payments in) by ticking them.
4. **The tour:** no new step; the paid back step's line may mention several at once if it stays one short sentence.
   `TourTests` follow if a word changes.
5. **German** for every new text (`scripts/strings.py`); light, dark and red mode; Reduce Motion; VoiceOver (the ticks,
   the summary read as text).

## Settled: do not re-open

- Pouring in date order, oldest first; the person picks both sides; one undo. Brief 201's limits.
- The selection stays a category's month list.

## Out of scope

- The data (brief 205), the engine, cash entries and receipts as links.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=claude-206'
  -derivedDataPath build/DerivedData` passes (tests for any new pure logic and words).
- `scripts/strings.py check`: 0 problems.
- **Real touches** (a temporary UI test in `Aresus/AresusUITests` driving Aresium, deleted after; 3 of 3 runs): select
  three expenses by a slide, the bar's new item, tick one payment in, the summary shows the oldest filled first, Link,
  the undo bar, the expenses' rows show what came back, Undo removes all three links; select two payments in on an
  income list, pick one expense, Link, the expense is paid back in full and the rest stays income; on one payment in's
  page tick two expenses and link.
- Screenshots `build/206-*.png` in German and English, light and dark (red once): the bar with the new item, the window
  with a group and two ticked, the summary with money left over, the undo bar after linking.
- `CLAUDE.md` updated (brief 203's section: several at once).

## Final message

As in `AGENTS.md`: files changed, the exact test summary (count the "' passed on" and "' failed on" lines), the choices
you made and why, anything doubtful. Never commit, push or merge: Claude does.
