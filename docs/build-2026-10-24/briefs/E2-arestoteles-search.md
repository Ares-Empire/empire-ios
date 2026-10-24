# E2: Arestoteles: a search field in each tab, and meaning search in the Search tab

Read `E-COMMON.md` first, then `E-search-contract.md`, `ares-empire/docs/ARESTOTELES-APP.md` (the decisions) and the
Arestoteles section of `~/empire-ios/CLAUDE.md`. Worktree: `~/wt/empire-ios-arest-search` (branch
`arestoteles-search`). Simulator: `agent-arest-search`. Do not edit `Shared/`. Run the app with `-sampleData`.

Patrik uses the app for quick lookups ("usually I just want to quickly look up a fact or a little aspect I cant fully
remember or a figure or a source"). Study the current screens first (`Screens/`, especially `SearchScreen.swift`,
`Style.swift`, `PositionsScreen.swift`, `TopicsScreen.swift`, `LibraryScreen.swift`) and stay in their look.

## 1. A search field in Positionen, Themen and Bibliothek

Patrik: "can we add search bars to the individual tabs that search within the individual tabs for quicker and better
access?"

- Each of the three tabs gets a search field at the top of its content, under the header, scrolling with the content
  (like iOS's own list search fields), in the same look as the Search tab's field. Typing filters the tab at once; the
  query's words are marked in the rows the way the Search tab marks them; × clears; scrolling dismisses the keyboard.
  No match: one calm line naming the query.
- **Positionen:** a position's title and text. **Themen:** a topic's title, summary and its section headings.
  **Bibliothek:** while a query is typed, matches from **all** kinds (each row shows its kind's small label);
  clearing returns to the chosen kind.
- The matching is `VaultSearch`'s (folding, every word must appear); put the filtering in `Model/` (unit-tested), no
  second folding function, no logic in the views.
- DEBUG launch argument `-tabSearch <query>` (with `-tab …`) for screenshots.

## 2. Meaning search in the Search tab

The server gets the route in `E-search-contract.md` (built at the same time by E3; the contract is final).

- As now, the device's results appear at once while typing.
- When typing pauses (about 0.4 s) and the query has at least 3 letters, ask `GET /search`; a newer query cancels the
  older request. The server's results come first, under a small heading ("Best matches" / "Beste Treffer"): up to 8
  rows, each with the note's title and the heading (small, muted), the `sentence` (body text, the query's words marked
  as now; a meaning-only row has none marked), tap: the note scrolled to that passage and highlighted (`NoteLink`
  with `block`) or, for a `position`, the position's page. Below, the device's results as now, without the passages
  already shown above.
- No connection, an error, a 503 or a timeout (5 s): only the device's results, no error shown. No spinner that
  flashes: show a quiet placeholder only if the answer takes longer than about 0.6 s. Results for an older vault
  commit than the app's are still fine to show; a passage whose `note`/`block` no longer exists in the app's vault is
  left out.
- Types and decoding in `Model/`, the request in `API/` beside `/vault` (same token, same 401/403 handling through
  `session.handleAuthFailure`), the state (debounce, cancel, merge with the device's results) in a small model object,
  unit-tested. Sample mode answers every query with `Samples/search.json`: write it by hand from the contract, with
  passages that exist in `Samples/vault.json` (the lead replaces it with the server's sample when merging).

## Done when

- `xcodebuild test` for Arestoteles passes; `scripts/strings.py check` says 0 problems.
- Screenshots (German, and one in English): each tab with a query typed and with no match; Bibliothek showing
  matches from several kinds; the Search tab with best matches above the device results; a tap on a best match landing
  on the highlighted passage.
