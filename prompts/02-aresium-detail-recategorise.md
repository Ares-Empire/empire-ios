# 02: Transaction detail and recategorise

Status: draft
Branch: `codex/02-aresium-detail` · Worktree: `../empire-ios-02-aresium-detail` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Tapping a transaction opens its full record, and from there it can be moved to another category (Switch) or
also listed under more categories (Add), exactly as on the website. Afterwards every screen shows the new
numbers.

## Read first

- `AGENTS.md`, `CLAUDE.md` (always). The app as it is now: `Aresium/Aresium/` (brief 01 built it).
- `~/aresium/docs/API-DATA.md`: `pick` (the categories to offer, already in display order) and the section
  "Other routes the clients use".
- `~/aresium/src/data/queries.ts` → `getTransactionDetail`, `recategorizeTransaction`, `setTransactionTags` (the
  detail's fields and the error cases), `~/aresium/src/web/server.ts` (status codes).
- The template: `~/aresium/web/public/app/panels.jsx` → `TxnDetailModal` and `RecategorizeModal` (layout, labels,
  which rows show, Switch/Add behaviour, "Save & remove from current"), the matching `md-*`/`recat-*` CSS in
  `~/aresium/web/public/index.html`.

## Build

1. **Models:** `pick` on `Dashboard`; a `TransactionDetail` type for `GET /api/transaction/:id`.
2. **API** in a new file `API/APIClient+Transactions.swift` (extension, not edits to the existing client body):
   detail, switch category, set tags. Same Bearer header and 401 handling as `dashboard`.
3. **Detail sheet** (new file in `Screens/`): opened by tapping a row in the category-in-a-month screen. Head
   (place, signed amount, date), category chip with "via …" and a Change button (only if `pick` offers
   something), "Also in" chips, account, the detail rows the website shows (only non-empty ones), and the
   original record collapsed.
4. **Recategorise sheet** on top: Switch (one target) and Add (several, pre-selected with the current tags;
   Save, and "Save & remove from current"). Choices: `pick.income` if the amount > 0, else `pick.spend`; show
   them in that order with each category's icon and colour. While saving, the controls are disabled; on
   failure an error stays visible. On success: show the returned detail, then reload the dashboard so every
   screen updates.
5. **Sample mode** (`-sampleData`): the detail comes from one bundled made-up detail (any transaction id shows
   it, with that row's place, amount and date); Switch/Add show "Not available with sample data".
6. **Tests:** detail decoding; the three requests (method, path with an id that needs percent-encoding, body,
   Bearer); choices by sign come from `pick` in order; a successful change triggers a reload; a failed one
   keeps the sheet open with an error. Use the fakes in `AresiumTests.swift` and the server fixture in
   `AresiumTests/server-dashboard.sample.json` (`pick` is in it).

## Settled: do not re-open

- The app never decides which categories are offered or their order: it shows `pick` as sent.
- After any change, reload `/api/data`; never patch numbers locally.
- Sheets (`.sheet`), native controls; the look follows the website's dark/light tokens already in `Theme.swift`.

## Out of scope

- Import and the start screen's controls (brief 03 runs in parallel and owns those files: anything about
  import, `ContentView`'s URL handling, the start screen's control row). Keep edits to existing files to the
  minimum: the row tap in the transactions screen, the `pick` property, store reload hook if needed.
- The red mode, widgets.

## Done when

- `xcodebuild test` passes on your own simulator, with the tests above, and the existing 21 still pass.
- Screenshots in sample mode: `build/02-detail.png`, `build/02-recategorise-switch.png`,
  `build/02-recategorise-add.png` (say how you navigated there).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots, what is missing or
doubtful.
