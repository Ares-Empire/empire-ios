# 37: The same bank payment from two file formats counts once

Status: running
Branch: `codex/37-two-formats` · Worktree: `../empire-ios-37-two-formats` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Brief 35's counting tests found the last way a payment counts twice in phone mode
(`PhoneCountingTests.csvAndCamtOfTheSameAccountReportDifferentEngineIDs`): one account imported once as a CSV and once
as a CAMT (or MT940) file for the same days gives every payment twice, because a payment's id is the bank's reference
where the format has one and a hash of that format's fields otherwise (`~/aresium/src/engine/readers/ids.ts`), so the
two formats never share ids. Banks offer both formats, and the bank guide names both, so a person switching formats
between imports hits this. After this brief such a payment is "already there".

## Read first

- `AGENTS.md`, `CLAUDE.md` (the "Aresium phone mode" entry: storage, import, the result line)
- `Aresium/Aresium/Model/PhoneLedger.swift` (the import: accounts by IBAN, `LedgerPayment.key`, what counts as already
  there), `Model/PhoneBackend.swift` (`importFiles`, the result counts), `Aresium/AresiumTests/PhoneCountingTests.swift`
  (the case above, its helpers `bankWithIBAN`, `camt`), `~/aresium/src/engine/readers/ids.ts` (read only).

## Build

1. **The rule (settled):** an export holds every booking of each day it covers (the premise of `ids.ts`). So when a
   bank file is imported, after the usual match by key: group the file's still-new payments by account, booking day,
   amount (in cents) and currency; for each group, count the stored payments of that account with the same day, amount
   and currency that **no payment of this file matched by key**; the first `min(new, stored)` new payments of the group
   are already there (one stored payment answers for at most one new one), the rest are new. Only bank files (PayPal's
   export has its own transaction codes; leave it as it is). The import result counts them as already there.
2. Put the rule in one place in the ledger's import, with a comment that says why (formats do not share ids), and keep
   it independent of which formats are involved.
3. **Tests** (made-up data): the existing CSV + CAMT case now gives 2 payments, spending 20, income 1000, and the second
   import reports 2 already there (rename the test for what it shows now); CAMT first, then CSV; an MT940 + CSV pair if
   the helpers make it easy; two different payments of the same amount on the same day in both files (both answer each
   other, nothing extra); a CSV covering more days than the CAMT (only the shared days count as there); two accounts
   with the same day and amount (never matched across accounts); re-importing the same CSV still matches by key as
   before; the same-format overlap tests keep passing.

## Settled: do not re-open

- No fuzzy matching on names or texts: day, amount, currency and account only, counted one to one.
- No engine change and no store schema change (brief 36 changes the schema in parallel).

## Out of scope

- PayPal files, receipts, cash, the look of the result line, `StoredChosen` and the category picker.

## Done when

- `xcodebuild test -scheme Aresium` passes on your own simulator (`codex-37`, commands in `AGENTS.md`), with the tests
  above.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, what is missing or doubtful.
