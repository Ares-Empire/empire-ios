# 142: Arestemis app: a listing reads like a listing, Open first, and a New search page that guides

Status: running (Claude agent, 2026-11-03)
Branch: `claude/142-listing-page-new-search` · Worktree: `../empire-ios-142-listing-page` · **For a Claude agent**
(design)

## Goal

Patrik (2026-11-03), after using builds 12 and 13, on three screens:

1. **A new listing's page** "gives a kinda long reasoning why it fits. I'd argue that's not really needed. Because the
   idea is it fits because of the filter. If anything short notes on what couldn't be confirmed / wasn't included and
   an overview of the stats like size, rent etc. — it might actually make sense to basically make it look like a
   normal listing with our metrics and just fill them in or have a '-' or a 'not confirmed' or smth there if empty. So
   not text explaining it but kinda like listings do it." And: "the flat description is cut off".
2. **The buttons:** "the Bewerbung button is colorful and confusing that all it does is give you your text whereas the
   button to the listing is less visible. I'd change it."
3. **New search** (the page of four kinds from brief 135): "in order to understand the diff options etc it's lots of
   concentrated reading because all text is in the same colour, small symbols and the screen is not really guiding
   etc. can we improve that? I think maybe the options can show less default text but let's see."

After this brief the listing page shows facts, not prose; Open on the site is the main button; New search reads at a
glance.

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules: no `.shadow` around content and nothing moving over a pathless shadow, brief
  87; no material under shadow/mask/group, brief 67; colours only from the shared pairs; light and dark; Languages;
  the Arestemis app entry: listings, New search, the tour), and `~/ares-empire/EMPIRE.md` → the design language.
- The Empire's restraint (Patrik): gold only as an accent and never decoration, no slogans; a province app is classy
  with **one accent colour** (Arestemis: purple), used for what matters, not spread over the whole screen.
- `Arestemis/Arestemis/Screens/MatchDetailScreen.swift` (the listing page: the facts grid, "Why it fits", warnings,
  the description with its "more", the bottom buttons), `ApplicationSheet.swift`, `ListingRows.swift`/`MatchRow.swift`
  (how a listing's facts read in a row), `Model/` for `Listing`, `ItemDetails`, `Match` (`reason`, `warnings`).
- `Screens/NewSearchScreen.swift`, `Model/NewSearch.swift` (`SearchKind.pitch`, `SearchExample`), the tour's step 2
  (`Model/Tour.swift`, `TourData.swift`: its words name the cards and their examples; keep them true).
- The server contract: `~/Arestemis/docs/API.md` → `Listing` (including the new `description_partial`, a CONTRACT
  ADDITION of 2026-11-03 that server brief 141 is building now: decode it leniently, absent = false) and `Match`.

## Build

1. **The listing page, flats and things** (`MatchDetailScreen`): a listing as a portal shows one, filled with our
   metrics.
   - **Facts first**, in the app's numbers face where they are numbers. A flat: warm rent, cold rent, size, rooms,
     flatmates (for a WG room), move-in, until (a sublet), furnished, district or address, kind (flat / WG room),
     posted. A thing: price (VB, auction bid and time left as today), condition, pickup or shipping and distance,
     seller kind, posted.
   - **Every fact the search asks about is always there**, with a quiet "–" when the listing does not state it. Choose
     the dash or a word ("not stated" / "nicht angegeben") and say why in your final message. Unknown must read
     unknown, never like a value. Facts the search does not ask about may be left out when unknown.
   - **"Why it fits" goes** from this page: the listing fits because of the search. The AI's `warnings` stay as short
     notes of what could not be confirmed ("Floor not stated", "Rent may be cold rent"), under the facts. Give them a
     quiet heading such as "To check" / "Zu prüfen" and a light mark, never an alarm colour. `reason` stays in the data
     and stays on "Filtered out" (there it says why a listing was turned down).
   - **The description in full**, without a "more" cut where the text is complete. When `description_partial` is true,
     one quiet line under it: "Only a preview. The whole text is on Immowelt." / "Nur ein Auszug. Den ganzen Text
     zeigt Immowelt." (the site's name from `source_name`), tappable to open the listing.
   - Watches' and price monitors' alarm pages are not part of this brief (they have their own layout).
2. **The buttons:** **Open on <site>** ("Bei ImmoScout24 öffnen") is the main button, in the accent fill. The
   application becomes the secondary one: quiet, outlined or plain, named for what it gives, e.g. "Application text" /
   "Bewerbungstext", with a small document symbol. Things have no application; their Open stays primary.
3. **New search** (`NewSearchScreen`), a page that guides:
   - Less to read: each kind gets one short line (about 6–8 words) instead of today's two or three, no lists of sites
     (the form shows them).
   - A clear order of looking: a larger mark for each kind (in a tinted tile of the accent or a calm surface), the
     kind's name strong, its line quieter, the examples as chips that look tappable but secondary.
   - Show fewer examples by default if that helps; maybe one per kind.
   - Try two or three variants on the simulator, choose the one that reads at a glance in German, and include
     screenshots of the ones you dropped in `build/142-variants/`.
   - Keep the tour's step 2 true: if a card's examples or words change, change the tour's words and data to match
     (both languages), and its ring still finds the first card.
4. **Words:** English in code; `scripts/strings.py sync` (undo changes to other apps' catalogs; restore `"Could not
   load older listings."` if dropped), German with `fill`, `check` at 0 problems. German style: du, plain, short.
5. **Tests:** the facts shown per kind with known and unknown values (a WG room without flatmates, a thing without
   condition), no "Why it fits" on a match while Filtered out keeps its reason, the partial line only when
   `description_partial` is true (and decoding without the field), the buttons' order and names, New search's cards
   and the tour's step 2 still matching.

## Out of scope

The server (brief 141 adds the field), watches' and price monitors' pages, TestFlight (Claude).

## Check before you report

- `xcodebuild test -scheme Arestemis` on your own simulator (`claude-142`; create and boot it; iOS 27.0 runtime, never
  27.1; screenshots from the app installed on that simulator itself, since `xcodebuild test` runs on clones).
- Screenshots `build/142-*.png`, each looked at yourself, German and English, light and dark:
  - the listing page of a flat (all facts known, and one with unknowns and warnings, with a partial description);
  - a WG room;
  - a thing;
  - the bottom buttons;
  - New search (before and after), the chosen variant and the dropped ones;
  - the tour's step 2.

## Final message

Files changed; build and test summary lines; screenshots; strings added (English and German); the variant you chose
for New search and why; anything doubtful.
