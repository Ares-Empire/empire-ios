# 30: Receipts in the engine: read a receipt, find its bank payment, count cash once

Status: running
Repo: **aresium** · Worktree: `../aresium-30-receipts` (branch `claude/30-receipts`) · Built by: a Claude agent ·
Rules: `~/aresium/AGENTS.md`

## Goal

Patrik wants receipts in Aresium (2026-10-27, decision D8 in `~/ares-empire/docs/ARESIUM-FOR-OTHERS.md` → part 6,
"Version 1"; read it first). The iPhone app photographs a receipt and reads its text with Apple's Vision (brief 31);
the **engine** (this brief, pure TypeScript in `src/engine/`, bundled into the app) turns what Vision saw into a
receipt (shop, date, total, currency, card or cash), finds the bank payment it belongs to so nothing counts twice, and
lets the dashboard count cash receipts without counting the cash withdrawal again. All receipt logic lives here, once,
tested with made-up receipts; the app only captures and shows.

## Read first

- `AGENTS.md` (the engine stays pure; no real data; checks before you report).
- The plan: `~/ares-empire/docs/ARESIUM-FOR-OTHERS.md` → part 6 (Version 1, and the research below it: the register's
  QR code), D8.
- `src/engine/index.ts` (what is exported and how blocks are marked), `src/engine/source.ts` (`buildDashboardSource`,
  `SourcePayment`), `src/data/dashboard.ts` (`buildDashboard`, the `Dashboard` JSON the app decodes; brief 20's rule
  that money in without a category counts as income "Other"), `src/engine/sorting/` (`merchantKey`, the shop list and
  its matcher, `starterCategory`; the `cash` rule: Geldautomat, Bargeldauszahlung, ATM, …), `src/engine/readers/values.ts`
  (how amounts and dates in many styles are already parsed: reuse, do not copy).

## Build

1. **`readReceipt(input) → ReceiptReading`.** Input (what the app sends, JSON):
   `{ observations: [{ text, x, y, width, height }], codes: [string] }`. Observations are Vision's recognised text
   pieces, boxes normalised 0–1 with the origin at the **top left** and y growing downwards; a receipt scanned in
   several pages comes as one list with page *n*'s y offset by *n*. `codes` are QR or barcode payloads found on it.
   - **Rows first:** a receipt's left text and its right-aligned price are separate observations; join pieces whose
     vertical centres are close into one row, left to right (`"SUMME EUR"` + `"23,40"` → one row). Tolerate slight
     tilt. Export the rows too (the app stores them as the receipt's text; no photo is kept).
   - **The register's code first:** most German receipts carry the signed register data (TSE), often as a QR code
     (`V0;…;Kassenbeleg-V1;Beleg^…^…;…`, DSFinV-K / BSI TR-03153; look up the published format and write down the source
     in a comment). When a code parses, its total, its payment split (`Bar` = cash, `Unbar` = card) and its time win
     over the printed text; say so in the reading (`from: "code"`).
   - **The printed text otherwise:** the total (the total words below, the amount on that row; not subtotals, VAT
     lines, "given"/change lines or deposit refunds; when unsure, the largest amount after the item lines that the
     change maths confirms: given − change = total); the date (and time when there); the currency (€/EUR when nothing
     else; £, $, CHF, Fr., kr, zł, Kč, …; ISO codes out); card or cash from the payment lines.
   - **Languages:** the words for total, card, cash, given and change, and the date and number styles, for German,
     English, French, Italian, Spanish, Dutch and Portuguese (for example SUMME, GESAMT, ZU ZAHLEN, TOTAL, AMOUNT DUE,
     MONTANT, TOTALE, IMPORTE, TOTAAL; Karte, girocard, EC, Visa, Mastercard, Maestro, kontaktlos, Apple Pay, CB, carte
     bancaire, tarjeta, carta, pinnen; Bar, gegeben, Rückgeld, cash, change, espèces, rendu, contanti, resto, efectivo,
     cambio, contant, wisselgeld, dinheiro, troco). Keep them in one table that is easy to extend. Dates: day first
     everywhere except a US receipt (dollars) when the day-first reading is impossible. Report the language the words
     matched (`language`), for the app's check window.
   - **The shop:** the shop list's matcher over the rows (the top rows count most; a known chain name anywhere, such as
     on a REWE receipt whose logo is an image and whose text says "REWE Markt GmbH"), giving the shop's name and its
     category id; otherwise the first row that is a name (not an address, phone number, VAT id, date or a register line),
     with no category.
   - Output: `{ shop, categoryId, date, time, total, currency, method: "card" | "cash" | null, language, from: "code" |
     "text", rows: [string], sure: { shop, date, total, method } }` where each `sure` is true when the value came from
     the code or an unambiguous line, false when it was a fallback (the app shows those fields first in the check
     window). Anything not found is null; never invent.
2. **`matchReceipt(receipt, payments, taken) → ReceiptMatch`.** `receipt`: `{ date, total, currency, shop }`;
   `payments`: the stored payments (`SourcePayment`-like: id, date, amount, currency, counterparty, description);
   `taken`: ids of payments another receipt already joined. Rules (D8): a card receipt's payment is money out, from the
   receipt's day to 7 days later. **Exact:** the same amount to the cent in the same currency and a similar shop (the
   shop list's match or `merchantKey` on both sides, or the receipt's shop words in the bank text; a bank text that
   names only a card processor counts as unknown, not as different). Exactly one exact match → `{ exact: id }`.
   Otherwise `candidates` (best first, at most 5), each with why: `amountDiffers` (the bank amount is larger by up to
   €200 with the same shop and day: cash back or a tip; or smaller by less than 2 %), `otherCurrency` (the receipt is
   not in the payment's currency: matched on day and shop only), `severalSame` (two or more exact ones). Nothing → empty.
   Pure; the app asks the person about every candidate, never joins one by itself.
3. **Receipts in the dashboard: `buildDashboardSource(input)` takes `receipts?: SourceReceipt[]`.** Without receipts
   nothing changes (Patrik's server never sends them: its numbers must stay identical; a test proves it on the existing
   fixtures). `SourceReceipt`: `{ id, date, total, currency, method: "card" | "cash", category: string | null,
   shop, paymentId: string | null }`.
   - `paymentId` set (joined): the bank payment counts as it is; the receipt adds nothing.
   - Card, not joined: counts as a payment of its own (money out, its category, its shop as the place), marked
     `provisional: true` on its dashboard transaction ("waiting for the bank statement" in the app).
   - **Cash:** counts as a payment of its own in its category on its day. Withdrawals (payments the shop list's `cash`
     rule matches, whatever category they are in) form a pool; each cash receipt takes its amount from the withdrawals
     on or before its day, the oldest first, never more than is left. The amount taken shows as one row per withdrawal
     and month in the **withdrawal's own category and month**, a positive amount labelled for the app ("covered by
     receipts", with the receipt ids), so that category shows only what has no receipt and the total spending stays the
     same. These rows are never income, also when the withdrawal has no category (brief 20's rule must not turn them
     into "Other" income). A cash receipt bigger than what is left counts the rest as spending of its own.
   - Foreign-currency receipts paid in cash arrive with their euro amount from the app (`total` in EUR, the original
     kept by the app); the engine does not convert currencies.
   - Every new field on the dashboard's JSON is optional, so the app's decoder and the server's website keep working.
4. **Exports and tests.** Export `readReceipt`, `matchReceipt` and the types from `src/engine/index.ts` in a marked
   block like the others. Tests with **made-up receipts** (fixtures in `src/engine/fixtures/receipts/`, as the
   observation JSON Vision would give, boxes included): German supermarket (card, with deposit and a coupon line), a
   bakery paid cash (given and change), a drugstore, a petrol station, a restaurant with a tip line, a German receipt
   with a register QR code whose total differs from a misread printed total (the code wins), a long receipt in two
   pages, noisy reading (O for 0, a missing letter in SUMME, a tilted row), and one receipt each in English (UK, £),
   US ($, month first), French, Italian, Spanish, Dutch and Portuguese, plus Swiss francs. Matching: exact, two exact
   (asks), cash back, tip, a card processor's bank text, another currency, already taken, none. Dashboard: card joined,
   card provisional, cash covered by an earlier withdrawal across months, cash bigger than the pool, cash with the
   withdrawal Not sorted, and no receipts = identical numbers.

## Settled: do not re-open

- No photo, no AI, nothing leaves the phone; the engine stays pure (no clock: dates come in).
- The engine never joins a candidate by itself; only an exact single match is joined without asking (D8).
- Items and splitting a receipt into several categories are version 2: not now (but keep the rows, they are its input).

## Out of scope

The app (brief 31), the server and its database, the website, deploying. Patrik's server mode gets receipts later.

## Done when

- `npm run typecheck`, `npm test` and `npm run engine` pass; the bundle grows by little (say how much).
- Final message (plain English): files changed, test counts, the exported functions and JSON shapes exactly as the app
  will call them (brief 31's second part is written from it), the QR format's source, what was hard or doubtful, and
  what Claude must run. Never commit, push, merge or deploy; never touch the server, any database or other repos.
