# 15: Aresium phone mode: other people's data on their iPhone

Status: draft (starts after 12 and 14 are merged: it needs `buildDashboardSource`, the transfer rules, `/api/mode` and
`readBankFile`)
Repo: empire-ios · Worktree: `../empire-ios-15-phone-mode` (branch `claude/15-phone-mode`) · Built by: a Claude agent

## Goal

Everyone but Patrik uses Aresium in **phone mode**: their bank files are read, stored, sorted and added up on their
iPhone by the shared engine (the server's own TypeScript, bundled, run in JavaScriptCore); nothing about their money
reaches a server. Patrik keeps **server mode**. The existing screens stay as they are and show the same `Dashboard`
in both modes. This brief builds the whole data side of phone mode with plain structural screens where new screens are
needed; Claude does the look of those screens afterwards.

## Read first

- `AGENTS.md` and `CLAUDE.md` (rules, languages, light mode, the shared login, central logout, the app switcher cover).
- The plan: `~/ares-empire/docs/ARESIUM-FOR-OTHERS.md` (parts 1–5, Decisions).
- The app: `Aresium/Aresium/` (`ContentView`, `Model/DashboardStore`, `Model/TransactionDetailStore`,
  `Model/ImportStore`, `Model/ImportFileReader`, `API/*`, `Screens/RecategoriseSheet`, `Screens/TransactionDetailSheet`,
  `Model/WidgetSnapshotPublisher`), `Aresium/AresiumShared/Dashboard.swift`, `Aresium/AresiumTests/` (incl.
  `EngineTests.swift` and `Engine/`), `Shared/Auth/EmpireSession.swift`, `Shared/Auth/AccountForms.swift`
  (`LeaveAppFlow`, the delete flow), `Shared/Design/SettingsScreen.swift` (`SettingsApp`).
- The engine: `~/aresium/src/engine/index.ts` and what it exports (`buildDashboard`, `buildDashboardSource`,
  `readBankFile`, `sortPayments`, `learn`, `merchantKey`, `DEFAULT_CATEGORIES`, `BUILT_IN_CATEGORIES`,
  `CATEGORY_LOOK`, `categoryLook`), `~/aresium/docs/API-DATA.md` (`GET /api/mode`).

## Build

1. **The engine in the app.** `scripts/aresium-engine.sh` runs `npm run engine` in `~/aresium` and copies
   `dist/aresium-engine.js` to `Aresium/Aresium/Engine/aresium-engine.js`, writing the aresium commit to
   `Engine/engine-version.txt`. `Model/AresiumEngine.swift`: an actor owning one `JSContext` with the bundle loaded,
   typed calls with `Codable` in and out (JSON across the bridge), JS exceptions as Swift errors. `EngineTests` uses the
   app's bundled copy (delete the test-resource copy of the bundle; keep the fixtures).
2. **One interface, two backends.** `AresiumBackend` (protocol): the dashboard, a transaction's detail, Switch, Add,
   and importing files. `ServerBackend` is today's `APIClient` code moved behind it, behaviour unchanged (every
   existing test stays green). `PhoneBackend` implements it with the engine and the phone's storage. `DashboardStore`,
   `TransactionDetailStore` and `ImportStore` use the backend, not `APIClient`. Phone-only work (categories, learning,
   layouts, export, deleting) is a second type, `PhoneLedger`, used by `PhoneBackend` and the new screens.
3. **Which mode.** After a login the app asks `GET /api/mode` once and remembers the answer per account id (app
   defaults). Unknown and offline: a calm line ("Aresium needs a connection the first time") with Try again; known
   and offline: the remembered mode (phone mode then works fully offline).
4. **Storage (`PhoneLedger`).** SwiftData, one store per Ares account id in Application Support (`Aresium/<account
   id>/`), file protection complete. Models: account (id, name, IBAN if the file has one), payment (id, account, source,
   `externalId`, booking and value date, amount, currency, text, counterparty, balance, the bank's original row, category
   id, category source: structural / learned / starter / manual / none, extra categories), chosen category (default id
   or a custom id, custom name, order), learned rule (merchant key → category id), saved CSV layout. A payment is unique
   by (account, source, `externalId`).
5. **Logout keeps the data.** Logout closes the store (nothing shown, nothing deleted); the same account logging in
   opens it again; another account gets its own store. The central logout's checks (`followMarker`, the marker) end
   the session as now but never delete the phone store. The data is deleted only by: Leave Aresium, Delete Ares
   account (each after the server said yes), and a "Delete Aresium data on this iPhone" row in Aresium's settings
   section. Add `SettingsApp.localData: (@MainActor () async throws -> Void)?`, run by the leave and delete flows after
   the server step; Aresium passes its delete. The widget snapshot goes with the data.
6. **Import in phone mode.** File bytes → `readBankFile` (with the account's saved layouts) → when the engine needs a
   layout: a structural confirmation sheet (the guessed columns and the first rows; the person can change a column's
   meaning; Confirm saves the layout and reads the file) → new payments only (unique key above) → sorted with
   `sortPayments` (structural, learned, starter; only the person's chosen categories) → stored → dashboard rebuilt.
   The result line says how many were new, already there, sorted, and waiting for a category. Files shared into the
   app keep working as today.
7. **Categories.** Nothing is preselected (Patrik, 2026-10-26). Before the first import, and from a "Categories" row in
   Aresium's settings section: a structural picker with the default list by group (names in the app's language,
   from the engine), a toggle each, and a field to add one's own names; the two built-ins are always there and not
   listed. Unticking a category with payments asks where they go (another category or Not sorted). Icons and colours
   come from the engine's `CATEGORY_LOOK` (custom: `categoryLook`); `CategorySymbol` already maps the icons.
8. **Corrections teach.** Switch and Add work in phone mode on the store. A Switch learns the merchant (`learn`,
   merchant key from the engine) and, when other payments of that merchant were not set by hand, asks once: "Also
   the N other payments from <shop>?" (a confirmation dialog for now) and moves them if yes.
9. **The dashboard.** Built by the engine from the store (`buildDashboardSource` with today's date, then
   `buildDashboard`), the same `Dashboard` type the server sends; rebuilt after every change; the Switch/Add choices
   (`pick`) are the chosen categories. A transaction's detail comes from the stored payment (with the original row).
   The widget snapshot is published as in server mode.
10. **Export and restore.** Settings → Export: one JSON file (schema version 1: accounts, payments, chosen categories,
    learned rules, layouts) through the share sheet, named `Aresium-<date>.json`. Restore from an export: only into an
    empty store, validated first, all or nothing. Tests round-trip it.
11. **Sample.** DEBUG `-samplePhone`: phone mode without a login or network, its store filled from made-up files (the
    engine fixtures), for screenshots and UI checks; `-samplePhoneEmpty` for the first run.

## Settled: do not re-open

- One `Dashboard` for both modes; existing screens unchanged. Server mode behaves exactly as today.
- No payment data leaves the phone in phone mode; no AI. The engine bundle is copied, never edited by hand.
- New screens are structure only (plain SwiftUI from the shared pieces, no new styling): the category picker, the
  layout confirmation, the "also N others" question, the first-run empty state, export/restore/delete rows. Claude
  designs them after.
- UI text in English in the code; list the new strings in your final message (Claude writes the German).

## Out of scope

Receipts; automatic sorting with AI; bank access (FinTS); the look of new screens; the hub and server.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium` passes on your own simulator
  (`-parallel-testing-enabled NO`), with tests for: both backends, the mode, storage and duplicates, the data lifecycle
  (logout keeps, leave/delete removes), import with and without a layout, sorting and learning, export round trip,
  and the engine host.
- All five apps build (Shared changes). `-samplePhone` shows a full dashboard; screenshots of each new structural
  screen in `build/15-*.png`.
- Final message: files, test counts, new strings, anything doubtful (especially SwiftData migration and the bridge).
