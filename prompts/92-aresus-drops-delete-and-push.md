# 92: Aresus server: delete any drop from the list, "delivered" push

Status: merged 2026-11-02 (aresus 894d25b, 589 tests; Claude: pushes sent outside the drops lock again, cancelled sample kept)
Branch: `codex/92-drops-delete` · Worktree: `../aresus-92-drops-delete` (a worktree of **`~/aresus`**, the server
repo) · Model: `gpt-6.1-sol`, effort `high`

## Goal

Patrik sent his first file from the phone (it worked) and asked for two things on the server side:

1. **Every drop can be deleted from the list** (the app gets Mail-like swipe to delete). Today `DELETE /drops/{id}`
   only cancels drops that have not landed and answers `409` for landed ones; cancelled ones stay in the list.
2. **The push for a landed file just says it was delivered**: "Report.pdf delivered" instead of
   "Zu sortieren: Report.pdf".

The contract is already updated: `docs/API.md` → "Drops" (the 2026-11-02 note, the `DELETE /drops/{id}` row, the
error line and the "Drop pushes" table). Build exactly that.

## Rules for you (this repo has no AGENTS.md)

- `CLAUDE.md` in this repo applies in full: wording only in `texts.py` (English and German), `models.py` = the
  contract, keep `docs/samples/` valid, never execute anything real in tests, never log a token.
- Write only inside your worktree. Never commit, push or touch git config (Claude commits). Install nothing. No network.
- Tests: `~/aresus/.venv/bin/python -m pytest -q` from your worktree.
- No real personal data in tests or samples.

## Read first

`docs/API.md` → "Drops"; `src/aresus/drops.py` (`cancel`, `upload` and its `_active` uploads, `listing`, `done`,
`failed`, `housekeeping`, `drop_note`); `src/aresus/push.py` (`drops_landed`); `src/aresus/texts.py` (the `drop_*`
texts); the drops route in `src/aresus/api.py`; the drops tests.

## Build

1. **`DELETE /drops/{id}` removes the drop from the list in every state → `204`.**
   - `uploading`, `waiting`, `failed`: cancel as today first (delete its `.age`/`.age.part` file; an upload that is
     streaming right now must stop and leave no file and no error in the log beyond one quiet line). The Mac must
     never get it afterwards: not in `GET /drops/pending`, `GET /drops/{id}/file` → `404`, `done`/`failed` →
     `404` (today's Mac program treats any HTTP error as "try later" and drops it from its pass once it is no longer
     pending; check that in `~/aresync/drop.py` → `Worker` and say if you see a case where it would loop).
   - `landed`, `cancelled`: just leave the list. Nothing on the Mac is touched.
   - Afterwards the drop is gone from `GET /drops`. A second delete or an unknown id → `404`.
   - Choose the simplest sound way (deleting the row, or a hidden mark that housekeeping later deletes) and say which
     and why. The 30-day housekeeping and the 7-day reminder keep working; a removed drop never gets a reminder or a
     landed push.
2. **Landed push wording:** one file → body `"<name> delivered"` / German `"<name> zugestellt"` (the landed file's
   own name, the last part of `landed`, so a "(2)" the Mac added shows); several → `"<n> files delivered"` /
   `"<n> Dateien zugestellt"`. A fallback or skipped-inventory note is still added after " · " exactly as today; the
   length budget that keeps the note visible stays. Title, url, interruption and collapse ids unchanged. Remove the
   texts nothing uses any more (`drop_folder_count`, and the old one/many bodies).
3. **Samples:** update `docs/samples/` if any shows the old push or a delete answer.

## Settled: do not re-open

- The contract in `docs/API.md` as it stands. If something in it cannot work, leave a `TODO(contract)` and say so.
- No undo on the server; the app shows the delete at once.

## Out of scope

The Mac program, the app, every other route.

## Done when

- `~/aresus/.venv/bin/python -m pytest -q` passes, with new or changed tests for: delete in each of the five
  states (`204`, gone from `GET /drops`, the file gone for the pending ones, the Mac's `pending`/`file`/`done`
  afterwards), delete while an upload is streaming, a second delete `404`, no reminder or landed push for a removed
  drop, the one/several landed pushes in English and German with and without a note.
- Fake mode (`ARESUS_FAKE=1`) still starts.

## Final message

Files changed, the exact pytest summary line, which way you removed drops and why, anything you saw in the Mac
program, every `TODO(contract)`, and anything doubtful.
