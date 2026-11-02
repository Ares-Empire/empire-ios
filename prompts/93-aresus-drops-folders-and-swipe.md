# 93: Aresus app: new folders in the picker, swipe to delete, the sheet closes with one swipe

Status: open
Branch: `claude/93-drops-folders-swipe` · Worktree: `../empire-ios-93-drops-folders-swipe` · Built by a **Claude
agent** (design work, `CLAUDE.md` → Workflow) · Simulator: `claude-93` (create it: iPhone 17, iOS 27.0)

## Goal

Patrik sent his first file from the phone to the MacBook (build 2, briefs 88–91) and it worked. His notes from that
first try, 2026-11-02:

1. "Is it possible to allow me to create and navigate inside folders from the phone?" Today the picker opens only
   folders that contain other folders (one without is chosen with a tap), and a new folder is a separate text field on
   the send sheet, away from where he browses.
2. The drop history: the tab already shows the newest three and "Show all" (keep that). He wants **each history item
   swipeable and deletable like in Mail**.
3. "The screen it opens should be closeable via swipe": the send sheet. It opens at medium height and grows to large
   once something is picked; a swipe down from large only shrinks it to medium, so closing takes two swipes.
4. (Server, brief 92, built in parallel: the push now says "<name> delivered", and `DELETE /drops/{id}` removes a
   drop in any state.)

## Rules for you

- Read and follow `AGENTS.md` and `CLAUDE.md` of this repo (worktree only, never commit or push, no new packages, no
  `project.pbxproj` edits, light and dark from the shared colour pairs, logic out of views with tests, English in code
  + German in the String Catalogs, `scripts/strings.py sync`/`check`).
- **Design language:** `~/ares-empire/EMPIRE.md` → "The crown language" and "How we build apps"; brief 91's screens
  are the reference (`Aresus/Aresus/Screens/SendSheet.swift`, `FolderPicker.swift`, `DropsSection.swift`) and
  `Shared/Design/`. Patrik's taste: classy, calm, quiet; the lightning-blue accent only on the key control; plain small
  labels, no slogans.
- No real personal data anywhere (samples are made up).

## Read first

- `prompts/91-aresus-drops-screens.md` (what the screens are and why), then the screens above and their models:
  `Model/SendDraft.swift`, `DropFolderTree.swift`, `DropDisplay.swift`, `DropNames.swift`, `DropsStore.swift`
  (`remove`), `DropRecentFolders.swift`.
- `~/aresus/docs/API.md` → "Drops" (the 2026-11-02 note: delete in any state, `404` = already gone; `new_folder` is
  **one** folder name made inside `folder`, which may be `""` = the root).
- `Aresium/Aresium/Screens/RowSwipe.swift` (Aresium's Mail-like swipe for rows in a `LazyVStack` in a `ScrollView`,
  brief 44; its header comment explains every choice) and `Shared/Design/BackSwipe.swift`.

## Build

1. **One swipe for both apps.** Move `RowSwipe.swift` to `Shared/Design/` with `git mv` (it uses only `Ink` and
   UIKit, both in Shared). Keep its API and behaviour for Aresium exactly as they are; add only what Aresus needs: an
   action role for a destructive action (Delete), drawn in the soft red Settings uses for Leave and Delete account
   (find that colour pair in `Shared/Design`; do not invent a new red). Nothing in Shared may use
   `UIApplication.shared` (the Aresium widget compiles Shared): check that the widget still builds. Aresium's own
   tests that pin `RowSwipeRule` must still pass. Tell Claude in your final message if anything in Aresium had to
   change.
2. **Swipe to delete every drop row**, on the tab's three and in Show all: swipe left (as in Mail and in Aresium),
   **Delete** at the row's end (trash symbol over the word, Mail's), a full swipe deletes at once. Every row, every
   state: on the phone (stops the upload, the outbox forgets it), uploading / waiting / failed (the server cancels it;
   the Mac never gets it), landed and cancelled (gone from the list; the file on the Mac stays). No question first
   (Mail asks none). The row leaves at once with the list's usual animation; if the server refuses, it comes back
   and the section's "Not refreshed: …" line says why. A `404` counts as deleted (the data side: `DropsStore.remove`
   and `DropRow.canRemove`, with tests). The long press keeps Try again where it applies and says **Delete** instead
   of Remove; VoiceOver gets the same actions. One row open at a time; it closes on scroll and on a tap elsewhere, as
   in Aresium.
3. **New folders where you browse.** In the folder picker:
   - Every folder can be opened, also one with no folders inside (its page then says so quietly under the new
     folder row). Every folder row gets the chevron. The page's first row stays "Choose <folder>". Recent folders and
     search results still choose with one tap.
   - Under "Choose <folder>" on every folder page, Documents' and Downloads' own pages included: **New folder**. It
     asks for the name where it stands (your call: an inline field in the card, as Files does, or Apple's name-field
     alert as Aresium's category rename, brief 80; the rule must be readable before sending, so an inline field with
     the failed rule under it is probably better), checked as you type with `DropNames.newName`; Return or a Create
     button makes it. A name that matches a folder already there (ignoring case, as the Mac's disk does) chooses that
     folder instead. Creating chooses `<this folder>/<new name>` and goes back to the send sheet, as choosing does.
   - Nothing is made on the Mac until the file is sent (the Mac makes the folder when the drop lands). One new folder
     per send, so a page reached through a new folder does not exist; the send sheet shows the choice.
   - **The send sheet's separate New folder field goes away.** Its Folder row shows the full place with the new
     folder in it and a quiet mark that it is new (for example `Documents › Studium › EIST › Blatt 3` with
     `folder.badge.plus`, or "new" in muted text; your call). `SendDraft` keeps the new folder as data, set by the
     picker; recent folders keep remembering a target with its new folder (`DropRecentFolders`, `DropFolderTree.start`
     already resolves it once the Mac lists it).
4. **The send sheet closes with one swipe down** at any height. Keep the medium start for the three choices and the
   large sheet once something is picked, but never two heights at once (for example `[.medium]` before a pick,
   `[.large]` after). While sending, it stays as today (`interactiveDismissDisabled`). The folder picker's back swipe
   inside the sheet must keep working.
5. **German** for every new or changed string (`Localizable.xcstrings`, and `Shared.xcstrings` for anything in Shared):
   plain and short ("Löschen", "Neuer Ordner", …).
6. **Tests** for the pure parts: the delete rules per state and the 404, the new-folder name check and the
   existing-folder match, the target the picker builds, the sheet's detents before and after a pick, every folder
   openable. If a test can drive real touches cheaply (a temporary UI test in `Aresus/AresusUITests`, as other briefs
   did, deleted afterwards), check the swipe on a drop row: a full swipe deletes, a short one opens and a tap on Delete
   deletes, a vertical drag scrolls.
7. **Screenshots** in sample mode (`-sampleData -tab aresync`, the send sheet's DEBUG arguments from brief 91), light
   and dark, English and German, into `build/93-*.png`: a drop row swiped open on the tab, Show all with one open, a
   folder page with New folder and its field (one with a failed rule), a leaf folder's page, the send sheet showing a
   new folder in its Folder row.

## Settled: do not re-open

- Swipe left to delete, as in Mail and Aresium; no confirmation.
- The history keeps the newest three on the tab and Show all.
- New folders live in the picker; one level per send (the server takes one name).
- The data side changes only as above (delete and its rules); say what you added.

## Out of scope

The server, the Mac program, receipts, the share extension, other apps' screens (Aresium only as far as the move).

## Done when

- `xcodebuild test -scheme Aresus` passes on `claude-93` with `-parallel-testing-enabled NO` (the parallel clones
  hang on this Mac), and so does `-scheme Aresium` (the move), on the same simulator; name in your final message
  `SlideSelectionTests`, `SlideTrackerTests`, `SelectionScreensTests` and the `RowSwipeRule` tests as passed (brief
  200's slide selection waits on the list's pan the same way the row swipe does).
- The Aresium widget extension builds.
- `scripts/strings.py check` reports 0 problems.
- The screenshots exist.

## Final message

Files changed (and the move), the exact test summaries of both schemes, the screenshots' paths, the strings added
(English → German), what changed on the data side, anything Aresium needed, and what you are unsure about in the
design.
