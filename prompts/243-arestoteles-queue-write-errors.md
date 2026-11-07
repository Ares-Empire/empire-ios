# 243: Arestoteles: every quick-note queue write that fails is reported

Status: running (Codex, started 2026-11-07)
Branch: `codex/243-queue-write-errors` · Worktree: `../empire-ios-243-queue-write-errors` · Model: `gpt-6.1-sol`, effort
`high` (a small, focused persistence change whose restart cases must be thought through; no frontier reasoning needed)

## Goal

The quick-note queue (notes kept on the phone until the server has them) never fails silently. Today the first Save
already reports a failed disk write and keeps the draft (`queueQuickNote`, tested by
`aFailedDiskWriteKeepsTheSheetDraftUnqueued`), but every later change of the queue goes through `saveQuickNotes()`,
which swallows the error with `try?`: deleting a note, marking a note the server refused, and removing a sent note. A
failed write there leaves the disk different from what the screen shows, and after a restart a deleted note is back,
or a sent note is sent again (a duplicate in the Inbox). After this brief each such failure is shown where the owner
is, the phone retries the write, and tests pin down what is on the disk after a restart.

## Read first

- `AGENTS.md` and `CLAUDE.md` (always; Languages and Light mode)
- `Arestoteles/Arestoteles/Model/VaultStore.swift` → "quick notes" (`queueQuickNote`, `confirmQuickNote`,
  `deleteQuickNote`, `startQuickNotes`, `runQuickNotes`, `send`, `saveQuickNotes`) and `clear()`
- `Arestoteles/Arestoteles/Model/Persistence.swift` (`VaultPersistence`, `FilePersistence`, `MemoryPersistence`)
- `Arestoteles/Arestoteles/Screens/Sheets.swift` → `QuickNoteSheet`, `PendingRow`; `ContentView.swift` → the notice
  overlay (it sits under any sheet, so a notice alone is not seen while the quick-note sheet is open)
- `Arestoteles/ArestotelesTests/BackgroundNotesTests.swift` (`UnwritableQueue`), `QuickNoteTests.swift`,
  `TestSupport.swift`

## Build

1. **Delete** (`deleteQuickNote`): write the queue without the note first; change memory only when the write
   succeeded (as `confirmQuickNote` already does). On failure the note stays in the list, and the owner sees why. Return
   whether it worked, if the caller needs it.
2. **Sent note** (`send`, success): the server has it, so it leaves the in-memory queue at once (never send it twice in
   one run). If the write fails, show it and keep a "queue not saved" state; retry the write the next time the queue is
   saved or flushed, and when the app becomes active. A later successful write clears the state.
3. **Refused note** (`send`, conflict or invalid): keep today's in-memory behaviour; if the write fails, show it and
   keep the same "queue not saved" state with the same retry.
4. **Where it shows:** the app's notice (as today for other problems) and, while the quick-note sheet is open, a line in
   the sheet itself, built like `PendingRow`'s problem line (same font and `StatusTone.issue` colour; no new look). Keep
   the text short and plain; examples: "This note could not be deleted on this iPhone: <reason>", "Sent, but this
   iPhone could not update its list; the note may be sent again after a restart: <reason>". Add the English strings to
   the String Catalog; leave the German to Claude and list the strings in your final message.
5. Replace `saveQuickNotes()`'s `try?` so no queue write in `VaultStore` ignores its error. The two `try?` in
   `VaultWorker.swift` (vault cache, a rebuildable copy) are out of scope; mention them only if you find a real harm.
6. A comment at the queue explains the one replay window that remains: a note the server accepted is sent again if the
   app is killed before the queue write succeeds. Exactly-once delivery would need the server to accept a note id
   (out of scope; say in your final message whether you think it is worth a brief).
7. **Simulator check hook:** a DEBUG-only launch argument in sample mode (e.g. `-failQueueWrites`) that makes queue
   writes fail, so Claude can see the messages on the simulator. It must still let a waiting note appear in the list
   first (e.g. the failures start after the first successful save, or the sample starts with one waiting note); say
   which in your final message. Compiled out of Release (`#if DEBUG`), like `-quickNoteText`.

## Tests (new, in `BackgroundNotesTests.swift` / `QuickNoteTests.swift`; shared fakes in `TestSupport.swift`)

A persistence fake whose queue writes can be switched to fail (and back) while it keeps what it last saved. For each
case, assert the visible state (notice, the sheet's line via the store property it reads, the pending list) and then
build a **new** `VaultStore` over the same persistence and assert what the queue holds after the "restart":
- delete fails → the note is still listed and still on disk; after writes work again, delete works;
- send succeeds but the write fails → not in memory, not sent again in the same run, still on disk (the documented
  replay), and after writes work again the next save removes it from disk;
- conflict and invalid refusals with a failing write → the problem is shown; the refusal is kept in memory;
- other queued notes are never lost or reordered by any of these failures;
- the existing first-Save failure test still passes unchanged.

## Settled: do not re-open

- No server change, no note id sent to the server (needs its own API brief).
- Memory follows the disk for owner actions (delete, confirm); for server outcomes (sent, refused) memory follows the
  server and the disk catches up by retrying.
- No new look: reuse the existing notice and problem-line styles.

## Out of scope

- Other apps, `project.pbxproj`, workflows, the vault cache writes in `VaultWorker.swift`.

## API

None (the quick-note request stays as it is).

## Done when

- On your own simulator `codex-243` (`AGENTS.md`): `xcodebuild test -project Arestoteles/Arestoteles.xcodeproj -scheme
  Arestoteles -destination 'platform=iOS Simulator,name=codex-243' -derivedDataPath build/DerivedData
  -parallel-testing-enabled NO -only-testing:ArestotelesTests` passes, with the new tests; show the summary line.
- `python3 scripts/strings.py check` reports no problems apart from the German you leave to Claude (say which).
- In the sample world with `-failQueueWrites`: open the quick-note sheet with a waiting note, tap Delete (AXe,
  `--tap-style physical`) and save a screenshot of the message to `build/243-delete-failed.png`.
- Delete the simulator at the end (`xcrun simctl delete codex-243`).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the new strings, what is missing or doubtful.
