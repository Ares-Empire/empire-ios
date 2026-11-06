# 187: Arestemis app: "Muss sein" and "Wäre schön" in the Dinge form; listings not checked in time

Status: open.
Branch: `claude/187-wishes` · Worktree: `../empire-ios-187-wishes` · Builder: Claude agent (design)

## Goal

Two server changes of 2026-11-06 reach the app.

1. **Must and nice wishes.** A Dinge search had one "What fits" text. The AI read "Rot" in Patrik's tie search as a soft
   wish and passed ties of every colour; it also passed wrong sizes. Patrik, asked whether a wish like "Rot" is a must
   or a nice-to-have: the app should ask the person ("asking is good"). The server (brief 185) now has two fields:
   `extra` = **Muss sein / Must have** (a listing that clearly breaks one is sorted out, and the server's rules can now
   check sizes, colours and materials against the sites' own fields) and `nice` = **Wäre schön / Nice to have** (never
   sorts a listing out). The form asks by giving the two their own places.
2. **Not checked in time.** When too much arrives for the free checking capacity, a thing listing that could not be
   checked within 24 hours used to vanish quietly. The server (brief 186) now keeps it for 7 days as **not checked**: a
   count on each search and a list. The person can look at those listings themselves. It is never a list of misfits.

The server is built and deployed: build from the contract.

## Read first

- `AGENTS.md` and `CLAUDE.md` (always: the design rules at the top, "Languages", "Light mode", the Arestemis entry, above
  all "Angebote as New | Searches"), `~/ares-empire/EMPIRE.md` → design language.
- The contract in `~/Arestemis/docs/API.md`: search for "brief 185" (`ItemSearch.nice`, `POST /search/parse` filling
  both) and "brief 186" (`Counts.not_checked` on hunt cards and the overview, `NotChecked`, `GET /not-checked?hunt=&limit=`).
  Server samples: `~/Arestemis/docs/samples/not-checked.json`, `hunts.json`, `overview.json` and the price-everywhere
  samples (now with `not_checked` in counts): copy the changed ones into `ArestemisTests/ServerSamples/` and decode them
  in `ServerSamplesTests`, as brief 182 did.
- Code: `Screens/ItemSearchScreen.swift` ("What fits", `-itemFits`), `Model/ItemSearchDraft.swift` (draft, validation,
  `parse` merge, coding), `Model/ItemModels.swift` (`ItemSearch` coding), `Model/ProductSuggestions.swift` (sets
  `extra`), `Screens/FormFields.swift` (`TextArea`, `ExtrasField`, `Caption`), `Model/ArestemisModels.swift` (`Counts`),
  `API/ArestemisAPI.swift`, sample mode's backend, `Model/ArestemisStore.swift` (`rejected`/`loadRejected`, brief 182's
  recent list), `Screens/ListingsScreen.swift` and `Screens/SearchListingsPage.swift` (Filtered out's and Recently
  viewed's row: brief 182 made one row component for both), `Screens/ListingRows.swift`, `Localizable.xcstrings`, the
  tour (`Model/TourData.swift`), and the tests next to them.

## Build

### 1. Two places for wishes (Dinge form only)

- "What fits" becomes two fields, in this order, in the same glass look: **Muss sein** (`extra`) and **Wäre schön**
  (`nice`), each with a short caption that says what it does: Muss: listings that clearly break it are sorted out; Wäre
  schön: never sorts anything out, a listing that has it says so. Placeholders that teach by example from one search
  (e.g. Muss "Größe 43, 100 % Seide", Wäre schön "Rot oder Bordeaux"; en "Size 43, 100% silk" / "Red or burgundy").
  Your layout: one section with two fields or two sections; keep it calm and short, the form is already long.
- Each at most 1,000 characters with the existing problem line; `nice` decodes missing as `""` (old searches and old
  servers), is sent always, counts for "changed" (Save enabled), and is filled by "describe it" (`POST /search/parse`
  returns soft wishes in `nice`); `ProductSuggestions` keeps writing `extra` only.
- An old search opens with its text under Muss sein and Wäre schön empty; nothing moves by itself.
- DEBUG: `-itemNice <text>` next to `-itemFits`.
- Flats keep their one Extras field (out of scope).

### 2. Not checked in time

- Decode `Counts.not_checked` (missing = 0) on hunt cards and the overview.
- Where Filtered out's row is (Angebote → Neu over all searches, and a search's own listings page), one more row with
  the same row component: **Nicht rechtzeitig geprüft** / **Not checked in time** with its count, shown only when the
  count is above 0. Pick a calm symbol (e.g. `hourglass`); not red, not a warning.
- The row opens a page (on the Angebote stack, like Recently viewed): one quiet line on top in plain words, "du", no
  "KI"/"AI" (for example de "Zu diesen Angeboten kam die Prüfung nicht rechtzeitig. Schau sie dir selbst an; sie bleiben
  7 Tage hier." / en "These listings could not be checked in time. Have a look yourself; they stay here for 7 days.";
  word them better if you can), then the items newest first: title (or "Ohne Titel" / "Untitled" when null), price
  when known, site, when it arrived, in a simple row that fits beside the listing rows without pretending to be one
  (no photo, no swipes, no star; they are not matches). A tap opens the link in the browser the app uses for listing
  links; a row without a link is not tappable. Over all searches each row carries its search's mark and name, as
  Recently viewed does. Loading, empty and failure as the other lists; pull to refresh.
- Store: `notChecked(hunt:)` loads with Neu and on pull to refresh, like Filtered out and Recently viewed; sample mode
  imitates it (a few items, one without title/link). DEBUG `-openNotChecked`.

## Settled: do not re-open

- Muss sein = `extra`, Wäre schön = `nice`; the server decides what happens with them.
- Not-checked listings are only a list: no state, no swipes, nothing to dismiss; the server prunes after 7 days.
- No new component style beyond the simple not-checked row; Filtered out's row component for the entry.

## Out of scope

- The server; flats' Extras; Favoriten; push texts.

## Done when

- `xcodebuild test` passes on your own simulator (commands in `AGENTS.md`), with new tests for: `nice` coding (present,
  missing), validation and dirty state; describe-it filling both; an old search opening with Wäre schön empty;
  `not_checked` decoding (present, missing) and `not-checked.json`; the row shown only above 0 with its count, over all
  searches and per search (asking with `hunt`); a row without link not opening anything; the words in both languages.
- `scripts/strings.py check` says 0 problems.
- Screenshots in `build/187-*.png`, light and dark, German and English, at the smallest phone width: the Dinge form with
  both fields (empty with placeholders, and filled), Angebote → Neu with the not-checked row under Filtered out, the
  not-checked page, a search's listings page with its row.

## Final message

Files changed, the exact build and test summary lines, the screenshot paths, new DEBUG arguments, what is missing or
doubtful.
