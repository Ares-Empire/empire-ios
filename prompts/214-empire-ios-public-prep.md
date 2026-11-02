# 214: empire-ios ready to be public: owner email, server name and Arestemis server briefs out

Status: running
Repo: `empire-ios` · Branch: `codex/214-public-prep` · Worktree: `../empire-ios-214-public-prep` · Model: `gpt-6.1-sol`, effort `high`

## Goal

This repo will go public; the Arestemis server repo stays private. After this brief no file here holds the owner's
email or the server's real host name, the briefs for the Arestemis server are no longer here (Claude moves them to
the Arestemis repo), and what remains says nothing about how Arestemis gets past sites' blocks.

## Read first

- `AGENTS.md`, `CLAUDE.md` → Workflow.
- Owner email: `docs/APP-STORE.md`, `docs/build-2026-10-24/briefs/E5-support-form.md`,
  `docs/build-2026-10-24/briefs/E6-privacy-legal.md`.
- Server host name: `Aresus/Aresus/Samples/overview.json`, `Aresus/AresusTests/AresusDecodingTests.swift`.

## Build

1. **Owner email:** in the three docs, replace it with a pointer: "the owner's email (the owner file, see ares-empire
   `docs/PRIVACY.md`)". Do the same for any postal address you find.
2. **Server host name:** in the Aresus sample and its test, use `server.example` instead. Claude makes the same change
   in the aresus repo's `docs/samples/overview.json`.
3. **Arestemis server briefs out:** delete every brief in `prompts/` that builds in the Arestemis repo: those whose
   `Worktree:` line points at `../Arestemis-…` (25 today, from `62-arestemis-application-notes.md` to
   `136-arestemis-browser-reader.md`), plus any other brief whose work is in the Arestemis repo (decide
   `138-arestemis-model-test.md` by its content). Do not delete briefs for the Arestemis iPhone app
   (`../empire-ios-…` worktrees). Claude copies the deleted ones to the Arestemis repo, `docs/briefs/`, under the same
   names. Repoint every reference (`CLAUDE.md`, `docs/`, other briefs, status files) to "the Arestemis repo,
   `docs/briefs/<name>`". In `CLAUDE.md` → Workflow add one line: briefs for the Arestemis server live in the Arestemis
   repo's `docs/briefs/` (that repo stays private), numbered in the same series as `prompts/`.
   List every deleted file in your final message.
4. **Site access details:** in what remains (app briefs, reviews, docs), cut descriptions of how the Arestemis server
   gets past sites' blocks to a plain statement: no per-site findings and no techniques. Search the repo for anything
   else on sites' blocks.
   App code that shows that a site blocked a search stays as it is.

## Settled: do not re-open

- Arestemis server briefs move as a group (by where they build), not picked one by one by how sensitive they look.
- The real owner values and the real host name never go into the repo, tests, docs, logs, or your final message.

## Out of scope

The Xcode project and all app code apart from the Aresus sample and its test. No restyling.

## Rules

As in `AGENTS.md`: stay in the worktree, never commit or push, no installs.

## Done when

- `xcodebuild test -scheme Aresus` passes on your own simulator (commands in `AGENTS.md`; give the summary line).
- `grep -rliF -f ~/.config/aresync/private-terms --exclude-dir=.git --exclude-dir=build .` prints nothing.
- No reference to a deleted brief points into `prompts/` any more.

## Final message

Files changed and deleted, the exact test commands and result lines, anything doubtful.
