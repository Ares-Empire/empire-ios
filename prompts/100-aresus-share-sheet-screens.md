# 100: Aresus: the send screen in the share sheet, dropping onto the tab, adding to a pick

Status: open (starts after brief 94 is merged)
Branch: `claude/100-share-screens` · Worktree: `../empire-ios-100-share-screens` · Built by a **Claude agent** (design
work, `CLAUDE.md` → Workflow) · Simulator: `claude-100` (create it: iPhone 17, iOS 27.0)

## Goal

Patrik (2026-11-02, approved): **Aresus in the iPhone's share sheet**, opening the drop menu right there; **drag and
drop** onto Aresus; **sending several things at once**, a second pick adding to the first. Brief 94 (Codex) built the
data and wired everything as plain structure: the drop code now lives in `Aresus/AresusDrops/` (compiled into the app
and the share extension), uploads run in a background session, `ShareViewController` shows `SendSheet(sharing:
true)` with the shared items, the Aresync tab takes dropped files (`ProviderDropTarget`), and the picked row has an
"Add" menu and `SendDraft.remove`. This brief gives all of it **the look**: as classy and quiet as brief 91's and 93's
screens, which are the reference.

## Rules for you

- Read and follow `AGENTS.md` and `CLAUDE.md` of this repo (worktree only, never commit or push, no new packages, no
  `project.pbxproj` edits, light and dark from the shared colour pairs, logic out of views with tests, English in code +
  German in the String Catalogs; code in `AresusDrops/` uses the `AresusDrops` table, as brief 94 set up;
  `scripts/strings.py sync`/`check`).
- **Design language:** `~/ares-empire/EMPIRE.md` → "The crown language" and "How we build apps"; the Aresus screens
  (`Aresus/AresusDrops/SendSheet.swift`, `FolderPicker.swift`, `DropComponents.swift`, `Aresus/Aresus/Screens/`) and
  `Shared/Design/`. Patrik's taste: classy, calm, quiet; the lightning-blue accent only on the key control; plain small
  labels, no slogans.
- No real personal data anywhere.

## Read first

- `prompts/94-aresus-drops-shared-and-background.md` and its result (the code), `prompts/91-…` and `93-…` (the screens).
- `Aresus/AresusShare/ShareViewController.swift` (the extension's screen today: a spinner, a line for no login, the
  unreadable count above the sheet), `Aresus/AresusDrops/SendSheet.swift` (`sharing`, the Add menu), `SendDraft.swift`
  (`add`, `remove`), `ShareItems.swift`.
- `Aresus/Aresus/Screens/AresusTabs.swift` (the drop target), `Shared/Design/ProviderDropTarget.swift`,
  `Shared/ProviderFiles.swift`, and Aresium's hover look for dropped files (`Aresium/Aresium/Screens/FileDropScreens.swift`,
  `DropHover`) as a reference for what a hover can look like in this family.

## Build

1. **The share sheet's screen** (the extension): it must look like Aresus's send sheet, not a bare screen.
   - While the items are read and the login restored: a calm loading state, not a lone spinner on an empty wall.
   - No login: the app's calm message style (`CalmMessage`), "Log in to Aresus on this iPhone first." and Cancel.
   - The sheet itself as in the app, starting with what was shared (no three choices). The unreadable count ("2
     items could not be read.") as one quiet line where it belongs (under the picked row, not floating above the
     sheet). The close button works as in the app.
   - **"Sort later (Sort later)"** shows today in the folder row (the fallback's name repeated while the folder list
     is not there yet, see `build/94-share-extension.png` in brief 94's worktree, or reproduce it): fix the words so it
     reads like the app's "Sort later (Zu sortieren)", or just "Sort later" when the folder is not known yet.
   - **Language:** the extension runs in its own process, which iOS starts in the iPhone's language. It should speak
     the app's own language choice, as the widgets do (`WidgetLanguage`, `AppRoot(widget:)` in `CLAUDE.md` →
     Languages): find how the widgets get it and do the same for the extension, or say why not.
   - **Light and dark:** the extension follows the app's appearance choice if that is cheap to read from the group,
     else the iPhone's; say which.
   - After Send the share sheet closes (as today). If queuing fails, the line stays under Send, as in the app.
2. **Adding to a pick and removing one** (the app's sheet): the picked row shows every item (photo thumbnails, a file
   symbol with the name), each with a small remove control in the iOS way (a quiet minus or xmark badge on the item);
   "Add" opens the same three choices (Photos, Camera, Files) as a menu or a small row; with several items the names
   list stays as today. The row scrolls sideways when it is long. Removing the last item goes back to the three
   choices. In the share sheet, adding may be left out (say so) but removing works.
3. **Dropping onto Aresus:** while files hover over the Aresync tab, a hover in this app's look (a calm full-screen
   overlay: the accent's thin edge, a symbol and "Drop to send to your MacBook" or similar, two lines at most, as
   Aresium's `DropHover` does for bank files); letting go opens the send sheet with them (brief 94 wired it). Only the
   Aresync tab takes drops; say if the Aresus tab should too.
4. **German** for every new string, short and plain.
5. **Tests** for the pure parts you add (the folder row's words before the list is there, the remove/add rules, the
   hover words). Real touches where cheap (a temporary UI test, deleted afterwards): share a made-up photo and a PDF
   from Files to Aresus and see the sheet; remove one; Send closes it. The drop needs two fingers in the simulator;
   if a UI test cannot drive it, show the hover with a DEBUG launch argument and say so.
6. **Screenshots** light and dark, English and German, into `build/100-*.png`: the share sheet loading, with one photo,
   with three items, without a login; the app's sheet with three items and their remove badges; the Add menu; the
   drop hover on the Aresync tab.

## Settled: do not re-open

- The send screen inside the share sheet (iOS gives a share extension no way to open its app).
- Brief 94's data side; change it only if a screen needs it, smallest change with a test, and say so.

## Out of scope

The server, the Mac program, receipts, the background upload logic, other apps.

## Done when

- `xcodebuild test -scheme Aresus` passes on `claude-100` (`-parallel-testing-enabled NO`).
- `scripts/strings.py check` reports 0 problems.
- The screenshots exist and you have looked at each yourself.

## Final message

Files changed, the exact test summary, the screenshots' paths, the strings added (English → German), how the
extension gets its language and look, anything you changed on the data side, and what you are unsure about.
