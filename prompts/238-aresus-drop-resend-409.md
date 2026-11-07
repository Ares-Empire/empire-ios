# 238: Aresus drops: a delivered file never shows as "Not sent" (409 after a lost upload answer)

Status: merged 2026-11-07 (Claude: idle records are only checked at launch, never retried; a failed check leaves them as they were)
Branch: `codex/238-drop-resend-409` · Worktree: `../empire-ios-238-drop-resend-409` · Model: `gpt-6.1-sol`, effort `high`

## Goal

A file sent from the phone that reached the Mac must never show as "Not sent" in the Aresync tab, and the phone must
never upload a file's bytes a second time without first asking the server whether it already has them. Patrik saw a
delivered file marked as failed (below); after this brief, the app cleans such a record up by itself on the next launch.

## What happened (2026-11-05/06, from the server log and database)

- 2026-11-05 16:12:58 `POST /drops` → 201 (drop 4, "AirPods Max 2.pdf", into Documents/Patrik Breeck/Rechnungen),
  16:12:59 `PUT /drops/4/file` → **200**. The Mac fetched it and reported `done` at 16:13:21; the file is on the Mac and
  drop 4 is `landed` on the server. The phone made no other drop request until the next day.
- 2026-11-06 19:36:59, when Aresus was opened: `PUT /drops/4/file` → **409** (`drop_state`, "This drop cannot be
  changed in its current state."), with **no** `GET /drops` before it. 4 s later the Aresync tab loaded (`GET
  /drops/folders`, `GET /drops`).
- So the phone's outbox still held drop 4's record although its upload had succeeded: it lost the 200 (most likely
  the share extension closed right after handing the upload to iOS and the completion came back as a retryable
  failure; see "Find out" below). At the next launch `DropOutbox.drain()` → `attempt()` saw a record with a `serverID`
  and `uploadSession == nil` and sent the bytes again blind. `fail()` treats the 409 as permanent, so the record is now
  `.failed` with that sentence and stays forever.
- **What Patrik sees:** the server row for drop 4 is drawn from the phone's hidden copy (`DropRow.hidden(for:in:)` →
  `DropRow.init(_:local:)` → `phone(_:)`), so the row reads "Not sent: This drop cannot be changed in its current
  state." with Retry, instead of "In Rechnungen · …". Retry sends the bytes again and gets 409 again. After 30 days the
  server drops landed rows from `GET /drops`, and the stale record would show as a phone row "Not sent" for good.

## Read first

- `AGENTS.md` and `CLAUDE.md` (always; in `CLAUDE.md` the "Aresus app" → "Aresync drops" paragraph)
- `Aresus/AresusDrops/DropOutbox.swift` (all of it: `reconnect()`, `recoverSharedUploads()`, `drain()`, `attempt()`,
  `finished()`, `scheduleDeferredRetry()`, `fail()`), `DropBackgroundUploads.swift`, `DropJournal.swift`,
  `DropsStore.swift` (`merge`, `refresh`, `observeUploads`), `DropDisplay.swift` (`DropRow`), `AresusAPI+Drops.swift`
- `Aresus/Aresus/AresusAppDelegate.swift`, `Aresus/Aresus/ContentView.swift` (the `.task` and `onEmpireForeground`
  calls to `reconnect()` / `recoverSharedUploads()` / `start()`), `Aresus/AresusShare/ShareViewController.swift`
- Tests: `Aresus/AresusTests/DropOutboxTests.swift`, `SharedDropsTests.swift`, `DropsStoreTests.swift`, `DropsTests.swift`
- The contract: `~/aresus/docs/API.md` → "Drops" (read only; do not change the server)

## Build

1. **One reconcile with the server, shared by every path.** Factor `reconnect()`'s check into one helper on
   `DropOutbox` that asks `GET /drops` once (`client.drops(token:)`) and settles each given record that has a
   `serverID` by the server's row:
   - `waiting`, `failed` or `landed`: the server has the bytes. Discard the local record and its file
     (`discard(_:)`) and call `onUploaded?(drop)` with the server's row.
   - `cancelled`: discard the local record and its file (nothing to send any more).
   - `uploading`: the bytes still have to go; leave the record to be sent.
   - not in the list: behave as today (the PUT goes; a `404` fails with the server's sentence). Leave a short comment.
   - the GET fails: handle it like any request failure in `fail()` (offline → retry later with the usual backoff;
     401 → `handleAuthFailure`). Never fall back to sending the bytes blind.
   Respect the existing rules around it: the `generation`/`epoch` checks, the journal lease (`journal.claim`), records
   owned by another process's active upload (`uploadSession` set and active) are not touched, `cancellationRequested`
   records keep their own DELETE path.
2. **Ask before re-sending.** In `attempt()`, when the record already had a `serverID` before this attempt started
   (a resend: a retry, a launch, a Retry tap), run the reconcile for that record first and send the bytes only when the
   server says `uploading`. A first send right after this attempt's own `POST` needs no GET.
3. **A 409 on the upload is not a failure.** When an upload ends with `HTTPError.server(409, _)` (in `finished()`,
   also for a deferred retry's completion in the share extension or the app woken for its session), run the reconcile
   for that record instead of `fail()`: the server has it (discard, `onUploaded`) or, if the server still says
   `uploading` (the server also answers 409 while another upload of the same drop is streaming), retry later as a
   retryable error (`.onPhone` with `retryAt`), never `.failed`.
4. **Old stale records clean themselves up.** Extend what the app runs at launch and on coming to the foreground
   (`reconnect()`, called from `ContentView`) so that it also reconciles records with a `serverID` that are `.failed`,
   or `.onPhone` without an `uploadSession`, in the same single `GET /drops`. Patrik's phone holds exactly such a record
   (drop 4, `.failed`, `lastError` "This drop cannot be changed in its current state."): with this build it must be
   gone after the first launch, and its row show the server's "In Rechnungen · …" line.
5. **The row shows the server's word once the server has the file.** `DropRow.hidden(for:in:)` returns the phone's
   copy only while the server row is `uploading`; for `waiting`, `landed`, `failed` and `cancelled` the row shows the
   server's line (`server(_:)`), whatever copy the phone still holds. (`DropsStore.merge` already hides the phone row
   behind a server row with the same id; keep that.)
6. **Find out (report; fix only if clear and small).** Read the Nov 5 path: the share extension sends (`ShareScreen` →
   `SendSheet.send()` → `DropOutbox.enqueue` → `drain` → `attempt` → `uploads.submit`), then `completeRequest` closes
   the extension; the background session finishes in the daemon; iOS wakes the app through
   `AresusAppDelegate.application(_:handleEventsForBackgroundURLSession:completionHandler:)`, or the extension still
   receives `didCompleteWithError`. List every way a `200` from `PUT /file` can end with the record left as `.onPhone`
   and `uploadSession == nil` (for example a completion delivered as `URLError.cancelled`, `fail()` on another error,
   `scheduleDeferredRetry`'s guard, `reconnect()` resetting a record whose task iOS no longer lists). If one is a clear
   bug, fix it with a test; otherwise name the candidates in your final message. Items 1–5 make every such case
   harmless either way.

## Settled: do not re-open

- No server change: `GET /drops` is the documented way to learn a drop's state (the comment in `reconnect()` already
  relies on it), and the 409 stays as the server's answer.
- The check is one `GET /drops` per reconcile, never one per record; no new endpoint, no `HEAD`.
- No new UI and no new strings: the rows already have every line needed.
- A record whose drop the server no longer lists keeps today's behaviour (item 1, "not in the list"). Re-creating a drop
  for it could file a second copy on the Mac, so it is out of scope.

## Out of scope

- The aresus server, the Mac's `drop.py`, `docs/API.md`.
- The look of the Aresync tab, the send sheet and the share extension.
- `project.pbxproj` (no new targets; new files in existing folders are picked up by themselves).

## API

From `~/aresus/docs/API.md` → "Drops" (2026-11-01, with the 2026-11-02 note) and `~/aresus/src/aresus/drops.py`:
- `GET /drops` (app auth) → `{"drops": Drop[]}`, newest first: the last 30 days plus every drop not yet landed or
  cancelled, at most 200. `Drop.state` is `uploading | waiting | landed | failed | cancelled` (`DropState`).
- `PUT /drops/{id}/file` → `200 Drop` in state `waiting`; `409 drop_state` when the drop is not `uploading` **or**
  another upload of it is streaming right now (`drops.py` `upload()`: `row["state"] != "uploading" or drop_id in
  self._active`); `404` unknown or removed; `400` size/checksum mismatch (stays `uploading`, repeatable).
- Already in the app: `AresusAPI.drops(token:)`, `uploadRequest(_:token:)`, `create(_:token:)`, `delete(_:token:)`.

## Done when

- `xcodebuild test -scheme Aresus` passes on your own simulator (`codex-238`, commands in `AGENTS.md`), with new or
  changed tests in `DropOutboxTests` / `SharedDropsTests` / `DropsTests` for:
  - a resend of a record whose drop the server lists as `landed` (and one as `waiting`): no `PUT`, the record and its
    file are gone, `onUploaded` got the server's row;
  - the Nov 6 state: a `.failed` record with `serverID` and the 409 sentence, server row `landed` → gone after
    `reconnect()`, with exactly one `GET /drops` and no `PUT`;
  - a `PUT` answered `409` while the server says `waiting` → discarded; while it says `uploading` → `.onPhone` with a
    `retryAt`, never `.failed` (also for a completion delivered through `DropBackgroundUploads.deliver`);
  - the `GET` before a resend failing offline → retry later, no `PUT`;
  - a server row `landed` with a `.failed` phone copy → `DropRow` shows the server's line and `canRetry == false`;
    a server row `uploading` with a phone copy → the phone's line as today;
  - `permanentErrorsKeepTheFileAndServerSentence` no longer lists 409 (413, 507, 404 stay permanent).
- The full Aresus test run's summary line in your final message.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, item 6's findings (each candidate path in one
or two sentences, and whether you fixed one), and anything missing or doubtful.
