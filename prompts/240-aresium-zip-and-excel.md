# 240: Reading ZIP and Excel bank files

Status: merged 2026-11-07 (aresium 5a4fb3c; files 231 -> 246, read right 215 -> 223, nothing wrong; app: .xlsx type and new codes in the app)
Repo: **aresium** · Worktree: `../aresium-240-zip-and-excel` (branch `codex/240-zip-and-excel`) · Model: `gpt-6.1-sol`,
effort `high` (picked 2026-11-07: well-defined format work with clear tests; the frontier model is not needed) · Runs
beside brief 239 (sorting, `src/engine/sorting/`); you own `src/engine/readers/` and `eval/files/`.

## Goal

Two kinds of bank file are refused today. **ZIP:** Sparkassen (Germany's most common bank) and others hand out CAMT
statements as a ZIP of XML files, one per statement day. The engine stops at the ZIP's first bytes (`read.ts`,
`PK\u0003\u0004` → code `zip`) and the app says "Unzip the file first", which most people cannot do on an iPhone without
help. **Excel:** an `.xlsx` (a bank's Excel export, or a CSV opened and saved in Excel) is also a ZIP, so it gets the
same wrong message. After this brief both are read like any other bank file, on the server and in the iPhone app (the
same engine, bundled for JavaScriptCore).

## Read first

- `AGENTS.md`, `eval/files/README.md`, `src/engine/readers/` (`read.ts`, `decode.ts`, `csv.ts`, `table.ts`, `camt.ts`,
  `mt940.ts`, `profiles.ts`, `bank-profiles.ts`, `ids.ts`, `types.ts`), `src/engine/bank-readers.test.ts`, brief 85
  (`~/empire-ios/prompts/85-aresium-reading-round-1.md`: its rules hold), `scripts/build-engine.ts` (the bundle check).
- How the app shows an error code: `~/empire-ios/Aresium/Aresium/Model/PhoneBackend.swift` →
  `ImportWording.bankFileProblem` (read only; Claude changes the app).

## The rules of this round

- **Payment ids of existing imports never change.** Every fixture keeps its `.expected.json` byte for byte. A CAMT file
  read from inside a ZIP gives exactly the ids it gives alone. An `.xlsx` saved from a known bank's CSV gives the ids
  the CSV gives (same account, date, amount, text), so importing both shows nothing twice; where that cannot hold, say
  why.
- Existing eval cases stay byte for byte (the seed-78 test must still pass); new cases are added beside them.
- A doubtful reading goes to the person (the readings, the column check), never silently into the payments.

## Build

1. **Unzip in the engine.** You may add **`fflate`** (MIT, pure JavaScript, no Node built-ins), pinned to an exact
   version; nothing else new. `npm run engine` must still bundle and pass its check. Safety limits: refuse encrypted
   entries, follow no nested ZIP, ignore `__MACOSX/` and dot files, and cap the total unpacked size and the number of
   entries (choose sensible numbers, e.g. 50 MB and 2,000, and test a file that exceeds them).
2. **A ZIP of bank files.** Read each entry that is a bank file (CAMT, MT940, CSV) with the existing readers. Entries of
   one account become one `BankFile`: payments in date order, a booking that appears in two entries (overlapping
   statements, camt.052 next to camt.053) kept once by its id. Entries of more than one account: refuse with a clear
   code (today one `BankFile` holds one account; do not change that). A ZIP with no bank file in it: refuse with a
   clear code. An `.xlsx` inside a ZIP is not followed.
3. **Excel (`.xlsx`).** Tell it from a plain ZIP by its contents (`[Content_Types].xml`, `xl/workbook.xml`). Read the
   first worksheet that holds a table (shared strings, inline strings, numbers, booleans; empty cells kept in their
   column), turn it into rows and hand them to the existing table path, so known banks are recognised by their header
   as from a CSV and unknown ones get the layout guess. Dates stored as serial numbers with a date format become dates
   (the 1900 and 1904 date systems); amounts stored as numbers become exact decimal strings without float noise
   (`-12.3` stays `-12.30` where the column is money).
4. **Old Excel (`.xls`, the `D0 CF 11 E0` header):** do not read it; refuse with a clear code that says to export as
   CSV or save as `.xlsx`.
5. **Error codes.** Reuse the existing codes where they fit. Every new code goes into `BankFileErrorCode` with an
   English message as the others have, and is listed in your final message so Claude adds its text to the app.
6. **Test set.** Add constructed cases to `eval/files` (`make.ts` may use `fflate` to write them): a Sparkasse-style
   CAMT ZIP with several days and one overlapping booking, the same with `__MACOSX` entries, a ZIP of one CSV, a ZIP
   of two accounts (refuse), a ZIP with no bank file (refuse), an oversized one (refuse), an encrypted one (refuse);
   `.xlsx` versions of at least three known banks' CSVs (dates as serial numbers, amounts as numbers), one unknown
   layout as `.xlsx`, one `.xls` (refuse). Report the score before and after; the old cases' numbers must not move.

## Settled: do not re-open

- Silently wrong is worse than a refusal. Ids of existing imports never change. One `BankFile` holds one account.

## Out of scope

- Sorting (brief 239), the app (Claude adds `.xlsx` to the file types and the new codes' words), the server's upload
  route.

## Done when

- `npm run typecheck`, `npm test` and `npm run engine` pass; every fixture's answer is unchanged; new behaviour has
  tests, including the limits.
- `npm run eval:files` before and after in the final message.

## Final message

As in `AGENTS.md`: files changed, the exact check results, the score before and after, the new error codes with their
messages, the limits chosen, anything doubtful (above all anything touching ids). Never commit, push or merge: Claude
does.
