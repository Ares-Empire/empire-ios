# 91: Aresus app: the send screen and the drops on the Aresync tab

Status: merged 2026-11-01 (9312656, 145 tests; Claude: sheet starts at half height, three drops on the tab)
Branch: `claude/91-drops-screens` · Worktree: `../empire-ios-91-drops-screens` · Built by a **Claude agent** (design work,
`CLAUDE.md` → Workflow) · Simulator: `claude-91` (create it: iPhone 17, iOS 27.0)

## Goal

Patrik sends files and photos from the Aresus app to his MacBook (plan: `~/ares-empire/docs/ARESYNC-DROP.md`; server,
Mac program and the app's data side are built and live: briefs 88–90). This brief builds **the screens**: a send
button on the Aresync tab, the send sheet (pick photos or files, pick the folder, the name, send), the folder picker,
and the drops on the Aresync tab with their state. They must look like the rest of Aresus: classy, calm, quiet; the
lightning-blue accent only as an accent.

## Rules for you

- Read and follow `AGENTS.md` and `CLAUDE.md` of this repo (the rules there apply to you: worktree only, never commit or
  push, no new packages, no `project.pbxproj` edits, light and dark from the shared colour pairs, logic out of views
  with tests, English in code + German in the String Catalog).
- **Design language:** `~/ares-empire/EMPIRE.md` → "The crown language" and "How we build apps"; the existing Aresus
  screens are the reference (`Aresus/Aresus/Screens/`: `SyncScreen`, `WatchtowerScreen`, `RunSheet`,
  `ProvinceDetailScreen`, `AresusComponents`), plus `Shared/Design/`. Reuse their components (`AresusHeader`,
  `GlassIconButton`, `SectionTitle`, `CardRows`, `CalmMessage`, `StatusLabel`, `ProvinceWall`, `AppFont`, `Ink`,
  `PressedRow`, the glass cards) before making new ones. **Patrik's taste (2026-10-24):** gold belongs to the Empire,
  not here; no slogans or "empire voice" labels; plain small labels; the app's accent (`.aresus`, lightning blue) only
  on the key control and highlights; red means a special mode, so a failure uses the existing warning/issue tones as
  the other screens do. Classy, clean, not busy.
- No real personal data anywhere (samples are made up).

## Read first

- `Aresus/Aresus/Model/DropsStore.swift` (what the screens call: `items`, `folders`, `recentFolders`, `errors`,
  `send(files:target:)`, `retry`, `remove`, `refresh`), `DropOutbox.swift` (`DropFile`, the item states), `Drops.swift`
  (`Target`, `Drop`, `DropState`, `FolderList`), `DropNames.swift` (name rules with the failed rule, default names,
  `DropSource`), `DropRecentFolders.swift`.
- `~/aresus/docs/API.md` → "Drops" (what each state and `note` means).
- `Aresus/Aresus/Screens/SyncScreen.swift` and `AresusTabs.swift` (where the tab and its refresh live),
  `ContentView.swift` (sample mode: `-sampleData`, `-tab aresync`).

## Build

1. **Send button** on the Aresync tab's header, left of the gear: a `GlassIconButton` (`square.and.arrow.up`, label
   "Send to MacBook"). It opens the send sheet.
2. **Drops on the Aresync tab**, above "Machines", only when there is at least one: section title "Sent to the
   MacBook" with the newest five of `DropsStore.items` and "Show all" (a pushed full list) when there are more. A row:
   a small symbol for the kind of file (photo, PDF, other), the name (one line, middle truncation), and one quiet line
   for its state:
   - phone items: "On the phone · waits for a connection", "Uploading …", "Not sent: <error>" (warning tone);
   - `waiting`: "Waiting for the MacBook"; `failed`: "The MacBook could not save it: <note>" (warning tone);
   - `landed`: "In <last folder of `landed`>" with the time; a fallback or a missing inventory row adds the `note` in
     muted text; `cancelled`: "Cancelled" (muted); `uploading` on the server: "Uploading …".
   Swipe or context menu: "Try again" for failed phone items and failed drops, "Remove" for phone items and for
   `uploading`/`waiting`/`failed` drops (it cancels on the server). Landed rows have no actions.
3. **The send sheet** (`.sheet`, its own `NavigationStack`, large detent):
   - **Start:** three calm choices: **Photos** (`PhotosPicker`, several, original data and file extension kept),
     **Camera** (only when the device has one; `UIImagePickerController` in a small representable; add
     `NSCameraUsageDescription` to `Aresus/Aresus/Info.plist` in English, German via the app's `InfoPlist.xcstrings`,
     made if the app has none, as another Empire app does), **Files** (`fileImporter`, several, any type; read each
     file inside `startAccessingSecurityScopedResource` while it is handed to `send`).
   - **Then, on the same sheet:** what was picked (photo thumbnails or a file symbol with the name, in one row that
     scrolls sideways), **Folder** (a row showing where it goes as `Documents › Studium › EIST`, or "Sort later
     (Zu sortieren)" when no target; tap → the folder picker), **New folder** (an optional text field: a folder made
     inside the chosen one), **Name** (one file: an editable field prefilled from `DropNames`; several files: the names
     listed, not editable), and **Send** as the one key control (accent). Name and new-folder rules are checked as you
     type with `DropNames`, the failed rule shown under the field in plain words; Send stays off until all is valid.
   - The folder starts at `recentFolders.lastBySource[source]`, else "Sort later".
   - After Send the sheet closes; the new item shows at the top of the tab as "Uploading …". A failure to even queue
     it (file unreadable) stays on the sheet as a line under Send.
4. **Folder picker** (pushed inside the sheet): a search field at the top (matches any part of the path, results as
   full paths); **Recent** (`recentFolders.targets`); **Sort later**; then **Documents** and **Downloads**, each
   drilling down folder by folder (a pushed list per folder, with "Choose <folder>" at its top). The tree comes from
   `FolderList`'s flat paths: put the tree building and the search in a pure helper with tests. At the bottom, muted:
   "Folders as of <time>" from `folders.updated`, and a calm message when the MacBook has not sent its folders yet
   ("The MacBook has not sent its folders yet. Files can still go to Sort later.").
5. **German** for every new string in `Localizable.xcstrings` (Aresus) — plain, short, the way the app already speaks.
6. **Tests** for the pure parts (tree, search, path display, row state lines from each state).
7. **Screenshots** in sample mode (`-sampleData -tab aresync`), light and dark, into `build/91-*.png`: the tab with
   drops, the send sheet with a photo picked (sample mode may fake a picked file through a DEBUG launch argument),
   the folder picker (top level and one level down), the search with results.

## Settled: do not re-open

- Entry point and layout as above (Patrik sketched: a button on the Aresync tab, then pick what to send, the folder,
  a new folder or the name).
- Receipts (scanner, reader, the receipt form) and the share extension are **not** in this brief (later briefs).
- No AI suggestions.
- The data side is as built in brief 90; if it lacks something a screen needs, add the smallest thing to it with a
  test, and say so.

## Out of scope

- The server, the Mac program, `project.pbxproj`, other apps.

## Done when

- `xcodebuild test -scheme Aresus` passes on `claude-91` with `-parallel-testing-enabled NO` (the parallel clones hang
  on this Mac).
- `scripts/strings.py check` reports 0 problems.
- The screenshots exist and show the screens above in light and dark.

## Final message

Files changed, the exact test summary, the screenshots' paths, the strings added (English → German), anything you
added to the data side, and what you are unsure about in the design.
