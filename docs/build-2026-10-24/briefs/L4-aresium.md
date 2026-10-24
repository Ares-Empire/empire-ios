# L4: Aresium server texts in English and German

Read `L-COMMON.md` (same folder) first; it holds the language contract, the German style and the test rules (here in
TypeScript: one `texts.ts`, plain objects). Worktree: `~/wt/aresium-lang` (branch `languages`); `npm ci` in the
worktree, then the repo's test command (`package.json`). Read `README.md`, `docs/API-DATA.md`, `src/data/pulse.ts`,
`src/web/server.ts`, `src/web/empire-auth.ts`, and the importers' error texts (`src/` → where `results[].error` is
made).

## Build

1. **`/api/pulse`** (the hub's Aresium line) in the request language: `€1,339 spent in October` →
   `1.339 € im Oktober ausgegeben`; `Nothing imported for October yet` → `Für Oktober noch nichts importiert`.
2. **Error bodies the iPhone app shows**, in the request language: the 401/403/503 of `empire-auth.ts` (`This account
   has no access to Aresium.` → `Dieses Konto hat keinen Zugang zu Aresium.`; `Login service unavailable, try again in
   a minute.` → `Anmeldedienst nicht erreichbar, versuch es in einer Minute noch einmal.`), the import errors (409
   running, 413 size, 400 no files, and each file's `results[].error`), recategorise errors (`not found`, `unknown
   category`, …). Word them as short sentences for a person in both languages.
3. **Not translated:** `/api/data` (month `label`/`short` stay English; the app formats months itself from `year` and
   `month`), category and account names, transaction texts, the login web page, the Telegram bot.
4. **The website stays English:** its own API calls (`web/public/app/`) send `Accept-Language: en`, so a German
   browser keeps the English site.
5. `docs/API-DATA.md`: a short "Language" section (which answers follow `Accept-Language`).

## Done when

- The test suite passes, with new tests for both languages on every text above and the header parsing.
- Deploy steps for the lead (how Aresium is deployed today: read `README.md`/`deploy/`).
