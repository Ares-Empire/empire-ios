# F2: accounts run from every app (iPhone side)

Read `COMMON.md` (same folder) and `F-accounts-contract.md` (final) first, then `~/empire-ios/CLAUDE.md` (Languages,
Settings, the shared login), `~/empire-ios/docs/build-2026-10-24/briefs/DESIGN.md` (the family look), and
`Shared/Auth/`, `Shared/Design/ProvinceLogin.swift`, `Shared/Design/SettingsScreen.swift`, `Shared/Support/` (the
pattern for a form with logic outside the view). Worktree: `~/wt/empire-ios-accounts` (branch `accounts`).
Simulator: create `agent-accounts` yourself (`xcrun simctl create agent-accounts "iPhone 17"
com.apple.CoreSimulator.SimRuntime.iOS-27-0`); never use the booted "iPhone 17" (Patrik's). You may edit `Shared/`.
Brief F1 builds the server side at the same time; the contract is final, so build against it with fakes.

## Build (shared, in every app)

1. **Login screen** (every app's login, incl. the Empire and Aresium ones): one line "One Ares account for all Ares
   apps" / "Ein Ares-Konto für alle Ares-Apps"; "Create account" and "Forgot password?" under the login button.
   - **Create account** sheet: email, password, password again, name (optional); it requests this app's service and
     sends the app's language. After it: one calm screen saying to confirm the email by the link just sent, that
     Patrik then approves the account, and that an email follows; back to login.
   - **Forgot password** sheet: email → "If there is an account for this address, an email is on its way."
   - The login error says it may also be an account not confirmed or not approved yet.
2. **No access to this app** (`access = .denied` today): add "Ask for access" / "Zugang anfragen" (adds this service to
   `requested`), then "Asked. You get an email once it's approved." Log out stays.
3. **Settings → Account** (`SettingsScreen`): the email; "Change password" (old, new, new again; afterwards the app logs
   in again by itself); "Log out" with the subline "in all Ares apps on this iPhone"; **"Leave <App>"** / "<App>
   verlassen" (explains in one or two lines what goes: this app's access, its data on the server where it has any, its
   data on this iPhone; the account and the other apps stay; a confirmation) and **"Delete Ares account"** (explains
   that the account and its data in every app go; asks for the password; a destructive confirmation). After leaving:
   this app's data on the phone is forgotten and it shows its login/no-access state; after deleting: logged out
   everywhere.
4. **Per app:** each app tells Settings whether its server keeps per-account data (`DELETE /api/<service>/me`): today
   only Arestemis. The Empire app's approvals show `requested` (which apps) and access requests of approved accounts
   (contract → hub approvals).
5. **Logic out of the views** (`Shared/Auth/`: an account client for these calls on the shared HTTP layer, errors
   mapped to plain lines; the session's new states), unit-tested in `EmpireTests` with a fake transport, including:
   sign-up body, password change then re-login, leave in the right order (service data first, then access), delete
   asking the password first, 400/401/429/offline lines.

## Done when

All five apps build, each app's tests pass (one after another), `scripts/strings.py check` says 0 problems (every new
text in English and German, "du" in German like the rest of the apps). Screenshots in German and English of each new
sheet and state (sample mode or DEBUG launch arguments; add them to `CLAUDE.md`), looked at by you. `CLAUDE.md`'s
login and Settings paragraphs updated.
