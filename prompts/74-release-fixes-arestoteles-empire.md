# 74: Arestoteles and the Empire app: three fixes from the release check

Status: merged 2026-11-01 (Arestoteles 156 tests, Empire 306, run by Claude); the Empire part ships with its next build
Branch: `codex/74-release-fixes` · Worktree: `../empire-ios-74-release-fixes` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Brief 73's check (`codex-runs/73-release-check.md`, confirmed by Claude in the code) found three things to fix before
these apps settle on Patrik's iPhone. After this brief: a vault the app throws away also leaves iPhone search; the
downloaded vault stays out of the iPhone's backups; and a notification's tap in the Empire app is never hidden behind
Settings.

## Read first

- `AGENTS.md` and `CLAUDE.md` (always; "One login for all apps" → central logout)
- `Arestoteles/Arestoteles/Model/VaultStore.swift` (`loadFromDisk`, the logout path), `Model/Spotlight.swift`,
  `Model/Persistence.swift`, and their tests in `Arestoteles/ArestotelesTests/`
- `Empire/Empire/ContentView.swift` (`showsSettings`, the `push?.openedURL` handler) and the Empire tests

## Build

1. **Arestoteles, Spotlight follows the saved vault.** `VaultStore.loadFromDisk()` deletes a saved vault that belongs to
   no login or to another account (`persistence.deleteAll()`), but the notes stay in Spotlight (`DeviceSpotlight`) until
   the next login. Remove them there too (`spotlight.removeAll()`), the same way the logout path does. Also when no
   vault was saved but the index still holds items while no login is saved (a crash between the two), if that is
   simple; say what you chose. Test it with a recording `SpotlightIndexing` fake.
2. **Arestoteles, the vault out of backups.** `FilePersistence` writes `vault.json` (a copy of the server's vault, always
   downloadable again) to Application Support, which iOS backs up. Exclude `vault.json` from backup
   (`URLResourceValues.isExcludedFromBackup`) after every write: an atomic write replaces the file, so the flag must be
   set again each time. `quick-notes.json` (notes not sent yet, which exist nowhere else) stays in the backup. Keep the
   data protection option. A unit test that the written vault file carries the flag and the quick notes file does not.
3. **Empire, a notification tap closes Settings.** When a tapped notification opens a ring page (`push?.openedURL` →
   `navigation.open`), close the Settings sheet first (`showsSettings = false`) so the page is not hidden behind it.
   Keep the change small; test it if the navigation logic allows without a UI test, otherwise say so.

## Settled: do not re-open

- No change to the login, the logout flow, the push registration or what is stored, only the three points above.
- The quick notes' failed-write handling stays as it is (a deliberate choice, commented in `saveQuickNotes`).
- Preview Content in Release builds: later, not here.

## Out of scope

- The look of any screen; the Arestoteles bust and icon (brief 72, another agent, in another worktree).
- `project.pbxproj`, other apps, `Shared/` (unless point 3 truly needs it: then stop and say why).

## API

None.

## Done when

- `xcodebuild test -scheme Arestoteles` and `xcodebuild test -scheme Empire` pass on your own simulator `codex-74`
  (commands in `AGENTS.md`, `-project Arestoteles/Arestoteles.xcodeproj` and `-project Empire/Empire.xcodeproj`), with
  the new tests.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines (tests run, failures), what is missing or
doubtful.
