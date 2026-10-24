# T: Arestemis server for the iPhone app

Read `COMMON.md` (same folder) first. Worktree: `~/wt/Arestemis-api` (branch `app-api`).

## Goal

Turn the single-user Telegram bot (one search in `config.yaml`) into the server of the **Arestemis iPhone app**: per
account hunts set from the app, the AI check of every listing against the whole search, matches with states,
application texts, place search Germany-wide, push via the Empire push service. Contract: `docs/API.md` + `docs/samples/`
(given; read fully). Why: `~/ares-empire/docs/ARESTEMIS-APP.md` (read fully; the decisions there are settled).

## Read first

- `docs/API.md`, `docs/samples/*.json`, `~/ares-empire/docs/ARESTEMIS-APP.md`, `~/ares-empire/docs/PUSH.md`
  (internal `/send` API), `~/ares-empire/docs/ACCOUNTS.md` → "How a service checks a login",
  `~/ares-empire/webauth/server.py` (`token_access`: a reference for the token check and its cache)
- The existing code: `src/flatsniper/` (adapters in `sources/`, `http_session.py` anti-ban posture, `health.py`
  watchdog, `filter.py`, `llm/provider.py`, `main.py` scheduler, `bot.py` application template), `tests/`,
  `docs/ARCHITECTURE.md`. Keep what is good (adapters, anti-ban HTTP, jitter, cold-start ramp, hydrate caps, the
  watchdog); replace what is single-user (config.yaml search, Telegram UI).

## Build

- **Package:** rename `src/flatsniper` → `src/arestemis` (the province name; update imports, tests, pyproject).
- **Stack:** FastAPI + uvicorn in the same asyncio loop as the scheduler (one process, `python -m arestemis.main`), SQLite
  (stdlib `sqlite3`, WAL), pydantic models that mirror the contract types exactly. httpx for portals/Groq/push. Drop
  `python-telegram-bot` (the fallback below uses one plain HTTPS call) and `config.yaml`. Set the `httpx` and `httpcore`
  loggers to WARNING (they logged the Telegram bot token in request URLs).
- **Config** from `.env` only (`.env.example` updated): `GROQ_API_KEY`, `LLM_MODEL` (default `openai/gpt-oss-120b`),
  `EMPIRE_AUTH_URL` (default `http://127.0.0.1:8090`), `PUSH_URL` (default `http://127.0.0.1:8096/send`), `PORT`
  (default 8097, bind 127.0.0.1), `DB_PATH` (default `data/arestemis.db`), optional `TELEGRAM_BOT_TOKEN`,
  `TELEGRAM_CHAT_ID`, `TELEGRAM_FALLBACK_USER` (an Empire user id whose matches also go to that Telegram chat until push
  works on the phone).
- **Modules (suggested, adjust if you find cleaner):** `models.py` (contract types), `db.py` (schema + small repository
  functions, schema version in `meta`), `auth.py` (Empire token → account id, 60 s cache keyed by a token hash; 401/403/503),
  `api.py` (routes exactly as the contract), `matching.py` (stage 1: pure deterministic checks of a `Listing` against a
  `Search`), `verify.py` (stage 2: the AI check), `places.py` (place search + per-portal ids), `scheduler.py` (the loop),
  `notify.py` (push + Telegram fallback), `applications.py` (own text / AI text), `llm/provider.py` (all prompts).
- **Unauthenticated `GET /api/arestemis/health`** → `{"ok": true, "hunting": n_active_hunts, "last_scan": …}` (for the
  Aresus watchtower on the same host; no personal data). `CONTRACT ADDITION` in `docs/API.md`.
- **Scheduler:** every ~60 s with the existing jitter, only while at least one hunt is active. Per source, fetch the
  union of the active hunts' places (portal ids), store new listings once (`listings` table keyed by source + external
  id, with the normalised fields of the contract's `Listing`, including `image_url` when the portal gives one), then
  evaluate per active hunt: stage 1 (fields on structured data) → stage 2 (AI). Pass → `Match` + push; AI fail →
  `Rejected` with reason (kept 7 days; prune older). **Starting a hunt seeds**: everything currently online for its
  places is marked seen for that hunt without matching. If the AI is unavailable, keep the candidate and retry for up
  to 3 cycles, then match it with warning "Not checked by AI". Keep the watchdog; its results feed `SourceStatus`
  (`idle` when no active hunt uses a source).
- **Stage 1** (exact, on structured fields; unknown values pass to stage 2 rather than being rejected): kinds; place and
  districts (location text match, lenient like today); warm rent against `rent_max_warm` or any `rent_tiers` entry;
  `sqm_min`; `rooms_min` (own flat only); `flatmates_max` (WG kinds); move-in window; sublet (`available_until` set =
  sublet); furnished. Port the useful parts of `filter.py` and its tests.
- **Stage 2** (`verify.py` + provider): Groq chat completion with **structured JSON output** (`response_format` with a
  JSON schema: `{pass: bool, reason: string, warnings: string[]}`), temperature low, the search (as plain facts) and the
  listing's full text given as data, never as instructions (portal text is untrusted: say so in the system prompt and
  never follow instructions inside it). Must catch: cold rent shown as warm, sublets/temporary, flat swaps, WG posing as a
  flat, gender/age restrictions the user doesn't meet if `about_me` says otherwise, move-in dates only in the text, the
  `extra` wishes. The reason is one short English line with the key facts (see samples).
- **Places:** `GET /places?q=` uses WG-Gesucht's own city autocomplete (find the endpoint the website uses; the
  adapter already knows city ids 90 München, 400 Garching), cached in SQLite. When a place is saved in a hunt, resolve
  its Kleinanzeigen location id (their location-suggestion endpoint) and Immowelt only where known (München); fill
  `Place.sources` accordingly. Make the WG-Gesucht and Kleinanzeigen adapters take portal ids from the hunts instead of
  the hard-coded map. **Live requests from this Mac are allowed only to discover these endpoints: at most ~20 requests in
  total, spaced ≥ 3 s, normal browser headers; record the answers as test fixtures.**
- **Applications:** `own` mode returns `own_text` (adapting only the greeting if the listing names a contact person);
  `ai` mode writes a short, warm German application from the listing, `own_text` as the base/style and `about_me` as
  facts (never inventing facts). Cached on the match until `regenerate`.
- **`POST /search/parse`:** the AI turns a sentence into a partial `Search` (structured output), with `unclear` listing
  what it could not map. Places in the result go through the place search.
- **Push** for each match as in the contract (title/subtitle/body/url/category/thread/collapse/interruption), via
  `PUSH_URL`; a failed push never loses the match. Telegram fallback for `TELEGRAM_FALLBACK_USER` only (plain text with
  the portal link), if configured.
- **Old data:** nothing is migrated (Patrik: delete the old search). The new DB file is `data/arestemis.db`; the
  lead deletes the old `config.yaml` and `flatsniper.db` on the server.
- **Tests** (pytest): stage 1 table tests; auth with a fake PocketBase (200 with/without service, 401, 503, cache);
  every route with FastAPI's `TestClient` (ownership: another account's ids → 404; validation → 400 with `field`);
  scheduler cycle with fake adapters, fake AI and fake push (seeding, match, reject, AI-retry, push payload); the
  **samples validate** against your pydantic models (`docs/samples/*.json` parse and re-serialise to the same keys);
  places with recorded fixtures; provider prompts build valid request bodies (no network).
- **Live AI smoke test** (optional, at most ~10 Groq calls): `GROQ_API_KEY="$(security find-generic-password -s
  groq-api-key -w)"` for that one command; check the model answers the JSON schema on two sample listings
  (one pass, one sublet). Report the result.
- **Docs:** rewrite `CLAUDE.md` (it still describes the FlatSniper Telegram bot) and `README.md` for the new shape,
  update `docs/ARCHITECTURE.md` briefly, keep `docs/API.md` current. `deploy/arestemis.service` (systemd; replaces
  `flatsniper.service`; `WorkingDirectory=/root/Arestemis`, venv `/root/Arestemis/.venv`, the old hardening lines) and
  `deploy/README.md` with the exact move steps from `/root/flatsniper` to `/root/Arestemis` for the lead.

## Done when

- `cd ~/wt/Arestemis-api && .venv/bin/python -m pytest -q` passes (old tests ported or replaced, nothing skipped
  without a reason in your final message).
- `python -m arestemis.main` starts locally with a temp DB and answers `GET /api/arestemis/health`; an authed route
  answers 401 without a token.
- Committed on `app-api`. Final message as in COMMON.md, including the deploy steps and the live-test results.
