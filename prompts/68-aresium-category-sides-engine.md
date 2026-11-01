# 68: Every category has a side: the engine

Status: merged to aresium main 2026-11-01 (7b26812; 399 tests; the server sample changes only as asked: transfers in pick.spend, one tagged payment given back lowers its income row). Not deployed: the server is not used by the app (server mode empty)
Repo: **aresium** · Worktree: `../aresium-68-category-sides` (branch `codex/68-category-sides`) · Model: `gpt-6.1-sol`,
effort `high` · The app's side follows in brief 69 (a Claude agent wires it into empire-ios).

## Goal

Patrik (2026-11-01): his own categories must work for money in too, and a category that is mainly spending but also
gets money back (Freunde: a friend pays back their share) must be offered for money in without becoming income.

Today a category's side is decided by its money (`buildDashboardSource`, `src/engine/source.ts`: `kind` is `income`
when the category's payments add up to more money in than out, otherwise `spend`). That has three effects:

- A new or empty category is always `spend`, so it is never offered for money in (`pick.income`), even an income
  default such as "Selling things" before its first sale, while a purchase can be moved into it.
- A spending category that got more back than it spent (Friends) flips to `income`: it leaves the spending list and
  its money shows as income.
- Money out in an `income` category is counted nowhere: not as spending (only `spend` categories are), not as income
  (only amounts above 0 are).

After this brief the caller can give each category its **side** (`spend` or `income`; transfers stay
`excludeFromTotals`) and can mark it **offered on the other side too**. The engine counts money by that side, builds
the two choice lists (`pick.spend`, `pick.income`) from it, and counts money out in an income category as money given
back. Without a side the engine keeps today's rule, so the server's dashboards stay as they are.

## Read first

- `AGENTS.md` (this repo), `docs/API-DATA.md` ("Rules the server applies", the income buckets), and
  `~/ares-empire/docs/ARESIUM-FOR-OTHERS.md` (phone mode, categories).
- `src/engine/source.ts` (`SourceCategory`, `buildDashboardSource`, the `kind` line), `src/data/dashboard.ts`
  (`Category`, `buildDashboard`: `incomeKeep`, `incomeBucketKeep`, the transaction loop, `categoryRows`,
  `incomeRows`, `pick`), `src/engine/categories.ts` (each default's `kind`), and their tests
  (`src/engine/source.test.ts`, `src/data/dashboard.test.ts`, `src/engine/receipt-dashboard.test.ts`).

## Build

1. **The input.** `SourceCategory` gets two optional fields:
   - `side?: "spend" | "income"`: the category's home side. Ignored when `excludeFromTotals` is true (a transfer stays
     a transfer). Without it: today's rule from the category's net.
   - `otherSide?: boolean`: also offered for the other direction of money (money in for a spending category, money out
     for an income category). Ignored for transfers (they are offered both ways anyway, item 3).
2. **The output.** `buildDashboardSource` sets each `Category`'s `kind` from `side` when given. `Category` gets an
   optional `otherSide?: true`, set only when the input says so, so a source without the new fields serialises
   exactly as before (the server's JSON and `dist/dashboard.sample-source.json` stay byte-identical for their inputs;
   check it).
3. **The choice lists** (`pick`, the lists the app's change window offers):
   - `pick.spend` (money out): `spend` categories, then transfer categories, then `income` categories with
     `otherSide`.
   - `pick.income` (money in): `income` categories, transfer categories and Tax, as today, then `spend` categories
     with `otherSide`.
   - Each part keeps today's order (the all-time rows of its own side first, the rest alphabetically); the other
     side's categories come last, in the order of their own side's rows, then alphabetically.
   - Transfers in `pick.spend` are new for everyone, the server too: money moved to one's savings could not be moved
     into "Savings & investing" or "Own transfers" by hand. Update the test that pins `pick.spend` to `spend` only.
4. **Money in a spending category** stays as today: it lowers that category's spending, and its money is listed
   under the `Refunds` income bucket. Do not change this here (Patrik decides separately whether paid-back money
   should also count as income).
5. **Money out in an income category** is money given back (a salary paid back, a refund to a buyer). It lowers that
   category's income, mirroring item 4:
   - The headline income (`total.income`, the month's `income`, `dayIncome`) goes down by it; it is never spending.
   - The category's income series and rows go down by it. Its series never go below 0 and its rows show only
     totals above 0, as `spend` series and rows already do; the headline totals are not clamped (as `expense`).
   - The transaction's `incomeBuckets` names the category, so it is listed under that income row.
   - Tagged ("Add") income categories on money out: the same, for each tagged income category.
   - Transfers, cash covered by receipts and unsorted payments keep their own rules.
   Today this money is counted nowhere; with the net rule it can happen on the server too (an income category whose
   net is above 0 that also has money out), so the server's numbers change in that case only. That is the fix. Say in
   your final message how to find such payments, so Claude can count them on real data.
6. **Docs:** `docs/API-DATA.md`: the two new fields, the pick lists, money out in an income category. Plain English,
   the file's style.

## Settled: do not re-open

- The side is the caller's (the app knows each default's side from `categories.ts` and asks the person for their own
  categories). The engine does not look up default ids: `SourceCategory` is by name.
- A category has one home side for its totals; `otherSide` only widens where it is offered, it never moves the money
  to the other side's totals.
- No side given means today's behaviour, exactly.

## Out of scope

- The sorting (`src/engine/sorting/`), the shop list, receipts and cash rules, the server's database and routes, the
  web pages. No deploy.
- Whether `Refunds` counts as income (item 4).
- The app (brief 69).

## Done when

- `npm run typecheck`, `npm test` and `npm run engine` pass.
- New tests: a given side wins over the net (an empty income category is `income`, a spending category with more
  money in than out stays `spend`); `otherSide` puts a category in the other list, after that list's own categories,
  and never into the other side's totals; transfers are in both lists; money out in an income category lowers its
  income (headline, month, day, series not below 0, rows above 0 only, `incomeBuckets`), also as a tag; a source
  without the new fields gives exactly today's dashboard (compare against `dist/dashboard.sample-source.json` and the
  existing fixtures).

## Final message

As in `AGENTS.md`: files changed, the exact check results (test counts), how Claude finds payments affected by item 5
on real data, anything doubtful. Never commit, push or merge: Claude does.
