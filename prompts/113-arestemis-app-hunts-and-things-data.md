# 113: Arestemis app: several hunts and things for sale, the data side

Status: draft
Branch: `codex/113-arestemis-hunts-data` · Worktree: `../empire-ios-113-arestemis-hunts-data` · Model: `gpt-6.1-sol`,
effort `high`

## Goal

Arestemis grows from one flat hunt into any number of hunts of different kinds: flats, and things for sale on
Kleinanzeigen (plan: `~/ares-empire/docs/ARESTEMIS-ANYTHING.md`). This brief builds the app's **data side** for that:
the types, the API client, the store with per-hunt actions, the form model of a thing search, formatting, push and the
samples. **The screens are not yours:** a Claude agent designs them afterwards (brief 114). You only keep today's
screens compiling and working on the new store.

The server is being built at the same time (briefs 111, 112, 116), so you build against the contract below and the
samples you write from it; Claude swaps in the server's own samples when they exist.

## Read first

- `AGENTS.md` and `CLAUDE.md` (always; `CLAUDE.md` → Languages, the Arestemis app entry under Setup state)
- **The contract:** `prompts/112-arestemis-several-hunts.md` → "The contract", both parts (several hunts; things for
  sale). Every type and field comes from there. Anything missing: `TODO(api)`, never guessed.
- `Arestemis/Arestemis/Model/ArestemisModels.swift`, `ArestemisStore.swift`, `SearchDraft.swift`,
  `KeptSearchDraft.swift`, `AppNavigation.swift`, `Notifications.swift`, `Formatting.swift`, `ArestemisSamples.swift`,
  `API/ArestemisAPI.swift`, `Arestemis/Arestemis/Samples/*.json`, and the tests in `Arestemis/ArestemisTests/`
  (`DecodingTests` pins how unknown portals are dropped)
- `~/Arestemis/docs/API.md` for today's contract (version 2)

## Build

1. **Types** (`ArestemisModels.swift`, or a new file in `Model/` if it grows past ~500 lines):
   - `HuntKind`: `flat`, `item`, and an unknown value kept as its string. **Decoding never fails on a new kind.**
   - `Hunt`: `name: String?`, `lastScan` (`last_scan`), and its search as an enum, e.g. `HuntSearch.flat(Search)`,
     `.item(ItemSearch)`, `.unsupported` (a kind this build does not know, or a search that does not decode for its
     kind): the hunt still decodes, so the home screen never fails because of one hunt.
   - `HuntCard` (`hunt`, `counts`, `sources`, `slowed`); `Overview.hunts`, read leniently: a server without it gives
     `[HuntCard(hunt: hunt, …)]` from `hunt` (counts from the account's), so the build works against today's server.
   - `ItemSearch`, `ItemDetails`, `Condition` (unknown values decode as nil, never fail), `Listing.item`,
     `Match.atStart` (missing = false), `Match.overMax`.
   - Encoding: `POST /hunts` sends `{kind, name, search}`; `PUT` sends `{search, name}` (name `null` clears it).
2. **API client** (`ArestemisAPI.swift` and the `ArestemisBackend` protocol): `hunts()`, `createHunt(kind:name:search:)`,
   `updateHunt(id:search:name:)`, `setActive(id:active:)`, `deleteHunt(id:)`, `matches(hunt:state:limit:before:)`,
   `rejected(hunt:limit:)`, `parse(text:kind:)`. Today's calls keep working.
3. **The store** (`ArestemisStore.swift`):
   - `hunts: [HuntCard]` from the overview; per-hunt start/pause, save, rename and delete, each optimistic with rollback
     and the server's sentence on failure (the 409s for 10 active and 30 hunts arrive as such sentences).
   - A selected hunt for the Listings tab (`nil` = all hunts), passed to `matches`/`rejected`.
   - Keep `hunt` (the first flat hunt) and every property today's screens use, so they compile and behave as today
     until brief 114 replaces them. Mark the kept ones `// brief 114 replaces`.
   - Matches of things: no application (the store refuses with a plain line if asked).
4. **Drafts:** `SearchDraft` stays the flat form's model. Add `ItemSearchDraft`: every field of `ItemSearch` as the form
   edits it (texts for numbers), validation with the server's limits (query 2–100, up to 20 exclude words of ≤ 40,
   min ≤ max, `vb_over_max` ≥ 0, radius 0–200, places 0–5 and at least one for pickup or either, extra ≤ 1000, at least
   one site), conversion to `ItemSearch`, the 10 % default for `vb_over_max` when a maximum is typed and the VB amount
   was not touched (rounded to whole euros), and filling from "Describe it" (`Partial<ItemSearch>`, same rules as the
   flat draft). `KeptSearchDraft` keeps one unsaved draft per hunt id, and one per kind for a new hunt.
5. **Formatting** (`Formatting.swift`, pure functions taking `language: AppLanguage`):
   - A thing's price line: fixed "80 €" / "€80" (as the app's money format), negotiable with a number "80 € VB" /
     "€80 VB", VB alone "VB", free "Zu verschenken" / "Free", auction "80 € (bid)" / "€80 (bid)" (TODO for eBay, keep
     simple), on request "Preis auf Anfrage" / "Price on request", unknown nothing.
   - Condition names (en New · Like new · Good · OK · For parts; de Neu · Wie neu · Gut · In Ordnung · Defekt), shipping
     ("Shipping" / "Versand", plus "from 6.19 €" / "ab 6,19 €" when known), pickup only ("Pickup only" / "Nur Abholung"),
     distance ("5 km", "0.8 km" / "0,8 km"), seller ("Private" / "Privat", "Commercial" / "Gewerblich"), reserved.
   - The fact lines for a thing's row and its detail (the counterpart of today's `facts` / `detailFacts`), and "VB, 30 €
     over your limit" / "VB, 30 € über deinem Limit" from `overMax`, and a hunt's summary line for each kind (today's
     `SearchSummary` for flats; for a thing: the query, the price range, delivery and place, sites).
   - A hunt's display name: its `name`, else for a thing the query, else today's flat summary's first part.
6. **Push** (`Notifications.swift`): a second category `ARESTEMIS_ITEM` with the action "Open listing" only, registered
   with the existing one; routing by `url` as today.
7. **Samples** (`Samples/*.json`, `ArestemisSamples.swift`, `SampleBackend`): made-up data only. The overview gets
   `hunts` with the flat hunt and a thing hunt (an office chair: "Herman Miller Aeron", max 450 €, VB 45 €, pickup or
   shipping near Garching within 20 km, Kleinanzeigen) and a paused second flat hunt; matches of the thing hunt (one
   `at_start`, one VB over the maximum with `over_max`, one shipped with a shipping cost, one free). `SampleBackend`
   handles several hunts: create, update, rename, start/pause with the limits, delete, filters by hunt. Keep the
   existing launch arguments working; add `-sampleHunt <id>` (Listings filtered to a hunt).
8. **Tests** (`ArestemisTests/`): decoding (an unknown kind, a hunt whose search does not decode, an overview without
   `hunts`, a thing's listing and match, unknown condition and price kind), the store's per-hunt actions and rollback,
   the limits' sentences, `ItemSearchDraft` (validation, conversion, the VB default, filling), formatting in both
   languages, the push categories.

## Settled: do not re-open

- **No screen design here.** Brief 114 (Claude) builds the Hunts list, the thing form and the thing cards. Do not add
  views beyond what keeps today's screens compiling.
- Unknown kinds and unknown values never break decoding (the app must survive a server ahead of it).
- English in code; leave the German catalog entries to Claude (list the new strings in your final message), except
  that pure formatting functions return both languages as above (they are tested in both).

## Out of scope

- The server, the screens' look, the String Catalog's German, TestFlight.

## API

The contract in `prompts/112-arestemis-several-hunts.md` → "The contract". The server serves the several-hunts part
after brief 112 and the things part after brief 116; until then the app runs on its samples.

## Done when

- `xcodebuild test -scheme Arestemis` passes on your own simulator (`codex-113`, commands in `AGENTS.md`), with the new
  tests.
- The app with `-sampleData` still shows today's screens with the sample flat hunt; save a screenshot to
  `build/113-hunt.png`.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the new strings (English), every `TODO(api)`,
anything doubtful.
