# 85: Reading bank files, improvement round 1

Status: merged 2026-11-01 (see the merge commit in aresium)
Repo: **aresium** · Worktree: `../aresium-85-reading-round-1` (branch `codex/85-reading-round-1`) · Model:
`gpt-6.1-sol`, effort `high` · Runs beside brief 84 (sorting, `src/engine/sorting/`); you own `src/engine/readers/`.

## Goal

Brief 78's test set of hard bank files has its first numbers (`npm run eval:files`): 179 of 228 files read right, 37
read wrong, **40 payments silently wrong** in files read without an error, 5 refused that should have been read, and
re-imported files keep their payment ids in 123 of 159. Patrik (2026-11-01) wants the reading made as good as we can
before more testers get Aresium. A clear "Aresium can't read this file" is acceptable; a file read wrong without a
word is the worst outcome, because the person's numbers are then wrong and they do not know it.

## Read first

- `AGENTS.md`, `eval/files/README.md`, `src/engine/readers/` (`read.ts`, `decode.ts`, `csv.ts`, `table.ts`, `guess.ts`,
  `profiles.ts`, `bank-profiles.ts`, `values.ts`, `readings.ts`, `ids.ts`), `src/engine/bank-readers.test.ts`,
  `src/engine/readings.test.ts`, `src/engine/fixtures/banks/` and their `.expected.json`.
- How the app shows an unknown file and its readings (`readingsOfUnknownFile`, "Does this look right?") in
  `~/empire-ios/CLAUDE.md` → "An unknown bank's file": a reading the person confirms is the second line of defence,
  so the first reading offered should be the right one.

## The rules of this round

- **Payment ids of existing imports never change** (`AGENTS.md`). Every fixture in `src/engine/fixtures/banks/` must
  keep its `.expected.json` byte for byte, ids included, unless a fixture was read wrong before (then say which and
  why, and Claude decides). Do not regenerate the fixtures' answers to make tests pass.
- Work from brief 78's failures; do not change its cases or answers. Do not run `--record` (Claude records after the
  merge).
- A guess the reader is not sure of goes to the person (the readings and the column check), never silently into the
  payments.

## Build

Fix the general causes Codex found in brief 78 (its final message, quoted in the merge commit `4213034`), each with
tests in `src/engine/`:

1. **Dates rewritten by a spreadsheet** (`14.10.26`, `2026-10-14`, `10/14/2026`): a known bank's profile with its
   fixed date format reads none of its rows and the import "succeeds" empty (16 silent missing payments). Accept the
   usual rewrites; decide day and month from the whole column (a value above 12 settles it; when the whole file
   cannot tell, offer both readings to the person rather than pick one).
2. **A file whose rows are all skipped or mostly skipped** must not import as a success with nothing or little in it:
   refuse with a clear code, or offer the readings.
3. **Damaged files** (cut off in the middle of a row, a broken quote): never import the damaged part silently; read
   the whole rows before it with a warning the app can show, or refuse.
4. **Several accounts in one file** (comdirect's sections): read every section, each payment on its account, or
   refuse; never only the first.
5. **A separator changed by a spreadsheet** (`;` ↔ `,` ↔ tab): a known bank's file should still be recognised as that
   bank (its columns are the same), keeping its own reading (fees, counterparty, pending rows, the booking currency).
6. **The payment text column:** a guessed layout that takes the booking type ("Lastschrift", "Überweisung",
   "Kartenverfügung") as the payment's text, while a column with the purpose exists, loses what sorting needs.
7. **ISO-8859-15** (the € sign): decode it as such where the bytes show it.
8. **Re-imported files keep their ids** where possible: a known bank's file saved again by a spreadsheet should give
   its payments the ids the original gives them (same account, date, amount, text), so a re-import shows nothing
   twice. Where that would change the ids of existing imports, do not; say what you found.

After each change run `npm run eval:files`; report the numbers before and after, and every fixture whose answer
changed (there should be none).

## Settled: do not re-open

- Silently wrong is worse than a refusal; a doubtful guess goes to the person.
- Ids of existing imports never change.

## Out of scope

- Sorting (brief 84), the app, the test set itself.

## Done when

- `npm run typecheck`, `npm test` (which runs the eval tests too) and `npm run engine` pass; every fixture's answer is
  unchanged; new behaviour has tests.
- `npm run eval:files` before and after in the final message, with what each change did.

## Final message

As in `AGENTS.md`: files changed, the exact check results, the score before and after, anything doubtful (above all
anything touching ids). Never commit, push or merge: Claude does.
