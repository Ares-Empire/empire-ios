# 244: Tap-through smoke tests for all five apps (AXe, sample data)

Status: running (Codex, started 2026-11-07)
Branch: `codex/244-smoke-ios` · Worktree: `../empire-ios-244-smoke-ios` · Model: `gpt-6.1-sol`, effort `high` (bounded
automation on a known tool; the care goes into waits and assertions that really prove a tap worked, not into hard
reasoning)

## Goal

One command taps through each app on a fresh simulator, over the apps' invented sample data, and fails loudly when a
screen does not appear or a tap does not change what it should. Today these checks are done by hand with AXe after each
build. After 2026-11-21 Claude builds alone; a scripted smoke run lets Claude check all five apps in light and dark,
English and German, after any change to `Shared/`, without remembering every path by hand.

## Read first

- `AGENTS.md`, `CLAUDE.md` (always; above all "Languages", "Light mode", and the Workflow's AXe line)
- `~/.claude/skills/ios-simulator/SKILL.md` (AXe: `describe-ui`, `tap --tap-style physical`, the first-call timeout)
- `axe --help` and `axe <command> --help`
- Each app's sample mode: the `-sampleData` launch argument and the other `-sample…` / `-open…` arguments in its
  sources (`grep -rhoE '"-sample[A-Za-z]+"' <App>/<App>`), `docs/DEVELOPMENT.md`
- Each app's `Localizable.xcstrings` (and the shared tables in `Shared/`, `AresiumShared/`, `AresusShared/`): the
  English keys and their German values

## Build

`scripts/smoke-ios/` (new; nothing else in the repo changes except a short "Smoke tests" paragraph in `README.md` and
one line in `CLAUDE.md`'s Workflow checks pointing at it):

1. **`run.py`** (Python 3 standard library only):
   `python3 scripts/smoke-ios/run.py [--all | <App> ...] [--language en|de] [--appearance light|dark] [--app-path <App>=<path.app>] [--keep]`
   - Builds each app's Debug simulator build into `build/smoke/DerivedData` unless `--app-path` gives one.
   - Creates its own simulator (`smoke-<random>`, "iPhone 17", iOS 27.0 runtime), sets the language (`-AppleLanguages`
     / `-AppleLocale` at launch) and appearance (`xcrun simctl ui <udid> appearance …`), installs, launches with
     `-sampleData` (plus what a scenario needs), and deletes the simulator at the end, also on failure or Ctrl-C.
     Never touches another simulator.
   - Steps: `tap(label | id)` (always `--tap-style physical`), `type(text)`, `swipe`, `wait_for(label | id,
     timeout)`, `expect(label | id present/absent, value contains …)`, `screenshot(name)`, `relaunch(args)`. Every
     wait is bounded and polls `axe describe-ui`; the first `describe-ui` after boot is retried (known timeout). A tap
     only counts when the next `wait_for`/`expect` sees the change it should cause: no step trusts AXe's "success".
   - Labels are written once, in English. For `--language de` the runner looks each label up in the String Catalogs
     (the German value of that English key), so one scenario serves both languages; a label with no German entry
     fails with a clear message rather than guessing. Prefer accessibility identifiers where the app has them; do not
     add identifiers to the apps (out of scope; list the places where one would make a scenario sturdier).
   - On failure: the step, what it waited for, the visible labels at that moment, and paths to a screenshot and the
     `describe-ui` JSON in `build/smoke/<run>/`. Exit non-zero. On success: one line per app (steps, duration) and a
     summary.
   - Output stays in `build/smoke/` (git-ignored). Sample data only, so screenshots hold nothing personal.
2. **One scenario per app** (`scenarios/<app>.py`), each with navigation across the main tabs or screens and one
   meaningful journey that changes state and checks the change on screen. Suggested, adjust to what the sample world
   allows (say what you chose and why):
   - **Aresium:** open a payment from the overview, change its category, see the new category on the payment and the
     sum move; open Settings and come back.
   - **Empire:** open a province from the ring, come back, open Settings → Appearance and Language screens.
   - **Arestemis:** run a search or open a hunt, open a listing's detail, open the tour and step through it to the
     price-history step.
   - **Aresus:** open a report, open Drops, open Settings.
   - **Arestoteles:** search for a sample note and open it; write a quick note and save it; see it listed as waiting
     (sample world), reopen the sheet and find it.
3. **A self-check:** `run.py --self-test` runs one scenario with a deliberately wrong expectation and passes only if
   that run fails with the failure report described above.
4. **`scripts/smoke-ios/README.md`**: how to run, how to write a step, how labels are translated, known limits (no
   login, no real server, no push, no device-only behaviour).

## Settled: do not re-open

- AXe, not XCUITest: no new test targets, no `project.pbxproj` or scheme edits, no app source changes.
- Sample data only (`-sampleData`); never a real account, server or token.
- Local only: GitHub's runners have no AXe, so no workflow for this (brief 242 owns the unit-test workflow).

## Out of scope

- App source, test targets, projects, workflows; briefs 242, 243 and 245 run in parallel on other files.

## API

None.

## Done when

- Both full runs pass on this Mac, each on a fresh simulator, and you show their summaries:
  `python3 scripts/smoke-ios/run.py --all --language en --appearance light` and
  `python3 scripts/smoke-ios/run.py --all --language de --appearance dark`.
- `python3 scripts/smoke-ios/run.py --self-test` passes (the wrong expectation is caught; show the failure report it
  printed).
- A second English run right after the first also passes (no leftovers between runs).
- No simulator named `smoke-…` is left (`xcrun simctl list devices | grep smoke-` shows none).

## Final message

As in `AGENTS.md`: files added, the journey chosen per app, the exact summary lines, where an accessibility identifier
would help, what is missing or doubtful.
