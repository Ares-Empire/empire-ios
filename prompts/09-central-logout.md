# 09: Central logout (every app, widget and push device follows a logout)

Status: running (2026-10-26)
Branch: `codex/09-central-logout` · Worktree: `../empire-ios-09-central-logout` · Model: `gpt-6.1-sol`, effort `xhigh`

## Goal

Logging out in one Empire app must end everything the login showed on this iPhone, also in the apps that are not
running: their saved data, their widgets and their push notifications. Today "log out everywhere" relies on every other
app running again (council 2026-10-25, `docs/reviews/2026-10-25-empire-app.md` → General case (b); `CLAUDE.md` → Open
12). This must hold before anyone but Patrik gets an app.

What is wrong today, concretely:
- **Widgets:** the Aresium widget shows its snapshot (`Aresium/AresiumShared/WidgetSnapshotStore.swift`) until its next
  timeline, which is the end of the month; another app cannot reload it (`WidgetCenter` only reloads the calling app's
  own widgets). The Aresus widget shows its saved status whenever the Keychain is locked
  (`Aresus/AresusShared/WidgetStatusLoader.swift`), without knowing whether that status belongs to the current login.
- **Push:** each app removes only its own device on logout (`Shared/Push/PushCenter.swift`, and only while it still
  holds `registered` in memory). Log out in the Empire app and Arestemis's and Aresus's devices stay registered to the
  account, so their notifications keep arriving on a logged-out phone.
- **Apps:** each app follows a logout only in `followSharedLogin()`, which needs the Keychain (readable only while the
  phone is unlocked) and runs in a `Task` after the app is already back on screen.

## Read first

- `AGENTS.md`, `CLAUDE.md` (One login for all, Light mode, Languages, Open 12).
- `Shared/Auth/EmpireSession.swift` and `Shared/Auth/TokenKeychain.swift` (the whole files: generations, `logOut`,
  `endSession`, `followSharedLogin`, `FirstLaunchTokenReset`), `Shared/EmpireShared.swift`.
- `Shared/Push/PushCenter.swift`, `Shared/Push/PushAPI.swift`, `~/ares-empire/docs/PUSH.md` → Public API (the
  `DELETE /api/push/devices` contract: needs a valid login, not the app's service; removes a device only while it is
  registered to that account).
- Saved data per app: Aresium `AresiumShared/WidgetSnapshot*.swift`, `AresiumWidget/WidgetProviders.swift`,
  `Aresium/Model/DashboardStore.swift`, `Model/WidgetSnapshotPublisher.swift`; Aresus `AresusShared/WidgetStatus*.swift`,
  `WidgetStatusLoader.swift`; Arestoteles `Model/VaultStore.swift` (it already checks the saved account at launch:
  `savedAccount`) and `Model/Persistence.swift`, `Model/Spotlight.swift`.
- Each app's `ContentView.swift` foreground handler (`followSharedLogin` call) and `Shared/AppRoot.swift`.
- Existing tests about logout: `Aresium/AresiumTests/AresiumTests.swift`, `WidgetTests.swift`, the push tests, and
  `scripts/check-shared-login.sh` (how a cross-app check runs).

## Build

1. **The login marker** (new `Shared/Auth/LoginMarker.swift`): one value in the shared App Group defaults
   (`group.de.ares-empire.shared`, key `empire.login.account`): the account id of the login saved for all apps, absent
   when there is none. App Group defaults are readable while the phone is locked (after the first unlock), unlike the
   Keychain item, so widgets and background launches can read it.
   - `EmpireSession` writes it whenever it saves a login (`accept`) and removes it whenever it deletes the saved login
     (`logOut` on the path that calls `storage.delete()`, and `FirstLaunchTokenReset`). Ending the session in this app
     only (`endSession` without deleting) leaves it. It uses the defaults the session is given (today's
     `installDefaults`; rename the parameter to `sharedDefaults` if it now does both jobs, and update the call sites);
     nil (sample mode, tests) writes nothing.
   - A small reader for the other places: `LoginMarker.account(in:)` → `String?`.
2. **Saved data checks the marker where it is shown** (the council's rule: check at the point of use):
   - **Aresium widget:** `WidgetSnapshot` gets `account: String?` (the app fills it from the session's account id when
     it publishes). The widget providers show a snapshot only while the marker's account equals the snapshot's; on a
     mismatch or no marker they delete the snapshot and show the existing logged-out/empty state. The timeline's next
     refresh becomes at most one hour away (today: end of month), so a logout in another app reaches the widget within
     the hour. The widget extension gets the `group.de.ares-empire.shared` App Group in
     `Aresium/AresiumWidget.entitlements` (you may edit that file for this).
   - **Aresus widget:** `WidgetStatus` gets `account: String?` (filled by whoever saves it: the app from its session, the
     widget from the token it fetched with, via `EmpireToken.accountID`). When the token cannot be read (locked), show the
     saved status only while it matches the marker; otherwise delete it and show `.loggedOut`. When the token is read and
     belongs to another account than the saved status, the saved status is not shown (fetch, or `.notLoaded`).
   - **Arestoteles:** `savedAccount` reads the marker instead of the Keychain, so the launch check also works on a
     background launch. Nothing else changes there.
   - **Every app, on coming to the foreground:** before the existing `followSharedLogin()` task, a synchronous check:
     if the marker's account is not the session's `accountID` (and the session has a token), end the session in this
     app at once (the same path a followed logout takes today), so the old data is gone in the first frame. Put this
     in ONE shared place (a method on `EmpireSession`, e.g. `followMarker()`, called from one shared modifier or from
     `AppRoot` if the session can reach it there); the five `ContentView`s should only call it, not copy the logic.
     A different account in the marker: end this session, then `followSharedLogin()` restores the new one as today.
3. **Every app's push device is removed by the app that logs out:**
   - A shared record in the App Group defaults (key `empire.push.devices`): app bundle id → APNs device token (hex).
     Each `PushCenter` adds its entry after the push service accepted its registration (204) and removes it after its
     own successful removal. Device tokens only; never an Empire token in defaults.
   - The logout handlers learn which login ended: `onLogout` hands its action the ended token (and whether the saved
     login was deleted here), e.g. `onLogout { ended in … }`. Adapt the existing callers.
   - When this app deleted the saved login because the person logged out (`logOut` with `refusedToken == nil`, which
     includes the password-change and account flows that call it), its `PushCenter` sends `DELETE /api/push/devices`
     `{app, token}` for **every** entry in the record, each with the ended Empire token (it is the same account for all
     apps), through its existing ordered queue, and removes each entry the service answered 204 for. An app that follows
     a logout made elsewhere still removes its own device as today (the service answers 204 for an unknown device).
   - A logout because a server refused the login: the token is invalid, so removal cannot work; try nothing extra.
   - Failures (offline, 5xx) are logged with `Logger` (no tokens in the log) and the entry is dropped from the record
     anyway. Do not edit other repos: describe this limit in your final message and Claude adds it to
     `~/ares-empire/docs/PUSH.md`.
   - A 401 from a removal after logout must never start another logout (the generation has moved on; keep it so and
     test it).
4. **Tests** (Swift Testing, fakes as in the existing tests; no real tokens):
   - marker: written on login and restore, removed on the person's logout and on a refused saved login, left on a
     this-app-only end and on a refused token that is no longer the saved one, nothing written with nil defaults;
   - Aresium widget: snapshot shown for the same account, deleted and not shown for another account or no marker;
     next refresh ≤ 1 h;
   - Aresus widget loader: locked + matching marker → saved; locked + other/no marker → deleted, `.loggedOut`;
     unlocked with another account's token → saved status not shown;
   - foreground check: marker of another account or none → session ended synchronously, data reset handlers ran;
   - push: record written on 204 only; person's logout removes every recorded app's device with the ended token in
     order, drops the entries; refused-login logout sends nothing; a 401 on removal does not log out again.

## Settled: do not re-open

- The marker holds the account id only, in the shared App Group defaults, never a token. It is the signal for "which
  login is current"; the Keychain item stays the login itself.
- Removing the other apps' devices from the logging-out app with the same Empire token, not a new server endpoint (the
  push service already allows it: same account, no service needed).
- Widgets refresh at most hourly to see a logout; no silent push, no background tasks for this.
- No screens and no styling: the widgets' logged-out state and the login screen stay as they look today. The privacy
  cover in the app switcher (the other half of Open 12) is Claude's and not in this brief.
- No server changes; no other repos edited.

## Out of scope

- Arestoteles's Spotlight entries when Arestoteles never runs again after a logout elsewhere (only that app can delete
  them; its launch check already does).
- Offline logout leaving devices registered (report it; Claude documents it).
- Anything in `project.pbxproj`; entitlements only `Aresium/AresiumWidget.entitlements` as above.

## API

- `DELETE https://www.ares-empire.de/api/push/devices` `{app, token}` with `Authorization: Bearer <Empire token>` →
  `204` (also when unknown), `401` token rejected (`~/ares-empire/docs/PUSH.md` → Public API; the app side is
  `Shared/Push/PushAPI.swift`). Nothing else.

## Done when

- `xcodebuild test` passes for all five projects on your own simulator (`-parallel-testing-enabled NO`, as in
  `scripts/check-shared-login.sh`), with the new tests above.
- `scripts/check-shared-login.sh <your simulator udid>` still passes.
- Every app still builds; the widget extensions build.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines per project, what is missing or doubtful
(especially anything about the marker's timing on launch, and the push limit for PUSH.md).
