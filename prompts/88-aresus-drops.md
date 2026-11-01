# 88: Aresus server: drops, files from the iPhone to the MacBook

Status: merged 2026-11-01 (aresus eceb410, 579 tests; Claude: pending drops never cleaned up, upload time limit grows with the file)
Branch: `codex/88-drops` · Worktree: `../aresus-88-drops` (a worktree of **`~/aresus`**, the server repo, not of
empire-ios) · Model: `gpt-6.1-sol`, effort `high`

## Goal

Patrik sends a file or photo from the Aresus app; it lands in a chosen folder on his MacBook, from anywhere. This
brief builds the server half: the app uploads, the server **encrypts the file on arrival with `age`** and keeps it
only until the MacBook has fetched it, and it tells Patrik by push where it landed. The Mac half is brief 89 (built at
the same time, against the same contract), the app comes later.

## Rules for you (this repo has no AGENTS.md)

- `CLAUDE.md` in this repo applies in full: commands only through `runner.Runner`, wording only in `texts.py` (English
  and German), `models.py` = the contract, keep `docs/samples/` valid, never execute anything real in tests, never log
  a token.
- Write only inside your worktree. Never commit, push or touch git config (Claude commits). Install nothing. No network.
- Run the tests with the main checkout's virtualenv from your worktree: `~/aresus/.venv/bin/python -m pytest -q`.
- No real personal data in tests or samples (made-up names and folders only).

## Read first

- **The contract, settled:** `docs/API.md` → "Drops (Aresync drop, version 1)". Build exactly that. If something in it
  cannot work, do not change it: leave a `TODO(contract)` and say so in your final message.
- Why: `~/ares-empire/docs/ARESYNC-DROP.md` (read only).
- `CLAUDE.md`, `src/aresus/api.py` (auth helpers, `_read_body`, the run-report route as the pattern for a machine
  route), `machines.py` (`MachineRegistry.verify`), `auth.py`, `config.py`, `runner.py`, `push.py` (`Pusher`,
  `_payload`, the owner-only transport), `monitor.py` (`run_round`, `housekeeping`), `service.py`, `store.py`
  (SQLite style), `texts.py`, `models.py`, `tests/conftest.py` (`ScriptedRunner`, the fake world).

## Build

1. **Config** (`config.py`, `.env.example`): `DROP_MACHINE` (the machine name whose token may use the Mac routes),
   `DROP_AGE_RECIPIENT` (`age1…`), `DROP_DIR` (default `data/drops`), `DROP_MAX_BYTES` (default 200 MB),
   `DROP_MAX_TOTAL_BYTES` (default 2 GB), `DROP_AGE` (the age binary, default `age`). Without `DROP_MACHINE` or
   `DROP_AGE_RECIPIENT` every drop route answers `503` with a clear sentence.
2. **`drops.py` (new):** its own SQLite file `drops.db` inside `DROP_DIR` (not `aresus.db`: the nightly backup takes
   that file, and drops must stay out of the backup). `DROP_DIR` is made with mode 700, files inside 600. Holds the
   drops (all fields of the contract plus the ciphertext's file name, the first-failure flag, the reminder flag) and
   the last folder list. Pure validation functions with tests: new names, folder parts (they may contain `:`), the
   target/receipt rules per kind, dates, sha256 shape, receipt field limits.
3. **Upload and encryption (`PUT /drops/{id}/file`):** stream the request body straight into the stdin of
   `<DROP_AGE> -r <recipient> -o <DROP_DIR>/<id>.age.part`, counting bytes and computing sha256 on the way. Size and
   checksum match → rename to `<id>.age`, state `waiting`; otherwise delete the part file, answer `400`, the drop stays
   `uploading`. More bytes than `size` or `DROP_MAX_BYTES` → stop and `413`. The waiting total would pass
   `DROP_MAX_TOTAL_BYTES` → `507` before reading. **The plaintext never touches disk** (no temp files, no buffering the
   whole file in memory: stream in chunks). Add a streaming method to the `Runner` protocol for this (for example
   `pipe(args, chunks, timeout) -> CommandResult`), implement it in `SubprocessRunner`, and fake it in tests (the fake
   writes a recognisable transformation of the bytes, so a test can prove the stored file is not the plaintext).
4. **Routes** (`api.py`): the ten routes of the contract. App routes with the existing `app_user`; Mac routes with a
   new dependency: unknown token `401`, a known machine other than `DROP_MACHINE` `403`. Register
   `/drops/folders` and `/drops/pending` before the `{id}` routes; ids match `^[0-9]{1,15}$`. `GET /drops/{id}/file`
   streams the `.age` file. `PUT /drops/folders` limited to 1 MB.
5. **States:** `uploading → waiting → landed`; `waiting → failed → (failed …) → landed`; `uploading | waiting | failed →
   cancelled` (file deleted). `done` deletes the `.age` file. Wrong state → `409` as the contract says.
6. **Notes** (`Drop.note`): rendered from codes in the request's language, wording in `texts.py`: each `fallback`
   reason, `inventory: skipped` ("The receipt is filed, but its INVENTORY.md row is missing: the table did not look as
   expected." and German), a failure's reason. Null when there is nothing to say.
7. **Pushes** (`push.py` + the check loop): the three kinds in the contract's table, English + `localized.de`.
   Landed drops are collected and sent **once per check round** (one file: the last folder and the name; several: the
   count and the folders with counts), so twenty photos make one push. First failure of a drop: an `active` push with
   `collapse_id: "drop-<id>"`; a landed push for a single drop uses the same collapse id. Reminder once per drop after
   7 days waiting (combined per round like landed). All drop pushes go through the existing owner-only transport.
8. **Housekeeping** (the existing 30-minute loop): remove `uploading` drops older than 24 h with their part files,
   send due reminders, delete rows older than 30 days, delete `.age`/`.part` files that belong to no pending drop.
9. **Models and samples:** the contract's types in `models.py`; routes validate against them. New
   `docs/samples/drops.json` (a `{"drops": [...]}` with one drop per state) and `docs/samples/drop-folders.json`, both
   made up and checked by the samples test.
10. **Docs:** `deploy/README.md` → a "Drops" section: the new `.env` settings, that `age` is already installed for the
    backups, that the drop key is made on the Mac (its secret half stays in the Mac's Keychain; only the `age1…` public
    half goes into `DROP_AGE_RECIPIENT`), and that `DROP_DIR` is not in the backup. `CLAUDE.md` → Layout gets
    `drops.py`.

## Settled: do not re-open

- The contract in `docs/API.md` (Claude's, 2026-11-01).
- Encryption with the `age` CLI through the Runner, not a Python library: the backups already use it on this server.
- A separate `drops.db` in `DROP_DIR`, outside the backup.
- Integer ids; one drop per file (several photos = several drops).
- A failed drop stays pending; only its first failure pushes.

## Out of scope

- The Mac program (brief 89), the app, Caddy (it already routes `/api/aresus/*`), deploying, making the real key.
- The AI suggestions (step 3 of the plan).

## Done when

- `~/aresus/.venv/bin/python -m pytest -q` passes, with new tests for: every name/folder rule (including `:` allowed
  in folder parts, refused in new names); each route's success and each error code of the contract; upload size
  and checksum mismatch leaving the drop `uploading` and no file behind; the stored file never equal to the
  plaintext and no other file in `DROP_DIR` than `drops.db`, `.age` and `.part` files; another machine's token `403`;
  `503` when not set up; state changes and `409`s; combined landed pushes (one and several), the failure push only
  once, collapse ids, German texts; housekeeping; both samples valid.
- Fake mode (`ARESUS_FAKE=1`) still starts.

## Final message

Files changed, the exact pytest summary line, every `TODO(contract)`, and anything doubtful.
