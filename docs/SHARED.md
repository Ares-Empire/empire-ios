# Shared pieces of the iPhone apps

How the parts every app uses are built: setup and signing, the login, accounts, Settings, languages, light mode, push,
support, the switcher cover, tours, privacy files. Read the section for what you touch. Rules for every app: `CLAUDE.md`. Owner decisions are tagged "(owner, date)"; when one changes, change its line (git keeps the old one).

## Decisions and rules in force

- Login token: a Keychain item in the shared group; the App Group's `LoginMarker` holds only an account id, never a
  token; a 401 deletes a login only while it is still the refused token.
- Central logout: account-bound widget snapshots (Aresus's status, Aresium's server mode) carry their account and are
  deleted on a mismatch (Aresium's phone-mode snapshot belongs to the phone's store); logout removes every recorded
  push device.
- The app-switcher cover hides an app while it is inactive; `SystemPrompt.begin()`/`end()` keeps it out of the way of
  the app's own iOS prompts.
- Samples and screenshots never touch the real account server (`SampleAccount`); sample mode only pretends to leave,
  delete or send.
- Contact & support reaches the owner through the account server's `feedback` collection; apps without a login
  (Aresium always, Arestia) use the open `contact` collection (owner, 2026-10-27).
- The login screen no longer shows "One Ares account for all Ares apps" (owner, 2026-10-31).
- The App Store Connect API key exists only in the Mac's Keychain.
- Known and left on purpose: a glass card lifted by a long press from a scroll view shows a coarse band on the
  simulator.

## Setup: the Mac, Apple Developer Program, App Store Connect

### The Mac and simulators

MacBook: Xcode 27.1 with two simulator runtimes (2026-10-23): **iOS 27.0** for all normal iPhones (use this)
and iOS 27.1, which only supports the foldable "iPhone Duo" (its screenshots came out black). The simulator
window app is called **DeviceHub** in Xcode 27; `xcrun simctl` works without it.

### Apple Developer Program

Apple Developer Program (paid, for TestFlight; decided in `ares-empire/docs/IPHONE-APPS.md`): **approved
2026-10-29**, team id `WQN8SHAH9B` (the former Personal Team, upgraded in place; Xcode's cached team list may still
call it free). Set as `DEVELOPMENT_TEAM` at project level in every project and in `scripts/new-app-project.py`.
Signing is automatic: Xcode made the Apple Development certificate on this Mac, and the App Store builds use Apple's
cloud-managed distribution certificate (nothing to keep on the Mac). The owner's iPhone 17 (Developer Mode on) is
registered: Apple issues no profile while a team has no device,
so `xcodebuild archive` failed until it was. All five apps (and both widgets) are registered with Apple: the other four by
a signing-only archive on 2026-10-30 (`scripts/testflight.sh <App> --export-only`, `-allowProvisioningUpdates`), so
App Store Connect's New App could offer their bundle ids; the signed Arestemis carries `aps-environment` production
and the time-sensitive entitlement. Uploads: `scripts/testflight.sh <App>` (`docs/DEVELOPMENT.md` → Releasing to the phone).

### App Store Connect API

**App Store Connect API** (2026-11-02): a team key with the App Manager role (owner), only in the Mac's Keychain
(item "Ares Empire App Store Connect API key": the base64 of the .p8, the key ID as account, the issuer ID in the
comment; Apple offers the file once, the download was deleted). `scripts/asc.py get|post|patch|delete <path> [body.json]`
signs a token with openssl and calls the API through curl (no packages; python.org's Python has no certificates).
Used for TestFlight: Aresium's test information, the external group "Tester", builds' "What to Test", Beta App Review.

## Projects and fixtures

### Aresium's Xcode project

Xcode project `Aresium/Aresium.xcodeproj` (2026-10-23): app + tests, folder-synchronized groups (new Swift
files need no `project.pbxproj` edits), bundle id `de.ares-empire.aresium`, iOS 26+. Signing team: `WQN8SHAH9B`
(project level). Launch argument `-sampleData` shows the server's bundled sample (`-scrollToEnd`: the start
screen at its band); every sample runs on `SampleAccount`'s made-up account server, signed out
(`-sampleSignedIn`: signed in).

### Aresium's test fixtures

Test fixtures `AresiumTests/server-dashboard.sample.json` + `.expected.json`: the Aresium server's sample and
the website's answers for it. When `/api/data` changes: `npm run sample` in aresium, then
`node scripts/aresium-fixtures.mjs`.

### Empire app fixtures

Empire app fixtures (2026-10-25): `Empire/EmpireTests/ServerSamples/` (every hub answer and error, made by the hub's
own code, `ares-empire/tools/empire_samples.py`; `ServerSamplesTests`) and the sample mode's `Preview Content`
(admin, member). When the hub API changes: `bash scripts/empire-fixtures.sh`.

### Two projects, one shared folder

**Two projects, one shared folder** (2026-10-24): `Aresium/Aresium.xcodeproj` and `Empire/Empire.xcodeproj`
(bundle id `de.ares-empire.empire`, made with `scripts/new-app-project.py`). `Shared/` (Empire login, network
layer, `AppFont`, fonts, `EmpireShared`) is compiled into every app (and the Aresium widget, for the fonts).

## One login for all apps

**One login for all apps:** the token is a Keychain item in the group `$(AppIdentifierPrefix)de.ares-empire.shared`
(every app's entitlements + `AppIdentifierPrefix` in its Info.plist), the fresh-install wipe keys off the App
Group `group.de.ares-empire.shared` (deleted by iOS only with the last Empire app). Rules in
`Shared/Auth/EmpireSession.swift`: an invalid login (401, refresh refused) logs out everywhere; an account without
this app's service, or a 403 from the app's server, closes only this app (`access = .denied`, the app forgets its
data via `onAppDataReset`); a failed new login never ends an existing one. **Aresium works without it** (the owner,
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

## Central logout

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

## App switcher cover

**App switcher cover** (2026-10-26, `Shared/Design/PrivacyCover.swift`): while an app is not active (app switcher,
Control Center, Notification Center, a system alert iOS shows by itself) a window of its own above everything, sheets
included, shows
the app's `LaunchBackground` wall with the band that ends its main screen (the app's display name; the Empire app
passes "THE EMPIRE" in gold, `AppRoot(cover:)`), in the look the app shows. Shown on the scene's `willDeactivate`
and `didEnterBackground`, faded out (0.18 s) on `didActivate`; it never takes touches. **Not behind the app's own
prompts** (brief 47, the owner's phone: "Aresium" flashed when turning a setting on): every place that asks iOS for
something shown over the app calls `SystemPrompt.begin()`/`end()` around it (the notification permission: Aresium's
`LocalMessageCenter`, the shared `PushCenter`; Face ID or the iPhone's code: Aresium's `AppLock`), and
`PrivacyCoverRule` holds the cover back on `willDeactivate` while one is up (the background still covers; the app
switcher opened during such a prompt finds the app already inactive and shows it as it is, the one gap). A new place
that asks iOS (camera, location, …) adds the same two calls. Tests: `EmpireTests/PrivacyCoverTests`. `AppRoot`
attaches it to the app's window. DEBUG `-privacyCover` keeps it shown for screenshots; the log category `cover` says when it shows and
hides (debug level: `xcrun simctl spawn <udid> log config --subsystem de.ares-empire.shared --mode
"level:debug,persist:debug"`). Checked on the simulator 2026-10-26: all five apps in light and dark, and a round trip
through Safari.

## Accounts in every app

**Accounts in every app** (2026-10-25, brief F2; contract `docs/build-2026-10-25/briefs/F-accounts-contract.md`,
server side `ares-empire/docs/ACCOUNTS.md` → Accounts in every app): one Ares account, made and run from any app.
The login (`AresLogin` in `Shared/Design/ProvinceLogin.swift`, used by the provinces and the Empire app; Aresium has
no login screen since brief 22, and since brief 215 no sign-in in Settings either; `SignInSheet` from the same pieces
stays for an app that offers one) shows the app's mark, the fields and Log in (the line "One Ares account for all Ares apps" under the name went 2026-10-31, the owner) and offers Create account (email,
password twice, optional name; asks for this app's service, sends the app's language; then "confirm your email,
the owner approves, an email follows") and Forgot password? (sheets, `Shared/Design/AccountSheets.swift`). Its error
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

## Contact & support

**Contact & support** (2026-10-24, brief E5): `Shared/Support/`, the form every app's Settings → Help opens
(`SupportSheet(session:accent:sample:)`): a kind (Problem, Idea or wish, Question, Something else) and a message,
posted with the Empire token to the account server's `feedback` collection, which mails it to the owner
(`ares-empire/docs/ACCOUNTS.md` → Contact & support). Logic in `SupportForm`/`SupportMessage`/`SupportAPI` (tests in
`EmpireTests/SupportTests`); a 401 logs out, a 429 says "too many", a 403 never closes the app; sample mode only
pretends. Screenshots (DEBUG, any app showing the sheet): `-supportKind <kind>`, `-supportText <text>`,
`-supportPhase sending|sent|offline|tooMany|loggedOut|other|invalidEmail`, `-supportEmail <text>`. **Without a login**
(brief 22; since brief 25 **always** in Aresium, also while an Ares login exists, the owner 2026-10-27: the privacy policy
handles Aresium's messages like the website's contact form, without accounts). It is a property of the app's identity,
`EmpireAppIdentity.supportWithoutLogin` (`.aresium` and `.arestia`; `SupportForm.sendsWithoutLogin` reads it), never a check in
a view; every other app always sends the account-linked `feedback` record. The form also asks for an email to answer
to (filled with the account's address when one is logged in, editable) and an optional name, and posts a
`ContactMessage` without a token to the account server's open `contact` collection (the website's form's; `name`,
`email`, `message` with the footer "— Aresium <version> · iOS … · <topic>", `language`, the empty honeypot `website`;
5 an hour per address). Tests in `AresiumTests/SupportContactTests` (a signed-in Aresium still posts `contact`). The account server's mail for it still says "the website's contact form"
(`accounts/pb_hooks/contact.pb.js`); the footer names the app.

## Push

**Push** (2026-10-24): `Shared/Push/` (`PushCenter`, `PushAppDelegate`, tests in `EmpireTests/PushCenterTests`)
registers devices with the Empire push service (`ares-empire/docs/PUSH.md`; a dry run until the APNs key went live on 2026-10-30). Wired into
Aresus, Arestemis and the Empire app (`@UIApplicationDelegateAdaptor(PushAppDelegate.self)` in the App, `push.start`
+ routing of `openedURL` in ContentView, never in samples/tests); each needs the Push Notifications capability (paid
team; `aps-environment` is in their entitlements) and, for time-sensitive notifications, the
`com.apple.developer.usernotifications.time-sensitive` entitlement (Arestemis, Aresus). Nothing in Shared may use
`UIApplication.shared` (the Aresium widget compiles Shared too). **A tap is answered on the main thread**
(2026-11-05, the owner's TestFlight crash reports, read with `scripts/asc.py get
/v1/apps/<id>/betaFeedbackCrashSubmissions` and `…/<submission>/crashLog`): every tap on a notification crashed
Arestemis up to build 20, because the `async` form of `userNotificationCenter(_:didReceive:)` ends on a background
thread and its compiler-made bridge calls UIKit's completion handler there, which aborts the app. Every delegate
(`PushAppDelegate`, Aresium's `InboxLaunchDelegate`) uses the completion-handler form through
`NotificationTap.answer`, which runs the routing and the handler on the main actor; never the `async` forms.
`PushCenterTests` calls the delegate through its Objective-C method, as iOS does, and checks the thread.

## Push in operation (the APNs key)

**Push** (`ares-empire/docs/PUSH.md` → Operating): **the APNs key is live since 2026-10-30**: key `22BDWZ79KS` (made by
   the owner, one key for all apps), on the server as `/etc/empire-push/AuthKey_22BDWZ79KS.p8` (empire-push, 600), settings
   in `/root/ares-empire/push/.env` (600); `/health` says `"dry_run": false`. A copy is in the Mac's Keychain (generic
   password "Ares Empire APNs key (base64 of AuthKey_22BDWZ79KS.p8)", restore with `security find-generic-password -s
   '<that name>' -w | base64 -d`); Apple never offers the file again. The Push Notifications capability (and Time
   Sensitive for Arestemis and Aresus) came with automatic signing: the uploaded Arestemis, Aresus and Empire builds
   carry `aps-environment` production. **Arestemis's push works on the owner's iPhone** (test notification 2026-10-31), so its Telegram copy is off since
   2026-10-31 (`TELEGRAM_*` in /root/Arestemis/.env commented out). Left: check on the phone the Empire app ("<App> is
   ready" for a member's account, its tap showing the ring). Aresus works on the phone (test push 2026-11-01), so
   Aresync's Telegram is retired (aresync e10dc07: the code is gone; `TG_*` commented out on the Mac and the server). Aresium's own bot (`aresium-bot.service`, its `current` command) was stopped and disabled 2026-10-30
   (owner); Aresium's messages are the app's own (planned, see the review of 2026-10-30).

## Tours

### The shared tour pieces

**The shared tour pieces** (`Shared/Design/TourPieces.swift`, moved from Aresium's `TourScreens.swift` in brief 139,
Aresium's look unchanged): `TourGuide` (what a tour points at, `\.tourGuide`), `tourSpot` (each app wraps it as
`tourAnchor` with its own spots), `tourSpotlight` (the veil and ring, around several spots together when a step names
more than one), `tourScrollsToTarget` and `TourScrollPlace`, and `TourCard` (count, way out, optional title, words, main
button in ink or the accent, an optional link). Aresium's `\.tour`, `tourAnchor` and `tourCard()` sit on them.

## Privacy

**Privacy** (2026-10-24, brief E6): each app and widget folder has its `PrivacyInfo.xcprivacy` (what it collects,
the required-reason APIs its Release binary really imports); each app's `Info.plist` has
`ITSAppUsesNonExemptEncryption = NO`. A new data type or API means updating the manifest, `docs/APP-STORE.md` (App
Store Connect's answers, TestFlight test information, what is missing) and `ares-empire/docs/PRIVACY.md`.

## Showcase images

**Showcase images** (2026-10-26): `showcase/<app>/NN-name.png`, each app's main screens inside a drawn iPhone, with
the sample data only, for display (portfolio, website); `showcase/README.md` lists them with captions. Refresh with
`python3 scripts/showcase.py [app ...]` (builds the apps, uses its own simulator `claude-showcase` and deletes it,
about 6 min for all five); the shots and their launch arguments are the `SHOTS` table in the script. After a screen
changes, re-run that app and look at its images (and `build/showcase/contact-sheet.png`) before committing.

## Languages (every app in English and German)

Decided 2026-10-24 (owner), rules in `ares-empire/docs/LANGUAGES.md`. The iPhone's language, or the app's own, picks
German or English. The Mac and the simulators are set to German, so the apps open in German there.

- **The app's own language: Settings → General → Language in every app** (the gear in its header; row "Sprache ·
  Deutsch" shows the language the app shows now). It offers Like the iPhone / English / Deutsch and writes the app's own
  `AppleLanguages` (`Shared/Language/LanguageSetting.swift`; "like the iPhone" removes it), the same setting iOS keeps in
  Settings → Apps → the app → Language, so the two always agree. iOS 27 shows that iOS entry only while the iPhone lists
  two or more languages (tested 2026-10-24), hence the in-app page. On the simulator, `xcrun simctl spawn <udid>
  defaults write <bundle id> AppleLanguages …` lands outside the app's container (the app follows it, iOS's page does
  not); choosing in the app or in iOS Settings writes the app's own defaults.
- **Switching restarts the app inside itself** (owner, 2026-10-25, brief G1). A row that brings another language asks
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
  `Aresium/AresiumShared/AresiumShared.xcstrings`, `Aresus/AresusShared/AresusShared.xcstrings`, `Arestia/ArestiaShared/ArestiaShared.xcstrings`. Code in those folders
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
server's `feedback` collection, which emails the owner), About (Privacy and Imprint open `LegalPage` in the app's language, inside the app in Apple's in-app browser (`SFSafariViewController`, closed with its own X), brief 41, `Shared/Design/InAppBrowser.swift`: SwiftUI's own
`openURL(_:prefersInApp:)` presents from the window's root, which iOS 27.0 refuses while a sheet such as Settings is open; Fonts & licences shows the OFL texts from
`Shared/Fonts` and an app's own licences, `SettingsApp.licences`, in a Data card (Aresium's shop list and local places) and a Code card (`BundledLicence.kind`; Aresium's engine packages, brief 315: the engine build lists them from the bundle, `scripts/aresium-engine.sh` writes their licences, and `EngineLicenceTests` fails when the app's list misses one), Version), Account (the email from the login answer, `EmpireSession.email`; Change password; Log out
"in all Ares apps on this iPhone", which asks first (brief 41, `Shared/Settings/LogOutQuestion.swift`: Apple's
confirmation dialog, as Leave and Delete, "Log out?" / "You'll be logged out of all Ares apps on this iPhone.", in an app
that works without an account plus "Your data in <app> stays."; Log out, destructive, and Cancel, which iOS 26 shows as a
popover from the row, cancelled by a tap outside) and then does what the
app's log-out did before (in sample mode it leaves the sample, as before); then, in the hub's soft red, Leave
<app> and Delete Ares account: pages in `Shared/Design/AccountScreens.swift`, see "Accounts in every app" above). An app
whose server keeps data per account passes its `DELETE …/me` as `SettingsApp(serverData:)` (today only Arestemis:
`ArestemisAPI.accountDataURL`); leaving deletes it there first. An app that works without an account
(`EmpireAppIdentity.accountOptional`, only Aresium, brief 22) shows, while no Ares app is logged in, a quiet "Ares
account" section last instead when it offers to sign in (`SettingsApp(offersSignIn:)`, true by default): Sign in
(`Shared/Design/SignInSheet.swift`, the login without Create account) and the app's line `SettingsApp(signInNote:)`;
signed in, the account section as everywhere (Leave <app> only while the account has the app); which one is
`SettingsAccountSection.shown`. **Aresium offers no sign-in** (brief 215, the owner 2026-11-02, the first-run review's
finding 5: an Ares account there is only for his own server, so testers met a sign-in they could not use): signed out,
its Settings end with About; its "Ares account" section shows only while a login of the Ares apps exists on the iPhone
(the owner signs in through his other apps). The Sign in sheet stays (DEBUG `-openSignIn`), without "One Ares account for
all Ares apps" since brief 215. **Switches** (brief 47, the owner's phone: in dark mode "on" was a pale ink track under the white knob, so on
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

Decided 2026-10-24 (owner: part of the standard design, before any new app); built 2026-10-25 for all five apps and
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

## TestFlight and App Store Connect

Upload with `scripts/testflight.sh <App>` (Setup above); before an upload, the Release resource audit
(`scripts/check-release-resources.py`, see `CLAUDE.md` → Checks). Each app has an App Store Connect record with an
internal group that gets every build automatically. The paid team is set at project level in every project; the App
Groups `group.de.ares-empire.aresium` and `group.de.ares-empire.shared` are registered for the bundle ids, the widgets'
too (`de.ares-empire.aresium.widget`, `de.ares-empire.aresus.widget`); the shared Keychain group needs only the team
prefix. For people besides the owner: external testing with a public TestFlight link per app, entered as `install` in
`ares-empire/webauth/apps.json` (the Empire app's Install button shows it to accounts that have the app). The forms:
`docs/APP-STORE.md`. Every build so far: `docs/BUILDS.md`.

## Pinned home services

`Shared/HomeReach/` provides `SPKIPin` for EC P-256 server keys and `PinnedServer` for TLS challenges and
redirects. `PinnedSession` caches one ephemeral HTTP session per pin and creates a dedicated session for
events. Session construction happens outside the cache lock. The cache keeps the first session
installed for a pin and invalidates duplicates.

`HomeRoute.select` reads a mailbox of results from a saved home address, discovery, and a remote
listener. A winner cancels losing probes and returns immediately. The cap bounds the wait even
when a probe is stalled. Each caller supplies its health probes, discovery, and remote policy.
The default policy allows remote, including on the lock screen.

`Deadline` uses `ContinuousClock` so time spent suspended counts. An `Attempt` records the first
ending and whether a commit ran under the same lock. Waiting ends on a result, the cap or caller
cancellation. Failure triggers the attempt's registered cleanups. Synchronous work runs on a
dispatch queue and can be abandoned when a system call stalls. An ended attempt refuses a late
commit. Tests can supply a clock. Request admission and decisions about repeating an action belong
to the calling app.
