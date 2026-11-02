# 213: Aresium: the owner's email from the owner file

Status: running
Repo: `aresium` · Branch: `codex/213-owner-file` · Worktree: `../aresium-213-owner-file` · Model: `gpt-6.1-sol`, effort `high`

## Goal

This repo will go public. Today `src/web/links.ts` → `OWNER_EMAIL` holds the owner's email, typed in, and
`src/web/contact-page.test.ts` repeats it. After this brief the server reads it from the owner file outside the repo,
and the website shows exactly what it shows today.

## Read first

- `AGENTS.md`, `CLAUDE.md`, `src/web/links.ts`, every user of `OWNER_EMAIL`, `src/web/contact-page.test.ts`,
  `deploy/README.md`.

## The owner file (the same contract in ares-empire, ares and aresium)

- Path: `$ARES_OWNER_FILE` if set, else `~/.config/ares-empire/owner.json` (on the server, where `aresium.service`
  runs as root: `/root/.config/ares-empire/owner.json`, already in place).
- Content: a JSON object with exactly the keys `name`, `street`, `city` and `email`, each a non-empty string.
  Anything else is an error. Aresium only uses `email`, but validates the whole file.
- Missing or invalid: the web server fails at startup with a message that names the path and the problem, never the
  values.
- Tests use a made-up file through `ARES_OWNER_FILE` (`owner@example.org`, plus made-up name, street and city).

## Build

- Load the owner file once in the server and pass the email to whatever uses `OWNER_EMAIL` today. If any of it runs
  in the browser, the server provides the value to the page; nothing in the repo holds it.
- Tests: the contact page shows the made-up email; startup with a missing or invalid file fails.
- `deploy/README.md`: one line that the server needs the owner file.

## Settled: do not re-open

- One owner file per machine for all three sites; the live pages do not change.
- The real values never go into the repo, tests, docs, logs, or your final message. Do not print them.

## Rules

As in `AGENTS.md`: stay in the worktree, never commit or push, no installs.

## Done when

- `npm run typecheck` and `npm test` pass (give the result lines).
- `grep -rliF -f ~/.config/aresync/private-terms --exclude-dir=.git --exclude-dir=node_modules .` prints nothing.

## Final message

Files changed, the exact commands and results, the server steps Claude must run, anything doubtful.
