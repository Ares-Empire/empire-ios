# empire-ios — rules for Claude Code

The Ares Empire's iPhone apps, all in this one public repo. This file holds the rules for every app. How each app and
each shared piece is built lives in `docs/`, read on demand: the table below says what to read before touching what.
Read `README.md` and `docs/DEVELOPMENT.md` first. The decisions behind the apps are in the ares-empire repo
(`docs/IPHONE-APPS.md`), the login plan there too (`docs/ACCOUNTS.md`).

## Before you touch X, read

| You touch | Read first |
|---|---|
| Aresium | `docs/apps/Aresium.md`: its decisions and a topic table; then only the topic file for your task |
| Arestemis | `docs/apps/Arestemis.md` |
| Aresus (with its Aresync tab) | `docs/apps/Aresus.md` |
| The Empire app | `docs/apps/Empire.md` |
| Arestoteles | `docs/apps/Arestoteles.md` |
| Arestia | `docs/apps/Arestia.md`, then `docs/ARESTIA-APP.md` |
| `Shared/`: login, accounts, Settings, languages, light mode, push, support, switcher cover, tours | `docs/SHARED.md`, the section for it |
| Setup, signing, a TestFlight upload | `docs/SHARED.md` → Setup and → TestFlight; `docs/APP-STORE.md`; add the build to `docs/BUILDS.md` |
| A review or a council | `docs/REVIEW.md` |

New as-built notes go into that app's file (or `docs/SHARED.md`), never into this file. An owner decision goes with its
note, one line, "(owner, YYYY-MM-DD)", no quotes; when it changes, change the line (git keeps the old one). In these
public files the owner is "the owner", never his name.

## Rules for every app

- Native SwiftUI only — no web views wrapping the websites.
- Each app uses its service's existing JSON API; if the API lacks something, change the service (its own repo), don't
  work around it in the app. A good structure is worth more work now: a copy of a service's logic or a workaround in
  the app is usually the wrong call (`ares-empire/EMPIRE.md` → How we build apps).
- Read server answers leniently: an unknown value, kind or site never breaks a screen; it is kept or read as unknown,
  or follows the endpoint's documented fallback (the app's file in `docs/apps/`).
- Log in via the Empire account system, never a service's own password (`docs/SHARED.md` → One login for all apps).
  Exceptions: Aresium works without an account and Arestia has none.
- Differences between apps go into `EmpireAppIdentity`, never into checks inside a view.
- Nothing in `Shared/` uses `UIApplication.shared`: the widgets compile `Shared/` too.
- Every notification delegate answers through `NotificationTap.answer` (the completion-handler form), never the `async`
  form, which crashed every Arestemis notification tap up to build 20. Push wiring never runs in samples or tests.
- Every place that asks iOS for something shown over the app (camera, location, notifications, Face ID) wraps it in
  `SystemPrompt.begin()`/`end()`, so the switcher cover stays out of the way.
- Every server caller passes the token it sent to the auth-failure handler: a refusal counts only for that token, and
  only a 403 `no_access` (or a 403 without a code) closes an app.
- An App Intent is compiled into one target only (one in both app and extension runs in the extension and breaks
  Spotlight). App Intent titles, descriptions and phrases never name Apple products (Mac, iPhone, Siri); Apple refused
  a build for it (ITMS-90626). In-app texts may.
- Every app has one Settings sheet from the gear (`gearshape`) in its header (`SettingsScreen`); a new app adds only
  its own section. Switches inside it use `EmpireSwitchStyle`, never ink (`docs/SHARED.md` → Settings).
- After meaningful work, add a line to the Chronicle: `ares-empire/CHRONICLE.md` (its header says where else).

### The look

- Design language: the Ares Empire "crown language" in `ares-empire/EMPIRE.md` (near-black, polished gold accent,
  Space Grotesk / JetBrains Mono).
- Every screen works in light and dark (Settings → Appearance; light mode is part of the standard, owner, 2026-10-24).
  Colours are light/dark pairs (`Ink`, `AppAccent`, `StatusTone`, … in `Shared/Design/EmpireDesign.swift`); a colour no
  token covers gets its own pair, named for its meaning. Never `.white`/`.black`/`Color(hex:)` for ink or surfaces,
  never a material pinned dark. Screens never call `preferredColorScheme`: the root sets the look on the window; a
  mode with its own colours uses `holdsColorScheme(_:)`. Details: `docs/SHARED.md` → Light mode.
- **Nothing that moves sits over or under a pathless shadow** (brief 87): `.shadow` on a view gives every layer under
  it a shadow of its own without a path, which Core Animation draws from the layer's pixels in an offscreen pass, again
  in every frame in which anything over that spot changes (a pulse, a spinner, a counting number). On the owner's
  iPhone (iOS 27.0.1) such a pass came out as a black rectangle the size of the shadow (the hunt card's pulsing dot,
  builds 2–4; the simulator never shows it). So: put `.shadow` on a surface, never around content; prefer a shape
  style's shadow (`.fill(color.shadow(.drop(…)))`, no pass, drawn only outside the shape) or a still image
  (`drawingGroup`, drawn once; keep it within the view's bounds, as a `List` row cuts off what is drawn past the row),
  as `GlassCard` does. Check a screen that animates with `scripts/offscreens/offscreens.sh` (`CA_PRINT_OFFSCREENS`): a
  steady frame should list no shadow, mask or group passes.
- **A blur draws straight onto the screen** (brief 67): never put a material (`.ultraThinMaterial`, `GlassCard`'s
  blur) under `.shadow`, `.mask`, `.compositingGroup`/`.drawingGroup` or a blend mode; Core Animation then takes the
  blur inside an offscreen pass. Its shadow is the material's own style (`Material.ultraThinMaterial.shadow(.drop(…))`).
  Arestemis's `edgeFade` is drawn by the wall (`provinceWall()`) instead of masking the scroll view.
- Every app's main screen (the first tab's root) ends with the app's name: `WordmarkScrollView`
  (`Shared/Design/EmpireDesign.swift`) in place of its `ScrollView`; the band scrolls with the content and shows only
  when you scroll down (owner, 2026-10-24). Its launch argument for screenshots: `-scrollToEnd` (Arestemis
  `-scrollBottom`).
- An alert's ordinary confirm button is a plain button in ink, never Apple's filled default button (it draws system
  blue whatever the tint); a destructive one stays destructive.
- A line that does not fit wraps onto a second line, never into a smaller font (fixed-size day tiles may shrink their
  labels at the largest accessibility sizes). Tap areas are at least 44 pt.
- Every motion has a Reduce Motion fallback (none or a fade).
- The back swipe stays the system's own.
- Screens follow the existing website and app components, not new decoration.

### Languages (every app in English and German)

Decided by the owner on 2026-10-24; rules in `ares-empire/docs/LANGUAGES.md`, how it is built in `docs/SHARED.md` →
Languages. The iPhone's language, or the app's own (Settings → General → Language), picks German or English. The Mac
and the simulators are set to German, so the apps open in German there.

- **Write English in the code, German in the String Catalogs.** SwiftUI literals (`Text("Save")`) are looked up by
  themselves. Text built as a `String` goes through the apps' own `String(localized: "…")`
  (`Shared/Language/AppLanguage.swift`), with a table as `String(localized: LocalizedStringResource("…", table:
  "Shared", locale: .appLanguage))`. Pure functions that tests pin take `language: AppLanguage = .current`. Names and
  numbers-only text use `Text(verbatim:)`. Never keep a looked-up text in a `static let` or anywhere else that outlives
  a language switch.
- **One catalog per folder that more than one target compiles** (`Shared/Shared.xcstrings`,
  `Aresium/AresiumShared/AresiumShared.xcstrings`, `Aresus/AresusShared/AresusShared.xcstrings`, `Arestia/ArestiaShared/ArestiaShared.xcstrings`); code there names its
  table, or the widget misses the string. Everything else uses the target's own `Localizable.xcstrings`.
- A word that means different things in two apps gets its own key.
- **After changing text:** `scripts/strings.py sync`, write the German (`scripts/strings.py fill de.json`, only new
  keys; it writes a key's German into every catalog that has it, so read the `git diff` of the other apps' catalogs),
  then `scripts/strings.py check` must say 0 problems. Look at every changed screen in German before merging; a label
  that wraps gets a shorter German word, not a smaller font.
- **Tests run in English**; German cases call the pure functions with `language: .german` or run in
  `AppLanguage.$scoped.withValue(.german) { … }`.
- German style: "du", plain and short; the apps' terms: Suche/Angebote/Filter (Arestemis), Problem/Aktiv/Inaktiv
  (Aresus), Buchung/Ausgaben/Einnahmen (Aresium), EROBERT/BELAGERT/… (Empire status words). "THE EMPIRE" stays a name.

### Privacy and safety

- This repo is public: no personal data (owner details come from the owner file, `ares-empire/docs/PRIVACY.md` →
  Owner file), no absolute home paths, no real data in samples, fixtures or screenshots.
- Samples and screenshots use only made-up data and the made-up `SampleAccount` server, never the real account server;
  sample mode only pretends to leave, delete or send.
- Tokens live in the Keychain only; the App Store Connect API key only in the Mac's Keychain (`scripts/asc.py`).
- A new data type or API means updating that app's `PrivacyInfo.xcprivacy`, `docs/APP-STORE.md` and
  `ares-empire/docs/PRIVACY.md`. Every app's Info.plist sets `ITSAppUsesNonExemptEncryption = NO`.
- Each app's own rules (Aresium's lock, its data staying on the iPhone, Arestia's pinned trust, …) are at the top of
  its file in `docs/apps/`.

## Building, testing, screenshots

- Simulators: the iOS 27.0 runtime for all normal iPhones (27.1 runs only the foldable iPhone Duo, whose screenshots
  come out black). `xcrun simctl` works without DeviceHub. A job makes its own named simulator and deletes it at the
  end; derived data stays inside `build/`.
- Every project sets `DEVELOPMENT_TEAM` at project level with automatic signing. New app projects come from
  `scripts/new-app-project.py`; the full list of places a new app touches is in `ares-empire/docs/IPHONE-APPS.md` → A
  new app touches.
- Upload with `scripts/testflight.sh <App>`; a new bundle id is first registered with a signing-only `--export-only`
  archive. App Store Connect API calls go through `scripts/asc.py`. Resources that exist only for samples are marked
  `debug_only` in `scripts/release-resources.json`.
- Server samples and fixtures are copies of the servers' own samples, refreshed by script, never edited by hand
  (`npm run sample` + `aresium-fixtures.mjs`, `empire-fixtures.sh`, `aresium-engine.sh`).
- Gestures, long presses, context menus, menus and drag-and-drop are checked with real touches: AXe, or a temporary UI
  test in `Aresus/AresusUITests` that drives the app, passes 3 of 3 runs and is deleted afterwards. DEBUG launches that
  push screens distort gesture measurements: count the pushes and make launch actions run once.
- Screenshots of every new screen go in `build/<brief>-*.png` (the brief's number, or a short slug for small work
  without a brief): English and German, light and dark, red mode where the app has it, and the largest text size
  (`xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`; `large` is the default). Take them
  with `axe screenshot` (`simctl io` sometimes caught the launch screen). When a screen in the showcase changes (the
  screens are listed in `scripts/showcase.py`), run `scripts/showcase.py <app>` again and look at the images before
  committing.

## Workflow

**Who builds** (owner, 2026-10-26 and 2026-10-31): design work (screens, the look, visual assets) is Claude's: the
session itself for small work, a Claude agent (the Agent tool) for a bigger build; everything else (data, plumbing,
scripts, tests, server code) that is worth delegating goes to Codex, which continues after its first month (renewed,
owner, 2026-11-18). Codex may build a
screen's structure and logic; Claude does the look, starting from the existing website and app components (owner,
2026-10-24). Where the look already exists in the website and the app, Codex may build the screens from those
components and Claude checks the look (owner, 2026-11-03). Models: global CLAUDE.md ("Codex models", "Claude models").

| Who | Does | Does not |
|---|---|---|
| **The owner** | Decisions, Apple account and App Store Connect, tries TestFlight builds on the phone | Relay prompts between tools |
| **Claude** | Plans, sets up the Xcode project, anything touching login or tokens, **the look of every screen**, writes briefs, runs Codex, builds and runs the app on the simulator, commits, merges, TestFlight uploads | Bulk typing Codex can do from a clear brief |
| **Codex** (run by Claude) | Bounded builds from a brief: data, models, the API client, flows and state, widget plumbing, unit tests; screens only as structure for Claude to style; second opinions and council seats | Decide the API contract or the login flow; own a screen's look; edit `project.pbxproj` unless the brief says so; merge |

**Delegate** when the task fits a brief with a clear "done" (it compiles, these tests pass, this screen shows this
data) and the build is clearly bigger than the brief. Otherwise Claude does it. Briefs are in `prompts/` (Arestemis
server briefs in the private Arestemis repo's `docs/briefs/`, numbered in the same series). The rules for builders are
in `AGENTS.md` here and `aresium/AGENTS.md`; they hold for Codex and Claude agents alike: a worktree, a full brief, and
Claude (not the builder) checks and merges. Work merged through a pull request follows the global CLAUDE.md →
Merging. A Claude agent stopped by the usage limit is continued after the reset by a fresh agent from its commits and
a short handoff (global CLAUDE.md: a fresh agent per step, owner, 2026-11-14).

### Running Codex

1. **Brief:** copy `prompts/TEMPLATE.md` to `prompts/NN-slug.md`. Settle the design choices in it; link to rules
   instead of restating them. Commit it to `main` before branching.
2. **Worktree:** a new one per brief, `~/empire-ios-NN-slug` on branch `codex/NN-slug` (created in step 3). Never let
   Codex (or uncommitted work) sit in `~/empire-ios` itself: aresync auto-commits and pushes that checkout.
3. **Run** as a `codex-job` in the background (`run_in_background`; `--wait` wakes Claude when it ends):
   ```
   WT=~/empire-ios-NN-slug
   git -C ~/empire-ios worktree add -b codex/NN-slug "$WT" main &&
   codex-job start empire-ios-bNN-build -C "$WT" -m "$MODEL" --effort high -s danger-full-access \
     --brief "$WT/prompts/NN-slug.md" --wait
   ```
   Pick the model per job (global CLAUDE.md) and say which and why in the brief. Always pass `-m`: the Mac's Codex
   default is not kept current. When the wait exits 0, save Codex's final message (turn 1) to
   `~/empire-ios/codex-runs/NN-slug.md` (gitignored; `mkdir -p` it first; `~/aresync/TOOLS.md` → "Saving a report"). Steering, fix rounds and the raw
   `codex exec` fallback: TOOLS.md → codex-job. Run `codex-job` with the Bash sandbox off.
4. **Check** (below), commit in the worktree, merge to `main` and push it, remove the worktree, set the brief's
   status line. Push as soon as work is merged, in every Empire repo; aresync's daily run is only the backstop (owner,
   2026-10-25).

**Why no sandbox:** Codex's `workspace-write` sandbox blocks `xcodebuild` and the simulator (tested 2026-10-23), so
builds run without it (owner, 2026-10-23). The limits the sandbox used to enforce are rules in `AGENTS.md`: stay in
the worktree, never commit or push, no installs. Council seats and reviews still run with `-s read-only`.

**Checks are light, but never skipped:**
- Before a TestFlight upload, run `python3 scripts/check-release-resources.py --app <App> --bundle
  <archive>.xcarchive/Products/Applications/<App>.app`; the Release resource audit must pass.
- After shared changes, run the five-app sample tap-through in both languages and appearances:
  [Smoke tests](scripts/smoke-ios/README.md).
- Build and run the tests yourself on the simulator (`bash scripts/test-unit.sh <App>`, the same run as GitHub's).
  Never take Codex's "build succeeded" as evidence.
- Read the diff: quickly for layout, carefully for anything near login, tokens, the Keychain, or API calls.
- Run the app on the simulator and look at each screen the brief touched.
- Tap through it with **AXe**, usually instead of a temporary UI test: `axe describe-ui` lists every button and
  label, `axe tap --label "…" --tap-style physical` taps (the default style does nothing in these apps),
  `axe swipe`/`touch`/`type`/`screenshot`; all take `--udid`, none needs the DeviceHub window. Steps and catches:
  `~/.claude/skills/ios-simulator/SKILL.md`; Codex's line is in `AGENTS.md`.

**Council** (method: `ares-empire/docs/COUNCIL.md`; iPhone specifics: `docs/REVIEW.md`): a few seats with their own
roles, blind first, then checking each other's answers, for hard-to-undo choices, milestones, a bug that comes back,
and every 2–3 weeks over merged Codex work.

**Allowance:** `/status` in an interactive `codex`, or the `rate_limits` line in the newest
`~/.codex/sessions/**/*.jsonl` (`used_percent`; window 10080 min = weekly).

## Open (across apps)

- Phone checks not yet recorded as done: widgets incl. row taps (`docs/reviews/2026-10-23-pre-testflight.md`); the
  shared login across the apps on the device; the Empire app opening Aresium (`aresium://`); no connection; after
  logging out in another app, a widget and a notification; the switcher card and Control Center (switcher cover);
  both looks (the iPhone switching by itself in the evening while an app is open, widgets on a light and a dark home
  screen); the comfort items of 2026-10-30, each tried once. Each app's own open items are in its file.
- Hub data, not this repo: Aresium's "About" on the hub (`data/state.json` on the server, `lock: true`) is outdated
  (Next.js, Prisma); the owner has not decided whether to rewrite it.
