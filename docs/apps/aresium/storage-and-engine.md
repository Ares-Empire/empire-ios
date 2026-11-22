# Aresium: Phone mode, storage and the engine

Part of Aresium's notes; start at `docs/apps/Aresium.md` (its decisions in force). Covers the two modes, the store and its schema versions, moving over, the bundled engine and local places, Settings' and the picker's timings, targets and Info.plist, Fonts & licences, the phone-mode launch arguments.

## Aresium phone mode

**Aresium phone mode** (2026-10-27, briefs 15, 18 and 22; plan `ares-empire/docs/ARESIUM-FOR-OTHERS.md`): everyone
but the owner keeps their Aresium data on their iPhone. **No account** (owner, 2026-10-27, brief 22): Aresium opens in
phone mode on the phone's one store at once, without a login and without waiting for any server (`ModeStore.start`);
the first screen or the dashboard. **Server mode** stays in the app, unused since 2026-10-31: the server answers
`server` only for ids in its `APP_SERVER_MODE_USERS` (empty), so the owner's Aresium shows the phone's data as
everyone's (logging in to another Ares app had switched it to his old server data). While a login
whose account has the `aresium` service exists, the app asks `GET /api/mode` once per session and remembers the answer
per account id (`aresium.mode.<id>` in the app's defaults): `server` → today's server dashboard (`ServerBackend` on
`APIClient`); `phone`, 401 (logs out everywhere), 403 (remembered as phone), an error or offline without a
remembered answer → phone mode. A remembered `server` works offline, at launch too (the saved login's account from
the marker; `ModeStore` starts there, so the phone screens never flash for the owner). When that login ends (a logout
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
version 6, brief 69; version 7 money paid back, version 8 fixed-cost marks; `LedgerSchemaCurrent` names the version the app opens, tests use it too); older stores move on by lightweight stages,
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

## Settings (brief 57)

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
schema 8 with the receipts, cash entries, corrected shop names, payment names, category sides, default personal names,
links of money paid back (brief 202) and fixed-cost marks (brief 208), `Aresium-<date>.json`, through the share sheet), Restore
from an export (only into an empty store, all or nothing; chosen categories and corrected shop names are replaced;
schema 1–7 files still restore).

## Engine, Fonts & licences, phone-mode launch arguments

Settings →
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

## Targets

Targets: `Aresium` (app), `AresiumWidgetExtension` (widgets, folder `Aresium/AresiumWidget/`, embedded in the
app), `AresiumTests`. `Aresium/AresiumShared/` is compiled into both app and widget (theme, `AppTheme`, `AppGroup`,
widget snapshot); everything else belongs to one target. App Group `group.de.ares-empire.aresium` in both
entitlements files (on the simulator Xcode embeds them as "simulated" entitlements; on the phone it needs
the paid team).

## Info.plist

`Aresium/Aresium/Info.plist` holds only what build settings cannot (document types: the share sheet offers
"Aresium" for `.csv`/`.xml` exports and MT940 `.sta`/`.mt940`, an imported type `de.ares-empire.aresium.mt940`; not
`.txt`, which iOS knows only as plain text, so Aresium would be offered for every text file; `.txt` statements are
picked inside the app; not `.zip` (brief 204): the engine reads no ZIP, it only answers "Unzip the file first", so
Aresium would be offered for every zip on the phone just to refuse it; the picker and a drop still take a `.zip` to
say so); it is merged with the generated plist and excluded from the folder's resources in the project file.

## Local places memory gate (briefs 95 and 98, 2026-11-01)

Adopted: the packed OpenStreetMap places list (`Engine/de.places.bin.gz`) stays loaded for the app's lifetime, about 13 MB above baseline (12.40–13.68 MB, about 94 ms once at the first phone engine's start). The budget for bundled data is under "Decisions" in `docs/apps/Aresium.md`. Both measurement reports: `docs/reviews/2026-11-01-local-places-memory-gates.md`.
