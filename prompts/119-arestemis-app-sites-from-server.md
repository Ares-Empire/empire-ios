# 119: Arestemis app: sites from the server, eBay and auctions

Status: merged 2026-11-02 (172 tests; built by a Claude agent). Uploaded as Arestemis build 7.
Branch: `claude/119-arestemis-sites` · Worktree: `../empire-ios-119-arestemis-sites` · **For a Claude agent** (mostly
screens; the small data part goes with it)

## Goal

Arestemis's server now offers eBay for thing hunts (the Arestemis repo, `docs/briefs/118-arestemis-ebay.md`; switched on once Patrik's eBay keys are in), and more sites
will follow (`~/Arestemis/docs/ARESTEMIS-SITES.md`). Today the app knows its sites as a closed list (`Source` in
`ArestemisModels.swift`): a site it does not know is dropped from every list, so eBay could never be chosen. After this
brief **the app takes its sites from the server** (`GET /kinds`), shows any site the server names, offers the **auction
switch** where a chosen site has auctions, and shows an **auction's bid and end** on its row and page. A later site then
needs no app update.

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules, Languages, the Arestemis app entry)
- The contract: `~/Arestemis/docs/API.md` → "Available kinds and sites" (`GET /kinds`: `kind`, `name`, `sources:
  [{source, name, ready, auctions}]`), `ItemSearch.auctions`, `ItemDetails.bids` / `ends`, `Source` (now also `"ebay"`);
  samples `~/Arestemis/docs/samples/kinds.json`, `ebay-match.json`, `overview.json`, `hunts.json`, `matches.json`
- `Arestemis/Arestemis/Model/` (`ArestemisModels.swift` → `Source` and its lenient decoding, `ItemModels.swift`,
  `ItemSearchDraft.swift`, `ItemFormatting.swift`, `ArestemisStore.swift`, `ArestemisSamples.swift`), the forms
  (`Screens/FlatSearchScreen.swift`, `Screens/ItemSearchScreen.swift`), `Screens/MatchRow.swift`,
  `Screens/MatchDetailScreen.swift`, the Portals card on the Hunts tab, `ArestemisTests/ServerSamplesTests.swift`

## Build

1. **Open sites (data):** `Source` becomes an open value (a struct wrapping the server's string, with the four known ones
   as constants for code that needs them, e.g. flat-only checks), so an unknown site is kept, not dropped. Its display
   name comes from the server: `SourceStatus.name`, `Listing.source_name`, `/kinds`' `name`; the app never invents a
   site's name. Keep decoding of every answer lenient (an unknown site never breaks anything). Update `DecodingTests`
   (which today pin "unknown sites are dropped") to the new rule: kept and shown by the server's name.
2. **`GET /kinds` (data):** the API client and the store load it with the overview (and keep the last answer); the forms'
   site chips come from it for their kind, in its order. A site with `ready: false` shows greyed with one line under the
   chips ("eBay is not set up yet." / "eBay ist noch nicht eingerichtet.", the server's own sentence where it sends one,
   else this) and cannot be chosen. Without an answer yet (offline, older server) the forms fall back to today's lists.
3. **Auctions:** `ItemSearch.auctions` (default true, kept when editing). In the thing form, under the sites, a switch
   "Include auctions" / "Auktionen einbeziehen" shows only while a chosen site has `auctions: true`.
4. **eBay and auctions on screen:** a thing's row shows an auction's current bid as its price with "bid" / "Gebot" (the
   formatting exists: `priceLine`) and the time left ("2 h left" / "noch 2 Std.", from `ends`; "ended" / "beendet" once
   past), and its bid count on the page. The page's open button names the site ("Open on eBay"); its facts grid gains
   Bids and Ends for auctions.
5. **Samples:** the sample data gains an eBay match (copy the shapes of the server's `ebay-match.json`, made-up values)
   with an auction, and `/kinds` (the server's `kinds.json` with eBay ready, plus a made-up third site not ready, so the
   greyed chip shows). Copy the server's current samples into `ArestemisTests/ServerSamples/` again (`server-kinds.json`
   too) and extend `ServerSamplesTests` to decode `kinds` and the eBay match.
6. **Words:** English in code; `scripts/strings.py sync` (undo any change it makes to other apps' catalogs, and restore
   `"Could not load older listings."` if it drops it: it is DEBUG-only and the export cannot see it), German with
   `fill`, `check` at 0 problems.
7. **Tests:** the open `Source`, `/kinds` decoding and fallback, the auction switch's visibility rule, the time-left text in
   both languages, the greyed site.

## Check before you report

- `xcodebuild test -scheme Arestemis` on your own simulator (`claude-119`); screenshots `build/119-*.png` in English and
  German: the thing form with Kleinanzeigen and eBay (eBay ready, the auction switch), with eBay not ready (greyed, the
  line), an eBay auction row and its page, the Hunts tab's Portals card with eBay. Look at each yourself.

## Settled: do not re-open

- Sites come from the server; names are the server's. Unknown sites are kept, never dropped.
- The auction switch shows only for sites with auctions.

## Out of scope

- The server, new sites beyond what `/kinds` lists, TestFlight.

## Final message

Files changed; build and test summary lines; screenshots; strings added (English and German); anything doubtful.
