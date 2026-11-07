# 256: Arestemis app: asking prices on searches and listings

Status: open (2026-11-07). Arestemis server brief 254 is live (schema 26); board #47 (Patrik: "yes").
Branch: `claude/256-asking-prices` · Worktree: `../empire-ios-256-prices` · Builder: Claude agent (design)

## Goal

Patrik's idea (2026-11-05): record the prices of listings the server already reads, per thing search, and tell him
what a fitting thing usually costs and whether a listing is cheap. The server now does it (Arestemis brief 254):
for each Dinge search it keeps the **asking prices of the listings that fit** (within the search's own limits) for
30 days, and every match can carry a verdict. No extra site reads, no extra checks. These are asking prices, not
sale prices, and the server's text says so.

Two places in the app show it:

1. **A search's page** (Dinge only): one calm card with what fitting listings usually cost there, per site when
   useful, and the cheapest of the last 7 days. Example live numbers (Air Force 1 test search): "64 passende
   Angebote · Üblicher Angebotspreis 25,00 €–33,50 € · Günstigstes Angebot der letzten 7 Tage: 15,00 €".
2. **A listing** (row and detail page): a small verdict when there is one: **Günstig / Cheap**, **Teuer /
   Expensive**, or **Ungewöhnlich günstig – genau prüfen / Unusually cheap – check carefully** (often bait, a scam or
   a mismatch). Most listings have none; nothing shows then.

The server is built and deployed: build from the contract.

## Read first

- `AGENTS.md` and `CLAUDE.md` (the design rules at the top, "Languages", "Light mode", the Arestemis entry),
  `~/ares-empire/EMPIRE.md` → design language. Arestemis' accent is moonlight violet; gold only as an accent.
- The contract in `~/Arestemis/docs/API.md`: search "brief 254" (`GET /hunts/{id}/price-record` →
  `ItemPriceSummary`; optional `Match.price_verdict` → `ItemPriceVerdict`). Each carries ready bilingual strings
  (`display.en/de`, `label`, `note`) plus the raw numbers; strings contain both languages regardless of
  `Accept-Language`. Server samples: `~/Arestemis/docs/samples/item-price-record.json`,
  `item-price-record-small.json`, `item-price-match.json`: copy them into `ArestemisTests/ServerSamples/` and
  decode them in `ServerSamplesTests`, as briefs 182/187 did.
- Code: `Screens/HuntPage.swift` (a search's page), `Screens/MatchRow.swift` and `Screens/ListingRows.swift` (rows),
  `Screens/MatchDetailScreen.swift` (a listing), `Model/ArestemisModels.swift` (`Match`), `Model/ItemModels.swift`,
  `API/ArestemisAPI.swift`, `Model/ArestemisStore.swift`, sample mode's backend (`Model/ArestemisSamples.swift`),
  `Localizable.xcstrings`, and the tests next to them. Price monitors (`PriceViews.swift`, `PricePresentation.swift`)
  already show prices: reuse their number style where it fits, but this is a different thing (a market range
  for a thing search, not one product's price), so keep the wording distinct.

## Build

### 1. Decode

- `ItemPriceSummary` (overall + per-site `ItemPriceStats`, `weekly_medians`, `trend`, `display`) and
  `ItemPriceVerdict` on `Match` (optional; missing = none). Old servers send neither: the app must work unchanged.
- `ArestemisAPI.priceRecord(huntID:)` for `GET /hunts/{id}/price-record`; load it with the search's page, only for
  thing searches. A 404 or failure shows nothing (never an error banner for this).

### 2. The search's page

- One card, placed where it reads naturally on a Dinge search's page (your call; it must not push the listings far
  down). Title e.g. **Preise** / **Prices**. Show the overall line from `display` (the server's text, already in both
  languages: pick by the app's language) and, when there are 2+ sites with their own numbers, a compact per-site
  breakdown (site name + range or count). A short caption that these are asking prices of fitting listings
  within the search's limits, from the last 30 days.
- Few observations: the server then sends only the count and the cheapest; show that plainly. None at all
  (`count` 0): hide the card, or one quiet line ("Noch keine Preise" / "No prices yet"), your call.
- A trend, when present, as words or a tiny symbol, never a big chart.

### 3. Listings

- Row: a small, calm label for the three verdicts, consistent with the row's existing badges. Cheap may use the
  accent; Expensive stays neutral; Unusually cheap gets a cautious look (not alarm red; it means "check").
- Detail page: the verdict's `display` line near the price, with its note.
- No verdict → nothing shows, no placeholder.

### 4. Sample mode and tests

- Sample mode shows believable invented numbers on one sample Dinge search and a few verdicts (one of each).
- Decoding tests for the three server samples, the old-server case (fields missing), a presentation test choosing
  the language, and a UI-free test that nothing shows without a verdict.
- No "AI"/"KI" in any visible text. German texts use "du", per the app's rules.

## Not in this brief

- A "doesn't fit" button using `POST /matches/{id}/reject` (the server has it): later, if Patrik wants it.
- The web demo at arestemis.de follows in a separate brief once the screens are settled.

## Verification

- Run the Arestemis unit tests with `bash scripts/test-unit.sh Arestemis` (the same run as GitHub's) and
  `scripts/strings.py sync` / `check` after text changes (0 problems); report the exact summaries.
- Screenshots for Claude's review, light and dark, German and English: a Dinge search's page with the card (rich
  and few-observation cases), a list with each verdict, and the detail page. Save them under
  `docs/build-2026-11-07/256/` (not committed) and list the paths.
- Commit on your branch in the worktree; never push or merge (Claude does).
