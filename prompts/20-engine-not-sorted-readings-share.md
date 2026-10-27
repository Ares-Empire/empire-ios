# 20: Engine: "Not sorted" counts only money out; several readings of an unknown file; a format people can share

Status: merged 2026-10-27 (aresium.de deployed: real data 1 payment, 7.94 EUR in one month; the app has the new engine)
Repo: aresium · Worktree: `~/aresium-20-readings` (branch `claude/20-readings`) · Built by: a Claude agent

## Goal

Three engine pieces for Aresium for other people (plan: `~/ares-empire/docs/ARESIUM-FOR-OTHERS.md`). The app work
that uses them comes after (a later brief); here only the engine (`src/engine/`, `src/data/dashboard.ts`), its tests
and the bundle.

## Read first

`AGENTS.md`; `src/data/dashboard.ts`; `src/engine/source.ts` (`UNCATEGORISED`, kind "spend"); `src/engine/readers/`
(`types.ts`: `CsvLayout`, `LayoutGuess`; `guess.ts`; `read.ts`; `bank-profiles.ts`, `profiles.ts`); `src/engine/index.ts`
(what the app may call); the engine tests and fixtures.

## Build

1. **"Not sorted" is money out only.** Today a payment without a category is in `Uncategorised`, kind "spend", so
   money coming in that is not sorted yet (a salary from an unknown employer, a friend paying back) lowers spending,
   counts as income ("Other") at the same time, and when money in exceeds money out in a month, that month's
   "Uncategorised" spend is ≤ 0 and the app's category screen shows "No activity recorded" (Patrik hit this,
   2026-10-27). Change: an `Uncategorised` payment with amount > 0 is not spending (not in `total.expense`, the month's
   expense and day values, the `Uncategorised` spend series, or its `categoriesIn`), only income in "Other" as now.
   Money out without a category stays spending. Refunds inside real spend categories keep today's behaviour (they
   lower that category; settled). Tests: a month with +150 unsorted in and −20 unsorted out shows 20 spent in Not
   sorted and 150 income in Other; the expense total is not lowered by the 150. This changes aresium.de's numbers a
   little (Patrik's own unsorted money in): say so in your final message; Claude measures it on the server.
2. **Several readings of an unknown file.** For a CSV whose layout is not known, the app will show the first few
   payments as they would appear and ask "Does this look right?"; on "No" it shows the next reading. Add
   `readingsOfUnknownFile(bytes, savedLayouts?)` (exported from `index.ts`): up to 4 complete `CsvLayout`s, best
   first, each with its first 5 payments read (`preview`: date, the other party, text, amount, as `readBankFile`
   gives them) and a short machine reason of what differs from the first (`"dateFormat"`, `"sign"`, `"debitCredit"`,
   `"counterpartyText"`, `"valueDate"` …). Build the alternatives from what `guessCsvLayout` is unsure about (day
   and month swapped, debit/credit the other way, counterparty and text swapped, booking and value date swapped, a
   sign column); leave out a reading whose preview equals an earlier one; never return a reading that fails to
   read the file. Known profiles and saved layouts still win before this is ever called. Tests with made-up files
   (an ambiguous date file 03/04/2026, a debit/credit file, swapped name/text).
3. **A format people can share.** `shareableLayout(layout)` returns a copy of a `CsvLayout` that is safe to send to
   us: no `name`/`profile`, and only if no header cell or status word looks like personal data (an IBAN or account
   number, an email address, a date, an amount, a run of 5+ digits, a person's name is not detectable: a header cell
   longer than 40 characters is refused too). When something looks personal, return `{ ok: false, reason }` instead
   of sending less: a layout with a blanked header would not recognise the next file. Output shape:
   `{ ok: true, layout: CsvLayout }` (JSON, `version: 1`). And the way back for Claude:
   `scripts/add-shared-layout.ts <file.json> --name "Bank name" --id some-id` prints a `bank-profiles.ts` entry
   (and the test fixture header) for a submitted layout, so adding a bank someone sent is one command plus a review.
   Tests: every profile in `bank-profiles.ts` passes `shareableLayout` (they are generic), a layout whose header holds
   an IBAN or a date is refused.

## Settled: do not re-open

- No AI, nothing leaves the phone in the engine. Payment ids never change. Known profiles before guesses.
- Server mode (aresium.de) keeps working; the only number change is item 1.

## Done when

`npm run typecheck`, `npm test`, `npm run engine` pass. Final message: what changed, test counts, the new exports and
their JSON shapes (the app brief uses them), and what Claude must run on the server to measure item 1. Never commit,
push, merge or deploy; never touch the server, any database or other repos. No real data: there are no real payments
on this Mac and you must not look for any.
