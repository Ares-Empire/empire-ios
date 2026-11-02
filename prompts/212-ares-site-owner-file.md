# 212: patrikbreeck.com: owner details from the owner file

Status: running
Repo: `ares` · Branch: `codex/212-owner-file` · Worktree: `../ares-212-owner-file` · Model: `gpt-6.1-sol`, effort `high`

## Goal

This repo will go public. Today `content/site.json` → `owner` holds the owner's name, postal address and email, and
`build.py` fills the legal pages from it. After this brief `build.py` reads them from the owner file outside the repo,
`site.json` has no `owner` block, and the built site is exactly the same as today.

## Read first

- `CLAUDE.md`, `README.md`, `build.py` (the `owner.*` placeholders), `deploy.sh` (runs on the server as root).

## The owner file (the same contract in ares-empire, ares and aresium)

- Path: `$ARES_OWNER_FILE` if set, else `~/.config/ares-empire/owner.json` (on the server
  `/root/.config/ares-empire/owner.json`, already in place; on the Mac it exists too).
- Content: a JSON object with exactly the keys `name`, `street`, `city` (postcode and town in one line) and `email`,
  each a non-empty string. Anything else is an error.
- Missing or invalid: `build.py` stops with a `BuildError` that names the path and the problem, never the values.
- Tests and checks use a made-up file through `ARES_OWNER_FILE` (`Erika Musterfrau`, `Musterstraße 1`,
  `12345 Musterstadt`, `owner@example.org`).

## Build

- `build.py`: the `owner.*` placeholders come from the owner file; remove `owner` from `content/site.json`.
- `CLAUDE.md` and `README.md`: where they say the owner details live in `site.json` (and in the Ares Empire pages),
  say they live in the owner file, shared with ares-empire and aresium, and are never in a repo.
- If the repo has tests or checks for the build, extend them for the owner file (made-up file fills the pages; a
  missing file stops the build). If it has none, add a small check script only if it fits the repo's style.

## Settled: do not re-open

- One owner file per machine for all three sites; the built pages do not change.
- The real values never go into the repo, tests, docs, logs, or your final message. Do not print them.

## Rules

Stay in the worktree. Never commit or push, no installs (`npm ci` inside `vendor/companions/web` is allowed if the
build needs it).

## Done when

- `ARES_OWNER_FILE=<made-up file> python3 build.py` builds; the built imprint and privacy pages contain the made-up
  values and no `{{` placeholder is left anywhere in `dist/`.
- Without the file (`ARES_OWNER_FILE=/nonexistent`) the build stops with the clear error.
- `grep -rliF -f ~/.config/aresync/private-terms --exclude-dir=.git --exclude-dir=dist --exclude-dir=node_modules .`
  prints nothing.

## Final message

Files changed, the exact commands and results, anything doubtful.
