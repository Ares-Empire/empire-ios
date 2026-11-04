# AGENTS.md: for Codex and other coding agents

You are working on **empire-ios**, the native SwiftUI iPhone apps of the Ares Empire (first app: Aresium,
a personal finance dashboard). Claude plans the work, writes your brief and checks what you build.

## Read first

1. **`CLAUDE.md`**, **`README.md`** and **`docs/DEVELOPMENT.md`**: what this repo is and its rules. They apply to you in full. The
   section "Workflow" in `CLAUDE.md` is about how Claude runs you; you can skip it.
2. **Your brief** (`prompts/NN-*.md`). It says what to build, what to read, what "done" means, and which
   questions are settled. Do not re-open settled questions; if you think one is wrong, say so in your
   final message and build what the brief says.
3. Whatever the brief points to (an API route in the aresium repo, `ares-empire/docs/ACCOUNTS.md`, a screen
   sketch).

## Rules for you

- **The API is given, not invented.** Endpoints, fields and types come from the brief or the service code it
  names. If something you need is missing, stop at a `TODO(api)` and list it in your final message. Never
  guess a field name or add a workaround in the app.
- **Login and tokens:** the Empire token goes in the Keychain only (never `UserDefaults`, files or logs). Do
  not change the login flow unless the brief is about it.
- Stay inside the brief's scope and files. No third-party packages unless the brief allows them.
- **You run without a sandbox, so these are rules, not walls:** write only inside your worktree (build output
  in its `build/`); never commit, push, or touch git config (Claude commits); install nothing (no Homebrew,
  no runtimes, no global packages); no network except what the brief allows; never touch `~/empire-ios`
  itself, other repos, the Keychain of the Mac, or the Apple account settings in Xcode.
- **Waiting for a long command:** run it in the foreground with a long timeout, or wait on its process id
  (`wait $pid`, `while kill -0 $pid; do sleep 3; done`). Never `until ! pgrep -f "<text>"`: `pgrep -f` matches the
  waiting loop's own command line, so it never ends (2026-10-30: nine such loops were left running after a brief).
- Do not edit `*.xcodeproj/project.pbxproj` unless the brief says so. The project uses folder-synchronized
  groups: a new Swift file in the right folder is picked up without it.
- Keep logic (models, API client, decoding, formatting) out of the views and give it unit tests.
- Every screen works in light and dark (`CLAUDE.md` → Light mode): colours come from the shared pairs (`Ink`,
  `AppAccent`, `StatusTone`, the app's own style), never `.white`, `.black` or a fixed `Color(hex:)` for text or
  surfaces; never call `preferredColorScheme`.
- No secrets, API keys, passwords, personal data or real transaction data in files, fixtures or tests. Use
  made-up sample data. Server URLs are fine.
- Code, comments and docs in plain English. UI text is written in English in the code and translated to German in
  the String Catalogs: every app speaks both (`CLAUDE.md` → Languages; `String(localized:)` for text built as a
  `String`, the folder's table in `Shared/`, `AresiumShared/`, `AresusShared/`). Leave the German to Claude unless the
  brief asks for it, and say in your final message which strings you added.

## Building and running

From the worktree, with build output kept inside it:
```
xcodebuild build -scheme <App> -destination 'platform=iOS Simulator,name=codex-NN' -derivedDataPath build/DerivedData
xcodebuild test  -scheme <App> -destination 'platform=iOS Simulator,name=codex-NN' -derivedDataPath build/DerivedData
```
Use your own simulator, never a shared one:
`xcrun simctl create codex-NN "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-0` (NN = your brief's
number; the iOS 27.1 runtime only supports the foldable iPhone Duo), and `xcrun simctl delete codex-NN` at
the end. Fix your own compile errors and failing tests before you report.
To look at a screen: `xcrun simctl io codex-NN screenshot build/NN-<screen>.png`.
To use a screen while you build (tap, type, read what it shows), use AXe, which is installed: `axe describe-ui --udid
<udid>` lists every element with its label, `axe tap --label "<label>" --tap-style physical --udid <udid>` taps (always
`--tap-style physical`: the default does nothing in these apps), `axe type '<text>' --udid <udid>`, `axe --help` for
swipes and long presses. The udid: `xcrun simctl list devices | grep -m1 'codex-NN (' | grep -oE '[0-9A-F-]{36}'`.

## Your final message

Claude saves it and checks it against the code. Keep it short and factual:

1. What you built, file by file.
2. The exact build and test commands you ran and their summary lines (tests run, failures).
3. What you could not check, any `TODO(api)`, and any doubt about the brief.

Report only what you saw. If you did not run something, say so.
