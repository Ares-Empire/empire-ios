# 76: One name per shop, the search's ranking, a day's payments: the data

Status: merged 2026-11-01 (696 Aresium tests; checked on Patrik's files: 101 of 167 shops get one name, none a PayPal or card line; Vinted "Vinted, UAB", Apple "Apple Services"; search 7.6 ms at 1,000 names)
Branch: `codex/76-names-search-day` · Worktree: `../empire-ios-76-names-search-day` · Model: `gpt-6.1-sol`, effort
`high` · The screens follow in brief 77 (a Claude agent), on this brief's API.

## Goal

Patrik (2026-11-01, after build 9), three things:

1. "sometimes the issue still happens that the same vendor has different names". Claude checked his real files on the
   Mac (they never leave it): Vinted is one shop to Aresium (brief 48's shop identity groups all of its payments, so
   adding up and "All with this name" already take them together), but each row shows its own bank line, and Vinted's
   changed during the year: "MGP Vinted - Kleiderkreisel" on the older payments, "Vinted, UAB" on the newer. After this
   brief **a shop shows one name**: the bank's name of its newest payment, unless the person gave it a name of their own.
2. "Search expenses … A small search icon. Im thinking search by names which uses own given and also original names
   organized by best match." This brief gives the ranking; brief 77 draws the screen.
3. "filter by day … Lets make days clickable too and lead to a screen with that days expenses and income (in two tabs
   with swipe)." This brief gives a day's payments for each side; brief 77 draws the page.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Aresium phone mode": payment names and groups of briefs 43–44 and 54, the name's page,
  brief 71's counting as it happened, the graph and a month's page of brief 56).
- `Aresium/Aresium/Model/PaymentNames.swift` (`apply`, `shown`, `key`, the detail's name, `nameGroups`),
  `Model/ShopIdentities.swift`, `Model/PaymentRename.swift` (`RenamePlan`), `Model/DashboardStore.swift` (scopes,
  `months`, `transactions(category:month:side:)`, `paymentList`), `AresiumShared/Dashboard.swift` (`Transaction`,
  `MonthData.dayExpense`/`dayIncome`), and their tests (`PaymentNamesTests`, `PaymentNameScreensTests`).

## Build

1. **One name per shop** (`PaymentNames`):
   - A bank payment without an own name (none of its own, no shop rule, or Own names off) shows its shop's name: the
     bank name (`LedgerPayment.place`) of the newest payment of the same shop identity (the newest by booking date,
     then the store's order). A payment with an empty merchant key keeps its own bank line, as its grouping does.
   - An own name still wins (the payment's, then the shop rule's), as today. Own names off hides own names only; the
     shop's name stays (it is a bank name).
   - `Transaction.bankName` / `TransactionDetail.bankName` carry this payment's own bank line whenever the shown name
     differs from it, so the payment's page still shows the bank's own line under the title (it already does for own
     names). `isOwnName` stays false for a shop's name.
   - Everything that shows a payment's name follows: the dashboard's rows, the payment's page, the name's page and its
     months, summed rows, the Cash page's withdrawals, the rename field's start (`RenamePlan`: it starts with the shown
     name as now). Receipts and cash entries keep their typed Shop, as today.
   - Names never enter sorting, learning, receipt matching or the engine (as today).
2. **The search's ranking** (pure, tested; `Model/NameSearch.swift`): `NameSearch.results(for query: String, in
   groups: …) -> [NameSearchResult]` over the dashboard's name groups (`Dashboard.nameGroups`, phone mode only). A
   group matches through any of its names: the shown name, each own name in it, and every bank line of its payments
   (Patrik: "own given and also original names"). Folding: case and diacritics ignored, "ß" = "ss", punctuation as a
   space. Every word of the query must match. Best match first, by tier:
   1. a name equal to the query;
   2. a name that starts with the query;
   3. every query word starts a word of one name;
   4. every query word is inside one name;
   5. close spelling: for query words of 4 or more letters, one letter wrong, missing or extra in a word.
   Within a tier: a match on the shown name before a match only on another name, then more payments, then the newer
   last payment. At most 50 results; an empty or spaces-only query gives none. A result carries the group's key (for
   `DashboardStore.nameGroup`), the shown name, the other name that matched when it was not the shown one (so the
   screen can say "Bank name: MGP Vinted - Kleiderkreisel"), the count, money out and money in, the newest payment's
   date and its category. Fast enough to run per keystroke on 5,000 payments on the main thread (measure in a test:
   under 10 ms for a 1,000-group dashboard on the simulator); if it is not, give `DashboardStore` an index built once
   per dashboard (cached by `revision`, as `namePage` is).
3. **A day's payments** (`DashboardStore.day(_ date: String) -> DayPayments`, `date` as `YYYY-MM-DD`): for each side
   (`.expenses`, `.income`) the day's rows as the month lists show them (the same rows, order and covered rows as
   `transactions(category:month:side:)` across all categories, without listing a payment twice for its extra
   categories), the side's total for the day (equal to the graph's `dayExpense` / `dayIncome` for that day: test it on
   the sample over every day), and for each row its category's name and look. Cached per dashboard revision like the
   other lists. Phone and server mode alike (server rows have no names but have dates and categories).
4. **Which graph points are days:** a small pure helper `DashboardStore.dayDate(atChartIndex:scope:)` (or on the chart's
   points) that says which date a day graph's point is (the start screen's Current and a month's page), nil for month
   points. Brief 77 opens the day page with it.

## Settled: do not re-open

- One shown name per shop = the newest payment's bank line; own names still win; the bank's own line stays visible on
  the payment's page.
- Search finds names (name groups), not single payments; a result opens that name's page (brief 77).
- A day's totals are the graph's own numbers.

## Out of scope

- Every screen (brief 77): the search icon and screen, the day page, the tour.
- The engine and the server.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=codex-76'
  -derivedDataPath build/DerivedData` passes (create the simulator `codex-76`, iPhone 17, iOS 27.0), with new tests:
  two bank lines of one shop show the newest one on every row and the older row's page keeps its own line as
  `bankName`; an own name and a shop rule still win; Own names off keeps the shop's name; an empty merchant key keeps its
  line; every search tier with made-up names (a made-up shop under two bank lines found by the older line, with the
  matched name carried), folding, word order, the limit, the timing; a day's rows and totals equal the graph on every
  day of the sample, covered rows as the lists show them, extra categories once; `dayDate` for day and month graphs.
- `scripts/strings.py check`: 0 problems.
- `CLAUDE.md`'s "Aresium phone mode" updated (payment names: one name per shop; the search's API; a day's payments).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the API brief 77 builds on (names and what
each returns), the search timing measured, anything doubtful. Never commit, push or merge: Claude does.
