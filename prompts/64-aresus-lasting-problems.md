# 64: Aresus server: Arestemis's portals watched, alerts only for problems that last

Status: draft
Branch: `codex/64-lasting-problems` · Worktree: `../aresus-64-lasting-problems` (a worktree of **`~/aresus`**, the
server repo, not of empire-ios) · Model: `gpt-6.1-sol`, effort `high`

## Goal

Arestemis's Telegram bot is retired, and Arestemis never tells its users about outages. Patrik (2026-10-31) wants
those alerts in **Aresus**, for him only: when a search portal blocks the server or fails for a long time, when the AI
check fails. **They must not overdo it.** The old bot sent "we're blocked" and ten minutes later "we're not blocked
anymore", over and over; that is exactly what this brief prevents.

After this brief Aresus watches each Arestemis portal as its own check (read from Arestemis's existing `/health`), and
a check can say how long a problem must **last** before it counts and how long it must be **fine** before it is over.
A short block never pushes; a long one pushes once, without breaking through Focus; the "back" note arrives silently
and replaces the alert on the lock screen.

## Rules for you (this repo has no AGENTS.md)

- `CLAUDE.md` in this repo applies in full: state rules only in `decide.py` (pure, with tests), the four push cases
  of the contract, wording only in `texts.py` (English and German), `models.py` = the contract, keep `docs/samples/`
  valid, never execute anything real in tests.
- Write only inside your worktree. Never commit, push or touch git config (Claude commits). Install nothing. No network.
- Run the tests with the main checkout's virtualenv from your worktree: `~/aresus/.venv/bin/python -m pytest -q`
  (pytest's `pythonpath = ["src"]` puts your worktree's code first).
- No real personal data in tests or samples.

## Read first

- `CLAUDE.md`, `README.md` → "How it decides", `docs/API.md`, `checks.yaml` (its header explains every option)
- `src/aresus/spec.py` (`CHECK_TYPES`, `OPTIONS`, `CheckSpec`), `src/aresus/checks.py` (`check_json`, `make_result`),
  `src/aresus/decide.py` (`Streak`, `advance`, `FAIL_ROUNDS`, `decide`), `src/aresus/monitor.py` (`run_round`,
  `_settle`), `src/aresus/push.py` (`issue_opened`, `issue_resolved`, `Pusher`), `src/aresus/store.py` (the `checks`
  and `incidents` tables), `src/aresus/texts.py`
- What Arestemis's health answers today (`~/Arestemis/docs/API.md`, `GET /health`; read only, do not change that
  repo): `{"ok": true, "hunting": 1, "last_scan": "2026-10-31T20:07:19Z", "sources": {"wg_gesucht": "ok",
  "kleinanzeigen": "ok", "immowelt": "idle"}}`. Each source is `ok | blocked | error | idle` (`idle` = not used by any
  active hunt). Blocked = HTTP 403/429, a captcha page, or WG-Gesucht's detail pages paused after 429s; error = other
  HTTP errors, network errors, or a list page without listings (a layout change).
- The push service's fields: `~/ares-empire/docs/PUSH.md` (`interruption`, `collapse_id` ≤ 64 bytes; unknown fields
  are a 400).

## Build

1. **A new check type `field`: one value of another check's JSON in the same province, no request of its own.**
   ```yaml
   - field: health.sources.wg_gesucht   # <id of a json check in this province>.<path into its JSON body>
     name: WG-Gesucht
     ok: [ok, idle]                     # the values that mean fine
     after: 60
     clear: 30
     urgent: false
   ```
   - `check_json` keeps the whole parsed body for this (the line templates still see only the top-level scalars, as
     today). The `field` check is evaluated after the round's json checks of its province, from that round's body.
   - Spec validation: the id must name a `json` check of the same province, the path must be non-empty, `ok` is a
     non-empty list of strings/numbers/booleans (no default: always given). Clear `SpecError`s with tests.
   - **No news is not a problem:** when the referenced json check failed this round, or the path is missing in the
     body, the field check's streak stays exactly as it was (the unit/json checks already report that Arestemis is
     down; a restart must neither open nor end a portal problem). Its row in the app says so ("unknown: health not
     readable" / "unbekannt: Health nicht lesbar", wording in `texts.py`).
   - Problem wording from the value, in `texts.py`: `blocked` → "WG-Gesucht blocked" / "WG-Gesucht gesperrt",
     `error` → "WG-Gesucht failing" / "WG-Gesucht gestört", any other value → "WG-Gesucht: <value>". The issue line gets
     " since 14:02" as for every timed check: "WG-Gesucht blocked since 14:02". The row's `detail` when fine is the
     value, translated (`ok` → "ok", `idle` → "not in use" / "nicht genutzt").
2. **Two new options for every check type: `after` and `clear`, in minutes.** Rules (in `decide.py`, pure):
   - A **problem run** starts at the first failed round (`failing_since`, as today).
   - A run **ends** only when the check has been fine for `clear` minutes in a row. Fine rounds shorter than that do
     not end it (and do not reset `failing_since`). `clear` defaults to 0: the first fine round ends it, as today.
   - The check **counts** (makes the province an Issue) when the run is open and either it already counted in this run,
     or the latest round failed and the run is at least `after` minutes old. Without `after` the rule stays "two
     failed rounds in a row" (`FAIL_ROUNDS`).
   - So a check that counted keeps counting through short fine spells until `clear` has passed; the province stays an
     Issue (line "WG-Gesucht blocked since 14:02") and no push goes out during those spells.
   - **Without `after` and `clear`, every existing check behaves exactly as today:** prove it with the existing tests
     unchanged plus a table test of old behaviour.
   - `Streak` gets what it needs (for example `fine_since` and `counted`); stored in the `checks` table with a schema
     step that keeps today's rows working (old rows read as "not counted, no fine spell"). Test the upgrade on a database
     made with today's schema.
3. **`urgent` (default true) decides how an opening push interrupts.** When the province's cause check has
   `urgent: false`, `issue_opened` is sent as `interruption: "active"` (a normal notification: it does not break
   through Focus) instead of `"time-sensitive"`, and as `"passive"` (no sound, no screen) when **the province's previous
   incident ended less than 6 hours ago** (a problem that keeps coming back says so once loudly, then quietly). Urgent
   causes stay time-sensitive as today.
4. **The "back" note replaces the alert.** Both pushes of one incident carry `collapse_id: "incident-<incident id>"`,
   so on the lock screen the resolved note (still `passive`) replaces the alert instead of standing beside it. Applies
   to every province's incidents. Add the field in `push.py` (and the pusher's held-push logic must keep it).
   Server-limit and Aresync pushes are unchanged.
5. **`checks.yaml`:** in the `arestemis` province, after the `health` json check, three field checks: WG-Gesucht
   (`health.sources.wg_gesucht`), Kleinanzeigen (`health.sources.kleinanzeigen`), Immowelt (`health.sources.immowelt`),
   each `ok: [ok, idle]`, `after: 60`, `clear: 30`, `urgent: false`, German names the same. Document `field`, `after`,
   `clear`, `urgent` in the file's header comment and in `README.md` → "How it decides". Keep the Arestemis line as it is.
6. **`docs/API.md`:** no shape changes (new checks appear as ordinary `Check` rows). Add one paragraph under the
   push/decision part saying how lasting checks and the collapse id work. Keep `docs/samples/` valid; if a sample
   province detail for Arestemis exists, add a field-check row to it.
7. **Tests** (new, all offline, with the fake clock):
   - a 10-minute block (blocked rounds, then fine): never an Issue, never a push, no incident;
   - blocked for 61 minutes: one Issue, one push with `interruption: "active"` and the collapse id, line
     "WG-Gesucht blocked since <time>";
   - after that: fine for 10 minutes, blocked again: still the same Issue, no second push, `since` unchanged;
   - fine for 30 minutes: resolved, one passive push with the same collapse id;
   - blocked again within 6 hours for 60+ minutes: opening push `passive`;
   - `idle` is fine; health unreachable for 20 minutes during a block: the run neither ends nor restarts;
   - German wording of the line and push ("WG-Gesucht gesperrt seit …");
   - spec errors for a wrong id, a non-json target, a missing `ok`;
   - the schema upgrade; existing tests pass unchanged.

## Settled: do not re-open

- **Aresus decides, Arestemis reports.** The thresholds live in `checks.yaml` (Patrik can change a number without a
  deploy of Arestemis); Arestemis's `/health` stays as it is in this brief.
- 60 minutes before a portal problem counts, 30 minutes fine before it is over, normal (not time-sensitive) delivery,
  quiet repeats within 6 hours: Claude's defaults from Patrik's "shouldn't be overdoing it"; he can change the numbers.
- The province stays the unit of incidents and pushes (one Arestemis incident even when two portals fail; the line names
  the first counted check), as for every province today.
- No app change: the new checks are ordinary rows on Arestemis's page in the Aresus app.

## Out of scope

- The Arestemis repo (another session is adding ImmoScout24 and Immowelt for every town in brief 63; ImmoScout24's
  check and the AI check's state come in a later brief once that has landed).
- The app (empire-ios), the Aresync alerts, the server limits, the 10-minute pusher limit (keep it).

## Done when

- `~/aresus/.venv/bin/python -m pytest -q` passes with the new tests, run against your worktree's code.
- `ARESUS_FAKE=1` start still works (`README.md` → Run it) and `checks.yaml` loads without errors
  (`python -c "from aresus.spec import load_spec; load_spec('checks.yaml')"` with `PYTHONPATH=src`).

## Final message

Files changed; the exact pytest summary line; the new `checks.yaml` entries and texts (English and German) in full; the
schema step; anything missing or doubtful.
