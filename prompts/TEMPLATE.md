# NN: <short title>

Status: draft | running | merged | partly merged | dropped (one line, updated when it lands)
Branch: `codex/NN-slug` · Worktree: `../empire-ios-NN-slug` · Model: `gpt-6.1-sol`, effort `high`

## Goal

One or two sentences: what exists after this that does not exist now, and why it matters on the phone.

## Read first

- `AGENTS.md` and `CLAUDE.md` (always)
- <exact files: the API route in the service repo, the screen or type to extend>

## Build

- <deliverables, file by file where known; say which go in the local package and which in the app target>

## Settled: do not re-open

- <design choices made for this brief, with the reason in a few words>

## Out of scope

- <what not to touch>

## API

<Every endpoint and field the build uses, with the service file it comes from; or "none".
Anything missing: `TODO(api)`, never guessed.>

## Done when

- `swift test` passes in the package (command in `AGENTS.md`), with new tests for <behaviour>
- Claude: the app target builds and <screen> shows <data> on the simulator

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, what is unbuilt, missing or doubtful.
