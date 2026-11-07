# Local iOS smoke tests

Run from the worktree on the Mac with Xcode, AXe and the iOS 27.0 runtime already installed. Python 3 uses only the standard library. No account or server is involved.

```sh
python3 scripts/smoke-ios/run.py --all --language en --appearance light
python3 scripts/smoke-ios/run.py --all --language de --appearance dark
python3 scripts/smoke-ios/run.py Aresium Arestoteles
python3 scripts/smoke-ios/run.py Empire --app-path Empire=build/smoke/DerivedData/Build/Products/Debug-iphonesimulator/Empire.app
python3 scripts/smoke-ios/run.py --self-test
python3 -B -m unittest discover -s scripts/smoke-ios -p 'test_*.py'
```

App names are case insensitive; omitted names mean all five. Each invocation creates a fresh `smoke-<random>` iPhone 17, uses its UDID for every operation, and deletes it in `finally`, including on failure, Ctrl-C or SIGTERM. `--keep` explicitly leaves only that run's simulator for inspection; delete it afterwards with `xcrun simctl delete <printed-udid>`. SIGKILL or a host crash cannot run cleanup. A normal run never reuses a simulator or another run's app containers.

The runner builds Debug apps with `xcodebuild build -project <App>/<App>.xcodeproj -scheme <App> -configuration Debug -destination 'platform=iOS Simulator,id=<owned-udid>' -derivedDataPath build/smoke/DerivedData CODE_SIGNING_ALLOWED=NO`. `--app-path App=path.app` skips that app's build; pass it repeatedly for multiple apps. Supplied apps must be Debug simulator builds with sample mode. DerivedData is shared between invocations for incremental builds; run this command serially within a worktree.

Every launch supplies `-sampleData`, `-AppleLanguages` and `-AppleLocale`. The simulator's appearance is set with `simctl ui`. Aresium additionally uses `-samplePhone`: its server sample disables category saves, while the phone sample creates an isolated ledger from invented bank exports. The scripts never launch without sample mode. AXe's first accessibility requests after boot may time out. Each launch first waits up to 120 seconds for the app's accessibility root, retrying those requests; scenario screen assertions then use their own shorter deadlines.

## Writing scenarios

Each `scenarios/<app>.py` exports `run(r)` and optionally `ARGS`, the extra initial sample launch arguments. Use existing identifiers before labels. Keep assertions specific to the result of the action:

```python
ARGS = ('-samplePhone', '-sampleOverview')


def run(r):
    r.wait_for('Settings', type='Button', timeout=60)
    r.tap('Settings', type='Button')
    r.wait_for('Done', type='Button', table='Shared')
    r.tap('Done', type='Button', table='Shared')
    r.expect('Done', type='Button', table='Shared', present=False)
    r.screenshot('returned-to-overview')
```

Available steps:

- `tap(label, ...)` or `tap(id='existingIdentifier')`: resolves exactly one target from the current AXe tree and always uses `--tap-style physical`.
- `type(text)`: sends literal text to the focused field. Follow it with an expectation of that field's value or a resulting search hit.
- `swipe(start=(200, 690), end=(200, 300))`: coordinates in screen points on the fixed iPhone 17. Follow it with an assertion of the newly revealed content.
- `wait_for(label, timeout=60, ...)` and `expect(label, present=True, timeout=40, ...)`: bounded accessibility polls. Both accept `id=`, `type=`, `contains=True` for a label substring and `value='substring'` for AXValue. `in_value=True` matches the translated label against AXValue instead (search placeholders have no AXLabel). For typed sample text, use `expect(text, literal=True, in_value=True, type='TextField')`. `ignore_case=True` handles headings drawn in capitals; `child_id='checkmark'` checks the selected category's marker, and `enabled=True` checks a control's availability. `present=False` checks absence.
- `screenshot('name')`: writes a PNG under this app's run folder.
- `relaunch(args)`: terminates this app and starts its sample world again with the given extra arguments; language is retained. App storage survives within this invocation; in-memory sample mutations may reset.

The PID returned by `simctl launch` identifies the foreground app even when AXe omits its application label. Zero-sized application frames fall back to the fixed iPhone 17 viewport, and empty accessibility responses are retried rather than treated as absent controls. Assertions require a stable result across accessibility snapshots for at least 0.6 seconds, so navigation frames can settle. A tap or swipe remains unverified until the next assertion observes a predicate that was false before the action and becomes true afterwards. A second tap, relaunch or scenario end with an unverified action fails. An already true assertion also fails; checking that a persistent tab exists does not prove navigation worked. Typing can happen after focusing a field, but its subsequent value/result assertion must prove the interaction. AXe's exit status alone never proves success.

## Labels and German

Write UI labels once as their English String Catalog keys. In German the runner reads that app's `Localizable.xcstrings`, `Shared/Shared.xcstrings` and, where present, its `AresiumShared` or `AresusShared` table. Missing German values fail explicitly. If a key has different translations in different tables, specify `table='Shared'` or `table='Localizable'`; the runner refuses to guess. `count=1` selects the catalog's English/German plural form and substitutes its `%lld` count; the quick-note waiting assertion uses this. No translations are maintained in the scenarios.

`literal=True` is reserved for verbatim invented sample content (shop names, listing titles, note text), app names and numeric output. Those strings deliberately have no localization keys and stay verbatim in either app language. Do not use it to bypass a missing translation of UI text. Substring selectors translate the English key first and then match the translated phrase within a combined accessibility label.

## Results and limits

All artifacts stay in git-ignored `build/smoke/`: `DerivedData/` and a dated, unique folder per invocation. Each app has its build command/log, ordered `steps.jsonl` and screenshots. Failures print the app and step, expected selector, visible labels, PNG path and raw AXe JSON path, and save `failure.json`. Exit status is nonzero. Success prints steps/duration for each app and a final summary. Durations include builds. `--self-test` runs the Empire journey in a child invocation, deliberately waits for a missing identifier, and succeeds only when the child exits nonzero with readable UI JSON, visible labels, a screenshot, the deliberate failure and completed simulator cleanup.

This checks sample navigation and a few visible mutations. It does not check login, real servers, push delivery, account tokens, device-only behavior, visual contrast or pixel correctness. Running in both appearances exposes layout/navigation failures but is not visual design approval. English server-sample sentences intentionally remain English in German. No app sources, identifiers, projects, schemes or test targets are changed. The fixed device, default text size and keyboard dismissal gestures are part of these local scenarios. AXe types physical keys: punctuation and Y/Z differ between English and German keyboards, so the invented input text uses keys shared by both layouts. Arbitrary keyboard layouts and glyph entry are not covered.

## Journeys

- **Aresium:** the phone sample renames Groceries to the invented “Smoke groceries” and creates “Smoke target” using existing launch arguments. From Overview, open a month and one fictional REWE payment, select the new category, save only that payment, verify the saved chip and the source total's decrease (within the overview's €1 rounding), then visit Settings and return. Dates and the exact payment amount are read from the sample UI, so month names and generated totals are not duplicated.
- **Empire:** rotate through Aresus to Aresync, verify both captions, tap Aresync for its province page, return, then visit Appearance and Language. Aresync has no external URL in the sample. Other provinces can launch another app or browser, including after a long press, so those open actions are avoided.
- **Arestemis:** search the invented listings, open a flat and favorite it, verify the changed star action, return to Hunts and open the tour from Settings. Advance each counter/title through step 7, open its Nintendo Switch 2 monitor, and check the actual price-history screen.
- **Aresus:** open all Drops and a sync report, then answer an invented “For you” question, check the option's removal and the committed answer under Answered, and open Settings. The five-second Undo offer is too short for multiple AXe assertions; the journey checks the committed sample answer instead.
- **Arestoteles:** use `-sampleOffline`, whose cached invented vault stays searchable while quick notes remain queued (the normal sample accepts them immediately). Find Printing press through Topics search, open the note, visit Library and Search, return to Positions, write/save a quick note, check its waiting count, and reopen the sheet to find its text under Not sent yet with Waiting to be sent.

Identifiers would make these selectors sturdier: Aresium's overview/month/payment rows and category choices; Empire's individual ring cards; Arestemis's search field, listing rows, tour card and monitor card; Aresus's drop/run rows, report close control and board answers; Arestoteles's search fields, topic rows and pending quick-note rows. Existing app and system identifiers are used where available (including the payment/category actions, settings gear, native back/search-tab controls and keyboard space key). No identifiers were added to the apps.
