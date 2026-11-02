# 204: Files from outside: the share sheet checked, and dropping a file on Aresium

Status: draft
Branch: `claude/204-files-from-outside` · Worktree: `../empire-ios-204-files-from-outside` · Built by: a Claude agent
(how a dropped file feels on the main screen) · Simulator: `claude-204` (create it: iPhone 17, iOS 27.0)

## Goal

Patrik (2026-11-02): "is it possible to have Aresium show up as an export option? Like if I export the csv data apps
show up like messengers, airdrop, downloads etc. could Aresium show up there so the import is easier? And could we
build drag and drop for Aresium? So you can drag a file, drop it in the main screen and it gets processed?"

The first exists since 2026-10-23: `Info.plist` declares document types (`.csv`, CAMT `.xml`, MT940 `.sta`/`.mt940`),
so the share sheet should offer Aresium, and a shared file goes through `route` in `ContentView` into
`imports.receive(_:source: .shared)` (held while the lock is on, the Inbox copy removed). Nobody has watched it work
end to end. This brief checks it with real touches and fixes what is wrong, then adds **dropping files on the main
screen**, through the same way in.

On the iPhone a drop comes from another app with two hands (hold the file in Files until it lifts, switch to Aresium
with another finger, drop). Make it work and feel right; do not invent a new way in.

## Read first

- `AGENTS.md`, `CLAUDE.md` (Aresium phone mode: the import, `ImportStore`, `ImportFileReader` and the Inbox, the
  share sheet's document types, the lock holding shared files, the first screen, the import feedback; the Empire's
  design restraint).
- `Aresium/Aresium/Info.plist`, `Aresium/Aresium/AresiumApp.swift` (`InboxSceneDelegate`), `ContentView.swift`
  (`route`, `heldFiles`, `importTypes`), `Screens/PhoneScreens.swift` (`PhoneImportTypes`), `Model/ImportStore.swift`,
  `Model/ImportFileReader.swift`, `Screens/ImportControls.swift`, and their tests.

## Build

1. **Check the share sheet first.** A temporary UI test drives the simulator's Files app (`com.apple.DocumentsApp`):
   a made-up VR Bank `.csv`, a PayPal `.csv` and a CAMT `.xml` in On My iPhone; share each; Aresium is in the app row
   or under More; choosing it opens Aresium and imports the file (the import feedback shows, the payments are there);
   the Inbox copy is gone afterwards. Also with the lock on: the file waits and imports after unlocking. Say what you
   found. If Aresium is missing or the import fails, find why and fix it. AirDrop's "open with" uses the same way;
   say that it cannot be tested on the simulator.
2. **Which files.** Today the share sheet claims `.csv`, `.xml`, `.sta`, `.mt940`, while the file picker also takes
   `.txt` (MT940 inside) and `.zip`. Leave `.txt` unclaimed (Aresium would be offered for every text file). Decide on
   `.zip` (some banks zip their CAMT files; Aresium would then be offered for every zip) and say why.
3. **Drop on the main screen** (phone mode: the dashboard pages and the empty first screen; not over sheets, the lock
   screen or the tour): files of the import's types (`PhoneImportTypes.all`: a drop is chosen by hand, so `.txt` is
   fine here), one or several, go exactly the way a shared file goes (`imports.receive(_:source: .shared)` or what
   step 1 settles), copied out of the drop first and the copies deleted after reading. Held while the lock is on, as
   shared files are. Other files are not accepted (the system's "not allowed" look while hovering), never a crash.
4. **Feel:** while an accepted file hovers, the screen says calmly that letting go imports it (your design, in the
   app's own pieces, no new decoration); letting go starts the import feedback the picker's import shows. Light, dark
   and red mode; Reduce Motion; VoiceOver (a drop target label).
5. **German** for any new text (`scripts/strings.py`).

## Settled: do not re-open

- One way in for every file from outside (share sheet, drop, picker): the import's own.
- No share extension: the document types open Aresium itself, which can unlock and show the result.
- Restoring an Aresium export stays in Settings (a dropped `.json` is not accepted).

## Out of scope

- The import's reading, the banks' formats, the file check window, receipts' photos.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=claude-204'
  -derivedDataPath build/DerivedData` passes, with tests for any new pure logic (which types a drop takes, the
  copies' clean-up).
- `scripts/strings.py check`: 0 problems.
- **Real touches** (temporary UI tests in `Aresus/AresusUITests` driving Files and Aresium, deleted after; 3 of 3 runs):
  the share sheet test of step 1; a drop from Files onto Aresium's dashboard if the simulator can drive a cross-app
  drag (say if it cannot, and test the drop's handling below the gesture instead).
- Screenshots `build/204-*.png` in German and English, light and dark (red once): the share sheet with Aresium in it, a
  file hovering over the dashboard, the import feedback after a drop.
- `CLAUDE.md` updated (the share sheet's check and the drop).

## Final message

As in `AGENTS.md`: files changed, the exact test summary (count the "' passed on" and "' failed on" lines), what the
share sheet check found, the choices you made and why, anything doubtful. Never commit, push or merge: Claude does.
