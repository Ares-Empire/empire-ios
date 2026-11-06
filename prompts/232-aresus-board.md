# 232: Aresus server: the board (asks for Patrik, work for a topic's session, scans, brief numbers)

Status: running 2026-11-06
Branch: `codex/232-board` · Worktree: `../aresus-232-board` (a worktree of **`~/aresus`**, the server repo, not of
empire-ios) · Model: `gpt-6.1-sol`, effort `high`

## Goal

Claude sessions on three machines build things and ask Patrik questions; when a session's attention moves on, finished
work sits unmerged and questions get buried (on 2026-11-05 five questions had waited two days, and two finished fixes
sat unmerged). The board is one list on the server: **asks** (a decision or action only Patrik can take) go to the
Aresus app; **work** (open work in a repo or area) goes to the session working on that topic, never to Patrik. Machines
send a scan of their repos (branches not merged, uncommitted worktrees), and sessions take brief numbers from one
counter so two sessions never pick the same number again. This brief builds the server half. The machine half
(aresync's `board` command, the scan, the session hooks) is brief 233, built at the same time against the same
contract; the app tab comes later.

## Rules for you (this repo has no AGENTS.md)

- `CLAUDE.md` in this repo applies in full: commands only through `runner.Runner`, wording only in `texts.py` (English
  and German), `models.py` = the contract, keep `docs/samples/` valid, never execute anything real in tests, never log
  a token.
- Write only inside your worktree. Never commit, push or touch git config (Claude commits). Install nothing. No network.
- Run the tests with the main checkout's virtualenv from your worktree: `~/aresus/.venv/bin/python -m pytest -q`.
- No real personal data in tests or samples: made-up topics, questions and session ids only.

## Read first

- **The contract, settled:** `docs/API.md` → "Board (version 1, 2026-11-06)". Build exactly that. If something in it
  cannot work, do not change it: leave a `TODO(contract)` and say so in your final message.
- Why: `~/ares-empire/docs/reviews/2026-11-05-work-board.md`, the sections "Patrik's decisions" and "The design that
  follows" (read only).
- `CLAUDE.md`, `src/aresus/api.py` (auth helpers, `_read_body`, the run-report and drop routes as the pattern for
  machine routes), `machines.py` (`MachineRegistry.verify`), `auth.py`, `config.py`, `store.py` (SQLite style and how
  the schema is made or migrated at startup), `monitor.py` (`run_round`, `housekeeping`), `push.py` (`Pusher`,
  `_payload`, the owner-only transport), `service.py`, `texts.py`, `models.py`, `fake.py`, `tests/conftest.py`.

## Build

1. **Models** (`models.py`): `Item`, `NewItem`, `ScanFinding`, `ScanReport`, `Waiting`, `Summary`, `Brief` and the small
   request bodies, with the contract's limits as validation (topic and session name shapes, lengths, at most 4 distinct
   options, `why` required for an ask, `options` empty for work, `source` starting with `session:`, `due` a real date,
   at most 500 findings). A bad body is `400` naming the field, in the request's language, like the other routes.
2. **Storage** (in `aresus.db`, so the nightly backup has it; schema made at startup the way `store.py` does it):
   items (every `Item` field, plus the scanning machine for scan items and the `since` a scan item was dropped at),
   topic reads (topic → last read), briefs (number unique), and the date of the last board push. Brief numbers come
   from one transaction (`BEGIN IMMEDIATE`), so two requests at the same moment never get the same number; test it
   with threads. `BOARD_BRIEF_START` in `config.py` and `.env.example` (default 235).
3. **`board.py` (new):** the rules, separate from the routes and testable without HTTP: state changes and their `409`s,
   the scan replace (new key opens, reported key updates `text` and `since`, missing open key is done, dropped key stays
   dropped until `since` is newer, keys are per machine), `unowned` (open work older than 48 h, not sent in the last 48
   h, its topic not read in the last 48 h; topics most items first, at most 5), the query filters of `GET /board/items`
   (a `topic` query marks the topic read), the `429` limits (scan items never count), the sort orders, housekeeping.
   Times come from an injected clock, as elsewhere.
4. **Routes** (`api.py`): every route of the contract. App routes use the app's auth; machine routes any machine token;
   `done` and `drop` take either (check the machine registry first, then the Empire login). `413` over 256 KB.
5. **Housekeeping** (the existing 30-minute loop): done and dropped items older than 90 days are deleted; answered
   asks older than 30 days become done.
6. **Push** (the check round): at most once a day, at the first round after 09:00 Europe/Berlin, when an open ask is
   due within two days or has waited more than 24 h: the contract's title and body (English and German through
   `texts.py`), `url: aresus://board`, passive, once per owner like every Aresus push. The day is stored, so a restart
   does not push twice. No push for work, for younger asks or for answers.
7. **Fake mode** (`fake.py`, `ARESUS_FAKE=1`): a few made-up items (two asks, one with options and a due date, one
   action; one answered ask; some work in two topics; one brief) so the app can be built against it.
8. **Samples:** `docs/samples/board-waiting.json` (made up, valid against `Waiting`), checked by the samples test like
   the others.
9. **Tests:** every route with both auths and every error code; the scan rules above, including two machines with the
   same key and a dropped finding that changes; `unowned` at the 48-hour edges; the brief counter under threads and its
   start value; the push once a day, not before 09:00, not after a restart the same day, German text; housekeeping.
   The whole suite stays green.

## Done means

All tests pass with the command above. In your final message: what you built, anything you could not build as the
contract says (`TODO(contract)`), and anything Claude must do when deploying (new settings, the schema change).
