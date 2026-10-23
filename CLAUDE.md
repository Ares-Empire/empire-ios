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
3. **Run** in the background (Claude is notified when it ends). Use the full path; `codex` is a stale alias:
   ```
   /opt/homebrew/bin/codex exec -s workspace-write -m gpt-6.1-sol -c model_reasoning_effort=high \
     -C ../empire-ios-NN-slug -o codex-runs/NN-slug.md - < prompts/NN-slug.md
   ```
   Models: `gpt-6.1-sol` builds (`xhigh` for tricky ones), `gpt-6-astra` council seats (uses the allowance
   about 3× faster), `gpt-6-luna` trivial jobs. `-o` goes to `codex-runs/` (gitignored).
4. **Check** (below), commit in the worktree, merge to `main`, remove the worktree, set the brief's status line.

**What the sandbox allows (tested 2026-10-23 on this Mac):** Codex writes only inside the worktree, cannot
write `.git` (Claude commits), and has no network. `swift build` and `swift test` work once the caches point
into the worktree (commands in `AGENTS.md`). **`xcodebuild` and the simulator fail** (the sandbox blocks the
CoreSimulator services), so Codex cannot build the app target or run it. Hence the split:
- Logic (models, API client, decoding, formatting) lives in a local Swift package per app (e.g.
  `Aresium/AresiumKit/`, platforms iOS + macOS) that Codex builds and tests itself.
- The SwiftUI app target stays thin. Codex writes views blind; Claude builds with `xcodebuild` and sends any
  compile errors back with `codex exec resume <session id> "<errors>"` (run from the same worktree).
- No third-party packages unless a brief allows them (no network to fetch them anyway).

**Checks are light, but never skipped:**
- Build and run the tests yourself on the simulator. Never take Codex's "build succeeded" as evidence.
- Read the diff: quickly for layout, carefully for anything near login, tokens, the Keychain, or API calls.
- Run the app on the simulator and look at each screen the brief touched
  (`xcrun simctl io booted screenshot <file>`).

**Council** (`docs/REVIEW.md`): a few blind reviewers with distinct focuses, for hard-to-undo choices,
milestones, a bug that comes back, and every 2–3 weeks over merged Codex work.

**Allowance:** `/status` in an interactive `/opt/homebrew/bin/codex`, or the `rate_limits` line in the newest
`~/.codex/sessions/**/*.jsonl` (`used_percent`; window 10080 min = weekly).

**Not set up yet:** no iOS simulator runtime is installed (`xcodebuild -downloadPlatform iOS`, several GB),
and no Xcode project exists. When Claude creates it, use folder-synchronized groups (the Xcode default),
so new Swift files need no `project.pbxproj` edits, and add the app's local package as above.
