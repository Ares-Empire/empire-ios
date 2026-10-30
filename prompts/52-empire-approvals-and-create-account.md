# 52: Empire's approvals can be refreshed (Patrik's list no. 12); Create account keeps what was typed (Shared 2, no. 11)

Status: merged 2026-10-30 (Empire 207 tests; Aresium and Aresus build; approvals, the discard question and the email hand-off checked on the simulator)
Branch: `codex/52-empire-comfort` · Worktree: `../empire-ios-52-empire-comfort` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Patrik approved both items (2026-10-30). After this brief the Empire app's approvals list can be pulled to refresh and
offers Try again when it failed to load, and in every app that has a login screen, Create account no longer loses what
was typed on a swipe down, and the email carries over into the login field after "Confirm your email".

Three other briefs run at the same time: 49 (Arestemis), 50 (Aresus), 51 (Arestoteles). **Another session works on
Aresium and may change `Shared/` too**: change only the files named here in `Shared/`; Claude merges main before
merging this.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Languages", "Light mode", "Accounts in every app" and the "Empire app" entry under
  Setup state)
- `docs/reviews/2026-10-30-swipe-and-comfort.md` → "The other four apps" → "Shared" item 2 and "Empire" item 1
- `Empire/Empire/Screens/EmpireSheets.swift` (`ApprovalsPage`, around lines 440–460; the sheet frame around lines
  15–35), where the approvals are loaded (`EmpireHomeStatus`, `EmpireHomeActions`, the store in `Empire/Empire/Model/`)
- `Shared/Design/AccountSheets.swift` (Create account, around lines 120–150 and 250–270), `Shared/Auth/AccountForms.swift`,
  `Shared/Design/ProvinceLogin.swift` (`AresLogin`, which presents it and owns the login's email field),
  `Shared/Support/SupportSheet.swift` (the pattern to copy: `interactiveDismissDisabled(form.hasUnsentText …)` and its
  "Discard this message?" question)

## Build

1. **Approvals: pull to refresh and Try again** (list no. 12). The approvals page loads its list again on a pull
   (`.refreshable`, on that page only, not on the other sheets that share the frame) and, when the list could not be
   loaded ("Pending accounts could not be loaded."), offers **Try again** under the line, which loads it again (the
   line and the button go while loading, as on first load). Use a button the Empire sheets already use for a quiet
   action (for example the "+" sheet's Ask for access); no new style.
2. **Create account keeps what was typed** (Shared 2, list no. 11), in `Shared/Design/AccountSheets.swift`:
   - While the email, a password or the name holds something and the account is not created yet, swipe down is held
     back, and the sheet's close button asks first: "Discard this account?" (Discard, destructive; Keep editing),
     the way Contact & support does. With nothing typed, or after the account was created, it closes at once.
   - After "Confirm your email" (the account created), closing the sheet in any way (Back to login, the close button,
     swipe down) puts the email into the login field, as Back to login does today (`created(form.email)`).
   - Put "has something to discard" in the form model (`AccountForms.swift`) with unit tests in `EmpireTests/
     AccountTests` (typed then cleared is nothing; spaces only is nothing; after creation nothing is held back).

## Settled: do not re-open

- No new looks: the Empire app's own sheet pieces and `Shared/Design` only.
- The question's wording follows Contact & support's ("Discard this message?" → "Discard this account?"), in the
  `Shared` table with German.

## Out of scope

- Every other file in `Shared/`; Aresium (another session), Arestemis, Aresus, Arestoteles (briefs 49–51).
- The account server and the hub. `project.pbxproj`.

## API

Existing only: the approvals list call the Empire app already makes. Nothing new.

## Done when

- `xcodebuild test -project Empire/Empire.xcodeproj -scheme Empire` passes on your own simulator (`codex-52`, commands
  in `AGENTS.md`), with the new tests. Build Aresus too (it shows the same Create account sheet) to be sure it compiles.
- `scripts/strings.py sync` then `scripts/strings.py check`: 0 problems. Write the German yourself (du, short), and keep
  it also in `build/52-de.json`.
- Looked at on the simulator in English and German, light and dark: screenshots `build/52-*.png` of the approvals page
  with Try again (`-sampleData -openSheet approvals`; add a DEBUG argument that makes the sample's list fail if there is
  none) and while refreshing, Create account's discard question (`-sampleLogin -openSheet createAccount` plus a DEBUG
  argument that types into it), and the login field with the email after the confirm step (`-accountPhase done`).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, the launch arguments
you added, the German strings you added, what is missing or doubtful. Never commit, push or merge: Claude does.
