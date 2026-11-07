# 256: Arestemis app: asking prices on searches and listings

Status: built (2026-11-07), on `claude/256-asking-prices`, waiting for Claude's review and merge. Arestemis server brief 254 is live (schema 26); board #47 (Patrik: "yes").
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

## Result (2026-11-07, Claude agent)

**Built.** Decoding (`Model/ItemPriceModels.swift`): `ItemPriceSummary`, `ItemPriceStats`, `ItemPriceWeek`, `ItemPriceTrend`,
`ItemPriceVerdict`, `LocalizedText`, and `Match.priceVerdict`. Lenient where the contract may grow: a verdict that is
missing, malformed or of an unknown kind reads as none (the listing still loads); an unknown trend is none; a missing
language shows the other. `ArestemisAPI.priceRecord(huntID:)` → `GET /hunts/{id}/price-record`;
`ArestemisStore.loadPriceRecord` loads it with a Dinge search's page only, again after a newer scan or a changed search
(`PriceRecordRead`; a changed search drops the old numbers at once, as the server restarts its record), forced on pull to
refresh; a 404 or a failure shows nothing (no notice, no error), a refused login still goes to the session. Words in
`Model/ItemPricePresentation.swift` (`PriceRecordCard`, `PriceVerdictWords`, pure, `language:`), screens in
`Screens/ItemPriceViews.swift`, wired into `HuntPage`, `MatchRow` and `MatchDetailScreen`. Old servers: unchanged
(checked with `-sampleNoPrices`).

**Layout choices.**
- *Search's page:* the section goes **under Latest**, so the listings stay exactly where they were (a card between the
  figures and Latest pushed them down by about half a screen in the rich case). Heading "ASKING PRICES" / "ANGEBOTSPREISE"
  (distinct from the monitor's "Preisverlauf"/"Günstigster Preis", and the server's own word) with "Last 30 days" /
  "Letzte 30 Tage" on the right, which covers the 30 days. One glass card: the server's `display` one fact per line
  (split at its " · "; a line without it stays whole), all in one quiet style, since the app cannot know which fact is
  which without parsing; the trend comes as the server's words. Two or more sites with offers: a hairline, then one row
  per site, name left, usual range in the numbers' face and a muted count right (only the count below 8 offers). The
  server's `note` under the card as fine print (it says asking prices, the search's limits, VB allowance, no fees, not
  sale prices). Count 0: no card, one quiet line "Noch keine Preise. Sie kommen mit den ersten passenden Angeboten." /
  "No prices yet. They come with the first fitting listings." (so a just-edited search doesn't simply lose the section).
- *Rows:* a small label on its own line right under the price: a mark plus the server's label, text only like the row's
  other labels (no capsule; the long German label would not fit beside the price once a photo takes the row's left).
  ↓ Günstig in the accent, ↑ Teuer in neutral ink, (!) Ungewöhnlich günstig – genau prüfen (`exclamationmark.circle`) in the warnings' amber
  (`Look.amber`, deeper ochre on the light wall), never red. The marks mean the three differ by more than colour.
- *Listing's page:* under the price, title and site (keeping the hero together; directly under the price it pushed the
  title down by seven lines), the server's line with only its leading label in the verdict's tone and the rest in quiet
  ink (split only when the line starts with the server's own label, else shown whole), the note under it in small muted
  type.
- A number keeps its word or currency when a line wraps (`PriceText.keepingNumbersTogether`, e.g. "letzten / 7 Tage",
  not "letzten 7 / Tage"): the server's texts use plain spaces.
- Nothing animates in the new views and none has a shadow; colours only from `Ink`, `Look.accent`, `Look.amber`.

**Sample mode** (`Model/PriceRecordSample.swift`, DEBUG; on with `-sampleData`, off in the tests unless asked, so the
contract's listings and ids stay as they were for existing tests): hunt 2 (Herman Miller Aeron) 23 fitting listings,
usually €400–450, cheapest of 7 days €360, weekly median falling, Kleinanzeigen €395–445 · 14 and eBay €410–450 · 9;
listing 31 (€400) cheap, 30 (€480 VB) expensive, 29 none, and one invented listing **43** (€95, shipped from Bremen)
unusually cheap (the auction and the free chair can never carry one, per the contract). Hunt 5 (jeans): 3 listings,
cheapest €22, counts per site only. Hunt 4: none yet. Texts worded as the server's `texts.py`.

**DEBUG arguments (new):** `-sampleNoPrices` (the samples as a server from before brief 254: no records, no verdicts),
`-scrollTo prices` with `-openHunt <id>` (a thing search's section). Screens: `-openHunt 2|5|4 -scrollTo prices`,
`-tab listings -openSearch 2` (each verdict in one list), `-openMatch 43|31|30`.

**Strings added** (Arestemis catalog, German filled): "Asking prices" / "Angebotspreise", "Last %lld days" / "Letzte
%lld Tage", "%lld listings" (plural: "1 Angebot" / "%lld Angebote"), "No prices yet. They come with the first fitting
listings." / "Noch keine Preise. Sie kommen mit den ersten passenden Angeboten.". Everything else on these screens is
the server's text.

**Tests:** `AskingPricesTests` (an old server's match, unreadable verdicts, a lenient record, the card and the verdict in
both languages, few/none, site ranges, numbers kept together, nothing without a verdict, the route, the store asking for
thing searches only and once per scan, 404/500/503 showing nothing, sample mode) and `ServerSamplesTests` (the server's
four samples, copied to `ArestemisTests/ServerSamples/server-item-price-*.json`). `bash scripts/test-unit.sh Arestemis`:
"Arestemis: 459 tests, 0 failures"; `scripts/strings.py check`: 0 problems.

**Screenshots** (not committed): `docs/build-2026-11-07/256/`: `search-rich-*`, `search-few-*`, `list-verdicts-*`,
`listing-unusually-cheap-*` in de/en × light/dark, plus `search-none-*`, `listing-cheap-de-light`,
`listing-expensive-en-dark`, `search-rich-top-de-dark` (the page as it opens) and `search-old-server-de-dark`.

**Open / for the reviewer:** the Chronicle line in `ares-empire/EMPIRE.md` (outside this worktree); the section's place
under Latest is the main judgement call (the alternative, between the figures and Latest, is one move in
`HuntPage.figuresAndLatest`); the tour's data has no record, so the tour shows none.
