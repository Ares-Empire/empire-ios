# 78: A test set for reading bank files, with a score

Status: merged 2026-11-01 (aresium b7d3460; 228 files: 179 read right, 37 read wrong, 40 rows silently wrong, re-import ids kept in 123 of 159; test files stored as exact bytes, 6efc3cc)
Repo: **aresium** · Worktree: `../aresium-78-eval-files` (branch `codex/78-eval-files`) · Model: `gpt-6.1-sol`,
effort `high` · Runs beside brief 79 (the sorting test set, `eval/sorting/`); you own `eval/files/` only.

## Goal

Patrik (2026-11-01) wants Aresium approved for more testers, and before that, the reading of bank files and the
sorting made as good as we can, measured rather than guessed: "I think we generate different csvs and also some
custom difficult ones to test if the reading fails and if we can improve it."

Today the engine's readers (`src/engine/readers/`) are held to 46 clean files in real bank layouts
(`src/engine/fixtures/banks/`, made-up payments), whose expected answers were written by running the reader itself
(`scripts/bank-fixtures.ts`). That catches changes, not mistakes, and it never sees the files people actually have:
saved again by Excel, in another text encoding, cut off, from a bank we do not know.

This brief builds **a test set of hard bank files with answers that do not come from the reader**, and **a score**.
It measures only: no reader changes. Improvements come in later briefs, measured against this set.

## Read first

- `AGENTS.md` (no real data: everything here is made up), this brief.
- `src/engine/readers/` (`read.ts` `readBankFile`, `decode.ts`, `csv.ts`, `table.ts`, `guess.ts` for unknown banks,
  `bank-profiles.ts`, `profiles.ts`, `values.ts`, `types.ts`), `src/engine/bank-readers.test.ts`,
  `src/engine/readings.test.ts`, `src/engine/fixtures/banks/` and `scripts/bank-fixtures.ts`.
- How the app reports a file it cannot read (the error codes `readBankFile` throws, and the unknown-file window in the
  app is fed by them): a clear refusal is an acceptable answer, a silently wrong reading never is.

## Build

All under `eval/files/`, TypeScript run with `npx tsx`, no new packages.

1. **Where each answer comes from** (the point of this set; never from running the reader under test):
   - **From the original:** a file derived from one of the 46 fixtures by a change that must not change its payments
     has the original's payments as its answer (date, amount in cents with sign, currency, counterparty, text; the
     original's `.expected.json` is the reference for what the payments are).
   - **By construction:** a file of a made-up bank is written from rows the generator made first; those rows are the
     answer.
   - **Written by hand:** for a file that must be refused or read in part, the case states the outcome (refuse with
     which error, or which rows and which warning), with one line why.
   Where today's reader does something wrong, the answer is the right outcome, not today's: the set must show
   today's failures.
2. **Hard files**, each with one line saying when this happens in real life. Aim for about 150 to 250 files, spread
   over the banks; a seeded, repeatable generator (`eval/files/make.ts`) writes them to `eval/files/cases/` with one
   `<name>.case.json` beside each (where the answer came from, the change made, the expected outcome). At least:
   - **Encodings and line ends:** UTF-8 with and without BOM, Windows-1252 and ISO-8859-1/-15 (umlauts, €, ß),
     UTF-16 LE with BOM (Excel's "Unicode text"), CRLF / LF / CR alone, no line end after the last row.
   - **Saved again in Excel and Numbers (German and English settings):** separator changed (`;` ↔ `,` ↔ tab), quotes
     dropped or added, dates rewritten (`14.10.2026` → `14.10.26`, `2026-10-14`, `10/14/2026` with English settings),
     amounts rewritten (`-1.234,56` → `-1234,56`, `-1234.56`, `-1,234.56`), empty columns at the end (`;;;`), empty
     rows at the end, a summary or total row added at the bottom.
   - **Banks' own variations:** extra lines before the header (account, period, balance), a section per account in
     one file, debit and credit in two columns (`Soll`/`Haben`), an `S`/`H` column, a minus at the end (`12,34-`),
     amounts with `EUR` in the cell, multi-line quoted purpose texts, a quote inside a text, very long purpose texts.
   - **Unknown banks** (made up, realistic German and English headers, about 30 files): different words for the
     columns (`Buchungstag`/`Valuta`/`Wertstellung`, `Betrag`/`Umsatz`, `Empfänger`/`Auftraggeber`/
     `Zahlungspflichtiger`/`Name`, `Verwendungszweck`/`Buchungstext`/`Beschreibung`), different date and amount
     styles, columns in another order, a currency column.
   - **Must not be read as payments:** a CSV that is not a bank file (contacts, a shopping list, a budget sheet with
     amounts and dates), a header with no rows, an empty file, an XLSX or PDF renamed `.csv`, a file cut off in the
     middle of a row, a row with a broken quote, mixed currencies where the reader cannot tell them apart.
   - **Re-import:** the same payments saved again by Excel must keep the same payment ids, or Aresium would show them
     twice. Record per derived file whether the ids equal the original's (measured only; ids of existing imports must
     never change, so a fix here is a later decision).
3. **The score** (`npm run eval:files`, `eval/files/score.ts`): runs `readBankFile` (the source by default; with
   `--engine <path>` a bundled `dist/aresium-engine.js`, as `scripts/check-shop-sorting.ts` loads one) over every case
   and prints:
   - files read right / refused (as expected or not) / **read wrong**;
   - **rows silently wrong**: a payment with a wrong date, amount, sign, currency or counterparty, a missing or an
     extra payment, in a file that was read without an error (the number that must reach 0);
   - re-import ids kept: n of m;
   - a table by kind of change and by bank, then each failing file with what differed (first few rows only).
   `--record` appends one line to `eval/history.csv` (date, git commit, `files`, the headline numbers), creating it
   with a header when missing (brief 79 writes `sorting` lines to the same file).
4. **`eval/files/README.md`**: what the set tests, where answers come from, how to add a case, how to run and record.
5. `package.json`: the `eval:files` script. `.gitignore`: anything the score writes besides `eval/history.csv`.

## Settled: do not re-open

- Measure only: no change to the readers, the fixtures in `src/engine/fixtures/` or their tests.
- An answer never comes from the reader under test.
- A clear refusal is fine; a silently wrong reading is the worst outcome.

## Out of scope

- Sorting (brief 79), receipts (later, with real photos), the app.

## Done when

- `npm run typecheck`, `npm test`, `npm run engine` pass; `npm run eval:files` runs and prints the first numbers.
- Tests for the score itself (`eval/files/*.test.ts`; `npm test` covers only `src/`, so run them with
  `npx tsx --test eval/files/*.test.ts`; Claude adds `eval/` to `npm test` after merging; the typecheck already
  covers `eval/`): a right file, a refused file, a silently wrong row, a missing row, a changed id are each counted right.
- Nothing real: banks' header lines and layouts are real, every payment, name and IBAN is made up (IBANs as the
  existing fixtures make them).

## Final message

As in `AGENTS.md`: files changed, the exact check results, **the first score in full** (the headline numbers and the
table by kind), the five most important failures you see and what you think causes each (do not fix them), anything
doubtful. Never commit, push or merge: Claude does.
