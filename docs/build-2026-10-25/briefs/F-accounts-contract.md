# One Ares account, run from every app (contract for F1 and F2, final)

Patrik (2026-10-25): "a central ares account makes sense. However that needs to be creatable in every app because the
first app someone gets might not be the empire app. In general, the empire app is the least useful one for normal
people. so one central account but controllable from every app but also every app independently controllable meaning
I guess in each apps settings you can delete that apps data and access as well as your entire ares account."

Decided with it: **one account, one password** for all apps (separate accounts per app were considered and rejected:
every sign-up, approval, reset and deletion would multiply, and the shared login on one iPhone would break). The
Empire app is optional; every app can do everything below by itself.

## What a person can do in every app

| Action | Where | How (server) |
|---|---|---|
| Create an account | login screen | `POST /api/collections/users/records` `{email, password, passwordConfirm, name?, requested: [<this app's service>]}`, then `POST /api/collections/users/request-verification` `{email}` |
| Forgot password | login screen | `POST /api/collections/users/request-password-reset` `{email}` (always 204) |
| Ask for access to this app (logged in, account lacks the service) | the "no access" screen | `PATCH /api/collections/users/records/<id>` `{requested: <current requested + this service>}` |
| Change password | Settings → Account | `PATCH /api/collections/users/records/<id>` `{oldPassword, password, passwordConfirm}`; old tokens end, the app logs in again with the new password at once |
| Leave this app (its access and its data) | Settings → Account | 1. `DELETE /api/<service>/me` where the service keeps data per account (today: Arestemis; push devices go with step 2's logout of this app). 2. `POST https://auth.ares-empire.de/api/empire/leave` `{service}` → `{services, requested}` |
| Delete the whole Ares account | Settings → Account | the app asks for the password and checks it (`auth-with-password`), then `DELETE /api/collections/users/records/<id>` → 204; the server deletes the account's data in every service (below); the app logs out everywhere |

## The account record (`users`, PocketBase)

- New field **`requested`** (multi-select, the same values as `services`): the apps an account asked for and does not
  have yet. The account may set it itself (create and update); only approval turns it into access.
- **Approval** grants what was requested: `approved = true`, `services = services ∪ requested`, `requested = []`.
  Signing up on the website requests `empire` (the hub). Declining an unapproved account deletes it (as today);
  declining an approved account's request only clears `requested`.
- Patrik is told by email of every sign-up and every new access request (which apps, which language), with the link
  that approves it; the person gets an email once approved (in their language: the sign-up sends `language`, a new
  `select` field `en`/`de`, also user-editable).
- Login still needs `verified && approved` (unchanged `authRule`). An app cannot tell "wrong password" from "not
  approved yet", so its login error says both.
- PocketBase's own emails (verification, password reset) are in German and English in one message.

## Deleting an account reaches every service

- PocketBase hook after a `users` record is deleted: one job per service that keeps data per account, in a collection
  **`deletions`** (`account`, `service`, `attempts`, `done`, `last_error`; superusers only). A cron (every 5 min) calls
  each open job: `DELETE http://127.0.0.1:<port>/internal/accounts/<id>` on the service (localhost only, never routed
  by Caddy, like the push service's `/send`), marks it done on 2xx/404, retries otherwise, and emails Patrik once if a
  job still fails after a day. Today's services with per-account data: **Arestemis** (settings, hunts, matches,
  applications) and the **push service** (devices). The account server's own rows (`feedback`) go by cascade.
- `DELETE /api/<service>/me` (public, with the token): the same deletion for the logged-in account, used by "leave
  this app". Today: Arestemis. Single-owner services (Aresium, Aresus, Arestoteles: only Patrik's data) get none;
  leaving them removes access and the data on the phone only.

## The hub's approvals (website and Empire app)

`GET /api/empire/approvals` items gain `requested: [service]` and `approved: bool` (an approved account asking for
more access). `POST /api/empire/approvals/<id>` `{approve: true}` grants as above; `{decline: true}` deletes an
unapproved account or clears an approved account's `requested`.
