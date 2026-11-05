# 178: Arestemis app: "Meintest du …" for misspelled search words, and a better page for a watch

Status: draft
Branch: `claude/178-spelling-better-page` · Worktree: `../empire-ios-178-spelling` · Builder: Claude agent (design)

## Goal

Patrik's first test searches (2026-11-05) showed two gaps:

- He searched Dinge for "Zenga Krawatte"; the brand is **Zegna**, and the word found nothing useful. He asked for a
  correction to be suggested ("a false suggestion isn't that bad"). After this brief, saving a Dinge search with a
  likely misspelled brand or model word shows **"Meintest du „Zegna Krawatte“?"** under the words; one tap takes it.
- A watch reads only the page it is given. When that page only names or links to the thing (a shop's homepage with
  a teaser), the watch shows **its own page as a suggestion**; one tap opens the watch's form with that address.

The server (Arestemis brief 177) is built at the same time; build from the contract below, not from its code.

## Read first

- `AGENTS.md` and `CLAUDE.md` (always: the design rules at the top, "Languages", "Light mode", the Arestemis entry),
  `~/ares-empire/EMPIRE.md` → design language.
- The contract: `~/Arestemis/docs/briefs/177-spelling-and-better-page.md` (sections 1–3) and `~/Arestemis/docs/API.md`
  → "Things for sale", "Page watches".
- `Arestemis/Arestemis/Screens/ItemSearchScreen.swift` (`saveSearch`), `Screens/SearchWordsField.swift` (the words and
  their chips), `Screens/PriceSearchScreen.swift` (`productChoices`: the existing "Meintest du …" chips; reuse their
  look), `Screens/WatchSearchScreen.swift`, `Model/WatchModels.swift` (`PageState`), the watch's card and page
  (`Screens/HuntCards.swift`, `Screens/HuntPage.swift`, `Model/HuntsPresentation.swift`), `API/ArestemisAPI.swift`,
  `Model/ArestemisSamples.swift`, `Localizable.xcstrings`, and the tests next to them (`SearchWordsTests`,
  `ItemSearchDraftTests`, `WatchTests`, `ProductSuggestionsTests`).

## Build

### 1. Dinge: check the words when saving

- `ArestemisAPI.spelling(words:)` → `POST /search/spelling` `{words}` → `{suggestions: [{word, suggestion}], checked}`.
  The words are the search's `query` followed by its `more_queries`, as the form will save them.
- On save, when these words were not checked yet in this form session: ask, with a **5-second limit**. Any error,
  timeout, `checked: false` or an empty list → save as today, with no message.
- With suggestions: **do not save yet.** Under the words field, for each suggestion, the existing chip look with
  the heading "Meintest du …" / "Did you mean…" (as in `productChoices`); the chip shows the corrected entry. A tap
  replaces exactly that entry (the main words or that extra word) in the draft and removes the chip. The save button
  stays as it is: tapping it again saves the words as they are now, without asking again for words already checked.
  Changing the words by hand removes the chips; the new words are checked on the next save.
- While the check runs (usually under a second), the save button shows its normal busy state; no new spinner.
- Editing an existing Dinge search behaves the same.
- Überall needs no app change: the server puts a corrected product name first in the refusal's `suggestions`, which
  the existing chips already show.

### 2. Watches: the suggested page

- Decode `PageState.suggested` (`{url, title}` or null; missing = null) and encode it back.
- When present, the watch's page (and, if it fits calmly, its card in the Hunts list) shows one quiet line under the
  page's state: **„Adventskalender 2026“ hat eine eigene Seite** (en: **"Adventskalender 2026" has its own page**)
  with an accent action **„Diese Seite beobachten“** (en: **"Watch this page"**). Patrik's words for the idea:
  "Diese Seite beobachten?". You may word the line better; keep it short, plain and without "KI"/"AI".
- The action opens the watch's own edit form with the address replaced by the suggested one (nothing is saved until
  the user saves; saving starts a new first read as any address change does).
- The title is page content: show it verbatim, one line, truncated in the middle if long.

## Settled: do not re-open

- The user decides; nothing is replaced or saved by itself. A false suggestion is acceptable.
- The check runs on save, not while typing.
- No "this word finds nothing" note.
- Same chip look as the Überall "Meintest du …"; no new component style.

## Out of scope

- The server; flats; Überall screens; existing searches (no back-check).

## API

- `POST /search/spelling` `{words: string[]}` (1–5 entries, 2–100 characters each) → `{suggestions: {word,
  suggestion}[], checked: boolean}`; always 200 for valid input, also when the check could not run.
- `PageState.suggested: {url: string, title: string} | null` in `HuntCard.page`.
- Samples to add in `ArestemisSamples.swift`: one spelling answer with a suggestion, one with `checked: false`, and one
  watch card with `suggested` (an invented shop: "Beispiel Bandshop", "Adventskalender 2026",
  `https://shop.example.com/catalog/adventskalender-2026.html`).

## Done when

- `xcodebuild test` passes on your own simulator (commands in `AGENTS.md`), with new tests for: decoding both
  additions (present, missing, `checked: false`), the save flow (suggestions hold the save; a tap replaces exactly one
  entry; a second save with checked words saves; an error or timeout saves at once; hand edits clear the chips), and
  the watch suggestion opening the form with the new address.
- Screenshots in `build/178-*.png`, light and dark, German and English, at the smallest phone width: the Dinge form
  with one and with two suggestions (main words and an extra word), and a watch page with a suggestion (long title too).

## Final message

Files changed, the exact build and test summary lines, the screenshot paths, what is missing or doubtful.
