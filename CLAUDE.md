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

## Languages (every app in English and German)

Decided 2026-10-24 (Patrik), rules in `ares-empire/docs/LANGUAGES.md`. The iPhone's language, or the app's own, picks
German or English. The Mac and the simulators are set to German, so the apps open in German there.

- **The app's own language: Settings → General → Language in every app** (the gear in its header; row "Sprache ·
  Deutsch" shows the language the app shows now). It offers Like the iPhone / English / Deutsch and writes the app's own
  `AppleLanguages` (`Shared/Language/LanguageSetting.swift`; "like the iPhone" removes it), the same setting iOS keeps in
  Settings → Apps → the app → Language, so the two always agree. iOS 27 shows that iOS entry only while the iPhone lists
  two or more languages (tested 2026-10-24), hence the in-app page. iOS reads the setting when the app starts: the page
  says the app switches after it is closed and opened again; the app's server texts follow it (`Accept-Language` from
  `AppLanguage.current`). Not checked yet: whether a widget (its own process and defaults) follows the app's own choice
  or the iPhone's. On the simulator, `xcrun simctl spawn <udid> defaults write <bundle id> AppleLanguages …` lands
  outside the app's container (the app follows it, iOS's page does not); choosing in the app or in iOS Settings writes
  the app's own defaults.
- **Write English in the code, German in the String Catalogs.** `Text("Save")`, `Button("Save")` and other SwiftUI
  literals are looked up by themselves. Text that is built as a `String` (model code, components taking `String`,
  errors) goes through `String(localized: "…")`; pure functions that tests pin take `language: AppLanguage = .current`
  and use `language.string("…")`. Names (Aresium, WG-Gesucht) and numbers-only text use `Text(verbatim:)`.
- **One catalog per folder that more than one target compiles:** `Shared/Shared.xcstrings`,
  `Aresium/AresiumShared/AresiumShared.xcstrings`, `Aresus/AresusShared/AresusShared.xcstrings`. Code in those folders
  names its table (`Text("Log in", tableName: "Shared")`, `String(localized: "…", table: "AresusShared")`), or the
  widget would miss the string. Everything else uses the target's own `Localizable.xcstrings` (each app, each widget).
- **Numbers, money, dates:** `AppLanguage.locale` (en_GB or de_DE, fixed per language): "€1,400" / "1.400 €",
  "Sat 24 Oct" / "Sa. 24. Okt."; `Format`/`AresusFormat`/`Money` take the language. A server's sentences arrive in the
  app's language: `URLSessionTransport` sends `Accept-Language`, `PushAPI` registers the device's language.
- **After changing text:** `scripts/strings.py sync` (exports every project and updates the catalogs: new keys in,
  unused ones out), write the German (`scripts/strings.py fill de.json`, plurals as `{"en": {"one", "other"}, "de":
  {…}}`, or edit the catalog in Xcode), then `scripts/strings.py check` must say 0 problems. Look at every changed
  screen in German before merging: `xcrun simctl launch <udid> <bundle id> -AppleLanguages "(de)" -AppleLocale de_DE`
  plus the app's sample arguments; a label that wraps gets a shorter German word, not a smaller font.
- **Tests run in English:** each scheme's test action pins `en`/`GB`. German cases call the pure functions with
  `language: .german` (`FormattingTests`, `AresusFormatTests`, `GermanTests`, `AppLanguageTests`).
- Sample mode shows the servers' English sample files, so their lines stay English there; live they come in German.
- German style: "du", plain and short; the app's terms: Jagd/Angebote/Suche (Arestemis), Problem/Aktiv/Inaktiv
  (Aresus), Buchung/Ausgaben/Einnahmen (Aresium), EROBERT/BELAGERT/… (Empire status words). "THE EMPIRE" stays a name.

## Settings (every app, 2026-10-24)

Every app has one Settings sheet, opened by the gear (`gearshape`) in its header where the account actions used to be:
`Shared/Design/SettingsScreen.swift` (`SettingsScreen(app:session:sample:logOut:) { app's own section }`). Sections: the
app's own (a view-builder slot, built with `SettingsSection` / `SettingsRow`; Arestemis puts its application texts and
hunt notifications there), General (Language; Notifications, opening the app's notification page in iOS Settings, in
apps with `sendsNotifications`), Help (Contact & support: brief E5's form from `Shared/Support`, a stub until it is
merged), About (Privacy and Imprint open `LegalPage` in the app's language, Fonts & licences shows the OFL texts from
`Shared/Fonts`, Version), Account (the email from the login answer, `EmpireSession.email`, and Log out, which does what
the app's log-out did before). Links: `Shared/Settings/SettingsInfo.swift`. Every login screen ends with "Privacy ·
Imprint" (`LoginScroll`). Screenshots: `-sampleData -openSheet settings` in every app. A new app: a gear in its header
and `SettingsScreen` in a sheet. The sheet is dark in every app, also in Aresium's light theme.

## Open (2026-10-24)

Four apps (Aresium, Empire, Arestemis, Aresus) work on the simulator and are merged; nothing reaches the phone until
Apple approves the developer account.

1. **TestFlight, once Apple approves:** set the paid team (project level, both projects); the App Groups
   `group.de.ares-empire.aresium` + `group.de.ares-empire.shared` registered for the bundle ids, the widgets' too
   (`de.ares-empire.aresium.widget`, `de.ares-empire.aresus.widget`) (Xcode's automatic
   signing can do it; the shared Keychain group needs only the team prefix); an App Store Connect record per app;
   Release build for a generic device; archive and upload both (README).
2. **On the phone:** the checks in `docs/reviews/2026-10-23-pre-testflight.md` (widgets incl. row taps), the shared
   login across the two apps on the real device, the Empire app opening Aresium (`aresium://`), no connection; the
   Aresus widget placed on the home and lock screen (refreshes by itself, the medium one's rows open their province).
3. **Council over the Empire app before its first upload** (`docs/REVIEW.md`): brief 08 (Codex: API, store, marks,
   opener) and the login changes (`followSharedLogin`). Not done yet.
4. Hub data, not this repo: Aresium's "About" on the hub (`data/state.json` on the server, `lock: true`, so the sync
   never refreshes it) is outdated (Next.js, Prisma); Patrik has not decided yet whether to rewrite it.
5. Later (decided): Aresium for several users, then Aresium `open` in the hub catalog.
6. **Push, once Apple approves** (`ares-empire/docs/PUSH.md` → Operating): create the APNs key (.p8) in the developer
   portal, put it on the server, set `APNS_KEY_ID`/`APNS_TEAM_ID`, restart `empire-push`; enable the Push Notifications
   and Time Sensitive capabilities for Arestemis and Aresus (entitlements are already in the projects). Then check on the
   phone and retire Telegram: Arestemis (`TELEGRAM_*` in /root/Arestemis/.env) and Aresync (`TG_*` in each config).
7. **Windows laptop:** an Aresus machine token for `Notebook-Patrik` (`aresus/scripts/new-machine-token.py`) into
   `windows/config.ps1`; the PowerShell report is untested.
9. **Arestoteles on the phone:** check the Discuss hand-off (`DiscussPrompt.target`, now `https://claude.ai/code`: does
   the Claude app open, and how to start a session there with the copied prompt); replace the bust (the website's
   `aristotle-bust.png` has a faint "Magnific" watermark); a widget with a position to revisit (needs a widget target).
8. **Build 2026-10-24 record:** `docs/build-2026-10-24/STATUS.md` (what was built, decisions, live tests). Built after the main work: the Aresus
   widget and the hub's live lines from Aresus.

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
  registers devices with the Empire push service (`ares-empire/docs/PUSH.md`; dry run until the APNs key). Wired into
  Aresus and Arestemis (`@UIApplicationDelegateAdaptor(PushAppDelegate.self)` in the App, `push.start` + routing of
  `openedURL` in ContentView, never in samples/tests); each needs the Push Notifications capability (paid team) and,
  for time-sensitive notifications, the `com.apple.developer.usernotifications.time-sensitive` entitlement (in the
  projects already). Nothing in Shared may use
  `UIApplication.shared` (the Aresium widget compiles Shared too).
- **Aresus app** (2026-10-24, `Aresus/`): two tabs, Aresus (summary, server card, province boxes, province page) and
  Aresync (machines, runs by day, run sheet), on the Aresus API (`aresus/docs/API.md`, samples in
  `Aresus/Aresus/Samples/` = copies of `aresus/docs/samples/`). Data in `Model/` + `API/`, look in `Screens/` (Shared/Design).
  Links `aresus://province/<slug>`, `aresus://sync/run/<id>`, `aresus://server` go through `AresusNavigation.open(_:)`
  (notification taps too). Launch arguments (DEBUG): `-sampleData` (`-sampleAllGood`,
  `-sampleEmpty`), `-tab aresus|aresync`, `-openProvince <slug>`, `-openRun <id>`, `-scrollToEnd`, and `-sampleLogin` /
  `-sampleLoading` for those screens. Sample mode runs its clock from the samples' moment, so times read as live.
  **Widget** (`AresusWidgetExtension`, kind `AresusStatus`, `de.ares-empire.aresus.widget`; small, medium, lock-screen
  rectangular and circular): "All running" or the issues, with the check's live age. Its timeline provider reads the
  shared Empire token (never logs in), fetches `GET /overview` every 15 min and saves a `WidgetStatus` in the App Group
  (`aresus-widget-status.json`); the app saves it after every overview and deletes it on logout. Offline, or with the
  Keychain locked (the token is readable only while the phone is unlocked), it shows the saved status; after an hour it
  loses its status colour. `Aresus/AresusShared/` is compiled into app and widget (overview types, API client core,
  widget status, store, loader, views). DEBUG `-widgetGallery good|issues|loggedout` shows the views for screenshots.
- **Arestemis app** (2026-10-24, build A1): `Arestemis/` (bundle id `de.ares-empire.arestemis`), the flat hunter on
  the Arestemis API (`~/Arestemis/docs/API.md`; samples in `Arestemis/Arestemis/Samples/`, copies of its `docs/samples/`).
  Data in `API/` + `Model/` (one `ArestemisStore`, optimistic changes with rollback), screens in `Screens/` on
  `Shared/Design`. Launch arguments (DEBUG): `-sampleData` (+ `-sampleNoHunt`, `-samplePaused`, `-sampleLoading`),
  `-tab hunt|listings|search`, `-filter new|saved|applied|all`, `-openMatch <id>`,
  `-openSheet settings|application|rejected|place|describe`, `-scrollBottom`, `-scrollTo size|rent|movein`. Push: the category and
  the link routing are in `Model/Notifications.swift`; `Shared/Push` is wired in ContentView.
  **Search (API version 2, 2026-10-24, Patrik):** Flat or WG / Flat / WG, people moving in, max flatmates, size ranges
  (flat, WG room), areas, cold and warm rent ranges, move-in and temporary offers, portals, extras; every field optional
  except a place and a portal. "Describe it" is a line at the top that opens a sheet (`SearchDraft`, `SearchScreen`).
- **Arestoteles app** (2026-10-24, build R2): `Arestoteles/` (bundle id `de.ares-empire.arestoteles`, URL scheme
  `arestoteles`), Patrik's Weltbild vault on the Arestoteles API (`Arestoteles/docs/API.md`, decisions
  `ares-empire/docs/ARESTOTELES-APP.md`; samples in `Arestoteles/Arestoteles/Samples/`, copies of its `docs/samples/`).
  Data in `API/` + `Model/`: one `VaultStore` (the last vault from Application Support first, only for the account of
  the saved login, then `GET /vault` with `If-None-Match`; one method per edit op, sent one at a time; quick notes kept
  on the device until sent; forgets files and Spotlight on logout), `VaultIndex` (lookups), `VaultSearch`, `NoteLink`
  (the one parser for links in notes, deep links and Spotlight), `DiscussPrompt` (target URL in one constant),
  `Spotlight`. Screens in `Screens/` are structure on `Shared/Design`, not styled yet. Launch arguments (DEBUG):
  `-sampleData` (edits answered with `edit-result.json`; `-sampleEditConflict` 409, `-sampleEditInvalid` 422,
  `-samplePushLater` pushed false, `-sampleOffline` the sample as the saved vault and no server),
  `-tab positions|topics|library|search`, `-library mechanisms|events|questions|actors`, `-search <query>`,
  `-openNote <id>[#<heading>]`, `-openPosition <id>`,
  `-openSheet brief|edit|quicknote|discuss|discussions|reword|change|drop|add|evidence`, and `-sampleVaultFile <path>` (a
  vault saved from the server instead of the made-up sample, to look at real notes; DEBUG only, never committed).
  **For lookups (Patrik, 2026-10-24):** position cards show the position's `title` (the bold part) cut to one line of
  thought (`Lookup.cardLine`); a position page offers Discuss (now, or "later" onto the vault's to-discuss list), Edit
  (wording) and Note (into the Inbox, about the position); no change/drop on the phone. Long notes open with their
  sections closed (`NoteBody`), with Figures & dates, Sources and Terms (`LookupPanel`), search shows sentences first,
  and pressing a paragraph or list item edits just that passage (the server's block `lines`).
- Targets: `Aresium` (app), `AresiumWidgetExtension` (widgets, folder `Aresium/AresiumWidget/`, embedded in the
  app), `AresiumTests`. `Aresium/AresiumShared/` is compiled into both app and widget (theme, `AppTheme`, `AppGroup`,
  widget snapshot); everything else belongs to one target. App Group `group.de.ares-empire.aresium` in both
  entitlements files (on the simulator Xcode embeds them as "simulated" entitlements; on the phone it needs
  the paid team).
- `Aresium/Aresium/Info.plist` holds only what build settings cannot (document types: the share sheet offers
  "Aresium" for `.csv`/`.xml` exports); it is merged with the generated plist and excluded from the folder's
  resources in the project file.
