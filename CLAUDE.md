# empire-ios — notes for Claude Code

Read `README.md` first, then the decision record in the ares-empire repo
(`docs/IPHONE-APPS.md`) and the login plan (`docs/ACCOUNTS.md`).

- Native SwiftUI only — no web views wrapping the websites.
- Each app uses its service's existing JSON API; if the API lacks something, change the
  service (its own repo), don't work around it in the app.
- Log in via the Empire account system, never a service's own password.
- Design language: the Ares Empire "crown language" in `ares-empire/EMPIRE.md`
  (near-black, polished gold accent, Space Grotesk / JetBrains Mono).
- Every screen works in light and dark (Settings → Appearance): build it from the shared colours, never fixed ones
  (below, "Light mode").
- Every app's main screen (the first tab's root) ends with the app's name: `WordmarkScrollView`
  (`Shared/Design/EmpireDesign.swift`) in place of its `ScrollView`; the band scrolls with the content and shows only
  when you scroll down (Patrik, 2026-10-24). Its launch argument for screenshots: `-scrollToEnd` (Arestemis `-scrollBottom`).
- Append a line to the Chronicle in `ares-empire/EMPIRE.md` after meaningful work.
- A good structure is worth more work now: if the app would need a copy of a service's logic or a
  workaround, fixing the service is usually the better call (`~/ares-empire/EMPIRE.md` → "How we build apps").

## Workflow (Codex month, until about 2026-11-20)

**Who gets delegated work (Patrik, 2026-10-26):** design-related work (screens, the look, visual assets) → Claude
agents (the Agent tool); everything else (data, plumbing, scripts, tests, server code) → Codex as below.
**Aresium for other people is built by Claude agents** (Patrik, 2026-10-27), all of it; briefs in `prompts/12-…`
onwards, the agents' rules in `aresium/AGENTS.md` and `AGENTS.md` here. The same rules
hold for both (a worktree, a full brief, Claude checks and merges). A Claude agent stopped by the usage limit is resumed
after the reset, not restarted.

ChatGPT Pro runs until about 2026-11-20. Until then Claude delegated bounded builds to Codex.
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
4. **Check** (below), commit in the worktree, merge to `main` and push it, remove the worktree, set the brief's
   status line. Push as soon as work is merged, in every Empire repo; aresync's daily run is only the backstop
   (Patrik, 2026-10-25).

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
  two or more languages (tested 2026-10-24), hence the in-app page. On the simulator, `xcrun simctl spawn <udid>
  defaults write <bundle id> AppleLanguages …` lands outside the app's container (the app follows it, iOS's page does
  not); choosing in the app or in iOS Settings writes the app's own defaults.
- **Switching restarts the app inside itself** (Patrik, 2026-10-25, brief G1). A row that brings another language asks
  first (`LanguageSwitch`): title, line and Restart in the language it switches to ("Switch to English?", "Aresus
  restarts in English.", "Restart" / "Auf Deutsch umstellen?", "… startet auf Deutsch neu.", "Neu starten"), Cancel in
  the current one, like iOS's own language change. Restart saves the choice, closes every sheet, sets
  `AppLanguage.current` and builds the whole app again (`Shared/AppRoot.swift`, every app's `WindowGroup {
  AppRoot { ContentView() } }`): the main screen, new stores (the servers answer in the new language), the login
  restored as at a launch, push registered again with the new language (`PushCenter.start` takes the new session). No
  `exit()`. A row that keeps the language shown (Deutsch while following a German iPhone) only saves. The widgets
  (Aresus, Aresium) run in their own process, which iOS starts in the iPhone's language: the app copies its choice into
  the App Group (`WidgetLanguage`, `AppRoot(widget:)`) and reloads them; they follow it (checked on the simulator's
  home screen, 2026-10-25). Not following: the widget gallery's name and description (system UI, the iPhone's language)
  and words iOS draws itself inside the app, such as the Cut/Copy/Replace menu on selected text: they keep the language
  iOS started the app in until it is next opened (measured 2026-10-25; SwiftUI's own words, like the Search tab's
  title, do follow). DEBUG screenshots: `-openSheet settings -openLanguage` (the page),
  `-confirmLanguage en|de|iphone` (the confirmation), `-switchLanguage en|de|iphone` (Restart, 2 s after launch); after
  a restart the arguments that open a screen are dropped (`LaunchArguments`), so read launch arguments from
  `LaunchArguments.current`, not `ProcessInfo`. UI tests: `Aresus/AresusUITests` (the real taps, both ways).
- **Write English in the code, German in the String Catalogs.** `Text("Save")`, `Button("Save")` and other SwiftUI
  literals are looked up by themselves (in the root's `.environment(\.locale)`). Text that is built as a `String`
  (model code, components taking `String`, errors) goes through `String(localized: "…")`, which is the apps' own
  (`Shared/Language/AppLanguage.swift`): it reads `AppLanguage.current`, as Foundation's would not after a switch.
  With a table or a comment it is `String(localized: LocalizedStringResource("…", table: "Shared", locale:
  .appLanguage))` (Xcode keeps the table and comment only for Foundation's own calls); `scripts/strings.py check` finds
  any lookup that would keep the start language and `scripts/strings.py fix-lookups` rewrites them. Pure functions
  that tests pin take `language: AppLanguage = .current` and use `language.string("…")`. Names (Aresium, WG-Gesucht)
  and numbers-only text use `Text(verbatim:)`. Never keep a looked-up text in a `static let` or anywhere else that
  outlives a restart.
- **One catalog per folder that more than one target compiles:** `Shared/Shared.xcstrings`,
  `Aresium/AresiumShared/AresiumShared.xcstrings`, `Aresus/AresusShared/AresusShared.xcstrings`. Code in those folders
  names its table (`Text("Log in", tableName: "Shared")`, `String(localized: LocalizedStringResource("…", table:
  "AresusShared", locale: .appLanguage))`), or the widget would miss the string. Everything else uses the target's own
  `Localizable.xcstrings` (each app, each widget).
- **Numbers, money, dates:** `AppLanguage.locale` (en_GB or de_DE, fixed per language): "€1,400" / "1.400 €",
  "Sat 24 Oct" / "Sa. 24. Okt."; `Format`/`AresusFormat`/`Money` take the language. A server's sentences arrive in the
  app's language: `URLSessionTransport` sends `Accept-Language`, `PushAPI` registers the device's language.
- **After changing text:** `scripts/strings.py sync` (exports every project and updates the catalogs: new keys in,
  unused ones out; Xcode's export also rewrites the catalogs, so run it rather than `-exportLocalizations` alone),
  write the German (`scripts/strings.py fill de.json`, plurals as `{"en": {"one", "other"}, "de": {…}}`, or edit the
  catalog in Xcode), then `scripts/strings.py check` must say 0 problems. Look at every changed
  screen in German before merging: `xcrun simctl launch <udid> <bundle id> -AppleLanguages "(de)" -AppleLocale de_DE`
  plus the app's sample arguments; a label that wraps gets a shorter German word, not a smaller font.
- **Tests run in English:** each scheme's test action pins `en`/`GB`. German cases call the pure functions with
  `language: .german` (`FormattingTests`, `AresusFormatTests`, `GermanTests`, `AppLanguageTests`), or run code in the
  other language with `AppLanguage.$scoped.withValue(.german) { … }` (per test, so tests running side by side keep
  theirs). The switch tests (`LanguageLookupTests`, `LanguageSwitchTests` in each suite) ask in both languages; to
  prove the other direction run them again with `-testLanguage de -testRegion DE`.
- Sample mode shows the servers' English sample files, so their lines stay English there; live they come in German.
- German style: "du", plain and short; the app's terms: Jagd/Angebote/Suche (Arestemis), Problem/Aktiv/Inaktiv
  (Aresus), Buchung/Ausgaben/Einnahmen (Aresium), EROBERT/BELAGERT/… (Empire status words). "THE EMPIRE" stays a name.

## Settings (every app, 2026-10-24)

Every app has one Settings sheet, opened by the gear (`gearshape`) in its header where the account actions used to be:
`Shared/Design/SettingsScreen.swift` (`SettingsScreen(app:session:sample:logOut:) { app's own section }`). Sections: the
app's own (a view-builder slot, built with `SettingsSection` / `SettingsRow`; Arestemis puts its application texts and
hunt notifications there), General (Language; Appearance; Notifications, opening the app's notification page in iOS
Settings, in apps with `sendsNotifications`), Help (Contact & support: the form from `Shared/Support`, sent to the account
server's `feedback` collection, which emails Patrik), About (Privacy and Imprint open `LegalPage` in the app's language, Fonts & licences shows the OFL texts from
`Shared/Fonts` and an app's own licences, `SettingsApp.licences`: Aresium's shop list, Version), Account (the email from the login answer, `EmpireSession.email`; Change password; Log out
"in all Ares apps on this iPhone", which does what the app's log-out did before; then, in the hub's soft red, Leave
<app> and Delete Ares account: pages in `Shared/Design/AccountScreens.swift`, see "Accounts in every app" below). An app
whose server keeps data per account passes its `DELETE …/me` as `SettingsApp(serverData:)` (today only Arestemis:
`ArestemisAPI.accountDataURL`); leaving deletes it there first. An app that works without an account
(`EmpireAppIdentity.accountOptional`, only Aresium, brief 22) shows, while no Ares app is logged in, a quiet "Ares
account" section last instead: Sign in (`Shared/Design/SignInSheet.swift`, the login without Create account) and the
app's line `SettingsApp(signInNote:)`; signed in, the account section as everywhere (Leave <app> only while the account
has the app). Screenshots: `-openSignIn`, `-openSupport`. Links: `Shared/Settings/SettingsInfo.swift`. Every
login screen ends with "Privacy · Imprint" (`LoginScroll`). Screenshots: `-sampleData -openSheet settings` in every app
(`-scrollToAccount` shows the Account section; `-openFonts` the Fonts & licences page, `-openLicence <name>` one of the
app's own licences). A new app: a gear in its header and `SettingsScreen` in a sheet. The
sheet follows the app's appearance (dark in Aresium's red mode).

## Light mode (every app, 2026-10-25)

Decided 2026-10-24 (Patrik: part of the standard design, before any new app); built 2026-10-25 for all five apps and
both widgets. **Settings → General → Appearance**: Like the iPhone (default) / Light / Dark, each app its own choice
(`Shared/Settings/Appearance.swift`, page `Shared/Design/AppearanceScreen.swift`); it switches at once, open sheets with
it, no restart.

- **Colours are light/dark pairs.** `Color(light:dark:)` (`Shared/Design/EmpireDesign.swift`) resolves as it draws
  (nonisolated: SwiftUI resolves some colours on its render thread during animations, 2026-10-27).
  `Ink` (background, primary, secondary, muted, line, grid, card, card2, press, field, edge, shadow), `AppAccent.color`
  (a deeper shade on the light wall, at least 4.5:1; `AppAccent.onColor` for words on an accent fill),
  `StatusTone.activeColor`/`issueColor`, `FormButtonStyle`, `LoginStyle.standard`. The light values are Aresium's
  website light theme (`aresium/web/public/index.html`, `html[data-theme="light"]`), except `Ink.muted` (darker, for
  small text). A screen built from them needs nothing else; a colour no token covers gets its own pair, named for its
  meaning. Never `.white`/`.black`/`Color(hex:)` for ink or surfaces, never a material pinned dark.
- **The root sets the look on the window** (`AppRoot` → `overrideUserInterfaceStyle`). Screens never call
  `preferredColorScheme`: SwiftUI fixes a sheet's look when the sheet opens, so a sheet open during a switch stayed in
  the old look (seen 2026-10-25). A mode with its own colours holds the window in one look with `holdsColorScheme(_:)`
  (Aresium's red mode: dark); `\.appearanceScheme` is the look to return to (the choice, or the iPhone's own, read
  from the screen, which the window's look does not change).
- **Widgets follow the home screen** (light or dark like the widgets around them), not the app's choice; Aresium's
  also shows its red mode (`WidgetSnapshotStore.redMode`, `AresiumWidgetLook`).
- **Aresium:** light or dark is the shared appearance; the sun button in its header switches it (writes the choice);
  red is Aresium's own mode over either (`ThemeState.red`, remembered), entered and left with the band.
- **Empire app: the marble hall** (light): ivory wall, antique gold (`EmpireStyle.goldText`/`goldName` as pairs), the
  bust laid in with multiply, parchment coins, a plain gold chronicle line with amber dust. The phone hub's greys keep
  their exact dark value at each place and take their role's light value (`EmpireStyle.title/heading/body/quiet/icon(dark:)`).
- **Screenshots:** `-appearance light|dark` (a launch argument read as the saved choice), or the simulator's own look
  with `xcrun simctl ui <device> appearance light|dark` (for "Like the iPhone" and the widgets); `-openSheet settings
  -openAppearance` shows the page. Aresium: `-sampleRed` for red mode (`-sampleLight` is gone; use `-appearance light`).
- Tests: `EmpireTests/AppearanceTests` (the choice, the pairs, contrast of the light accents and status colours on the
  light wall), Aresium's `ThemeStateTests` and `WidgetTests`.

## Open (2026-10-26)

All five apps (Aresium, Empire, Arestemis, Aresus, Arestoteles) work on the simulator and are merged; nothing reaches
the phone until Apple approves the developer account.

**Order of the big steps** (Patrik, 2026-10-25; also in `ares-empire/EMPIRE.md` → Now and next): light mode (done
2026-10-25, "Light mode" above) → TestFlight once Apple approves (1–3, 6) → Aresium for other people (5) → Aresync file sharing from the phone (11, on
hold) → new apps. Next up (2026-10-26): the plan for Aresium for other people. The other items fit in between.

1. **TestFlight, once Apple approves:** set the paid team (project level, all five projects); the App Groups
   `group.de.ares-empire.aresium` + `group.de.ares-empire.shared` registered for the bundle ids, the widgets' too
   (`de.ares-empire.aresium.widget`, `de.ares-empire.aresus.widget`) (Xcode's automatic
   signing can do it; the shared Keychain group needs only the team prefix); an App Store Connect record per app;
   Release build for a generic device; archive and upload each (README). For people besides Patrik: external
   testing with a public TestFlight link per app, entered as `install` in `ares-empire/webauth/apps.json` (the Empire
   app's Install button shows it to accounts that have the app).
2. **On the phone:** the checks in `docs/reviews/2026-10-23-pre-testflight.md` (widgets incl. row taps), the shared
   login across the apps on the real device, the Empire app opening Aresium (`aresium://`), no connection; the
   Aresus widget placed on the home and lock screen (refreshes by itself, the medium one's rows open their province).
3. ~~**Council over the Empire app before its first upload**~~: done 2026-10-25, "Corrected"
   (`docs/reviews/2026-10-25-empire-app.md`); fixes merged and the servers deployed. Left from it: 12 and 13 below.
4. Hub data, not this repo: Aresium's "About" on the hub (`data/state.json` on the server, `lock: true`, so the sync
   never refreshes it) is outdated (Next.js, Prisma); Patrik has not decided yet whether to rewrite it.
5. Later (decided): Aresium for several users, then Aresium `open` in the hub catalog. **Other people's Aresium data
   stays on their iPhone** (Patrik, 2026-10-25: imports, categories and storage on the device; no bank data on the
   server; Patrik's own stays on the server for aresium.de). Its section in the privacy policy says so before it opens.
   Plan: `ares-empire/docs/ARESIUM-FOR-OTHERS.md`. **Phone mode is built** (briefs 15 and 18, 2026-10-27; "Aresium phone
   mode" under Setup state): data, engine, imports, categories, sorting, the screens in both languages; logout keeps the
   data. **No account needed** (brief 22, 2026-10-27): it opens without a login on the phone's one store, with an
   optional lock (Face ID and/or an own code); the login is only for Patrik's server mode. Before it opens (plan part 7): the privacy policy's Aresium section, the App Store information, external
   TestFlight, then `open` in the hub catalog.
6. **Push, once Apple approves** (`ares-empire/docs/PUSH.md` → Operating): create the APNs key (.p8) in the developer
   portal, put it on the server, set `APNS_KEY_ID`/`APNS_TEAM_ID`, restart `empire-push`; enable the Push Notifications
   capability for Arestemis, Aresus and the Empire app, Time Sensitive for Arestemis and Aresus (entitlements are
   already in the projects). Then check on the phone (the Empire app: "<App> is ready" for a member's account, its tap
   showing the ring) and retire Telegram: Arestemis (`TELEGRAM_*` in /root/Arestemis/.env) and Aresync (`TG_*` in each
   config).
7. ~~**Windows laptop:** an Aresus machine token for `Notebook-Patrik`~~: done; its token is on the server and its
   PowerShell report works (three daily runs 2026-10-24 to 26, all `ok`, checked in the Aresus database 2026-10-26).
8. **Build 2026-10-24 record:** `docs/build-2026-10-24/STATUS.md` (what was built, decisions, live tests). Built after the main work: the Aresus
   widget and the hub's live lines from Aresus.
9. **Arestoteles on the phone:** check the Discuss hand-off (`DiscussPrompt.target`, now `https://claude.ai/code`: does
   the Claude app open, and how to start a session there with the copied prompt); replace the bust (the website's
   `aristotle-bust.png` has a faint "Magnific" watermark); a widget with a position to revisit (needs a widget target).
10. ~~Light mode~~: built 2026-10-25 (section "Light mode"). On the phone, check both looks once TestFlight runs
   (the iPhone switching by itself in the evening while an app is open, the widgets on a light and a dark home screen).
11. **Aresync file sharing from the phone** (Patrik, 2026-10-25): on hold; Patrik will say what it should do when it
   comes up. Don't ask before then.
12. **Before anyone but Patrik gets an app** (council 2026-10-25): ~~log out centrally~~: merged 2026-10-26 (brief 09,
   "One login for all apps" below; on the phone: check a widget and a notification after logging out in another app).
   ~~A privacy cover in the app switcher~~: built 2026-10-26 ("App switcher cover" below; on the phone: check the
   switcher card and Control Center once TestFlight runs).
   (Installing a missing app from the Empire app: built 2026-10-25, the page's Install from the hub's `install` link.)
13. **For Patrik to decide** (council 2026-10-25): (a) ~~should a member's ring show every province the account has
   access to~~: decided 2026-10-25, yes (the "Empire app" entry below). (b) What makes the Empire app worth having
   over the mobile website: members are told "<App> is ready" by a notification (2026-10-25); Patrik's sign-ups and
   requests stay email plus the approvals sheet, no push to him (Patrik, 2026-10-26). Opening offline (the last hub
   kept on the phone): not now, later (Patrik, 2026-10-26).

14. **Arestemis sample with real details:** `Arestemis/Arestemis/Samples/settings.json` (and Arestemis's `docs/samples/`)
   holds Patrik's real application text (name, TUM, Garching, age), so the showcase leaves that screen out. Replace it
   with a made-up text if Patrik wants that screen shown (offered 2026-10-26).

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
  paid team once approved. Launch argument `-sampleData` shows the server's bundled sample (`-scrollToEnd`: the start
  screen at its band); every sample runs on `SampleAccount`'s made-up account server, signed out
  (`-sampleSignedIn`: signed in).
- Test fixtures `AresiumTests/server-dashboard.sample.json` + `.expected.json`: the Aresium server's sample and
  the website's answers for it. When `/api/data` changes: `npm run sample` in aresium, then
  `node scripts/aresium-fixtures.mjs`.
- Empire app fixtures (2026-10-25): `Empire/EmpireTests/ServerSamples/` (every hub answer and error, made by the hub's
  own code, `ares-empire/tools/empire_samples.py`; `ServerSamplesTests`) and the sample mode's `Preview Content`
  (admin, member). When the hub API changes: `bash scripts/empire-fixtures.sh`.
- **Two projects, one shared folder** (2026-10-24): `Aresium/Aresium.xcodeproj` and `Empire/Empire.xcodeproj`
  (bundle id `de.ares-empire.empire`, made with `scripts/new-app-project.py`). `Shared/` (Empire login, network
  layer, `AppFont`, fonts, `EmpireShared`) is compiled into every app (and the Aresium widget, for the fonts).
- **One login for all apps:** the token is a Keychain item in the group `$(AppIdentifierPrefix)de.ares-empire.shared`
  (every app's entitlements + `AppIdentifierPrefix` in its Info.plist), the fresh-install wipe keys off the App
  Group `group.de.ares-empire.shared` (deleted by iOS only with the last Empire app). Rules in
  `Shared/Auth/EmpireSession.swift`: an invalid login (401, refresh refused) logs out everywhere; an account without
  this app's service, or a 403 from the app's server, closes only this app (`access = .denied`, the app forgets its
  data via `onAppDataReset`); a failed new login never ends an existing one. **Aresium works without it** (Patrik,
  2026-10-27, brief 22; `EmpireAppIdentity.aresium.accountOptional`): no login screen; any login, or none, opens it, a
  login without the `aresium` service is not denied, and only its server's 403 denies (which means phone mode there). A refusal counts only for the login it
  was made with: every caller passes the token it sent (`handleAuthFailure(_:generation:token:)`), so a late 401 for
  an older token (one renewed or replaced in another app) changes nothing, and a 401 deletes the saved login only
  while it is still the refused token (council 2026-10-25). Only a 403 with the code `no_access`, or none, closes the
  app; other codes (`admin_only`) only refuse that request (`HTTPError.forbidden`), and a 503 shows the server's own
  sentence (`Shared/API/HTTP.swift`). Coming to the foreground, each app calls
  `followSharedLogin()`: it picks up a login or logout made in another app meanwhile (a renewed token of the same
  account is taken over without a server call); while the app is closed because the account lacks its service, it
  asks the account server again quietly, at most once a minute, so an approval opens the app by itself.
  **Central logout** (2026-10-26, brief 09): the shared App Group holds the saved login's account id
  (`LoginMarker`, key `empire.login.account`; never a token), written whenever a login is saved and cleared when it is
  deleted. It is readable while the phone is locked, so saved data is shown only where it matches: each app checks it
  synchronously on coming to the foreground (`onEmpireForeground` → `followMarker()`, before `followSharedLogin()`),
  the Aresium widget's snapshot and the Aresus widget's status carry their account and are deleted on a mismatch (the
  Aresium widget refreshes at least hourly to notice), Arestoteles's saved vault is checked against it. Each app records
  its accepted push device in the group (`PushDeviceStore`, `empire.push.devices`); the app where the person logs out
  removes every recorded device with the ended login (Aresium and Arestoteles through a cleanup-only `PushCenter`), so
  notifications of apps that are not running stop too (`ares-empire/docs/PUSH.md` → the limit). Every logout is written to the device log with the line that
  asked for it (`log show --predicate 'subsystem == "de.ares-empire.shared"'`; on a simulator via `xcrun simctl spawn
  <udid> log show …`). Verified across the two apps on the simulator with
  `scripts/check-shared-login.sh <udid>` (2026-10-24).
- **App switcher cover** (2026-10-26, `Shared/Design/PrivacyCover.swift`): while an app is not active (app switcher,
  Control Center, Notification Center, a system alert) a window of its own above everything, sheets included, shows
  the app's `LaunchBackground` wall with the band that ends its main screen (the app's display name; the Empire app
  passes "THE EMPIRE" in gold, `AppRoot(cover:)`), in the look the app shows. Shown on the scene's `willDeactivate`
  and `didEnterBackground`, faded out (0.18 s) on `didActivate`; it never takes touches. `AppRoot` attaches it to the
  app's window. DEBUG `-privacyCover` keeps it shown for screenshots; the log category `cover` says when it shows and
  hides (debug level: `xcrun simctl spawn <udid> log config --subsystem de.ares-empire.shared --mode
  "level:debug,persist:debug"`). Checked on the simulator 2026-10-26: all five apps in light and dark, and a round trip
  through Safari.
- **Accounts in every app** (2026-10-25, brief F2; contract `docs/build-2026-10-25/briefs/F-accounts-contract.md`,
  server side `ares-empire/docs/ACCOUNTS.md` → Accounts in every app): one Ares account, made and run from any app.
  The login (`AresLogin` in `Shared/Design/ProvinceLogin.swift`, used by the provinces and the Empire app; Aresium has
  no login screen since brief 22, only Settings' `SignInSheet` from the same pieces) says "One Ares account for all Ares apps" and offers Create account (email,
  password twice, optional name; asks for this app's service, sends the app's language; then "confirm your email,
  Patrik approves, an email follows") and Forgot password? (sheets, `Shared/Design/AccountSheets.swift`). Its error
  names an account not confirmed or approved yet too. An account without this app sees the no-access panel
  (`NoAccessPanel`): who is logged in, Ask for access (adds the service to `requested`; reads the account first so a
  request from another app is kept), then "Asked …"; Log out. Settings → Account: Change password (the app logs in
  again with the new password at once and saves that login for all apps; while it does, a 401 of an older request is
  no logout, `EmpireSession.isChangingPassword`; if that login fails the page offers Try again, and leaving it logs out
  with a line), Leave <app> (the app's server data first, then `POST /api/empire/leave`; the session then closes this
  app like a denied one: its data on the phone and its push device go, the login stays; Aresium is not closed and its
  data on the iPhone stays, it only loses server mode), Delete Ares account (password
  checked with a login first, then a confirmation, then `DELETE` with that login; logged out everywhere with a calm
  line, `EmpireSession.notice`). Logic in `Shared/Auth/EmpireAccountClient.swift` (calls, PocketBase errors → one line,
  `AccountFailure`) and `AccountForms.swift` (one model per action, on the session's transport); tests in
  `EmpireTests/AccountTests`. Nothing changes on the phone until the server said yes; a 401 logs out everywhere, any
  other failure leaves account and login as they were. Sample mode (`-sampleData`) only pretends; leaving or deleting
  there ends the sample. Screenshots (DEBUG, every app, `SampleAccount`: a made-up account on a fake account server,
  never the real one): `-sampleLogin`, `-sampleNoAccess`, `-sampleAccessAsked`, `-sampleAccountDeleted`; on the login
  `-openSheet createAccount|forgotPassword`; in Settings `-openAccount changePassword|leave|delete`; any form's state
  with `-accountPhase <state>` (sending, done, notSent, sent, asking, asked, changing, loginFailed, leaving,
  dataDeleted, checking, confirming, deleting, or a failure: offline, tooMany, wrongPassword, wrongCurrent, emailTaken,
  refused (the server's sentence, `-accountMessage <text>`), …) and `-accountEmail <text>`. The admin account cannot
  leave an app or delete itself: the account server answers 403 with a sentence in the app's language, which the page
  shows (`AccountFailure.refused`; only for leave and delete, where the server explains its refusals). The Empire app: `-sampleData -openSheet approvals`. Screenshots of every sheet and
  state in both languages: `build/screens/` (2026-10-25).
- **Empire app** (2026-10-24): the approved phone hub (`ares-empire/web/app/mobile.jsx` + `mobile.css`) in SwiftUI,
  `Empire/Empire/Screens/` (Claude's look; values copied from the CSS, with the CSS selector named in comments), data
  in `Model/` + `API/` (brief 08). Launch arguments (DEBUG): `-sampleData` (admin sample), `-sampleUser` (member
  sample), `-sampleCatalog` (a member made up from the admin sample's provinces: Arestemis in the ring with an install
  link; in "+" Aresolus to ask for, Aresync asked for, Aresium coming soon), `-samplePush` (push routing in sample
  mode, for `simctl push` with `Empire/PushSamples/app-ready.apns`; the sample never signs in, so nothing registers), `-openSheet province|unopened|idea|add|approvals|support` (`add`:
  the "+" sheet), `-tapProvince <slug>` (the ring tap at launch), `-scrollToEnd` for screenshots. Screenshots of the
  new states: `-sampleData -sampleCatalog -openSheet add` (the "+" sheet), `-sampleData -sampleCatalog -openSheet
  unopened` (the page with Install). **Whose ring shows what** (Patrik, 2026-10-25, `ares-empire/docs/EMPIRE-APP.md`):
  the ring is `projects`, every app the account has (Patrik: every province); members get a "+" card ("More apps") at
  the end, whose sheet lists `addable`, the other apps open to users, each with its state on the right: Ask for access
  (a quiet gold button; `POST /api/empire/request`, whose answer is the new hub data, so the row then says "Asked ·
  waiting for approval"; a refusal shows the hub's sentence), or Coming soon (not requestable). There is no adding or
  removing any more (the old `POST /api/empire/ring` is gone from the app); leaving an app is Settings → Leave. Each
  province's `access` (`granted` | `requested` | `none`) and `install` (its TestFlight or App Store link, only for apps
  the account has) are read leniently: a hub without them, or an unknown value, counts as granted in the ring and not
  asked for in "+" (`EmpireData.init(from:)`), no install link. Ring: tap the front province to open it (its app if
  installed, else its website, else its page with "The … app isn't on this iPhone" and, when the hub sends an https
  install link, **Install**), hold any tab for its page; on the page the name is the link (Patrik, 2026-10-24).
  **Notification** (2026-10-25): a member whose request Patrik approved gets "<App> is ready" (`url` `empire://ring`,
  thread `access`, no actions); tapping it closes any sheet and asks the hub again, so the new app is in the ring
  (`EmpireLink`, `EmpireNavigation`, which `ContentView` owns so a tap works before the hub has loaded; `onChange(…,
  initial: true)` so a tap that launched the app is not missed). The app declares no URL scheme: links come only in
  the payload. No push to Patrik: his sign-ups and access requests come by email and he decides in the approvals sheet
  (Patrik, 2026-10-26). `ProvinceOpener` tries the app's URL and uses iOS's answer, so no
  scheme is declared anywhere (no `LSApplicationQueriesSchemes`; a new province app needs no change here). Province marks load from the hub with the
  Bearer token, so the samples show monograms. Approvals list new sign-ups and approved accounts asking for more apps
  (`PendingAccount.requested`/`approved`), each with the apps asked for and "Email not confirmed yet" while `verified`
  is false; approving sends the apps the card shows (`requested`), and the hub's answer carries the list and the count
  (`DecisionAnswer`; an older hub's `{"ok": true}` makes the app ask for both). A failed decision asks for the list
  again. `pending` is null when the hub could not count (no badge). A hub answer that does not decode is logged by its
  key path (`log show --predicate 'subsystem == "de.ares-empire.shared" && category == "decoding"'`).
- **Contact & support** (2026-10-24, brief E5): `Shared/Support/`, the form every app's Settings → Help opens
  (`SupportSheet(session:accent:sample:)`): a kind (Problem, Idea or wish, Question, Something else) and a message,
  posted with the Empire token to the account server's `feedback` collection, which mails it to Patrik
  (`ares-empire/docs/ACCOUNTS.md` → Contact & support). Logic in `SupportForm`/`SupportMessage`/`SupportAPI` (tests in
  `EmpireTests/SupportTests`); a 401 logs out, a 429 says "too many", a 403 never closes the app; sample mode only
  pretends. Screenshots (DEBUG, any app showing the sheet): `-supportKind <kind>`, `-supportText <text>`,
  `-supportPhase sending|sent|offline|tooMany|loggedOut|other|invalidEmail`, `-supportEmail <text>`. **Without a login**
  (brief 22, only an app that works without an account, Aresium; `SupportForm.sendsWithoutLogin`): the form also asks
  for an email to answer to and an optional name, and posts a `ContactMessage` without a token to the account server's
  open `contact` collection (the website's form's; `name`, `email`, `message` with the footer "— Aresium <version> ·
  iOS … · <topic>", `language`, the empty honeypot `website`; 5 an hour per address). Tests in
  `AresiumTests/SupportContactTests`. The account server's mail for it still says "the website's contact form"
  (`accounts/pb_hooks/contact.pb.js`); the footer names the app.
- **Push** (2026-10-24): `Shared/Push/` (`PushCenter`, `PushAppDelegate`, tests in `EmpireTests/PushCenterTests`)
  registers devices with the Empire push service (`ares-empire/docs/PUSH.md`; dry run until the APNs key). Wired into
  Aresus, Arestemis and the Empire app (`@UIApplicationDelegateAdaptor(PushAppDelegate.self)` in the App, `push.start`
  + routing of `openedURL` in ContentView, never in samples/tests); each needs the Push Notifications capability (paid
  team; `aps-environment` is in their entitlements) and, for time-sensitive notifications, the
  `com.apple.developer.usernotifications.time-sensitive` entitlement (Arestemis, Aresus). Nothing in Shared may use
  `UIApplication.shared` (the Aresium widget compiles Shared too).
- **Aresus app** (2026-10-24, `Aresus/`): two tabs, Aresus (summary, server card, province boxes, province page) and
  Aresync (machines, runs by day, run sheet), on the Aresus API (`aresus/docs/API.md`, samples in
  `Aresus/Aresus/Samples/` = copies of `aresus/docs/samples/`). Data in `Model/` + `API/`, look in `Screens/` (Shared/Design).
  Links `aresus://province/<slug>`, `aresus://sync/run/<id>`, `aresus://server` go through `AresusNavigation.open(_:)`
  (notification taps too). Launch arguments (DEBUG): `-sampleData` (`-sampleAllGood`,
  `-sampleEmpty`), `-tab aresus|aresync`, `-openProvince <slug>`, `-openRun <id>`, `-scrollToEnd`, and `-sampleLoading` for the loading screen (the login screens: the
  shared `-sampleLogin` and friends, "Accounts in every app"). Sample mode runs its clock from the samples' moment, so times read as live.
  **Widget** (`AresusWidgetExtension`, kind `AresusStatus`, `de.ares-empire.aresus.widget`; small, medium, lock-screen
  rectangular and circular): "All running" or the issues, with the check's live age. Its timeline provider reads the
  shared Empire token (never logs in), fetches `GET /overview` every 15 min and saves a `WidgetStatus` in the App Group
  (`aresus-widget-status.json`); the app saves it after every overview and deletes it on logout. Offline, or with the
  Keychain locked (the token is readable only while the phone is unlocked), it shows the saved status; after an hour it
  loses its status colour. `Aresus/AresusShared/` is compiled into app and widget (overview types, API client core,
  widget status, store, loader, views). DEBUG `-widgetGallery good|issues|loggedout` shows the views for screenshots.
  `AresusUITests` (UI tests, in the scheme): Settings → Language switched both ways with the real taps, about a minute.
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
  `-sampleSlowSearch` (the server's search answers after 3 s), `-tab positions|topics|library|search`,
  `-library mechanisms|events|questions|actors`, `-search <query>`, `-tabSearch <query>` (in the field of the tab
  `-tab` opens), `-openBestMatch <n>` (taps the n-th best match), `-openNote <id>[#<heading>]`, `-openPosition <id>`,
  `-openSheet brief|edit|quicknote|discuss|discussions|reword|change|drop|add|evidence`, `-scrollToEnd` (Positions), and `-sampleVaultFile <path>` (a
  vault saved from the server instead of the made-up sample, to look at real notes; DEBUG only, never committed).
  **For lookups (Patrik, 2026-10-24):** position cards show the position's `title` (the bold part) cut to one line of
  thought (`Lookup.cardLine`); a position page offers Discuss (now, or "later" onto the vault's to-discuss list), Edit
  (wording) and Note (into the Inbox, about the position); no change/drop on the phone. Long notes open with their
  sections closed (`NoteBody`), with Figures & dates, Sources and Terms (`LookupPanel`), search shows sentences first,
  and pressing a paragraph or list item edits just that passage (the server's block `lines`).
  **Search (2026-10-24, build E2):** Positions, Topics and Library each have a search field over their own items
  (`TabSearch`, `VaultSearch`'s matching; the Library shows every kind while a query is typed). The Search tab puts the
  server's best matches (`GET /search`, by words and meaning; `BestMatches`: asked once typing pauses, a newer query
  cancels the older, 5 s timeout, nothing shown on failure) above the device's results; sample mode answers every
  query with `Samples/search.json`.
- **Aresium phone mode** (2026-10-27, briefs 15, 18 and 22; plan `ares-empire/docs/ARESIUM-FOR-OTHERS.md`): everyone
  but Patrik keeps their Aresium data on their iPhone. **No account** (Patrik, 2026-10-27, brief 22): Aresium opens in
  phone mode on the phone's one store at once, without a login and without waiting for any server (`ModeStore.start`);
  the first run or the dashboard. **Server mode** stays for the owner through the shared Ares login: while a login
  whose account has the `aresium` service exists, the app asks `GET /api/mode` once per session and remembers the answer
  per account id (`aresium.mode.<id>` in the app's defaults): `server` → today's server dashboard (`ServerBackend` on
  `APIClient`); `phone`, 401 (logs out everywhere), 403 (remembered as phone), an error or offline without a
  remembered answer → phone mode. A remembered `server` works offline, at launch too (the saved login's account from
  the marker; `ModeStore` starts there, so the phone screens never flash for Patrik). When that login ends (a logout
  here or elsewhere, the central logout's marker, the server's 403, leaving Aresium) the app goes back to phone mode:
  the server dashboard and its widget numbers go (`DashboardStore` clears only server data), the phone's store is
  untouched. Phone mode (`PhoneBackend`) reads bank files, sorts and builds the same `Dashboard` with the shared engine,
  the server's own TypeScript (`aresium/src/engine`) bundled as `Engine/aresium-engine.js` and run in JavaScriptCore
  (`AresiumEngine`, an actor with one `JSContext`). `DashboardStore`, `TransactionDetailStore` and `ImportStore` go
  through `AresiumBackend` and never know which. **Storage:** SwiftData, one store per iPhone in `Application
  Support/Aresium/local/ledger.store`, file protection complete (`PhoneLedger`, `PhoneStorage`): accounts, payments
  (unique by account, source and `externalId`; who set the category), chosen categories, learned merchants, the CSV
  layouts the person confirmed. **Moving over** (builds before 22 kept one store per account in `Aresium/<account
  id>/`): when there is no `local/` store, the most recently changed older store (its newest file) is moved (never
  copied) to `local/` at the first open; with several, the others stay untouched where they are (logged, category
  `storage`). **Lifecycle:** the data belongs to the iPhone, not to a login: logging in or out, leaving Aresium and
  deleting the Ares account never touch it; it goes only with Settings → Delete Aresium data on this iPhone or the
  lock's "Forgot the code?". Settings → Your data on this iPhone (phone mode): Categories, Export (one JSON file, schema
  1, `Aresium-<date>.json`, through the share sheet), Restore from an export (only into an empty store, all or nothing).
  **The widget snapshot** belongs to the store it shows: phone mode's carries `phone: true` and is shown whoever is
  logged in; server mode's carries its account and follows the marker as before (`WidgetSnapshotStore.readShown`).
  **The lock** (brief 22, `Model/AppLock.swift`, `Screens/LockScreen.swift`, `Screens/LockSettings.swift`): optional,
  off by default; Settings → Lock (both modes): "Lock with Face ID" (Touch ID on such phones; without an own code the
  iPhone's code is the fallback, `deviceOwnerAuthentication`; turning it on or, when it is the whole lock, off asks
  Face ID first) and Own code (set, change, remove; 6 digits; changing and removing ask the current code; with it only
  Face ID or the code opens Aresium, `deviceOwnerAuthenticationWithBiometrics`). The code is kept as a salted
  PBKDF2-SHA256 hash (310,000 rounds, CommonCrypto), with the Face ID switch and the wrong-code count, in one Keychain
  item of Aresium's own group (`$(AppIdentifierPrefix)de.ares-empire.aresium`, named explicitly, since the default
  group is the first in the entitlements, the shared one; `AfterFirstUnlockThisDeviceOnly`). Wrong codes: after 5 wait
  1 minute, then 5, 15, 60 (the count survives a restart; a clock set back never shortens a wait). A file
  `Application Support/Aresium/lock-in-use` marks a lock set in this install: a Keychain lock without it is left from a
  deleted install and is removed. It locks at launch and after more than 10 seconds in the background (`LockTiming`;
  inactive, as under the Files picker, the share sheet or Control Center, never locks). The lock screen is a window of
  its own above everything, the app switcher cover included (`LockWindow`, level alert + 2; the cover is alert + 1),
  shown before the app is seen when it comes back; it is the cover's wall and band with the code pad (a Face ID key
  when Face ID is on; "Forgot the code?" deletes Aresium's data on this iPhone and the lock, and in server mode also
  logs out, so the lock never opens the server's data to someone without the code) or, with Face ID alone, one Face ID
  button under the band where the cover has it. Face ID is offered once by itself when locked and active. A file shared
  into Aresium while locked waits until it is unlocked. While the lock is on, the widgets show only "Locked" (no numbers
  are kept for them: `widget-locked.json` in the App Group). `NSFaceIDUsageDescription` in `Info.plist`, German in
  `InfoPlist.xcstrings`. **Contact & support** without a login: the `contact` path (above). **Push:** Aresium never
  registers a device (only the cleanup-only center that removes the other apps' devices when someone logs out here).
  **Current view:** a category opens this month's payments directly (`CategoryRoute`; the widget's category links too);
  Overview keeps the month list first. **Screens** (`Screens/PhoneScreens.swift` and `Screens/FileCheck*.swift`,
  Claude's look from the dashboard's rows, `CategoryTile`/`DayTile`, and the Settings pieces; ink only): the first run
  (what Aresium does with the data,
  two steps, Restore as a quiet link; it ends with the band), the category picker (the default list by group, nothing
  ticked at first, one's own names; unticking a category with payments asks where they go, Not sorted first), after a
  Switch the alert "Also the other payments from <shop>?" (the count on its button), the store's opening state.
  **An unknown bank's file** (brief 23, Patrik 2026-10-27: most people don't know what a CSV is;
  `Model/FileCheck.swift`,
  `Screens/FileCheckSheet.swift`): a window with the file's name, "Aresium doesn't know this bank yet. This is how your
  payments would look:", the first 3 payments as the dashboard's rows (day tile, who or the text, the whole date, the
  amount; no column names) and "Does this look right?" with Yes, import / No. The readings are the engine's
  (`readingsOfUnknownFile`, up to 4, best first, computed at import and carried by `LayoutRequest`); No shows the next
  one with a line on what changed (`FileCheckWording`: "Day and month swapped", "Money in and out swapped", "Name and
  payment text swapped", …; none for the first shown or a reason without a plain sentence); after the last one (or with
  none) the column check, the last resort (`ColumnCheckModel`, `Screens/FileCheckColumns.swift`): plain questions
  ("Which column is the date?", the amount or two columns for money out and in, the name, the payment text) as menus of
  the file's columns by name and first value, how dates and amounts are written, the first payments read that way,
  Import. Cancel everywhere leaves the file out; only the layout the person confirmed is saved. **Sending the format**
  (`Model/BankFormatShare.swift`, `Screens/FileCheckSend.swift`): when a file is read with a confirmed layout whose
  `shareableLayout` is ok (else nothing is offered and only the engine's reason is logged, category `formats`), the
  import's result shows one quiet card, "Help Aresium learn your bank": the bank's name (the engine's name for it as a
  suggestion when it has one; for an unknown file it has none today) and Send (the keyboard's Send too); "What is
  sent?" opens the format as `SharedFormat` shows it (every column with what it holds, date and number style, separator,
  any other setting, the name, the app's version and language). Send posts `{bank, layout, app_version, language}` to
  the account server's `bank_formats` (`BankFormatAPI`, no token, `Accept-Language` of the request; ares-empire
  `docs/ACCOUNTS.md` → Bank formats). Not now, closing the result and Send each mean the layout is never offered again
  (a SHA-256 of its separator and header in `Application Support/Aresium/bank-formats.json`,
  `PhoneStorage.bankFormatsURL`,
  deleted with Aresium's data). Offline or a server error: kept in the same file (only the request's body and the
  failed tries) and sent by itself at the next start or foreground (`BankFormatOutbox.sendWaiting`, one round a
  minute), at most 3 tries (a try without a connection does not count); a 400 is final (a card still on screen shows
  the server's sentence; a 400 about the name only lets the person type it again); a 429 waits for the next start.
  Sent: "Thank you. Aresium learns your bank with the next update." Sample mode only pretends. The dashboard's own
  "Uncategorised" (engine and server) shows as "Not sorted" in both modes and the widget through `CategoryName.shown`
  (AresiumShared); Switch, Add, routes and links keep the real name. Settings →
  About → Fonts & licences also lists the shop list's name-suggestion-index notice (BSD-3-Clause,
  `BundledLicence.shopList`, Aresium only). **Engine:** `bash scripts/aresium-engine.sh` runs `npm run engine` in
  aresium and copies the bundle (its commit in `Engine/engine-version.txt`), the engine's test files and the licence
  notice (`Engine/name-suggestion-index-licence.txt`); the bundle is never edited by hand. Launch arguments (DEBUG):
  `-samplePhone` (a made-up store in a temporary folder, filled through the real import), `-samplePhoneEmpty` (the
  first run; `-sampleChosen` after the categories), `-sampleSignedIn` (signed in on the made-up account server),
  `-openSheet categories|settings`, `-sampleUntick <category id>` (in the picker), `-sampleLayout` (an unknown bank's
  CSV: "Does this look right?"; `-sampleReading 2` the second reading, `-sampleReading columns` the column check),
  `-sampleFormat` (that file confirmed and imported: the result with the send card; `-formatBank <name>`,
  `-formatPhase sending|sent|kept|refused|badName`, `-formatMessage <the server's sentence>`, `-openFormatDetails`
  "What is sent?", `-formatFocus` the keyboard on the name), `-sampleCategory <name> -sampleMonth <YYYY-MM>
  -samplePhoneTransaction <text>` (a payment's detail; `-samplePhoneSwitch <category>` switches it, then the merchant
  question), `-sampleImportResult` (the result
  line); the lock in memory: `-sampleLock faceID|code|both` (the code is 123456), `-sampleUnlocked` (open at launch),
  `-sampleWrongCodes <n>`, `-openCode` (Settings → Lock → Own code), `-openCodeEntry set|change|remove`. Tests:
  `PhoneModeTests`, `PhoneBackendTests`, `PhoneStoreTests` (with the moving over), `PhoneEngineTests`,
  `PhoneLookTests`, `LockTests`, `SupportContactTests`, `CategoryRouteTests`, `FileCheckTests`, `BankFormatTests`.
  Screenshots of every phone-mode screen in both looks and languages, and at the largest text size: `build/18-*.png`
  (2026-10-27); without an account and the lock: `build/22-*.png`, contact sheet `build/22-sheet.png`; the unknown
  file's window and sending: `build/23-*.png`, contact sheet `build/23-sheet.png`.
  **"How do I get my file?"** (brief 24, Patrik 2026-10-27: he did not know how the first time): the per-bank steps of
  brief 19's research, now in the app (`Guide/bank-steps.json`, one copy; how it was researched and what is unsure:
  `docs/bank-export-guide/README.md`; `Model/BankGuide.swift`, `Screens/BankGuideScreens.swift`). A list with a search
  ("Your bank": every typed word starts a word of a bank's names, or a name is among the typed words, `BankSearch`),
  Another bank always last; a bank's page: Website / App (only places with steps; for the other one line, "doesn't work"
  or "Aresium knows no way" when no source describes one), the numbered steps, the quiet line "a button may be called a
  little differently" below high confidence, which file (the bank's labels as chips) and why, Good to know (the limits),
  how the file gets to Aresium (the bank's `toAresium` ways, the usual one open), Choose file (the import picker; in
  phone mode the category picker first while none is chosen; the files are imported once the guide has closed). No
  sources and no format names in the screen's own sentences (`BankGuideTests` checks the data). Opened from the first
  run (a link under the import step), an empty dashboard page and Settings → Help → Get the file from your bank
  (`SettingsScreen`'s `help` slot, Shared). **The tour** (brief 24, `Model/TourModel.swift`, `Model/TourData.swift`,
  `Screens/TourScreens.swift`): offered as "Look around first?" on the first run and Settings → Help → Tour of Aresium,
  never by itself. The real dashboard (`DashboardStack`, the same view as the person's, on its own `DashboardPlace`) on
  `TourWorld`: a store in `tmp/aresium-tour-<uuid>/` filled through the real import with `TourData` (a made-up VR Bank
  file, this month always full), its own session (never logged in) and widget numbers inside that folder; the person's
  store, categories and learned shops are never opened. The folder is deleted on End tour (always on the card), at the
  end, when a widget's link or a shared file opens the app, and at the next launch if the app was closed during a tour
  (`removeLeftovers`). Ten steps (`TourStep`), each pointing at a real control (`.tourAnchor`, anchor preferences;
  `.tourSpotlight` on each screen and sheet draws the veil in the wall's colour and the ink ring, and keeps taps off the
  rest except at the swipe step; `.tourCard` the glass card with Next and End tour); a step goes on when the person does
  the thing (`TourModel.update`, `importTapped`, `paymentRecategorised` through `DashboardStore.onRecategorised`) or taps
  Next, and Next gets the step's screen ready (`prepare`). In the tour the gear opens the tour's own Settings (only
  Categories), the import button only answers its step, the band does not enter red mode. VoiceOver: the card takes the
  focus at each step, the highlighted control stays reachable; Reduce Motion: the ring jumps, nothing slides. Launch
  arguments (DEBUG, with `-samplePhone` or `-samplePhoneEmpty`): `-openGuide list|<bank id>` (`-guidePlace
  app|website`, `-guideSearch <text>`, `-scrollToEnd` the page's end), `-tour <1–10>` (`-tourSettings`: its Settings open). Tests: `BankGuideTests`,
  `TourTests`. Screenshots: `build/24-*.png`, contact sheet `build/24-sheet.png`.
- Targets: `Aresium` (app), `AresiumWidgetExtension` (widgets, folder `Aresium/AresiumWidget/`, embedded in the
  app), `AresiumTests`. `Aresium/AresiumShared/` is compiled into both app and widget (theme, `AppTheme`, `AppGroup`,
  widget snapshot); everything else belongs to one target. App Group `group.de.ares-empire.aresium` in both
  entitlements files (on the simulator Xcode embeds them as "simulated" entitlements; on the phone it needs
  the paid team).
- `Aresium/Aresium/Info.plist` holds only what build settings cannot (document types: the share sheet offers
  "Aresium" for `.csv`/`.xml` exports and MT940 `.sta`/`.mt940`, an imported type `de.ares-empire.aresium.mt940`; not
  `.txt`, which iOS knows only as plain text, so Aresium would be offered for every text file; `.txt` statements are
  picked inside the app); it is merged with the generated plist and excluded from the folder's resources in the project
  file.
- **Privacy** (2026-10-24, brief E6): each app and widget folder has its `PrivacyInfo.xcprivacy` (what it collects,
  the required-reason APIs its Release binary really imports); each app's `Info.plist` has
  `ITSAppUsesNonExemptEncryption = NO`. A new data type or API means updating the manifest, `docs/APP-STORE.md` (App
  Store Connect's answers, TestFlight test information, what is missing) and `ares-empire/docs/PRIVACY.md`.
- **Showcase images** (2026-10-26): `showcase/<app>/NN-name.png`, each app's main screens inside a drawn iPhone, with
  the sample data only, for display (portfolio, website); `showcase/README.md` lists them with captions. Refresh with
  `python3 scripts/showcase.py [app ...]` (builds the apps, uses its own simulator `claude-showcase` and deletes it,
  about 6 min for all five); the shots and their launch arguments are the `SHOTS` table in the script. After a screen
  changes, re-run that app and look at its images (and `build/showcase/contact-sheet.png`) before committing.
