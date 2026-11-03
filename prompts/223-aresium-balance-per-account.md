# 223: A balance that matches the bank, account by account

Status: merged + deployed 2026-11-03 (aresium aaf3443; 638 tests; real data: only balances changed, 0 uncertain account-days); in the app with build 21 (brief 227). Open: a check against the bank files on the Mac.
Branch: `codex/223-balance` (repo `aresium`) · Worktree: `~/aresium-223-balance` · Model: `gpt-6.1-sol`, effort `high`

## Goal

The balance line (`byMonth[m].dayBalance`, `overview.balance`) is not reliable, on the website and in the app (both
use the shared engine). Brief 222's read-only answer (`~/empire-ios/codex-runs/222-balance-answer.md`, read it) found
why: on a day with several payments the last balance met wins, and same-day order is not fixed (by date only before
218, by import time and id now), so the two versions pick different payments and differ by up to 1,557 € on the
owner's real data; balances are read after the PayPal funding filter, so a closing row can be dropped; and all
accounts are mixed into one "last balance" instead of being added up. After this brief each day's balance is what the
accounts actually held at the end of that day, whatever order the rows are stored in.

## Build

1. **Per account:** keep the account of each booking through the adapter (`src/data/queries.ts` drops `accountId`
   today) into the engine's source, and calculate balances from all of an account's bookings with a balance, before
   any filtering for spending (transfers, funding, exclusions do not touch the balance).
2. **A day's closing balance without relying on row order:** within one account and one day, the bookings form a
   chain (balance before = balance after minus amount). The closing balance is the end of that chain. Use the
   statement's own order where it is stored; otherwise derive it from the chain. Where the chain does not close
   (missing rows, two candidates), take the stored order and record the day as uncertain in the result, never guess
   silently.
3. **Carry forward and add up:** each account carries its last closing balance over days without bookings; the day's
   balance is the sum of the accounts that have one. Before an account's first booking with a balance it counts as
   unknown, not zero; days before any account is known are unknown (`null`), as the chart already handles.
4. **The same in the app:** the engine change reaches the iPhone app through `npm run engine`; say in the final
   message what the app must update (Claude builds it).

## Settled

- `/api/data` keeps its fields and shapes; only the balance values change (plus an optional field listing uncertain
  days, if you add one: document it in `docs/API-DATA.md`).
- Same results first: spending, income, categories, totals and every other field must stay identical. Add a test
  that runs the existing fixtures through old and new and asserts only the balance fields differ.
- Readable code in the existing style (lines under about 120 characters, one statement per line). No real data.

## Done when

`npm run typecheck`, `npm test` and `npm run engine` pass, with brief 222's proving test: opening 1,000 €, same-day
debits 100 € then 50 €, closing 850 €; stored in shuffled order the day and the following days stay at 850 €;
plus an excluded transfer, a PayPal funding row and a second account (summed). Final message as in `AGENTS.md`, plus
the exact script Claude runs on the server to check the new balances against the bank files' own balances per day.
