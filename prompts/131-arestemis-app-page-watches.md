# 131: Arestemis app: page watches

Status: running (Claude agent, 2026-11-02)
Branch: `claude/131-arestemis-page-watches` · Worktree: `../empire-ios-131-arestemis-watch` · **For a Claude agent**
(screens and their data part)

## Goal

The server learns a third kind of hunt in brief 130 (Codex, at the same time as this brief): **watching a web page for
a change the user describes** ("when KALLAX costs under 45 €", "when the Mensa Garching has Schnitzel"). After this
brief the app can create, edit, pause and delete a watch, shows on its card what the page says now and whether it can
be read, and shows a found change as a match with a push. Today a watch would show only "Needs a newer app".

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules, Languages, the Arestemis app entry, how strings and screenshots work)
- The plan: `~/ares-empire/docs/ARESTEMIS-ANYTHING.md` → "Page watches" (what a watch is, the 17 test pages, what can
  and cannot be read and why)
- **The contract:** brief 130 → "Contract" (`prompts/130-arestemis-page-watches.md`, section 5). Codex is writing it
  into `/Users/pab/Arestemis-130-page-watch/docs/API.md` and `docs/samples/` while you work: read them there (never
  write there). If its final words differ from the brief, the server's `docs/API.md` wins; Claude reconciles at merge.
- The app: `Model/ArestemisModels.swift` (`HuntKind` with `.unknown`, `Hunt`, `HuntCard`, `Listing`),
  `Model/ItemModels.swift`, `Model/ItemSearchDraft.swift`, `Model/HuntsPresentation.swift`, `Model/Notifications.swift`
  (the two push categories), `Model/ArestemisSamples.swift`, `Screens/HuntsScreen.swift` (the "+" kind choice),
  `Screens/HuntCards.swift`, `Screens/HuntPage.swift`, `Screens/ItemSearchScreen.swift` and `FormFields.swift` (the
  form to follow), `Screens/MatchRow.swift`, `Screens/MatchDetailScreen.swift`, and the tests for each

## Build

1. **Data:** `HuntKind.watch`; `WatchSearch` (`url`, `change`, `every`); `PageState` on `HuntCard` (`page_title`,
   `host`, `now`, `read`, `checked`, `changed`, `note`) with an unknown `read` decoded leniently (shown as the note
   only); `Listing.page` (`added`, `removed`, `now`) and `source: "page"` (a source the app never lists as a site);
   the third push category `ARESTEMIS_WATCH` opening the match like the other two; sample data with a watch in each
   state the samples carry.
2. **The kind choice** ("+"): a third entry from `/kinds` ("Watch a page" / "Seite beobachten"), as the other two.
3. **The watch form**, in the style of the thing form:
   - **Page:** the address (URL keyboard, no autocorrection or capitals; pasting a whole shared text keeps only its
     first link).
   - **Tell me when:** the change in the user's words, a few lines; one placeholder example, short ("the price is under
     45 €" / "der Preis unter 45 € liegt"); 3–500 characters.
   - **How often:** 15 min, 30 min, 1 h, 3 h, 6 h, 12 h, daily; default 1 h.
   - **Name:** optional; empty = the page's title once read, else the host.
   - One short line under the form says what a watch cannot read yet: pages that need a login, or that build their
     content with JavaScript (for example appointment bookings). Your words; one sentence.
   - The server's refusals ("This address can't be watched.", "{site} has its own hunt in Arestemis.", "Describe the
     change to watch for.") appear at their field like the thing form's errors.
4. **The watch's card** (Hunts list and its page): name, host, the `now` line as the card's main fact ("KALLAX
   49,99 €"), last checked and last changed (relative, short), Start/Pause as the others. `waiting`: "Reading the
   page…" ; `unreadable`, `failing`, `blocked`: the server's `note`, in the same restrained style as the greyed sites
   (brief 119/129): no red alarm, and for `blocked` one hint that editing tries again.
5. **A found change** (match row and page): the summary as the title, host and time; on the page: "Now: …", the added
   lines and removed lines (removed ones visibly so, not by colour alone), "Open page" (the address), Save and Dismiss
   as for things (no application). `at_start` matches: "Already true when the watch started" / "Schon so beim Start
   der Beobachtung".
6. **Words:** English in code; `scripts/strings.py sync` (undo its changes to other apps' catalogs; restore
   `"Could not load older listings."` if it drops it), German with `fill`, `check` at 0 problems. German noun for a
   watch: "Beobachtung".
7. **Tests:** decoding (the search, `PageState` with each `read` and an unknown one, `Listing.page`, the kind in
   `/kinds`), the form draft (required fields, `every` choices and default, the name rule, the pasted-text link rule),
   the card's line per state in both languages, the push category, samples.

## Settled: do not re-open

- The server decides what can be watched and says why not; the app shows its words and never second-guesses an address.
- No share-sheet extension, no in-app browser preview, no picking a part of the page in this brief.

## Out of scope

- The server, Aresus, TestFlight (Claude).

## Check before you report

- `xcodebuild test -scheme Arestemis` on your own simulator (`claude-131`; boot it first with
  `xcrun simctl bootstatus <id> -b`, a cold simulator failed to launch the app once in brief 129).
- Screenshots `build/131-*.png`, each looked at yourself: the kind choice with three kinds; the watch form empty and
  filled, English and German, light and dark; the Hunts list with a watch `ok` (a `now` line) and one `blocked`; a
  found change's page with added and removed lines; an `at_start` match.

## Final message

Files changed; build and test summary lines; screenshots; strings added (English and German); where the contract in
`docs/API.md` differed from brief 130, and anything doubtful.
