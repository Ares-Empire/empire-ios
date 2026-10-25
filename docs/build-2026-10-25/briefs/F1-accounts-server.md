# F1: accounts run from every app (server side)

Read `COMMON.md` (same folder) and `F-accounts-contract.md` (final) first, then `~/ares-empire/docs/ACCOUNTS.md`,
`~/ares-empire/accounts/` (migrations, hooks, `test-rules.sh`), `~/ares-empire/webauth/server.py` (approvals),
`~/ares-empire/docs/PUSH.md` and the push service code, and `~/Arestemis/docs/API.md` + `src/arestemis/` (`db.py`,
`auth.py`, the API). Worktrees: `~/wt/ares-empire-accounts` (branch `accounts`) and `~/wt/Arestemis-accounts` (branch
`accounts`). No iOS work (brief F2 builds the apps against the same contract at the same time).

## Build

1. **Account server** (migration + hooks): the `requested` and `language` fields and their rules; approval granting
   `requested` (both through the admin UI and through the hub); the emails to Patrik for sign-ups and access requests
   (which apps, which language) and to the person once approved (German or English by `language`); PocketBase's
   verification and password-reset emails in German and English in one message; the route `POST /api/empire/leave`
   (auth required; removes one service from the account's `services` and `requested`; 400 for an unknown service);
   the `deletions` collection, the after-delete hook and the cron with retries and the one-time failure email.
   Extend `accounts/test-rules.sh` (your SMTP catcher pattern from E5 is there) for every rule and route; a fake
   service on localhost for the deletion calls.
2. **Hub approvals** (`webauth/server.py` and the website's approvals view if there is one): `requested` and
   `approved` in the list, approve grants, decline as in the contract; hub tests.
3. **Push service:** `DELETE /internal/accounts/<id>` deletes that account's devices; tests.
4. **Arestemis:** `DELETE /me` (public, the account's own data: settings, hunts, matches, applications, anything else
   stored per account; 204) and `DELETE /internal/accounts/<id>` (localhost only, the same deletion); check that no
   per-account row is left behind (a test that lists every table with an `account` column); docs/API.md.
5. **Docs:** `ares-empire/docs/ACCOUNTS.md` (a section "Accounts in every app" from the contract), PUSH.md, Arestemis
   API.md. (`docs/PRIVACY.md` is not on main yet; the lead updates it.)

## Done when

All test suites pass (`bash accounts/test-rules.sh`, `python3 -m unittest webauth/test_server.py`, the push service's
and Arestemis's tests). Final message with exact deploy steps for the lead (backup of `pb_data` first; order of
deploying the services before the account server so the deletion calls find their routes).
