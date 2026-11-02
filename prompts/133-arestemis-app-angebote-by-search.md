# 133: Arestemis app: Angebote as "New | Searches", and a search over all listings

Status: draft (starts after brief 131 is merged; the search needs server brief 132)
Branch: `claude/133-arestemis-angebote` · Worktree: `../empire-ios-133-arestemis-angebote` · **For a Claude agent**
(screens and their data part)

## Goal

Patrik (2026-11-02): with several searches, the Listings tab (German: "Angebote") gets unorganized: today it is one
list with a row of chips per search and the New · Saved · Applied · All switch on top of it. He chose this structure
from three drawn options:

- **Two parts at the top: "New" | "Searches"** ("Neu" | "Suchen").
  - **New:** everything new across all searches, **grouped under each search's name** ("Wohnung München · 3 neu"),
    the search with the newest finding first, newest first within it. This is where a push and the badge lead.
  - **Searches:** one row per search (name, its kind's symbol, the new count, saved and applied counts in a quiet
    line). Tapping one opens **today's view for just that search**: New · Saved · Applied · All ("Asked" for things,
    as today), its swipe actions, and its "Filtered out".
- **A search icon** in the header: type a name ("Kallax", "Aeron", "Schwabing") and see the found listings of all
  searches, **best match first** (server brief 132). On one search's page the same icon searches only that search.

The chip row goes away.

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules, Languages, the Arestemis app entry, strings, screenshots)
- `~/Arestemis/docs/API.md` → `GET /matches` and its `q` parameter (brief 132; if 132 is not merged yet, its brief
  `prompts/132-arestemis-listing-search.md` is the contract), `Overview.hunts` (`HuntCard.counts`)
- `Screens/ListingsScreen.swift` (today's tab), `Model/AppNavigation.swift` (`listingsPath`, `filter`, launch
  arguments), `Model/HuntsPresentation.swift` (`HuntChips`), `Model/ArestemisStore.swift` (match lists per filter,
  `selectedHuntID`, rejected), `Screens/HuntPage.swift` (its "Listings" button and the figures that open listings),
  `Screens/MatchRow.swift`, `Model/Notifications.swift` (a push opens a match), and their tests

## Build

1. **Navigation:** the Listings path can hold a search's page and a match (not only match ids). A push still opens its
   match; the hunt page's "Listings" button and its figures open that search's page (with the figure's filter).
2. **New:** the grouped list. Swipe to save or dismiss as today; a group disappears when its last new listing is
   handled; with a single search no group header is needed (your call). Empty: today's calm "Nothing new" line.
   "Filtered out" stays reachable (your call where: under New for all searches, and on each search's page for it).
3. **Searches:** the rows as above, in the Hunts tab's order; paused searches too (they keep their listings); a
   search of a kind this build does not know shows its name only. With no search: today's "No search yet" message
   and its button.
4. **One search's page:** today's switch and list for that one hunt, its name as the title, back to Searches.
5. **The search:** the icon opens a search field (keyboard up at once); results as the user types (from 2 characters,
   after a short pause), from `GET /matches?q=` (with `hunt` on a search's page), best match first, each row as today
   with its search's name and its state (new, saved, applied) visible; tapping opens the match; swipe actions as
   elsewhere. Nothing found: "Nothing found for "…"." / "Nichts gefunden für „…“.". Errors calm, with "Try again".
6. **Remembered:** the chosen part (New or Searches) across launches; nothing else new.
7. **Look:** the existing cards, rows, segmented control and section style; no new decoration; the accent only where
   today's screens use it. Check English and German, light and dark, and the largest text size on the New list.
8. **Launch arguments** for screenshots (`-listings new|searches`, `-openSearch <hunt id>`, `-search "<words>"`), and
   sample data with three searches (a flat, a thing, a page watch) so every screen fills on the simulator.
9. **Words:** English in code; `scripts/strings.py sync` (undo its changes to other apps' catalogs; restore
   `"Could not load older listings."` if it drops it), German with `fill`, `check` at 0 problems.
10. **Tests:** grouping and order of New, the Searches rows and counts, a search's page filters, navigation (push →
    match, hunt page → search page), the search's request (debounce, `hunt` on a search's page, minimum length) and
    its states (loading, empty, error), the remembered part.

## Settled: do not re-open

- "New | Searches" with the search icon (Patrik's choice, 2026-11-02). The server ranks; the app shows its order.

## Out of scope

- The server (brief 132), TestFlight (Claude), the Hunts tab.

## Check before you report

- `xcodebuild test -scheme Arestemis` on your own simulator (`claude-133`; boot it first).
- Screenshots `build/133-*.png`, each looked at yourself: New grouped (English and German, light and dark), Searches,
  one search's page, the search with results and with none.

## Final message

Files changed; build and test summary lines; screenshots; strings added (English and German); anything doubtful.
