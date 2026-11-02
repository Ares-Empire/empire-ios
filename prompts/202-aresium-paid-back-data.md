# 202: Money paid back: the app's data

Status: draft (waits for brief 201's engine)
Branch: `codex/202-paid-back-data` · Worktree: `../empire-ios-202-paid-back-data` · Model: `gpt-6.1-sol`, effort
`high` · Simulator: `codex-202` (create it: iPhone 17, iOS 27.0) · Claude copies brief 201's engine into the worktree
first (`scripts/aresium-engine.sh`) · The screens follow in brief 203 (a Claude agent) on this brief's API.

## Goal

Patrik (2026-11-02) named expenses that were paid back to him (one in full, two by half) and expected them to show only
his share. He chose a link made by hand: a payment that came in **pays back** a payment that went out, all of it
or a part; those euros then come off the expense and are not income. Brief 201 taught the engine to count such links
(`~/empire-ios/prompts/201-aresium-paid-back-engine.md`: the rules, limits and output fields). This brief stores the
links on the phone, hands them to the engine, makes every number the app adds up itself follow, and gives the screens
what they need: suggestions, a search, set, change and remove with undo, and both ends on a payment's page.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Aresium phone mode": the ledger and its export, counting as it happened (brief 71), payment
  names and name groups, adding up names (brief 53), the day page and search (briefs 76, 77), several payments at once
  (briefs 81, 82), the quick sort (brief 99), the undo bar, the tour's sample store).
- Brief 201's prompt (above) and the engine's `SourcePayment`/transaction fields in `~/aresium/src/engine/source.ts`
  and `src/data/dashboard.ts` after it.
- `Model/PhoneLedger.swift`, `Model/LedgerExport.swift`, `Model/PhoneBackend.swift` (`PhoneDashboard.input`,
  `detail`), `Model/EngineTypes.swift`, `AresiumShared/Dashboard.swift` (`Transaction`), `Model/PaymentNames.swift`
  (name groups), `Model/PaymentSums.swift`, `Model/DayPayments.swift`, `Model/PaymentSelection.swift`,
  `Model/BatchChanges.swift`, `Model/QuickSort.swift`, `Model/NameSearch.swift`, `Model/TransactionDetail.swift`,
  `Model/TransactionDetailStore.swift`, `Model/PhoneSample.swift`/`TourData.swift`, and their tests.

## Build

1. **Storage:** a payment that came in keeps its links (`paysBack`: the other payment's id and the euros, as the
   ledger keeps money). Saved with the ledger; the export becomes schema 7 with them; restore reads 6 (no links) and 7.
   Re-importing the same file keeps them (ids do not change).
2. **To the engine and back:** `PhoneDashboard.input` passes `paysBack`; `Transaction` (and the engine types) take the
   new fields (`counted`, `paidBack`, `paidBackBy`, `paysBack`) with a `countedAmount` (`counted ?? amount`). In DEBUG,
   `paybacksIgnored` from the engine is logged; after any app operation it must be empty (tests).
3. **Every number the app adds up itself uses the counted amount:** name groups (`PaymentNames`, their months),
   summed rows (`PaymentSums`), the day page's totals, the selection's money total, search's sums if any, the quick
   sort's sums. Find every place that adds `amount`s and list them in the final message. Rows keep both: the counted
   amount and the original.
4. **The screens' API** (`DashboardStore`/`PhoneBackend`, phone mode only; server mode offers nothing):
   - `paybackState(for:)`: whether the payment can take part (money in that can pay back, money out that can be paid
     back; not transfers, cash withdrawals, receipts or cash entries) and its **rest** (money in: its amount minus
     what it pays back; money out: its amount minus what it got back).
   - `paybackSuggestions(for:)`: for money in, expenses it may pay back; for money out, payments in that may pay it
     back. A pure, tested ranking: first those whose amounts fit (the payment in's rest is the expense's whole amount,
     half, a third or a quarter of it, or the expense's rest, within one cent), then by how close the dates are; only
     money in from 30 days before to 120 days after the expense; never transfers, withdrawals, receipts, cash
     entries, payments with no rest, or the payment itself. Each suggestion says what fits (`whole`, `half`, `third`,
     `quarter`, `rest`, or none) and the euros a link would take (the fit's, else the smaller rest). At most about 8.
   - `paybackSearch(_ query:, for:)`: every candidate of the other direction whose names match (the spellings
     `NameSearch` uses: own names and bank lines), newest first, same exclusions, no date window: for money paid back
     in parts or long after (a course paid back in instalments).
   - `setPayback(from:to:amount:)`: validates the directions, both rests and cents (an existing link's amount can be
     changed), saves once, rebuilds once, returns an undo. `removePayback(from:to:)` likewise.
   - On a payment's detail (`TransactionDetail`), both ends: what it got back or pays back in all, and each link (the
     other payment's id, shown name, date, its own amount, the linked euros), so the page can show and open them.
5. **Category changes:** a payment moved to a transfer category (own transfers, savings) loses its links at either end
   (a single switch, a batch switch, the quick sort, a category deleted and its payments resorted); the undo of that
   change brings them back.
6. **The tour's sample store** gets one made-up case: a trip paid in full and half of it paid back by a made-up person
   a day later, linked, so brief 203's tour step can show it. Made-up names and amounts only.
7. **Messages** (the monthly review) and the widget read the engine's numbers: check they follow, say how.

## Settled: do not re-open

- Links are made by hand; suggestions only rank. Brief 201's rules and limits.
- A link lives on the payment that came in.
- No links for cash entries or receipts yet.

## Out of scope

- The screens and the tour's step (brief 203), the engine (brief 201), the server.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=codex-202'
  -derivedDataPath build/DerivedData` passes, with tests for: the ledger and export round trip (6 and 7); suggestions
  (half the next day first, whole, a rest, outside the window left out, transfers, withdrawals and used-up payments
  left out, ties by date); search; both limits and cents; undo of set and remove; a switch to a transfer removes the
  links and its undo restores them; name groups, summed rows, the day page and the selection total follow the counted
  amounts; the detail's links at both ends; the dashboard numbers with a link (headline, month, category) as brief 201
  counts them.
- `python3 scripts/strings.py check`: 0 problems.

## Final message

As in `AGENTS.md`: files changed, the exact test summary (count the "' passed on" and "' failed on" lines), every place
that adds amounts and what it uses now, anything doubtful. Never commit, push or merge: Claude does.
