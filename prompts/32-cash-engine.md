# 32: Cash in the engine: cash entries by hand, gifts, and one place for every cash movement

Status: merged 2026-10-28 (aresium; engine tests 347; server /api/data identical on real data, deployed)
Repo: **aresium** · Worktree: `../aresium-32-cash` (branch `claude/32-cash`) · Built by: a Claude agent ·
Rules: `~/aresium/AGENTS.md`

## Goal

Patrik tried receipts (2026-10-28) and found the gap: **cash that never came from the bank** (a cash gift, money from
selling something). A cash receipt paid with it is today taken out of a bank withdrawal, which is wrong. He wants (D9 in
`~/ares-empire/docs/ARESIUM-FOR-OTHERS.md`, read it first, with D8 and part 6):

- **Cash entries by hand**, both ways: cash spent ("Flohmarkt, 20 €", any spending category) and cash received ("Geburtstag
  von Oma, 50 €", an income category). A spent entry works exactly like a cash receipt without a photo.
- **Received cash is a source of cash like a withdrawal:** cash spending takes from the sources in the pool, not only
  from withdrawals.
- **Where a cash payment came from can be chosen** per receipt or entry ("paid from" a given withdrawal or received
  cash); automatic otherwise.
- **One place for all cash:** a "Cash" page that lists every cash movement from the wallet's side: withdrawals and cash
  received as plus, cash receipts and entries as minus, and what is not accounted for. It is a view, never counted in
  the totals; the movements still count where they count today (the receipt in Groceries, the gift in its income
  category, the withdrawal's unaccounted rest in its own category).
- The default category `cash` ("Cash" / "Bargeld"), which holds the withdrawals, is renamed **"Cash withdrawals" /
  "Abhebungen"** (the id stays `cash`), so "Bargeld" is the page.

## Read first

- `AGENTS.md`; the plan (part 6, D8, D9); brief 30 (`~/empire-ios/prompts/30-receipts-engine.md`) and its code:
  `src/engine/receipts/` (`count.ts`: the pool, latest withdrawal first, `CASH_LOOKBACK_DAYS` = 92), `src/engine/source.ts`
  (`SourceReceipt`), `src/data/dashboard.ts` (`ReceiptMarks`), `src/engine/categories.ts`, the tests
  `receipt-dashboard.test.ts`.

## Build

1. **`SourceReceipt` grows** (all optional, old callers unchanged): `direction: "out" | "in"` (default "out"; "in" only
   with `method: "cash"`), `kind: "receipt" | "manual"` (default "receipt"; for the app's labels), `paidFrom: string |
   null` (the id of a withdrawal payment or of a received-cash entry; only for cash out).
2. **Cash received** (`direction: "in"`): counts as money in, in its category (an income category, or Not sorted; brief
   20's rule for money in without a category applies as for any payment), on its day; it is a source in the pool.
3. **The pool** (count.ts): sources are the withdrawals (the shop list's cash rule, as now) and the cash-received
   entries. Each cash out (receipt or entry, in date order) takes first from its `paidFrom` source when that is set,
   is on or before its day and has money left; then, for what is left, from the latest source on or before its day, at
   most `CASH_LOOKBACK_DAYS` back, as now; what no source covers is spending of its own. Covered rows stay as they are
   for withdrawals (one per withdrawal, in its category and month, positive, never income); a received-cash source needs
   no covered row (it was counted as income, and its spending counts where it is). A `paidFrom` that names nothing
   (deleted, wrong id) is ignored.
4. **The Cash page's data.** When `receipts` is given (the app always gives it, possibly empty; the server never does,
   so its JSON must stay byte-identical: prove it as brief 30 did), the dashboard gets an optional `cash` object:
   `{ months: { "YYYY-MM": { withdrawn, received, spent, unaccounted } }, movements: [{ id, date, amount (wallet side:
   + in, − out), kind: "withdrawal" | "received" | "receipt" | "manual", place, category, paidFrom: [source ids it took
   from] | null, coveredBy: [ids] | null }] }` sorted by date, newest last; `unaccounted` = what the month's withdrawals
   still hold after everything that took from them (the same number their category shows). Withdrawals also get
   `cashWithdrawal: true` on their dashboard transaction (only when `receipts` is given). Names: "spent" counts receipts
   and entries out; a gift spent on something is in "spent", the gift itself in "received".
5. **Rename** the default `cash` category's names to "Cash withdrawals" / "Abhebungen" in `categories.ts` (the id, its
   look and the shop list's rule stay).
6. **Tests** (made-up data only): a gift then a cash receipt paid from it (the withdrawal untouched); `paidFrom` naming a
   withdrawal; `paidFrom` naming a source with too little left (the rest automatic); `paidFrom` naming nothing; cash
   received with no category (never counted twice, never "covered"); a manual cash out with no receipt; the `cash`
   object (months and movements) over two months; the rename; and no receipts = identical numbers (the existing hash
   test, plus: the server's JSON gains no `cash` and no `cashWithdrawal`).

## Settled: do not re-open

- Withdrawals stay spending (their unaccounted rest), so people who never track cash keep correct totals (D8).
- The Cash page never counts in the totals. No exchange rates (euro only; other currencies: plan item 15).
- The engine stays pure; nothing joins or chooses by itself beyond the rules above.

## Out of scope

The app (brief 33), the server and its database, deploying.

## Done when

- `npm run typecheck`, `npm test`, `npm run engine` pass; the bundle's growth stated.
- Final message (plain English): files changed, test counts, the new and changed JSON shapes exactly as the app will
  use them (brief 33's second part is written from it), anything doubtful, what Claude must run (the byte-identical
  check on the server). Never commit, push, merge or deploy; never touch the server, any database or other repos.
