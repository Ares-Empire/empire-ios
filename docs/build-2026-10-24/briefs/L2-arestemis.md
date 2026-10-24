# L2: Arestemis server in English and German

Read `L-COMMON.md` (same folder) first; it holds the language contract, the German style and the test rules.
Worktree: `~/wt/Arestemis-lang` (branch `languages`). Venv: `/opt/homebrew/bin/python3 -m venv .venv &&
.venv/bin/pip install -e '.[dev]'`; tests: `.venv/bin/python -m pytest -q`. Never call a real AI or a real portal
(tests use the fakes). Read `CLAUDE.md`, `docs/API.md` (version 2), `docs/ARCHITECTURE.md`, then `notify.py`,
`health.py`, `verify.py`, `scheduler.py`, `describe.py`, `llm/provider.py`, `db.py`, `models.py`, `api.py`.

## Build

1. **`texts.py`:** every sentence and word the server writes, English and German.
2. **Fixed texts follow the request language:** source notes in `health.py` (`Blocked since 14:02 (HTTP 403)` →
   `Gesperrt seit 14:02 (HTTP 403)`, `Failing since …` → `Fehler seit …`, `Only München` → `Nur München`), the warning
   `Not checked by AI` → `Nicht von der KI geprüft`, `notify.summary()` (the plain line for unchecked matches: German
   `980 € warm, 42 m², Schwabing, ab 1. Dez.`), and error bodies the app shows (401/403/404/409/503 and the 400s for
   a search the app sends: `{"error", "field"}`, `field` unchanged).
   **Stored warnings:** store the warning as its key (or both texts) so an old English one still reads in English and
   a new one in the request's language.
3. **The AI check writes both languages in the same call:** the schema gets `reason_de` and `warnings_de` next to
   `reason` and `warnings` (same facts, natural German, German number style, at most 120 characters each). Store both
   (next `MIGRATIONS` entry in `db.py`; old rows: English for both). `Match.reason`, `Match.warnings` and
   `Rejected.reason` follow the request language. The prompt change stays small; the rules in the prompt are not
   loosened.
4. **"Describe it"** (`POST /search/parse`): `unclear` is written in the request language (tell the AI which one);
   `extra` stays in the text's language as now.
5. **Pushes** (`notify.py`): English as now (`€980 · 42 m² · Schwabing`, `WG-Gesucht · Flat`, the English reason) plus
   `localized: {"de": {"title": "980 € · 42 m² · Schwabing", "subtitle": "WG-Gesucht · Wohnung", "body": <reason_de>}}`
   (only fields that differ). Kind labels: flat `Flat` / `Wohnung`, wg `WG room` / `WG-Zimmer`. The push service
   accepts `localized` from the parallel brief L3 (contract: `localized` maps a language to any of `title`,
   `subtitle`, `body`; a device registered as `de` gets those, every other device the top-level ones). The Telegram
   text stays English (Telegram retires once pushes reach the phone).
6. **Not translated:** listing titles and texts, places and districts, `extra`, the AI application text (it is written
   to the landlord, in German as now), portal names.
7. `docs/API.md`: a "Language" section naming the fields that follow `Accept-Language`; `CLAUDE.md`/`README.md`
   where they become wrong.

## Done when

- All tests pass, with new ones for both languages on every field above, the migration on a file with old rows, the
  AI schema (the fake returns both), the push payload and the header parsing.
- Deploy steps: Arestemis deploys itself after a push to `main` (Aresync hook) and runs its migration on start;
  say what the lead should check on the live server afterwards (and recommend a database backup command first).
