# 257: Board answers wake the asking session

Status: running
Repo: `aresync` (private) · Branch: `codex/257-board-watch` · Worktree: `~/aresync-257-board-watch` · Model:
`gpt-6.1-sol`, effort `high` (careful plumbing in one script with tests, design settled below; no open reasoning that
needs Astra's 3× allowance)

## Goal

When Patrik answers a board ask in the Aresus app ("For you" tab), the Claude session that asked learns it within
seconds, even when it is idle, with the same line it gets today: `Patrik answered #N (text: …): answer: …. Act on it,
then run `board done N`.` Today the answer only arrives through the UserPromptSubmit hook (`board hook-prompt`), so an
idle session misses it until someone types (board #86, Patrik 2026-11-07). The prompt hook stays as the backup.
Sessions run on the MacBook, the server (Linux) and the Windows laptop (Git Bash, native Windows Python 3.13).

## How the wake works (settled, checked on Claude Code 2.1.316–2.1.319)

Claude Code runs a command hook with `"asyncRewake": true` in the background; when that process exits with code 2,
Claude Code wakes the session at once, even when idle, and shows it the hook's stderr (stdout if stderr is empty) after
the prefix `rewakeMessage` ("Board:"); the terminal shows `rewakeSummary`. Claude Code enforces the hook's `timeout`
on such a hook, so it gets a long one (10 days). Docs: https://code.claude.com/docs/en/hooks.md → "Run hooks in the
background", "Limitations". The hooks Patrik's machines will get (Claude installs them, not you):

```json
"Stop": [
  {"hooks": [{"type": "command", "command": "\"$HOME/.local/bin/board\" hook-watch", "asyncRewake": true,
              "timeout": 864000, "rewakeMessage": "Board:", "rewakeSummary": "Patrik answered a board ask"}]}
],
"SessionStart": [ … existing entries …,
  {"matcher": "resume",
   "hooks": [{"type": "command", "command": "\"$HOME/.local/bin/board\" hook-watch", "asyncRewake": true,
              "timeout": 864000, "rewakeMessage": "Board:", "rewakeSummary": "Patrik answered a board ask"}]}
]
```

Stop fires every time the session finishes a turn, so a watcher starts whenever the session goes idle; at most one
runs per session (the lock below). The hook gets the usual hook JSON on stdin (`session_id`) and these environment
variables: `CLAUDE_PID` (the session's own Claude Code process, the hook's parent) and `CLAUDE_CODE_ENTRYPOINT`
(`cli` interactive, `sdk-cli` for `claude -p`, `sdk-ts`/`sdk-py` for the SDK). In `claude -p` runs Claude Code may run
an asyncRewake hook in the foreground and wait for it, so the watcher must never wait there.

The server side is live: `GET /board/items?ids=1,2,3&state=any` returns exactly those items (at most 50 ids, combined
with the other filters by AND) and, unlike a `topic` query, marks no topic as read (aresus d22864c;
`~/aresus/docs/API.md` → Board → Routes).

## Read first

- `README.md` → "Board" (commands, install steps, hooks, the tracking file) and "Session names"
- `claude/board`: `Session` (the `.asks` tracking file, `load_asks`/`save_asks`), `hook_prompt`, `run` (the `ask`
  branch), `main` (hook detection, SIGALRM, the fast path when no `.asks` file exists, silent errors in hooks)
- `tests/test_board.py`, `tests/fake-board.py` (the fake HTTP server), `tests/run_local.py`

## Build

1. **One function that checks a session's own asks**, used by both `hook-prompt` and the new `hook-watch`:
   - Read the tracking file; nothing tracked → no request.
   - One request per 50 tracked ids: `GET board/items?state=any&ids=<ids>`. No more `session=`/`topic=` queries in
     the hooks (`answered_items` for the plain `board` listing stays as it is).
   - Then, under the state lock, read the file again and update only the asks the request covered: an answered ask
     not yet `delivered` gives the message (exact wording of today's `hook_prompt`) and is marked `delivered`; an ask
     that is done, dropped, or missing from the answer (deleted by the server's 90-day housekeeping) is removed; an
     ask added to the file meanwhile is kept untouched. Write atomically as today; remove the file when no ask is
     left. A failed request changes nothing.
   - `hook-prompt` keeps its output format (`additionalContext` JSON) and its silence on errors.
2. **`board hook-watch`** (a hook command like `hook-prompt`: reads the hook JSON from stdin, never prints the token,
   any unexpected error → exit 0 silently):
   - Exit 0 at once, with no network request and no output, when `CLAUDE_CODE_ENTRYPOINT` starts with `sdk-`, when
     the session id is invalid, or when the session has no tracking file (the same fast path as `hook-prompt`, before
     reading the config).
   - Take the session's watcher lock without waiting; if another watcher of this session holds it, exit 0.
   - Loop: run the check from step 1. Messages → print them to **stderr**, one per line, nothing else on stderr, and
     exit **2**. No undelivered ask left (all delivered or closed, or the file gone) → exit 0. Then exit 0 also when
     the session's process is gone (below) or the watcher has run for 9 days (the hook timeout is 10). Otherwise
     sleep 15 s and repeat. When the server is unreachable or answers 5xx, keep going with a growing pause (15, 30,
     60, then 120 s at most; back to 15 after a success). A missing token, a 401/403 or unreadable settings → exit 0.
   - No SIGALRM for `hook-watch`; each request keeps the 10-second limit.
   - **Is the session still there:** `CLAUDE_PID` (digits; when missing or invalid, skip this check). On macOS and
     Linux `os.kill(pid, 0)` (ProcessLookupError → gone, PermissionError → there). On Windows (`os.name == "nt"`)
     never call `os.kill`, which terminates the process there: use `ctypes` `OpenProcess`
     (`PROCESS_QUERY_LIMITED_INFORMATION`) + `GetExitCodeProcess` (`STILL_ACTIVE` 259 → there; `OpenProcess` failing
     with access denied → there; any other failure → gone). On any other platform (MSYS or Cygwin Python, whose
     process ids differ from Windows ones) skip the check.
3. **Locks** (standard library only, both in the session-names folder next to the tracking file, created mode 0600,
   never deleted):
   - State lock `<id>.asks.lock`, held briefly around every read-modify-write of `<id>.asks`: the update in step 1 and
     `board ask` (restructure it: POST the ask first, then under the lock read the file, append, write; today a check
     running between its read and write could drop the new ask).
   - Watcher lock `<id>.watch`, held for the watcher's whole life, so a killed watcher frees it.
   - macOS/Linux: `fcntl.flock`. Windows: `msvcrt.locking` on byte 0 (seek to 0 first; `LK_NBLCK` for the watcher,
     `LK_LOCK` for the state lock, which retries for 10 s and then raises), `LK_UNLCK` before closing.
4. **README** → "Board": what `hook-watch` does in a few sentences (who gets woken, when it stops, that the prompt
   hook stays as the backup); add the two hook entries to the settings snippet for macOS/server and say the same
   entries go into the laptop's settings; note that `rewakeMessage`/`rewakeSummary` are not in Claude Code's docs (if
   a later version drops them, the wake still arrives under Claude Code's default "Stop hook" wording); the tracking
   file paragraph mentions the two lock files. Update the command table (`hook-watch` is a hook, like the others: one
   line).

## Settled: do not re-open

- The wake goes through Claude Code's own asyncRewake hook in each session. No per-machine daemon, no use of Claude
  Code's internal session sockets (`CLAUDE_CODE_MESSAGING_SOCKET`), no server push through Remote Control: those are
  undocumented or need Claude credentials on the server.
- Only the session's own tracked asks are watched (the `.asks` file), as `hook-prompt` does today. Answers for other
  sessions or earlier sessions on the topic stay with the plain `board` command.
- Polling every 15 s is enough; no long-poll or server push.

## Out of scope

- `~/.claude/settings.json` on any machine (Claude installs the hooks after the merge).
- The server (`~/aresus`), the plain `board` listing, `route`, `scan`, `brief`, `name-me`.

## Checks

New tests in `tests/test_board.py` against the fake server (extend `tests/fake-board.py` with the `ids` filter and a
request log; keep its existing behaviour). Real-time waits must stay short: make the poll pause, the pause after
errors and the 9-day limit module constants that the tests patch (in-process) or override (subprocess), so the whole
file still runs in a few seconds.

- `hook-watch` exits 0 at once with no output and no request: no tracking file; `CLAUDE_CODE_ENTRYPOINT=sdk-cli`;
  an invalid session id.
- An ask answered on the fake server while a watcher polls: the watcher prints exactly the message on stderr and
  exits 2; the ask is marked delivered; a following `hook-prompt` prints nothing for it; a following `hook-watch`
  exits 0 at once (nothing undelivered).
- Several asks, two answered in the same round: both lines in one wake.
- A second watcher for the same session while the first holds the lock exits 0 at once; after the first is killed
  (SIGKILL on POSIX), a new one takes the lock.
- `CLAUDE_PID` of a process that has ended → exit 0 after one round; the 9-day limit → exit 0.
- Server down for a few rounds, then up with the answer → still delivered; the pause grows and resets.
- 401 from the server → exit 0, silent.
- The hooks send only `ids=` queries (no `topic=`, no `session=`), per the fake server's log.
- An ask appended by `board ask` while a check is between its request and its write is kept (test the merge
  directly, or hold the state lock in the test).
- Done, dropped and missing items leave the file; the file is removed when empty.
- Existing `hook-prompt` and `ask` tests keep passing (adapt them to the ids query where they assert on requests).
- `/usr/bin/python3 tests/test_board.py` and `python3 tests/test_board.py` pass, and
  `bash tests/run-local.sh --only aresync` passes (give the summary lines).
- Windows: you cannot run it here. Keep Windows-only branches small and guarded by `os.name == "nt"`; Claude has the
  laptop run the tests before merging. Tests that need `fcntl` or SIGKILL skip themselves on Windows.
- Privacy: `grep -rliF -f ~/.config/aresync/private-terms --exclude-dir=.git .` in the worktree prints nothing (file
  names only, never the terms).

## Rules

Write only inside `~/aresync-257-board-watch` and temp folders (`mktemp -d`). Never touch `~/aresync` itself, any
other checkout, `~/.claude`, git config, or the machine's aresync config. Never commit, push, merge or install. No
network except the tests' local fake server on 127.0.0.1.

## Final message

Files changed, the exact test result lines, and anything doubtful (especially the Windows branches you could not run).
