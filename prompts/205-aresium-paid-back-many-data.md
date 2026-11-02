# 205: Money paid back for several payments at once: the data

Status: merged 2026-11-02 (850 Aresium tests, one import test passed on a rerun alone; PaybackGroups.swift: group, pouring plan, group suggestions, setPaybacks with one undo)
Branch: `codex/205-paid-back-many` · Worktree: `../empire-ios-205-paid-back-many` · Model: `gpt-6.1-sol`, effort `high` ·
Simulator: `codex-205` (create it: iPhone 17, iOS 27.0) · The screens follow in brief 206 (a Claude agent) on this
brief's API.

## Goal

Patrik (2026-11-02, on build 17, after linking his first paybacks): "I love it the connecting is great! Let's add that
for multiple payments at once. So if I select many statements I can then select income that payed them back and it just
goes expense by expense until it's empty. Then let's also add the other direction that it's possible to do it from
income to expenses if you know what I mean. It was great that it worked that I can't over use income, good catch."

Briefs 201–203 link **one** payment in to **one** expense, by hand. This brief lets a **group** on one side (several
selected payments of a category's month list, or one payment's page) be linked to **one or more** payments of the other
side, chosen by the person, with the euros **poured in order**: expense by expense, each filled before the next, until
the money in runs out (or every expense is paid back in full; the rest stays income). Both directions: expenses
selected and the payments in picked, or payments in selected (several transfers paying back one course) and the
expense picked. Every limit of brief 201 holds: no payment in pays back more than it has, no expense gets back more
than it cost, and what is already linked counts.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Money paid back", briefs 201–203; "Several payments at once", briefs 81, 82, 200: the
  selection, `selectionIDs(for:)`, `selectionSummary`, `BatchUndo` and the save revision).
- `prompts/201-aresium-paid-back-engine.md`, `prompts/202-aresium-paid-back-data.md`.
- `Model/Paybacks.swift`, `Model/PaybackLedger.swift`, `Model/PaybackPage.swift`, `Model/BatchChanges.swift`,
  `Model/BatchLedger.swift`, `Model/PaymentSelection.swift`, and their tests (`PaybackTests`, `PaybackScreensTests`,
  `BatchChangesTests`).

## Build

1. **A group** (`DashboardStore.paybackGroup(ids:)`, phone mode; nil in server mode): a set of row ids on one side
   (a selection's ids, a summed row's members included, or one payment's id). It says the direction, the ids that can
   take part (`paybackState` allows them and their rest is above 0), their total rest, and what is left out and why, as
   counts: receipts and cash entries, transfers, withdrawals, other currencies, nothing left. Nil when nothing can take
   part or the ids are of both directions.
2. **The plan** (pure, tested; `PaybackPlan`): the group's payments and the picked payments of the other side, each
   with its rest. **Order:** each side by date, oldest first, then the list's order (`Transaction.listOrder`'s rule),
   then id. **Pouring:** the first expense takes from the first payment in until it is paid back in full or that
   payment is used up, then goes on with the next payment in or the next expense; whole cents only. Out: the links
   (payment in, expense, euros), per payment what it gives or gets in this plan, what is left on each side (expenses
   still open, money in still income), and whether anything was linked at all. A pair already linked adds to its link
   (old + new, within both rests).
3. **Suggestions for a group** (`paybackSuggestions(forGroup:)`, at most about 8): payments of the other side with a
   rest, in the date window of brief 202 stretched over the group (money in from 30 days before the group's earliest
   expense to 120 days after its latest; for a group of payments in, expenses from 120 days before the earliest to 30
   after the latest); first those whose rest fits the group's total rest (whole, half, a third, a quarter, within a
   cent; for a group of payments in, an expense whose rest is the group's total or twice it), then the nearest date to
   the group's newest payment. Each says what fits. **Search** (`paybackSearch(_:forGroup:)`): as brief 202's, no window.
   For one payment the group's answers equal today's `paybackSuggestions(for:)` / `paybackSearch(_:for:)` (keep those as
   thin wrappers or replace their callers; say which).
4. **Saving** (`setPaybacks(group:others:)`): the plan computed again inside the ledger at save time under the save
   revision (a change since the preview refuses, as brief 81's), one save, one rebuild, **one** `BatchUndo` for every
   link it made or raised; a result with the counts and euros the undo bar needs (how many expenses, how many payments
   in, euros linked, what stayed open or stayed income). The single `setPayback(from:to:amount:)` with a typed amount
   stays for one payment on each side.
5. **Words** for the screens' summary lines in both languages (pure, tested), for example "3 expenses, €240.00 paid back.
   €60.00 stays income." / "3 Ausgaben, 240,00 € zurückgezahlt. 60,00 € bleiben Einnahme." and "€30.00 still open." /
   "30,00 € noch offen." (made-up amounts).

## Settled: do not re-open

- Pouring in date order, oldest first, each expense filled before the next; nothing is matched automatically: the
  person picks both sides. Brief 201's limits.
- One undo for one linking.
- The selection stays what it is (one category's month list); the other side comes from suggestions and search.

## Out of scope

- The screens (brief 206), the engine, cash entries and receipts as links.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=codex-205'
  -derivedDataPath build/DerivedData` passes, with tests (made-up data only) for: pouring one payment in over three
  expenses (the oldest filled first, the last partly, nothing over); three payments in over one expense (it fills, the
  last payment in keeps a rest as income); two by two; links that already exist (rests respected, a pair raised); the
  group's left-out counts (a receipt, a cash entry, a transfer, a withdrawal, a used-up payment, a summed row's members);
  both directions; suggestions for a group (the total fits first, half, the window stretched over the group); a change
  between preview and save refused; one undo removes every link it made and restores raised ones; the dashboard numbers
  after a group link (each expense's category and month, the income) as brief 201 counts them; the words in both
  languages.
- `python3 scripts/strings.py check`: 0 problems.

## Final message

As in `AGENTS.md`: files changed, the exact test summary (count the "' passed on" and "' failed on" lines), the API
for brief 206 in a few lines, anything doubtful. Never commit, push or merge: Claude does.
