# 225: Arestoteles: can an edit get lost?

Status: running (started 2026-11-03)
Branch: `codex/225-edit-safety` (repo `Arestoteles`) · Worktree: `~/Arestoteles-225-edit-safety` · Model:
`gpt-6-astra`, effort `high`

## Goal

The Arestoteles iPhone app edits the owner's Weltbild vault through the server, which keeps its own git clone of the
vault (`carlsenares/opinions`), pulls every 60 seconds and pushes the app's edits. The owner also edits the same vault
in Obsidian on his computers, synced through GitHub. Find every path where an edit is lost, silently overwritten,
reported as saved when it was not, or leaves the vault broken; prove each with a test; fix the proven ones.

## Read first

`CLAUDE.md`, `README.md`, `docs/`, `deploy/README.md`, `src/arestoteles/` (the vault clone, sync, edits and their
API), the tests. For how the vault reaches the computers: `~/aresync` (read only). From the vault itself read only its
`CLAUDE.md` (`~/Documents/Patrik Breeck/Weltbild/CLAUDE.md`), never the notes.

## Look for

- Two edits to one note at once: the app and Obsidian, or the app twice; an edit made on an old version (is there a
  version check?); what a rebase or merge conflict does.
- A push that is refused or fails (GitHub down, network gone, rejected after someone else pushed): is the edit kept
  and retried, and does the app learn the truth?
- Writes that stop half way; renamed or moved notes; names with umlauts (macOS writes them decomposed, NFD);
  line endings; very large notes.
- The server's clone getting stuck (a rebase in progress, a lock file) and every later edit failing quietly.

## How

Tests with temporary git repositories (the repo's tests already do this; run them with `GIT_CONFIG_GLOBAL=/dev/null`).
Failing test first, then the smallest fix that keeps the rest identical. Changes to `~/aresync` are out of scope:
report them. Readable code in the existing style.

## Done when

The repo's tests pass, with new ones for every fix.

## Final message

Proven and fixed (what happened, the test, file and line); suspected but not proven; checked and sound; anything
Claude must do on the server.
