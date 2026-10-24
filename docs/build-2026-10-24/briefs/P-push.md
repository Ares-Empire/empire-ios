# P: Empire push service + Shared/Push (iPhone side)

Read `COMMON.md` (same folder) first. Worktrees: `~/wt/ares-empire-push` (branch `push`) and `~/wt/empire-ios-push`
(branch `push`). Simulator for you: clone "iPhone 17" (iOS 27.0) as `agent-push`.

## Goal

One push service for every Empire app (contract: `~/wt/ares-empire-push/docs/PUSH.md`, read it fully). Province services
(Arestemis, Aresus) call it on localhost; apps register their device tokens with it. Until Apple approves the paid
developer account there is no APNs key, so **dry-run** must be a first-class mode. Plus the Swift `PushCenter` that
every app uses.

## Read first

- `~/wt/ares-empire-push/docs/PUSH.md` (the contract), `docs/ACCOUNTS.md` → "How a service checks a login"
- `~/wt/ares-empire-push/webauth/server.py` (the hub's stdlib server: `pb_call`, `token_access`, caching, statuses) and
  `webauth/test_server.py` (how it fakes PocketBase): follow the same style
- `~/wt/empire-ios-push/README.md`, `CLAUDE.md` → Setup state; `Shared/Auth/EmpireSession.swift`, `Shared/API/HTTP.swift`,
  `Empire/EmpireTests/` (test style, fakes)

## Build — server (`~/wt/ares-empire-push/push/`)

- Python, standard library HTTP servers like the hub (`ThreadingHTTPServer`), plus `httpx[http2]` (APNs needs HTTP/2)
  and `cryptography` (ES256 provider token). `push/requirements.txt` pins them.
- Two listeners in one process: **public** `127.0.0.1:8095` (Caddy routes `/api/push/*` there): `POST/DELETE
  /api/push/devices`; **internal** `127.0.0.1:8096`: `POST /send`, `GET /health`. Ports, auth URL, data path, APNs settings
  from env (`push/.env.example`): `EMPIRE_AUTH_URL` (default `http://127.0.0.1:8090`), `PUSH_DB`
  (default `/var/lib/empire-push/push.db`), `APNS_KEY_FILE`, `APNS_KEY_ID`, `APNS_TEAM_ID`. Missing key settings → dry run.
- Token check: PocketBase `auth-refresh`, 60 s cache per token (store a hash, not the token), the app→service table from
  PUSH.md, statuses 400/401/403/503 as the contract says.
- SQLite: `devices(app, token, user, environment, created, updated)` unique `(app, token)`; `outbox(id, at, app, user_or_all,
  title, body, url, result)` keeping the last 200 (dry run and real sends both logged, without device tokens).
- APNs client: JWT (ES256, `kid`, `iss` = team id, `iat`) cached ~50 min; `POST https://api.push.apple.com/3/device/<token>`
  (sandbox host for `environment = sandbox`), headers `apns-topic` (= app bundle id), `apns-push-type: alert`,
  `apns-priority` (10, or 5 for passive), `apns-collapse-id`, `apns-expiration` (now + 1 day). Payload `aps.alert
  {title, subtitle, body}`, `aps.sound`, `aps.thread-id`, `aps.category`, `aps.interruption-level`, `aps.mutable-content`
  not needed; custom key `url`. Delete the device on 410, or 400 with `BadDeviceToken` / `DeviceTokenNotForTopic`.
- Daily clean-up of devices not updated for 60 days (a timer thread is fine).
- Never log full tokens (device or Empire): first 6 chars + "…".
- Tests (`push/test_push.py`, `python3 -m unittest`): fake PocketBase and a fake APNs transport; register / re-register
  (account switch moves the token) / delete; 401/403/400/503; `/send` to user and to all; dry run fills the outbox;
  stale-token deletion; JWT is valid ES256 (verify with `cryptography` against a generated test key); the internal listener
  is never reachable on the public port (route table test).
- Deploy files: `deploy/empire-push.service` (systemd, a dedicated system user `empire-push`, `ProtectSystem=strict`,
  `ReadWritePaths=/var/lib/empire-push`, `NoNewPrivileges`), `deploy/install-push.sh` (venv at `/opt/empire-push/venv`,
  data dir, user, unit, idempotent), and the exact Caddy lines for the lead (a `handle /api/push/*` with
  `reverse_proxy 127.0.0.1:8095` inside the `ares-empire.de, www.ares-empire.de` site, **before** the hub's catch-all).
  Add a short section to `docs/PUSH.md` → "Operating" (install, logs, adding the key) and a line in `README.md`.

## Build — iPhone (`~/wt/empire-ios-push/Shared/Push/`)

- `PushCenter` (`@MainActor @Observable`, one per app), configured once at launch with the app's bundle id, the
  `EmpireSession`, and the app's notification categories (`[UNNotificationCategory]`).
  - When the session is signed in (and again at every launch / foreground while signed in): ask permission once
    (`.alert, .sound, .badge, .timeSensitive`) if not determined, then `registerForRemoteNotifications()`; when the device
    token arrives, `POST https://www.ares-empire.de/api/push/devices` with the Bearer token, `environment` = `sandbox` in
    DEBUG, `production` otherwise. Remember (in memory) the Empire token used.
  - On log out (`session.onLogout`) and on `access = .denied`: `DELETE` the device with the remembered token
    (best effort; errors ignored). The session clears its token before logout handlers run, which is why you keep it.
  - A 401 from the push API calls the session's normal failure path (`handleAuthFailure`); 403 just stops trying.
  - `openedURL: URL?` set when the user taps a notification (from the payload's `url`) or chooses an action whose
    identifier the app maps to a URL; the app observes it and routes. Also expose `lastActionIdentifier` with the URL so an
    app can treat "Open listing" differently.
  - Foreground presentation: show banners while the app is open (`willPresent` → `.banner, .sound, .list`).
- `PushAppDelegate` (an `UIApplicationDelegate` + `UNUserNotificationCenterDelegate`) that apps adopt with
  `@UIApplicationDelegateAdaptor`; it forwards the device token / failure / responses to `PushCenter.shared`… or better
  without a singleton if you find a clean way; your call, explain it.
- Testable without APNs: the HTTP part goes through `HTTPTransport`; tests in `Empire/EmpireTests/PushCenterTests.swift`
  (Shared is compiled into the Empire app, so its tests live there) cover register, re-register on account switch,
  unregister on logout/deny, 401/403 handling, URL extraction from a payload.
- Do **not** wire it into the Empire or Aresium app yet and do not edit any `project.pbxproj` or entitlements (the lead
  adds the push capability per app). Build the Empire scheme and run its tests to prove it compiles and passes.
- Document in `README.md` (Layout → Shared) in one or two lines, and add how to test with
  `xcrun simctl push <udid> <bundle id> <file>.apns` (a sample payload file under `Shared/Push/`).

## Done when

- `cd ~/wt/ares-empire-push && python3 -m unittest push/test_push.py` passes; the hub's own tests still pass
  (`python3 -m unittest webauth/test_server.py`).
- `xcodebuild test -project Empire/Empire.xcodeproj -scheme Empire -destination 'platform=iOS Simulator,name=agent-push'
  -derivedDataPath build/DerivedData` passes in `~/wt/empire-ios-push`.
- Both branches committed. Final message as in COMMON.md, with the deploy steps.
