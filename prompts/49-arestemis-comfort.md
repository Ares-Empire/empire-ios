# 49: Arestemis comfort before its first TestFlight build (Patrik's list nos. 13–19)

Status: merged 2026-10-30 (91 tests; every changed screen checked in both languages and looks; Claude: undo bar before the counts reload, the header Save in the accent)
Branch: `codex/49-arestemis-comfort` · Worktree: `../empire-ios-49-arestemis-comfort` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Patrik approved the comfort list for Arestemis (2026-10-30, all items). After this brief a dismissed listing can be
brought back, the Hunt tab's latest listings can be saved or dismissed without opening them, Search's changes are hard
to lose, small buttons are easy to hit, Listings loads on as you scroll, Add place's keyboard key says what it does,
and "More" on a match page is a proper button. Arestemis goes to Patrik's iPhone right after this.

Three other briefs run at the same time: 50 (Aresus), 51 (Arestoteles), 52 (Empire and the shared Create account).

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Languages", "Light mode", the "Arestemis app" entry under Setup state)
- `docs/reviews/2026-10-30-swipe-and-comfort.md` → "The other four apps" → "Arestemis": what was found, with file
  and line references
- `Shared/Design/UndoBar.swift` (new, by Claude: `UndoOffer` and `.undoBar(_:accent:)`; use it, do not restyle it)
- `Arestemis/Arestemis/Screens/`: `ListingsScreen.swift`, `HuntScreen.swift`, `MatchDetailScreen.swift`,
  `MatchRow.swift`, `SearchScreen.swift` (with `PlaceSearchSheet`), `Style.swift` (`Chip`, `ProvinceButtonStyle`,
  `AppHeader`); `Model/ArestemisStore.swift`, `Model/SearchDraft.swift`, `Model/AppNavigation.swift`
- The server: `~/Arestemis/src/arestemis/api.py` (`POST /matches/{id}/state` accepts any of new, saved, applied,
  dismissed, so undo is setting the state the listing had before). Read only; nothing changes there.

## Build

1. **Undo for Dismiss** (list no. 13). Whenever a listing is dismissed (Listings' swipe left, its VoiceOver action, the
   match page's state menu, and the new menu of item 2), show the shared undo bar: "Listing dismissed." with Undo,
   which sets the state the listing had before (new, saved or applied) and puts it back where it was in the lists.
   The offer lives in the store (`ArestemisStore.undo: UndoOffer?` or similar), so it survives the match page closing
   after a dismiss. Attach `.undoBar(…, accent: Look.accent)` on the Listings and Hunt tabs' `NavigationStack`s
   (outside them), so the bar shows on the list the match page goes back to. If the dismiss itself failed and was
   rolled back, no undo bar.
2. **Actions on Hunt → Latest** (list no. 14). A long press on a listing row (Apple's `contextMenu`) offers what the
   row's state allows: Save (when new), Mark applied, Dismiss, with the same icons as the match page's state menu. Add
   the same long-press menu to Listings' rows too, so the two lists behave the same. Listings keeps its swipes; Hunt's
   Latest is a short stack in a scroll view, not a `List`, so it gets no swipe. Build the menu once and use it in
   both places (a modifier or a small view next to `MatchRow`), not two copies.
3. **Search: harder to lose changes** (list no. 15).
   - While the form differs from the saved search (`isDirty`) and the form is valid, the header (`AppHeader`'s
     trailing slot) shows **Save** in `.quiet` style, doing what the bottom button does (spinner while saving). The
     bottom button stays.
   - **The draft is kept**: unsaved changes survive leaving the tab and closing the app. Keep the draft with the
     search it started from in the app's own `UserDefaults` (not the shared App Group), keyed by the account id
     (`EmpireSession`); make `SearchDraft` `Codable` for it. On opening Search: if a kept draft exists and the
     server's search still equals the one it started from, show the draft (dirty, so Save shows); if the server's
     search changed meanwhile (another device), drop the draft and show the server's. Saving or deleting the search
     drops it. When the app forgets its data at logout (find the hook the store already uses, e.g.
     `onAppDataReset`), drop it too. Unit tests for: kept and restored, dropped when the server changed, dropped on
     save, another account's draft never shown.
4. **44 pt tap areas on the chips' buttons** (list no. 16). The × on a place or area chip (`Chip.onRemove`) and the +
   that adds an area are drawn 22 × 22 pt: keep the drawn size and the layout, make each take taps over at least
   44 × 44 pt. No changes to the chips' look.
5. **Listings loads on** (list no. 17). Replace "Show older" with loading the next page when the end of the list comes
   into view (`loadMatches(filter, more: true)`, once at a time). While it loads, a small spinner row at the end; if it
   fails, that row says the store's error with Try again (the existing `CalmMessage` with its action). Pull to refresh
   unchanged.
6. **Add place's keyboard key** (list no. 18; Patrik chose option (b) on 2026-10-30, do not re-open). In
   `PlaceSearchSheet` the key's label changes from Search to **Done** (`.submitLabel(.done)`); pressing it closes the
   keyboard, as today. Nothing else changes: towns are still added by tapping them.
7. **"More" on a match page is a regular button** (list no. 19, `MatchDetailScreen.swift` around line 221): the
   app's `.quiet` button style (at least 36 pt tall) instead of 13 pt bare text, leading aligned as now.

## Settled: do not re-open

- No new looks: Apple's controls, `Shared/Design`, and Arestemis's own `Style.swift` pieces only. The undo bar is the
  shared one, as it is.
- Undo restores the state from before; it does not delete anything on the server.
- The draft stays on this iPhone, never in the shared App Group, and goes with logout.

## Out of scope

- `Shared/` (other briefs run there; you only use `UndoBar.swift`), other apps, the Arestemis server.
- The look of rows, chips and headers beyond what each item says.
- `project.pbxproj`.

## API

Existing only: `GET /matches?state=…&limit=…&before=…`, `POST /matches/{id}/state` `{state}` (any of the four
states), `PUT /hunts/{id}` (save), all already in `API/ArestemisAPI.swift`. Nothing new.

## Done when

- `xcodebuild test -project Arestemis/Arestemis.xcodeproj -scheme Arestemis` passes on your own simulator
  (`codex-49`, commands in `AGENTS.md`), with new tests for: undo restoring each earlier state (and none after a
  failed dismiss), the draft rules in item 3, loading on not asking twice at once.
- `scripts/strings.py sync` then `scripts/strings.py check`: 0 problems. Write the German yourself for this brief
  (du, short; Arestemis's terms: Jagd, Angebote, Suche), and keep it also in `build/49-de.json` (the `fill` input) so
  Claude can fill it again if the catalog conflicts at merge.
- Looked at on the simulator in English and German, light and dark (`-sampleData`): screenshots `build/49-*.png` of
  the undo bar on Listings, the long-press menu on Hunt → Latest, Search with Save in the header, the loading row at
  Listings' end, Add place's keyboard with Done, the match page's More. Add DEBUG launch arguments where a state cannot
  be reached otherwise (for example `-sampleUndo`, `-sampleSearchDraft`), and list them in your final message.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, the launch
arguments you added, the German strings you added, what is missing or doubtful. Never commit, push or merge: Claude
does.
