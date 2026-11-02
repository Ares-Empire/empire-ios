# 203: Money paid back: the screens and the tour

Status: draft (waits for brief 202)
Branch: `claude/203-paid-back` · Worktree: `../empire-ios-203-paid-back` · Built by: a Claude agent (the look and the
flow) · Simulator: `claude-203` (create it: iPhone 17, iOS 27.0)

## Goal

Patrik (2026-11-02), looking at what Aresium counts as spent over 14 months, named expenses that were paid back to him
(one in full, two by half) and expected them to show only his share. He chose a link made by hand: a payment that
came in **pays back** a payment that went out, all of it or a part; those euros come off the expense (in its month and
categories) and are not income. And: "It would need to be added to the tour but it remains a completely optional thing
to do."

Briefs 201 (engine) and 202 (the app's data and API) are merged. This brief makes it usable: link from either payment's
page, see it on both, see it in the lists, and one tour step.

## Read first

- `AGENTS.md`, `CLAUDE.md` (Aresium phone mode: the payment page and its actions, `TransactionDetailSheet`; the change
  window; lists, `PaymentRow` and summed rows; the name page, day page and search; the undo bar; the tour, its sample
  store and its rings; "Nothing that moves sits over or under a pathless shadow"; the Empire's design restraint).
- `prompts/201-aresium-paid-back-engine.md` and `prompts/202-aresium-paid-back-data.md` (the rules and the API:
  `paybackState`, `paybackSuggestions`, `paybackSearch`, `setPayback`, `removePayback`, the detail's links,
  `countedAmount`).
- `Screens/TransactionDetailSheet.swift`, `Screens/PaymentList.swift`, `Screens/SummedRows.swift`,
  `Screens/NameScreen.swift`, `Screens/DayScreen.swift`, `Screens/SearchScreen.swift`, `Screens/TourScreens.swift`,
  `Model/TourModel.swift`, `Model/TourData.swift`, `Shared/Design/UndoBar.swift`.

## Build

1. **On a payment's page** (phone mode, only where `paybackState` allows):
   - Money in: an action to say it pays back an expense (German "Zahlt eine Ausgabe zurück", English "Pays back an
     expense"; your words if better). Money out: an action to pick the payment that paid it back ("Wurde
     zurückgezahlt" / "Paid back to you", or better). Quiet, below what is there: optional, never in the way.
   - The choice: the suggestions first, each with its name, date, amount and what fits ("die Hälfte", "ganz", "der
     Rest"); a search for anything else (paid back in parts or months later); then the euros (the suggestion's, else
     the smaller rest; editable, never above either rest) and a confirm. Then the page shows the link.
   - A linked payment's page shows each link (name, date, the linked euros), opens the other payment on a tap, can
     change the euros and remove the link (the undo bar after a change, as elsewhere). The expense's page shows its
     own amount and what it got back; the payment in's page what it pays back and any rest that still counts as income.
2. **In lists** (a category's month list, the name page, the day page, search): a row's number is what counts there
   (`countedAmount`), so a list's rows still add up to its total; a small second line says why, for example
   "240 € · 120 € zurück" on the expense, "zahlt Hotel zurück" on the payment in. A payment wholly paid back or
   wholly used stays listed; make clear it counts 0 without shouting. Summed rows follow.
3. **The tour:** one step on the sample's payback (brief 202 put one in the sample store): the trip's page, its link.
   Say it is optional, and what it does, in one short sentence (for example "Paid back by someone? Link it: only your
   share counts."). Its ring and store as the other steps; `TourTests` follow. Nothing else asks the person to link:
   no prompts after an import, no badges.
4. **German** for every new text (`scripts/strings.py`); light, dark and red mode; Reduce Motion; VoiceOver labels.

## Settled: do not re-open

- Made by hand from either payment's page; suggestions only help.
- A list's rows add up to its total (counted amounts), the original amount stays visible.
- Optional: one tour step, no other prompts.

## Out of scope

- The engine and the data (briefs 201, 202), cash entries and receipts as links, selecting many to link at once.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=claude-203'
  -derivedDataPath build/DerivedData` passes (tests for any new pure logic; `TourTests` with the new step).
- `scripts/strings.py check`: 0 problems.
- **Real touches** (a temporary UI test in `Aresus/AresusUITests` driving Aresium, deleted after; 3 of 3 runs): open a
  payment in, pick the half suggestion, confirm; the expense's category total falls by that much; open the expense,
  it shows the link; open the other payment from it; remove the link, undo brings it back; search finds an expense
  outside the suggestions.
- Screenshots `build/203-*.png` in German and English, light and dark (red once): the action on both pages, the choice
  with suggestions, the amount, a linked expense's page, a payment in's page, a list with a paid back row, the tour step.
- `CLAUDE.md` updated (a section for briefs 201 to 203).

## Final message

As in `AGENTS.md`: files changed, the exact test summary (count the "' passed on" and "' failed on" lines), the choices
you made and why, anything doubtful. Never commit, push or merge: Claude does.
