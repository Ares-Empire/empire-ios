# 149: Arestemis app: several search words in one thing search

Status: merged 2026-11-03 (Arestemis build 15)
Branch: `claude/149-several-words` · Worktree: `../empire-ios-149-several-words` · **For a Claude agent** (design)

## Goal

Patrik (2026-11-03): "if I want to search for multiple similar items at once, does that need multiple searches? My
usecase: ties from different manufacturers, maybe even with diff colors depending on manufacturer." He approved up to
five search words in one thing search (plan https://claude.ai/artifact/FBXeut5PmPNm3JqTeu38F1, section 2, and its phone
sketch). The server side is the Arestemis repo's brief 148, running now; the contract is already in
`~/Arestemis/docs/API.md` → `ItemSearch.more_queries` (CONTRACT ADDITION 2026-11-03):
- `query` stays the first word;
- `more_queries` holds up to four more, each 2–100 characters, none repeating another (case- and accent-insensitive);
- refusals come as `400` with `field: "search.more_queries[1]"`.

After this brief the thing form takes up to five search words as chips, and one description says what fits per word.

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules, Languages, the Arestemis app entry: the thing form, New search and its
  examples, names and renaming).
- `Arestemis/Arestemis/Screens/ItemSearchScreen.swift`, `Model/ItemSearchDraft.swift`, `Model/ItemModels.swift`,
  `HuntText.automaticTitle`, the form pieces in `Screens/FormFields.swift` and Shared (`SearchBox`, chips, `NameField`).
- The plan's sketch, section 2.

## Build

1. **Data:** `ItemSearch.moreQueries` (`more_queries`, decoded leniently: absent = `[]`), carried by the draft, sent
   when saving, kept in a kept draft; the server's field refusals shown under the words field.
2. **The field "Search words" / "Suchbegriffe"** (replacing today's single search field, first in the form after Name):
   the words as chips in the app's accent tint with a small ×, and a text field after them; Return or a comma adds the
   typed word as a chip; up to five (then the field hides and a quiet line says five is the most); a word repeating
   another is not added (a quiet line says why). The first chip is `query`, the rest `more_queries`. A long press or a
   drag reorders only if it comes naturally; not required. VoiceOver reads each chip and its remove action.
3. **The description field:** today's "Extras" with the caption "Anything else: size, colour, with box …". Make it
   clearly the place for what fits per word: label "What fits" / "Was passen soll", placeholder e.g. "Hermès only in
   blue, Ferragamo red or burgundy. Silk, new or like new." / "Hermès nur in Blau, Ferragamo in Rot oder Bordeaux.
   Seide, neu oder wie neu.", no extra caption if the placeholder says enough. Same field (`extra`) underneath.
4. **Names:** the automatic name (grey placeholder in Name) and the cards: the hunt name, else the first word and
   "+ 2" ("Hermès Krawatte + 2"), both languages.
5. **The search's card and page** show the words compactly (first word, "+ 2"), and the page lists them all where it
   lists the search's settings today.
6. **New search's Dinge example** stays as it is unless a two-word example reads better; your call.
7. **Words:** English in code; `scripts/strings.py sync` (undo changes to other apps' catalogs; restore `"Could not
   load older listings."` if dropped), German with `fill`, `check` at 0 problems.
8. **Samples:** one sample thing hunt with two or three words; when the server's `docs/samples/` gain `more_queries`
   (brief 148), Claude copies them, so read the field leniently.
9. **Tests:** decoding with and without the field, adding and removing chips (limit, repeats, Return and comma),
   what is sent, field refusals per index, the automatic name and card text in both languages.

## Out of scope

The server (brief 148), automatic site picking, the Preismonitor's "Überall", TestFlight (Claude).

## Check before you report

- `xcodebuild test -scheme Arestemis` on your own simulator (`claude-149`; create and boot it; iOS 27.0 runtime;
  screenshots from the app installed on that simulator itself, since `xcodebuild test` runs on clones).
- Screenshots `build/149-*.png`, German and English, light and dark:
  - the thing form with three words and the description;
  - the five-word limit;
  - a repeated word refused;
  - a server refusal under the field;
  - the hunt's card and its page.

## Final message

Files changed; build and test summary lines; screenshots; strings added (English and German); anything doubtful.
