# 43: Aresium remembers names the person gives payments, and adds up all payments of one name (the data)

Status: merged 2026-10-30 (Aresium tests pass, 0 failed; ledger schema 5, export schema 4; API in CLAUDE.md → Aresium phone mode)
Branch: `codex/43-own-names` · Worktree: `../empire-ios-43-own-names` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Patrik (2026-10-30): people should be able to rename their payments to names they remember more easily. Aresium keeps
each name with the bank's original name, so new imports are still sorted as before and get the name automatically.
Payments of the same name can be added up (in a later brief: from a swipe on the row and from the payment's page). A
setting switches between the person's names and the bank's. The payment's page shows the bank's name small under the
person's.

This brief builds the data and the logic for phone mode: storage, applying names on import, the setting, the numbers
for "all payments of this name", export/restore, tests. **No screens:** brief 44 (a Claude agent) builds the screens
on what you make, and brief 42 runs in parallel in `Screens/`. Write the API you add down in `CLAUDE.md` (the
"Aresium phone mode" entry) so brief 44 can build on it without reading all of your code.

## Read first

- `AGENTS.md`, `CLAUDE.md` (the "Aresium phone mode" entry: learning a shop, "Also the other payments from <shop>?",
  the ledger and its schema, export/restore, the rule that work after a tap never blocks the main thread, brief 39)
- `Aresium/Aresium/Model/PhoneStore.swift` (`LedgerSchemaV1…V3`, the migration plan), `Model/PhoneLedger.swift`
  (`LedgerPayment.place`, learned rules, `shopNames()`, export/restore), `Model/LedgerExport.swift` (export schema 3),
  `Model/PhoneBackend.swift` (`PhoneDashboard.input`, learning, `otherPayments(of:besides:target:)`, the
  `merchantKeys` calls), `Model/AresiumEngine.swift` (`merchantKeys`: the engine's `merchantKey`, source
  `~/aresium/src/engine/sorting/merchant.ts`), `Model/PhoneReceipts.swift` (receipts' shop and its merchant key),
  `Model/DashboardStore.swift`, `Model/TransactionDetail*.swift`, `Model/PaymentPage.swift`, `Model/PaymentRows.swift`,
  `AresiumShared/Dashboard.swift` (`Transaction`: shared with the widget and the server's JSON).

## Behaviour (settled with Patrik's request; build exactly this)

1. **Two names.** Every bank payment has its *bank name*: today's `place` (the counterparty, else the text). It never
   changes, and sorting, learning, `merchantKey` and the receipt matching keep reading only it. The person can add an
   *own name*.
2. **Renaming applies to one payment or to the shop.** The screens will ask, as the category change does: "Also the
   other N payments from <bank name>?"
   - *The shop:* a name rule `merchantKey → name`. Every payment with that merchant key shows it, the ones there now
     and every one imported later. This is what makes the three spellings of one Penny get one name.
   - *Only this payment:* a name on that payment alone. It wins over the shop's rule.
   - A payment whose merchant key is `""` (a bare PayPal line without a seller) can only be renamed alone: N is 0.
   - An empty name removes the name (the rule or the payment's own name, whichever the person is changing), back to the
     bank name. Leading/trailing spaces are trimmed; a name at most 60 characters (say if you pick another limit).
   - Only bank payments are renamed. Receipts and cash entries already have their Shop (their Edit), and stay as they
     are.
3. **The setting "own names"** (UserDefaults, key `aresium.ownNames`, on by default). On: the dashboard shows the own
   name wherever one applies. Off: the bank names everywhere; the own names stay stored and come back when it is
   switched on. Changing it rebuilds the dashboard (off the main thread, as every rebuild).
4. **What the dashboard carries** (phone mode; the server's JSON and the widget unchanged, so only optional fields):
   - `Transaction.place` is the *shown* name (own name if the setting is on and one applies, else the bank name), so
     every row, the payment page and the widget show it with no screen change.
   - New optional fields for brief 44: the bank name when it differs from the shown one; whether the shown name is
     the person's own and whether it comes from the shop's rule or the payment alone; the *name key* (below).
5. **"All payments of this name"** (the numbers brief 44's page shows). The *name key* groups payments:
   - setting on and an own name applies: the own name, compared case- and diacritic-insensitively, so two shops both
     named "Supermarkt" count together;
   - otherwise the merchant key (so the Penny spellings count together without any renaming);
   - merchant key `""`: the bank name exactly (a bare PayPal line groups only with identical lines).
   - Cash receipts and cash entries join the group of their shop's merchant key (or own name, if a rule names that
     key), so cash at Penny counts with Penny. Covered rows ("Accounted for") are left out.
   - The same counting rules as the dashboard's totals: a payment that counts in no total (a category excluded from
     totals, own transfers) is left out of the group's numbers and rows.
   - For a name key: the rows (newest first), the count, the money out and the money in (separately: a shop can refund),
     and per month the same two, over every month the dashboard has (not only the current range).
   - Build the groups once per dashboard build, off the main thread (a dictionary from name key to its rows), not on
     every tap or every view update.
6. **Renaming from the app** (for brief 44): one call that takes the payment, the name and the scope (shop or alone),
   saves it, and rebuilds the dashboard; one that tells a payment's page what to offer and ask: its bank name, its
   current own name and where it comes from, whether it can be renamed at all (bank payment, phone mode), and N for the
   question. Mirror how the category change is wired (`TransactionDetailStore` → `PhoneBackend`), so brief 44 opens the
   rename the same way.
7. **Storage:** a new ledger schema version with a lightweight migration from V3 that keeps every payment, rule and
   receipt (test it with a V3 store, as earlier migrations are tested). Name rules and payments' own names are stored
   on the phone only, as everything else. "Delete all data" removes them too.
8. **Export/restore:** the export carries the name rules and the payments' own names (export schema 4); a restore of
   schema 4 brings them back; schema 1–3 exports restore exactly as before.
9. **Server mode and the sample:** server mode offers no rename (the server keeps no names). Phone mode's sample
   (`-samplePhone`): follow what the category change does there.

## Settled: do not re-open

- Sorting and learning stay on the bank name and merchant key; an own name never changes a category.
- One payment's own name beats the shop's rule; the setting only changes what is shown and how payments group.
- No engine (JavaScript) change: the merchant key comes from the engine as it is.

## Out of scope

- Every file in `Screens/` and `ContentView.swift`: brief 42 runs in parallel there and brief 44 builds the screens.
  The Settings toggle for `aresium.ownNames` is brief 44's. If you need a screen change to test, describe it instead.
- Server mode's API (`~/aresium`), the widget's look.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium` passes on your own simulator (`codex-43`,
  commands in `AGENTS.md`), with new tests (made-up data only) for: a shop rule names every payment of the merchant
  key, also one imported afterwards; a payment's own name beats the rule; empty name removes; merchant key `""` only
  alone; the setting off shows bank names and keeps the own names; the name key groups the Penny spellings, two shops
  with the same own name, a cash receipt with its shop; excluded payments left out; the numbers per month; sorting is
  unchanged by a rename; the V3 → new schema migration keeps data; export/restore round trip with names; schema 3
  export still restores; nothing of it runs on the main actor except setting published values.
- The API you add is described in `CLAUDE.md` → "Aresium phone mode" (short: what to call, what it returns).
- `scripts/strings.py check`: 0 problems (only if you add user-facing text, such as an error).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the API you added (names and one line each),
your choices (name length limit, schema version, how the groups are built), what is missing or doubtful. Never
commit, push or merge: Claude does.
