# 90: Aresus app: drops, the data side (outbox, upload, folder list, list of drops)

Status: merged 2026-11-01 (82b5d7d; Claude: server samples, tests adjusted, German strings)
Branch: `codex/90-drops-data` · Worktree: `../empire-ios-90-drops-data` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Patrik sends files and photos from the Aresus app's Aresync tab to his MacBook (plan:
`~/ares-empire/docs/ARESYNC-DROP.md`). The server (brief 88) and the Mac program (brief 89) are being built against
the contract in `~/aresus/docs/API.md` → "Drops". This brief builds **everything in the app except the look**: the
models, the API calls, an outbox on the phone that keeps a file until the server has it (also without a connection),
the upload, the folder list for picking, recent folders, default names and the name rules, and the list of drops for
the tab. **Build no screens:** Claude designs and builds them on top of what you make (`CLAUDE.md` → Design stays
with Claude).

## Read first

- `AGENTS.md` and `CLAUDE.md` (always).
- **The contract, settled:** `~/aresus/docs/API.md` → "Drops (Aresync drop, version 1)" and its samples
  `~/aresus/docs/samples/drops.json` and `drop-folders.json` once they exist (brief 88 writes them; if they are not
  there yet, write your own made-up copies to the contract into `Aresus/Aresus/Samples/` and say so).
- `Aresus/AresusShared/AresusAPI.swift`, `Aresus/Aresus/API/AresusAPI+Details.swift` (how a call is made and checked),
  `Shared/API/HTTP.swift` (`HTTPTransport`, `checkResponse`, `HTTPError`), `Aresus/Aresus/Model/AresusStore.swift`
  (loading, errors, `session.onAppDataReset`, sample mode), `Aresus/Aresus/Model/AresusSamples.swift`,
  `Aresus/AresusTests/AresusTestSupport.swift`.

## Build

1. **Models** (`Aresus/Aresus/Model/Drops.swift`): `Target`, `Receipt`, `NewDrop`, `Drop` (with `DropState`),
   `FolderList`, exactly as the contract (snake_case on the wire). Receipts are decoded and sent but get no flow yet.
2. **API** (`Aresus/Aresus/API/AresusAPI+Drops.swift`): `folders()`, `create(NewDrop)`, `upload(id, fileURL)` (from the
   file, `application/octet-stream`, not loaded into memory), `drops()`, `cancel(id)`. Errors through
   `checkResponse`, so the server's sentence reaches the screen. `HTTPTransport` gets an upload method if needed
   (keep `URLSessionTransport` as the one real transport; a fake in tests).
3. **Name rules** (`DropNames`, pure, with tests): the contract's rules for new names and folder parts (NFC, byte
   limits, forbidden characters, leading dot, trailing space or dot), returning which rule failed so a screen can say
   it. Default names: a file keeps its own name; a photo or a camera shot becomes `YYYY-MM-DD HH-mm-ss.<ext>` in local
   time with the original extension (`.heic`, `.jpg`, …). Several files with the same name in one send get
   ` (2)`, ` (3)` … before the extension.
4. **Outbox** (`DropOutbox`): what was sent but is not yet on the server. On "send" each file is copied into the app's
   own container (`Application Support/Drops/`, excluded from iCloud backup) with a JSON record (the `NewDrop`, its
   local file, the server id once created, attempts, last error). Then it works through the queue: compute size and
   sha256 (CryptoKit, streaming), `create` (only once: the server id is stored), `upload`, delete the local copy on
   success. It runs at launch, when the app comes to the foreground, when the network comes back (`NWPathMonitor`)
   and right after a send; one item at a time, oldest first. While the app is in the background it asks for extra time
   (`UIApplication.beginBackgroundTask`) to finish the current upload. Errors: no connection or `5xx` → keep and retry
   later (growing pause, at most 10 minutes); `400` on upload (size or checksum) → recompute and retry once, then
   stop with the error; `413`/`507`/other `4xx` → stop with the server's sentence (the item stays, shown as failed,
   until Patrik removes it). Removing an item that has a server id also sends `cancel`. On logout
   (`session.onAppDataReset`) the outbox and its files are deleted.
5. **`DropsStore`** (`@MainActor @Observable`), owned next to `AresusStore` and loaded like it (refresh with the
   tab, keep the last good answer, errors per part): the folder list (also saved to `Caches` so the picker works
   offline, with its `updated` time), the server's drops, and one merged list for the tab: outbox items first
   ("on the phone", "uploading", "failed on the phone"), then the server's drops newest first, without doubles (an
   outbox item whose server id appears in the server list shows as the server's drop). Methods the screens call:
   `send(files:[local URL or Data + suggested name], target:)`, `retry(item)`, `remove(item)`, `refresh()`.
   **Recent folders:** the last 8 targets used (root + folder + new folder made), stored in `UserDefaults` (they are
   folder names, not secrets), plus the last target per kind of source (photo, camera, file), for the screen to
   pre-select.
6. **Sample mode:** the store answers from the bundled samples (as `AresusStore` does), so Claude can design the
   screens on the simulator without a server.
7. **Tests** (`AresusTests/`): decoding the samples; the name rules (every rule, `:` allowed in folder parts only);
   default names; the outbox with a fake transport: create once then upload, retry after no connection without a
   second create, `400` retried once then stopped, `413` stopped with the sentence, cancel sends `DELETE`, logout
   empties it; the merged list (no doubles, order); recent folders (8, newest first, no duplicates).

## Settled: do not re-open

- The contract (Claude's, 2026-11-01). One drop per file.
- No screens and no strings for screens in this brief (Claude's). Error sentences come from the server; the few
  phone-side sentences you need (no connection, file unreadable) go in `Localizable.xcstrings` in English; list them.
- A normal `URLSession` with a background task for v1. A background `URLSession` comes with the share extension later.
- Files go to the phone's own container, never into the shared App Group.

## Out of scope

- The share extension, receipts (scanner, reader, the receipt form), AI suggestions, `project.pbxproj`.
- The server and the Mac program.

## API

Exactly `~/aresus/docs/API.md` → "Drops": `GET /drops/folders`, `POST /drops`, `PUT /drops/{id}/file`, `GET /drops`,
`DELETE /drops/{id}` with the app's Empire token. Anything missing: `TODO(api)`, never guessed.

## Done when

- `xcodebuild test -scheme Aresus` passes on your own simulator (`codex-90`), with the tests above.
- `xcodebuild build -scheme Aresus` has no new warnings in your files.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the strings you added, every `TODO(api)`,
what is missing or doubtful.
