# 86: Sorting round 2: an experiment with a list of local places from OpenStreetMap

Status: merged 2026-11-01 as an experiment, off by default (aresium b04ff9b; known places right 187 -> 437 of 500, wrong unchanged; Patrik +5 right; memory on the phone not measured yet)
Repo: **aresium** · Worktree: `../aresium-86-local-places` (branch `codex/86-local-places`) · Model: `gpt-6.1-sol`,
effort `high` · An experiment: Claude decides from your numbers whether it goes into the app.

## Goal

After sorting round 1 (brief 84) Aresium is right on 99% of what it sorts, and what it misses is mostly **local
places**: one-off names without a word that says what they are ("Zur Mühle", "Lieblingsstück", "Il Buongustaio").
Patrik asked whether a list of vendors would help (2026-11-01: "Could it be smart to just build a list of vendors
with sorting"; Claude's answer: for chains we have it, for local places the one source is OpenStreetMap; he said "yes
trying it cant hurt").

Build **a compact list of Germany's named local places from OpenStreetMap with their kind**, an **optional** way for
the engine to use it, and **honest measurements**: what it finds, what it gets wrong, what it costs in app size and
engine start. Nothing is switched on by default; the app does not change in this brief.

## Read first

- `AGENTS.md`, `eval/sorting/README.md` (the held-back rule), `eval/sorting/categories.md` (its OSM/NSI mapping table
  is the starting point for kind → category), `eval/sorting/sources.ts` (how the test set fetched OSM places), the
  sorting engine (`src/engine/sorting/`: `sort.ts`, `starter-rules.ts`, `shop-matcher.ts`, `merchant.ts`,
  `shop-words.ts`), `scripts/build-shop-list.ts` and `scripts/build-engine.ts` (how data reaches the app's bundle),
  `~/empire-ios/CLAUDE.md` → "Aresium phone mode" (the engine runs in JavaScriptCore on the phone: `AresiumEngine`).

## Build

1. **The list** (`scripts/build-local-places.ts`, output under `src/engine/sorting/` or a separate data file the
   bundle can load): named places in Germany of the kinds people pay at (food and drink, shops, health, personal
   care, petrol and car, hotels, leisure; the mapping table's kinds), each as its normalised name, its category from
   the mapping table, and its town (or postcode). From OpenStreetMap: the Overpass API by state and kind, politely,
   or a Geofabrik extract read with one devDependency for the PBF format (allowed, used only in `scripts/`, never in
   `src/engine/`). Raw downloads in an ignored cache folder. Record the data date and the source in the file.
2. **Keep it precise and small:**
   - A name with **one kind across Germany** (or one dominant kind, say how you decide) may match by name alone; a
     name with several kinds matches only together with the town the bank line shows ("ZUR MUEHLE … GARCHING DE");
     drop names that are ordinary words or too short to be safe (a word list; tests with negative cases).
   - Chains are the shop list's job: leave out names the shop list or the name-suggestion-index already knows.
   - A compact format (a sorted table, a trie, codes for categories and towns), measured: bytes added to the bundle or
     the data file, compressed and not, and the engine's start time with it (in Node's `vm` as `scripts/` does, and
     on the simulator through the app's `PhoneEngineTests` timing if you can run it; say what you measured).
     A budget to aim for: under 5 MB added to the app, under 200 ms more engine start on the simulator.
3. **The engine uses it only when given it**: `sortPayments(payments, { categories, learned, localPlaces? })`. Order:
   learning and the structural rules first, then the shop list, then the local list, then the words; or another order
   if the measurements show it is better (say why). A match on the town as well as the name wins over a name alone.
4. **Measurements that do not fool us** (the test set's local places come from OpenStreetMap too, so a list that
   contains them would only show that the list knows itself):
   - **Left-out towns:** build a variant of the list **without** the test set's eight places (Garching, München
     Schwabing, Köln, Berlin Kreuzberg, Leipzig, Hamburg, Wernigerode, Wacken; by their areas) and score the test set
     with it (`npm run eval:sorting` with the list passed in; worked-on part fully, held-back totals only). This shows
     what the list does for places it does not contain: mostly whether it causes wrong answers.
   - **Known places:** draw a fresh sample of about 500 places from other towns that **are** in the list, render them
     as bank lines with brief 79's renderer, and score how many the list sorts right and wrong against their own OSM
     kind (no judges needed for this measurement, say so in the report). This shows what a person whose town is in
     OpenStreetMap gets.
   - **Wrong answers elsewhere:** the brands, made-up shops and non-shop payments of the test set must not get worse
     with the list (false matches of list names).
   - Claude runs Patrik's data (counts only) with and without the list.
5. **Licence:** OpenStreetMap data is ODbL: the list's file carries "© OpenStreetMap contributors, ODbL" and the
   source, and the repo's licence notes say where the derived list comes from. Say in the final message what the app
   would need to show (its Fonts & licences page lists such notices).
6. **Rebuilding:** one command builds the list again from the cache or a fresh download; the README of the list says
   how often it makes sense (twice a year).

## Settled: do not re-open

- An experiment: off by default, no app change.
- Wrong must not rise anywhere; a doubtful match is no match.
- The held-back part stays unopened; the left-out-towns measurement is the one that counts for the test set.

## Out of scope

- The app (Claude decides afterwards), other sources than OpenStreetMap, anything sent from the phone.

## Done when

- `npm run typecheck`, `npm test` and `npm run engine` pass; the list's matching has tests (name alone, name and
  town, ambiguous names, ordinary words, the order against the shop list and learning).
- The final message has: the list's size (places, names, bytes), the start-time measurements, the three measurements
  of item 4 with and without the list, examples of what it finds (made-up or anonymised), and your recommendation.

## Final message

As in `AGENTS.md`: files changed, the exact check results, the measurements, anything doubtful. Never commit, push or
merge: Claude does.
