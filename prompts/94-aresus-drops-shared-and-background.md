# 94: Aresus: drops shared with the share extension, uploads in the background

Status: open (starts after brief 93 is merged; it changes the same screens)
Branch: `codex/94-drops-shared` · Worktree: `../empire-ios-94-drops-shared` · Model: `gpt-6.1-sol`, effort `xhigh`
Simulator: `codex-94` (create it: iPhone 17, iOS 27.0)

## Goal

Patrik sends files and photos from Aresus to his MacBook (briefs 88–93; plan `~/ares-empire/docs/ARESYNC-DROP.md`).
Next (Patrik, 2026-11-02, approved): **Aresus in the iPhone's share sheet** (Photos, Files, Safari, Mail, …) showing
the same send screen right there, **dropping files onto the Aresync tab**, and **a second pick adding** to what is
already picked. Uploads must go on after the share sheet closes.

Claude has set up the project (commit 2cf1ea4): a share extension target `AresusShareExtension`
(`Aresus/AresusShare/`: `Info.plist`, `ShareViewController.swift`, a placeholder screen) and a folder
**`Aresus/AresusDrops/`** compiled into both the app and the extension (`DropContainer.swift`: the App Group
`group.de.ares-empire.aresus`, which both have, and the background session's identifier). Both targets also compile
`Shared/` and `Aresus/AresusShared/`.

This brief is the **data and plumbing** half: the drop code moved so the extension can use it, made safe for an
extension, uploads in a background `URLSession`, the share sheet's items read into files, the drop's file handling
shared with Aresium. Brief 100 (a Claude agent, after you) builds the look: the extension's screen, the drop target's
hover, the picked row with remove. You may wire screens **as structure** (so the extension shows the send sheet with
its items and Send works), never their look.

## Rules for you

- `AGENTS.md` and `CLAUDE.md` of this repo apply in full: your worktree only, never commit or push, no installs, no
  new packages. **You may not edit `project.pbxproj`**; you do not need to: `AresusDrops/` and `AresusShare/` are
  folder-synchronized, so files moved or added there are compiled automatically (into the targets the folder belongs
  to). Move files with `git mv`.
- English in code, German in the String Catalogs (`scripts/strings.py sync`, German, `check` = 0 problems). A string
  used by code in `AresusDrops/` must work in both targets: check where the catalog it uses is compiled (the
  "One catalog per folder that more than one target compiles" rule in `CLAUDE.md`; `AresusDrops/` may need its own
  `AresusDrops.xcstrings` with `table:` lookups, as `AresusShared` has).
- Nothing in `Shared/`, `AresusShared/` or `AresusDrops/` may use `UIApplication.shared` (extensions cannot).
- No real personal data in tests or samples.
- Run tests serially: `-parallel-testing-enabled NO` (the parallel clones hang on this Mac). No `timeout` (not on
  macOS). Never kill processes by pattern; only exact PIDs you started.

## Read first

- `prompts/90-aresus-drops-data.md`, `91-aresus-drops-screens.md`, `93-aresus-drops-folders-and-swipe.md` (what exists
  and why).
- The drop code: `Aresus/Aresus/Model/` `Drops.swift`, `DropNames.swift`, `DropOutbox.swift`, `DropsStore.swift`,
  `DropRecentFolders.swift`, `DropFolderTree.swift`, `DropDisplay.swift`, `SendDraft.swift`;
  `Aresus/Aresus/API/AresusAPI+Drops.swift`; `Aresus/Aresus/Screens/SendSheet.swift`, `FolderPicker.swift`,
  `DropsSection.swift`, `AresusComponents.swift`; `AresusTabs.swift`, `ContentView.swift`, `AresusApp.swift`.
- `Aresus/AresusDrops/DropContainer.swift`, `Aresus/AresusShare/` (both from Claude's setup).
- `~/aresus/docs/API.md` → "Drops" (POST creates, PUT uploads the bytes, the rules).
- Aresium's drops onto its main screen (brief 204): `Aresium/Aresium/Model/FileDrop.swift`,
  `Aresium/Aresium/Screens/FileDropScreens.swift`, and `receiveFromOutside`/`receiveDropped` in
  `Aresium/Aresium/ContentView.swift`.
- `Shared/Push/PushAppDelegate.swift` (the app delegate Aresus uses), `Shared/Auth/EmpireSession.swift` (the login the
  extension shares through the Keychain group).

## Build

1. **Move the drop code into `AresusDrops/`**, everything the send sheet needs in both targets: the models above, the
   API extension, `SendSheet.swift`, `FolderPicker.swift`, and the components they use (`AresusComponents.swift`
   pieces: move what both need; choose `AresusDrops/` or `AresusShared/`, whichever leaves the clearer structure, and
   say why; the widget compiles `AresusShared/`). `DropsSection.swift` (the tab's list) may stay in the app. The app
   must behave exactly as before.
2. **Safe in an extension.** `DropOutbox` uses `UIApplication.shared` (background time, lifecycle notifications):
   put that behind something the app supplies and the extension does not (an injected protocol or closure), so the
   moved code compiles in the extension and the app keeps today's behaviour.
3. **One store of drops on the phone, in the App Group.** The outbox's folder and records move from the app's
   Application Support (`Drops/`) to `DropContainer.url` (e.g. `Drops/` inside it), so the app and the extension see
   the same queue. Move what is already there on Patrik's phone at the app's first launch (records and files), once,
   never losing an item; test it. Recent folders (`DropRecentFolders`) go to the group's `UserDefaults(suiteName:)`
   (move the old value once). Keep the Mac's last folder list in the group too (a small cache: the extension's picker
   opens with it at once and refreshes from the server). The app re-reads the queue when it comes to the foreground,
   so items the extension added show on the tab.
4. **Uploads in a background `URLSession`** (`DropContainer.uploadSession`, `sharedContainerIdentifier` =
   `DropContainer.appGroup`), for the app and the extension alike: **one** way of uploading, not two. The order stays
   as today (a record saved before any request, the server id saved before the bytes; `POST /drops` may stay a normal
   request), then `PUT /drops/{id}/file` as a background upload task from the queued file. The upload goes on when the
   extension has closed or the app is suspended; when it ends, iOS wakes the app
   (`application(_:handleEventsForBackgroundURLSession:completionHandler:)`: Aresus needs it on its delegate, without
   changing the other apps' `PushAppDelegate` behaviour), which updates the record and calls the completion handler.
   Whichever process finishes a task updates the record in the group (atomic writes; the other process re-reads).
   Keep today's retry rules (`retryDelay`, checksum retries, 401 handling through the session), cancelling
   (brief 93: delete cancels a running upload), and the `onUploaded` hand-over to `DropsStore`. Describe in your final
   message what happens in each case: the extension closes mid-upload; the app is killed mid-upload; no network; the
   token expires.
5. **The share sheet's items into files** (`AresusDrops/`): from the extension's `NSExtensionItem`s to `[DropFile]`,
   each copied into the group at once with `NSItemProvider.loadFileRepresentation` (never a whole file in memory: an
   extension has a small memory limit; an item that only offers an image or data object is written to a file), a name
   from `suggestedName` with the type's extension, else the app's default names (`DropNames`, a photo's as the Photos
   choice names it), and its source (photo or file) for recent folders. Up to 20 items. Unreadable items are counted,
   not fatal. Tests with made-up providers.
6. **The extension wired as structure**: `ShareViewController` shows the send sheet starting with those items (no
   three choices), using the shared login (`EmpireSession` as the app builds it; the extension never shows a login
   screen: without a login it shows one line, "Log in to Aresus on this iPhone first.", and Cancel), and closes the
   share sheet after Send has queued everything (`completeRequest`), or on Cancel (`cancelRequest`). The look is brief
   100's; keep it plain.
7. **Dropping files onto the Aresus app.** Move the general part of Aresium's file drop (taking the files out of a
   drop's providers into the app's own copies, the hover state) into `Shared/` so both apps use one version; Aresium's
   own rule (which items its import takes) and its screens stay in Aresium and behave exactly as before (its tests
   pass). In Aresus: the Aresync tab takes dropped files of any kind and opens the send sheet with them (as structure;
   brief 100 draws the hover).
8. **A second pick adds** (`SendDraft`): picking photos, a camera photo or files again adds them to what is picked
   (the same file twice only once), and one picked item can be removed (`SendDraft` API with tests). A draft can
   start with given files (the share sheet, a drop).
9. **Tests** for: the move of the old outbox and recent folders; the queue shared by two outbox instances on one group
   folder (one adds, the other sees it after re-reading); the background upload's delegate path (a fake session or
   delegate calls: success, failure, a 401, cancellation, a task finishing in the other process); the share items
   (file, image data, several, unreadable); the shared file drop (Aresium's existing tests unchanged and passing);
   `SendDraft` adding and removing. The existing tests keep passing.

## Settled: do not re-open

- A share extension with the send screen inside it; iOS gives a share extension no way to open its app.
- Aresus's own App Group `group.de.ares-empire.aresus` (already registered and signed: Claude checked an App Store
  export).
- One upload path (background session) for app and extension.
- The look is brief 100's.

## Out of scope

The server and the Mac program; receipts; `project.pbxproj`; Aresium beyond the shared file drop.

## Done when

- `xcodebuild test -scheme Aresus` passes on `codex-94` (`-parallel-testing-enabled NO`), and `-scheme Aresium`
  passes too (the shared file drop).
- The app with both extensions builds for the simulator, and `xcodebuild build -scheme Aresus -configuration Release
  -destination 'generic/platform=iOS'` builds (an extension-unsafe call shows up there).
- `scripts/strings.py check` reports 0 problems.
- On `codex-94` in sample mode: the share extension, opened from the simulator's Photos or Files with a made-up file,
  shows the send sheet with the item (describe how you checked; a temporary UI test driving another app is fine, as
  other briefs did, deleted afterwards).

## Final message

Files moved and changed, where each piece now lives and why, the exact test summaries of both schemes, the four
upload cases from item 4, how the extension was checked, any `TODO`, and anything doubtful.
