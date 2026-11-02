# E5: "Contact & support" in every app

Read `E-COMMON.md` first, then `~/ares-empire/docs/ACCOUNTS.md` (the account server: PocketBase 0.40.6, its rules,
hooks and email through Resend), `~/ares-empire/accounts/` (migrations, `pb_hooks/accounts.pb.js` for how a hook sends
mail, `test-rules.sh`), and `Shared/Auth/`, `Shared/API/` in empire-ios.
Worktrees: `~/wt/ares-empire-support` (branch `support`, the server part) and `~/wt/empire-ios-support` (branch
`support`, the app part). Simulator: `agent-support`. You may edit `Shared/` (only new files in `Shared/Support/`, plus
the smallest additions elsewhere you need).

## Why

Patrik (2026-10-24): "each settings thing should get a 'support' or 'contact' entry so that a user could easily
contact me. it should just open a menu where they can select issue, suggestion / feature, etc (dropdown or smth) and
then write into a box what it is. It then just sends it to the owner's email (the owner file, see ares-empire `docs/PRIVACY.md`)"

## Server: a `feedback` collection on the account server

- A migration (next number after the existing ones) adds the collection `feedback`: `user` (relation to `users`,
  required, deleted with the account), `app` (select: `empire`, `aresium`, `arestemis`, `aresus`, `arestoteles`),
  `kind` (select: `problem`, `idea`, `question`, `other`), `message` (text, required, 1–5000 characters),
  `app_version` (text, ≤ 40), `system` (text, ≤ 80), `language` (select `en`, `de`), `created`.
- Rules: create only for a verified, approved account and only as itself (`@request.body.user = @request.auth.id`);
  list, view, update, delete for superusers only (Patrik reads them in the admin UI). A rate limit for creating
  (PocketBase's built-in rate limiter, for example 10 per hour; check the right label for 0.40.6).
- A hook `accounts/pb_hooks/feedback.pb.js`: after a feedback record is created, mail it to the owner's email (the owner file, see ares-empire `docs/PRIVACY.md`) (one
  constant at the top) from the server's sender, with `Reply-To` the account's email, subject like
  `[Arestoteles] Idea: <first words>`, and a plain body (kind, app, version, system, language, account email, the
  message). If sending fails, log it; the record stays (never fail the create because of mail).
- Extend `accounts/test-rules.sh`: an approved user can create their own feedback, not one for another user, cannot
  list or view any; no login → refused; an invalid `kind`/`app` → refused. Run it with the disposable PocketBase
  (`~/.pocketbase-test/pocketbase`). Update `docs/ACCOUNTS.md` (the collection, the hook, the rate limit).

## App: `Shared/Support/`

- `SupportSheet` (the form) for every app: "Contact & support" / "Kontakt & Support". A kind picker (a menu-style
  `Picker`: Problem / Problem, Idea or wish / Idee oder Wunsch, Question / Frage, Something else / Sonstiges), a text
  box with a short placeholder, one primary Send button (disabled until there is text), and one muted line saying
  what is sent with it (app version, iOS version, language) and that the answer comes by email to the account's
  address. Sending: a calm progress state; success: "Thanks, it's arrived." with Done; failure: the text stays, one
  line why (no connection; too many messages, try later; something else) and Send again. Closing the sheet with text
  in it asks first.
- Logic out of the view: the request (validation, the JSON body with `user` from the token's account id via
  `EmpireToken.accountID`, `app` from `EmpireAppIdentity.service`, version from the bundle, `system` like
  "iOS 27.0 · iPhone", `language` from `AppLanguage.current`), the API call
  (`POST https://auth.ares-empire.de/api/collections/feedback/records`, Bearer token, through the shared HTTP layer;
  401 through `session.handleAuthFailure`, 429 and offline mapped to the lines above), unit-tested in `EmpireTests`
  with a fake transport. Sample mode (`-sampleData`) pretends to send (short delay, success) and never calls the server.
- Brief E4b builds the Settings screen at the same time with a stub where your sheet goes; do not edit E4b's files.
  For screenshots add a DEBUG launch argument to the Empire app that opens your sheet (`-openSheet support`, in the
  existing `-openSheet` handling), and name in your final message the one line the lead needs to connect it.

## Done when

- `bash accounts/test-rules.sh` passes; the Empire app's tests pass; `scripts/strings.py check` says 0 problems.
- Screenshots (German and English): empty form, filled form with the kind menu open, sending, sent, an error.
- Final message: exact deploy steps (copy migration and hook to `/opt/empire-accounts/`, restart, a live test with the
  test account: the lead does it).
