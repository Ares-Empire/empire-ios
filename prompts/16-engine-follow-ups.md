# 16: Engine follow-ups: stricter own transfers, English PayPal, the bench sees the whole list

Status: draft
Repo: aresium · Worktree: `~/aresium-16-follow-ups` (branch `claude/16-follow-ups`) · Built by: a Claude agent

## Goal

Three small fixes the earlier briefs found (plan: `~/ares-empire/docs/ARESIUM-FOR-OTHERS.md` → "Engine follow-ups"
1, 3 and 4). Precision first: a wrong "own transfer" hides real spending or income.

## Read first

`AGENTS.md`; the plan's "Engine follow-ups"; `src/engine/sorting/transfers.ts`, `src/engine/sorting/sort.ts` and their
tests; `src/engine/readers/` (types, profiles, `read.ts`, `camt.ts`, `mt940.ts`); `src/engine/paypal.ts`;
`bench/run.ts`, `bench/data.ts`, `bench/export.ts`.

## Build

1. **The other party's IBAN in reader output:** `readBankFile` results carry `counterpartyIban` (optional, normalised:
   no spaces, upper case) wherever the format has it: the profiles' `iban` column, CAMT's related party account
   (`DbtrAcct`/`CdtrAcct`), MT940's `:86:` `?31`. The server's own readers and their ids stay unchanged (the field is
   added in the engine's wrapper, not in `src/import/`).
2. **Own transfers between accounts need proof** (follow-up 1): a pair counts only when one side's `counterpartyIban`
   is the other payment's account IBAN (either direction), or both sides' texts say it themselves ("Umbuchung",
   "Übertrag", "Eigenübertrag", "Kontoübertrag", "own account"/"eigenes Konto"). Equal amounts alone no longer pair.
   Tests: the unrelated 20.00 purchase and a friend's 20.00 do not pair; a Girokonto → Tagesgeld move with the IBAN
   does; two equal moves on one day pair one-to-one.
3. **English PayPal exports** (follow-up 4): their funding rows ("Bank Deposit to PP Account", "General Card Deposit",
   and the other English funding types PayPal uses; name your source) are left out like the German ones. Patrik's
   exports are German, so aresium.de's numbers do not change: prove it with a test on the German fixtures (unchanged
   output).
4. **The bench sees the whole list** (follow-up 3): `bench/run.ts` sorts with one `sortPayments` call over all payments
   up to the point in the replay (so structural rules run), keeping its privacy rules (only totals, category names and
   months in the output). `bench/export.ts` adds what the structural rules need (source, account, and the counterparty
   IBAN if stored; the database has the raw row, so take it from there only if it is already parsed: otherwise leave
   it out and say so). Tests with fake data where a PayPal line and an own transfer are sorted structurally.

## Settled: do not re-open

- Precision before recall for own transfers. No change to aresium.de's numbers. Payment ids never change.

## Done when

`npm run typecheck`, `npm test`, `npm run engine` pass; `npx tsx bench/fake-data.ts && npx tsx bench/run.ts` runs;
the final message says what Claude must run on the server to measure again.
