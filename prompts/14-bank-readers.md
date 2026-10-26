# 14: Reading every German bank's export (CSV, CAMT, MT940)

Status: draft
Repo: aresium · Worktree: `~/aresium-14-bank-readers` (branch `claude/14-bank-readers`) · Built by: a Claude agent

## Goal

Friends will import files from banks we do not know yet. Patrik (2026-10-26): "be flexible". Today the engine reads
VR Bank CSV, CAMT (written for VR Bank) and PayPal CSV. Make the engine read the common German banks' exports, find
its way through an unknown CSV by itself, and hand the app a preview the person confirms once. All in the engine (pure),
so the app runs it on the phone; nothing about payments goes to a server.

## Read first

`AGENTS.md` (rules); the plan's part 3 ("Imports from other banks"); `src/import/*.ts` (the three readers, `types.ts`,
`util.ts`, `errors.ts`, `core.ts` for duplicates), `src/engine/index.ts`, the engine tests and fixtures.

## Build

1. **Text decoding in the engine:** `decodeBankFile(bytes: Uint8Array)` → text: UTF-8 (with or without BOM), else
   Windows-1252 / ISO-8859-1 (many German bank CSVs), chosen by validity, written in plain TypeScript (no
   `TextDecoder`, which JavaScriptCore lacks). Tests with umlauts in each encoding.
2. **Format detection:** `detectBankFile(text)` → CAMT (XML), MT940 (`:20:`, `:61:`, `:86:` blocks), PayPal CSV,
   or another CSV; for a CSV the separator, the header row (banks put account details above the table), and the
   layout when it is a known one.
3. **Known CSV layouts** (one small declarative profile each: header names, separator, date and number format, one
   amount column or debit/credit columns, which columns hold counterparty, text, IBAN, balance; how to make a stable id):
   Sparkasse (CSV-CAMT V2 and CSV-MT940), Volksbank/VR (exists; keep its ids), ING, DKB (old and new layouts), comdirect,
   Commerzbank, Deutsche Bank, Postbank, N26, Revolut, Trade Republic, Consorsbank, C24, Santander, Targobank,
   American Express, Barclays, Advanzia, Hanseatic, PayPal (exists). Take the header lines from public sources (the
   banks' help pages, open-source importers such as the Firefly III data importer's configurations, hledger examples)
   and name each source in the profile. One made-up fixture file per profile with the real header and invented
   payments, and its expected result.
4. **Unknown CSV:** `guessCsvLayout(text)` → a layout (date column, amount column or debit/credit, counterparty,
   text, optional balance and IBAN, date and number format) with a confidence and the first rows parsed by it, found
   from the values (columns where every cell is a date, an amount, …) and the header words (German and English). The
   app shows the preview, the person confirms or changes a column once, and passes the confirmed layout back:
   `readCsv(text, layout)`. Layouts are plain JSON, so the app can save them.
5. **CAMT from any bank** (camt.052/053/054 versions in use) and **MT940** readers, with fixtures (MT940's `:86:`
   subfields as German banks fill them: `?20`–`?29` text, `?32`/`?33` name, `?31` IBAN).
6. **Ids for duplicates:** every reader returns `externalId`s stable across re-imports of the same file and of an
   overlapping period. Use the bank's own reference where the format has one. Otherwise a hash of the booking fields
   **plus its occurrence number among identical bookings of that day**, so two identical payments on one day stay two.
   VR Bank CSV, VR CAMT and PayPal keep their current id scheme exactly (existing imports must not get new ids).
7. One entry, `readBankFile(bytes, savedLayouts?)` → `{ format, account?: {iban?, name?}, transactions, needsLayout?:
   guess }`, exported from `src/engine/index.ts`.

## Settled: do not re-open

- No AI, no network: unknown layouts are found from the values and confirmed by the person (the plan's AI-on-headers
  idea is not part of version 1).
- Readers return the existing `NormalizedTxn` shape (plus account info); the server's import route keeps working
  unchanged for VR Bank and PayPal.

## Done when

`npm run typecheck`, `npm test`, `npm run engine` pass; every profile has a fixture and an expected result; the final
message lists each bank with its source and anything unconfirmed (layouts you could not find a public header for).
