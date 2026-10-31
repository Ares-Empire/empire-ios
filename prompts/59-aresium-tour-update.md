# 59: The tour shows what Aresium can do now, in one coherent walk

Status: merged 2026-10-31 (all 609 Aresium tests pass; 18 steps, 17 without the graph; a real-touch walk from Start tour to Done in German passed; adding up in the tour on its own choices)
Branch: `claude/59-tour` · Worktree: `../empire-ios-59-tour` · Built by: a Claude agent (the look, the words and the
feel) · Simulator: `claude-59`

## Goal

Patrik (2026-10-31, fifth round, item 8; `docs/reviews/2026-10-30-aresium-phone-test.md`): "for the new features and
toggles we should update the tour so it explains everything and is coherent." The tour (brief 24, lightened in brief
25, the graph step in brief 42) was written before most of what Aresium does now. After this brief a new person who
taps Start tour learns, on the made-up data, every everyday feature and where its switches are, in a walk that feels
like one story, not a list of features.

## Read first

- `AGENTS.md`, `CLAUDE.md`: "Languages", "Light mode", "Settings", and in the "Aresium phone mode" entry: the tour
  ("**The tour** (brief 24 …"), "Renaming and the name's page" (briefs 44, 47, 55), "Adding up names in a category's
  list" (brief 53, fix 58), the graph (brief 56: the hold-and-slide chip, a tap opens a month, Overview's month page,
  "Graph moves away when scrolling"), "Settings → Messages and the offer" (brief 46), receipts and cash (the import
  menu), "Comfort on the dashboard" (the long press).
- `Aresium/Aresium/Model/TourModel.swift` (`TourStep`, its texts, `target`, `update`, `prepare`, `holdsTheScreen`,
  `TourWorld` and its `PaymentSums(offered: false)`), `Model/TourData.swift` (the made-up bank file), `Screens/TourScreens.swift`
  (anchors, veil, card, the tour's own Settings), `AresiumTests/TourTests.swift`.
- `docs/reviews/2026-10-30-aresium-phone-test.md` and `docs/reviews/2026-10-30-swipe-and-comfort.md`: what Patrik asked
  for and why, so the tour's sentences match how he thinks about each feature.

## What the tour should cover

Today's twelve steps: welcome, income, overview, graph, category, payment, switch category, categories, lock, contact,
import, done. Missing, in rough order of everyday use:

- **The graph:** hold and slide to read a day's or month's number; a tap on a month opens it (Overview: the month's
  page); it moves away while the categories scroll (the switch in Settings → Dashboard).
- **Renaming:** on a payment's page, a tap on the name (or its pen) renames it; "also the other payments" names the
  shop. The category chip (or its pen) changes the category (today's switch step points at it: keep that step, adjust
  its words if needed).
- **The row swipe:** swipe left on a payment: **Add up** (this name as one row in this category) and **All** (the
  name's page). The long press offers the same and more.
- **Adding up:** the stack icon at the top of a category's list adds up every name there; Settings → Dashboard adds up
  everywhere; a name's page has its own switch.
- **The name's page:** every payment of one name, by month; a month opens its payments.
- **Messages:** Settings → Messages: an import reminder and a month review, made on the iPhone.
- **Import:** files from the bank, receipts (scan or photo) and cash entries come in through the import button (today's
  import step says files and receipts; cash belongs in the same sentence).
- **Settings' switches** in one place: Dashboard (Graph, the graph moving away, Add up same names), Own names, Lock.

## Build

1. **A new step list** that covers the above in an order that flows (the dashboard, a category, a payment and what can
   be done with it, a list's swipe and adding up, the name's page, then Settings' places, import, done). Keep it as
   short as the content allows: aim for 15 to 17 steps, one short sentence per card (two only where a step really needs
   it), in the app's plain "du" German and plain English (no "AI", no marketing words; Patrik's terms: Buchung, Ausgaben,
   Einnahmen, Summieren, Auflösen, Alle). Combine where one screen naturally shows two things (e.g. the payment's page:
   rename and change category in one or two steps; Settings → Dashboard's switches in one step).
2. **Each step points at a real control** (`.tourAnchor`) and goes on when the person does the thing or taps Next, as
   today; End tour always on the card. New anchors as needed (the payment page's name/pen, a row for the swipe, the
   category's add-up icon, a name page's month row, Settings' Messages and Dashboard sections). A step the person can
   do in the tour should work there on the made-up store: renaming saves to the tour's store only; the swipe's Add up
   and the icon work on the tour's in-memory choices (`TourWorld` must offer adding up now: an empty in-memory
   `PaymentSums`, never the person's; make sure the steps that point at single rows still find single rows, e.g. by
   pointing at a name that is not added up, or by the order of the steps). Messages and the Lock in the tour's Settings
   only point and go on: no iOS permission prompt, no notification planned, no lock set (as the Lock and Contact
   steps already do). The graph step may let the person try the hold-and-slide (the tour's veil lets that gesture
   through on that step) or just show it; your call.
3. **Hidden graph:** with Graph off in the person's Settings, the graph steps drop out (as today's `TourStep.steps(
   showingGraph:)`), and no step mentions it.
4. **The tour's Settings** shows the person's Settings sections it points at, in the same order as the real Settings
   (`ContentView`'s sheet), so what the tour shows is where things are.
5. **German** for every new text (`scripts/strings.py`); old step texts that no longer fit are replaced, not kept.
6. Nothing outside the tour changes behaviour. The person's store, choices (`aresium.sums`), names, messages, lock and
   settings are never read or written by the tour (tests prove it, as `TourTests` and `PaymentSumsTests.theTourHasItsOwnInMemory` do).

## Settled: do not re-open

- The tour stays offered (Start tour, Settings → Help → Tour), never started by itself.
- One sentence per card; the card's look, the veil (0.3) and the ring stay as they are.
- The tour uses the real screens on its made-up store, as today.

## Out of scope

- Any feature's own behaviour or look outside the tour.
- The first screen and the bank guide.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=claude-59'
  -derivedDataPath build/DerivedData` passes, with `TourTests` updated for the new steps (each step's target and what
  moves it on, the hidden graph's list, nothing of the person's touched, adding up in the tour in memory only).
- `scripts/strings.py check`: 0 problems.
- A walk through the whole tour with real touches (a temporary UI test, deleted afterwards), doing each step's action
  where it has one and Next where not, from Start tour to Done, in German; it ends on the first screen or the dashboard
  as today.
- Screenshots `build/59-*.png` of every step in German (light) and of a few in English and dark, plus the step list
  (one line per step: its text in both languages and what it points at) in your final message.
- `CLAUDE.md` updated (the tour's part of "Aresium phone mode": the steps, the new anchors, adding up in the tour).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the step list, the screenshots' paths, your
choices, what is missing or doubtful. Never commit, push or merge: Claude does.
