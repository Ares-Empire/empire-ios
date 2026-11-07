# 242: iPhone unit tests reliable enough for CI, one command, and a GitHub workflow

Status: draft
Branch: `codex/242-unit-ci` · Worktree: `../empire-ios-242-unit-ci` · Model: `gpt-6-astra`, effort `high` (the core is
diagnosing tests that fail only under load and telling a slow machine from a real ordering bug; that is the hardest
diagnostic work in this series and worth Astra's higher allowance use; the script and workflow are routine)

## Goal

Every push to empire-ios (public) runs the five apps' unit tests on GitHub's macOS runners, and a red result means a
real bug, not a busy machine. Today some Aresium tests fail when the full suite runs under load and pass alone, and a
few tests assert machine speed. After this brief: those tests wait for what they check instead of a clock, speed
measurements are kept out of the correctness run (still runnable locally), one script runs the unit tests the same way
on this Mac and on GitHub, and a workflow runs it. This matters most after 2026-11-21, when Claude builds alone.

## Read first

- `AGENTS.md`, `CLAUDE.md`, `README.md`, `docs/DEVELOPMENT.md` (always)
- `Aresium/AresiumTests/AresiumTests.swift` around the import tests (the 5-second polling deadline after
  `waitForRequest`, `failedImportBannerPersistsUntilDismissed` with its 4.7-second sleep), `NameSearchTests.swift`
  (`indexedSearchOfFiveThousandPaymentsStaysFast`), and the Aresium import code those tests drive (`ImportStore`, the
  banner and its auto-dismiss timing)
- The record of earlier load failures: `prompts/208-aresium-fixed-costs-data.md` (top) and
  `codex-runs/217b-fixed-costs.md` if present
- GitHub's image `xcode-27` (preview): macOS 27.0.1, Xcode 27.1 default (build 27A9275, the same as this Mac), iOS 27.0
  simulator runtime with "iPhone 17". Readme:
  `gh api repos/actions/runner-images/contents/images/macos/xcode-27-arm64-Readme.md --jq .content | base64 -d`

## Known flaky tests (all fail in a full run on a fresh simulator, all pass alone)

Reported by the Aresium session on 2026-11-07, each with `imports.banner == nil`:
- `FileDropTests/aDropImportsLikeASharedFile`
- `ImportThenCategoriesTests/thePickerOpensAfterAnImportThatAddedPayments`
- `ImportThenCategoriesTests/theResultLineIsCountedAgainWhenThePickerCloses`
- `MessageScreensTests/theOfferComesAfterTheCategoryPickerAndTheResultOnce`

Find the real cause before changing anything (for example a success banner that dismisses itself after a few seconds
of wall-clock time, so a slow run checks it after it is gone; or a result published after `importPendingFiles()`
returns). Say in your final message what the cause was and how you showed it (e.g. reproduced under load, or with a
slowed clock).

## Build

1. **Reliable tests, all five apps.** Fix the flaky tests above and the two Aresium waits named in "Read first". A
   test waits for the event it checks (an awaited completion, a published state, an injected clock), never for wall
   time; where the app's own behaviour depends on time (a banner's auto-dismiss), make that time injectable or
   observable in a narrow way and keep the behaviour unchanged. Then search all five apps' unit tests for other
   wall-clock waits and speed assertions (`Task.sleep` before an `#expect`, polling deadlines, `ContinuousClock`
   budgets, "stays fast" tests, e.g. `PickerTimingTests`, `LocalPlacesMeasurementTests`, `PackedLocalPlacesTests`,
   Arestoteles `VaultTimingTests`) and list each with what you did.
2. **Speed checks stay, but apart.** A test whose point is a time budget (NameSearch keystrokes, picker timing,
   local-places measurement) keeps its budget unchanged. It is left out of the correctness run and runs with
   `--timing` (below). Never loosen a budget or an assertion to get green.
3. **`scripts/test-unit.sh`**:
   - `bash scripts/test-unit.sh [--all | <App> ...] [--timing] [--keep-simulator]`. `--all` = Aresium, Empire,
     Arestemis, Aresus, Arestoteles.
   - Creates its own simulator (`test-unit-<random>`, "iPhone 17", the iOS 27.0 runtime; on the runner, whatever
     iOS 27.0 iPhone 17 runtime it has) and deletes it at the end, also on failure or Ctrl-C (`trap`). Never uses a
     shared or booted simulator.
   - Per app: `xcodebuild test -project "$app/$app.xcodeproj" -scheme "$app" -configuration Debug -destination
     "platform=iOS Simulator,id=$udid" -derivedDataPath "build/test-unit/$app" -resultBundlePath
     "build/test-unit/$app.xcresult" -parallel-testing-enabled NO -only-testing:"${app}Tests"`, plus the signing
     settings that work on a machine without Patrik's Apple account (find out which; e.g. `CODE_SIGNING_ALLOWED=NO`
     or ad-hoc `CODE_SIGN_IDENTITY=-`; Keychain and App Group tests must still pass, so check them). UI tests
     (`AresusUITests`), `scripts/check-shared-login.sh` and other opt-in probes are not part of it.
   - Without `--timing` the speed tests are skipped (an explicit `-skip-testing` list kept in the script, or a
     Swift Testing tag if `xcodebuild` can filter on it without project or scheme edits); the script prints which
     tests it skipped and why. With `--timing` it runs only those.
   - Prints one line per app (tests run, failures, duration) and a final summary; exits non-zero if any app fails.
     On failure it prints the failing test names (from the result bundle, `xcrun xcresulttool`), nothing else.
4. **`.github/workflows/ci.yml`** ("iPhone unit tests"):
   - `runs-on: xcode-27`; `sudo xcode-select -s /Applications/Xcode_27.1.app` (pinned, matching this Mac); print
     `xcodebuild -version` and the runtimes.
   - One job per app (matrix, `fail-fast: false`) running `bash scripts/test-unit.sh <App>`, `timeout-minutes` per job.
   - Triggers: `push` (all branches), `pull_request`, `workflow_dispatch`. `concurrency` keyed on workflow and ref with
     `cancel-in-progress: true`. Top-level `permissions: contents: read`.
   - Actions pinned by full commit SHA with the tag in a comment (look them up with
     `gh api repos/actions/checkout/git/ref/tags/<tag>`; never invent one). No secrets of any kind, no signing
     material, no App Store Connect, no artifact uploads (result bundles can contain screenshots).
   - Also runs `python3 scripts/strings.py check` once (a small ubuntu job is fine).
5. **Docs:** a short "Tests" section in `README.md` (what CI runs, `scripts/test-unit.sh` usage, `--timing`, what stays
   manual: shared-login probe, AXe checks, device-only things), and update the build/test lines in `AGENTS.md` and
   `docs/DEVELOPMENT.md` to point at the script.

## Settled: do not re-open

- No change to app behaviour. A narrow, test-only seam (an injected clock or a completion to await) is allowed where a
  test needs it; say each one in your final message.
- Never loosen an assertion or a time budget; never retry a failed test into success; no `withKnownIssue` for these.
- No `project.pbxproj` or scheme edits. No third-party actions besides `actions/checkout`.
- empire-ios is public, so its macOS runner minutes are free; private repos are not involved.

## Out of scope

- The Release resources (brief 245), smoke scripts (brief 244), the Arestoteles quick-note queue (brief 243, running in
  parallel: do not touch `Arestoteles/Arestoteles/Model/VaultStore.swift` or the Arestoteles queue tests).
- Aresium's file import types and engine (another session's brief 240, just merged).

## API

None.

## Done when

- `python3 scripts/strings.py check` reports zero problems.
- `bash scripts/test-unit.sh --all` passes on this Mac; show its summary. Then **three consecutive full Aresium runs**
  (`bash scripts/test-unit.sh Aresium`) pass, at least one of them while another build or test run keeps the Mac busy
  (e.g. Empire's tests at the same time on another simulator); show the three summary lines.
- `bash scripts/test-unit.sh --timing Aresium` runs the speed tests and shows their result (on this Mac they should
  pass; report honestly if one does not).
- A deliberately wrong assertion (made in a temp copy or reverted at once, never left in) makes the script exit
  non-zero and name the test; show that output.
- The workflow file loads with `ruby -ryaml -e 'YAML.load_file(ARGV[0])'`, and you have read it once more against
  point 4. Only a real GitHub run can prove the runner part: Claude pushes the branch and checks it.
- Every simulator you created is deleted (`xcrun simctl list devices | grep test-unit-` shows none).

## Final message

As in `AGENTS.md`: files changed, the cause of each flaky test, every test-only seam added, the skipped speed tests, the
exact summary lines, what is missing or doubtful.
