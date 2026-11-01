# 99: Quick sort: going through what is not sorted, biggest first

Status: brief
Branch: `claude/99-quick-sort` · Worktree: `../empire-ios-99-quick-sort` · Built by: a Claude agent (the flow and its
look, and the small model behind it) · Simulator: `claude-99` (create it: iPhone 17, iOS 27.0)

## Goal

Patrik (2026-11-01), after seeing that most of what stays unsorted on day one is personal (money from his parents 77
payments, his own categories 50, friends and gifts, a few payees with many payments each) and that no rule or list can
know it: "yes a more efficient not sorted sorting is smart. Like a way to see the top not sorted factors and going
through them".

Today the only way is a category's month list: one payment (or a selection, brief 82) at a time, month by month.
After this brief Aresium offers to **go through what is not sorted, payee by payee, the biggest first**: one card per
payee with how many payments and how much money, a tap on a category sorts all of that payee's unsorted payments at once
and teaches Aresium the payee for new imports, then the next card. A handful of taps sort most of a person's first
import.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Languages", "Light mode", and in "Aresium phone mode": payment names and groups
  (`Dashboard.nameGroups`, `nameKey`, shop identities, brief 54/76), the change window (`RecategoriseSheet`, its tiles,
  "Andere Kategorie …", New category; briefs 60, 70, 80, 83), selecting several payments and brief 81's batch API
  (`switchCategory(ids:to:)` with learning, its follow-up and undo), the import's result and the category picker after
  an import, the undo bar, the tour (briefs 59, 77, 82)).
- `Model/BatchChanges.swift`, `Model/PaymentNames.swift`, `Model/DashboardStore.swift`, `Screens/RecategoriseSheet.swift`,
  `Screens/ImportControls.swift`, `Screens/PaymentList.swift`, `Model/TourModel.swift`.

## Build

1. **The groups** (a pure, tested model, phone mode only): every payment that is **Not sorted** (no category, not a
   covered cash row), across all months, grouped by payee as the name groups group them (shop identity, an own name,
   or the exact bank line for an empty merchant key; a person paying or paid by bank transfer is a payee too), **split
   by direction** (money in and money out of one payee are two groups: a parent's transfers to you and your payment to
   them are different questions). Ranked by the number of payments, then by the money. Each group: the shown name,
   the count, the total, the first and last date, two or three example payment texts (the purpose lines, not repeated),
   the side, and the ids. Built off the main thread from the dashboard the store already has, cached by revision.
2. **Sorting a group:** a tap on a category sets every payment of the group to it by hand and learns the payee, using
   brief 81's `switchCategory(ids:to:)` (never a copy of it), with its follow-up applied automatically when it only
   concerns the same payee's other **Not sorted** payments (there are none outside the group by construction; say if
   you find a case). One undo for the last group sorted (brief 81's undo).
3. **Where it starts:**
   - After an import that leaves payments Not sorted (once the category picker after an import and the result are
     done, in the result's place as the reminder offer does, never on top of another window): a quiet offer, "34
     payments not sorted, from 12 payees. Go through them?" / "34 Buchungen nicht sortiert, von 12 Absendern.
     Durchgehen?", **Go through** / **Durchgehen** and **Later** / **Später**.
   - On Not sorted's month list (Current and Overview), a card at the top while there are groups of two or more:
     "12 payees · 150 payments · Go through" (your words), opening the flow for all months.
   - Not in server mode.
4. **The flow** (a sheet at full height, Claude's look from the app's own pieces): a progress line ("3 of 12" and the
   payments sorted so far), Done; one card at a time: the payee's name in the payment page's title style, "18 payments ·
   −312.40 € · Jan–Oct 2026", the example lines in quiet type, and whether it is money in or out; under it the
   category tiles of that side, as the change window shows them (with "Andere Kategorie …" and New category, brief 80's
   behaviour for a typed name that exists); **Skip** / **Überspringen** and **Undo** / **Rückgängig** (the last group)
   at the bottom. A tap on a tile sorts the group, a light haptic, and the next card slides in (Reduce Motion: a fade).
   At the end, a summary ("84 payments sorted from 9 payees, 3 skipped") and Done. Groups of one payment come last;
   the person can stop any time, and what was sorted stays sorted. VoiceOver reads each card as one element with the
   tiles as buttons.
5. **The tour:** one step for it where it fits (after the import step, or at Not sorted's card), in the tour's words,
   on the tour's store. `TourTests` follow.
6. **German** for every new text (`scripts/strings.py`), checked on screen; light, dark and red mode.

## Settled: do not re-open

- Not sorted only; grouped by payee and direction; biggest first.
- One tap sorts the whole group and teaches the payee; undo for the last group.
- The person's own choice; nothing is guessed for them.

## Out of scope

- Suggesting a category for a group (a later idea), server mode, changing already sorted payments.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=claude-99'
  -derivedDataPath build/DerivedData` passes, with tests for the grouping (payees, persons, directions split, covered
  rows out, ranking, all months), sorting a group (manual, learned, the next import of that payee sorted by learning),
  undo, the offer's conditions after an import, the card on Not sorted, the summary's words in both languages, the tour.
- `scripts/strings.py check`: 0 problems.
- Real touches (a temporary UI test, deleted after): the offer after an import opens the flow, a tile sorts and moves
  on, Skip, Undo, Done; the card on Not sorted opens it.
- Screenshots `build/99-*.png` in German and English, light and dark (red once): the offer, the card on Not sorted, a
  card in the flow (a shop and a person), the end. DEBUG launch arguments for these, listed in `CLAUDE.md`.
- `CLAUDE.md` updated.

## Final message

As in `AGENTS.md`: files changed, the exact test summary (count the "' passed on" and "' failed on" lines), the
screenshots' paths, your design choices and why, anything missing or doubtful. Never commit, push or merge: Claude does.
