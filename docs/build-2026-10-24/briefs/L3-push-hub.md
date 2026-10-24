# L3: push service and hub API in English and German

Read `L-COMMON.md` (same folder) first; it holds the language contract, the German style and the test rules.
Worktree: `~/wt/ares-empire-lang` (branch `languages`, already at `main`). Read `EMPIRE.md` → "How we build apps",
`docs/LANGUAGES.md`, `docs/PUSH.md`, `docs/API-EMPIRE.md`, then `push/*.py` (tests `push/test_push.py`) and
`webauth/server.py` (tests `webauth/test_server.py`). Both are Python; look at how their tests run today
(`push/requirements.txt`; webauth is stdlib only) and use a `.venv` in the worktree if needed.

## Build

1. **Push service, device language** (`push/`): `POST /api/push/devices` takes an optional
   `language: "en" | "de"` (anything else → `400`; missing → `en`). Store it per device (migration of the
   `devices` table, existing rows `en`); an upsert updates it, so a phone that changes its language moves over at the
   app's next launch.
2. **Push service, localized text:** `POST /send` takes an optional `localized: {"de": {"title"?, "subtitle"?,
   "body"?}}`. A device registered as `de` gets each given field instead of the top-level one; every other device
   the top-level text. Validation as strict as the rest (unknown languages or fields → `400`, the 4 KB limit per
   delivered notification). The outbox records the language each notification went out in. Dry run counts as now.
3. **`docs/PUSH.md`:** both additions marked `CONTRACT ADDITION (2026-10-24, languages)`, with an example.
4. **Hub live lines** (`webauth/server.py`): read the visitor's language from `Accept-Language` (contract in
   `L-COMMON.md`) and pass it on as `Accept-Language: de|en` when asking Aresium (`/api/pulse`) and Aresus
   (`/overview`). Cache per account **and** language. The prefix `Issue: ` is `Problem: ` in German.
5. **Hub API texts:** error bodies of `/api/empire*` and the push API that the apps show, in both languages
   (`This account has no access to Ares Empire.` → `Dieses Konto hat keinen Zugang zu Ares Empire.`;
   `Login service unavailable, try again in a minute.` → `Anmeldedienst nicht erreichbar, versuch es in einer
   Minute noch einmal.`). Not translated: province names and texts, the chronicle, ideas (content written in English;
   Patrik decides later). The login, sign-up and reset web pages stay English (the websites are not part of this yet).
6. **The website stays English:** the hub website's API calls (`web/app/empire-api.js`) send `Accept-Language: en`
   explicitly, so a German browser still gets English live lines on the English site.
7. `docs/API-EMPIRE.md`: a short "Language" note (live lines and errors follow `Accept-Language`).

## Done when

- Both test suites pass, with new tests for the device language (register, upsert, invalid, migration of an old
  table), `localized` (per-device pick, field fallback, validation, outbox), the live-line language and cache key,
  and the header parsing.
- Deploy steps for the lead: the push service needs `sudo bash deploy/install-push.sh` on the server (the hub
  deploys itself after a push to `main`); state the order (push service first, so the provinces' `localized` field is
  accepted before they send it) and how to check each on the server.
