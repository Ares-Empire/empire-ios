# 255: Aresync auto-commits only the notes repo

Status: merged 2026-11-07 (aresync 33219cd; Mac suites and the laptop's Windows tests, 92 passed, green)
Repo: `aresync` (private) · Branch: `codex/255-auto-commit` · Worktree: `~/aresync-255-auto-commit` · Model:
`gpt-6.1-sol`, effort `high` (a careful change mirrored in two scripts with tests, design settled below; no hard
reasoning that needs Astra's 3× allowance)

## Goal

Patrik decided (2026-11-07, board #26, "Off for code"): the sync stops committing uncommitted edits in code repos and
keeps doing it for the Weltbild notes (repo `opinions`). Today `aresync.sh` (Mac, server) and `windows/aresync.ps1`
(the Windows laptop) commit every repo's uncommitted files at login and 09:00 and push them; a Claude session's
half-done edit in a website repo can go live that way. The board scan already lists checkouts with uncommitted files,
so nothing is forgotten without the auto-commit. Pulls must keep working for every clean checkout.

## Read first

- `README.md` (the table under "For each non-archived …", Privacy guard, the config sections, Windows setup)
- `aresync.sh`: the defaults block, the per-repo loop from the busy/detached checks through the pull (about lines
  400–460), the pull-only path where a non-noreply `COMMIT_EMAIL` sets `AUTO_COMMIT="false"`
- `windows/aresync.ps1` (the same steps, about lines 280 and 350–400), `config.example`, `windows/config.example.ps1`
- `tests/test-report.sh`, `tests/test-submodules.sh`, `tests/test-windows-sync.ps1`, `tests/run_local.py`

## Build

1. **A list of repos that auto-commit.** New setting `AUTO_COMMIT_REPOS` (space-separated repo names; `*` means every
   repo), default `"opinions"`, in the defaults block of `aresync.sh` with a short comment, and the same in
   `windows/aresync.ps1` (`$AUTO_COMMIT_REPOS = 'opinions'`). `AUTO_COMMIT` stays the master switch: `false` (the
   server, and the pull-only privacy path) still means no repo is committed. A repo is auto-committed only when
   `AUTO_COMMIT` is true and its name is on the list (exact name match, or `*`). The commit itself stays exactly as it
   is (gitlinks left out, `--only`, the noreply identity, the message).
2. **Uncommitted code repos are left alone, calmly.** On a machine with `AUTO_COMMIT` true, a repo not on the list
   whose tracked files have uncommitted changes (staged or not; `status --porcelain --untracked-files=no
   --ignore-submodules=all`, matching what `pull --rebase` refuses) is skipped for this run before the pull: log
   `SKIP  <name>  (uncommitted changes: left for whoever is editing, not pulled)`, count it as skipped, and raise no
   problem and no alert (the board scan reports it). Untracked files alone do not stop the pull. With `AUTO_COMMIT`
   false nothing changes: such a checkout still fails to pull and raises the existing `pull:<name>` problem, because on
   a pull-only deploy machine uncommitted changes are an anomaly that stops deploys and must alert.
3. **Same behaviour on Windows** in `windows/aresync.ps1`, step for step.
4. **Docs.** README: the table row for uncommitted changes ("auto-commit only repos in `AUTO_COMMIT_REPOS`, default the
   notes repo; others are skipped until committed"), and the setting where the other settings are described.
   `config.example` and `windows/config.example.ps1`: the setting with a one-line comment. The header comments of both
   scripts (the numbered step list) say the same.

## Settled: do not re-open

- No autostash, no stash of any kind, no fetch-then-reset: a session may be editing that checkout right now; its files
  are never touched.
- Pushes of local commits (`AUTO_PUSH`) stay as they are for every repo.
- The board scan (`claude/board`) does not change.

## Checks

- `tests/test-report.sh` and `tests/test-submodules.sh` keep passing. Where they rely on committing a repo that is not
  `opinions`, add `AUTO_COMMIT_REPOS="*"` to their test config rather than renaming repos, so their old cases still
  test the commit path.
- New cases in `tests/test-report.sh` (or a new `tests/test-auto-commit.sh` that `tests/run_local.py` runs with the
  other aresync shell suites), each with a bare origin and a clone as the existing tests make them:
  - default list, a code repo with a modified tracked file and origin one commit ahead: no commit, HEAD unchanged,
    the file's content unchanged, the SKIP line logged, the run report has no problem and no alert for it;
  - the same repo with only an untracked file: pulled to origin's commit, the untracked file still there, no commit;
  - a repo named `opinions` with a modified file: committed and pushed as before;
  - `AUTO_COMMIT_REPOS="*"`: the code repo is committed again (old behaviour);
  - `AUTO_COMMIT="false"` with a dirty code repo: no commit, and the `pull:<name>` problem is reported as today.
- Matching cases in `tests/test-windows-sync.ps1`. `pwsh` is not on this Mac: write them carefully against the
  existing cases' helpers; Claude has them run on the laptop before merging.
- `bash tests/run-local.sh --only aresync` passes (give the summary lines).
- Privacy: `grep -rliF -f ~/.config/aresync/private-terms --exclude-dir=.git .` in the worktree prints nothing (file
  names only, never the terms).

## Rules

Write only inside `~/aresync-255-auto-commit` and temp folders (`mktemp -d`). Never touch `~/aresync` itself, any other
checkout, git config, or the machine's aresync config, launchd jobs or logs. Never commit, push, merge, install, or
run `aresync.sh` against real repos (only the tests' temp repos). No network.

## Final message

Files changed, the exact test result lines, and anything doubtful (especially in the PowerShell you could not run).
