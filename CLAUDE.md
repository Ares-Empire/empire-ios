# empire-ios — notes for Claude Code

Read `README.md` first, then the decision record in the ares-empire repo
(`docs/IPHONE-APPS.md`) and the login plan (`docs/ACCOUNTS.md`).

- Native SwiftUI only — no web views wrapping the websites.
- Each app uses its service's existing JSON API; if the API lacks something, change the
  service (its own repo), don't work around it in the app.
- Log in via the Empire account system, never a service's own password.
- Design language: the Ares Empire "crown language" in `ares-empire/EMPIRE.md`
  (near-black, polished gold accent, Space Grotesk / JetBrains Mono).
- Append a line to the Chronicle in `ares-empire/EMPIRE.md` after meaningful work.
- A good structure is worth more work now: if the app would need a copy of a service's logic or a
  workaround, fixing the service is usually the better call (`~/ares-empire/EMPIRE.md` → "How we build apps").

## Workflow (Codex month, until about 2026-11-20)

ChatGPT Pro runs until about 2026-11-20. Until then Claude delegates bounded builds to Codex.
After that, Claude builds alone: drop this section. Same setup as nametbd3 (`docs/WORKFLOW.md` there),
adapted for Xcode on the MacBook. Codex's own rules: `AGENTS.md`.

| Who | Does | Does not |
|---|---|---|
| **Patrik** | Decisions, Apple account and App Store Connect, tries TestFlight builds on the phone | Relay prompts between tools |
| **Claude** | Plans, sets up the Xcode project, anything touching login or tokens, **the look of every screen** (design and visual polish), writes briefs, runs Codex, builds and runs the app on the simulator, commits, merges, TestFlight uploads | Bulk typing Codex can do from a clear brief |
| **Codex** (run by Claude) | Bounded builds from a brief: data, models, the API client, flows and state, widget plumbing, unit tests; screens only as structure for Claude to style; second opinions and council seats | Decide the API contract or the login flow; own a screen's look; edit `project.pbxproj` unless the brief says so; merge |

**Design stays with Claude** (Patrik, 2026-10-24, after the phone hub: Codex's screens looked generic and "cheap"
twice; Claude's rebuild from the desktop's own components was approved at once). Codex may build a screen's
structure and logic; Claude does the look, starting from the existing website/app components, not from new decoration.

**Delegate** when the task fits a brief with a clear "done" (it compiles, these tests pass, this screen
shows this data) and the build is clearly bigger than the brief. Otherwise Claude does it.

### Running Codex

1. **Brief:** copy `prompts/TEMPLATE.md` to `prompts/NN-slug.md`. Settle the design choices in it; link to
   rules instead of restating them. Commit it to `main` before branching.
2. **Worktree:** `git worktree add -b codex/NN-slug ../empire-ios-NN-slug main`. Never let Codex (or
   uncommitted work) sit in `~/empire-ios` itself: aresync auto-commits and pushes that checkout.
3. **Run** in the background (Claude is notified when it ends):
   ```
   codex exec --dangerously-bypass-approvals-and-sandbox -m gpt-6.1-sol -c model_reasoning_effort=high \
     -C ../empire-ios-NN-slug -o codex-runs/NN-slug.md - < prompts/NN-slug.md
   ```
   Models: `gpt-6.1-sol` builds (`xhigh` for tricky ones), `gpt-6-astra` council seats (uses the allowance
   about 3× faster), `gpt-6-luna` trivial jobs. `-o` goes to `codex-runs/` (gitignored).
4. **Check** (below), commit in the worktree, merge to `main`, remove the worktree, set the brief's status line.

**Why no sandbox:** Codex's `workspace-write` sandbox blocks `xcodebuild` and the simulator (tested
2026-10-23), so builds run without it (Patrik's call, 2026-10-23). Codex can then build, run the simulator and
fix its own compile errors. The limits the sandbox used to enforce are now rules in `AGENTS.md`: stay in the
worktree, never commit or push, no installs. Council seats and reviews still run with `-s read-only`.

**Checks are light, but never skipped:**
- Build and run the tests yourself on the simulator. Never take Codex's "build succeeded" as evidence.
- Read the diff: quickly for layout, carefully for anything near login, tokens, the Keychain, or API calls.
- Run the app on the simulator and look at each screen the brief touched
  (`xcrun simctl io booted screenshot <file>`).

**Council** (`docs/REVIEW.md`): a few blind reviewers with distinct focuses, for hard-to-undo choices,
milestones, a bug that comes back, and every 2–3 weeks over merged Codex work.

**Allowance:** `/status` in an interactive `codex`, or the `rate_limits` line in the newest
`~/.codex/sessions/**/*.jsonl` (`used_percent`; window 10080 min = weekly).

## Open (2026-10-24)

Both apps work on the simulator and are merged; nothing reaches the phone until Apple approves the developer account.

1. **TestFlight, once Apple approves:** set the paid team (project level, both projects); the App Groups
   `group.de.ares-empire.aresium` + `group.de.ares-empire.shared` registered for the bundle ids (Xcode's automatic
   signing can do it; the shared Keychain group needs only the team prefix); an App Store Connect record per app;
   Release build for a generic device; archive and upload both (README).
2. **On the phone:** the checks in `docs/reviews/2026-10-23-pre-testflight.md` (widgets incl. row taps), the shared
   login across the two apps on the real device, the Empire app opening Aresium (`aresium://`), no connection.
3. **Council over the Empire app before its first upload** (`docs/REVIEW.md`): brief 08 (Codex: API, store, marks,
   opener) and the login changes (`followSharedLogin`). Not done yet.
4. Hub data, not this repo: Aresium's "About" on the hub (`data/state.json` on the server, `lock: true`, so the sync
   never refreshes it) is outdated (Next.js, Prisma); Patrik has not decided yet whether to rewrite it.
5. Later (decided): Aresium for several users, then Aresium `open` in the hub catalog.

## Setup state (update as it changes)

- MacBook: Xcode 27.1 with two simulator runtimes (2026-10-23): **iOS 27.0** for all normal iPhones (use this)
  and iOS 27.1, which only supports the foldable "iPhone Duo" (its screenshots came out black). The simulator
  window app is called **DeviceHub** in Xcode 27; `xcrun simctl` works without it.
- Apple Developer Program (paid, for TestFlight; decided in `ares-empire/docs/IPHONE-APPS.md`): payment confirmed,
  enrollment **pending** at Apple (2026-10-23). Xcode is signed in, so far with only the free "Personal Team"; the
  paid team appears under the same account once Apple approves (check: Xcode → Settings → Apple Accounts). Until then: simulator only, no TestFlight (a free
  Apple ID could install on the phone, but those builds stop opening after 7 days, so we don't use it).
- Xcode project `Aresium/Aresium.xcodeproj` (2026-10-23): app + tests, folder-synchronized groups (new Swift
  files need no `project.pbxproj` edits), bundle id `de.ares-empire.aresium`, iOS 26+. Signing team: set to the
  paid team once approved. Launch argument `-sampleData` skips login and shows the bundled sample.
- Test fixtures `AresiumTests/server-dashboard.sample.json` + `.expected.json`: the Aresium server's sample and
  the website's answers for it. When `/api/data` changes: `npm run sample` in aresium, then
  `node scripts/aresium-fixtures.mjs`.
- **Two projects, one shared folder** (2026-10-24): `Aresium/Aresium.xcodeproj` and `Empire/Empire.xcodeproj`
  (bundle id `de.ares-empire.empire`, made with `scripts/new-app-project.py`). `Shared/` (Empire login, network
  layer, `AppFont`, fonts, `EmpireShared`) is compiled into every app (and the Aresium widget, for the fonts).
- **One login for all apps:** the token is a Keychain item in the group `$(AppIdentifierPrefix)de.ares-empire.shared`
  (every app's entitlements + `AppIdentifierPrefix` in its Info.plist), the fresh-install wipe keys off the App
  Group `group.de.ares-empire.shared` (deleted by iOS only with the last Empire app). Rules in
  `Shared/Auth/EmpireSession.swift`: an invalid login (401, refresh refused) logs out everywhere; an account without
  this app's service, or a 403 from the app's server, closes only this app (`access = .denied`, the app forgets its
  data via `onAppDataReset`); a failed new login never ends an existing one. Coming to the foreground, each app calls
  `followSharedLogin()`: it picks up a login or logout made in another app meanwhile (a renewed token of the same
  account is taken over without a server call). Verified across the two apps on the simulator with
  `scripts/check-shared-login.sh <udid>` (2026-10-24).
- **Empire app** (2026-10-24): the approved phone hub (`ares-empire/web/app/mobile.jsx` + `mobile.css`) in SwiftUI,
  `Empire/Empire/Screens/` (Claude's look; values copied from the CSS, with the CSS selector named in comments), data
  in `Model/` + `API/` (brief 08). Launch arguments (DEBUG): `-sampleData` (admin sample), `-sampleUser` (member
  sample), `-openSheet province|idea|add|approvals` for screenshots. Ring: tap the front province to open it (its app if
  installed, else its website), hold any tab for its page; on the page the name is the link (Patrik, 2026-10-24). Province marks load from the hub with the
  Bearer token, so the samples show monograms. Signing up and password resets stay on the website.
- **Push** (2026-10-24): `Shared/Push/` (`PushCenter`, `PushAppDelegate`, tests in `EmpireTests/PushCenterTests`)
  registers devices with the Empire push service (`ares-empire/docs/PUSH.md`; dry run until the APNs key). Not wired
  into any app yet; each app needs the Push Notifications capability (paid team) and, for time-sensitive
  notifications, the `com.apple.developer.usernotifications.time-sensitive` entitlement. Nothing in Shared may use
  `UIApplication.shared` (the Aresium widget compiles Shared too).
- **Aresus app** (2026-10-24, `Aresus/`): two tabs, Aresus (summary, server card, province boxes, province page) and
  Aresync (machines, runs by day, run sheet), on the Aresus API (`aresus/docs/API.md`, samples in
  `Aresus/Aresus/Samples/` = copies of `aresus/docs/samples/`). Data in `Model/` + `API/`, look in `Screens/` (Shared/Design).
  Links `aresus://province/<slug>`, `aresus://sync/run/<id>`, `aresus://server` go through `AresusNavigation.open(_:)`
  (notification taps too, once Shared/Push is wired). Launch arguments (DEBUG): `-sampleData` (`-sampleAllGood`,
  `-sampleEmpty`), `-tab aresus|aresync`, `-openProvince <slug>`, `-openRun <id>`, `-scrollToEnd`, and `-sampleLogin` /
  `-sampleLoading` for those screens. Sample mode runs its clock from the samples' moment, so times read as live.
- **Arestemis app** (2026-10-24, build A1): `Arestemis/` (bundle id `de.ares-empire.arestemis`), the flat hunter on
  the Arestemis API (`~/Arestemis/docs/API.md`; samples in `Arestemis/Arestemis/Samples/`, copies of its `docs/samples/`).
  Data in `API/` + `Model/` (one `ArestemisStore`, optimistic changes with rollback), screens in `Screens/` on
  `Shared/Design`. Launch arguments (DEBUG): `-sampleData` (+ `-sampleNoHunt`, `-samplePaused`, `-sampleLoading`),
  `-tab hunt|listings|search`, `-filter new|saved|applied|all`, `-openMatch <id>`,
  `-openSheet settings|application|rejected|place`, `-scrollBottom`, `-scrollTo rent|movein`. Push: the category and
  the link routing are in `Model/Notifications.swift`; `Shared/Push` is not wired in yet.
- Targets: `Aresium` (app), `AresiumWidgetExtension` (widgets, folder `Aresium/AresiumWidget/`, embedded in the
  app), `AresiumTests`. `Aresium/AresiumShared/` is compiled into both app and widget (theme, `AppTheme`, `AppGroup`,
  widget snapshot); everything else belongs to one target. App Group `group.de.ares-empire.aresium` in both
  entitlements files (on the simulator Xcode embeds them as "simulated" entitlements; on the phone it needs
  the paid team).
- `Aresium/Aresium/Info.plist` holds only what build settings cannot (document types: the share sheet offers
  "Aresium" for `.csv`/`.xml` exports); it is merged with the generated plist and excluded from the folder's
  resources in the project file.
