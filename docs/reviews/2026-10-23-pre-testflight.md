# Council 2026-10-23: Aresium app before its first TestFlight build

**Subject:** `empire-ios` at 3b45279 (app, widget extension, shared code, project, plists, privacy manifest) and the
server API it uses, `aresium` at af5a1d5. **Why a council:** milestone before the first TestFlight build; login,
tokens and financial data on the phone (`docs/REVIEW.md`: 3–4 seats). Prompt: `codex-runs/council/common.md`.

| Seat | Focus | Model |
|---|---|---|
| 1 | Security and privacy | Claude (subagent) |
| 2 | Apple platform and TestFlight readiness | Claude (subagent) |
| 3 | API boundary: does the app match what the server really sends | Codex `gpt-6-astra`, high, read-only |
| 4 | General case and goal; what hurts in three months | Codex `gpt-6-astra`, high, read-only |

All four ran in parallel, blind, about 10 minutes. Seats 3 and 4 independently found the same top issues; seats 1
and 2 overlapped on most of the rest, so the findings below are merged (seat numbers in brackets).

## Outcome: **Corrected**

No finding changes what is built or why: server-side calculation, the token-free widget, the Keychain handling and
the project structure held up under all four seats. Seats disagreed on what blocks the first build (seat 1: nothing;
seat 2: only signing; seats 3 and 4 each named two items). Claude's call: for an internal build on Patrik's own phone
only signing blocks, but everything accepted below is done before that build, since we are waiting for Apple anyway.
Two findings are about what the numbers mean and go to Patrik (D1, D2).

## Accepted: app (brief 06)

| # | Finding | Seats |
|---|---|---|
| A1 | No refresh when the app comes back to the foreground; the token is re-checked only on a cold launch. Refresh on `scenePhase == .active` when data is a few minutes old, re-check the token when older than ~12 h, dedupe. | 2, 3, 4 |
| A2 | An import finishing during a detail load or recategorise invalidates that request (one shared "generation"): the save's result is dropped, the sheet stays open, no reload. Separate session invalidation from fetch sequencing; interleaving test. | 3, 4 |
| A3 | Import robustness: the queue is emptied before sending and never restored (offline, 409, 401); per-file errors are reduced to a count; files shared while logged out survive logout and go to the next login unseen; no background-task protection (leaving the app kills the upload while the server finishes). Keep the failed batch for Retry/Discard, clear on logout, show waiting files on the login screen, show per-file results, `beginBackgroundTask` around the upload. | 1, 2, 3, 4 |
| A4 | Size guard is per file (20 MB) while the server limit is per request (25 MB, after JSON escaping). Check the encoded request size; send large files one per request. | 1, 2, 3, 4 |
| A5 | Shared exports are copied into the app's Inbox and never deleted (IBANs, full history, in backups). Delete app-owned incoming copies after reading or discarding; never delete file-picker originals. | 1, 2, 4 |
| A6 | Revoked access (refresh answers 403, or `services` lacks `aresium`) keeps the token and the widget snapshot ("Retry saved session" forever). Treat as logout with the reason shown. | 1, 3 |
| A7 | Sample/screenshot launch arguments are compiled into Release and sample mode writes the real App Group snapshot (and its logout deletes it); tests write the real App Group too. `#if DEBUG` the hooks; isolated publisher for sample mode and tests. | 1, 4 |
| A8 | Widgets: amounts not `.privacySensitive()` (StandBy / locked); a failed read is treated as "no data" forever under `.never`; month change needs the app to run. Mark amounts private, explicit file protection `completeUntilFirstUserAuthentication`, retry after 30 min on read failure, refresh at the start of the next month. | 1, 2 |
| A9 | `URLSession.shared` keeps a disk cache; fine only while every route sends `no-store`. Use an ephemeral session. | 1 |
| A10 | The Keychain token survives deleting the app (reinstall = logged in). Wipe it on the first launch after install. | 1 |
| A11 | White flash at launch (generated launch screen uses the system background). Launch background colour #050507. Haptic generator not prepared. | 2 |

## Accepted: server (aresium brief 02)

| # | Finding | Seats |
|---|---|---|
| S1 | Auth outcomes are conflated: PocketBase down / slow / 429 becomes 401, so the app logs out and wipes the widget during an outage; strangers' random Bearer tokens can push PocketBase rate limiting (all checks share 127.0.0.1). Return 401 (token invalid), 403 (no access, incl. `EMPIRE_ALLOWED_USERS`), 503 (could not check); forward the client IP on refresh. | 1, 3, 4 |
| S2 | `pick.spend` offers the synthetic "Uncategorised", which Switch rejects and Add ignores (also on the website). Exclude synthetic categories from `pick`. | 3 |
| S3 | Oversized import requests are cut off instead of answered; the limit counts characters, not bytes. Byte limit and a JSON 413. | 1, 3 |
| S4 | `CAT_META[name]` reads inherited properties (`constructor`, `__proto__`): such a category name would break the whole dashboard. Own-property lookup. | 3 |

## Accepted: setup (Claude)

- One place for version and build numbers (project level) instead of six (seat 2).
- `.gitignore`: `*.csv`, `*.xml` exports outside fixtures, signing files (`*.p12`, `*.cer`, `*.mobileprovision`), `*.xcarchive` (seat 1).
- `ACCOUNTS.md` says tokens last 7 days; the migration sets 30. Fix, and add "phone lost: change the Empire password" (seat 1).
- Fixture provenance: record the aresium commit the fixtures came from; derive the test's expected count from the fixture (seat 4).
- Before upload: a Release build for a generic device; put both widgets on the simulator's home screen once (Edit
  Widget, row taps: the small widget's per-row `Link` may not work, seat 2) .

## For Patrik

- **D1. Payments in US dollars** (seat 3; confirmed on real data: 18 USD rows). Each PayPal dollar purchase is
  counted as the same number of euros, and its "Allgemeine Währungsumrechnung" partner row counts as income
  (4 of them uncategorised, under "Other"). The website has always shown it this way. Proposal: count the euro leg of
  each PayPal conversion as the purchase and drop the dollar rows from the totals (server-side, like bank funding).
- **D2. "This month" on the widget** (seat 3). It shows the latest month that has transactions, so on 1 November,
  before the first November import, it still shows October (correctly labelled). Patrik asked for "the month that I'm
  in". Proposal: show the calendar month with "nothing imported yet for November · last data 30 Oct".

## Noted, not now

- Password AutoFill needs an Associated Domains entitlement and an `apple-app-site-association` file (seat 2).
- App lock / privacy cover in the app switcher: already "Face ID later" in `IPHONE-APPS.md`; before other users (seat 1).
- Add "User ID" to the privacy manifest's collected data before external testers (seat 2).
