# R1: Arestoteles server: the Weltbild vault API (and the trading code goes)

Read `COMMON.md` (same folder) first; its rules hold: only your worktree, commit on your branch but never push or merge,
no SSH, no secrets, no installs outside a `.venv` in the worktree. Worktree: `~/wt/Arestoteles-app` (branch
`weltbild`; its first commit holds the contract). Python: `/opt/homebrew/bin/python3 -m venv .venv`.

## Why

Patrik retires the trading bot. Arestoteles becomes the iPhone app for his Weltbild: an Obsidian vault of topics,
positions, mechanisms, events and questions. Read, in this order:
1. `~/ares-empire/docs/ARESTOTELES-APP.md` (the decisions; do not re-open them),
2. `docs/API.md` and `docs/samples/*.json` in your worktree (the contract; build exactly this),
3. the vault's own rules: `~/Documents/Patrik Breeck/Weltbild/CLAUDE.md` (the note types, frontmatter, positions,
   callouts, voice rules, "How my view changed") and its check `~/Documents/Patrik Breeck/Weltbild/.tools/check.rb`.
   **That folder is Patrik's real vault: read only, never write, never copy its content into the repo or a test.**
4. `~/ares-empire/docs/LANGUAGES.md` and `~/empire-ios/docs/build-2026-10-24/briefs/L-COMMON.md` → "The language
   contract" (error texts in English and German, `Accept-Language`).
5. The Aresus server as the pattern for an Empire service: `~/aresus/src/aresus/auth.py` (the login check: service
   `arestoteles` here), `api.py`, `texts.py`, `deploy/`, its tests.

## Build

1. **Delete the trading code.** Keep everything the website arestoteles.de needs and only that: `web/`, `webauth/`,
   the compose `web` service, `scripts/refresh_quotes.py` and its timer unit, the brand assets, and whatever those
   import (read `docker-compose.yml`, `webauth/server.py` and the quotes script to be sure). Delete the engine
   (`src/arestoteles/` as it is now, its tests, `migrations/`, `config/`, the other compose services, the trading
   timers, the trading docs `docs/01`–`docs/10`; keep `docs/11-web-frontend.md`). Rewrite `README.md` and `CLAUDE.md`
   short for the new purpose (keep the website's operating notes). List in your final message what the lead must
   stop or remove on the server (old timers, the `db` container and its volume: say what exists in the deploy files,
   the lead checks the server).
2. **The vault service, exactly as `docs/API.md`:** `python -m arestoteles`, FastAPI + uvicorn on `127.0.0.1:8099`,
   one process: the API plus the sync loop. Settings by environment (`ARESTOTELES_VAULT` = the clone, default
   `/var/lib/arestoteles/vault`; the account server URL like Aresus). Modules, each small and tested:
   - **reader:** a note file → `Note` (frontmatter YAML, title, summary box, blocks, callouts, positions, history,
     part-of line, event fields, links). Use a well-trodden Markdown parser (e.g. `markdown-it-py`) for the CommonMark
     structure and add the Obsidian parts yourself (wikilinks with alias and heading, embeds, callouts with titles,
     `→ [[…]]` section links, "(draft)"). Text fields become the inline Markdown the contract describes.
   - **index:** the whole `Vault`: ids, link resolution (unresolved links stay plain text), backlinks, topic membership,
     positions (Positions.md: "Across topics", then each embedded topic in that page's order), glossary (Glossary.md's
     table), briefs, `home.learn_next`.
   - **git:** pull every 60 s (fast-forward or rebase; never lose a local commit), rebuild when the commit changed,
     commit and push edits as the contract says, retry pushes in the loop when GitHub is unreachable.
   - **edits:** every op of the contract, by the vault's rules (positions renumbered, history entries, `updated`,
     quick notes verbatim). Then the vault's check (`ruby -E UTF-8:UTF-8 .tools/check.rb`, run inside the clone; read
     the script for its output format): errors undo the edit (`422`), warnings are returned. Ruby is on the server; when
     it is missing, skip the check and return a warning saying so.
   - **auth** (copy Aresus's approach), **texts** (English and German error texts), **health**.
3. **Tests (pytest):**
   - a **made-up fixture vault** in `tests/fixtures/vault/` with the same notes as `docs/samples/vault.json`. Building
     it must give exactly that sample, except `commit`, `built` and each `version`. If you find the sample wrong
     against the contract, fix the sample and say so in your final message.
   - every edit op, including 409 (version changed, position gone), 422 (check error), rebase over a concurrent push
     (a temporary bare remote), a real conflict undoing the edit, push failure keeping the commit.
   - auth, languages, ETag/304, health.
   - **the real vault, read-only:** a test that runs only where `~/Documents/Patrik Breeck/Weltbild` exists, copies it
     to a temp dir and builds the index: no exceptions, every position found, every link either resolved or reported.
     It must print and assert only counts, never content.
4. **Deploy files** (the lead deploys): `deploy/arestoteles.service` (systemd, runs as root like Aresus, from the
   server's checkout `/root/Arestoteles`), the Caddy snippet for `/api/arestoteles/*` inside the `www.ares-empire.de`
   site (before the hub's catch-all, like Aresus), an Aresync deploy hook (what it runs after a pull), and the
   `checks.yaml` entry for Aresus (the province becomes active: the unit, `GET /api/arestoteles/health`, the deploy
   checkout). Exact steps in `deploy/README.md`.

## Done when

- `.venv/bin/python -m pytest -q` passes, including the sample test and (on this Mac) the real-vault test; print its
  counts in your final message (notes, positions, unresolved links), no content.
- `python -m arestoteles` started against a temp copy of the real vault (pushing disabled) answers `GET /vault`
  locally with a fake login (test client), in under a second for the whole vault.
- The website files are untouched and the compose file still describes the `web` service.

Final message as `COMMON.md` says, plus the server clean-up list from step 1.
