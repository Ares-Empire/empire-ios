# Rules for every build agent (2026-10-25)

You are one of several Claude build agents. Claude (the lead) wrote your brief, reviews your work, merges it and
deploys it. Patrik (the owner) is away; do not ask him anything.

## Where you work

- **Only in your worktree(s)** (paths in your brief). Never edit the main checkouts (`~/ares-empire`, `~/empire-ios`,
  `~/Arestemis`, `~/aresus`, `~/aresync`, …): the Aresync LaunchAgent auto-commits and pushes those.
- **Commit** on your branch in your worktree as you reach working steps (small commits, plain English messages, end
  each message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`). **Never push, merge, rebase onto
  main, or change git config.**
- **No SSH to the server, no changes to live services, DNS, Caddy, PocketBase.** Deploying is the lead's job; you
  write the deploy files and the exact steps.
- Install nothing globally (no Homebrew, no global pip). A virtualenv **inside your worktree** (`python3 -m venv .venv`,
  git-ignored) with the packages your brief names is fine. Local Python is 3.14 (python.org build); the server runs
  Python 3.13, so write code for `>=3.11`.
- iOS builds: your own simulator (`xcrun simctl clone` of the "iPhone 17" iOS 27.0 device, named in your brief), your own
  `-derivedDataPath` inside the worktree. Never use the booted "iPhone 17" itself.

## Secrets and personal data

- No secrets, tokens, passwords, API keys or personal data in any file, test, fixture, log or commit. Made-up sample
  data only. Server URLs are fine.
- Where your brief allows a live test, read credentials from the macOS Keychain at run time
  (`security find-generic-password -s <item> -w`) into an environment variable of that one command; never print them.
- Never log an Empire token, an APNs device token or a bot token in full.

## How to build

- Read the documents your brief lists **before** writing code. The API contracts are given: do not rename fields or
  invent endpoints. If the contract is clearly missing something you need, add the smallest addition, mark it
  `CONTRACT ADDITION` in the docs, and list it in your final message.
- Good structure over quick hacks (Patrik's rule: `~/ares-empire/EMPIRE.md` → "How we build apps"). Keep logic out of
  views and handlers, in small modules with unit tests. Match the surrounding code's style and comment density.
- Plain English in code, comments and docs. Keep docs short and current (update the repo's README/CLAUDE.md where
  your change makes them wrong).
- Run your tests yourself and fix failures before finishing. Do not claim something works that you did not run.

## Final message (your last reply, for the lead)

1. What you built (files, short).
2. The exact test command(s) and their summary lines (pass/fail counts).
3. Anything not done, doubtful, or deviating from the brief/contract, and why.
4. Exact deploy steps for the lead (server work), if your brief has server parts.
5. The branch name and last commit hash.
