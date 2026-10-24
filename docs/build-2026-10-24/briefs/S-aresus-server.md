# S: Aresus server (watchtower + Aresync reports) and the Aresync report

Read `COMMON.md` (same folder) first. Worktrees: `~/wt/aresus-server` (branch `server`, the new `aresus` repo) and
`~/wt/aresync-report` (branch `report`, the `aresync` repo).

## Goal

The server of the **Aresus iPhone app**: it checks every province on the empire's server, decides Issue / Active /
Inactive, keeps incidents and uptime, receives a report from every Aresync run on every machine, and pushes when an
issue opens or closes and when Aresync raises an alert. Contract: `docs/API.md` + `docs/samples/` (given; read fully).
Why: `~/ares-empire/docs/ARESUS-APP.md` (settled decisions; read fully).

## Read first

- `~/wt/aresus-server/docs/API.md`, `docs/samples/*.json`, `~/ares-empire/docs/ARESUS-APP.md`,
  `~/ares-empire/docs/PUSH.md` (internal `/send`), `~/ares-empire/docs/ACCOUNTS.md` → "How a service checks a login",
  `~/ares-empire/webauth/server.py` (`token_access`: reference for the token check)
- `~/wt/aresync-report/aresync.sh`, `windows/aresync.ps1`, `README.md`, `config.example`, `windows/config.example.ps1`
- `~/ares-empire/web/app/empire-data.js` (province slugs, names, logos; on the server the hub's live copy is
  `/root/ares-empire/data/state.json` with the same `projects` shape; read it for names/logos/blurbs, fall back to
  `checks.yaml`)

## Build — Aresus (`~/wt/aresus-server`)

- **Stack:** Python (`>=3.11`), FastAPI + uvicorn on `127.0.0.1:8098`, SQLite, httpx, PyYAML; one process: API + a check
  loop (every 60 s) + a deploy loop (every 30 min). Package `src/aresus/`, `pyproject.toml`, tests with pytest.
- **Runs on the Linux server as root** (needs `systemctl` and `docker`). Everything that runs a command goes through one
  small runner interface so tests use fakes; on the Mac nothing real is executed.
- **`checks.yaml`** (committed; no secrets) declares each province: `slug`, optional `name`/`logo` fallback, `expect:
  active | inactive`, `line` (a short template, e.g. `"Website {website.ms} ms"`, `"Off on purpose · website {website.word}"`),
  and checks of these types: `unit` (systemd: `systemctl show -p ActiveState,SubState,ActiveEnterTimestamp`), `timer`,
  `container` (docker inspect: running + health if present), `http` (URL, expected statuses, timeout 10 s; record ms),
  `tls` (host:443 certificate expiry; issue below 10 days), `json` (a local health URL whose JSON feeds the line),
  `deploy` (git checkout path: last commit; `behind` from a `git fetch` in the deploy loop, never pulling). Initial
  content (today's server):
  - `empire` "Ares Empire": units `ares-empire.service`, `ares-empire-bot.service`, `empire-accounts.service`,
    `empire-push.service`, `caddy.service`; timer `empire-sync.timer`; http `https://www.ares-empire.de/login` (200),
    `https://auth.ares-empire.de/api/health` (200); tls `www.ares-empire.de`, `auth.ares-empire.de`; deploy
    `/root/ares-empire`. Expect active.
  - `aresium`: units `aresium.service`, `aresium-bot.service`; container `aresium-db-1` (healthy); http
    `https://aresium.de/` (303 or 200); tls `aresium.de`; deploy `/root/aresium`. Expect active.
  - `arestemis`: unit `arestemis.service`; json `http://127.0.0.1:8097/api/arestemis/health` (line: "Hunting · last scan
    …" when `hunting > 0`, else "Paused"); deploy `/root/Arestemis`. Expect active (the service runs even when no hunt is on).
  - `aresync`: no service checks; its state comes from the sync data (issue when a machine has an open problem that
    Aresync alerted about or the server has not reported for 30 min; line "3 machines · last sync 4 min ago").
  - `arestoteles`: container `arestoteles-web-1`, http `https://www.arestoteles.de/` (302 or 200), deploy `/opt/arestoteles`.
    Expect **inactive** (stopped on purpose; line "Off on purpose · website up").
  - `aresis`: expect inactive, no checks, line "Not deployed".
  - Any province in the hub's `state.json` without an entry here → `inactive`, word **Planned**, line "Not built yet".
- **State rules:** a check counts as failing only after **two consecutive failed rounds**. `expect: active` + any failing
  check → `issue` (word "Issue", line = the first failing check, e.g. "Website down since 14:02 (502)"); all ok →
  `active`. `expect: inactive` → always `inactive` (word "Inactive"), its checks only inform the line. The server
  (disk > 0.85, memory > 0.92 → `issue` on the server object) also counts in `summary`. Sorting and `summary` exactly
  as the contract.
- **Incidents and uptime:** an incident opens when a province enters `issue` and closes when it leaves; per-day uptime
  ratio from the check rounds (14 days kept for uptime, 30 days for incidents).
- **Push** via `PUSH_URL` (default `http://127.0.0.1:8096/send`), app `de.ares-empire.aresus`, `to: {"all": true}`,
  exactly the four cases and texts of the contract; one push per incident open and one per close; never more than one
  push per province per 10 minutes (flapping).
- **Aresync reports:** `POST /api/aresus/sync/runs` with a machine token (Bearer); `machines.json` (git-ignored, path from
  env `MACHINES_FILE`) maps `name → {os, sha256}`; `scripts/new-machine-token.py <name> <os>` creates a random token,
  prints it once, stores only its hash. Validate the body (64 KB, 500 lines), store runs 30 days, compute `quiet` (no
  clones/commits/pulls/pushes, no problems, result ok), fold quiet runs per machine and day in `GET /sync`, push the
  report's `alerts`. Machine `state` as in the contract.
- **App routes** as in the contract with the Empire token check (service `aresus`, 60 s cache keyed by a token hash;
  401/403/503). Unauthenticated `GET /api/aresus/health` → `{"ok": true, "checked": …}` (no details).
- **Tests:** state machine (two-round rule, expect inactive, planned), sorting/summary, line templates, incidents and
  uptime, flapping limit, push payloads, each check type with fake runner/fake HTTP, auth (fake PocketBase), every route,
  sync report validation/auth/quiet folding/alerts push, and **the samples validate** against your models.
- **Deploy files:** `deploy/aresus.service` (systemd, root, `WorkingDirectory=/root/aresus`, venv `/root/aresus/.venv`),
  `deploy/README.md` (install, `.env`, machine tokens, Caddy `handle /api/aresus/*` → `127.0.0.1:8098` in the
  `ares-empire.de, www.ares-empire.de` site before the hub's catch-all, logs), `.env.example`, a `CLAUDE.md` for the repo
  (what it is, rules, how to test), README update.

## Build — Aresync report (`~/wt/aresync-report`)

- `aresync.sh`: collect the run's log lines (the existing `log` function can also append to an array) and, at the end of
  **every** run (also the early `send_alerts partial; exit 1` aborts), send one report as in the contract: machine name
  (`ARESUS_MACHINE`, default the short host name), os (`uname`), start/finish UTC, result, counts, lines (without the
  timestamp prefix), problems, and the alerts this run sent (the `out` messages in `send_alerts`). Config:
  `ARESUS_URL` (default `https://www.ares-empire.de/api/aresus/sync/runs`) and `ARESUS_TOKEN` (empty = no report).
  Build the JSON with `python3` if present (bash 3.2 must stay supported; no `jq` dependency), send with `curl
  --max-time 15`, and **never** let the report change the run's outcome or exit code; a failed send is one log line.
  Telegram stays as it is (it retires later).
- `windows/aresync.ps1`: the same report (`ConvertTo-Json`, `Invoke-RestMethod`, try/catch, timeout), config in
  `windows/config.example.ps1`. You cannot run PowerShell here: keep it simple and say so.
- Update `config.example`, `README.md` (a short "Reports to Aresus" section; the server section: REPOS can list several
  repos and each may have a deploy hook), and add example hooks under `hooks.example/` for the server:
  `Arestemis` (`systemctl restart arestemis.service`), `aresus` (`systemctl restart aresus.service`), `ares-empire`
  (restart `ares-empire.service ares-empire-bot.service`; if `push/` changed also `empire-push.service`).
- **Test without syncing anything real:** a test script (`tests/test-report.sh`) that runs `aresync.sh` with a temporary
  `REPO_ROOT`, a fake `gh` first on `PATH` that lists one local bare repo, a temporary config, and a tiny local HTTP
  server (python) as `ARESUS_URL` that saves the report; assert the JSON fields, that a failing report endpoint does not
  change the exit code, and that an abort still reports. **Never run aresync.sh against `$HOME` or real repos.**

## Done when

- `cd ~/wt/aresus-server && .venv/bin/python -m pytest -q` passes; the service starts locally with a temp DB and fake
  checks mode (`ARESUS_FAKE=1` or similar) and answers `/api/aresus/health`; authed routes answer 401 without a token.
- `bash tests/test-report.sh` passes in `~/wt/aresync-report`.
- Both branches committed. Final message as in COMMON.md, with exact deploy steps (Aresus install, machine tokens for
  `Aresium` (the MacBook) and `Server`, Aresync config lines, server REPOS + hooks).
