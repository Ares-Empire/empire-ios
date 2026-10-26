# 12: Engine: the dashboard source, PayPal and own transfers, and the mode route

Status: merged 2026-10-27 (parity on the real database: identical, 1,246 payments)
Repo: aresium · Worktree: `~/aresium-12-engine-source` (branch `claude/12-engine-source`) · Built by: a Claude agent

## Goal

Phone mode (other people's data on their iPhone) needs every step from stored payments to the finished dashboard in
the shared engine, and the app must learn from the server whether an account uses server mode (Patrik) or phone
mode (everyone else). Today the step "payments in the database → dashboard source" lives in the database code
(`src/data/queries.ts` → `getDashboardSource`), and the PayPal handling sits next to it. Move it into the engine
without changing a single number on aresium.de, add the two transfer rules the measurements asked for, and add the
mode route.

## Read first

`AGENTS.md` (rules), the plan's part 1 ("One app, two modes"), part 3 ("Several accounts per person"), and the
Measurements results ("Main error source in all layers": the PayPal lines). Code: `src/data/queries.ts`
(`getDashboardSource`, `isPaypalBankFunding`, `CAT_META`, `fetchWithCategory`), `src/data/paypal-fx.ts`,
`src/data/dashboard.ts`, `src/engine/index.ts`, `src/engine/sorting/sort.ts`, `src/engine/categories.ts`,
`src/web/server.ts`, `src/web/empire-auth.ts`, and their tests.

## Build

1. **`src/engine/source.ts`:** `buildDashboardSource({ transactions, categories, today })` → `DashboardSource`, pure:
   everything `getDashboardSource` does after fetching (dropping PayPal funding rows, folding PayPal currency
   conversions, income/spend/transfer kinds, the Uncategorised entry, months with the current one partial, balance by
   day, opening balance, `databaseCategoryNames`). `today` is an ISO date passed in (no clock in the engine). Its input
   types are plain JSON (dates as ISO strings, amounts as numbers, a category with name, icon, colour and
   `excludeFromTotals`); icons and colours come in with the categories (`CAT_META` stays on the server and is applied
   there before the call). Move `foldPaypalConversions` and the PayPal funding test into the engine with it.
2. **The server uses it:** `getDashboardSource` fetches, maps rows to the engine's input and calls
   `buildDashboardSource`. Keep the old body as `getDashboardSourceLegacy` for now, plus
   `scripts/check-source-parity.ts`: computes both from the real database (read only) and prints only "identical" or
   the number of differing keys (never values). Claude runs it on the server; after "identical" Claude deletes the
   legacy function.
3. **PayPal rule in sorting:** a person who imports both their bank and their PayPal export has each PayPal purchase
   twice: once in the PayPal export (with the shop) and once as the bank's PayPal line (the money moving into PayPal).
   When the person's payments include PayPal export rows, a bank line whose counterparty or text is PayPal (the
   patterns the server uses: "paypal europe", "paypal (europe" and similar) is an **own transfer**
   (`own-transfers`), before learned and starter rules. Without PayPal export rows nothing changes (then the bank line
   is the only record of the purchase). Put it in `sortPayments` as a structural step with its own `source`
   (`structural`), with tests both ways.
4. **Own transfers between accounts:** when the person has two or more accounts, a pair of payments with the same
   absolute amount, opposite signs, on different accounts, within 3 days, is an own transfer on both sides (also
   `structural`). Each payment pairs at most once; ties go to the closest dates. Tests, including two equal
   transfers on the same day and a near-match that must not pair.
5. **Mode route:** `GET /api/mode` → `{"mode":"server"}` for an account in `EMPIRE_ALLOWED_USERS` (Patrik),
   `{"mode":"phone"}` for any other approved account with the `aresium` service, 401 without a valid login, 403
   (`no_access`) without the service. This is the only route that does not require the owner list; every other route
   keeps its check. It stores and logs nothing about the account. Document it in `docs/API-DATA.md`.
6. **Export** `buildDashboardSource` and the transfer step from `src/engine/index.ts`; the bundle grows by them.

## Settled: do not re-open

- aresium.de's numbers must not change (the parity check decides). Payment ids never change.
- The bank-side PayPal rule applies only when PayPal export rows are present.
- No change to the dashboard builder (`buildDashboard`) itself, to the app, or to other repos.

## Done when

`npm run typecheck`, `npm test` (with the new tests), `npm run engine` pass; `scripts/check-source-parity.ts` exists
and runs against a made-up database shape in a test (no real database here); the final message says exactly what
Claude must run on the server.
