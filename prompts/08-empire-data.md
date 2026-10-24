# 08: Empire app data layer (no screens)

Status: draft
Branch: `codex/08-empire-data` · Worktree: `../empire-ios-08-empire-data` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Everything the Empire iPhone app needs below its screens: loading the per-account hub data, the ring actions,
approvals, province marks, and opening a province. Claude builds the screens in parallel (the approved phone hub,
`ares-empire/web/app/mobile.jsx`); **do not build or style any screen** (CLAUDE.md → Workflow: the look is Claude's).

## Read first

- `AGENTS.md`, `CLAUDE.md` (Setup state: two projects, `Shared/`, one login for all).
- `~/ares-empire/docs/API-EMPIRE.md` (the contract: `GET /api/empire`, the ring and approvals routes, statuses),
  `~/ares-empire/docs/EMPIRE-APP.md` (what the app does).
- `Empire/Empire/Model/EmpireData.swift` (the data types, written by Claude: use them, don't change field names),
  `Empire/Empire/Preview Content/empire.admin.json` / `empire.user.json` (the hub's own samples).
- `Shared/` (EmpireSession with `app: .empire`, `checkResponse`, `HTTPTransport`), and how Aresium does the same jobs
  (`Aresium/Aresium/API/APIClient.swift`, `Aresium/Aresium/Model/DashboardStore.swift`: generations, foreground
  refresh, sample mode, `onAppDataReset`).

## Build (files: `Empire/Empire/API/`, `Empire/Empire/Model/` except `EmpireData.swift`, `Empire/EmpireTests/`)

1. **`EmpireAPI`** (base `https://www.ares-empire.de`, `Authorization: Bearer <token>`, statuses via `checkResponse`):
   `empire()` → `EmpireData`; `ring(add:)` / `ring(remove:)` → `EmpireData`; `approvals()` → `[PendingAccount]`;
   `decide(id:approve:)`. Injectable transport, as in Aresium.
2. **`EmpireStore`** (`@Observable`, MainActor): the data, loading and error state; `reload()`; foreground refresh when
   the data is older than 5 minutes (and `session.restore()` first after 12 h, as Aresium); ring add/remove (busy
   state, error kept until the next action, the returned data replaces the old); approvals list and decide (refresh
   the list and `pending` afterwards). On `session.onAppDataReset` forget everything. 401 → `session` logs out; 403 →
   `session.handleAuthFailure` (this app closes, the shared login stays); 503 → keep data, show the error.
   **Sample mode** (launch argument `-sampleData`, plus `-sampleUser` for the user sample; DEBUG only, as in Aresium):
   data from the bundled samples, ring and approvals changed in memory, nothing sent.
3. **`ProvinceMarks`**: loads `https://www.ares-empire.de/<logo>` with the Bearer token (the hub allows this for
   `/brand/` images only), in-memory cache, decoded with `UIImage(data:)` (WebP works on iOS), `nil` on failure. In
   sample mode no network: return nil (the screens show the monogram). Expose a small async API the screens can use;
   no SwiftUI view.
4. **`ProvinceOpener`**: `open(_ province:)`: if `province.app` is set and `UIApplication.shared.canOpenURL` says the
   app is installed, open the app; otherwise open `province.url` in the browser. Add `aresium` to
   `LSApplicationQueriesSchemes` in `Empire/Empire/Info.plist` (you may edit that file for this key only). Injectable
   for tests (a protocol around `canOpenURL`/`open`).
5. **Tests** (`Empire/EmpireTests/`, Swift Testing, fakes like Aresium's): decoding both samples; every request (method,
   path, body, Bearer); store flows (load, foreground rule, ring add/remove incl. error, approvals approve/decline,
   401 → logout, 403 → denied in this app with the shared login kept, 503 → data kept, app-data reset clears);
   marks send the Bearer and cache; the opener picks the app when installed and the website otherwise. Keep the
   existing `SharedLoginProbe` test as it is.

## Settled: do not re-open

- No screens, no styling, no `ContentView` changes (Claude's, in parallel). If you need a call site for manual
  checking, use the tests.
- Data types and field names from `EmpireData.swift`; all logic for who sees what stays on the server.
- No third-party packages; no project-file edits.

## Done when

- `xcodebuild test -project Empire/Empire.xcodeproj -scheme Empire` passes on your own simulator (parallel testing
  off, see `scripts/check-shared-login.sh`), and the Aresium project still builds.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, anything doubtful.
