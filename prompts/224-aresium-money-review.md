# 224: Aresium's numbers: find and fix flaws like the balance bug

Status: merged + deployed 2026-11-03 (aresium; 647 tests; real data: 1,246 payments, no field changed). Three fixes: one Uncategorised row, category sides in whole cents, today as Berlin's day. Open: PayPal cross-format duplicates (not proven).
Branch: `codex/224-money-review` (repo `aresium`) · Worktree: `~/aresium-224-money-review` · Model: `gpt-6-astra`,
effort `high`

## Goal

On 2026-11-03 the balance line turned out to have been wrong for weeks, on the website and in the app: the result
depended on the order rows happened to be stored in, and two accounts were mixed into one number (briefs 222, 223).
Nobody noticed because every test passed. The owner decides with these numbers. Find other flaws of that kind in how
Aresium counts money, prove each with a failing test on made-up data, and fix the proven ones.

## Read first

`AGENTS.md`, `docs/API-DATA.md`, `docs/BALANCE-CHECK.md`, `src/engine/` (counting, not the bank readers or sorting
rules), `src/data/`, and the briefs `~/empire-ios/prompts/218-*`, `223-*` and `~/empire-ios/codex-runs/222-balance-answer.md`.

## Look for

- Results that depend on stored or import order, or on object key order.
- Money counted twice or not at all: transfers between one's own accounts, PayPal funding and conversions, refunds
  and reversals (Storno), money paid back (one and several), receipts and cash joined to bank payments, the same
  payment from two file formats.
- Days and months: timestamps cut to a date in UTC instead of Europe/Berlin, bookings near midnight, month and year
  ends, summer time changes, 29 February, the current unfinished month.
- Euros as floating-point numbers: sums that drift by a cent, rounding in averages and shares.
- The monthly average and fixed costs: unfinished months, ended or paused subscriptions, price steps.
- Anything where the website (server) and the app (engine bundle) would show different numbers for the same data.

## How

For every suspicion write the failing test first. Fix only what a test proves, in the place the rule belongs; every
other number stays identical (show it with the existing fixtures before and after). Small, separate fixes; readable
code in the existing style (lines under about 120 characters). No real data.

## Done when

`npm run typecheck`, `npm test`, `npm run engine` pass.

## Final message

1. Proven and fixed: what was wrong, a made-up example with the wrong and the right number, file and line, the test.
2. Suspected but not proven, and why.
3. Checked and sound.
4. A script Claude runs on the server that compares the dashboard before and after on the real data (as on
   2026-11-03: everything identical except the fields your fixes are meant to change).
