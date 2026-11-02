# 208: Monthly average and fixed costs: the data

Status: merged 2026-11-02 (871 Aresium tests; 5 timing and import tests failed under load and passed alone, 44 of 44; detection 145 ms at 5,000 payments off the main thread; marks in ledger and export schema 8)
Branch: `codex/208-fixed-costs-data` · Worktree: `../empire-ios-208-fixed-costs-data` · Model: `gpt-6.1-sol`, effort
`high` · Simulator: `codex-208` (create it: iPhone 17, iOS 27.0) · The screens follow in brief 209 (a Claude agent) on
this brief's API.

## Goal

Patrik (2026-11-02, after build 18) asked for feature ideas; Claude offered two: the monthly average under the
Overview's total, and a page of fixed costs, what repeats every month (rent, subscriptions, insurance) and what it adds
up to. Patrik: "lets do monthly and fixcost screen feature first because thats actually a great idea and wont take that
long", and agreed to this plan: the Overview says "Ø €1,940 a month" over finished months only, and "of which fixed
€860 a month"; a tap opens the fixed costs: the monthly total on top, each one with its amount, how often, the last
payment and the next one due (a yearly payment counts as a twelfth a month); one that stopped (a cancelled
subscription) under Ended; one counted by mistake taken out by the person ("Not fixed"); on the income side the same
for regular money in (salary, a monthly transfer from the parents). This brief builds the numbers and the person's
marks; brief 209 builds the screens.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Quick sort": groups by `Transaction.nameKey`, built off the main thread with each phone
  dashboard and published with its `revision`; "Payment names and groups", "Shop identities" and "One bank name per
  shop": what `nameKey` groups and how name rules are keyed and moved when the engine changes; "Counting as it
  happened" and "Money paid back": `countedAmount`; the storage paragraph: schema versions, migration, export and
  restore; "Several payments at once — data API": `BatchUndo` and the save revision).
- `Model/QuickSort.swift` (the pattern to follow), `Model/DashboardStore.swift` (`reload`, `builtQuickSort`),
  `Model/PaymentNames.swift`, `Model/PhoneStore.swift` (`LedgerSchemaV7`, `LedgerMigrationPlan`),
  `Model/LedgerExport.swift`, `Model/BatchChanges.swift`, `AresiumShared/Dashboard.swift` (`Month.partial`,
  `byMonth`, `Transaction`).

## Build

1. **The monthly average** (pure, `MonthlyAverage`, both sides): from a `Dashboard`, the months that count are every
   month the engine does not mark `partial` (the running month), leaving out the first month when the data's earliest
   payment falls after that month's 7th day (the bank file most likely starts inside it). The average is those months'
   totals (`byMonth[key].expense` or `.income`, which already count paid-back euros as brief 201 says) divided by their
   number, in whole cents. Out: the amount, how many months, the first and the last month counted. Nil with fewer than
   two months. A pure function of the dashboard, so server mode has it too.
2. **Fixed costs and regular income** (pure, `FixedCosts`, both directions; phone mode, since it needs `nameKey`):
   - **Candidates:** bank payments with a `nameKey`, never receipts, cash entries, cash withdrawals, a withdrawal's
     covered row, own transfers or a transfer-kind category, and never a payment that counts 0. The amount is
     `countedAmount` (one's own share after money paid back). Money out makes fixed costs, money in regular income.
   - **Series:** within one name and direction, walk the payments oldest first; a payment joins the open series whose
     newest amount is within 10 % or €3 of it (whichever is larger), else it starts a new one. So one shop with two
     subscriptions makes two series, and a rent raised in steps stays one.
   - **How often:** from the gaps between a series' payments in days: monthly (median gap 26–35), quarterly (85–98),
     half-yearly (175–190), yearly (355–375). A series is regular when it has at least 3 payments (monthly, quarterly)
     or 2 (half-yearly, yearly) and at least three quarters of its gaps fit the cadence; a gap of about twice the
     cadence counts as one missed payment, not a break; a gap under half the cadence means visits to a shop, not a
     fixed cost (the series is not regular).
   - **Running or ended:** running while its newest payment is no older than one cadence plus some grace (monthly 45
     days, quarterly 120, half-yearly 220, yearly 400) before the **reference day: the newest payment's day in the
     whole ledger**, not today (someone who imports every few months must not see everything as ended).
   - **Each entry:** a stable id (survives a rebuild and a new import: the mark key below, the direction and the
     cadence), the shown name and the category (the newest payment's, its primary category on that side), the
     cadence, the amount now (the newest payment's), the monthly equivalent (monthly ×1, quarterly ÷3, half-yearly ÷6,
     yearly ÷12, whole cents), the count, the first and the last day, the next day due (the newest day plus 1, 3, 6 or
     12 calendar months, the day of the month clamped), running or ended, the row ids newest first, the newest
     `Transaction`.
   - **A side's list:** running entries by monthly equivalent (largest first, then the name), ended entries by their
     last day (newest first), entries the person took out (below) apart; the monthly total over running entries not
     taken out.
3. **"Not fixed"** (the person's correction): taking an entry out of its side's list and total, and putting it back.
   Stored in the ledger: a new model in **schema version 8** (the next stage of `LedgerMigrationPlan`, never V7 edited),
   keyed as name rules are keyed so it survives the engine changing (the shop's merchant key; an own name; the bank
   line for a payment without a merchant key; your call, said in the final message), plus the direction and the
   cadence, and moved like name rules when the engine revision changes. Export **schema 8** carries the marks; files of
   schema 1–7 still restore; Delete data deletes them. `setNotFixed(_ entry:, _ notFixed: Bool)`: one save, one
   rebuild, a `BatchUndo`.
4. **The API for brief 209** on `DashboardStore`: `monthlyAverage(side:)`, `fixedCosts(side:)` (nil in server mode)
   with the running, ended and taken-out entries and the monthly total, built off the main thread with each phone
   dashboard and published with its `revision` as the quick sort's groups are (`QuickSortCache` is the model), and
   `setNotFixed`. A row's entry by id for the screens (`fixedCost(id:)`). Say in the final message how long the build
   takes at 5,000 payments on the simulator (the existing 5,000-payment timing source).
5. **Words** (pure, tested, both languages): the cadences ("monthly" / "monatlich", "quarterly" / "vierteljährlich",
   "every 6 months" / "halbjährlich", "yearly" / "jährlich"); the next day due ("next 3 Dec" / "nächste am 3. Dez.",
   the year only in another year). Brief 209 writes the rest.

## Settled: do not re-open

- Detection in Swift on the dashboard, like the quick sort: it groups by the app's own names (`nameKey`), which the
  engine does not know.
- Counted amounts (one's share after paybacks); bank payments only; the reference day is the ledger's newest payment.
- Taking out is the only correction for now; adding one by hand is not part of this brief.

## Out of scope

- The screens, the tour (brief 139 is moving the tour's pieces into `Shared/` right now; do not touch
  `TourModel.swift` or `TourScreens.swift`), the engine, the website.

## API

None: everything is on the phone's dashboard and ledger.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=codex-208'
  -derivedDataPath build/DerivedData` passes, with tests (made-up data only) for: the average leaving out the running
  month and a first month that starts late, both sides, nil under two months, paid-back euros counted as brief 201
  says; a monthly rent with one raise (one entry, the new amount); two subscriptions under one shop (two entries); a
  supermarket visited every week at changing amounts (none); a gym that ended four months before the newest payment
  (ended); a yearly insurance paid twice; a quarterly one; one missed month (still regular); two payments in one month
  (not regular); a rent shared and half paid back (the counted half); a monthly salary and a monthly transfer in
  (regular income); receipts, cash, withdrawals and own transfers never counted; the monthly total and the order; a
  mark that takes an entry out, survives a rebuild, a new import and the engine revision's key move, and comes back
  with undo; export and restore of schema 8, and a schema 7 file still restoring; the words in both languages.
- `python3 scripts/strings.py check`: 0 problems.

## Final message

As in `AGENTS.md`: files changed, the exact test summary (count the "' passed on" and "' failed on" lines), the API for
brief 209 in a few lines, the mark's key and why, the timing at 5,000 payments, anything doubtful. Never commit, push
or merge: Claude does.
