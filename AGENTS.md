# AGENTS.md: for Codex and other coding agents

You are working on **empire-ios**, the native SwiftUI iPhone apps of the Ares Empire (first app: Aresium,
a personal finance dashboard). Claude plans the work, writes your brief and checks what you build.

## Read first

1. **`CLAUDE.md`** and **`README.md`**: what this repo is and its rules. They apply to you in full. The
   section "Workflow" in `CLAUDE.md` is about how Claude runs you; read only its sandbox paragraph.
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
- Do not edit `*.xcodeproj/project.pbxproj` unless the brief says so. The project uses folder-synchronized
  groups: a new Swift file in the right folder is picked up without it.
- Logic goes in the app's local package (e.g. `Aresium/AresiumKit/`) with tests; views stay thin.
- No secrets, API keys, passwords, personal data or real transaction data in files, fixtures or tests. Use
  made-up sample data. Server URLs are fine.
- You cannot commit (the sandbox protects `.git`). Leave the work in the worktree; Claude commits.
- Code, comments and docs in plain English. UI text in English, like the Aresium website, unless the brief
  says otherwise.

## Building in the sandbox

Your sandbox cannot write outside the worktree and cannot reach the simulator. Use these forms, from the
package folder (`build/` is gitignored):
```
export CLANG_MODULE_CACHE_PATH=$PWD/build/ModuleCache SWIFTPM_MODULECACHE_OVERRIDE=$PWD/build/ModuleCache
swift build --disable-sandbox --scratch-path build/spm --cache-path build/spm-cache \
  --config-path build/spm-config --security-path build/spm-security
swift test  --disable-sandbox --scratch-path build/spm --cache-path build/spm-cache \
  --config-path build/spm-config --security-path build/spm-security
```
`xcodebuild` and `xcrun simctl` do not work here; do not try to work around that. Claude builds the app
target and runs it on the simulator, and sends you any compile errors.

## Your final message

Claude saves it and checks it against the code. Keep it short and factual:

1. What you built, file by file.
2. The exact build and test commands you ran and their summary lines (tests run, failures).
3. What you could not check (app-target code is unbuilt from your side; say which files), any `TODO(api)`,
   and any doubt about the brief.

Report only what you saw. If you did not run something, say so.
