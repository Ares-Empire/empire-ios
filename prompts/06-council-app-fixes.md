# 06: App fixes from the pre-TestFlight council

Status: draft
Branch: `codex/06-council-app` · Worktree: `../empire-ios-06-council-app` · Model: `gpt-6.1-sol`, effort `high`

## Goal

The app behaves well in real use on a phone, not only on the simulator: it refreshes when reopened, survives
outages, interrupted imports and revoked access, cleans up bank exports, and keeps debug hooks out of Release.
Findings A1–A11 in `docs/reviews/2026-10-23-pre-testflight.md` (read their rows; the seats' reasoning is there).

## Read first

- `AGENTS.md`, `CLAUDE.md`, `docs/reviews/2026-10-23-pre-testflight.md`.
- `~/aresium/docs/API-DATA.md` → **Auth** (the new 401 / 403 / 503 table; the server implements it in parallel,
  so build against the table) and "Other routes" (`/api/import` now answers 413 with `{error}` when too large).
- The code the findings point at: `ContentView.swift`, `Auth/EmpireSession.swift`, `API/*`, `Model/DashboardStore.swift`,
  `Model/TransactionDetailStore.swift`, `Model/ImportStore.swift`, `Model/ImportFileReader.swift`,
  `Model/WidgetSnapshotPublisher.swift`, `AresiumShared/WidgetSnapshotStore.swift`, `AresiumShared/WidgetViews.swift`,
  `AresiumWidget/WidgetProviders.swift`, the tests.

## Build

1. **Auth statuses (with A6).** 401 → log out (as now). 403 → log out, delete the widget snapshot, show the server's
   or a clear "no access to Aresium" message on the login screen (also when `restore()` gets 403 or a record without
   `aresium`). 503 → keep token, data and widget; show "Login service unavailable, try again" with Retry. Applies to
   every API call and to `restore()`.
2. **A1 Foreground refresh.** On `scenePhase == .active`: reload the dashboard if the last successful load is older
   than 5 minutes; run `restore()` first if the token was last renewed more than 12 hours ago. One refresh at a time;
   visible data stays while loading.
3. **A2 Generations.** Separate "the session changed" (logout/login: drop everything in flight) from "a newer
   dashboard fetch exists" (only the older fetch is dropped). A detail load or a save in the same session always
   completes and, for a save, triggers the reload. Test: import finishing while a save is in flight.
4. **A3 Import robustness.** Keep the attempted batch until it succeeds or the user discards it (Retry / Discard in
   the result banner, which stays until dismissed on failure). Clear pending files on logout. On the login screen,
   show "N file(s) waiting, imported after login" when files arrived while logged out. Show per-file results
   (name + added, or the file's `error`) instead of only a count. Wrap the upload in
   `UIApplication.beginBackgroundTask`/`endBackgroundTask` (with the expiration handler).
5. **A4 Size.** Check the encoded JSON request size against 25 MB before sending; if several files exceed it
   together, send them in several requests (one file per request when needed); a single file too large for one
   request is refused with its name. Handle a 413 `{error}` from the server.
6. **A5 Inbox cleanup.** After a shared file is read (or its batch is discarded or imported), delete it if and only if
   it lies inside the app's own container (the Inbox copy); never delete files chosen with the file picker. Also
   clear leftovers on launch.
7. **A7 Debug hooks.** All `-sample…` launch arguments and screenshot routing compile only in `DEBUG`. Sample mode
   and tests use a snapshot publisher pointing at a temporary directory, never the real App Group. Tests must not
   touch the real App Group.
8. **A8 Widgets.** `.privacySensitive()` on every amount; write the snapshot with
   `.completeFileProtectionUntilFirstUserAuthentication`; distinguish "no snapshot file" (empty state) from "could not
   read it" (keep the empty state but the timeline asks again after 30 minutes); otherwise refresh at the start of the
   next month.
9. **A9** Requests use an ephemeral `URLSession` (no disk cache). **A10** On the first launch after install (no flag
   in `UserDefaults` yet) delete any Keychain token left from an earlier install, then set the flag (UserDefaults is
   already declared in the privacy manifest). **A11** Launch screen background `#050507` (a colour set plus
   `UILaunchScreen` → `UIColorName` in `Aresium/Info.plist`: you may edit `Info.plist` for this key only), and
   `prepare()` the haptic generator when the theme transition starts.
10. **Tests** for each of the above that is logic (auth statuses incl. restore 403/503, foreground refresh rules,
    generations interleaving, batch retry/discard/logout, size splitting, Inbox deletion rules, first-launch Keychain
    wipe, widget read-failure policy). Existing tests stay green.

## Settled: do not re-open

- The status table in `API-DATA.md` is the contract; the app never logs out on 503.
- No share extension; no network in the widget; no money calculated in the app.
- Do not edit the project file. `Info.plist` only for the launch screen colour key.

## Out of scope

- What "this month" means for the widget and the PayPal currency question (wait for Patrik).
- Signing, team, TestFlight upload; Associated Domains; app lock.

## Done when

- `xcodebuild test` passes on your own simulator, the existing 67 tests too.
- A Release build compiles: `xcodebuild -project Aresium/Aresium.xcodeproj -scheme Aresium -configuration Release
  -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData-release CODE_SIGNING_ALLOWED=NO build`, and
  you confirm (e.g. `strings` on the binary) that no `-sample` argument name is in it.
- Screenshots: the 503 message (`build/06-auth-unavailable.png`), the import failure banner with Retry/Discard and a
  per-file result (`build/06-import-failed.png`), the login screen with waiting files (`build/06-login-waiting.png`).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the Release check, the screenshots, what is
missing or doubtful.
