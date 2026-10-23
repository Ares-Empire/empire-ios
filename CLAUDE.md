# empire-ios — notes for Claude Code

Read `README.md` first, then the decision record in the ares-empire repo
(`docs/IPHONE-APPS.md`) and the login plan (`docs/ACCOUNTS.md`).

- Native SwiftUI only — no web views wrapping the websites.
- Each app uses its service's existing JSON API; if the API lacks something, change the
  service (its own repo), don't work around it in the app.
- Log in via the Empire account system, never a service's own password.
- Design language: the Ares Empire "crown language" in `ares-empire/EMPIRE.md`
  (near-black, polished gold accent, Space Grotesk / JetBrains Mono).
- Append a line to the Chronicle in `ares-empire/EMPIRE.md` after meaningful work.
- A good structure is worth more work now: if the app would need a copy of a service's logic or a
  workaround, fixing the service is usually the better call (`~/ares-empire/EMPIRE.md` → "How we build apps").

## Workflow (Codex month, until about 2026-11-20)

ChatGPT Pro runs until about 2026-11-20. Until then Claude delegates bounded builds to Codex.
After that, Claude builds alone: drop this section. Same setup as nametbd3 (`docs/WORKFLOW.md` there),
adapted for Xcode on the MacBook. Codex's own rules: `AGENTS.md`.

| Who | Does | Does not |
|---|---|---|
| **Patrik** | Decisions, Apple account and App Store Connect, tries TestFlight builds on the phone | Relay prompts between tools |
| **Claude** | Plans, sets up the Xcode project, anything touching login or tokens, writes briefs, runs Codex, builds and runs the app on the simulator, commits, merges, TestFlight uploads | Bulk typing Codex can do from a clear brief |
| **Codex** (run by Claude) | Bounded builds from a brief: screens, models, the API client, widget code, unit tests; second opinions and council seats | Decide the API contract or the login flow; edit `project.pbxproj` unless the brief says so; merge |

**Delegate** when the task fits a brief with a clear "done" (it compiles, these tests pass, this screen
shows this data) and the build is clearly bigger than the brief. Otherwise Claude does it.

### Running Codex

1. **Brief:** copy `prompts/TEMPLATE.md` to `prompts/NN-slug.md`. Settle the design choices in it; link to
   rules instead of restating them. Commit it to `main` before branching.
2. **Worktree:** `git worktree add -b codex/NN-slug ../empire-ios-NN-slug main`. Never let Codex (or
   uncommitted work) sit in `~/empire-ios` itself: aresync auto-commits and pushes that checkout.
3. **Run** in the background (Claude is notified when it ends):
   ```
   codex exec --dangerously-bypass-approvals-and-sandbox -m gpt-6.1-sol -c model_reasoning_effort=high \
     -C ../empire-ios-NN-slug -o codex-runs/NN-slug.md - < prompts/NN-slug.md
   ```
   Models: `gpt-6.1-sol` builds (`xhigh` for tricky ones), `gpt-6-astra` council seats (uses the allowance
   about 3× faster), `gpt-6-luna` trivial jobs. `-o` goes to `codex-runs/` (gitignored).
4. **Check** (below), commit in the worktree, merge to `main`, remove the worktree, set the brief's status line.

**Why no sandbox:** Codex's `workspace-write` sandbox blocks `xcodebuild` and the simulator (tested
2026-10-23), so builds run without it (Patrik's call, 2026-10-23). Codex can then build, run the simulator and
fix its own compile errors. The limits the sandbox used to enforce are now rules in `AGENTS.md`: stay in the
worktree, never commit or push, no installs. Council seats and reviews still run with `-s read-only`.

**Checks are light, but never skipped:**
- Build and run the tests yourself on the simulator. Never take Codex's "build succeeded" as evidence.
- Read the diff: quickly for layout, carefully for anything near login, tokens, the Keychain, or API calls.
- Run the app on the simulator and look at each screen the brief touched
  (`xcrun simctl io booted screenshot <file>`).

**Council** (`docs/REVIEW.md`): a few blind reviewers with distinct focuses, for hard-to-undo choices,
milestones, a bug that comes back, and every 2–3 weeks over merged Codex work.

**Allowance:** `/status` in an interactive `codex`, or the `rate_limits` line in the newest
`~/.codex/sessions/**/*.jsonl` (`used_percent`; window 10080 min = weekly).

## Setup state (update as it changes)

- MacBook: Xcode 27.1 with two simulator runtimes (2026-10-23): **iOS 27.0** for all normal iPhones (use this)
  and iOS 27.1, which only supports the foldable "iPhone Duo" (its screenshots came out black). The simulator
  window app is called **DeviceHub** in Xcode 27; `xcrun simctl` works without it.
- Apple Developer Program (paid, for TestFlight; decided in `ares-empire/docs/IPHONE-APPS.md`): Patrik applying
  2026-10-23. Xcode is signed in (2026-10-23), so far with only the free "Personal Team"; the paid team
  appears under the same account once Apple approves. Until then: simulator only, no TestFlight (a free
  Apple ID could install on the phone, but those builds stop opening after 7 days, so we don't use it).
- No Xcode project yet. When Claude creates it: folder-synchronized groups (the Xcode default), so new Swift
  files need no `project.pbxproj` edits; signing team = the paid team once approved.
