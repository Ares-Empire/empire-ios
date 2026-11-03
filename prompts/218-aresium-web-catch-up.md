# 218: The Aresium website catches up with the iPhone app

Status: running (started 2026-11-03)
Branch: `codex/218-web-catch-up` (repo `aresium`) · Worktree: `~/aresium-218-web-catch-up` · Model: `gpt-6.1-sol`,
effort `high`

## Goal

Since 2026-10-27 the iPhone app gained many features that aresium.de does not have: neither the desktop layout
(`web/public/app/app.jsx`) nor the phone layout of the website (`mobile.jsx`), nor the public demo at aresium.de/demo.
After this brief the website does the same things, so the owner can use either, and the demo shows what the app does.

## Read first

- `aresium/AGENTS.md` (your rules: stay in the worktree, no real data, the engine stays pure) and this brief.
- `~/ares-empire/EMPIRE.md`: the design language section, and every `· aresium` changelog line from 2026-10-27 to
  2026-11-02. Those lines are the feature list in plain words.
- `~/ares-empire/docs/LANGUAGES.md` (English and German), `~/ares-empire/docs/ARESIUM-FOR-OTHERS.md`.
- The website: `web/public/app/` (`app.jsx`, `mobile.jsx`, `panels.jsx`, `chart.jsx`, `data.js` including the
  demo's made-up fetch), `src/web/server.ts` (the API), `docs/API-DATA.md`, `docs/DEVELOPMENT.md`,
  `scripts/build-sample.ts`.
- The app, **read only**, for what each feature does, how it is laid out and what it says: `~/empire-ios/Aresium/`
  (`Screens/`, `Model/FixedCosts.swift`, `Model/FixedCostLedger.swift`, `Model/AresiumEngine.swift`) and the
  Aresium sections of `~/empire-ios/CLAUDE.md`. Each feature has its brief in `~/empire-ios/prompts/` (grep for it;
  fixed costs are 208, 209, 215, 216, 217; money paid back 201–206; selecting by sliding 200). A brief's rules are the
  spec for that feature.

## Build

0. **Gap list first.** Write `docs/WEB-PARITY.md`: every app feature from the changelog lines above, and whether the
   website has it (yes / partly / no / not for the website, with the reason). Then build the missing ones **in this
   order**, each one finished (engine and API, desktop, phone layout, demo, both languages, tests) before the next:
1. **Monthly average and fixed costs:** the average of the finished months and the fixed part under the overview's
   total; the fixed costs page (rent, subscriptions, insurance; how often, the steady day, next due; Ended; marking an
   entry as not fixed).
2. **Money paid back:** linking a payment in to an expense on either payment's page, with suggestions (same amount,
   half, a third, within days) and a search; several expenses and several payments at once (the oldest expense first,
   each paid back in full before the next), with the summary before linking; only one's own share counts as spent.
3. **Finding things:** search (a name, one's own or the bank's, best match first, opens all its payments), the day
   page (a day of the graph: that day's spending and income), a name's page (all its payments added up, its months),
   renaming a payment to a remembered name (new imports get the name too).
4. **Changing many at once:** selecting payments in a list and changing Kategorie or Name for all of them with one
   question for their shops, and undo.
5. **Sorting what is not sorted, name by name**, as the app offers after an import: the most payments first, one
   choice sorts all of a name's payments and teaches the name for the next import; skip and undo.
6. **Categories:** a new category where one is chosen, renaming and deleting categories, a category's side (money in
   and out).
7. Anything else in the gap list that fits the website, if the allowance is left.

## Settled: do not re-open

- **Calculations stay on the server.** The website shows what the server calculates (`/api/data`); copy no
  calculation into the browser. New calculations go into the shared engine (`src/engine/`), which the server runs and
  which is bundled into the iPhone app, so there is one copy. Fixed costs and the monthly average exist today only in
  Swift (`Model/FixedCosts.swift`, `FixedCostLedger.swift`): port them into the engine, with the cases of the app's
  `AresiumTests/FixedCost*Tests.swift` as engine tests giving the same results. Do not change the iPhone app; moving
  it onto the engine's copy is a later brief. Pure display work (searching and selecting among payments already
  loaded) stays in the browser, as today's filters do.
- **What the owner sets is stored on the server**: payback links, "not fixed" marks, remembered names, changes to
  many payments, categories. New API routes next to the existing ones (recategorising is the pattern), behind the
  same login. A database change comes as a Prisma migration file; Claude applies it on the server. Payment ids
  (`externalId`) never change.
- **`/api/data` only grows.** Existing fields keep their names and meaning (the app's test fixtures and the hub read
  them). Every new route and field goes into `docs/API-DATA.md`.
- **The look:** you build the screens. Use only the website's existing components, colours, fonts and spacing; the
  layout and the wording follow the app's screen for the same feature. Gold only as an accent, no slogans, no new
  decoration. Claude checks the look afterwards.
- **No touch gestures on the desktop:** sliding to select, long presses and swipes become the web's usual way (tick
  boxes, shift-click for a range, a button or a menu, a back link). The phone layout may use taps and tick circles
  like the app.
- **The demo shows every new feature:** extend the made-up sample (`scripts/build-sample.ts`, `npm run sample`) with
  made-up rent, two subscriptions (one ended), an insurance, a friend paying back part of a dinner, and a few unsorted
  names, so each new screen has something to show. The demo saves nothing: new changes ask the visitor to log in there,
  as today's do.
- **English and German** for every new word, as the website does now.
- **Not for the website:** reading receipt photos, the Face ID lock, the share sheet, widgets.

## Out of scope

- `~/empire-ios` and every other repo: read only.
- The server itself, deploying, running migrations, the real database.
- Reading bank files and the sorting rules.

## Done when

- `npm run typecheck`, `npm test` and `npm run engine` pass, with new tests for the engine's fixed costs (the app's
  cases, same results), every new API route (login required; the demo changes nothing) and any new engine logic.
- The website runs locally on the demo sample (`docs/DEVELOPMENT.md`) and every new screen works at desktop and
  phone width, in English and German. If a headless browser is already installed, save screenshots of each new screen
  at both widths to `build/218-<screen>-<desktop|phone>.png`; install none, and say so if there is none.
- `docs/WEB-PARITY.md` lists every app feature as done or not for the website (with why).

## Final message

As in `AGENTS.md`: files changed, the exact check results (test counts), what Claude must run (migrations, copying
the new sample into the app's fixtures `AresiumTests/server-dashboard.sample.json`, deploying), what is missing
or doubtful, and which numbered steps are done.
