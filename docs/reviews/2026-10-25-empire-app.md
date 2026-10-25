# Council 2026-10-25: Empire app before its first TestFlight build

**Subject:** `empire-ios` at 241e15c (the Empire app, `Shared/Auth`, `Shared/API`, `Shared/Push`) and the servers it
talks to, `ares-empire` at 0039ebd (hub API, account server). **Why a council:** milestone before the first TestFlight
build; login and tokens (`docs/REVIEW.md`: 3–4 seats). All seats Claude agents (Patrik, 2026-10-25: Claude agents, not
Codex), read-only, blind to each other, about 8–9 minutes each.

| Seat | Focus | Model |
|---|---|---|
| 1 | Security and privacy | Claude (subagent) |
| 2 | API boundary: does the app match what the server really sends | Claude (subagent) |
| 3 | Apple platform and TestFlight readiness; general case and goal | Claude (subagent) |

## Outcome: **Corrected**

All three seats: nothing blocks the first internal build except setting the paid team. All three found the same bug
independently (the Arestoteles card opened the website). No finding changes what the Empire app is for; two questions
about what it should become go to Patrik (13 in `CLAUDE.md` → Open).

**General case (two seats):** (a) facts copied by hand across repos with nothing checking that they agree: the list of
apps (about nine places) and the province shape vs the app's fixtures; (b) protections placed away from where the data
is used: private apps trusted a `services` list the asker fills, and "log out everywhere" relied on every other app
running again. Answer: check at the point of use, generate fixtures from the server, and a checklist for a new app
(`ares-empire/docs/IPHONE-APPS.md` → A new app touches).

## Fixed (2026-10-25)

App and shared code (`empire-ios` d257d2b, b61b770):

- **Opening a province** [1, 2, 3]: `canOpenURL` with an incomplete `LSApplicationQueriesSchemes` (no `arestoteles`),
  and a dead tap for a province with an app but no website. Now: try the app, else the website, else the province's
  page with "The … app isn't on this iPhone"; the plist key is gone, so a sixth app needs no edit here.
- **Error codes** [2]: a 403 closes the app only for `no_access` (or no code, for servers without codes); `admin_only`
  and others only refuse that request; a 503 shows the server's sentence.
- **A late 401 deletes a newer token** [1]: refusals count only for the token they were made with; the Keychain item is
  deleted only while it still holds the refused token.
- **"No access" never cleared** [2]: while the account lacks the app's service, the app asks again quietly on the
  foreground, at most once a minute.
- **Approvals** [2]: the decision answer carries the list and count; approve/decline send the services shown on the
  card; any failed decision reloads the list; "Email not confirmed yet" on unconfirmed accounts; `pending` may be null.
- **Admin leave/delete** [1]: the server's sentence is shown instead of "It didn't go through".
- **Decoding failures** are logged by key path; **fixtures** come from the hub's own code (`scripts/empire-fixtures.sh`,
  `ServerSamplesTests`), with the real statuses and an empty-ring case [2].

Servers (deployed 2026-10-25, checked live):

- **Private apps check their owner** [1]: Arestoteles and Aresus let in any account with their service, and an account
  fills its own `requested`, so one tap on Approve could open Patrik's vault. Both now have `EMPIRE_ALLOWED_USERS`
  like Aresium (empty = nobody); Aresus pushes go to the owner only. Live: the test account (which has both services)
  gets 403 from all three; Patrik's id is the admin account.
- **Hub** [2]: every error `{"error", "code"}` with a catch-all 500; `state.json` brought to the contract's shape in one
  place (a bad hand edit no longer breaks the app or drops the connection); `pending: null` when the count fails;
  approvals carry `verified`, decisions return the list and honour the services Patrik saw.
- **Admin cannot leave or delete himself** [1]: the account server answers 403 with a sentence; Arestemis's
  `DELETE /me` keeps the admin's data (found by the fix agent: leaving deleted the data before the refused leave).
- **Docs** [1, 3]: `PRIVACY.md` (accounts row, logs), `APP-STORE.md` (demo account, internal only), `EMPIRE-APP.md`
  (field name), README (upload as App Store Connect, not "TestFlight Internal Only", which can never go external).

## Left open

- **Before anyone but Patrik gets an app** (Open 12): central logout cleanup across apps, widgets and push devices
  [1]; a privacy cover in the app switcher [1, from 2026-10-23]; installing a missing province app from the Empire app [3].
- **For Patrik** (Open 13): whether a member's ring shows every province the account has access to [3]; what makes the
  Empire app worth having over the mobile website (e.g. approve sign-ups from the lock screen, open offline) [3].
- Small: sample JSONs ship in the Release bundle; the home-screen name "Empire" vs "Ares Empire" [3]; a shared
  `.xcconfig` for the team when Apple approves [3].
