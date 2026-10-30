# 34: Sorting on day one: card lines, branch towns, Vinted, PayPal conversions

Status: running
Repo: **aresium** · Worktree: `../aresium-34-sorting` (branch `codex/34-sorting`) · Built by: Codex (`gpt-6.1-sol`,
effort `high`) · Rules: `~/aresium/AGENTS.md`

## Goal

Patrik's first test of phone mode with his real files (2026-10-30, `~/empire-ios/docs/reviews/2026-10-30-aresium-phone-test.md`,
finding 2): with every default category ticked, 43% of his payments (own transfers not counted) stay Not sorted, and a
correction often does not carry over to the next payment of the same shop. After this brief the engine sorts the
common cases on day one and one correction covers a shop. No AI, no network, no noticeable growth of the bundle.

Claude measures the result on Patrik's real files afterwards (they never leave his Mac: **you get no real data**;
build made-up fixtures that follow the patterns below exactly).

## Read first

- `~/aresium/AGENTS.md` (rules, commands), `src/engine/sorting/merchant.ts` (`merchantKey`, `payeeText`),
  `src/engine/sorting/shop-matcher.ts` (`compileShopList`, `branchMerchant`, `decide`), `src/engine/sorting/sort.ts`,
  `src/engine/sorting/transfers.ts` (`ownTransfers`), `scripts/shop-list.de.ts` + `scripts/build-shop-list.ts` (the list
  is generated: `shops.de.json` is never edited by hand), `src/engine/paypal.ts` (the currency-conversion rule),
  `src/engine/readers/bank-profiles.ts` (the VR Bank profile), `src/engine/sorting.test.ts`, `src/engine/shop-list.test.ts`.

## Build

1. **VR Bank card lines get a stable merchant key.** A VR Bank card payment has no counterparty; the whole line is in
   Verwendungszweck, with runs of spaces between parts. Made-up example of the exact shape (all 392 of Patrik's card
   lines look like this, the tail is always "MC Hauptkarte"):
   `Penny Musterstadt          DEU Musterstadt            EUR   9,47 Umsatz vom 08.10.2026 MC Hauptkarte`
   Shapes seen: `<merchant>  <3-letter country> <town>  <currency> <amount> Umsatz vom <dd.mm.yyyy> <card words>`;
   the merchant part may have dots, hyphens and several words ("Rossmann Fil. 123", "Mueller Drogerie-Markt"); amounts
   like `9,47`, `23,07`, `1.234,50`. Today `merchantKey` keeps amount and card words, so every payment is its own
   merchant (`penny musterstadt deu musterstadt eur 9 47 umsatz vom mc hauptkarte`). **New:** for a payment whose text
   has this card shape, the key is the merchant part only, cleaned as today (`penny musterstadt`): the same key the
   PayPal side gets for "Ihr Einkauf bei Penny Musterstadt". Recognise the shape by the tail
   (`<currency> <amount> Umsatz vom <date>`) and the country code before the town, not by the bank's name. Other banks'
   card texts that put the amount and "Umsatz vom" in the text: look in `src/engine/fixtures/banks/*` for any, and cover
   them only if they exist there.
2. **A known merchant before its own town matches.** `penny musterstadt` finds nothing today: a merchant from the hand
   list (`MERCHANTS`, e.g. penny, norma, netto) matches only as the whole name or before a branch number, and
   `citySuffix` knows 24 big cities. **New:** in a card line (item 1), when the merchant part ends with the line's own
   town word, that word is dropped for matching (`Penny Musterstadt … DEU Musterstadt` → `penny` → Groceries). Also
   for any payee text: a hand-list merchant followed by exactly one more word that is the town of the same line, or
   one of `citySuffix`'s cities, matches. Never match the exceptions the list already has (`penny reisen`, `penny
   mobil`, `pennyblack`; add tests that they stay unmatched). Do not add a list of all German towns (size).
3. **Vinted sorts to Clothes.** Vinted is in `MARKETPLACES` (left out as "can be anything"). Patrik (2026-10-30): Vinted
   is clothes for him, and that is what most people buy there. Take `vinted` out of `MARKETPLACES` and add a
   hand-written rule Clothes, money out, for `vinted` and `kleiderkreisel` (its old name). It must match both spellings
   PayPal writes: `MGP Vinted - Kleiderkreisel` and `Vinted, UAB`. Money in from Vinted (a sale) stays unsorted.
   Write the reason next to the rule in one line.
4. **PayPal currency conversions never wait in Not sorted.** A purchase in a foreign currency comes with two
   "Allgemeine Währungsumrechnung" rows (English "General Currency Conversion") linked by the related transaction code
   (`src/engine/paypal.ts`). The dashboard already leaves both out and counts the purchase at its euro cost, but
   `sortPayments` returns them unsorted, so they sit in Not sorted. **New:** exactly when the dashboard's rule leaves
   them out (the purchase and its euro row are present), `ownTransfers` marks both conversion rows as own transfers
   with a new rule `{ rule: "paypal-conversion" }` (the `OwnTransfer` type gets it). When the euro row is missing they
   stay as today. The dashboard's figures must not change.
5. **Tests** (made-up data only, in the style of the existing ones): the card-line key (several shops, amounts with
   thousands, two payments of one shop give one key, the PayPal spelling gives the same key); matching with the
   line's town and the exceptions; Vinted both spellings, money in unsorted; the conversion rows (with and without the
   euro row); `learn` on one card payment sorts the next card payment of that shop. Regenerate `shops.de.json` with the
   script and keep `shop-list.test.ts` passing (update its counts only where your change explains them).

## Settled: do not re-open

- No AI, no network, no new dependencies, no town list.
- Keys stay lower case and readable (the app shows nothing of them, but they are stored in the phone's learned list).
- Learned entries saved under old keys need no conversion here (the app rebuilds them; brief 35).

## Out of scope

- The server's own categorising (`src/sync/`), the website, the readers' parsing (only `merchantKey` and the matcher
  read the text differently), `src/engine/categories.ts`.

## Done when

- `npm run typecheck`, `npm test` and `npm run engine` pass; the new tests above exist and pass.
- The bundle grows by less than 20 KB (`ls -l dist/aresium-engine.js` before and after; report both).

## Final message

As in `AGENTS.md`: files changed, the exact command summary lines (tests run, failures), the bundle size before and
after, what is missing or doubtful.
