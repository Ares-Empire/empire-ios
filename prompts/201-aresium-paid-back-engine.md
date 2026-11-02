# 201: Money paid back: the engine

Status: draft
Repo: **aresium** · Worktree: `../aresium-201-paid-back` (branch `codex/201-paid-back`) · Model: `gpt-6.1-sol`, effort
`high` · Claude copies the engine into the app afterwards; the app's data follows in brief 202 (Codex), the screens in
brief 203 (a Claude agent).

## Goal

Patrik (2026-11-02), looking at what Aresium counts as spent over 14 months, named expenses that were paid back to him
(one in full, two by half) and expected them to show only his share. Since brief 71 every payment counts in the
direction it went, so money someone pays back counts as income and the expense keeps counting in full. Offered a
"pays back" link made by hand, he chose it: "Yes A actually makes sense, let's do it."

After this brief **a payment that came in can pay back a payment that went out**, all of it or a part, because the
person linked them. The linked euros come off that expense, in the expense's month, day and categories, and are not
income. Nothing is matched automatically: every payment without a link counts exactly as brief 71 says.

## Read first

- `AGENTS.md`, `docs/API-DATA.md` ("Rules the server applies", written in brief 71), `~/empire-ios/prompts/71-aresium-count-as-it-happens.md`.
- `src/engine/source.ts` (`SourcePayment`, `buildDashboardSource`, `counted`), `src/data/dashboard.ts`
  (`buildDashboard`: the transaction loop, `categoriesIn`, `incomeBuckets`, `categoryRows`, `incomeRows`, series,
  `overview`, `byMonth`, the day arrays and `dayExpenseRunning`), `src/engine/receipts/count.ts` (covered rows: the
  one exception so far), `src/engine/paypal.ts` (bank funding rows dropped, foreign currency folded), `src/data/pulse.ts`,
  `eval/sorting/own-data.ts` (`parseExport`), and their tests.

## Build

1. **Input:** `SourcePayment.paysBack?: { payment: string; amount: number }[]`, on a payment that came in: the ids of
   stored payments that went out and the euros (positive, whole cents) it pays back of each.
2. **When a link counts:** the payment carrying it is money in, counted (not dropped as PayPal bank funding, not
   folded away) and in euros, and not in a transfer category; the target is a counted row of a stored payment (not a
   receipt or cash entry row, not a withdrawal's covered row), money out, in euros, not in a transfer category and
   not a cash withdrawal (`cashWithdrawal`); the amount is above 0. Any other link is ignored and reported (item 5).
3. **Limits:** a payment in pays back at most its own amount in all; an expense gets back at most its own amount in
   all. Links apply in a fixed order (payment in by date, then id; its links in the order given); a link that would
   pass a limit counts only up to it, and is reported as clamped.
4. **Counting.** The expense's counted amount is its amount plus what it got back (money out, never above 0); the
   payment in's counted amount is its amount minus what it paid back (never below 0). Everything that counts either
   payment uses its counted amount: the headline `expense` and `income`, the month's, `dayExpense`/`dayIncome` on its
   own day, the running line, every category it is listed in (primary and tags; tags still count once in the
   headline), rows, series and the overview. **Paid back counts in the expense's month and day**, not in the month the
   money came. The balance does not change (it is the bank's). Both payments stay listed where brief 71 lists them
   (`categoriesIn` by money out, `incomeBuckets` by money in), also at a counted 0, so the app's lists can show them;
   rows still only show totals above 0.
5. **Output** on each transaction, only where something applies (absent otherwise, so the server's JSON and the sample
   stay byte for byte as they are): `counted` (its counted amount, only when it differs from `amount`); on the
   expense `paidBack` (euros it got back) and `paidBackBy: { payment, amount }[]`; on the payment in
   `paysBack: { payment, amount }[]` (as applied, after limits). On the dashboard `paybacksIgnored?: { from, to,
   reason, amount? }[]` (reasons: the target is missing, not money out, a transfer, a withdrawal, not in euros; the
   payment in is not money in, a transfer, not counted, not in euros; `clamped` with the euros that did not count),
   only when there is any.
6. **The pulse** (`src/data/pulse.ts`) and anything else that reads amounts count the same way.
7. **The eval's export parser** (`eval/sorting/own-data.ts`, `parseExport`) accepts schema 7 too (the app's export
   gets the links in brief 202) and ignores `paysBack`.
8. **Docs:** `docs/API-DATA.md`: the second exception to "counted as it happened", in plain English.

## Settled: do not re-open

- Only by hand: no automatic matching here. Suggesting likely pairs is the app's job (brief 202), and a suggestion is
  only a suggestion.
- Paid back counts in the expense's month and day.
- Both ends stay listed by direction; what counts is the counted amount.
- Brief 71's rule for every payment without a link, including shop returns.

## Out of scope

- The app (briefs 202, 203), the server's own database and deploy (the server has no links), receipts' matching,
  cash entries as either end of a link.

## Done when

- `npm run typecheck`, `npm test` and `npm run engine` pass.
- Tests (made-up data only): half paid back the next day (the expense's category, month, day and headline lower by
  half; the income lower by the same; rows and series follow); paid back in a later month (the expense's month lower,
  the later month's income lower); several payments in paying back one expense in parts; one payment in paying back
  two expenses and keeping a rest as income; both limits clamp and are reported; ignored links (target missing, money
  in as target, a transfer at either end, a withdrawal, a PayPal bank funding row as the payer, another currency); an
  expense with a tag lowers both lists and the headline once; a folded PayPal foreign purchase as the target (its
  euros); no links at all: `buildDashboard` of the sample source is identical to before.

## Final message

As in `AGENTS.md`: files changed, the exact check results (test counts), anything doubtful. Never commit, push or
merge: Claude does.
