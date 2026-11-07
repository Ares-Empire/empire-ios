# Developing the Ares iPhone apps

How the repository is laid out, how push is wired and how a build reaches TestFlight. The overview is in the
[README](../README.md); the full working notes are in [CLAUDE.md](../CLAUDE.md), the rules for coding agents in
[AGENTS.md](../AGENTS.md).

## Layout

```
empire-ios/
  Aresium/        Aresium.xcodeproj: the Aresium app, its widget extension, tests
  Empire/         Empire.xcodeproj: the Ares Empire app (the hub), tests
  Aresus/         Aresus.xcodeproj: the watchtower (every province, the server) and Aresync's sync runs, its
                  status widget (home and lock screen), tests
  Arestemis/      Arestemis.xcodeproj: the flat hunter (search, hunt, matches, applications), tests
  Arestoteles/    Arestoteles.xcodeproj: Patrik's Weltbild vault (positions, topics, library, search, edits,
                  quick notes, Discuss with Claude, Spotlight), tests
  Shared/         compiled into every app: the Empire login (one login for all apps) and the account's own
                  actions (create, password, ask for access, leave an app, delete; Auth/), the network
                  layer, the fonts, push (Push/: PushCenter + PushAppDelegate), the contact form
                  (Support/); each project includes it as a synchronized folder
  scripts/        new-app-project.py (a new app project, wired to Shared/), strings.py (String Catalogs),
                  check-shared-login.sh, aresium-fixtures.mjs
```

**Push** (`Shared/Push/`, server: `ares-empire/docs/PUSH.md`): an app adopts `PushAppDelegate` with
`@UIApplicationDelegateAdaptor`, calls `delegate.push.start(app:session:categories:)` once its session exists and
routes `delegate.push.openedURL`. Until the paid team allows the Push capability, try a notification on the
simulator with `xcrun simctl push <udid> <bundle id> Shared/Push/sample-push.apns` (the app must have asked for
permission first).

Code moves into `Shared/` when a second app needs it (2026-10-24: the login, network layer and fonts, for the
Empire app). A new province app: `python3 scripts/new-app-project.py <Name> <bundle id> "<display name>"`.

## Working on it

- Needs a Mac with Xcode. Work with **Claude Code on the MacBook**, so it can build, run the
  simulator and fix errors itself. aresync clones this repo there automatically.
- The services themselves (Aresium server, Empire login) are changed in their own repos on the server.
- **Never commit secrets:** no API keys, no App Store Connect keys, no passwords. Server URLs are fine.

## Tests

Use the same runner as CI, from the worktree:

```sh
bash scripts/test-unit.sh --all
bash scripts/test-unit.sh Aresium Empire
bash scripts/test-unit.sh --timing Aresium
python3 scripts/strings.py check
```

The runner needs Xcode 27.1 and the iOS 27.0 iPhone 17 runtime. It creates a unique `test-unit-…` simulator and deletes
it on success, failure or interruption; `--keep-simulator` retains it. It builds Debug with ad-hoc signing, without an
Apple account, serializes test execution, selects only the app's unit-test target and never retries. Logs, derived
data and `.xcresult` bundles stay in `build/test-unit/`. Each app's result is replaced on its next run; simultaneous
runs of the same app are refused. A failure prints test names from the result bundle; build/launch failures point to
the local log, with each failure's first line. GitHub runs a separate job per app with `--ci` and uploads no
artifacts. `--ci` leaves out the receipt tests listed in the script's `ci_skips` (Vision's barcode detection finds
nothing on GitHub's virtual Macs, 2026-11-07); run them locally before merging receipt work.

For a build or an AXe screen check, create your own simulator as described in [AGENTS.md](../AGENTS.md) and keep derived
data inside `build/`. Shared-login probes, UI tests, AXe checks, notifications delivered to a phone, camera, Face ID
and device rendering remain manual.

The timing inventory is explicit in `scripts/test-unit.sh`. `--timing` runs only that inventory, including enabling
the previously opt-in measurement suites. Local-places measurements use the shipped engine and packed list; these
Debug simulator measurements do not replace the Release/device memory gates recorded in `CLAUDE.md`.

The wall-clock audit (brief 242):

| Tests | Correctness run |
| --- | --- |
| Aresium import batching and result/banner tests (including FileDrop, ImportThenCategories, MessageScreens) | Await batching/upload/reload completion even when an automatic import already started; explicitly control the banner timer. Production still dismisses successes after 4.5 seconds. A held reload and advanced timer reproduce the vanished-banner failure; a held request also proves that the explicit trigger can return before an existing import finishes. |
| Aresium PhonePickerBatch | Suspend debounce and await its cancellation/flush; no 650 ms sleep or one-hour substitute. |
| Aresium WindowComfort, SelectionScreens, Tour | Await receipt tasks, completion callbacks and observed state. |
| Aresium BackSwipe | Wait for UIKit state on run-loop events and Observation publications, including mark attachment and transition completion. |
| Aresium PhoneStore | Remove the unnecessary 100 ms pause after the awaited fixture write. |
| Aresium NameSearch, PickerTiming, LocalPlacesMeasurement, Engine timings, 5,000-payment sort, FixedCostTiming | Only `--timing`; existing assertions and budgets unchanged. Measurement/GC/layout sampling pauses remain in these experiments. |
| Aresium BatchChanges (500 rows from 60 shops) | Keep all data, worker/call-count and undo assertions in correctness; the unchanged 300 ms budget runs separately with `--timing`. The loaded validation run demonstrated 321.453 ms with all data assertions passing. |
| Aresium PackedLocalPlaces, SettingsWork | Keep in correctness: identity, call counts and worker placement, with no speed budget. |
| Arestemis PriceMonitor | Manual pacing clock and a held server answer replace sleeps and request polling. Existing minimum intervals are checked on that clock. |
| Arestemis ProductSuggestions | Await the completed retry; its minimum pacing interval remains a correctness check, with no maximum speed assumption. |
| Arestemis SampleBackend | Use its existing injected date instead of comparing sample creation with the wall clock after reload. |
| Arestemis Spelling; Arestoteles BestMatches | Manual timeout/placeholder clocks and observed cancellation; the original five-second response budgets run only with `--timing`. |
| Arestoteles Edit, Version, non-queue VaultArrival tests | Await operation publication or worker-entry callbacks. |
| Arestoteles quick-note queue | Unchanged per brief 243's ownership, including its remaining `eventually` polling helper in TestSupport and VaultArrival queue test. |
| Arestoteles VaultTiming | Only `--timing`, with its measurement flag enabled. |
| Empire PrivacyCover | Already passes explicit instants; no wall-clock wait or speed budget. |
| Aresus SharedDrops | Inject the retry date; preserve the deadline assertion and check that processing cannot retry before it. Other drop tests already use explicit dates or await work. |

## Releasing to the phone (TestFlight)

1. Bump `CURRENT_PROJECT_VERSION` (project-level build settings, the one place for app and widget), commit, then
   `scripts/testflight.sh <App>`: it archives the app (the archive appears in Xcode's Organizer) and uploads it as an
   *App Store Connect* build (not *TestFlight Internal Only*: such a build can never go to external testers or the App
   Store; internal testers need no review either way). `--export-only` signs without uploading. By hand, the same is
   Product → Archive in Xcode, *Distribute App* → *App Store Connect*. Each of the five apps is uploaded on its own,
   and its App Store Connect record must exist first (Apps → + → New App, with its bundle id).
2. After processing (a few minutes) the build shows up in the TestFlight app on the iPhone → *Update*.
3. Each build stays installable for 90 days; any newer build restarts that clock.

Later: automate step 1 (Xcode Cloud or a script with an App Store Connect API key kept outside the repo).

What App Store Connect asks (App Privacy, TestFlight test information, demo login) and what is still missing before
the App Store: [`docs/APP-STORE.md`](APP-STORE.md).

Release configurations exclude `Preview Content/` (Aresium, Empire) and `Samples/` (Arestemis, Aresus,
Arestoteles), plus the shared `sample-push.apns` simulator fixture; Debug keeps them. Arestemis's shipping tour
history lives in `Resources/prices-9.json`, and Aresium keeps `AresiumShared/dashboard.sample.json` for its shipping widget placeholders and gallery.
Before uploading, run `python3 scripts/check-release-resources.py --app <App> --bundle <path/to/App.app>` on the
archive's `.app` under `Products/Applications/` (the same command accepts a Release simulator `.app`).
The audit checks forbidden fixtures recursively, including extensions, and required runtime resources at their
loader's bundle paths. When adding a sample, trace its Release callers and update `scripts/release-resources.json`
with its classification and reason; put shipping resources outside excluded folders and add their required bundle
paths. Classify unused files too, retaining them in source for review. Unclassified samples fail the audit.
