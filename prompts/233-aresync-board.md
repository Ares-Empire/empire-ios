# 233: Aresync: the `board` command, the repo scan and the session hooks

Status: merged 2026-11-06 (aresync 9f2c379 + 550dd75, 15 board tests; Claude: unusable repo names skipped, worktrees only through their repo, system certificates for python.org Python); installed on the MacBook and the server
Branch: `codex/233-board` · Worktree: `../aresync-233-board` (a worktree of **`~/aresync`**, not of empire-ios) ·
Model: `gpt-6.1-sol`, effort `high`

## Goal

The board (brief 232 builds its server half in Aresus, at the same time, against the same contract) keeps open work
and Patrik's decisions in one list. **Asks** (a decision or action only Patrik can take) reach his Aresus app; **work**
belongs to a topic and goes to the Claude session working on that topic, never to Patrik. This brief builds what
runs on the machines:

1. **`board`**, a command Claude sessions run in their shell: see their topic's open items, ask Patrik, leave work for
   a topic, find work to send to another session, mark items sent, done or dropped, take the next brief number.
2. **The scan**: every aresync run on the MacBook and the server reports the machine's repos' branches that are not
   merged and worktrees with uncommitted changes, so finished work that never shipped shows up by itself.
3. **Two hooks** for Claude Code: at session start, two lines of counts; on each prompt of a session that asked
   something, Patrik's answers once they arrive.

**How sessions are named** (already live, read it): `claude/name-me` and the README's "Session names". A session runs
`name-me aresium` and is called `mac-aresium` from its next prompt on; the hook records the applied name in
`~/.claude/session-names/<session id>.applied`. A session's **topic** is its name without the machine word (`mac-`,
`laptop-`, `server-`): `mac-aresium` → `aresium`. Claude Code gives every command `CLAUDE_CODE_SESSION_ID` (the local
id) and, while Remote Control is on, `CLAUDE_CODE_BRIDGE_SESSION_ID` (`session_01…`, the id the Claude app opens).

## Rules for you (this repo has no AGENTS.md)

- Write only inside your worktree. Never commit, push or touch git config (Claude commits). Install nothing. **No
  network**: tests use a local fake server on 127.0.0.1 (extend `tests/fake-aresus.py` or add one beside it).
- **Never touch the real `~/.claude`, `~/aresync/config` or any real repo**: tests use temp folders for the home,
  the Claude folder (`CLAUDE_CONFIG_DIR`) and the repos (`git init` in a temp folder).
- **Python must run on `/usr/bin/python3` (3.9.6)** and on newer ones: `from __future__ import annotations`, no
  `match`, standard library only. Shell stays bash 3.2 compatible, like the rest of the repo.
- Never put the machine token on a command line, in a log or in an error message.
- No real personal data in tests or fixtures.

## Read first

- **The contract, settled:** `~/aresus/docs/API.md` → "Board (version 1, 2026-11-06)" (read only). Build the machine
  side exactly to it, with `Authorization: Bearer <ARESUS_TOKEN>`. If it cannot work, leave `TODO(contract)` and say
  so in your final message.
- Why: `~/ares-empire/docs/reviews/2026-11-05-work-board.md`, "Patrik's decisions" and "The design that follows".
- This repo: `README.md` (Reports to Aresus, Drops, Session names), `aresync.sh` (how a run walks the repos, `log`,
  `send_report`, how `config` is read), `config.example`, `drop.py` (the pattern for a Python helper that reads the
  config and talks to Aresus with the token), `claude/name-me`, `tests/` (how tests run; `fake-aresus.py`).

## Build

1. **`claude/board`** (Python, executable, `#!/usr/bin/env python3`; it is linked as `~/.local/bin/board`, so find the
   repo through the real path of the file). Config from the aresync `config` beside the repo root (the same file
   `aresync.sh` reads; parse its `KEY="value"` lines, never run it): `ARESUS_TOKEN`, and the base URL from `BOARD_URL`,
   else `DROP_URL`, else `ARESUS_URL` with its `/sync/runs` cut off. Timeouts 10 s for commands, 3 s for hooks. Output
   is plain, short text for Claude to read; every item line starts with `#<id>` and its topic; item text is quoted as
   data (`text: "…"`), never printed as if it were the command's own words. Commands:
   - `board` — with a topic: that topic's open items (asks and work, oldest first), this session's answered asks (with
     the answer and "act on it, then `board done <id>`"), and one line counting other topics' open work not sent in
     24 h ("run `board route`"). Without a topic: the summary and "name the session first: `name-me <topic>`".
   - `board ask "<question>" --why "<why>" [--option <answer>]… [--due YYYY-MM-DD] [--topic <topic>]` — an ask
     (`source: session:<name>`, `session` = the bridge id when set). Prints its id. Records it in
     `<claude dir>/session-names/<session id>.asks` (JSON: the bridge id, and per ask its id and topic) for the prompt
     hook.
   - `board leave <topic> "<text>"` — work for a topic's session.
   - `board route` — open work of other topics not sent in 24 h (`not_topic`, `unsent=true`), oldest first, at most
     10, and the instruction: for each, if a running session's name ends with `-<topic>` (ListAgents), send it the item
     as a dated message and run `board sent <id> <session name>`; if none runs, leave it.
   - `board sent <id> <session name>`, `board done <id>`, `board drop <id>`.
   - `board brief <topic> "<title>"` — prints the number.
   - Errors: one plain line on stderr and exit 1 (no token set, server unreachable, the server's `{"error"}` sentence).
     Topic and name shapes as the contract's; `--topic` overrides the session's.
2. **The scan** (`board scan`, run by `aresync.sh`): every repo the run walks (the same list), and every worktree of
   each (`git worktree list --porcelain`). Findings as the contract's `ScanFinding`:
   - `branch`: each local branch other than the default one (`origin/HEAD`, else `main`, else `master`) with commits
     not in `origin/<default>` (`git rev-list --count`); `since` = its last commit's time; `detail` = "N commits not
     in <default>". A branch whose changes are already in the default branch (a squash or rebase merge) is not a
     finding: test with `git merge-tree --write-tree origin/<default> <branch>` giving the default branch's own tree;
     if that git has no `--write-tree`, keep the finding.
   - `dirty`: each checkout or worktree with uncommitted changes (`git status --porcelain -z`, untracked counted,
     ignored not, submodules' own dirt ignored); `ref` = its path relative to the home folder; `since` = the newest
     modification time among the changed paths that exist; `detail` = "N files changed".
   - The topic is the main repo's folder name, lowercased (a worktree `~/aresium-224-money-review` belongs to
     `aresium`). Names and counts only, never file contents. At most 500 findings (the oldest kept). It must finish in
     a few seconds for 20 repos; read-only git commands only (no fetch: the run already fetched).
   - In `aresync.sh`: after the repos, before the report, when `ARESUS_TOKEN` is set: run it with a time limit; a
     failure is one `WARN  board scan failed` line and never changes the run's result or exit code. Not on Windows
     (`windows/` stays as it is).
3. **The hooks** (`board hook-start`, `board hook-prompt`; both read Claude Code's JSON on stdin, both print nothing
   and exit 0 on any error or timeout):
   - `hook-start` (SessionStart): `GET /board/summary` → plain text, at most three lines: asks waiting on Patrik (and
     the oldest's age), open work per topic (the five with most), and "Name this session when its topic is clear
     (`name-me <topic>`), then run `board`."
   - `hook-prompt` (UserPromptSubmit): only when this session's `.asks` file exists (no network otherwise). Asks the
     server for those asks (by `session` when the bridge id is known, else by each ask's topic and id); for each newly
     answered one prints JSON `{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext":
     "…"}}` with "Patrik answered #12 (“<question>”): “<answer>”. Act on it, then run `board done 12`." Records what
     it delivered so it is said once. Removes the file when none of its asks is open or answered any more.
4. **README:** a section "Board" after "Session names": what it is (two sentences), the commands, the scan, and the
   install (link `~/.local/bin/board`, the two hooks' JSON for `~/.claude/settings.json`, merged with the name-me
   hooks: SessionStart with matcher `startup|resume` → `board hook-start`, UserPromptSubmit → `board hook-prompt`,
   timeout 5). Do not change `global-CLAUDE.md`; Claude adds the sessions' rule after review.
5. **Tests** (`tests/test_board.py`, run like the others; list the command in your final message): every command
   against the fake server, including errors and the token never appearing in output; the scan on temp repos (a
   branch ahead, a squash-merged branch, a worktree with changes, a clean repo, a repo without `origin/HEAD`); the
   hooks (silence without the `.asks` file, an answer delivered once, the file removed, silence on a dead server
   within the time limit); `aresync.sh` still passing its tests with the scan in it.

## Done means

All tests pass. In your final message: what you built, the test commands, anything not built as the contract says
(`TODO(contract)`), and what Claude must do to install it on the MacBook and the server.
