# 71: Every payment counts as it happened: the engine

Status: merged 2026-11-01 (aresium 62ff840, website sample fbfb742; 400 engine tests; in the app with 661 tests, empire-ios merge of claude/71-engine-in-app). Not deployed to the server
Repo: **aresium** · Worktree: `../aresium-71-as-it-happens` (branch `codex/71-as-it-happens`) · Model: `gpt-6.1-sol`,
effort `high` · Claude copies the engine into the app and adjusts the app's tests afterwards.

## Goal

Patrik (2026-11-01), asked how money paid back should count: "booking everything as it happens is clearer and more
truthful. Plus in the other way errors are worse. So while returns and refunds are kinda weird with the expense 100
income 100 I do think doing it that way is best overall and easier because we dont rely on matching."

Today money in under a spending category (a shop's refund, a friend paying back) is used twice: it lowers that
category's spending **and** counts as income (the `Refunds` bucket). After this brief **every payment counts once, in
the direction it went**: money out is spending, money in is income, each listed under its own category. Nothing is
subtracted from anything. A returned €100 order shows €100 spent and €100 in, both under its category.

The categories' sides (brief 68) stay, but only decide where a category is **offered** (`pick`), no longer where its
money counts.

## Read first

- `AGENTS.md`, `docs/API-DATA.md` (the rules this changes), `prompts/68-aresium-category-sides-engine.md` (just merged:
  its item 5 is replaced here).
- `src/data/dashboard.ts` (`buildDashboard`: the transaction loop, `categoriesIn`, buckets, `categoryRows`,
  `incomeRows`, `INCOME_META`), `src/engine/source.ts`, `src/engine/receipts/count.ts` (covered rows), `src/data/pulse.ts`,
  their tests.

## Build

1. **Money out** (amount < 0), not a transfer: counts as spending, the headline (`expense`, the month's, `dayExpense`,
   the running line) and each category it is in (primary and tags, `categoriesIn`), whatever the category's kind
   (an income category with money out is listed under spending with that money). Unsorted money out stays "Not
   sorted" spending, as today.
2. **Money in** (amount > 0), not a transfer: counts as income, the headline (`income`, the month's, `dayIncome`) and
   an income row under its own category's name (primary and tagged categories, whatever their kind); unsorted money in
   is `Other`, as today. It never lowers any spending. The `Refunds` bucket is no longer made (keep `INCOME_META.Refunds`
   only if something else still needs it; say so).
3. **The one exception: cash covered by receipts.** A withdrawal's covered row (`coveredBy`, `receipts/count.ts`) is not
   money in: it moves cash spent with a receipt from the withdrawal to the receipt's category, so it keeps lowering the
   withdrawal's spending and is never income. Nothing else may lower spending.
4. **Lists follow the same rule:** a payment's `categoriesIn` (the spending lists it shows in) holds categories only for
   money out (and the covered rows, item 3); its `incomeBuckets` names its income rows only for money in. So a
   category's spending list sums to its spending, and its income list to its income. Brief 68's money out in
   `incomeBuckets` goes.
5. **Rows and series:** spending rows and series per category from money out only, income rows and series per
   category from money in only. Rows show only totals above 0, series are never below 0 (as now). A category can have
   both a spending and an income row in the same month.
6. **What stays:** transfers count nowhere; tags list a payment in more places but never count it twice in a headline
   figure; `pick` and `otherSide` as brief 68 made them (sides only decide where a category is offered); cash entries
   received count as income, spent ones as spending; the balance.
7. **The pulse** (`src/data/pulse.ts`) and anything else that read the netted numbers follow the same rule; a test
   that pinned a refund lowering spending changes to the new numbers.
8. **Docs:** `docs/API-DATA.md`: "Rules the server applies" rewritten for this (counted as it happened, the covered
   exception, income rows by category, no `Refunds`), plain English.

## Settled: do not re-open

- No netting of money in against spending, except the covered cash rows. Patrik chose this knowing returns show as
  spent and received.
- Income rows are named by the payment's own category (one rule), not grouped under `Refunds`.
- Sides decide menus only.

## Out of scope

- The app (Claude), the server's deploy, the sorting, receipts' matching.

## Done when

- `npm run typecheck`, `npm test` and `npm run engine` pass.
- Tests: a refund in a spending category counts as income under that category and leaves its spending as it was; a
  friend's payback in Friends (a spending category with `otherSide`) likewise; money out in an income category is
  spending under that category; a covered withdrawal still lowers its spending and is not income; a category with both
  directions in one month has both rows; `categoriesIn` and `incomeBuckets` follow the direction; tags count once in the
  headline; transfers count nowhere; the headline income equals all money in except transfers and covered rows, the
  headline expense all money out except transfers minus covered rows.

## Final message

As in `AGENTS.md`: files changed, the exact check results (test counts), what changed in the sample dashboard
(`dist/dashboard.sample-source.json` through `buildDashboard`, before and after), anything doubtful. Never commit,
push or merge: Claude does.
