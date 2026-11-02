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
- **Nothing that moves sits over or under a pathless shadow** (brief 87): `.shadow` on a view gives every layer under
  it a shadow of its own without a path, which Core Animation draws from the layer's pixels in an offscreen pass, again
  in every frame in which anything over that spot changes (a pulse, a spinner, a counting number). On Patrik's iPhone
  (iOS 27.0.1) such a pass came out as a black rectangle the size of the shadow (the hunt card's pulsing dot, builds
  2–4; the simulator never shows it). So: put `.shadow` on a surface, never around content; prefer a shape style's
  shadow (`.fill(color.shadow(.drop(…)))`, no pass, drawn only outside the shape) or a still image (`drawingGroup`,
  drawn once; keep it within the view's bounds, as a `List` row cuts off what is drawn past the row), as `GlassCard`
  does. Check a screen that animates with `scripts/offscreens/offscreens.sh` (`CA_PRINT_OFFSCREENS`): a steady frame
  should list no shadow, mask or group passes.
- **A blur draws straight onto the screen** (brief 67): never put a material (`.ultraThinMaterial`, `GlassCard`'s
  blur) under `.shadow`, `.mask`, `.compositingGroup`/`.drawingGroup` or a blend mode; Core Animation then takes the
  blur inside an offscreen pass. Its shadow is the material's own style (`Material.ultraThinMaterial.shadow(.drop(…))`).
  Arestemis's `edgeFade` is drawn by the wall (`provinceWall()`) instead of masking the scroll view.
- Every app's main screen (the first tab's root) ends with the app's name: `WordmarkScrollView`
  (`Shared/Design/EmpireDesign.swift`) in place of its `ScrollView`; the band scrolls with the content and shows only
  when you scroll down (Patrik, 2026-10-24). Its launch argument for screenshots: `-scrollToEnd` (Arestemis `-scrollBottom`).
- Append a line to the Chronicle in `ares-empire/EMPIRE.md` after meaningful work.
- A good structure is worth more work now: if the app would need a copy of a service's logic or a
  workaround, fixing the service is usually the better call (`~/ares-empire/EMPIRE.md` → "How we build apps").

## Workflow (Codex month, until about 2026-11-20)

**Who gets delegated work (Patrik, 2026-10-26):** design-related work (screens, the look, visual assets) → Claude
agents (the Agent tool); everything else (data, plumbing, scripts, tests, server code) → Codex as below.
This holds for Aresium too (Patrik, 2026-10-31: "codex agents can get all work except design related things, that goes
to claude agents"); the exception of 2026-10-27, Aresium for other people built entirely by Claude agents, has ended.
Briefs in `prompts/`, the agents' rules in `aresium/AGENTS.md` and `AGENTS.md` here. The same rules
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
- German style: "du", plain and short; the app's terms: Suche/Angebote/Filter (Arestemis; the tabs, since 2026-11-01), Problem/Aktiv/Inaktiv
  (Aresus), Buchung/Ausgaben/Einnahmen (Aresium), EROBERT/BELAGERT/… (Empire status words). "THE EMPIRE" stays a name.

## Settings (every app, 2026-10-24)

Every app has one Settings sheet, opened by the gear (`gearshape`) in its header where the account actions used to be:
`Shared/Design/SettingsScreen.swift` (`SettingsScreen(app:session:sample:logOut:) { app's own section }`). Sections: the
app's own (a view-builder slot, built with `SettingsSection` / `SettingsRow`; Arestemis puts its application texts and
hunt notifications there), General (Language; Appearance; Notifications, opening the app's notification page in iOS
Settings, in apps with `sendsNotifications`), Help (Contact & support: the form from `Shared/Support`, sent to the account
server's `feedback` collection, which emails Patrik), About (Privacy and Imprint open `LegalPage` in the app's language, inside the app in Apple's in-app browser (`SFSafariViewController`, closed with its own X), brief 41, `Shared/Design/InAppBrowser.swift`: SwiftUI's own
`openURL(_:prefersInApp:)` presents from the window's root, which iOS 27.0 refuses while a sheet such as Settings is open; Fonts & licences shows the OFL texts from
`Shared/Fonts` and an app's own licences, `SettingsApp.licences`: Aresium's shop list, Version), Account (the email from the login answer, `EmpireSession.email`; Change password; Log out
"in all Ares apps on this iPhone", which asks first (brief 41, `Shared/Settings/LogOutQuestion.swift`: Apple's
confirmation dialog, as Leave and Delete, "Log out?" / "You'll be logged out of all Ares apps on this iPhone.", in an app
that works without an account plus "Your data in <app> stays."; Log out, destructive, and Cancel, which iOS 26 shows as a
popover from the row, cancelled by a tap outside) and then does what the
app's log-out did before (in sample mode it leaves the sample, as before); then, in the hub's soft red, Leave
<app> and Delete Ares account: pages in `Shared/Design/AccountScreens.swift`, see "Accounts in every app" below). An app
whose server keeps data per account passes its `DELETE …/me` as `SettingsApp(serverData:)` (today only Arestemis:
`ArestemisAPI.accountDataURL`); leaving deletes it there first. An app that works without an account
(`EmpireAppIdentity.accountOptional`, only Aresium, brief 22) shows, while no Ares app is logged in, a quiet "Ares
account" section last instead: Sign in (`Shared/Design/SignInSheet.swift`, the login without Create account) and the
app's line `SettingsApp(signInNote:)`; signed in, the account section as everywhere (Leave <app> only while the account
has the app). **Switches** (brief 47, Patrik's phone: in dark mode "on" was a pale ink track under the white knob, so on
and off could not be told apart): `SettingsScreen` gives every switch inside it `EmpireSwitchStyle`
(`Shared/Design/FormPieces.swift`): Apple's switch, on in the app's accent, or for the ink-only apps (Aresium, Empire)
in the Empire's green for on and running (`StatusTone.activeColor`, the colour iOS gives a switch that is on); never
ink. A switch outside Settings takes it with `.toggleStyle(EmpireSwitchStyle(accent:))` (the tour's picture of the Lock).
`AppearanceTests` pins it (a colour, not a grey; the knob shows on it as on iOS's own green). Screenshots: `-openSignIn`,
`-openSupport`. Links: `Shared/Settings/SettingsInfo.swift`. Every
login screen ends with "Privacy · Imprint" (`LoginScroll`), opening inside the app too (`InAppBrowser` as the links'
`openURL`; the Aresium widget compiles it with the rest of `Shared/`). Aresium's Sign in sheet has no such footer. Screenshots: `-sampleData -openSheet settings` in every app
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
  from the window's scene, which the window's look does not change; not from the screen, which still held the old look
  when the iPhone switched while an app was open, brief 36).
- **Widgets follow the home screen** (light or dark like the widgets around them), not the app's choice; Aresium's
  also shows its red mode (`WidgetSnapshotStore.redMode`, `AresiumWidgetLook`).
- **Aresium:** light or dark is the shared appearance, chosen only in Settings → General → Appearance (the header's sun
  button is gone since brief 42);
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

1. **TestFlight** (Apple approved 2026-10-29): **Aresium done**: 0.1 (1) uploaded with `scripts/testflight.sh` and installed
   on Patrik's iPhone through internal TestFlight (group in App Store Connect → Aresium → TestFlight → Internal
   Testing). Build 2 (2026-10-30): the fixes of Patrik's first test (briefs 34–37). Build 3: the picker's scroll, the
   back swipe and the comfort items (briefs 38–41). Build 4 (2026-10-30 evening): own names and the name's page with the
   left swipe, the graph as a setting, Aresium's own messages (briefs 42–46). Build 5 (2026-10-30 night): the payment page with pens, switches readable in
   dark, no cover flash, one shop under changing names, adding up names in a list (briefs 47, 48, 53, 54). Build 6 (2026-10-31): day tiles as dates, the name's months as pages, Settings' work off the main thread, the graph read by sliding and moving away, the header without boxes, the add-up icon fixed (briefs 55–57, fix 58). Build 7 (2026-10-31 evening): the tour in one walk of 18 steps over everything above (brief 59). Build 8 (2026-10-31 night): New category in the change window, the receipt window and Add cash (brief 60). Build 9 (2026-11-01): every category has a side (own categories for income too, "Andere Kategorie …" offers one of the other side, side and offers in Settings → Categories), and every payment counts as it happened, money out as Ausgaben and money in as Einnahmen under its own category (briefs 68–71). Build 10 (2026-11-01): one name per shop (the newest bank line that names it, never a PayPal or card line), search by name, a day's page from a tap on the day graph, unsorted money in shown as Nicht sortiert (briefs 76, 77). Build 11 (2026-11-01): a typed category name that exists is used (offered, ticked or picked), rename every category, delete one's own and remove defaults with their payments sorted again (brief 80; brief 81's selection data inside, its screens in build 12). Build 12 (2026-11-01): select several payments in a category's month list as in Mail and move, add to or rename them at once with one question and an undo (briefs 81, 82); Save in Add asks to leave the current category and about the shop's other payments (brief 83); the engine's sorting and reading round 1 (aresium briefs 84, 85). Build 13 (2026-11-01): sorting round 3 (card spellings, compounds, regional utilities, cars; aresium brief 96) and the local places list from OpenStreetMap, packed and kept loaded (aresium briefs 86, 97; app brief 98), with its ODbL entry in Fonts & licences. Build 14 (2026-11-02): the quick sort, Not sorted gone through name by name, the biggest first, one tap sorting a name's payments and teaching it; offered after an import and as a card on Not sorted (brief 99). Build 15 (2026-11-02): selecting calmer (a tick fades in place, the count changes at once, one short slide in) and selecting by sliding a finger over the rows as in Mail, with the list scrolling at its edges (brief 200). **Arestemis 0.1 (1) uploaded 2026-10-30** (after its comfort items, brief 49). Arestemis build 2 (2026-10-31 evening): Patrik's fine-tuning rounds 1–3, no "KI" anywhere, "Suche starten", no one-account line on the login (`docs/reviews/2026-10-31-arestemis-phone-test.md`). Arestemis build 3 (2026-10-31 night): Settings → Application as rows with the switch, notes and About you pages, settings loaded with the home screen, ImmoScout24 known to the app, "Suche läuft" (briefs 61, 62). Arestemis build 4 (2026-11-01 night): the black corner on the hunt's card (the glass card's blur no longer drawn offscreen, brief 67), German tabs Suche / Angebote / Filter. Arestemis build 5 (2026-11-01 evening): build 4 still showed it; the real cause was the pulse redrawing pathless shadows offscreen every frame, so `GlassCard` draws none (brief 87). Arestemis build 6 (2026-11-02): several hunts and things for sale on Kleinanzeigen: two tabs Suche / Angebote, the Hunts list, the thing search and the thing cards (briefs 113, 114; server briefs 110–117, plan `ares-empire/docs/ARESTEMIS-ANYTHING.md`). Arestemis build 7 (2026-11-02): the sites come from the server (`GET /kinds`), eBay's auctions shown (brief 119). Arestemis build 8 (2026-11-02): sites that cannot serve the chosen delivery greyed and switched off (IKEA Preowned pickup only, Vinted and mydealz shipping only), the OpenStreetMap credit (brief 129; server briefs 124–128). **Aresus 0.1 (1) uploaded 2026-10-31 21:16** (98 tests; the
   Aresync tab included; Arestemis's outage alerts come from the aresus server, brief 64, no app change). **Empire 0.1
   (1) uploaded 2026-11-01 02:13** (306 tests; the uploaded build carries `aps-environment` production) and **Arestoteles
   0.1 (1) uploaded 2026-11-01 02:25** (156 tests; the bust without the watermark, brief 72; Spotlight and backup fixes,
   brief 74); **Arestoteles build 2 uploaded 2026-11-01 03:01** (brief 75: a note closes at once and is sent in the background, the vault prepared off the main thread), after a check of what differs between the simulator and the phone (brief 73: no blocker; its three fixes
   in brief 74, whose Empire part, a notification's tap closing Settings, ships with Empire build 2; later: Preview
   Content and samples are bundled in Release builds of all apps, and a failed write of Arestoteles's quick-note queue
   is not reported). So all five apps reach Patrik's iPhone. App Store Connect records (Patrik, 2026-10-30: Arestemis, Aresus, Arestoteles, Ares Empire),
   each with an internal group that gets every build automatically (Arestemis's checked: Patrik as tester). Original
   list: set the paid team (project level, all five projects; done); the App Groups
   `group.de.ares-empire.aresium` + `group.de.ares-empire.shared` registered for the bundle ids, the widgets' too
   (`de.ares-empire.aresium.widget`, `de.ares-empire.aresus.widget`) (Xcode's automatic
   signing can do it; the shared Keychain group needs only the team prefix); an App Store Connect record per app;
   Release build for a generic device; archive and upload each (README). For people besides Patrik: external
   testing with a public TestFlight link per app, entered as `install` in `ares-empire/webauth/apps.json` (the Empire
   app's Install button shows it to accounts that have the app).
2. **On the phone:** Patrik's first Aresium test, 2026-10-30: `docs/reviews/2026-10-30-aresium-phone-test.md` (PayPal
   counted twice after "also move the others", day-one sorting, the slow category picker; to fix before build 2).
   The checks in `docs/reviews/2026-10-23-pre-testflight.md` (widgets incl. row taps), the shared
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
6. **Push** (`ares-empire/docs/PUSH.md` → Operating): **the APNs key is live since 2026-10-30**: key `22BDWZ79KS` (made by
   Patrik, one key for all apps), on the server as `/etc/empire-push/AuthKey_22BDWZ79KS.p8` (empire-push, 600), settings
   in `/root/ares-empire/push/.env` (600); `/health` says `"dry_run": false`. A copy is in the Mac's Keychain (generic
   password "Ares Empire APNs key (base64 of AuthKey_22BDWZ79KS.p8)", restore with `security find-generic-password -s
   '<that name>' -w | base64 -d`); Apple never offers the file again. The Push Notifications capability (and Time
   Sensitive for Arestemis and Aresus) came with automatic signing: the uploaded Arestemis, Aresus and Empire builds
   carry `aps-environment` production. **Arestemis's push works on Patrik's iPhone** (test notification 2026-10-31), so its Telegram copy is off since
   2026-10-31 (`TELEGRAM_*` in /root/Arestemis/.env commented out). Left: check on the phone the Empire app ("<App> is
   ready" for a member's account, its tap showing the ring). Aresus works on the phone (test push 2026-11-01), so
   Aresync's Telegram is retired (aresync e10dc07: the code is gone; `TG_*` commented out on the Mac and the server). Aresium's own bot (`aresium-bot.service`, its `current` command) was stopped and disabled 2026-10-30
   (Patrik); Aresium's messages are the app's own (planned, see the review of 2026-10-30).
7. ~~**Windows laptop:** an Aresus machine token for `Notebook-Patrik`~~: done; its token is on the server and its
   PowerShell report works (three daily runs 2026-10-24 to 26, all `ok`, checked in the Aresus database 2026-10-26).
8. **Build 2026-10-24 record:** `docs/build-2026-10-24/STATUS.md` (what was built, decisions, live tests). Built after the main work: the Aresus
   widget and the hub's live lines from Aresus.
9. **Arestoteles on the phone:** check the Discuss hand-off (`DiscussPrompt.target`, now `https://claude.ai/code`: does
   the Claude app open, and how to start a session there with the copied prompt); ~~replace the bust~~ (done
   2026-11-01, brief 72: the hub's clean `arestoteles_transparent.png` in the icon, the app, arestoteles.de and the
   hub's ring mark; `showcase/` still shows the old one until `scripts/showcase.py` runs again); a widget with a
   position to revisit (needs a widget target).
10. ~~Light mode~~: built 2026-10-25 (section "Light mode"). On the phone, check both looks once TestFlight runs
   (the iPhone switching by itself in the evening while an app is open, the widgets on a light and a dark home screen).
11. **Aresync file sharing from the phone** (Patrik, 2026-10-25; specified 2026-11-01): send any file or photo from
   Aresus's Aresync tab or the share button to a chosen folder on the MacBook, receipts into Rechnungen with their
   inventory line. Plan: `ares-empire/docs/ARESYNC-DROP.md`. Not built yet.
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
15. ~~**Comfort items for Empire, Arestemis, Aresus, Arestoteles**~~: **built and merged 2026-10-30** (briefs 49 Arestemis,
   50 Aresus with the aresus server's province links, 51 Arestoteles, 52 Empire and Shared 2; the shared undo bar
   `Shared/Design/UndoBar.swift`, since brief 82 also in Aresium: `accent: nil` draws Undo in ink, and
   `UndoOffer(message:)` is a line alone without Undo; no. 18 = option (b), the key says Done). On the phone: try each once. The original
   item (Patrik approved all, 2026-10-30): build each app's
   before its first TestFlight upload, from `docs/reviews/2026-10-30-swipe-and-comfort.md` → "The other four apps":
   Empire 1 (approvals: pull to refresh, Try again); Arestemis 1–7 (undo for Dismiss, actions on Hunt → Latest, Search's
   Save at the top and a kept draft, 44 pt chip buttons, Listings loading on, Add place's keyboard key, a regular "More");
   Aresus 1–3 (Done on the run report, Open on a province's page, the gear on the Aresync tab); Arestoteles 1–4 (ask
   before discarding text in its sheets, the tab bar on note pages, a + for Add a position, undo for To discuss → Done);
   Shared 2 (Create account keeps what was typed) with the first of them. **Arestemis 6 (Patrik's list no. 18, Add
   place's keyboard key): Patrik did not follow it, so explain it to him first and let him choose** (the item has both
   options). Briefs for these say "Patrik's list no. N" so he recognises them.

## Setup state (update as it changes)

- MacBook: Xcode 27.1 with two simulator runtimes (2026-10-23): **iOS 27.0** for all normal iPhones (use this)
  and iOS 27.1, which only supports the foldable "iPhone Duo" (its screenshots came out black). The simulator
  window app is called **DeviceHub** in Xcode 27; `xcrun simctl` works without it.
- Apple Developer Program (paid, for TestFlight; decided in `ares-empire/docs/IPHONE-APPS.md`): **approved
  2026-10-29**, team id `WQN8SHAH9B` (the former Personal Team, upgraded in place; Xcode's cached team list may still
  call it free). Set as `DEVELOPMENT_TEAM` at project level in all five projects and in `scripts/new-app-project.py`.
  Signing is automatic: Xcode made the Apple Development certificate on this Mac, and the App Store builds use Apple's
  cloud-managed distribution certificate (nothing to keep on the Mac). Patrik's iPhone 17 (Developer Mode on) is
  registered: Apple issues no profile while a team has no device,
  so `xcodebuild archive` failed until it was. All five apps (and both widgets) are registered with Apple: the other four by
  a signing-only archive on 2026-10-30 (`scripts/testflight.sh <App> --export-only`, `-allowProvisioningUpdates`), so
  App Store Connect's New App could offer their bundle ids; the signed Arestemis carries `aps-environment` production
  and the time-sensitive entitlement. Uploads: `scripts/testflight.sh <App>` (README → Releasing).
- Xcode project `Aresium/Aresium.xcodeproj` (2026-10-23): app + tests, folder-synchronized groups (new Swift
  files need no `project.pbxproj` edits), bundle id `de.ares-empire.aresium`, iOS 26+. Signing team: `WQN8SHAH9B`
  (project level). Launch argument `-sampleData` shows the server's bundled sample (`-scrollToEnd`: the start
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
  Control Center, Notification Center, a system alert iOS shows by itself) a window of its own above everything, sheets
  included, shows
  the app's `LaunchBackground` wall with the band that ends its main screen (the app's display name; the Empire app
  passes "THE EMPIRE" in gold, `AppRoot(cover:)`), in the look the app shows. Shown on the scene's `willDeactivate`
  and `didEnterBackground`, faded out (0.18 s) on `didActivate`; it never takes touches. **Not behind the app's own
  prompts** (brief 47, Patrik's phone: "Aresium" flashed when turning a setting on): every place that asks iOS for
  something shown over the app calls `SystemPrompt.begin()`/`end()` around it (the notification permission: Aresium's
  `LocalMessageCenter`, the shared `PushCenter`; Face ID or the iPhone's code: Aresium's `AppLock`), and
  `PrivacyCoverRule` holds the cover back on `willDeactivate` while one is up (the background still covers; the app
  switcher opened during such a prompt finds the app already inactive and shows it as it is, the one gap). A new place
  that asks iOS (camera, location, …) adds the same two calls. Tests: `EmpireTests/PrivacyCoverTests`. `AppRoot`
  attaches it to the app's window. DEBUG `-privacyCover` keeps it shown for screenshots; the log category `cover` says when it shows and
  hides (debug level: `xcrun simctl spawn <udid> log config --subsystem de.ares-empire.shared --mode
  "level:debug,persist:debug"`). Checked on the simulator 2026-10-26: all five apps in light and dark, and a round trip
  through Safari.
- **Accounts in every app** (2026-10-25, brief F2; contract `docs/build-2026-10-25/briefs/F-accounts-contract.md`,
  server side `ares-empire/docs/ACCOUNTS.md` → Accounts in every app): one Ares account, made and run from any app.
  The login (`AresLogin` in `Shared/Design/ProvinceLogin.swift`, used by the provinces and the Empire app; Aresium has
  no login screen since brief 22, only Settings' `SignInSheet` from the same pieces) shows the app's mark, the fields and Log in (the line "One Ares account for all Ares apps" under the name went 2026-10-31, Patrik) and offers Create account (email,
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
  (brief 22; since brief 25 **always** in Aresium, also while an Ares login exists, Patrik 2026-10-27: the privacy policy
  handles Aresium's messages like the website's contact form, without accounts). It is a property of the app's identity,
  `EmpireAppIdentity.supportWithoutLogin` (only `.aresium`; `SupportForm.sendsWithoutLogin` reads it), never a check in
  a view; every other app always sends the account-linked `feedback` record. The form also asks for an email to answer
  to (filled with the account's address when one is logged in, editable) and an optional name, and posts a
  `ContactMessage` without a token to the account server's open `contact` collection (the website's form's; `name`,
  `email`, `message` with the footer "— Aresium <version> · iOS … · <topic>", `language`, the empty honeypot `website`;
  5 an hour per address). Tests in `AresiumTests/SupportContactTests` (a signed-in Aresium still posts `contact`). The account server's mail for it still says "the website's contact form"
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
- **Arestemis app** (2026-10-24, build A1): `Arestemis/` (bundle id `de.ares-empire.arestemis`), the hunter for flats and, since
  build 6 (briefs 113, 114, 2026-11-02), things for sale: several hunts, two tabs Suche (the Hunts list, each hunt's page, the
  forms opened from a hunt) and Angebote (New | Searches since brief 133, below), on the Arestemis API (`~/Arestemis/docs/API.md`; samples in `Arestemis/Arestemis/Samples/`, copies of its `docs/samples/`).
  Data in `API/` + `Model/` (one `ArestemisStore`, optimistic changes with rollback), screens in `Screens/` on
  `Shared/Design`. Launch arguments (DEBUG): `-sampleData` (+ `-sampleNoHunt`, `-samplePaused`, `-sampleLoading`),
  `-tab hunt|listings|search` (`search`: the first hunt's form), `-filter new|saved|applied|all`, `-openMatch <id>`, brief 114's
  `-openHunt <id>`, `-openForm <id>`, `-openItemForm`, `-newItemForm`, `-newFlatForm`, `-newSearch` (the kind dialog),
  `-sampleSlowed`, `-sampleNewerKind`; brief 133's `-listings new|searches`, `-openSearch <id>`, `-search <words>`;
  `-openSheet settings|application|rejected|place|describe`, `-scrollBottom`, `-scrollTo size|rent|movein` (the thing form:
  `where`); Settings →
  Application (brief 61): `-openSettingsPage ownText|notes|aboutMe`, `-sampleOwnMode`, `-sampleNoTexts`. Push: the category and
  the link routing are in `Model/Notifications.swift`; `Shared/Push` is wired in ContentView.
  **Search (API version 2, 2026-10-24, Patrik):** Flat or WG / Flat / WG, people moving in, max flatmates, size ranges
  (flat, WG room), areas, cold and warm rent ranges, move-in and temporary offers, portals, extras; every field optional
  except a place and a portal. "Describe it" is a line at the top that opens a sheet (`SearchDraft`, `SearchScreen`).
  **Settings → Application** (brief 61, Patrik 2026-10-31): after Notifications, one card of rows like General's: the
  switch Write automatically (on = `ai`), the row it leads to (Your text, or Notes = `application_notes`, brief 62) and
  About you, each opening a page with one text field (`ApplicationPage`); one draft, saved when the sheet closes. **Sites come from the server** (brief 119, 2026-11-02): `Source` is open (`Model/Sites.swift`), a site the
  app does not know is kept and shown by the server's name (`SourceStatus.name`, `Listing.source_name`, `GET /kinds`);
  the forms' site switches come from `GET /kinds` for their kind (`SiteChoices`; today's lists when there is no answer),
  a site with `ready: false` is greyed with "<site> is not set up yet.", and the thing form's "Include auctions" shows
  only while a chosen site has `auctions`. An eBay auction shows its bid and time left (`DecodingTests`, `SitesTests`;
  DEBUG `-sampleEbayNotReady`). **Delivery** (brief 129, 2026-11-02): `/kinds` says how a site's listings change hands
  (`KindSource.delivery`: IKEA Preowned pickup, Vinted and mydealz shipping; absent or unknown = both); the thing form
  greys a site its delivery cannot serve as one not set up and switches it off at once, also a saved search's and when
  the sites arrive later, never on again by itself (`ItemSearchDraft.switchOffSitesThatCannotServe`); the one line under
  the sites names what is not set up, then the delivery's reason in the server's words ("eBay is not set up yet.
  mydealz and Vinted only ship."). Fonts & licences credits OpenStreetMap (`BundledLicence.townLocations`,
  `Licences/town-locations-licence.txt`; the server looks up thing searches' towns on Nominatim). Sample hunts 4
  (Bookcase, pickup, IKEA Preowned) and 5 (Denimwerk jeans, shipping, Vinted) with matches 33 and 34
  (`DeliverySitesTests`; DEBUG `-sampleDelivery pickup|shipping|either`, chosen in the thing form as a tap would).
  **Page watches** (brief 131, 2026-11-02; server brief 130, plan `ares-empire/docs/ARESTEMIS-ANYTHING.md` → Page watches):
  a third kind, `watch` ("Watch a page" / "Seite beobachten", offered when `/kinds` lists it): an address, the change in
  the user's words, how often (15 min to daily, default 1 h) and an optional name (`Model/WatchModels.swift`,
  `WatchSearchDraft`, `Screens/WatchSearchScreen.swift`, in the thing form's style; a pasted text keeps its first link,
  `WatchAddress.fromField`). The server decides what can be watched: its refusals come as `400` with `field`
  (`FieldRefusal`, `ArestemisStore.searchErrorField`) and show under that field. The card (`WatchLines`,
  `WatchCardText`): the name (own, else the page's title, else the host), the host, what the page says now as its main
  fact, "Checked … · Changed …"; while waiting, unreadable, failing or blocked one quiet line in muted ink (the server's
  note; blocked adds that editing tries again), never an alarm colour. The words name a watch "Beobachtung"
  (`HuntWords`); its third figure is Saved. A found change (`Listing.page`, source `"page"`): the summary as title,
  "Now: …", Added and Removed lines (removed struck through), Open page; Save and Dismiss only. Push category
  `ARESTEMIS_WATCH` ("Open page"). Sample hunts 6 (KALLAX, ok), 7 (AirPods on Geizhals, blocked), 8 (Mensa, ok) with
  matches 35 and 36 (`at_start`); DEBUG `-openWatchForm`, `-newWatchForm` (`-watchURL <text>`, `-watchChange <text>`,
  `-saveWatch`: the sample imitates the server's refusals), `-sampleWatchRead <read>` (hunt 7's state),
  `-scrollToHunt <id>`. Tests: `WatchTests`. Screenshots: `build/131-*.png`.
  **Angebote as "New | Searches"** (brief 133, Patrik 2026-11-02, chosen from three drawn options: with several searches
  the one list with a chip per search was "a little unorganized"; the chips are gone). The tab's header (`ListingsScreen`)
  has the magnifying glass and a segmented switch **New | Searches** ("Neu" | "Suchen"); the part the user picks is
  remembered across launches (`AppNavigation.choose`, `ListingsPartMemory`, key `arestemis.listingsPart`); a
  notification's match opens over New and a hunt's page shows Searches without changing that choice. **New:** every
  search's new listings (`loadMatches(.new)`), grouped under a heading per search (`NewListings.groups`: the search with
  the newest finding first, newest first within it, by `found` then id; `NewGroupHeading`: the kind's mark, the name,
  the hunt card's "● 3 NEW" and a chevron opening that search's listings at New; no headings while the account has one
  search), the usual swipes, a group gone with its last new listing; then "Filtered out" of every search. **Searches:**
  one glass card per search in the Hunts tab's order, paused ones too (`SearchRow`, `SearchRowCard`): the kind's mark
  and name, the new count, "2 saved · 1 applied" ("asked" for things, saved only for a watch, "Paused" first) in a quiet
  line; a kind this build does not know shows its name only. A tap opens **one search's listings**
  (`SearchListingsPage`, `ListingsRoute.hunt`): its name as the title, the magnifying glass for its own listings, New ·
  Saved · Applied/Asked · All (a watch has no Applied, `MatchFilter.choices`; it opens at New while there are new ones,
  else All, `MatchFilter.opening`), its own "Filtered out" (`RootSheet.rejected(hunt)`). A hunt's page's Listings and
  figures open it over Searches (`AppNavigation.showSearch`); the Hunts tab's "All listings" opens the tab as it was.
  The store keeps its lists per search and filter (`ArestemisStore.ListScope`, `list(_:hunt:)`, `matches(_:hunt:)`,
  `rejected(hunt:)`; `selectedHuntID` is gone); deleting a hunt forgets them and the screens ask again. **The search over
  listings** (`ListingSearchPage`, `ListingsRoute.find(hunt:)`; the server ranks, server brief 132, `GET /matches?q=`):
  the place search's field on its glass card (`SearchBox`, shared with Add place), the keyboard up as it opens, the
  hint "Type at least two letters. The best matches come first."; from two letters, 0.3 s after typing pauses, the
  server's answer in its order (`ListingSearch`: a newer query cancels the older, the same words are not asked twice, at
  most 100 characters, 50 results with "More listings match. Another word narrows it down." when there are more); each
  row the usual card with its state (NEW too) and, over every search, the search's mark and name above it; tap, swipes
  and long press as elsewhere; "Nothing found for “…”." / "Nichts gefunden für „…“."; a failure is a calm line with Try
  again. Sample mode imitates the server's search simply (`SampleBackend.findMatches`; the app never ranks). Tests:
  `ListingsTests`; the server's sample answer `ArestemisTests/ServerSamples/server-matches-search.json`. Screenshots:
  `build/133-*.png`.
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
  **Notes go in the background** (brief 75, Patrik's first day on the phone, 2026-11-01: "notes lock me in the note
  creation screen while waiting to be sent"): Save in a note sheet and Later in Discuss call
  `VaultStore.queueQuickNote` (synchronous: the note is written to `quick-notes.json` first) and close at once; the
  store's own task sends the queue in order, holding an iOS background grant (`QuickNoteBackgroundTask`) so a note saved
  just before leaving the app still goes; what is left goes with the next refresh. Success is silent; the tabs'
  "N quick notes waiting" counts only notes that already failed once (`failedQuickNotes`), so it never flashes after a
  Save; a 422 shows the notice and keeps the note under "Not sent yet". **The vault off the main thread** (same brief;
  Patrik: "slight lags initially"): decoding (`ArestotelesAPI.decode`, `@concurrent`), comparing, building
  `VaultIndex`/`VaultSearch`/`TabSearch` and reading/writing `vault.json` run on `VaultWorker` (one serial queue, so a
  logout's delete always follows an accepted save); the main actor only assigns the results after its context and
  `vaultRevision` checks, so a late answer never replaces a newer vault or outlives a logout. Measured on the simulator
  with a made-up vault as large as the real one (80 notes, 305 KB, 540 passages): the main actor's share went from about
  90 ms to under 0.4 ms at a launch from the saved vault, the first download and an edit's answer
  (`TEST_RUNNER_VAULT_TIMINGS=1` with `-only-testing:ArestotelesTests/VaultTimingTests`). The saved vault is now read
  after the first frame, so while it is read (`VaultStore.isLoadingSaved`) ContentView shows the plain
  `LaunchBackground`, iOS's launch screen, not the loading screen (Claude, checked by recording launches: no flash, the
  launch as long as before). DEBUG: `-quickNoteText <text>` fills the open note sheet, `-saveQuickNote` then saves.
- **Aresium phone mode** (2026-10-27, briefs 15, 18 and 22; plan `ares-empire/docs/ARESIUM-FOR-OTHERS.md`): everyone
  but Patrik keeps their Aresium data on their iPhone. **No account** (Patrik, 2026-10-27, brief 22): Aresium opens in
  phone mode on the phone's one store at once, without a login and without waiting for any server (`ModeStore.start`);
  the first screen or the dashboard. **Server mode** stays in the app, unused since 2026-10-31: the server answers
  `server` only for ids in its `APP_SERVER_MODE_USERS` (empty), so Patrik's Aresium shows the phone's data as
  everyone's (logging in to another Ares app had switched it to his old server data). While a login
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
  layouts the person confirmed, receipts (schema version 2, brief 31), the receipts' direction, kind, `paidFrom` and the
  shop as read plus the corrected shop names (schema version 3, brief 33), one's own categories' icon and colour (schema
  version 4, brief 36), bank payments’ own names and merchant name rules (schema
  version 5, brief 43), category sides and other-side offers (schema
  version 6, brief 69; `LedgerSchemaCurrent` names the version the app opens, tests use it too); older stores move on by lightweight stages,
  one after the other (`LedgerMigrationPlan`; a model change always adds the next version, never edits one in place;
  `ReceiptBookTests` opens a version 1 store, `ReceiptCorrectionTests` a version 2 one, `OwnCategoryLookTests` a version 3
  one). **Own categories' looks** (brief 36, `Model/OwnCategoryLook.swift`): an icon from a word of the name (English and
  German, matched on word beginnings), else the next unused of a spare set, and a colour no default category has; stored
  with the category when it is made, never two alike while icons are left. **Counting** (briefs 35, 37): own transfers
  never move with a shop's other payments; the same bank payment from two file formats is matched by account, day,
  amount and currency, one to one (`PhoneLedger.add`); every way a payment could count twice has a test
  (`PhoneCountingTests`, `PhoneConversionTests`). **The picker** sorts once the taps stop (`CategoryPickerModel.settle`,
  half a second) or when it closes, and rebuilds the dashboard only when it closes (brief 39). **Off the main thread**
  (brief 39, measured: a settled burst held the main thread 404 ms at 5,000 payments, now 0.2 ms): SwiftData ran the
  `@ModelActor` ledger's jobs on the main thread even when made elsewhere, so `PhoneLedger` has its own serial queue
  (`PhoneLedgerExecutor`, the context made and used only there); the sort, the counts and the dashboard's input are built
  inside the ledger (`PhonePickerWork.swift`), so the big arrays live and die there too; the engine's `JSContext` is made
  off the main thread (`AresiumEngine.bundledForPhone`), since JavaScriptCore runs its clean-up timers on the run loop it
  was made on; values are set only when they changed, and the picker's rows are equatable. Signposts: subsystem
  `de.ares-empire.aresium`, category `picker` (`PickerTiming`; Instruments on the phone shows them); the timing run:
  `TEST_RUNNER_PICKER_TIMINGS=1` with `-only-testing:AresiumTests/PickerTimingTests`.
  **Settings (brief 57):** `AppLock` caches biometric availability; its `LAContext` checks run off main on launch,
  foreground and opening Settings. The dashboard observes only cached reminder eligibility, so refreshing Messages
  or changing its other choices does not invalidate it. A category picker model lives for one opening (it was made anew on every
  redraw). The app's own work in Settings measured at most 1.4 ms (1,250 payments) and 4.6 ms (5,000) per step on the
  simulator; the longer main-thread turns that remain are iOS drawing the sheet and its pages (and the test driver).
  Measure on `codex-57`: build Aresium, then `python3 scripts/57-settings-timing.py after 1250 --prepare` (also 5000;
  use a fresh phase name for each run, `--app <saved app>` for a baseline). DEBUG `-sampleSize` fills an exact-size fictional store over a year;
  `-settingsTimings` uses real authentication availability and the fake notification center with live scheduling paths.
  Signposts: `settings.mainTurn` in category `settings`, plus `PickerTiming`'s work spans. Raw wall/CPU main-run-loop
  turns, work spans, UI logs and summaries go to `build/57-*`. The driver resolves coordinates and checks state outside
  measured windows, since accessibility snapshots add overhead; whole busy turns still include UIKit/SwiftUI rendering.
  Learned merchants are rebuilt from corrections when the bundled engine changes
  (`PhoneBackend.rebuildLearnedKeys`). **Moving over** (builds before 22 kept one store per account in `Aresium/<account
  id>/`): when there is no `local/` store, the most recently changed older store (its newest file) is moved (never
  copied) to `local/` at the first open; with several, the others stay untouched where they are (logged, category
  `storage`). **Lifecycle:** the data belongs to the iPhone, not to a login: logging in or out, leaving Aresium and
  deleting the Ares account never touch it; it goes only with Settings → Delete Aresium data on this iPhone or the
  lock's "Forgot the code?". Settings → Your data on this iPhone (phone mode): Categories, Receipts, Export (one JSON file,
  schema 6 with the receipts, cash entries, corrected shop names, payment names, category sides and default personal names, `Aresium-<date>.json`, through the share sheet), Restore
  from an export (only into an empty store, all or nothing; chosen categories and corrected shop names are replaced;
  schema 1–5 files still restore).
  **Payment names and groups** (brief 43, data only; `Model/PaymentNames.swift`, screens in brief 44):
  `LedgerPayment.place` always stays the bank name; sorting, learning and receipt matching use only those original
  fields. Schema 5 adds `LedgerPayment.ownName` and merchant → name rules (`PhoneLedger.paymentNames()`); export schema
  4 carries both, older stores migrate through every frozen version and exports 1–3 still restore. Delete data deletes
  names with the store. Names trim whitespace and keep at most 60 characters (Swift grapheme clusters); empty removes
  only the selected scope. Removing a payment override reveals a remaining shop rule; changing/removing a shop rule
  leaves payment overrides intact. An empty merchant key allows only the payment scope.
  **Shop identities** (brief 54): one engine `shopIdentities` call per name/lookup job over the distinct keys of all
  bank payments, receipts, stored name rules, learned category rules and bank-line-only probes (`ShopIdentities.swift`,
  `names.identities`). `AresiumEngine.nameKeys` batches the full merchant keys, place-alone probes (counterparty =
  place, empty description) and the engine's `cardMerchant(place)` checks in one bridge call. The probes share the
  identity universe; they only qualify display names and never become additional learned/name rule keys.
  Original merchant keys and stored/exported rules stay unchanged. Different names of one shop group together, including
  receipts and cash entries; payment-only names and exact bank-line grouping for empty keys keep their behavior. A name
  rule uses the exact merchant key first, then the lexical first rule of its shop. Renaming/removing a shop name
  removes the other name rules of that identity. The category question counts that shop’s eligible other payments;
  All replaces the learned rules of every current/stored key of the shop, so an older exact rule cannot win later.
  Manual, receipt-set and own-transfer categories never move with it. Receipt learned-category presets use the same
  exact-first, then valid lexical rule precedence as sorting, over the receipt's key and the learned keys only (as
  `sortPayments` does for one payment), so opening a receipt never reads every stored payment. Receipt OCR name corrections still match the print as read.
  When the engine revision changes (also on restore), manual corrections rebuild learned keys and obsolete name keys
  move to their longest current whole-word prefix; an existing rule at that current key wins. Absent shops stay stored.
  **Brief 44 API:** get a `TransactionDetailStore` with `DashboardStore.transactionDetailStore(for:)` as for category
  changes. `await prepareRename()` loads the detail and `renameInfo` (`PaymentRenameInfo`, nil in server mode);
  `canRename` is false there. The info has `bankName`, effective `ownName`/`source` (`.shop` or `.payment`), both
  `paymentOwnName` and `shopOwnName` for scope-specific editing/removal, `canRenameShop`, and `otherPaymentCount` (N,
  all other bank payments of the same shop identity, 0 for an empty key). Call `await rename(to:scope:)` with `.shop` or
  `.payment`: saves, refreshes the detail/info and rebuilds the dashboard/widget; use the existing `isSaving` and
  `saveError`. Row and page use the same store. Phone samples use their real temporary ledger, as category changes do.
  The lower-level `PhoneBackend.renameInfo(id:)` returns that info; `rename(id:name:scope:)` saves and returns the new
  `TransactionDetail` (callers outside the detail store must reload their dashboard).
  **One bank name per shop** (brief 76): after counting, `PaymentNames` chooses `LedgerPayment.place` from the
  shop identity's newest qualifying bank payment (booking date, then later store order) for every bank row without
  an effective own name. A line qualifies only when the engine's merchant key of that line alone belongs to the same
  shop identity AND `cardMerchant(line)` returns null. Card statements carrying a payment's amount/date never supply
  the shop name; a payment service named as counterparty cannot supply it merely because the shop appears in the
  description. Both checks use the engine, with no Swift copies of its patterns. If no line qualifies, each payment keeps its own bank line. A payment's own
  name still wins over the shop rule; Own names off hides only own names, keeping the
  shop's newest qualifying bank line. An empty merchant key keeps its own bank line. `Transaction.bankName` and the detail's
  `bankName` carry that payment's original line whenever different, including when the title is the shop's bank name
  (`isOwnName` remains false). Cash withdrawals, name pages/months, summed rows and the rename field follow the shown
  name; receipts and cash entries keep their typed Shop. `PaymentRenameInfo.shopBankName`/`bankDisplayName` supply
  the fallback to details and `RenamePlan.start`; original fields never change or reach the engine under a display name.
  **Several payments at once — data API** (brief 81; screens in 82; `Model/BatchChanges.swift`,
  `Model/BatchLedger.swift`): phone mode's category month lists, Current and Overview, Not sorted included.
  `DashboardStore.offersSelection(in:)` (or `category:month:side:`) and `selectableRows(in:)` exclude covered rows;
  `selectionIDs(for: PaymentListEntry)` returns one id or all a sum's member ids. Keep a `Set<String>` of these row ids.
  `selectionRows(_:)` resolves live rows; `selectionSummary(_:)` returns `PaymentSelectionSummary`: `counts`
  (`BatchCounts.bankPayments`, `receipts`, `cashEntries`, `total`), `side`, positive `total` in euros, a shared
  `currentCategory`, `canSwitch`, `canRename` (Own names must show). `offeredCategories(for:)` returns `[Category]`
  from `PhoneCategoryList.offered` for that side, leaving out a common primary category. Empty, missing, mixed-month
  or mixed-side action selections are refused (`switchCategory(ids:to:span: .allMonths)`, brief 99, lets one name's
  payments of one direction span every month: the quick sort's card). Server mode offers nothing; the tour's ledger
  uses the same API.
  `switchCategory(ids:to:)`, `addCategory(ids:name:)`, `rename(ids:to:scope:)` are async/throwing and return
  `BatchChangeResult`: `action`, `category`, `changed` and `skipped` counts, localized `message`, `undo`, optional
  `followUp`. Switch sets bank rows manual and learns each payment, changes receipts as Edit (learns their shops)
  and entries as Edit (no learning); one save, no sort. Add preserves primary/source and extras, skips bank rows
  already carrying the category and receipts/entries. `renameInfo(ids:)` returns `BatchRenameInfo` with
  `bankPaymentCount`, `otherPaymentCount` (distinct shops, excluding selected ids), `shopCount`, `allPaymentCount`
  and skipped receipt/entry counts. `BatchRenameScope.payments` sets each selected bank row's own name;
  `.shops` consolidates each distinct shop's rule and drops selected overrides; keyless rows get their own name.
  Names use the single rename's trim/60-character rule; empty removes names in that scope. Receipts and entries
  keep their typed Shop. These APIs also exist on `PhoneBackend` (save/summary only; no dashboard rebuild).
  `BatchMerchantFollowUp` supplies `count`, `shopCount`, `shop` (one shop only), `category`, localized `question`;
  `apply()` returns a new result with the same undo handle. It moves each eligible other bank payment once,
  excluding manual, receipt-set, structural, own-transfer, selected and already-target rows, and replaces every
  relevant alias's learned rule. `BatchUndo.perform()` returns `.undone` or `.unavailable` with a localized
  `message`; the original handle also undoes an applied follow-up. Each store action, applied question and
  successful undo rebuilds dashboard/widgets once. An observer of **every save on the ledger context** increments
  a revision; tokens also check ledger identity and complete before/after value snapshots. An intervening import
  or save (even changing a payment and changing it back) invalidates the whole undo/question before any write.
  Undo restores only the changed row category/source/extras, own names, and added/replaced/removed learned/name
  rules, with one save. The revision also protects planning across engine awaits. All ledger work
  stays on its executor in one operation per action; the bridge's `learnMany` calls the existing engine `learn`
  for each correction in one JSON crossing. Tests: `BatchChangesTests`, including 500 selected rows / 60 shops
  (79.739 ms on codex-81, including learning, save and undo snapshots; the learning bridge 1.575 ms).
  **Name search API** (brief 76, data only; screens in 77): `NameSearch.results(for:in:)` takes a query and
  `Dashboard.nameGroups`; `DashboardStore.searchNames(_:)` uses a `NameSearch.Index` cached by dashboard `revision`
  for keystrokes. A group retains `names`: shown spellings, every original bank line and every own name (also hidden
  names). All query words must match one spelling, folding case, accents and ß/ss, with punctuation treated as spaces.
  Ranking: equal, full prefix, all word prefixes in any order, all substrings, then one insertion/deletion/substitution
  per query word of at least four letters (short words must match exactly as substrings). Within each tier: shown name,
  more payments, newer last payment; the opaque key breaks remaining ties. Empty queries return none; at most 50 hits.
  `NameSearchResult` returns `key` (also `id`), `shownName`, optional `matchedName` (the other original spelling),
  `count`, positive `moneyOut`/`moneyIn`, `newestDate` and `categoryName` (the newest row's); `nameGroup(_ key:)`
  looks up that result's group. Server mode has no name groups and returns no hits. The index builds once per
  dashboard; `NameSearchTests` times 1,000 groups / 5,000 payments.
  **Setting:** `DashboardStore.ownNames` (or `PhoneBackend.ownNames`) reads `aresium.ownNames`, default true.
  Settings calls `await DashboardStore.setOwnNames(_:)` to persist and rebuild, rather than writing defaults directly.
  Off hides own names without deleting them. `Transaction.place` and `TransactionDetail.place` carry the shown name;
  optional `bankName` is set only when different, `isOwnName` says whether the shown name is own, `ownNameSource` says
  which scope, and `nameKey` is an opaque grouping key. These fields are absent in server data.
  **All payments of this name:** `DashboardStore.nameGroup(for:)` looks up the prebuilt `Dashboard.nameGroups` dictionary
  by a row’s `nameKey` (nil for excluded/covered rows or server mode). `PaymentNameGroup` has `rows` newest first,
  `count`, separate positive `moneyOut`/`moneyIn`, and `months[YYYY-MM]` (`PaymentNameAmounts`, the same two numbers),
  including zeroes for every dashboard month. Built once per dashboard on the ledger worker, after the engine counted
  it: own names fold case and diacritics; otherwise the engine’s shop identities, or exact bank lines for empty merchant keys.
  Receipts/entries keep their Shop on screen but join that shop’s key/rule (waiting card receipts count until joined,
  as on the dashboard). Covered rows and payments counting in neither overall total are excluded; tags cannot add
  them back. The ledger executor also does name saving, merchant-key input and the question’s count off main;
  `PaymentNamesTests` checks the worker spans (`names.*`) and opens an actual schema 3 store with all record types.
  **Renaming and the name's page** (brief 44, the screens; Patrik 2026-10-30: swipe left only, no direction setting;
  **brief 47**, Patrik's test of build 4: renaming was hard to find): the payment's page shows the shown name as its
  title and, whenever different, this payment's original bank line small under it. **The name is edited where it
  stands** (brief 47; brief 44's Name row, its Rename button and `RenameSheet` are gone): in phone mode with Own names on, a small pen
  (`PenButton`: SF `pencil`, muted ink, 44 pt tap area, VoiceOver "Rename") follows the title, and a single tap on the
  name or the pen (Patrik asked for a double tap; a single tap is found without being told and a double tap still
  works, its first tap opens the field; Patrik agreed 2026-10-30) turns the title into a field in the title's own font
  and place (a field's box reaching into the margin), the name all selected and the keyboard up
  (`TransactionDetailSheet`: `nameEditor`, `PaymentRenameModel`; the selection is set once the field has the keyboard).
  Under it "Your bank's name: …", "Only the name you see changes. …" and, while an own name shows, "Use the bank's
  name" (bordered). The bar shows Cancel and Save instead of Done while the field is open (Save off while unchanged;
  Cancel after typing asks, `DiscardingCancel`; the page's swipe down is held back while something is typed); Return
  (the keyboard's Done) saves, and closes the field when nothing changed. `RenamePlan` (`Model/PaymentRename.swift`):
  the field starts with the shown name, the bank's too. A new name asks whenever there is a merchant key and N > 0:
  "Also the other payments from <bank>?" with "With All, new payments … get the name too.", **All N+1** (the shop's
  rule; this payment's own name is dropped) or **Only this one**. "Use the bank's name" on a name other payments share
  through the shop's rule asks "Use the bank's name for all N+1 payments?": **All N+1** (the rule goes), **Only this
  one** (brief 47: this payment shows the bank's name while the shop keeps its name; stored as the payment's own name
  equal to the bank's name as names are kept, `PaymentNames.keptBankName`, read by `PaymentNames.shown` as no own name,
  so the payment shows the shop's bank name and counts with that shop; export and restore carry it as any own name),
  Cancel. Server mode and Own names off: no pen, no field. **The category** (brief 47): the chip and a pen beside it ("Change
  category") open the change window, an extra category's chip opens it at Add; the Change button and the reason sentence
  went, the reason (`PaymentWording.categoryReason`) is one quiet line under "Currently in" at the window's top. Server
  mode the same wherever the page has categories to change to.
  **Counting as it happened** (brief 71, Patrik 2026-11-01: "booking everything as it happens is clearer and more
  truthful"): every payment counts once, in the direction it went, under its own category (and its extra ones): money
  out is Ausgaben, money in is Einnahmen, whatever the category's side; nothing is netted, so a returned order shows as
  spent and as received, and there is no Refunds / Rückerstattungen row. The one exception is a withdrawal's cash covered
  by receipts, which moves to the receipt's category. A payment's `categoriesIn` (its spending lists) holds categories
  only for money out, its `incomeBuckets` only for money in; `PaymentNames` groups a row that has either. Unsorted money in counts under the same "Uncategorised" as unsorted money out (aresium cd20cf8, 2026-11-01; it was "Other", which showed untranslated and in English shared its row with the default category Other), so both sides show it as "Not sorted" / "Nicht sortiert" (`CategoryName.shown`).
  **A day's payments API** (brief 76, data only; screens in 77): `DashboardStore.day(_:)` takes `YYYY-MM-DD` and
  returns `DayPayments` cached by dashboard `revision`. `date`, `expenses` and `income`; each side has `rows` and
  `total`, also accessible as `day[.expenses]` / `day[.income]`. Each `DayPayments.Row` has the usual `TransactionRow`
  in `row`, a convenience `transaction`, `id`, and the dashboard's `Category` (name, icon, colour and kind) in
  `category`. Rows keep the month lists' stable order and covered rows, one occurrence per payment despite extra
  categories. The category is the primary list on that side, else its first list (server mode's Other, for example).
  Totals come directly from `dayExpense` / `dayIncome`, including covered cash on the withdrawal's date; transfers
  stay absent as in month lists. Phone and server mode both work; invalid/absent dates return empty lists and zero.
  `dayDate(atChartIndex:scope:)` maps a zero-based day point on `.current` (including a review month) or `.month(key)`
  to its date; `.overview`, missing months and indices outside the graph return nil. `DayPaymentsTests` compares every
  sample day with the graphs and month lists in both modes, plus covered cash, extra categories and revision changes.
  **A day's page and the search on screen** (brief 77, Patrik 2026-11-01: "make days clickable too and lead to a screen
  with that days expenses and income (in two tabs with swipe)", "A small search icon … search by names which uses own
  given and also original names organized by best match"). **A day's page** (`Screens/DayScreen.swift` `DaySheet`, words
  and the tap in `Model/DayPage.swift`): a short tap on a day of a day graph (the start screen's Current, a month's
  page; `SeriesChart.onPick` → `DashboardStore.dayRoute(atChartIndex:side:scope:)`) opens that day on the side of the
  graph tapped (`DayRoute`, `DashboardPlace.day`); holding and sliding still reads the graph and opens nothing. A sheet
  (presented by `DashboardStack`), not a pushed page, so a sideways swipe turns its sides and a swipe down closes it; it
  opens at medium height (`.presentationDetents([.medium, .large])`, Claude's choice: a day has a few rows, and the
  graph that was tapped stays in view above it; pulled or scrolled up it takes the whole screen): the
  bar "Day" / "Tag" with Done (as the payment's page's "Payment"), the day written out as the title, 22 pt bold
  (`DayPageWording.title`, the payment page's date: "Monday, 12 October 2026" / "Montag, 12. Oktober 2026"; too long
  for a centred bar title in German), the start screen's dots (`PageDots`, shared with `DashboardPages`), then the two
  sides as pages (`TabView` paging): each the day's total to the cent under the side's word in the start screen's
  heading (`SideTotal`, shared with `StartPage`) and the day's rows (`DashboardStore.day`, read in `body`, so after a
  row's page or window closes it shows the store as it is) or one quiet line ("No spending on this day." / "Keine
  Ausgaben an diesem Tag.", "No income on this day." / "Keine Einnahmen an diesem Tag."). **The rows**
  (`PaymentRow(day:)`): a month's list's row with the category in the day's place (`PaymentRowLabel(category:)`: its
  tile, and its name first in the quiet line, "Groceries · Munich"; every row has the same day there, and nothing else
  says the category), the tap (the payment's page over the sheet), the long press (Change category, Rename, "All with
  this name"); **no swipe of their own** (`PaymentRow.swipes`, Claude's choice, 2026-11-01): a swipe left on a row
  would have to mean both "All" and "to Income", and Patrik asked for the sides to swipe; tried with real touches, a
  sideways swipe that starts on a row turns the side. "All" is in the long press and on the payment's page. A name's
  page asked for there closes the sheet, then is pushed on the dashboard's stack (`DashboardStack.afterDay`). In the
  tour the sheet has its spotlight and card; the tour's steps close it (`TourModel.closeSheets`). **The search**
  (`Screens/SearchScreen.swift`, words in `Model/SearchPage.swift`): a magnifying glass (`magnifyingglass`, an
  `IconButton` in `HeaderButtonLook`) in the start screen's header before the import button, phone mode only
  (`DashboardStore.offersSearch`: server rows have no names). It pushes `DashboardRoute.search` on the dashboard's stack
  (the header "Search" / "Suche" with its arrow and gear; the back swipe works): `SearchField` in Apple's search field
  look (a capsule with the magnifying glass, the prompt "Search names" / "Namen suchen" and the clear button; the second
  card and the line, the cursor in ink), the keyboard up as the page opens (once: back from a name's page it stays down
  and the query is kept); a scroll puts the keyboard away. **Before typing** (Claude's choice): one quiet line, "Finds
  your own names and the bank's." / "Findet deine eigenen Namen und die der Bank.", and under "LATEST" / "ZULETZT" the
  names of the eight newest payments (`DashboardStore.latestNames`, `NameSearch.latest`), so the likely ones are one
  tap away and the rows show what a result looks like; the line alone would leave the page empty above the keyboard. **While typing**: `searchNames` best match first; **a result** (`NameResultRow`, lines in
  `SearchPage.Row`): the newest payment's category tile, the shown name with the money out (the list's red, "−84.50")
  and under it the money in ("+35.00") when there is any, a quiet line "5 payments · 22 Oct · Clothes" (the newest
  day, its year only in another year; "last"/"zuletzt" made the German line too long for the category), and when found
  by another name that name in a second quiet line, up to two lines rather than cut: a bank payment's line "Bank's
  name: MGP Vinted - Kleiderkreisel" / "Bei der Bank: …" (the key the payment page's VoiceOver line shares; "Name bei
  der Bank" wrapped the row), an own name (another payment's, or hidden while Own
  names is off) "Your name: …" / "Dein Name: …", a receipt's typed Shop alone (`SearchPage.kind`); a chevron, as rows
  that open a page. A tap opens the name's page (`DashboardRoute.name`). No match: "No name found for “…”." / "Kein
  Name für „…“ gefunden." DEBUG (with `-samplePhone`): `-openDay <YYYY-MM-DD>` (`-daySide income`), `-openSearch`
  (`-searchText <text>` typed, `-searchKeyboardDown` without the keyboard), `-sampleShopLines` (made-up Vinted
  payments under two bank lines, "MGP Vinted - Kleiderkreisel" four and three months ago, "Vinted, UAB" since, with one
  sale on the 12th of last month: a search for "Kleider" finds it by the older line). Tests: `SearchAndDayScreensTests`
  (which tap opens which day on which side, the day page's words and empty side, the rows' category, the page
  following the store, the search only in phone mode, the result rows' lines in both languages, before typing),
  `TourTests`. Real touches (a temporary UI test in `Aresus/AresusUITests`, deleted; 3 of 3 runs each, the day's
  sheet again at medium height): a tap on the 12th opens its page on the side tapped, a sideways swipe starting on a row
  turns to Income and back, a swipe down closes it, a row's tap opens the payment's page over it, the long press's "All
  with this name" closes it and pushes the name's page, a hold-and-slide reads 5–20 Oct (the `graph` log) and opens nothing, a hold alone opens nothing, a tap on
  Current's day opens it, the search's field has the keyboard at once, "Kleider" finds Vinted with its bank's line, the
  result opens the name's page and back keeps the query, the edge swipe leaves the search. Screenshots:
  `build/77-*.png`.
  **Category names, rename and removal** (brief 80): every New category field uses
  `PhoneBackend.useCategory(named:side:sorting:)`: a name in either original language or a chosen personal name,
  ignoring case and accents, reuses that category. The result is made, existing, offered on this side, or a default
  ticked (with waiting payments sorted). Built-ins and reserved page names still refuse. Settings clears the add row
  and shows the result in a quiet line using the shown name; the change, receipt and cash windows pick it. A newly
  ticked Friends is offered for money in too; existing chosen entries and restored side choices are preserved.
  Holding any chosen row in Categories opens Apple's menu: Rename…, Use the original name while a default is renamed
  (with its original name as subtitle), the existing side choices, then Delete for one's own or Remove for a default.
  Rename uses Apple's name-field alert with a plain ink button, keeps a rejected name for correction, and checks other
  categories while allowing its own current and original names. Defaults keep their personal name in the existing
  `customName` field (no storage migration); it stays in both languages until restored to the original.
  Delete/Remove confirms in Apple's dialog anchored at the row, with the payment count and re-sorting explanation;
  Remove also says it can be ticked again. Both reuse `unchoose(id, moveTo: nil)` and sort: primary manual choices are
  reset, learned rules and built-in sorting run again, unknowns stay Not sorted, extra-category references go, receipts
  and cash entries become Not sorted. Own rules go with a deleted category; default rules wait for its next tick.
  The tick's existing move-to sheet is unchanged. Rows/counts update in the picker; its close rebuilds the dashboard.
  Dashboard source/detail/tag names use `PhoneCategoryList.name(of:)`; open category routes carry their stable id and
  follow a rename (or close on removal), and stale widget name links open the dashboard. Sum choices keep their id keys.
  Export schema 6 carries default personal names; schemas 1–5 still restore; SwiftData stays on V6.
  The tour's categories card mentions holding to rename/delete. Tests: `CategoryEditingTests`, `TourTests` and the
  existing category/window/export suites. DEBUG with `-samplePhone -openSheet settings -openCategories`: `-sampleRenameCategory <id>
  -categoryName <name>` renames before display; `-renameCategory <id>` opens the alert; `-removeCategory <id>` opens
  its confirmation; `-sampleTick <id,id,…>` seeds defaults absent from the sample (use it for Friends);
  `-categoryAddName <name> -categoryAddSide spend|income` uses the add row; `-scrollToCategory <id>`
  brings its row into view (`own` brings the add row). `-sampleNoOtherSide <id,id,…>` reproduces existing offers;
  `-sampleCategoryPayments <id|name> -sampleCategoryPaymentCount <n>` puts made-up payments there for confirmations. Context menus are checked with real UI-test long presses.
  Screenshots: `build/80-*.png` (English/German, light/dark).
  **Category sides** (brief 69): every category has one home side, which since brief 71 decides only where it is
  offered (the menus), not where its money counts. Defaults take `kind` from the engine's
  catalog; one's own store `side` (`"spend"` or `"income"`) in schema 6's chosen category, alongside `otherSide` (false
  by default) for any chosen category. Transfers have no side and are offered in both directions. `PhoneStorage.open`
  runs `PhoneLedger.giveCategoriesSides` before exposing the store: the engine's old no-side counting (primary
  categories, including receipts and cash as usual) gives an own category income for a positive net, otherwise spending;
  a default spending category with a positive net gets `otherSide`. An empty income default stays income. The internal
  `sidesAssigned` flag makes this once-only, so removing an offer survives reopening. Export schema 5 keeps both values;
  restore of schemas 1–4 assigns them after all payments and receipts are present. `PhoneCategoryList.offered(for:includingTransfers:)` is the shared menu rule: home categories, transfers when requested, then other-home categories
  with `otherSide`; receipts and cash omit transfers and append Not sorted. The dashboard's engine `pick` has the same
  membership, ordered by its totals. New category requires `CategorySide` in `PhoneBackend.addCustom(named:side:)`:
  change window follows the payment, receipt uses spending, Add cash follows Spent/Received; Settings → Categories the
  add row's side (brief 70). `setSide(_:of:)` changes one's own home and keeps the old
  direction offered if it holds primary payments or receipts/entries; `setOtherSide(_:for:)` changes a chosen
  non-transfer's additional offer. `ChosenCategory` equality includes both fields, so dashboard invalidation notices.
  `TransactionDetailStore.otherSideChoices` lists unused other-home choices; `pickFromOtherSide` picks locally and shows
  it last before the tiles. Save stores `otherSide` for the picks actually saved (Switch and Add); Cancel stores nothing.
  `stopOffering` removes an additional offer immediately, except a home or current category. The tour uses its own
  store and the same APIs. Tests: `CategorySideTests`, updated `NewCategoryInChangeTests` and
  `NewCategoryInWindowsTests`.
  **Category sides on screen** (brief 70, Patrik 2026-11-01: own categories for income too, menus not bloated, "if
  category A is on expenses but also has incomes then it should be addable not just switchable"; a side only decides
  where a category is offered, and since brief 71 every payment counts in the direction it went, so no screen explains
  any effect on totals). Words in one place, `Model/CategorySideWording.swift` (both languages, tested); the German uses
  the app's terms (money in = Einnahmen, money out = Ausgaben: "Geldeingänge" wrapped in the context menu). **The
  change window** (`RecategoriseSheet`): the grid ends with two quiet action tiles in brief 60's look (`ActionTile`: the
  tiles' size, the second ink, the line's thin outline, no category colour), for money in and money out alike, in
  Switch and Add, phone mode only: **Other category…** / "Andere Kategorie …" (`square.grid.2x2`; the two-arrow symbol
  looked like Own transfers' tile beside it), only while `otherSideChoices` is not empty
  (`TransactionDetailStore.offersOtherCategory`), then New category, last as before. Other category… is Apple's menu
  (not a sheet: tried with every default ticked, 30 spending categories for money in, it scrolls as iOS's menus do and
  stays readable, and it spares a third sheet over the payment's page and the window): one quiet header line, "From
  spending" / "Aus den Ausgaben" for money in, "From income" / "Aus den Einnahmen" for money out (`otherSideListLine`),
  then the categories in the engine's order, each with its symbol in its own colour (`CategoryMenuIcon`: a UIKit image
  drawn as it is, since a menu draws plain symbols in its own ink), `menuOrder(.fixed)` so the header stays on top when
  it opens upwards. Picking one closes it and shows the category before the action tiles, picked
  (`pickFromOtherSide`); Save stores it as offered here (brief 69). **Taking one back:** a tile offered here only from
  the other side (stored, or picked in this opening; never this side's own, a transfer or the payment's current
  category, `offeredFromOtherSide`) has Apple's context menu with one entry, "Not for money in" / "Nicht für
  Einnahmen" (or "Not for money out" / "Nicht für Ausgaben", `stopOfferingEntry`, `minus.circle`); every other tile has
  no long press. It stores at once (`stopOffering`); one picked in this opening only leaves the window, nothing stored.
  No mark on such tiles: in the grid they read as categories like the rest, and the person put them there; the long
  press is the only difference. **Settings → Categories** (`CategoryPickerScreen`, also after an import and in the
  tour's Settings): one's own rows say their side in a quiet line under the name ("Spending" / "Ausgaben", "Income" /
  "Einnahmen", 12 pt muted, the up-down chevron), which is Apple's menu: the two sides (`setSide`) and, after a divider,
  "Also for money in" (or out) as a tick (`setOtherSide`). A ticked row offered on the other side too says so in the same
  quiet line ("Also for money in" / "Auch für Einnahmen", or "Also for money out" / "Auch für Ausgaben"), for default
  and own categories; that line is the same menu. Every ticked row but a transfer's has the same choices on its long
  press (Apple's context menu; a default row only the tick); an unticked row and a transfer's none
  (`CategoryGroup.Item`: `side`, `otherSide`, `canOfferOtherSide`, `choosesSide`, `showsOtherSide`). The line's menu is
  laid over the row where a hidden copy of the line stands (`SideLineAnchor`, `overlayPreferenceValue`): inside the row's
  button the button took its tap and ticked the row off (seen with real taps). The menus' tick is Apple's toggle
  (`.toggleStyle(.automatic)`): Settings' `EmpireSwitchStyle` drew it greyed in a menu. Chosen from the line rather than
  a chip on the right (the count and the tick are there already) or two sections (switching would still need a long
  press, and the add row would be in neither). **Adding one** asks the side under the field, as a row's line (Apple's
  menu, spending first, kept while the picker is open: `CategoryPickerModel.newSide`, `addCustom()`). A side change or
  an offer refreshes the rows at once and builds the dashboard again when the picker closes (no sort). DEBUG (with
  `-samplePhone`): `-sampleIncome` (the income side, also for `-sampleCategory`, e.g. `-sampleIncome -sampleCategory
  Other -sampleMonth 2026-10 -samplePhoneTransaction Erika -sampleRecategorise switch`: a money-in window),
  `-otherCategoryPick <name>` (picked from the list in that window), `-sampleOwnIncome <name,…>` (own income
  categories), `-sampleOtherSide <id or own name,…>` (offered on the other side too), `-sampleChooseAll` (every default
  ticked: the longest list). The menus and context menus need real taps: a temporary UI test in `Aresus/AresusUITests`
  driving Aresium (deleted). Tests: `CategorySideScreensTests`. Screenshots: `build/70-*.png`.
  **Save in Add asks** (brief 83; phone mode, `CategoryQuestions.swift`): after adding a category, Save asks
  “Also remove from <current>?” with the Foundation-formatted list of the remaining categories, Remove and Keep both.
  Remove uses Switch's learning and shop question; Not sorted promotes the first category without asking. The quiet
  bottom button is gone. Keep both, or changing only extras, asks whether to add/remove those extras on the shop's
  eligible other bank payments. The count excludes rows already carrying an addition, rows without a removed extra,
  own transfers and structural rows; receipt and cash rows have no extras. All adds/removes extras in one ledger job
  and one rebuild, preserving primary categories and learning nothing. The follow-up's `wording` builds its title,
  optional message and button titles for both one payment and a selection.
  **Selection window API for Add:** call `DashboardStore.prepareAddCategories(ids:names:currentCategory:removing:)`
  on Save with the list's category and the added/removed extra names (`offeredCategories(for:mode: .add)` omits
  Own transfers). Present the returned `BatchAddRequest.question`
  if present (`RemoveCurrentQuestion.title/message/removeTitle/keepTitle`); then call `request.save(removeCurrent:)`.
  Without a question call `request.save()`. The returned `BatchChangeResult.followUp` is the usual shared, single-use
  follow-up; its original undo also restores an applied answer. Remove switches only selected rows whose primary is
  the list's category; the others get extras. Unsorted selected rows switch automatically. The lower-level
  `addCategory(ids:name:removingCurrent:)` and `addCategories(ids:names:removing:removingCurrent:)` save an already
  answered choice. The selection screens are brief 82's (below).
  **Several payments at once on screen** (brief 82, Patrik 2026-11-01: "make expenses / incomes selectable and then
  moveable / changable at the same time … like in Mail when selecting mails"; logic `Model/PaymentSelection.swift`, look
  `Screens/SelectionScreens.swift`). **The icon:** a category's month list (Current and Overview, Not sorted included;
  phone mode, while `DashboardStore.offersSelection(on:)`) has `checkmark.circle` in the header's buttons
  (`ScreenHeader.select`, after red mode's X, before the icon of adding up; VoiceOver "Select" / "Auswählen"); nowhere
  else. **Selecting** (`PaymentSelection`: the list's route and the ticked row ids, kept in `DashboardPlace.selection`, so
  the header, the rows and the bar read one state; it follows its list through a rename, `isSameList`, and ends when
  another page is on top, `DashboardPlace.path`'s `didSet`): the rows slide right by a circle and its gap
  (`SelectionLook.inset` 34 pt) in selecting's own motion (`SelectionMotion`, brief 200 below; Reduce Motion: none), an
  empty circle (muted ink) at each selectable row's left edge; a tap anywhere on a row ticks it, and so does a finger
  sliding over the rows (brief 200 below) (`checkmark.circle.fill`, the app's ink with the tick in
  the wall's colour; the row on `palette.card2`, radius 12; VoiceOver: selected). The rows' long press and swipe are off,
  the scroll works. A summed row has one circle for its payments and stays closed (open sums close as selecting
  starts); a withdrawal's covered row has no circle and is faded (0.45). **The header** (`SelectionHeader`, in
  `DashboardStack`'s `PageHeader` in place of the screen's header, at its height, the same `HeaderLayout`): "All" /
  "Alle" (then "None" / "Keine") on
  the left, the count as the title ("3 selected" / "3 ausgewählt", "Select payments" / "Buchungen auswählen" at 0),
  "Done" / "Fertig" on the right (ends selecting, nothing changed), words in ink on the wall; the back arrow, the gear
  and the back swipe wait. **The bar** (`SelectionBar`, a bottom `safeAreaInset`, fading in and out with selecting):
  Category
  (`square.grid.2x2`) and Name (`pencil`), symbol over word, on the card colour laid over the wall's with the line on top,
  into the home indicator's area; muted while off (`SelectionBarState`: both off at 0, Name off without a bank payment,
  not offered while Own names is off, as the page's pen); it stays at the bottom under the keyboard. **Category** opens
  the one change window: `RecategoriseSheet` is generic over `CategoryWindow` (`Model/CategoryWindow.swift`), which
  `TransactionDetailStore` (one payment) and `SelectionCategoryChange` (a selection) implement; the picking (Switch's
  target, Add's extras, a category made here or picked from the other side, taking one back, New category) is one shared
  piece (`CategoryPicks` and the protocol's extension), so neither window copies the other. The selection's heading:
  "10 payments" / "10 Buchungen" and their total under it, signed in the side's colour as a payment's amount shows,
  "Currently in" the list's category; its lines say "they" (`CategoryWindowWording.modeLine`); the grid brief 81's
  `offeredCategories`; Save switches (`switchCategory`) or for Add asks brief 83's "Also remove them from Groceries?"
  (`prepareAddCategories`), then the shops' other payments in the merger's words (`CategoryQuestionWording`, e.g. "Also
  move 92 other payments from 3 shops?", **Move 92 more** / **Only these**), with the single window's alert pieces.
  **Name** (`SelectionRename`, `selectionRenameAlerts`): Apple's alert "Name for 10 payments" / "Name für 10 Buchungen"
  (the bank payments that take it), the field with the name they all show or empty, "Receipts and cash entries keep
  their shop." when any are ticked, Cancel and Rename (a plain button in ink); Rename is on once the name is new. Then,
  when the shops have other payments (`renameInfo(ids:)`), the single rename's question for all of them
  (`SelectionRenameQuestion`: "Also the other 14 payments from these 3 shops?", one shop "… from REWE?" with the name they
  show, else "… from this shop?"; "With All, new payments from … get the name too."; **All 24** (`.shops`) / **Only
  these** (`.payments`)); without others the payments alone. **After an action** selecting ends, the list shows the store
  as it is, and the shared undo bar (`UndoBar`, `accent: nil` = Undo in ink; above the selection's bar while one shows)
  says it in brief 81's words (`result.message`; after All the selection's and the others' count together,
  `SelectionWording.done`) with Undo (`BatchUndo.perform`); a refused undo shows its line alone ("Cannot undo because
  the data changed."), as does a failed action (`UndoOffer(message:)` without Undo, Shared). **The tour**: step 10 of 21
  (`TourStep.select`, after the payment's switch and before Add up): the ring on the icon (`.selectIcon`), "Tap to select
  several payments and move or rename them at once." / "Tippe hier, um mehrere Buchungen auszuwählen und auf einmal zu
  verschieben oder umzubenennen.", Next; selecting frees the screen and works on the tour's store; Next ends it.
  DEBUG (with `-samplePhone -sampleCategory <name> -sampleMonth <YYYY-MM>`): `-selectPayments <n|all>` (selecting, the
  first n rows ticked; 0 none), `-selectionWindow` (Category; `-selectionMode add`, `-samplePick <name,…>`,
  `-selectionSave`, `-selectionAnswer remove|keep|all|only`), `-selectionName` (`-selectionNameText <text>`,
  `-selectionRename`, `-selectionRenameAnswer all|only`), `-sampleUndoRefused` (the refused line). Tests:
  `SelectionScreensTests` (the icon only where offered, ticking, All/None, a summed row, a covered row, selecting
  following its list, the bar's states, the window's heading and choices, Switch with the shops' question and one undo,
  Only these and a refused undo, Add's removal question, one view for one payment and a selection, Name's start, question
  and both answers, the words in both languages), `TourTests`. Real touches (a temporary UI test in
  `Aresus/AresusUITests` driving Aresium, deleted): the icon starts selecting, a tap ticks and unticks, All and None,
  Done ends it, Category → Climbing → Save → Only these moves Not sorted's rows out and Undo puts them back, Add →
  Clothes → Save → Keep both → the shops' question → Only these, Name → the alert → the question → Only these renames
  both, the list scrolls while selecting (4 of 4; a test that taps Rename in the very instant the last key is typed
  loses the tap, a moment later it works). Screenshots: `build/82-*.png`.
  **Calmer, and selecting by sliding** (brief 200, Patrik on build 14, 2026-11-02: "selecting statements is quite bouncy
  … can we build it like mail so you can basically just slide your finger up and down and it keeps selecting statements
  or when going up deselecting them"). **What bounced** (a recording of build 14 on the simulator, its frames measured;
  `build/200-motion-before.{mp4,png}`): every tick slid the new circle in from up to 29 pt left of its place while the
  old one slid away (the circle swapped two views, and the swap took the circle's own way in, `.offset(x: -34)`), and
  the header's count rolled letter by letter with a blur for 0.56 s (`numericText`), drifting sideways as its width
  changed; All and None slid every circle at once; the rows' spring (`SumMotion`, 0.38 s) took 0.49 s, its last 4 pt
  creeping; the header swapped in one frame both ways; the bar came in one frame and sank out over 0.45 s; the list itself
  never moved (0 pt, measured on the amounts' column, also with the bar coming and going at the list's end). **Now**
  (`build/200-motion-after.{mp4,png}`): `SelectionMotion` (an ease-out of 0.25 s; Reduce Motion: none; DEBUG
  `-selectSlow <s>`) starts and ends selecting (the icon, Done, the end after an action, open sums closing): the rows and
  their circles slide 34 pt (done in 0.23 s, measured), the header and the bar fade in place (`PageHeader`: the two
  headers in one `ZStack`, the selection's at the page header's measured height; the incoming header and the bar fade in
  by themselves, `fadesIn`, since insertions there took no animation, not even a transition's own; the outgoing header
  keeps its last words, `lastShown`). A tick fades the circle (both symbols always there, one seen) and the row's
  background in 0.1 s; nothing moves; the count changes at once. Not sorted's quick sort card stays in its place while
  selecting, faded (0.45) and taking no taps (it had gone, moving every row up). `SumMotion` is adding up's alone again.
  The plain button's press dim (to about 80 % while the finger is down, back over about 0.3 s) is left: press feedback,
  as iOS's lists give, not motion. **The slide** (`Model/SlideSelection.swift`, pure; `Screens/SlideSelect.swift`):
  while a list selects, a drag that starts on a row's circle column (`SelectionLook.column`: from the list's margin to
  the day's tile, 58 pt) slides at once in any direction; elsewhere on a row only a drag that starts clearly sideways
  (the row swipe's measure, decided after 6 pt, `SlideStart`) slides, and may then turn up or down (Photos'); a vertical
  drag there scrolls. The first row decides (`SlideSelection`: not ticked, the slide ticks; ticked, it unticks); every
  row between it and the finger takes that state and every other row is as it was before the slide, so the way back
  restores; a summed row is one row (`selectionIDs(for:)`); a covered row is passed over and no slide starts on it;
  beyond the list's start or end the finger counts as over its first or last row. The finger's row comes from the rows'
  frames in the list's own layout (`slideRow`, `onGeometryChange` in `SlideSpace.list`, the space around the gesture
  so both are measured in one place; `SlideRows`: a lazy list lays out only the rows near the screen, and a finger
  beyond them is over the nearest). Near the top or bottom of the visible part (`ScrollGeometry`: under the header,
  above the bar) the list scrolls by itself (`SlideScroll`: a 60 pt zone, the speed growing with the square of the depth
  to 900 pt/s at the edge and past it; a display link and `ScrollPosition.scrollTo(y:)`), the rows coming in ticked as
  they pass under the finger; it stops at the list's start and where its last row stands just above the bar (not into
  the band). One `SlideSelectRecognizer` (a `UIPanGestureRecognizer` subclass, as the row swipe's) over the whole list:
  it asks where the touch went down (`SlideTracker.place`), fails at once off the rows, and the list's own pan waits for
  it while it decides (`shouldBeRequiredToFail`), so a drag on the column never scrolls instead. A light selection haptic
  per change (`sensoryFeedback(.selection)`; the finger hides the circle it ticks). Taps still tick one row; the header,
  the bar and the undo bar work; the back swipe waits; VoiceOver is unchanged (the slide is a shortcut). Tests:
  `SlideSelectionTests`, `SlideTrackerTests`, `SelectionScreensTests` (a slide over a real list with a summed and a
  covered row). Real touches (a temporary UI test in `Aresus/AresusUITests` driving Aresium, with XCTest's own
  multi-point touch paths, deleted; 3 of 3): down the column over five rows ticks five; down five and back up
  two leaves three; a slide from a ticked row unticks; sideways on a row's middle then down ticks; a tap ticks one row;
  Category opens the window for the slid selection; Done ends selecting; on a 48-row list a vertical drag on a row's
  middle scrolls and ticks nothing, and a slide held at the bottom edge scrolls and ticks the rows that came into view
  (held 5 s: all 48, the last row 8 pt above the bar). Screenshots: `build/200-slide-{en,de}-{light,dark}.png`,
  `build/200-slide-de-red.png`.
  DEBUG (with `-samplePhone -sampleCategory Groceries -sampleMonth 2026-10 -samplePhoneTransaction REWE
  -sampleRecategorise add`): `-samplePick Clothes -sampleAddSave` picks and taps Save after the sheet opens;
  `-sampleRemoveAnswer keep|remove` answers the first alert and shows the shop alert. Tests: `AddQuestionsTests`,
  plus updated new-category and other-side tests. Screenshots: `build/83-en-remove.png`, `build/83-de-remove.png`,
  `build/83-en-add.png`, `build/83-de-add.png` (English/German; the Add screenshots use Keep both).
  **Quick sort** (brief 99, Patrik 2026-11-01, after three sorting rounds still left about 240 of his payments Not sorted
  on day one, most of them personal: "a way to see the top not sorted factors and going through them"; logic
  `Model/QuickSort.swift` and `Model/QuickSortFlow.swift`, look `Screens/QuickSortScreens.swift`, phone mode only).
  **The groups** (`QuickSort.groups(in:)`, pure): every Not sorted row (no category; a withdrawal's covered row is none)
  over every month, grouped by `Transaction.nameKey` (the name groups' key: shop identity, own name, or the exact bank
  line for an empty merchant key; a person paying or paid by transfer is a name too) and **split by direction**
  (`CategorySide(amount:)`: a name's money in and money out are two cards), ranked by count, then money in integer cents,
  then the newest payment, then the key (singles last by that). A group has the newest row (its shown name), count,
  cents, first and last day, up to three example texts (`Transaction.purpose`, the bank's text, set on phone rows by
  `PhoneDashboard.addPurposes`; tidied, newest first, none repeated ignoring case and accents, none that only repeats
  the name or the bank's line) and its ids. Built off the main thread (`QuickSortCache.build`, a detached task) from each
  phone dashboard in `DashboardStore.reload` before it is published, and published in the same turn with its
  `revision` (`builtQuickSort`), so `quickSortGroups` (and `quickSortTally`: names, payments, `hasRepeats`) never belong
  to another dashboard; server mode has none. **Sorting a card** (`QuickSortCard`, a `CategoryWindow`, so its tiles,
  Other category… and New category are the change window's own: the grid is one view, `CategoryGrid`, extracted from
  `RecategoriseSheet`, with `pick`/`pickFromOtherSide` for what a tile does and `working` greying the others; New
  category's `createCategory()` now returns the name it picked): a tap is brief 81's
  `switchCategory(ids:to:span: .allMonths)` at once (by hand, every payment learned, one save and rebuild, its undo),
  after storing a category picked from the other side as offered here (brief 69). Brief 81's question about the shop's
  other payments is never asked: it is applied by itself only when every payment it would move is the same name's, same
  direction and Not sorted in the rebuilt dashboard (`QuickSort.takesFollowUp`; by construction they are in the card, so
  only payments imported while the flow is open, a shared file, qualify). Found while building it, and left alone: the
  question can also hold the shop's payments in the other direction (a card of their own), its payments under an own
  name (a card of their own) and its payments already sorted by the built-in list or a learned rule (the quick sort
  changes no sorted payment). **The flow** (`QuickSortFlow`, in `DashboardPlace.quickSort`, a sheet of `DashboardStack`
  at full height): the groups as they were when it opened, one outcome per card (`sorted(payments:)`, `skipped`, `gone`
  for one whose payments were all sorted meanwhile); Skip; Undo puts back the last card sorted (brief 81's single-use
  undo, so only the last; any later save refuses it with "Cannot undo because the data changed.", shown as a line), the
  card shows again and the cards after it come again. The look (Claude's): the bar "Not sorted" / "Nicht sortiert" with
  `navigationSubtitle` "3 of 12 · 41 sorted" / "3 von 12 · 41 sortiert" and Done (gone at the end, where the summary's
  Done is the way out); the list's thin bar for how far; the card (`palette.card`, the line, radius 14): the direction in
  small capitals ("MONEY OUT" / "AUSGABEN", "MONEY IN" / "EINNAHMEN"), the name in the payment page's title style (22 pt
  bold), the money signed as the payment page shows it (`palette.expenseText` / `palette.balance`, mono 20 bold), "18
  payments · Jan – Oct 2026" (Foundation's interval style: "Jan.–Okt. 2026"), a hairline and the example lines in quiet
  type; VoiceOver reads it as one (`QuickSortWording.spoken`), the tiles are buttons. Over the tiles "A tap sorts all 18
  and Aresium remembers the name." / "Einmal tippen sortiert alle 18, und Aresium merkt sich den Namen." (not "Ein
  Tipp", which reads as advice). Undo ("Widerrufen", the shared undo bar's word, iOS's own) and Skip ("Überspringen")
  in the selection's bottom bar (`BottomBar`/`BarItem`, shared with `SelectionBar` now). A tap sorts, a light haptic
  (`sensoryFeedback`, not for an undo), and the next card slides in from the right while the last fades (from the left
  after Undo; Reduce Motion: a fade). At the end a ringed check, "84 payments sorted" / "Nothing sorted", "From 9 names ·
  3 skipped" or "… Everything is sorted.", Done. **Where it starts:** (1) **the offer after an import** (`QuickSortOffer`,
  in the import result's place and card as brief 46's: `OfferCard`, shared with the messages' offer now): set by
  `ImportStore.finishIfDone` when an import in phone mode added payments (`offersQuickSort`); shown while payments are
  Not sorted once the import's work, the category picker and the result are gone, never over another window
  (`ContentView.windowOpen` or the flow), in the tour or behind the lock; it goes first, the messages' offer waits
  (`ReminderOffer.Moment.quickSort`). "34 payments not sorted" / "34 Buchungen nicht sortiert", "From 12 names. One tap
  sorts all payments of a name." / "Von 12 Namen. Einmal tippen sortiert alle Buchungen eines Namens.", **Go through** /
  **Durchgehen** (the flow) and **Later** / **Später** (also the swipe down). Answered by either, by opening the flow from
  Not sorted's card, or over when nothing is left Not sorted (`QuickSortOffer.expires`, so it never shows later without
  an import); the next import that adds payments offers again. The cards are **names**, not payees: the app calls
  whoever a payment is with its name everywhere (Search names, the name's page), and "payee" / "Absender" are one
  direction only. (2) **The card at the top of Not sorted's month list** (Current and Overview, both sides; while
  selecting it stays in its place, faded and taking no taps, brief 200; `DashboardStore.offersQuickSort(on:)`: phone mode while some name has two or more payments Not sorted):
  `QuickSortListCard`, a list row on the card colour with the line, the stack symbol in the day tile's place, "Sort name
  by name" / "Name für Name sortieren", "9 names · 42 payments · all months" / "9 Namen · 42 Buchungen · alle Monate",
  the chevron. Not in server mode. DEBUG (with `-samplePhone`): `-sampleQuickSort` (made-up people to go through: a
  relative's monthly transfers in and one payment back, a friend paid for a garage, a drinks shop),
  `-sampleQuickSortOffer` (the offer, as after an import), `-openQuickSort` (the flow at launch; `-quickSortSkip <n>`
  skips n cards, `-quickSortSort <category>` sorts the card shown, `-quickSortFinish` skips the rest: the end); the
  card: `-sampleCategory Uncategorised -sampleMonth <YYYY-MM>`. Tests: `QuickSortTests` (grouping: names, persons, own
  names, directions, covered rows, sorted payments out, ranking, all months, the texts; server mode; a tap: manual,
  learned, the next import sorted by it; Skip and Undo, a refused undo; the question only for the name's own Not sorted
  payments, newcomers taken; New category on a card; the offer's conditions and its end; the card on Not sorted; the
  words in both languages; VoiceOver's line), `TourTests`, `MessageScreensTests` (the messages' offer after the quick
  sort's). Real touches (a temporary UI test in `Aresus/AresusUITests` driving Aresium, deleted; 3 of 3 runs): the
  made-up bank file imported into the empty store, the picker ticked and closed, the result gone, the offer's Go through
  opens the flow; a tile sorts and the next card comes; Skip; Undo brings the sorted card back (and is then off); Done
  closes it and the offer does not come back; Not sorted's card opens the flow, Skip, a swipe down closes it.
  Screenshots: `build/99-{offer,list,person,shop,end}-{en,de}-{light,dark}.png`, red mode `build/99-person-en-red.png`
  and `build/99-offer-de-red.png`, contact sheets `build/99-sheet-en.png`, `build/99-sheet-de.png`,
  `build/99-sheet-red.png`.
  **New category where a category is chosen** (brief 60,
  Patrik after build 7: "otherwise you have to leave, create it, come back"): one piece for three places,
  `NewCategoryModel` (`Model/NewCategory.swift`: the alert's name, kept after a name problem; whether the alert shows;
  the busy state; the problem's line; `create(in:side:offer:)` resolves the name with `PhoneBackend.useCategory(named:side:sorting:)`,
  Settings → Categories' path with its name check and brief 36's icon and colour, then the window's `offer` puts it
  among its choices and picks it) and `Screens/NewCategoryPieces.swift` (`newCategoryAlert`: Apple's alert "New
  category" / "Neue Kategorie" with the field "Name", Cancel and Create / Anlegen; `CategoryMenuRow`). **The change
  window** (`RecategoriseSheet`, `TransactionDetailStore.newCategory`, `createCategory`): the grid's last tile, "New
  category" with `plus`, the category tiles' size, the second ink and the line's thin outline, no category colour; in
  Switch and Add, phone mode only, for money out and money in alike: the new category gets the payment's side
  (`CategorySide.spend` / `.income`), so the engine offers it in that direction immediately. Create rebuilds the
  dashboard and picks it (the target in Switch, an extra in Add); one
  made in this opening of the window comes last, just before the tile (`madeHere`), the next opening has the
  dashboard's order. While it is made the tile shows `BusyLabel` and the other tiles are greyed (0.4, `whileWorking`),
  the segmented control and Save are off and the swipe down is held. Nothing about the payment is saved before Save;
  after a Switch the shop question follows as for any category, and the shop learns it. Cancel after making one keeps
  the category. **The receipt window and Add cash** (`ReceiptCheckView`, `CashEntryView`, both `CategoryMenuRow`): the
  category menu ends with "New category…" / "Neue Kategorie …" (`plus`, after a divider); the same alert; the category
  is made, offered and picked there (`ReceiptCheckModel.createCategory`, `CashEntryModel.createCategory`; in Add cash for
  spent and received alike, with the side of that window); while it is made the chip shows a spinner and the menu is
  off. A name problem (built-in or reserved) makes nothing and keeps the typed name for the next tap: one
  line in the window's error style (the change window's under the grid, `FormProblem` under the menus' row) with
  Settings → Categories' words (`LedgerError`). Create is off while the name is empty or spaces; the keyboard's Return
  creates, and on an empty or spaces-only field iOS's Return closes the alert like Cancel (nothing made, no line).
  Create is a plain button in the window's ink, not Apple's filled default button, which iOS draws in the system blue
  whatever the tint (checked 2026-10-31). The windows' Cancel still asks first (a category picked is a change) and the
  category stays after it. **The dashboard catches up:** a category made in the receipt window or Add cash whose window
  was then cancelled changes no payment, so `DashboardStore.reloadIfCategoriesChanged()` (called by
  `TransactionDetailStore.load` in phone mode) builds the dashboard again when the store's chosen categories differ from
  the ones it was built with (`builtChosen`), so the change window offers it. The tour's switch step keeps the tile; a
  category made there goes with the tour's store. DEBUG (with `-samplePhone`): on a payment's page with
  `-sampleRecategorise switch|add` (and in `-sampleReceipt`'s or `-addCash spent|received`'s window): `-newCategory` (the
  alert), `-newCategoryName <text>` (typed in it), `-newCategoryCreate` (Create: picked, or the problem's line;
  `-holdWork` keeps it busy; `NewCategoryModel.debugLaunch`); on the page also `-newCategorySave` (then Save) and
  `-newCategoryAnswer only|all` (the shop question answered). Tests: `NewCategoryInChangeTests`,
  `NewCategoryInWindowsTests`. Screenshots: `build/60-*.png` (the menus open: a temporary UI test with real taps,
  deleted). **"All from <name>"** (a card under the date on the
  payment's page, a withdrawal's too, and since brief 47 a receipt's and a cash entry's page opened from a list,
  `ReceiptPageView(nameLine:openName:)`, `DashboardStore.receiptNameLine`; only when the group has more than this
  payment; the long press; the swipe) opens the **name's page** (`Screens/NameScreen.swift`, `DashboardRoute.name`,
  pushed on the dashboard's stack, so the arrow and the back swipe work; from the payment's sheet it closes the sheet
  first): the count and range, Spent (and Received when any), the switch (brief 53), the graph above the months
  (`showsGraph` = the Graph setting), then the months with a payment of the name oldest first, as a category's months
  (`ValueRow` with the chevron; a month without the name has no row). **The name's months** (brief 55, Patrik's fifth
  round: the payments listed below the months were "very weird"; "make each month just as the other months"): a month's
  row or its graph point (`SeriesChart.onPick`, the one hook) opens that month's payments of the name on a page of its
  own (`NameMonthScreen`, `DashboardRoute(name:month:)`, pushed like the others): the name as the header's title, "Oct
  2026 · activities" / "Okt. 2026 · Buchungen" under it (a category's month list's line), the arrow and the back swipe
  (Apple's, `BackSwipe` unchanged); its rows a category's month list's, in its order (`Transaction.listOrder`, by day):
  `PaymentRow` with tap, long press and the swipe's All, no Add up (every row is the same name). All, "All with this
  name" and a payment page's "All from" there go back to the name's page below instead of stacking a second copy
  (`DashboardPlace.open`). A month with only money the other way (a refund of a shop, no purchase) keeps its row, its
  payments being nowhere else: an empty bar and the money signed in its colour ("+€80", `NameWording.otherSide`). The
  page (with every month's rows) is built once per dashboard (`DashboardStore.namePage`, cached by `revision`), never
  in `body`. After a row's page, change sheet or Edit window closes (each now tells its list, `closed`), the month's page
  follows a rename that took the name along, together with the name's page below (`NamePageStep.follow`,
  `DashboardPlace.follow`, in place), and goes back one page when the month has no payments of the name left
  (`NamePageStep.back`: renamed alone, moved out of the counted payments). The tour never reaches it. DEBUG:
  `-openNameMonth <YYYY-MM>` with `-openName <text>`; `-sampleDay31` adds a made-up REWE purchase on the newest 31st,
  `-sampleRefund` a made-up Zalando refund this month (a month with only a refund).
  Tests: `NameMonthsTests` (`DayWordingTests`, `DashboardPlaceTests`). Screenshots: `build/55-*.png`. **The day's
  tile** (brief 55, Patrik: "44×" next to "44" was confusing): every tile showing a date (a payment's row, the Cash
  page's movements, the receipt check's and the file check's payments) writes the day as the language writes it alone,
  German "4.", English "4" (`DayWording.alone`, one function; Foundation's lone day has no dot in German either); the
  tile keeps its size and shrinks its words at the largest text sizes (`DayTile`, "31." included). **The swipe** (`Screens/RowSwipe.swift`: `RowSwipeRule`, tested, inside a `UIPanGestureRecognizer`
  subclass, since a plain recognizer got no moves inside the scroll view): only a drag at least twice as sideways as
  vertical and leftward (rightward on an open row closes it); it opens at 84 pt and fires at 55 % of the row (at least
  168 pt) with a haptic at the threshold; one row open at a time, closed by a scroll or a tap elsewhere; the action is a
  quiet grey "All" with a stack icon, VoiceOver's action "All from <name>", Reduce Motion fades it in. The month's list,
  the name's page and the Cash page (brief 47) share one row (`Screens/PaymentList.swift`: `PaymentRow`, generic over
  its label: `PaymentRowLabel`, or the Cash page's `CashMovementRow`; tap, long press, swipe, and the windows they
  open). The long press adds Rename (it opens the payment's page with the name's field ready, `PaymentRowMenu.rename`;
  no double tap on rows, which would delay every row's tap) and **"All with this name"** / "Alle mit dem Namen"
  (brief 47: every entry short; "All from <long bank name>" could not be read; the lifted row shows the name; "dem",
  not "diesem", which wrapped the entry) where the page offers them (`PaymentRowAction`); receipts' and entries' rows
  add it too now that their page has the card.
  **Adding up names in a category's list** (brief 53, Patrik's D after build 4: "10 Vinted purchases in Clothes in
  October" as one row; `Model/PaymentSums.swift`, `Screens/SummedRows.swift`; phone mode only, server rows have no
  names): only how a month's list of a category shows (Current and Overview); totals, the category's numbers, the export
  and the engine never change. **Choices** (`SumChoices`, the more specific wins): everywhere (Settings → Dashboard →
  "Add up same names" / "Gleiche Namen summieren", off by default), a category (the icon), a name (the name's page's
  switch "Add up in every category" / "In jeder Kategorie summieren", on a card under the totals), a name in a category
  (the swipe and the long press); every level but everywhere on, off or not set, and **a choice equal to what the levels
  above give is not set** (fix 58, Patrik 2026-10-31: in Oct 2026 Kleidung the icon did nothing after Vinted was added up
  and separated by hand), so Separate after Add up, or a switch turned back, leaves nothing that outvotes a later choice.
  **The icon shows what the list shows** (on while every name with two or more payments there is one row,
  `PaymentList.allSummed`), not the category's own choice; its tap (`toggleCategory(_:names:)` with the list's
  `sumKeys`) gives the category the opposite, clears the name-in-this-category choices there and gives the tap's choice
  to any name there whose own (name page) choice says otherwise, so it always means all or none in that list; the name
  page's switch sets the name and clears its per-category choices. Keyed by the category's stable id (`DashboardStore.sumCategoryKey`: "id:groceries"
  for Groceries and Lebensmittel, "id:custom-…" for one's own; the dashboard's own entries such as Refunds by name) and
  the opaque `nameKey`. Kept in Aresium's defaults (`aresium.sums`, JSON, `PaymentSums(defaults:)`), not in the export,
  deleted with Delete data and "Forgot the code?" (`ModeStore.deleteLocalData`); tests and samples have an empty set in
  memory (`DashboardStore(sums:)` defaults to it), the tour too, whose lists offer adding up on its own choices since
  brief 59 (its addUp, sumIcon and allFrom steps; nothing is added up before them, so the rows earlier steps point at
  stay single).
  A choice keyed by a name key that later changes (a shop renamed gets an `own:` key) no longer applies. **The list** (`PaymentList`, built once per change of the dashboard or
  the choices: `DashboardStore.paymentList(category:month:side:)` caches by `DashboardStore.revision`, which counts every
  new dashboard, and `PaymentSums.revision`; the header's icon and the list read the same one): a name with two or more
  payments there that adds up is one row where its newest payment would be (covered rows and rows without a name key
  stay single). **The summed row:** the day's tile with a second tile peeking above it (`StackTile`, a stack, as SF
  `square.stack`) and the count ("5×"), the name as the newest payment shows it, the days ("4–28 Oct" / "4.–28. Okt.",
  Foundation's interval style), the net sum in cents with the list's sign and colour. A tap opens it in place: a card
  (`palette.card`, the line, radius 12) holds the summed row, a hairline and its payments, each the usual `PaymentRow`
  (tap, long press, swipe All); a tap closes it. Opening, closing, Add up, Separate and the icon animate with a spring
  without bounce (0.38 s, `SumMotion`; Reduce Motion none): the card grows and clips its payments to its height, the rows
  below glide. **The swipe** (`RowSwipeRule` with `count`): a single row whose name has more payments in the list shows
  **Add up** / **Summieren** (`rectangle.compress.vertical`) and All; a summed row **Separate** / **Auflösen**
  (`rectangle.expand.vertical`) and All; members of an open sum All only. The inner action is a raised tile (`Ink.card2`,
  the edge, the first ink), All keeps its grey fill. Each action 84 pt (drawn 78, 6 pt gaps): one opens at 84, two at
  168; the full swipe (the last, All) at max(open + 84, 55 % of the row): 168 for one (as before), 252 for two on an
  iPhone 17's 378 pt row; past it All takes the whole room (`RowSwipeRule.widths`). VoiceOver actions by the same names.
  The actions' words grow only up to the largest standard text size (fixed tiles; "Summieren" was cut at the largest
  accessibility size), and a row's day shrinks into its tile there instead of turning into "…" (`DayTile` for every
  tile since brief 55).
  **The long press** (`DashboardStore.rowActions(for: PaymentListEntry)`): a single row with a group in the list adds Add
  up before "All with this name"; a summed row offers Separate and "All with this name". **The icon** (`SumCategoryButton`
  in `ScreenHeader`, after red mode's X and before the gear): `square.stack` on the wall (brief 56: no box; on in full ink
  with `square.stack.fill` at 24 % under it, its front tile lit, off the outline in muted ink; the filled symbol alone
  reads as a jar); only on a category's month list while some name has
  two or more payments there (not the Cash page, a name's page or a covered list); VoiceOver "Add up same names", a
  toggle, On/Off. DEBUG (with `-samplePhone`): `-sampleSums on` (everywhere on, in memory), `-sampleSumOpen <text>` (opens
  that summed row; `-sumsDelay <s>` first), `-sumsSlow <s>` (the motion stretched, for screenshots halfway),
  `-sampleSwipe <pt> -swipeRow <text>` also on a summed row. Tests: `PaymentSumsTests` (`SumChoicesTests`,
  `PaymentSumsStoreTests`, `PaymentListTests`, `RowSwipeTwoActionsTests`, `PaymentSumsStoreFlowTests`: the levels, the
  clearing, a language switch, Delete data, the tour, the grouping, the menus). Screenshots: `build/53-*.png`.
  **Own names** ("Eigene Namen") is a toggle in Settings → Your data on this iPhone (`DashboardStore.setOwnNames`).
  Launch arguments (DEBUG, with `-samplePhone`): `-sampleNames` (made-up own names), `-ownNames off`, `-openRename` (the
  name's field open), `-renameText <text>`, `-renameSave`, `-renameBankName`, `-openAllFrom`, `-openName <text>`,
  `-sampleSwipe <pt> -swipeRow <text>` (on the Cash page too), `-sampleLongName` (three payments under a long made-up
  bank name this month; the engine sorts them into Clothes), `-sampleShopReceipt` (a cash receipt from the sample's
  LIDL, so a receipt's page shows the "All from" card).
  Tests: `PaymentNameScreensTests` (brief 47: `RenamePlanTests` for the field's start and the bank's name kept for one
  payment, with export and restore; `PaymentRowMenuTests` for receipts' "All from" and the Cash page's rows).
  Screenshots: `build/44-*.png`, `build/47-*.png`. Real-touch checks (a temporary UI test, deleted): a slanted vertical
  drag scrolls and opens nothing; the back swipe from the middle still works 6 of 6. **The back swipe's distance**
  (brief 47, Patrik: "about half the screen" on a month's payments and the name's page; measured with real touches on
  the iOS 27.0 simulator, iPhone 17, 402 pt wide, a binary search to 8 pt; slow = 150 pt/s held still before letting go,
  flick = 3000 pt/s): a month's payments, the name's page, a category's months and Apple's own Settings → General all
  go back after the same distance: a slow drag from the edge 189 pt (47 % of the width), from the content (x 100) 215 pt;
  a flick from the edge 99–105 pt, from the content 53 pt; a thumb resting 0.3 s before it drags the same. That is
  iOS's own rule (a slow drag goes back past about half the width, a flick at once), so the row swipe and the long press
  take nothing from it and the gesture stays the system's. Measuring on a DEBUG launch that pushes screens (`-sampleMonth`,
  `-openName`) misleads: count the pushes, and the month list's launch actions now act once (`launchActionsDone`), as
  they reopened the name's page each time the list showed again.
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
  `InfoPlist.xcstrings`. **Contact & support** always without a login: the `contact` path (above). **Push:** Aresium never
  registers a device (only the cleanup-only center that removes the other apps' devices when someone logs out here).
  **Local messages** (brief 45, logic only; Settings and the offer are brief 46): phone mode uses
  `UNUserNotificationCenter`, never remote push. `DashboardStore.messages: AresiumMessages?` is the page's model;
  only the live `ContentView` installs it (`installMessages(lock:active:)`). Tests and the server sample have none (the
  phone sample a pretend one since brief 46, below); the tour
  suspends scheduling and removes Aresium's pending/delivered messages until it ends. The model and its serial queue
  survive a language restart (`AresiumMessages.live`); the rebuilt store supplies the new language and dashboard.
  All notification-center calls and review planning run on `MessageScheduler`, a worker actor. Account reductions
  run on the ledger's own executor (`MessageScheduler.swift`'s extension), without returning its payment array.
  **Brief 46's API:**
  - `preferences: MessagePreferences` (read-only): `enabled` (default false), `importReminder` (true),
    `interval: MessageInterval` (`week`, `fortnight` default, `month`), `monthReview` (true), `hour` (18), `minute` (0).
    Copy the struct, change a field and call `setPreferences(_:)`; `setEnabled(_:)` changes just the master switch.
    Settings/history live under `aresium.messages.preferences` and `aresium.messages.history` in UserDefaults;
    `aresium.messages.progress` keeps consumed reminder slots and their scheduled dates (no amounts).
  - `authorization: MessageAuthorization`: `notAsked`, `allowed`, `denied`; `error: String?` reports a scheduling
    failure. Enabling asks once for **alert and sound**, no badge; a refusal leaves all choices intact. `refresh()`
    refreshes permission and schedules again (also called on foreground/launch). `idle()` awaits queued work.
  - `shouldOfferReminder: Bool`: true after an import added payments, while Messages is off and the offer was never
    answered. `finishReminderOffer()` consumes it, including Not now; the offer page saves its switches separately.
  - `recordImport(accounts:addedPayments:at:)`: stable account IDs and a completion time; every account timestamp
    advances, but the reminder and offer move only with new payments. `ImportStore` calls `importFinished(_:ledger:)`
    after each batch, including confirmed layouts, before rebuilding the dashboard. Each file read into an account counts
    as an import of it, also one that added nothing (`PhoneImportResult.accountID`).
  - `dashboardBuilt(_:)`, `setPhoneMode(_:ledger:)`, `setTour(_:)`, `setLocked(_:)`: wired to dashboard builds,
    backend switches, the tour and `AppLock`'s saved settings. `deleteAll()` resets all message defaults and removes
    owned pending/delivered notifications; `ModeStore.deleteLocalData()` awaits it (Settings and Forgot the code).
  Reminders are three absolute one-shot requests (`aresium.reminder.1...3`), each another interval after the anchor,
  at the chosen wall-clock time, using calendar arithmetic across DST. The anchor is the last import that added
  payments; before one exists it is when the reminder was enabled. Past dates are never queued again; persisted elapsed slots prevent a time/interval change or relaunch
  from resetting the limit. An import starts the three dates again. Text: "Time for new statements" / "Your last
  import was 14 days ago." (calendar days at delivery, then 28/42 for a fortnight); before any import, or with the lock
  on, the body is "Import your statements to keep your dashboard up to date." (the lock hides the day count too).
  The next review is at the next 3rd, for its preceding calendar month, only with payments in the dashboard. It uses
  `byMonth`'s expense/income/category totals unchanged; complete requires every participating ledger account to have
  an import timestamp at or after the following month's midnight. No complete history means "Import your statements
  to complete October."; complete: "October: 1,234 € spent, 2,100 € in. Most on Groceries: 320 €." (up to two decimal
  places); no spending omits the category sentence. Locked: "Your October review is ready." Turning the lock on also
  clears delivered messages, so earlier numbers disappear. Turning Messages off removes only `aresium.reminder.` and
  `aresium.review.` pending/delivered identifiers; unrelated notifications are preserved.
  **Taps:** Aresium's own `InboxLaunchDelegate` is the notification delegate (set before launch finishes), retaining
  a tapped URL in `MessageTapRouter`; no shared push registration changes. `ContentView` feeds it into the existing
  file/widget URL route, ending a tour first. `AresiumURL.importData` (`aresium://import`) opens phone mode's file
  picker after the store and lock are ready; `.review("2026-10")` (`aresium://review/2026-10`) opens that month's
  dashboard totals/categories/graph (`DashboardStore.showReview(month:)`). This month stays focused until the app goes to the background, a widget/start
  link, backend switch or a rebuilt root; `showReview(month: nil)` restores the latest month. No new screen.
  **DEBUG verification:** `-enableMessages -logMessages` enables live local messages and logs owned pending IDs;
  never combine it with sample/test arguments (those install no live model). It uses the normal interval, with no
  accelerated delivery argument. Verified on `codex-45` (2026-10-30): Allow, three pending reminders
  (`build/45-pending.log`), and the import route opening the file picker (`build/45-import-route.png`).
  `MessageTests` injects clock, calendar and center; no system scheduling in tests.
  **English catalog keys added, German left to Claude:** "Time for new statements", "Your last import was %lld days
  ago.", "Import your statements to keep your dashboard up to date.", "Month review", "Your %@ review is ready.", "Import
  your statements to complete %@.", "%@: %@ spent, %@ in. Most on %@: %@.", "%@: %@ spent, %@ in.".
  **Settings → Messages and the offer** (brief 46, the screens; `Screens/MessagesSettings.swift`, words and choices in
  `Model/MessageSettings.swift`): phone mode only, a section "Messages" / "Mitteilungen" of its own after "Your data on
  this iPhone" and before Lock (the messages are about the data; Dashboard stays last, above Appearance), one row
  "Reminder and review" / "Erinnerung & Rückblick" (the ampersand keeps it on one line beside "Nur Erinnerung") with its
  state on the right (`MessageWording.state`: Off, On, Reminder only, Review only, None
  chosen, Off in iOS). The page: the Messages switch (iOS asks the first time, brief 45); while on, Import reminder with
  its line and How often (Apple's menu from the column check's `MenuChip`: every week, every 2 weeks, every month), Month
  review with its line, Time (Apple's compact time picker, `MessageTime`); while iOS has the notifications off, a line
  and Allow in iOS Settings (`openNotificationSettingsURLString`), the switches keep what was chosen; `error` as a
  `FormProblem`; the note "made on this iPhone, nothing sent", plus "no numbers" while the lock is on. **The offer**
  (`ReminderOffer`): in the import result's place and card (`BottomToast` in `Screens/ImportControls.swift`, the
  result's chrome and swipe, shared since brief 46), only once the result (with its send card), the category picker
  after an import, the import's work and every other window are gone, never in the tour or behind the lock
  (`ReminderOffer.shows`, built from the stores by `ReminderOffer.Moment(messages:imports:…)`): "Remind you to import
  new statements?", the line names the reminder's interval and the review, Turn on (both messages, interval and time
  kept; then, once iOS allowed, "Messages are on. You can change them in Settings." in the result's place) and Not now
  (also a swipe down); both answer it for good. The start screen's expense graph in red mode draws the light ink
  (`Palette.expense`; the website's black read at about 1.3:1 on the app's darker red), as the widget's line; income
  keeps its green (about 10:1). **DEBUG** (with `-samplePhone`/`-samplePhoneEmpty`; the sample gets a pretend model,
  `Model/MessageSample.swift`: its own defaults emptied at launch, a center that reaches nothing in iOS):
  `-openMessages` (with `-openSheet settings`: the page), `-sampleMessages on|reminder|review|none` (Messages on with
  both, one or none), `-sampleNotifications allowed|denied|notAsked` (the pretend iOS's answer; allowed by default),
  `-sampleReminderOffer` (the sample may offer: a made-up import at launch, so the offer shows on the dashboard; with
  `-samplePhoneEmpty -sampleImport -samplePickerDone` after the picker and the result, as live), `-sampleMessagesFail`
  (planning fails: the page's failure line). Without these the sample neither offers nor plans anything. Tests:
  `MessageScreensTests` (the row's words, the page's words and time, the offer after the picker and the result and never
  with the send card, once; Turn on; the red graph's contrast). Screenshots: `build/46-*.png`, contact sheet
  `build/46-sheet.png`.
  **Current view:** a category opens this month's payments directly (`CategoryRoute`; the widget's category links too);
  Overview keeps the month list first. **Screens** (`Screens/PhoneScreens.swift` and `Screens/FileCheck*.swift`,
  Claude's look from the dashboard's rows, `CategoryTile`/`DayTile`, and the Settings pieces; ink only): **the first
  screen** (brief 25, Patrik 2026-10-27; `PhoneFirstScreen`, logic `Model/FirstScreen.swift`): while phone mode has no
  payment, a calm empty state a little above the middle (a mark in a thin circle as the store's own states): "No data
  yet", one line on what Aresium does and that everything stays on this iPhone, **Import data** (the main button) and
  **Start tour** (quiet), then the quiet links "How do I get my file?" and "Restore from an export"; it ends with the
  band. **The file first** (brief 27, Patrik 2026-10-27: Import data had opened the categories, which felt wrong):
  Import data, the dashboard's import button and the guide's Choose file open the file picker at once. Choosing
  categories is no step of its own: **when an import in phone mode ended and added payments while no category is
  chosen, the category picker opens** over the dashboard with the payments already in, whatever brought the files (the
  file picker, the share sheet, the file check window), once per import (several files: after the last, also after a
  file check that was skipped). Not after a cancelled picker, a failed file, a file whose payments were all there
  already, a restore from an export, the tour, or with categories chosen. It is decided in one place, the import's end
  (`ImportStore.finishIfDone` → `asksForCategories`, with `AresiumBackend.waitsForCategories`; ContentView only presents
  it, once no other sheet is open). Its line on top: "Your payments are in. Aresium sorts them as you tick." Ticking
  sorts the waiting payments at once (`PhoneBackend.choose`); closing it with nothing ticked is allowed (the payments
  stay Not sorted and the next import asks again). **The result line stays true:** the import's line ("4 new · 0
  already there · 0 sorted · 4 not sorted") waits under the picker and, when it closes, is counted again from the store
  for that import's own payments (`PhoneImportResult.newIDs`, `AresiumBackend.recount`), then goes after the usual
  pause; the files' lines claim no sorting. What shows is `MainScreen.choose` (the tour, the store's state, the first
  screen, the dashboard): after the tour, finished or ended early, the first screen is back while there is no data, so
  the made-up data is never shown outside the tour. Then the category picker (the default list by group, nothing
  ticked at first, one's own names; unticking a category with payments asks where they go, Not sorted first; **each row
  shows a quiet number** (brief 27, Patrik 2026-10-27; `PhoneBackend.categoryCounts`): a ticked category and one's own
  the payments in them, a default one not ticked how many of the payments waiting as Not sorted it would get if ticked
  (one dry run of `sortPayments` over the waiting payments with every default category besides the chosen ones; nothing
  stored; an estimate, since a learned shop's unticked category can take a payment), none at 0 or before any payment,
  counted again after every change; in muted ink before the tick, under the name at the accessibility text sizes; read
  out as "34 payments"; with numbers on the rows the picker's note adds "The number by a category is how many of your
  payments it has, or would get once ticked."; in every picker: after an import, Settings → Categories, the tour's
  Settings; one's own rows say their side and every ticked row whether it is also offered the other way, brief 70's
  "Category sides on screen" above), after a Switch the alert "Also the other payments from <shop>?" (the count on its button), the store's
  opening state.
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
  the account server's `bank_formats` (no token, `Accept-Language` of the request; ares-empire `docs/ACCOUNTS.md` → Bank
  formats). Not now, closing the result and Send each mean the layout is never offered again (a SHA-256 of its separator
  and header in the outbox's file, below). Sent: "Thank you. Aresium learns your bank with the next update."
  **"My bank is missing"** (brief 25; `Model/BankRequest.swift`, `Screens/BankRequestView.swift`): when the guide's
  search finds no bank (`BankGuide.results` → `.unknown`), the list shows Another bank's steps in place under a card,
  "We don't know this bank yet. The general steps below may help." with **Tell us about your bank**: it opens the name
  (prefilled with the search text, following it until edited) and Send, so two taps; Another bank's own page ends with
  the same card ("Your bank is missing? Tell us which one.", the field empty and focused). Send posts `{bank,
  app_version, language}` to the account server's `bank_requests` (brief 26, ares-empire; `Accept-Language`, no token;
  200, 400 with `message` and `data.bank.code`, 429 at 5 an hour per address). Sent: "Thank you. We'll look at adding
  it." Not in the tour (its guide gets no outbox: nothing real is sent there). **One outbox for both**
  (`Model/BankOutbox.swift`, generalised from brief 23's `BankFormatOutbox`): `BankOutbox` carries a `BankSubmission`
  (`.format` or `.request`, each to its own collection through `BankOutboxAPI`) and keeps what could not go at once in
  one file, `Application Support/Aresium/bank-outbox.json` (`PhoneStorage.bankOutboxURL`: the request bodies with their
  kind and failed tries, and the asked format layouts; brief 23's `bank-formats.json` reached no phone, so nothing moves
  over; an entry without a kind still reads as a format), deleted with Aresium's data. Offline or a server error: sent by
  itself at the next start or foreground (`sendWaiting`, one round a minute), at most 3 tries (a try without a
  connection does not count); a 400 is final (a card or form still on screen shows the server's sentence; a 400 about
  the name only lets the person type it again); a 429 waits for the next start. **A name that looks like personal
  data** (an IBAN, an email, a date, an amount, a long number) is not sent: "Only the bank's name, please: no account
  number, IBAN, email, date or amount." under the field, for both kinds. The rule is the engine's own (`looksPersonal`,
  which `shareableLayout` applies to a format's words; the bundle exports no `looksPersonal`, so the bridge's
  `personalData` runs it through a one-column `shareableLayout`, `AresiumEngine.personalData`), loaded the first time a
  name is checked (`BankNameCheck`); the server checks again. Sample mode only pretends. The dashboard's own
  "Uncategorised" (engine and server) shows as "Not sorted" in both modes and the widget through `CategoryName.shown`
  (AresiumShared); Switch, Add, routes and links keep the real name. **The payment page** (brief 28, Patrik 2026-10-27;
  `Screens/TransactionDetailSheet.swift`, its words in `Model/PaymentPage.swift`, one place for both modes): "Payment" /
  "Buchung"; the shop, the amount, the booking date written out ("Sunday, 4 October 2026" / "Sonntag, 4. Oktober 2026");
  the category's chip with a pen (brief 47: both open the change window), the sentence on why it is there moved into that
  window's top (`PaymentWording.categoryReason`; phone `structural` "A transfer
  between your own accounts.", `learned` "Aresium learned this from a change you made.", `starter` "Sorted by Aresium's
  built-in list.", `manual` "You chose this category."; server `rule` "Sorted by a rule.", `llm` "Sorted
  automatically."; nothing for `none`, a payment not sorted, or a value it does not know); then Account (name,
  IBAN in groups of four, "From your PayPal file" only when a PayPal payment's account is not called PayPal), To / From
  (An / Von) by the direction, Payment text (Verwendungszweck; not when it repeats the title), Balance after, Value date
  only when it is another day, and the server's Location, Trip, Kind of place (only the place types it knows) and
  Recurring. No Source, Booking date or External ID rows. The bank's own row comes last, closed ("As in your bank's
  file", or PayPal's). The labels form one column as wide as the longest (a `Grid`), above their values at the
  accessibility text sizes. Its Edit and Unjoin are Apple's regular-size bordered buttons (brief 41; drawn 32 pt
  tall, they take taps about 5 pt beyond their edges by themselves, measured on iOS 27.0; neither a tap area in the label
  nor a content shape on the button widens that).
  **Comfort on the dashboard** (brief 41, Patrik's approved list of 2026-10-30,
  `docs/reviews/2026-10-30-swipe-and-comfort.md`): **a long press on a payment row** (a month's list, both modes) is
  Apple's context menu with what the row's page offers (`Model/PaymentRows.swift`: `DashboardStore.page(for:)` decides
  what a row's tap opens and `rowActions(for:)` its menu, so the two never differ): a payment Change category (only when
  its page shows Change), opening the same change sheet at once (`TransactionDetailStore.beginRecategorisationFromRow`:
  it fills as the payment loads, or says why it could not, with Retry) with the same flow after it (the shop question,
  learning, the tour's `paymentRecategorised`); a receipt or cash entry row Edit (the window its page's Edit opens,
  `ReceiptEditSheet`; if it cannot open, the row's page opens); a withdrawal's covered row nothing (its long hold
  opens its list, as a tap). The Cash page's movement rows have the same tap, long press and swipe since brief 47
  (`DashboardStore.cashRows`: each movement's dashboard row; one the dashboard lists nowhere only opens its page). The back swipe and
  this menu are the dashboard's shortcuts (`DashboardStack.shortcuts`): the tour turns both off while it holds the
  screen (at the payment step the ringed row must open the page the card speaks of), except the rows' swipe and long
  press at its swipe steps (`rowShortcuts`, brief 59). **The import result goes with a
  swipe down** (`ImportStore.closesBySwipe`: where Dismiss or the send card's Not now would, never while Retry and
  Discard are offered or the format is sending, nor while the result scrolls; VoiceOver's escape does the same); a
  success still goes by itself after 4.5 s. DEBUG `-sampleBannerDrag <points>` shows it moved as halfway through the
  swipe (with `-sampleImportResult` or `-sampleFormat`). **Tap areas of 44 pt** (`minimumTapArea()` in `Screens/Components.swift`:
  the area grows around a control drawn smaller, layout unchanged): the result's Dismiss, Retry, Discard, "What is
  sent?" and Not now, the header's 42 pt buttons (`IconButton`, `headerButtonFace`) and the import button; the
  Expenses/Income dots are 44 × 44 pt each. Tests: `DashboardComfortTests` (`PaymentRowMenuTests`,
  `ImportBannerSwipeTests`, `LogOutQuestionTests`). Screenshots: `build/41-*.png`.
  **The graph and the header** (brief 56, Patrik's fifth round of 2026-10-31, items 5–7 in
  `docs/reviews/2026-10-30-aresium-phone-test.md`). **Reading a graph** (every `SeriesChart`: the start screen's day and
  month graphs, a month's page, a category's months, a name's months): a finger held still for 0.25 s on the graph
  (`ChartHold`, UIKit's long press, `ChartReading.holdDuration`, 10 pt of wander) and then followed shows a dashed guide
  line (`Palette.guide`, the website's `--guide`), a dot on the line ringed in the wall's colour and a one-line chip just
  above the plot, over the axis's "EUR" (the website's `.chart-tip`: the day written out "Wed 14 Oct" / "Mi. 14. Okt."
  or the month "Sep 2026", a dot in the line's colour, the amount to the cent; `ChartReading.chip`, `ChartPoint.title`,
  the nearest point `ChartReading.nearest`), a selection haptic per point; letting go hides it. A drag that moves before
  the hold is up stays the scroll's, the pages' or the back swipe's; once the hold has begun they give way until the
  finger lifts. A short tap opens a month where one opens (`onPick`): Overview's graph that month's page, a category's
  that month's payments, a name's its month (brief 55); a day graph's that day's page (brief 77). VoiceOver reads the points as
  before (the finger's layer is hidden). DEBUG `-readGraph <index>` shows the chip on that point (every graph shown);
  the debug log category `graph` records each point read (the real-touch check reads it). **A month's page**
  (`DashboardRoute(monthPage:side:)`, `MonthScreen`, pushed on the dashboard's stack; the header shows the month and
  "Expenses and income" / "Ausgaben und Einnahmen"): that month as Current shows this month, the start screen's pages
  (`DashboardPages`) over `DashboardScope.month(key)`. `DashboardStore` serves every scope (`.current`, which is the review
  month while one is shown, `.overview`, `.month`): `totals(_:)`, `rows(side:scope:)`, `startChart(side:scope:)`,
  `rangeLabel(_:)`, `route(category:side:scope:)`, `cashRoute(_:)`, `cashUnaccounted(_:)`, `monthPage(atChartIndex:side:)`;
  the older `current:` forms call them. Its categories open that month's payments, its Cash row that month's Cash page.
  Its Expenses and Income turn only with the dots (they slide; `DashboardPages(swipesPages: false)`): it is a pushed
  page, so a swipe right goes back from either side, as on every pushed page (with the pager there, a swipe right on
  Expenses only bounced; real touches, brief 56: middle swipe back 4 of 4, edge swipe at 400 pt/s 5 of 5; a synthetic
  1500 pt/s flick from x = 2 right after a push was lost 3 to 4 of 5 there, on a category's page and on main alike). A
  sideways swipe to the left that starts on a category row there opens that row (seen once; the row's button takes it).
  DEBUG `-openMonthPage <YYYY-MM>` (with `-samplePhone`) opens it at launch.
  **The graph moves away** (Settings → Dashboard, under Graph and only while the graph shows: "Graph moves away when
  scrolling" / "Diagramm weicht beim Scrollen aus" (the Graph row is "Diagramm"), one line; `aresium.graphMoves`,
  `GraphMotionSetting` beside `GraphSetting` in `Model/GraphSetting.swift`, on by default, not in the export; the tour
  takes it when it starts, `TourModel.graphMoves`): the graph is the first part of its list (each start page and
  month's page, a category's months; the name's page always had it so), so it scrolls up with the rows and nothing of
  its own runs per frame (no view body, no state; the pages line up only when a scroll rests); off, it stays above the
  list as before. Measured on the simulator (Time Profiler, the same eight finger-held 400 pt drags each way): no hang
  either way; 2.8 s of main-thread time with it on against 2.0 s off over the run, mostly SwiftUI's own updates of the
  larger moving content (the graph and the rows it uncovers); Aresium's code under 4 % of it (the graph's axis labels,
  which Swift Charts asks for again while the graph moves, and the pages lining up at rest). Instruments' Hitches do not
  run on the simulator, so frame drops are for the phone to judge. The range picker has its own row under the header; the Expenses/Income dots stand under it,
  above the pages, so they are always in reach; a sideways swipe moves a whole page with its graph and heading. When a
  page's list comes to rest, the page beside it lines up (`GraphMotion.follow`: the same place while the graph is partly
  there, at least the graph's height while it is wholly away), and again as its first sliver comes into view (a page
  out of sight may not take a scroll); while the graph moves, a page's content is at least the screen plus the graph,
  so two rows can take it away as well. DEBUG `-scrollGraph <points>` scrolls the shown page that far. **The header**
  (`ScreenHeader`, every screen alike): each button on the wall without card or outline (`HeaderButtonLook`: a 19 pt
  symbol in the second ink, drawn 42 pt, taps over 44 pt, 44 pt apart): red mode's X first (the others keep their
  places when it comes), then the page's own (the start screen's search, brief 77, and import button, beside the gear
  since brief 56, with its menu and spinner; a category's select icon, brief 82, and icon of adding up), then the gear; the title stays in the middle of the screen while it
  fits (`HeaderLayout`). The tour's `.search`, `.importButton` and `.settings` rings follow them there. Tests:
  `GraphAndHeaderTests` (`ChartReadingTests`, `MonthPageTests`, `MonthRouteTests`, `GraphMotionSettingTests`).
  Screenshots: `build/56-*.png`. Settings →
  About → Fonts & licences also lists the shop list's name-suggestion-index notice (BSD-3-Clause,
  `BundledLicence.shopList`, Aresium only). **Engine:** `bash scripts/aresium-engine.sh` runs `npm run engine` in
  aresium and copies the bundle (its commit in `Engine/engine-version.txt`), the engine's test files and the licence
  notice (`Engine/name-suggestion-index-licence.txt`); the bundle is never edited by hand. A confirmed layout keeps every field the engine gives it: `CsvLayout.idStyle` ("vrbank", aresium brief 85) carries the id formula that keeps a VR Bank file's ids when a spreadsheet re-saved it (`LayoutIdStyleTests`); a new engine layout field needs its Swift twin, or saving drops it. Launch arguments (DEBUG):
  `-samplePhone` (a made-up store in a temporary folder, filled through the real import), `-samplePhoneEmpty` (the
  first screen; `-importData` taps Import data at launch: the file picker; `-sampleImport` imports the tour's made-up
  bank file as if picked, so on the empty store the category picker opens after it as after a real import),
  `-sampleSignedIn` (signed in on the made-up account server), `-sampleOverview` (Overview, not Current) and
  the graph (Settings → Dashboard → Graph, `aresium.graph`, on by default since brief 42, `Model/GraphSetting.swift`; on
  a category's page above its months; whether it moves away while its list scrolls, `aresium.graphMoves`, brief 56,
  above; `-toggleGraph` flips the saved setting once; with only one month of data each graph is one point, drawn as a stem with a dot,
  `ChartAxis.singlePointDomain`, `OneMonthTests`), `-openSheet settings`, in the picker
  `-sampleTick <id,id,…>` (ticks those), `-sampleUntick <category id>`, `-scrollToCategory <id>` and
  `-samplePickerDone` (then Done: the dashboard with the result line counted again), `-sampleLayout` (an unknown bank's
  CSV: "Does this look right?"; `-sampleReading 2` the second reading, `-sampleReading columns` the column check),
  `-sampleFormat` (that file confirmed and imported: the result with the send card; `-formatBank <name>`,
  `-formatPhase sending|sent|kept|refused|badName`, `-formatMessage <the server's sentence>`, `-openFormatDetails`
  "What is sent?", `-formatFocus` the keyboard on the name), in the guide (`-openGuide list -guideSearch <a name no bank
  matches>`) `-bankRequest` (the name and Send open) and `-bankRequestPhase sending|sent|kept|refused|personal`
  (`-bankRequestMessage <the server's sentence>`), `-sampleCategory <name> -sampleMonth <YYYY-MM>
  -samplePhoneTransaction <text>` (a payment's detail; `-samplePhoneSwitch <category>` switches it, then the merchant
  question; `-openOriginal` opens the bank's own row and shows the page's end; an own transfer: `-sampleCategory "Own
  transfers" -sampleMonth 2026-02 -samplePhoneTransaction PayPal`, the sample's made-up PayPal bank line),
  `-sampleImportResult` (the result
  line); `-sampleOwn <names>` (own categories in the sample), `-openCategories` (Settings → Categories),
  `-sampleRecategorise` (the change sheet, also in phone mode; `-samplePick <category>` picks one); the lock in memory: `-sampleLock faceID|code|both` (the code is 123456), `-sampleUnlocked` (open at launch),
  `-sampleWrongCodes <n>`, `-openCode` (Settings → Lock → Own code), `-openCodeEntry set|change|remove`. Tests:
  `PhoneModeTests`, `PhoneBackendTests`, `PhoneStoreTests` (with the moving over), `PhoneEngineTests`,
  `PhoneLookTests`, `LockTests`, `SupportContactTests`, `CategoryRouteTests`, `FileCheckTests`, `BankFormatTests`,
  `BankRequestTests`, `FirstScreenTests`, `ImportThenCategoriesTests`, `CategoryCountsTests`, `PaymentPageTests`,
  `OneMonthTests`, `ReceiptCaptureTests`, `ReceiptBookTests`.
  Screenshots of every phone-mode screen in both looks and languages, and at the largest text size: `build/18-*.png`
  (2026-10-27); without an account and the lock: `build/22-*.png`, contact sheet `build/22-sheet.png`; the unknown
  file's window and sending: `build/23-*.png`, contact sheet `build/23-sheet.png`; the first screen, the lighter tour
  with the lock and contact, the guide's no-match and sent states: `build/25-*.png`, contact sheet `build/25-sheet.png`;
  Import data's file picker, the category picker after an import with its numbers, the dashboard after ticking (both
  languages and looks, the largest text size): `build/27-*.png`, contact sheet `build/27-sheet.png`; the payment page
  (phone, own transfer, server sample, the tour's payment steps): `build/28-*.png`, contact sheet `build/28-sheet.png`.
  **"How do I get my file?"** (brief 24, Patrik 2026-10-27: he did not know how the first time): the per-bank steps of
  brief 19's research, now in the app (`Guide/bank-steps.json`, one copy; how it was researched and what is unsure:
  `docs/bank-export-guide/README.md`; `Model/BankGuide.swift`, `Screens/BankGuideScreens.swift`). A list with a search
  ("Your bank": every typed word starts a word of a bank's names, or a name is among the typed words, `BankSearch`),
  Another bank always last; a bank's page: Website / App (only places with steps; for the other one line, "doesn't work"
  or "Aresium knows no way" when no source describes one), the numbered steps, the quiet line "a button may be called a
  little differently" below high confidence, which file (the bank's labels as chips) and why, Good to know (the limits),
  how the file gets to Aresium (the bank's `toAresium` ways, the usual one open), Choose file (the file picker; the
  files are imported once the guide has closed, and in phone mode the category picker follows while none is chosen). No
  sources and no format names in the screen's own sentences (`BankGuideTests` checks the data). Opened from the first
  screen, an empty dashboard page and Settings → Help → Get the file from your bank
  (`SettingsScreen`'s `help` slot, Shared). **The tour** (brief 24, `Model/TourModel.swift`, `Model/TourData.swift`,
  `Screens/TourScreens.swift`): offered as Start tour on the first screen and Settings → Help → Tour of Aresium, never by
  itself; when it ends the first screen comes back while there is no data. The real dashboard (`DashboardStack`, the same view as the person's, on its own `DashboardPlace`) on
  `TourWorld`: a store in `tmp/aresium-tour-<uuid>/` filled through the real import with `TourData` (a made-up VR Bank
  file, this month always full), its own session (never logged in) and widget numbers inside that folder; the person's
  store, categories and learned shops are never opened. The folder is deleted on End tour (always on the card), at the
  end, when a widget's link or a shared file opens the app, and at the next launch if the app was closed during a tour
  (`removeLeftovers`). **Twenty-one steps, twenty while the graph is hidden** (brief 59, Patrik 2026-10-31: "update the
  tour so it explains everything and is coherent"; brief 77 added the search, brief 82 selecting, brief 99 the quick sort; `TourStep`, one walk: the start screen, a
  category, a payment and what can be done with it, the list's swipe and adding up, Settings' places in their real
  order, import, done): welcome; income (the page dots, the swipe); overview (the range); graph (Overview's graph: hold
  and slide reads each month, a tap opens its month's page, which the ring follows, and there a day's; the card says so:
  "… A tap opens the month, or the day where it shows days."; Next); search (brief 77: the start screen's magnifying
  glass, `.search`; on the search's page and the names it opens the tour points at nothing, so they are free to try on
  the tour's store; Next, as the graph's, since the category's step brings the start screen back: "Search a name, your
  own or the bank's. A tap shows all its payments." / "Such nach einem Namen, deinem eigenen oder dem der Bank.
  Antippen zeigt alle seine Buchungen."); category (a row); payment (its row opens the page); rename
  (`.paymentName`: the page's name and pen, the field while open; goes on when a name is saved, `onRenamed`); switch
  (the category's chip and pen, `.change`; the shop question answered); select (brief 82: the list's select icon,
  `.selectIcon`; selecting frees the screen, Next goes on and ends it); addUp (the list's first single row whose name
  has more payments there: the swipe's or the long press's Add up); sumIcon (the header's icon of adding up, `.sumIcon`;
  its tap); allFrom (the name added up at addUp, `.summed(key)`, or its first row: All opens the name's page, which
  stays under the next step's gear); categories (the gear, then Categories with Own names, `.dataRows`; the picker free);
  messages (`.messagesRow`); lock; dashboardSettings (`.dashboardRows`: Graph, Graph moves away, Add up same names);
  contact; import (files, receipts and cash); quickSort (brief 99: this month's Not sorted list with its card ringed,
  `.quickSortCard`, "What an import leaves Not sorted, you go through here name by name. …"; the card opens the flow on
  the tour's store, free to sort, and closing it goes on); done. Without the graph the graph step drops out and the Dashboard card
  says only "Here you add up same names in every list." (`TourStep.text(showingGraph:)`): no card mentions the graph.
  The cards' words are `TourStep.text` (German in the catalog). Each step points at a real control (`.tourAnchor`, anchor preferences; a payment row's and a summed
  row's anchor sit outside their swipe, so the ring stays still and the swipe's actions lie inside it);
  `.tourSpotlight` on each screen and sheet draws a light veil in the wall's colour, `TourVeil.veil` 0.3 (brief 24 had
  0.74, far too dark: the app under it must read easily, Patrik 2026-10-27), and the full-ink ring, and keeps taps off
  the rest except at the swipe to income; `.tourCard` the glass card with Next and End tour, on a sheet's scroll view
  after its spotlight (the payment's page, the tour's Settings and the picker pushed there: on the sheet's
  NavigationStack the list ran on under the card and Contact & support could not be reached, brief 59);
  `.tourScrollsToTarget` scrolls only as far as it takes, the control's lower edge to 60 % of the view, and not at all
  when it shows there (`TourScrollPlace`; a start page's moving graph went half away for a category row that nearly
  showed). `TourData` has a third grocer (ALDI SUED, twice a month, fixed made-up amounts) so Groceries keeps two names
  with several payments after the switch step moved REWE out, and the icon step has something to add. A step goes on when the
  person does the thing (`TourModel.update`: the swipe, Overview, a category, a payment, a name's page; `importTapped`;
  `settingsRowTapped(_:)` for the Settings rows; `paymentRenamed` through `DashboardStore.onRenamed`;
  `paymentRecategorised` through `DashboardStore.onRecategorised`; `sumsChanged` through `PaymentSums.onChange`, all
  nil outside the tour) or taps Next, and Next gets the step's screen ready (`prepare`: Overview for the graph, the
  payment's page, the list under it, the tour's Settings). While the tour holds the screen the back swipe and the rows'
  long press and swipe are off (`DashboardStack(shortcuts:)`), except at addUp and allFrom, where the ringed row's swipe
  and long press work (`DashboardStack(rowShortcuts:)`, `TourModel.rowShortcuts`) and the back swipe stays off. A step
  whose control is not on screen (the person tapped the row's page open, or All at addUp) points at nothing, so the
  screen is free until they come back; Next always gets the screen ready again. **Adding up in the tour**: its
  `DashboardStore` has an empty `PaymentSums()` in memory, never the person's `aresium.sums`; the swipe's Add up, the
  icon and the name's page's switch work on it; nothing is added up before addUp, so the rows the earlier steps point at
  are single. In the tour the gear opens the tour's own Settings: the person's sections it points at in the real order
  (Your data on this iPhone with Categories on the made-up store and Own names; Messages; Lock; Dashboard; Help →
  Contact & support), each but Categories a picture of the tour's own state built from the real rows
  (`OwnNamesRow`, `DashboardSettingsRows`, `MessageWording.state`) that only points and goes on: no setting changes, no
  lock is set, no message planned and iOS never asked, no form opens, nothing is sent; the tour never sees `AppLock`,
  `AresiumMessages` or the support form, nor writes the graph, own names or messages settings (`TourTests` compares the
  app's defaults before and after a walk). The import button only answers its step, the band does not enter red mode.
  VoiceOver: the card takes the focus at each step, the highlighted control stays reachable; Reduce Motion: the ring
  jumps, nothing slides. Launch arguments (DEBUG, with `-samplePhone` or `-samplePhoneEmpty`): `-openGuide list|<bank
  id>` (`-guidePlace app|website`, `-guideSearch <text>`, `-scrollToEnd` the page's end), `-tour <1–21>` (`-tourSettings`:
  its Settings open). Tests: `BankGuideTests`, `TourTests` (every step's target and what moves it on, Next's screens,
  the hidden graph's 18 and its words, the search's step, every card's German, adding up in memory only, the person's store and defaults
  untouched, ending at any step). Screenshots: `build/24-*.png`, contact sheet `build/24-sheet.png`; brief 59's walk
  `build/59-*.png`.
  **Receipts** (brief 31, Patrik 2026-10-27; D8 in `ares-empire/docs/ARESIUM-FOR-OTHERS.md` → part 6; phone mode
  only). **Capture:** in phone mode Import (the first screen's Import data, the dashboard's import button) is Apple's
  menu: Choose file, Scan receipt (only where `VNDocumentCameraViewController.isSupported`; the iOS 27 simulator says
  yes but cannot record, so there the scanner stops: "The scanner stopped. Try again."), Choose photo (`PhotosPicker`,
  no library access needed); server mode keeps its button; in the tour every item only answers the import step
  (`ImportChoices.tour`). `NSCameraUsageDescription` (German in `InfoPlist.xcstrings`). Reading on the phone
  (`Model/ReceiptCapture.swift`): `RecognizeTextRequest` (accurate, the language detected, minimum text height 0.005:
  the default dropped pieces of a long receipt) and `DetectBarcodesRequest` for QR codes, which falls back to Core
  Image's QR detector when it throws (its model does not load on the simulator); off the main actor, cancelled with
  its sheet; the image is never written and is released after reading. Vision's boxes become the engine's in one place
  (`ReceiptBox`: top left, y down, page n at y = n). **The engine:** `readReceipt` (shop, date, total, currency, card or
  cash, the rows, what it is sure of), `matchReceipt`, and `buildDashboardSource`'s `receipts` (`AresiumEngine`,
  `EngineTypes.swift`). **The check window** (`Model/ReceiptCheck.swift`, `Screens/ReceiptCheckView.swift`, the file
  check window's look): "This is what Aresium read from the receipt:", the fields not sure or not found first under
  "Please check" (each says which: "Aresium is not sure about this." / "Not found on the receipt."), then "Read from
  the receipt"; Shop (text), Date (Apple's date picker), Total (with its currency, brief 33; an undecided "kr" must
  be chosen), Paid by Card / Cash (segmented; not read: Card only when a stored bank payment matches, with
  that said, else nothing and Save waits), Amount in euros (another currency paid in cash, required), Category (the
  person's categories and Not sorted; the shop list's one preset when chosen; one picked by hand teaches the shop),
  "As on the receipt" folded, "Does this look right?" and Save (the line above it says what is still missing).
  Nothing read: the same window empty ("Aresium couldn't read this receipt. Type what it says:"). **Keeping and
  joining** (`Model/Receipts.swift`, `Model/PhoneReceipts.swift`, `StoredReceipt`): the read rows and the confirmed
  values, never the image. A card receipt is matched on Save (`taken`: other receipts' payments and the ones the person
  declined): one exact match joins at once (a payment Not sorted takes the receipt's category, source `receipt`:
  "Sorted by its receipt."), candidates ask **"Is this the same payment?"** in the same sheet (the receipt, then the
  payments as the dashboard's rows with what differs: "€20.00 more: cash back or a tip?", "One of 2 payments with this
  amount", "Paid in another currency"; "None of these" declines them and it waits), none waits ("Waiting for the bank
  statement", counted on its own meanwhile, `provisional`). After every bank import (`PhoneBackend.importFiles` →
  `matchWaitingReceipts`) the waiting card receipts are matched again: exact ones join (the result line adds "· 1
  receipt joined"), candidates queue in `PhoneBackend.receiptQuestions` and ContentView asks them once each after the
  import's windows and the category picker (`ReceiptQuestionSheet`; closing it lets the receipt wait). A saved
  receipt's line goes to the import's result banner. **Cash** counts in its category and is taken out of the
  withdrawals before it by the engine: the withdrawal's category shows a "Covered by receipts" row (`coveredBy`), which
  opens those receipts. A card receipt in another currency waits outside the dashboard until joined (Settings → Receipts
  shows it). **Pages:** a receipt row in a payment list (a clock mark and "Waiting for the bank statement" or "Paid in
  cash") opens the receipt's page (`Screens/ReceiptPageView.swift`, `ReceiptPageModel`: shop, amount, the day written
  out, Paid by and where it stands, Category with Change (learns the shop), the bank payment with Unjoin or Join with a
  payment… (the engine's candidates, else money out from the receipt's day to a week later), "As on the receipt",
  Delete receipt: unjoins, a category its payment took from it goes, the cash is uncovered). A joined payment's page has
  a Receipt section (shop, day, the rows folded, Unjoin). Settings → Your data → Receipts lists them newest first with
  where each stands. The tour's import step: "Files from your bank, receipts and cash come in here." (brief 59); the tour never
  opens the camera or reads anything. Launch arguments (DEBUG, with `-samplePhone`/`-samplePhoneEmpty`):
  `-sampleReceipt` (the made-up receipt, `ReceiptSample`, read through Vision and the engine: the check window, all
  read but the shop; `-sampleReceiptShop REWE` prints a chain the shop list knows: all sure), `-sampleReceiptUnsure` (a café receipt without code, payment line or total word),
  `-sampleReceiptBlank` (nothing read), `-sampleReceiptQuestion` (saved with two payments of its amount and one €20
  more: the question), `-sampleReceipts` (kept receipts: waiting in Groceries, cash after the month's withdrawal, one
  joined to the month's first REWE payment, one in pounds; then `-sampleCategory Groceries -sampleMonth <YYYY-MM>
  -samplePhoneTransaction <shop>` opens a page, `-samplePhoneTransaction Covered` in Cash withdrawals the covered receipts,
  `-samplePhoneTransaction REWE` the joined payment), `-openSheet settings -openReceipts` (Settings → Receipts),
  `-openReceiptText` ("As on the receipt" open), `-choosePhoto` (the photo picker). Tests: `ReceiptCaptureTests`
  (Vision, boxes, pages, photos, cancelling), `ReceiptBookTests` (a version 1 store from
  `AresiumTests/Fixtures/ledger-v1`, export 2 and 1, joining, asking, waiting, after an import, cash and its covered
  row, deleting, foreign cash, card or cash not read, the words in both languages). Screenshots: `build/31-*.png`
  (part A), `build/31b-*.png`.
  **Correcting receipts** (brief 33 part A, Patrik 2026-10-28: the window asked "Does this look right?" but seemed to
  offer nothing to do when it was not; D9). **Every value looks like something to tap:** Shop and Total (and Amount in
  euros) sit in the fields' box (`Ink.field`, a thin line; `fieldBox`, a tap anywhere on it focuses the field), the
  total's currency and the category are the column check's `MenuChip` menus (any receipt's currency can be changed; an
  undecided "kr" says Choose), the date and Card / Cash are Apple's own; under the top the quiet line "Something
  wrong? Tap it and change it." **Edit after saving:** the receipt's page has Edit in its bar, a joined payment's
  Receipt section Edit beside Unjoin; both open the same window filled from the stored receipt ("This is the receipt as
  you saved it.", one section, nothing marked; `ReceiptCheckModel(editing:)`, `ReceiptEditSheet`,
  `ReceiptPageModel.beginEdit`). Saving (`PhoneBackend.updateReceipt`): a new total, date, currency or card or cash
  (`ReceiptEdit.matchesAgain`; said above Save while it was joined or is card: "Aresium looks for its bank payment again
  when you save.") unjoins it (its payment loses a category it had from the receipt and is sorted again), forgets the
  payments declined for it and matches it again as on Save (exact joins, candidates asked in the same sheet, none
  waits); a new shop, category or euro amount only updates (a joined payment that took its category from the receipt
  follows the new one). **Learning** (`Model/ReceiptCorrections.swift`): a shop name the person changed (on Save or
  later) is remembered for the shop as read (`ShopNames.key`: lower case, letters and digits only; kept as
  `StoredShopName`, the receipt keeps `shopAsRead`), so the next receipt read the same way shows it, in the read
  section with "Corrected by you before." (`Mark.corrected`); saving the name exactly as read drops it. A category
  picked by hand is learned for the shop as a Switch (`learnShop`, as in brief 31) and is now preset for the shop's
  next receipt (`learnedCategory(forShop:)`, before the shop list's). The total and card or cash are never learned
  (misreads are one print's; one shop takes both). Launch arguments (DEBUG): `-sampleShopCorrection <name>` (the
  made-up receipt's shop corrected before, with `-sampleReceipt`), `-editReceipt` (Edit open on the page that
  `-samplePhoneTransaction` opens, the receipt's or a joined payment's; `-editReceiptTotal <text>` types a total).
  Tests: `ReceiptCorrectionTests` (every field changed and saved, Edit filled from the receipt, a new total joins
  again or asks, cash instead of card, shop or category only update, the corrected shop through Vision and the engine,
  forgetting it, the learned category preset, total and card or cash not learned, a version 2 store from
  `AresiumTests/Fixtures/ledger-v2.store`, export 3 and restore of 2 and 1, schema 3's checks). Screenshots:
  `build/33-*.png`.
  **Cash** (brief 33 part B, Patrik 2026-10-28, D9; the engine is brief 32's, aresium 4de0b4b; `Model/Cash.swift`,
  `Model/PhoneCash.swift`, `Screens/CashScreens.swift`). **Hand entries:** Add cash ("Bargeld eintragen"), the fourth
  item of phone mode's import menu (the first screen's too; `banknote`) and the Cash page's Add spending / Add received
  cash: one window in the check window's look (`CashEntryView`, `CashEntryModel`): Spent / Received (segmented, with
  a line on what each is for), Amount (euros only), Date, What ("Where or what for" / "From whom or what for"),
  Category (its home side's categories, then the other side's with `otherSide`, no transfers, Not sorted last;
  `CashCategories`), and for Spent **Paid from**. Kept as a receipt (`CashEntryDraft` → `LedgerReceipt`: kind
  `manual`, cash, its direction, no rows, never joined: `PhoneDashboard.source` never sends a hand entry's payment,
  and cash is never matched); its category is not learned (an entry names an occasion more often than a shop). A store
  with only receipts or entries shows the dashboard, not the first screen (`MainScreen.choose(phoneRecords:)`). The
  entry's page is the receipt's page ("Cash entry"; title what was typed, else "Cash spent" / "Cash received"; a
  received one shows what it still holds, Left; Edit opens the same window, `.entry` in `ReceiptEditSheet`; Delete
  entry). **Paid from** (cash receipts and spent entries, in their windows and on their pages): Automatic (default) or
  one withdrawal or received entry on or before the day, newest first, each with what it still holds (`PaidFromList`,
  from the engine's movements, `CashPage.sources`; the last 92 days first, the older ones behind "Show older",
  `CashPage.split`, Claude 2026-10-28); saved as `paidFrom` (`setPaidFrom`), the dashboard rebuilt; the
  page says where the engine took it from ("From the withdrawal of 18 Oct", "From the cash received on 3 Oct", "… and 1
  more", "From cash not recorded here"). Deleting a received entry, or making it spent, sends what was paid from it
  back to automatic (`PhoneLedger.forgetPaidFrom`). **The engine:** phone mode always passes the receipts (even none),
  with `direction`, `kind` and `paidFrom` (`SourceReceipt`), so the dashboard carries `cash` (`CashView`: the months'
  withdrawn, received, spent, unaccounted; every movement from the wallet's side) and marks withdrawals
  `cashWithdrawal` (`Transaction`). **The Cash page** ("Cash" / "Bargeld"; `DashboardRoute(cash: true)`): a row below
  the categories on both pages of the dashboard (`CashRow`: a wallet mark, "Cash", what is not accounted for; no
  amount column, set apart by a hairline), only while `cash` has a movement; it follows Current / Overview like a
  category (`DashboardStore.cashRoute`): this month's page, or its months (`CashMonthsScreen`). The month's page
  (`CashScreen`): Not accounted for with its number and "In your wallet still, or spent without a receipt.", then
  Withdrawn, Received, Spent; Add spending, Add received cash; the movements newest first (`CashMovementRow`: day, place
  or what, kind and category, what a source still holds or where the money came from, + / − amount); a tap opens the
  withdrawal's payment page or the receipt's or entry's page; "No cash this month." with a line and the two buttons when
  empty. A view: it counts in no total. **Names:** "Cash" / "Bargeld" is the page (one key; "Bezahlt mit: Karte |
  Bargeld" uses it too), so one's own category may not take it (`PhoneCategoryList.reservedNames`); the withdrawals'
  category is the engine's "Cash withdrawals" / "Abhebungen". The covered row in it reads "Accounted for" /
  "Erfasst", "Counted where it was spent" (receipts and entries alike); its list "Accounted for". Launch arguments
  (DEBUG, with `-samplePhone`): `-sampleCash` (made-up entries around the sample's withdrawal on the 18th: a gift from
  grandma, a flea market paid from it, an ice cream after the withdrawal; last month a bike sold and a cinema ticket),
  `-openCash` (the Cash page; `-cashMonth <YYYY-MM>` another month, an empty one for the empty state;
  `-sampleOverview` its months), `-cashOpen <text>` (on the page, the movement whose place contains it),
  `-addCash spent|received` (Add cash, from the import menu or with `-openCash` from the page), `-openPaidFrom` (Paid
  from in that window, or on the page `-cashOpen` opened). Tests: `CashTests` (entries stored and never joined, no
  payment to the engine, the window's categories and Edit, Paid from saved and passed, deleting a gift, the page over
  two months, the words in both languages, the name check, only cash shows the dashboard). Screenshots:
  `build/33b-*.png`.
  **Comfort in the windows** (brief 40, Patrik 2026-10-30; `docs/reviews/2026-10-30-swipe-and-comfort.md`; the pieces
  in `Screens/WindowComfort.swift`). "Is this the same payment?" has **Later** top left (in the receipt window after
  Save, in Edit receipt, after an import): what a swipe down does, the receipt waits and nothing is declined; after Save
  it (and the swipe) shows "Receipt saved. It waits for the bank statement." and builds the dashboard again
  (`ReceiptCaptureModel.later`); after an import the next queued question opens after it, and the next import asks
  again. The file check has **Back** beside No from the second reading (Back and No share No's half, Yes keeps its own,
  `EqualWidthRow`) and beside Import in the column check when there were readings (to the last reading; the column
  check keeps its answers; `FileCheckModel.back`). **Number pads** (Total, Amount in euros, Add cash's Amount) have
  Done above them (`numberPadDone`; iOS 26 floats it outside the keyboard's safe area, so the bottom bar rises clear of
  it, `clearOfKeyboardDone`); Shop's Return moves to Total, What's Return closes the keyboard. **Cancel asks first**
  (`DiscardingCancel`, as Contact & support's X: "Discard this receipt?" / "Discard this entry?" / "Discard your
  changes?", Discard, Keep editing) when something would be lost: a new reading always (unless nothing was read or
  typed), Edit receipt, Add cash and Edit entry once a value changed (`hasSomethingToDiscard`, `hasChanges`: amounts by
  their number, the date by its day); Add cash's swipe down is held back on the same rule. **The busy sign:** the
  tapped button shows the spinner (`BusyLabel`; a payment row in its amount's place; Edit in the bar in its word's
  place), the others are greyed (`whileWorking`): a receipt's page (Edit, both Change, Unjoin, Delete;
  `ReceiptPageModel.working`), Join with a payment, the question's rows and None of these. Launch arguments (DEBUG):
  `-sampleImportQuestion` (two waiting receipts asked after a made-up import; `-tapLater` taps Later on the first),
  `-typeIn shop|total|euros|amount|what` (the cursor there; several comma-separated, one every 2 s), `-askDiscard`
  (Cancel tapped once there is something to discard; `-cashAmount <text>` types Add cash's amount), `-holdWork` (a
  tapped button's work waits a minute) with `-tapWork category|unjoin|delete` on a receipt's page or `-tapAnswer
  first|none` on the question. Tests: `WindowComfortTests`. Screenshots: `build/40-*.png`.
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

## Local places memory gate (brief 95, 2026-11-01)

**Over budget; app integration stopped.** The shipped engine, resources, sorting and licence UI are unchanged.
Measured on `codex-95`, iPhone 17 (`iPhone18,3`), iOS 27.0 / 24A434, Apple M5 / 16 GB. These are simulator
app-hosted measurements with a fresh `AresiumEngine` on a worker, Release `-O`, no `DEBUG`, and
`task_vm_info.phys_footprint` (decimal MB); physical-device memory remains unmeasured. Three independent candidate
processes used aresium `b04ff9b`; the separate control used today's shipped engine, `400754e5`.

| Candidate process | Before loading, MB | Loaded after GC, MB | Added, MB | Released after sorting and 10 s, MB |
|---|---:|---:|---:|---:|
| 1 | 114.61 | 217.83 | 103.22 | 240.85 |
| 2 | 115.89 | 219.68 | 103.79 | 239.72 |
| 3 | 114.79 | 218.07 | 103.28 | 242.91 |

Today's no-list control: **116.66 MB** initially, **120.39 MB** after the same number of sorts and 10 s of GC.
After each load, temporary native data/strings leave an autorelease pool, then three `JSGarbageCollect` calls run
and 250 ms elapse. After sorting, the context's list global is set to `undefined` and checked, GC runs three times
immediately and after each of ten one-second waits. The release figures are process footprint, including retained
VM/allocator pages; they do not prove a live-object leak. Both the +60 MB loaded and +5 MB released gates fail.

Loading the 3,428,315-byte gzip (10,503,935-byte JSON) took **100.45 ms median**, **90.68–155.39 ms** across the
three processes: read **0.96 ms**, gunzip plus UTF-8 **19.32 ms**, native string bridge plus JSC JSON parse
**83.41 ms** (component medians). File reads use the warm filesystem cache; this is not cold-launch timing.

| Fictional payments | Today's engine, no list | Candidate, no list | Candidate, with list |
|---|---:|---:|---:|
| 1,250 | 9.89 ms | 17.27 ms | 10.24 ms |
| 5,000 | 44.81 ms | 40.41 ms | 48.16 ms |

Sort medians include the string bridge, JSC input parsing, sorting, result JSON and Swift decoding; input JSON is
prepared beforehand. Three warmups per size precede sampling; five paired samples per size/variant/process
alternate order (15 each), with ten per size in the control. Timings vary with JIT/GC and simulator scheduling;
the 1,250-payment figures do not establish a speedup. Payments use fictional amounts and merchants plus REWE.

Reproduce with `bash scripts/95-local-places-measure.sh` after creating/booting the owned simulator. It builds the
candidate into `build/` using aresium's existing esbuild, reads the source repo only, runs one `xcodebuild test`
and three `test-without-building` calls, and exports diagnostics and result summaries. Existing tests depend on
DEBUG-only helpers, so this Release-only experiment excludes their sources via a command-line build setting;
the project file is untouched. **Four runs: one test each, zero failures** (`TEST SUCCEEDED`, then three
`TEST EXECUTE SUCCEEDED`). The full suite was not run; the initial full Release compilation failed on those
existing helpers. `python3 scripts/strings.py check`: **0 problem(s)**. No new UI strings or licence screenshots.
Raw results: `build/95-measure-final.log`, `build/95-20261101-215832-*.xcresult` and matching diagnostics;
gzip SHA-256: `6cf2685ffbd014173646f9bb3ba87ad59dc3cca64db04817c17025153faeba9b`.

Before another app attempt, change the format in aresium: a sorted UTF-8 name blob with offset tables and flat
integer category/town columns, exposed as typed arrays and searched in place. Give the builder and matcher the
same ordering; decode only a matched record, avoiding hundreds of thousands of nested JS arrays and strings.
Keep structural rules and learning first, preserve the existing matching safeguards, then remeasure the new format
against the same two memory gates. This format change is outside brief 95.
## Packed local places memory gate (brief 98, 2026-11-01)

**Adopted and kept loaded (Claude's clarified decision).** The loaded measurements are **12.40–13.68 MB** above
baseline, median **12.75 MB**, with about **93.90 ms once at the first phone engine's start**. The 5 MB release
limit applies only to the 25–60 MB tier that unloads after sorting, not this under-25 MB lifetime tier.
`scripts/aresium-engine.sh` refreshed the engine from aresium
`main` at `eadfc47e97b6241923f1c992a40826eb2f19582e` (briefs 96/97, 524,873 bytes), copied
`Engine/de.places.bin.gz` (3,281,615 bytes) and generated `Engine/local-places-licence.txt` from the packed
metadata. `bundledForPhone` makes the context off main, awaits native loading on `PackedLocalPlacesCache`'s serial
actor, and installs the actual no-copy buffer once through `AresiumEngine.setLocalPlaces`. The cache's weak entries
share the immutable 9,779,212-byte allocation across simultaneous phone/tour contexts; every JSC ArrayBuffer retains
its native owner independently. Once all contexts and callers release that owner, the allocation can be freed.
No clearing timer, background clearing or memory-warning clearing is installed. Each context still validates its own
views, but does not inflate or copy the shared data again. All phone import/sort/categoryCounts/picker dry-run paths
pass `localPlaces: true` at the two engine call sites in `PhonePickerWork.swift`. Other engine callers omit the option;
server mode uses its existing HTTP contract and never passes or loads the list.

Settings → About → Fonts & licences lists `BundledLicence.localPlaces()` alongside the shop list, with attribution,
ODbL 1.0 and links for copyright, the licence and `https://aresium.de/osm/local-places-de.places.bin.gz`. The five new
English strings and their German translations are in Aresium's own catalog; the shared licence page supports optional
link data with the same existing typography and colours.

Measured on the owned `codex-98`, iPhone 17 (`iPhone18,3`), iOS 27.0 / 24A434, Apple M5 / 16 GB. Release `-O`,
no `DEBUG`, app-hosted `task_vm_info.phys_footprint`, decimal MB. Three fresh candidate processes and a fourth
fresh no-list control all use the same refreshed engine. Physical-device memory remains unmeasured.

| Process | Initial, MB | Before load, MB | Loaded after GC, MB | Added, MB | Cleared after sorting + 10 s, MB | Retained from initial, MB |
|---|---:|---:|---:|---:|---:|---:|
| 1 | 118.92 | 119.69 | 133.37 | 13.68 | 163.06 | 44.14 |
| 2 | 131.65 | 132.01 | 144.76 | 12.75 | 164.68 | 33.03 |
| 3 | 119.64 | 119.62 | 132.03 | 12.40 | 162.14 | 42.50 |
| No-list control | 123.47 | — | — | — | 135.74 | 12.27 |

The loaded increment fits the 25 MB lifetime-loading tier. The initial implementation stopped because it treated
the release gate as universal; Claude clarified that the release gate applies only to the middle tier, and directed
adoption in the kept-loaded tier. The release experiment remains recorded: after subtracting the control's own
12.27 MB growth, candidates retain **31.87 / 20.76 / 30.23 MB** more, median **30.23 MB**. Absolute released
footprints are **27.31 / 28.93 / 26.39 MB** above control. These process-footprint results include retained
allocator/VM/JIT pages and the app host; they do not establish a live-object leak or confirm when the native
deallocator ran. Initial-footprint variation and the timing outlier limit precision. Release results do not gate
this adoption because normal engines keep the list for their lifetime. These measurements were captured before
production loading was enabled; no physical-device measurement or cold-launch timing is claimed.

Inflation reads the gzip trailer's exact size (9,779,212 bytes), validates it with zlib and writes directly into
one aligned native allocation. On the worker, `JSObjectMakeArrayBufferWithBytesNoCopy` wraps it; a retained owner
is released by the JSC deallocator, including on a C API exception. The actual protected buffer is passed through
`JSObjectCallAsFunction` to `AresiumEngine.setLocalPlaces`, with no list JSON/string/base64/number-array conversion.
The harness retains no host JSValue/global for the packed buffer. Loading temporaries leave scope, GC runs three
times and 250 ms elapse before the loaded snapshot. After the paired sorts, `setLocalPlaces(null)` clears the
installed list; GC runs three times immediately and after each of ten one-second waits, with snapshots at 1/5/10 s.
The control makes the same number of sorts and collections without loading the list.

| Loading | Median | Range across three processes |
|---|---:|---:|
| Read | 0.82 ms | 0.82–1.87 ms |
| Native inflate | 10.94 ms | 10.61–151.67 ms |
| No-copy handover + engine validation | 82.39 ms | 46.75–158.07 ms |
| Total | 93.90 ms | 58.59–311.67 ms |

Component medians need not sum to the total median. Reads use the warm filesystem cache, not cold-launch timing.

| Fictional payments | Current engine control, no list | Candidate, no list | Candidate, packed list |
|---|---:|---:|---:|
| 1,250 | 15.85 ms | 22.65 ms | 19.23 ms |
| 5,000 | 55.38 ms | 60.13 ms | 57.04 ms |

Sort medians include input string bridging/JSC parsing, sorting, result JSON and Swift decoding, with prebuilt
input JSON. The existing harness uses fictional merchants/amounts plus REWE, three warmups per size and five
paired samples per size/variant/process, alternating order (15 samples each); the control has ten samples per
size. These timings reflect this workload, GC/JIT and simulator scheduling, and do not establish a speedup.

Reproduction/check commands run from this worktree:

```sh
xcrun simctl create codex-98 'iPhone 17' com.apple.CoreSimulator.SimRuntime.iOS-27-0
bash scripts/aresium-engine.sh /Users/pab/aresium > build-engine-98.log 2>&1
mv build-engine-98.log build/98-engine.log
bash scripts/98-local-places-measure.sh > build/98-measure.log 2>&1
python3 scripts/strings.py check > build/98-strings-check.log 2>&1
git diff --check
xcrun simctl delete codex-98
```

The measurement script runs `xcodebuild test` once, then three `xcodebuild test-without-building` calls, with
`-project Aresium/Aresium.xcodeproj -scheme Aresium -configuration Release -destination
'platform=iOS Simulator,name=codex-98' -derivedDataPath build/DerivedData ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES
-parallel-testing-enabled NO -only-testing:AresiumTests/LocalPlacesMeasurementTests`, and excludes the other test
Swift sources via `EXCLUDED_SOURCE_FILE_NAMES` because their helpers require DEBUG (as in brief 95).
**Four runs: one test each, zero failures**: `TEST SUCCEEDED`, then three `TEST EXECUTE SUCCEEDED`.
Initial measurement checks: `python3 scripts/strings.py check`: **0 problem(s)**; `git diff --check`: pass.
The adoption's full-suite and screenshot checks are recorded below. No `TODO(api)`.
`PackedLocalPlacesTests` uses the small fictional fixture generated by aresium's packer through
`scripts/98-local-places-fixture.mjs`: actual no-copy backing address, opt-in and disabled categories, clear/reload,
concurrent native cache sharing, independent context clearing, corrupt gzip/packed replacement, phone import,
picker dry-run/counts, choosing/sorting, learning and structural precedence, server import contract isolation,
and the bilingual licence attribution/links.

Raw results: `build/98-measure.log`, `build/98-20261101-222124-{1,2,3,baseline}.xcresult`, matching diagnostics and
`*-summary.json`; condensed measurements in `build/98-measurements.json`.
Engine SHA-256: `64f25badb23afdf2913a321a80a1e74e64de0bd719064ba5d88b4fa620cb986e`.
Packed gzip SHA-256: `2ab7d4938cc2a35be9a46819d1cde71ce5aa5590f1f3c2a71072fff2660caab9`.

Adoption verification (same owned iPhone 17 / iOS 27.0 simulator):

```sh
node --import /Users/pab/aresium/node_modules/tsx/dist/loader.mjs scripts/98-local-places-fixture.mjs /Users/pab/aresium
TMPDIR="$PWD/build/tmp" python3 scripts/strings.py sync > build/98-strings-sync.log 2>&1
python3 scripts/strings.py fill build/98-de.json > build/98-strings-fill.log 2>&1
xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=codex-98' -derivedDataPath build/DerivedData > build/98-test-final.log 2>&1
python3 scripts/strings.py check > build/98-strings-check.log 2>&1
git diff --check
```

Final full-suite summary: **`TEST SUCCEEDED`**; **`Test run with 665 tests in 77 suites passed after 61.628 seconds.`**
The xcresult summary reports **665 total, 661 passed, 0 failed, 4 skipped** (772 passed including expanded parameter
cases in its device breakdown). The four skips are the opt-in shared-login probe, memory measurement and two timing
experiments. All seven new packed-list tests pass, including one native read/inflate off main, reuse after removing
the source fixture file, and the person's learned correction beating the listed category on a later import.
No existing sample expectations were changed for the refreshed engine. Two earlier full runs failed only in new
tests: one used the build before German was filled; the second compared serialized JSON bytes despite unordered
keys. The finished catalog and structural request-field assertions fix those failures; the final run passes.
`python3 scripts/strings.py check`: **0 problem(s)**. `git diff --check`: pass.

New catalog strings (English and German): “Local places · © OpenStreetMap contributors”, “Local places for sorting”,
“OpenStreetMap copyright and contributors”, “Open Database License (ODbL) 1.0”, and “Download the local places list”.
Unrelated catalog normalization by the all-project export was restored; only Aresium's five additions remain.

Screenshots: `build/98-licence-{en,de}-{dark,light}.png` (the entry) and
`build/98-licence-detail-{en,de}-{dark,light}.png` (the attribution/licence/download page), captured with the app's
existing sample launch arguments and visually inspected in both languages and appearances. The full command log
is `build/98-screenshot-commands.json`; capture waits for the actual licence text and the navigation transition.
The licence page retains the existing single-line navigation title, which truncates its long attribution title;
the list's two-line name and the page's attribution paragraph show the full attribution.

Final test artifacts: `build/98-test-final.log`, `build/98-test-summary.json`, `build/98-test-final-diagnostics` and
`build/DerivedData/Logs/Test/Test-Aresium-2026.11.01_22-35-57-+0100.xcresult` (see the log for the exact result path).
The public download URL is linked as requested; hosting it remains Claude's deployment step and was not checked
over the network. Physical-device memory remains unmeasured. No commit, push or merge; `codex-98` deleted after QA.
