# 51: Arestoteles comfort before its first TestFlight build (Patrik's list nos. 23–26)

Status: draft
Branch: `codex/51-arestoteles-comfort` · Worktree: `../empire-ios-51-arestoteles-comfort` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Patrik approved the comfort list for Arestoteles (2026-10-30, all items). After this brief no sheet throws away typed
text without asking, note pages keep the tab bar, a position can be added from the top of Positions, and To discuss →
Done can be undone.

Three other briefs run at the same time: 49 (Arestemis), 50 (Aresus), 52 (Empire and the shared Create account).

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Languages", "Light mode", the "Arestoteles app" entry under Setup state)
- `docs/reviews/2026-10-30-swipe-and-comfort.md` → "The other four apps" → "Arestoteles"
- `Shared/Design/UndoBar.swift` (new, by Claude: `UndoOffer` and `.undoBar(_:accent:)`; use it, do not restyle it)
- `Arestoteles/Arestoteles/Screens/Sheets.swift` (every sheet; the Edit text sheet, around lines 155–180, is the
  pattern to copy), `NoteScreen.swift`, `PositionsScreen.swift`, `Style.swift`;
  `Model/VaultStore.swift` (`setInboxStatus(of:processed:)`: `processed: false` sets the note back to "new"),
  `Model/AppNavigation.swift`, `ContentView.swift`

## Build

1. **Sheets ask before discarding typed text** (list no. 23). Quick note, Edit passage, Reword, Change my view and Add
   a position close on swipe down or Close and throw the text away without asking. Make each behave as Edit text
   already does: while the person typed or changed something, swipe down is held back
   (`interactiveDismissDisabled`) and Close or Cancel asks "Discard your changes?" (Discard, destructive; for a new
   text such as a quick note, "Discard this note?") through the same `confirmationDialog`; with nothing typed or
   changed, they close at once. Put the "has something to discard" rule for each sheet in its model or a small pure
   function, with unit tests (a text typed then cleared again is nothing to discard; a loaded text unchanged is
   nothing to discard). Quick notes that are waiting to send are not affected (they are kept by the store already).
2. **Note pages keep the tab bar** (list no. 24). Remove `.toolbar(.hidden, for: .tabBar)` from `NoteScreen`, so after
   following links several notes deep, a tap on the tab goes back. Check that tapping the current tab returns to the
   tab's root (SwiftUI usually does this for a `NavigationStack` in a `TabView`; if it does not here, reset the tab's
   path in `AppNavigation`). Check that nothing at the bottom of a note page sits under the tab bar now (scroll to a
   long note's end).
3. **A + for Add a position** (list no. 25). Positions' header gets a `GlassIconButton` with `plus` (label "Add a
   position") next to the existing header buttons, doing exactly what the button at the end of the list does (same
   target, hidden when there is no target, disabled while sending). The button at the end stays.
4. **Undo for To discuss → Done** (list no. 26). After Done in the To discuss sheet, show the shared undo bar in that
   sheet: "Marked as discussed." with Undo, which sets the note back (`setInboxStatus(of:processed: false)`) so it
   returns to the list. If marking failed, no undo bar. Unit test: Undo sends the reverse status for the same note.

## Settled: do not re-open

- No new looks: Apple's controls, `Shared/Design` and Arestoteles's own `Style.swift` pieces only. The undo bar is the
  shared one, as it is. The discard question is the one Edit text already uses.

## Out of scope

- `Shared/` (other briefs run there; you only use `UndoBar.swift`), other apps, the Arestoteles server.
- `project.pbxproj`.

## API

Existing only: the vault edit ops already in `Model/VaultStore.swift` (`setInboxStatus` with status `processed` or
`new`). Nothing new.

## Done when

- `xcodebuild test -project Arestoteles/Arestoteles.xcodeproj -scheme Arestoteles` passes on your own simulator
  (`codex-51`, commands in `AGENTS.md`), with the new tests above.
- `scripts/strings.py sync` then `scripts/strings.py check`: 0 problems. Write the German yourself (du, short), and keep
  it also in `build/51-de.json`.
- Looked at on the simulator in English and German, light and dark (`-sampleData`): screenshots `build/51-*.png` of a
  discard question in Quick note and in Reword, a note page with the tab bar (`-openNote <id>`), Positions' header
  with the + (`-tab positions`), the undo bar in To discuss (`-openSheet discussions`). Add DEBUG launch arguments
  where a state cannot be reached otherwise, and list them in your final message.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, the launch arguments
you added, the German strings you added, what is missing or doubtful. Never commit, push or merge: Claude does.
