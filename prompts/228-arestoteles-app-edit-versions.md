# 228: Arestoteles app: every edit says which version it was made on

Status: merged 2026-11-06 as Arestoteles build 3 (156 tests, 194 cases, on Claude's run); the server (brief 225) accepts versions since 2026-11-06.
Branch: `codex/228-edit-versions` · Worktree: `../empire-ios-228-edit-versions` · Model: `gpt-6.1-sol`, effort `high` ·
Simulator: `codex-228` (create it as `AGENTS.md` says)

## Goal

The Arestoteles server's edit-safety work (brief 225, branch `codex/225-edit-safety` in `~/Arestoteles`, worktree
`~/Arestoteles-225-edit-safety`, not deployed) refuses an edit that does not say which version of the note it was made
on (`428`), and a stale one (`409`), so an edit made on an old version can never overwrite newer text. The app must
ship first. After this brief every structured edit carries the version the person saw, and nothing typed is lost when
the server refuses.

## Read first

`AGENTS.md`, `CLAUDE.md` (the Arestoteles app section), `~/Arestoteles-225-edit-safety/docs/API.md` (the new contract;
read only), `~/Arestoteles-225-edit-safety/deploy/README.md` → "Edit-safety rollout (225)", the app's `VaultStore`,
edit API and quick-note queue, and their tests.

## Build

1. Position, confidence and status edits (and any other structured edit the new contract versions) send the
   **version shown when the draft was opened**, never the newest at send time.
2. A quick note about a position stores that note's version when it is written and sends it from the queue later.
   Plain quick notes stay as they are. Notes already in the queue without a version: keep them, and ask the owner
   before attaching them to the current position (one plain question, in the existing sheets' words and look).
3. A `409` or `428` keeps the draft on screen or in the queue, with the existing conflict message where there is one.
4. Update the app's server samples from the new contract's samples, and the sample mode's answers.

## Settled

- No new screens; wording follows the existing sheets; both languages (`scripts/strings.py check` 0 problems).
- Do not touch `~/Arestoteles`. No TestFlight upload (Claude). Readable code in the existing style.

## Done when

`xcodebuild test` passes on `codex-228`, with tests for each point above (stale draft refused and kept, version captured
at opening, queued note's version kept across a relaunch, old queued note asks).

## Final message

As in `AGENTS.md`: files changed, exact build and test lines, what Claude must check on the phone, anything doubtful.
