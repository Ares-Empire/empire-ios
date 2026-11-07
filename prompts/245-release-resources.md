# 245: Release builds without development fixtures, checked by an audit

Status: draft
Branch: `codex/245-release-resources` · Worktree: `../empire-ios-245-release-resources` · Model: `gpt-6.1-sol`, effort
`high` (mostly build configuration, but each resource's use must be traced through Release code paths so no shipping
tour or screen loses a file it needs; a miss would only show on Patrik's phone)

## Goal

What reaches TestFlight holds only what the app uses in Release. Today the folder-synchronized groups copy every file in
`Preview Content/` and `Samples/` into every build, so Release apps carry DEBUG-only sample data (invented, but dead
weight and confusing in a public app). Some of those files are used in Release, though: Arestemis's tour reads
`Samples/prices-9.json`. After this brief, Release leaves out what only DEBUG uses, keeps what Release uses, and a
script checks a built app against an explicit list, so a later change cannot quietly ship a fixture or drop a needed
file.

## Read first

- `AGENTS.md`, `CLAUDE.md` (always)
- The five `project.pbxproj` files (folder-synchronized groups, `PBXFileSystemSynchronizedBuildFileExceptionSet`,
  the Debug/Release build settings)
- Every loader of a resource in `Preview Content/` or `Samples/` (`Bundle.main.url(forResource:`, `path(forResource:`,
  `NSDataAsset`, …) and whether it sits behind `#if DEBUG`: e.g. `Arestoteles/Arestoteles/Model/ArestotelesSamples.swift`,
  `Arestemis/Arestemis/Model/TourData.swift` (≈ line 248, `prices-9.json` in the shipping tour), Aresium's
  `Preview Content/PhoneSample/` (`-samplePhone`), Empire's `Preview Content/`, Aresus's `Samples/`
- `prompts/22-aresium-without-account.md`: check whether any sample or demo mode is reachable in Release (a tour, a
  "try it without an account" path) before calling a file DEBUG-only
- `scripts/testflight.sh` (how TestFlight builds are made: an archive)

## Build

1. **Classify every file** in those folders per app: *Release uses it* (keep), *only DEBUG uses it* (leave out of
   Release), or *nothing uses it* (list it; do not delete it, Claude decides). Put the result in the allowlist
   (point 3) with a one-line reason per file or folder.
2. **Leave DEBUG-only files out of Release**, with the smallest clear build-configuration change (e.g. a Release-only
   `EXCLUDED_SOURCE_FILE_NAMES`, or moving Release-needed files out of a DEBUG-only folder). Debug builds keep
   everything, so sample mode, previews and screenshots work as before. If moving a file is cleaner (e.g.
   `prices-9.json` into a folder for shipping resources), move it and update its loader, nothing else.
3. **`scripts/check-release-resources.py`** (Python 3 standard library) and **`scripts/release-resources.json`**:
   `python3 scripts/check-release-resources.py --app <App> --bundle <path/to/App.app>`. It fails (non-zero, with the
   file names) when a forbidden file is in the bundle (any file under the excluded patterns, also inside an appex)
   or a required runtime resource is missing (the kept samples, the engine bundle, shop list, local places database,
   fonts, String Catalog outputs: whatever Release loads; derive the list from the loaders, do not guess). It prints
   one line per app on success.
4. **Docs:** a short paragraph in `docs/DEVELOPMENT.md` (what Release leaves out, how to run the audit, how to add a new
   sample file), and one line in `CLAUDE.md`'s TestFlight/Workflow notes so the audit runs before an upload.

## Settled: do not re-open

- No behaviour change in Release or Debug; Release tours keep working, including Arestemis's price-history step.
- Unused files are listed, not deleted.
- `project.pbxproj` edits are allowed in this brief, limited to the resource exclusions; no other build setting changes.

## Out of scope

- `scripts/testflight.sh` itself, signing, App Store Connect; the unit-test script and workflow (brief 242); smoke
  scripts (brief 244); Arestoteles's quick-note queue (brief 243). Other sessions may change Aresium sources while you
  work: touch only the files this brief names.

## API

None.

## Done when

For each app (Aresium, Empire, Arestemis, Aresus, Arestoteles):
- An unsigned archive builds, as TestFlight's does, and passes the audit:
  `xcodebuild archive -project "$app/$app.xcodeproj" -scheme "$app" -configuration Release -destination 'generic/platform=iOS' -archivePath "build/release/$app.xcarchive" CODE_SIGNING_ALLOWED=NO`
  then `python3 scripts/check-release-resources.py --app "$app" --bundle "build/release/$app.xcarchive/Products/Applications/$app.app"`.
- A Release simulator build passes the same audit (`-sdk iphonesimulator -configuration Release
  -derivedDataPath build/release-sim/$app CODE_SIGNING_ALLOWED=NO`).
- The Debug unit tests still pass on your own simulator `codex-245` (`AGENTS.md`), `-only-testing:<App>Tests`; show
  each summary line.
- On `codex-245`: the Release Arestemis build's tour reaches the price-history step and shows its chart (AXe,
  `--tap-style physical`; screenshot `build/245-arestemis-tour-prices.png`), and each other app's Release build starts
  to its first screen without a missing-resource error. The Debug build still opens sample mode (`-sampleData`) in each
  app.
- In temp copies of a bundle: adding a forbidden file makes the audit fail, removing a required one makes it fail; show
  both outputs.
- `xcrun simctl delete codex-245` at the end.

## Final message

As in `AGENTS.md`: the classification per app (kept / left out / unused), files changed, the exact build, audit and
test summary lines, what is missing or doubtful.
