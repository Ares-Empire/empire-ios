# 22: Aresium without an account, with an optional lock

Status: merged 2026-10-27 (Aresium 189, Empire 204 tests; other apps build; deleting the data also removes left-behind stores)
Repo: empire-ios · Worktree: `../empire-ios-22-no-account` (branch `claude/22-no-account`) · Built by: a Claude agent
(data, flows and the look of the new screens)

## Goal

Patrik decided (2026-10-27): **Aresium needs no account.** In phone mode the account did nothing for a friend (their
data never leaves the phone) and only cost them a sign-up, an email confirmation and waiting for approval; Apple's
review guideline 5.1.1(v) also says an app without account-based features must work without a login. Instead,
Aresium gets an **optional lock: Face ID and/or a code of its own**. Patrik keeps server mode through the shared
Ares login. A friend installs Aresium, opens it, and is on the first-run screen.

## Read first

`AGENTS.md`, `CLAUDE.md` (Setup state → "Aresium phone mode", "One login for all apps", central logout, "App switcher
cover", Languages, Light mode, the design rules), `~/ares-empire/docs/ARESIUM-FOR-OTHERS.md`. The code:
`Aresium/Aresium/ContentView.swift`, `Model/ModeStore.swift`, `Model/PhoneStore.swift`, `Model/PhoneBackend.swift`,
`Model/DashboardStore.swift`, `Model/WidgetSnapshotPublisher.swift`, `AresiumShared/WidgetSnapshotStore.swift`,
`Screens/PhoneScreens.swift`, `Screens/DashboardScreens.swift`, `Screens/LoginScreen.swift`, `Shared/Auth/*`
(`EmpireSession`, `LoginMarker`), `Shared/Design/SettingsScreen.swift` (`SettingsApp`), `Shared/Design/PrivacyCover.swift`,
`Shared/Support/*`, `Shared/Push/*`; the contact collection on the account server:
`~/ares-empire/accounts/pb_migrations/1793200000_contact.js` and the website's `~/ares-empire/web/legal/contact.js`.

## Build

1. **Open without a login.** Aresium starts in phone mode on this phone's one store: the first run (choose
   categories, import, Restore as a quiet link) or the dashboard. The login screen is no longer on Aresium's path.
   The "needs a connection the first time" state goes (nothing waits for the server any more); remove what becomes
   unused.
2. **One store per phone.** `Application Support/Aresium/local/` instead of one per account id. Moving over: if no
   local store exists and exactly one old per-account store does, it becomes the local store (move, not copy); with
   several, the most recently changed one moves and the others stay untouched (log it). The widget snapshot belongs
   to the local store (no account check for it); server mode's snapshot stays as today.
3. **Server mode stays for the owner.** When the shared Keychain login exists (from any Ares app), Aresium asks
   `GET /api/mode` as today: `server` → server mode exactly as today; anything else (`phone`, 401, 403, an error,
   offline without a remembered answer) → phone mode on the local store. A remembered `server` answer works offline.
   When that login ends (logout here or in another app, the central logout's marker), Aresium goes back to phone mode
   on the local store; the server dashboard and its widget numbers are cleared, the local store is untouched.
4. **Settings.** Without a login: Your data on this iPhone (Categories, Export, Restore, Delete Aresium data), Lock
   (below), language, look, Contact & support, About, Privacy · Imprint, and last a quiet **Ares account** row:
   "Sign in" with the caption "Only for an Aresium server of your own. Your data here stays on this iPhone." (login
   sheet without "Create account"). Signed in: that row shows the email and Log out, plus Leave Aresium / Delete Ares
   account as today. Leaving or deleting the account never deletes the local store (it belongs to the phone, not to
   an account); "Delete Aresium data on this iPhone" does.
5. **The lock** (off by default; Settings → Lock):
   - "Lock with Face ID" (Touch ID on such phones): unlock with Face ID; without an own code the iPhone's code is the
     fallback (`deviceOwnerAuthentication`).
   - "Own code" (set, change, remove; 6 digits): with it, unlocking asks Face ID (if on) and else the code; the
     iPhone's code is then not accepted. Setting it says plainly: a forgotten code cannot be reset; without it and
     without Face ID the only way back is deleting Aresium's data on this iPhone (export first).
   - Stored as a salted hash (PBKDF2-SHA256, ≥ 200,000 rounds, or CryptoKit equivalent) in Aresium's own Keychain
     items, this device only, never in the shared group. Wrong codes: after 5, wait 1 minute, then 5, 15, 60; the
     count survives a restart.
   - Locks at launch and after more than 10 seconds in the background; being inactive (the Files picker, the share
     sheet, Control Center) does not lock. A file shared into Aresium while locked waits until it is unlocked.
   - With the lock on, the widgets show no numbers (just that Aresium is locked); the Settings footer says so.
   - The lock screen in Aresium's look (the app switcher cover's wordmark band is the start), one Face ID button,
     a code pad; calm, no slogans. `NSFaceIDUsageDescription` in English and German.
6. **Contact & support without a login** posts to the account server's `contact` collection (no account needed:
   email required so Patrik can answer, optional name, the message with a short footer "Aresium <version> · iOS …",
   language, the empty honeypot `website`) instead of `feedback`. Signed in, it stays `feedback`. Keep this in
   `Shared/Support` as a second path the other apps never use (they always have a login).
7. **Push:** no device registration without a login.
8. **"Current" view: a category opens this month's payments directly** (the route with the current month), in both
   modes; Overview keeps the month list first. (Patrik expected payments, not months, when he tapped a category.)
9. **German** for every new string (`scripts/strings.py sync`, `fill`, "du", plain); `check` says 0 problems.
10. **Notes:** `CLAUDE.md` (the phone mode entry, "One login for all apps": Aresium works without it, the lock, the
    files), `docs/APP-STORE.md` (Aresium: login optional; the review needs no demo account any more, say how to test
    with the made-up file), `PrivacyInfo.xcprivacy` if a required-reason API is added.

## Settled: do not re-open

- No account for phone mode; server mode only for the owner list through the shared login. No data leaves the phone.
- Engine and dashboard numbers are not part of this brief (brief 20 changes "Not sorted" separately).
- The hub and the Empire app's catalog (Aresium as "get the app" without asking for access) come in a later brief.

## Done when

- `xcodebuild test` for Aresium passes (`-parallel-testing-enabled NO`), with tests for: launch without a login →
  phone mode on the local store; owner login → server; another login → phone on the same local store; logout
  elsewhere → back to phone; moving an old per-account store; the lock (hash and check, wrong-code waits, the
  background timing as plain functions); support without a login builds a `contact` record; the Current-view route.
- Empire, Arestemis, Aresus and Arestoteles still build and their tests pass (Shared changes).
- Screenshots `build/22-*.png`: first launch without a login, Settings signed out and signed in, the lock settings,
  the lock screen (Face ID and code), light and dark, English and German, one at the largest text size; a contact
  sheet `build/22-sheet.png`.
- Final message: files, test counts, screenshots, the moving-over behaviour, and anything doubtful. Never commit,
  push, merge or deploy; never touch the server, any database or other repos. No real data: there are no real
  payments on this Mac and you must not look for any.
