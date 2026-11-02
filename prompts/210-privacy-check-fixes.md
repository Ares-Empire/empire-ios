# 210: Privacy check: scan only what a commit adds, and never choke on non-UTF-8 text

Status: running
Repo: `aresync` · Branch: `codex/210-privacy-check-fixes` · Worktree: `../aresync-210-privacy-check` · Model: `gpt-6.1-sol`, effort `high`

## Goal

`privacy-check.sh` (the pre-push hook and the `--all` audit) has two faults. After this brief, a commit that
removes personal data can be pushed normally, and commits with Latin-1 or other non-UTF-8 text are scanned like any
other.

1. The term scan reads removed lines (`-`) as well as added ones, so a commit that deletes personal data is blocked.
   That pushes people to `git push --no-verify`, which skips the whole check (it happened on 2026-11-01).
2. The term scan's awk aborts with `towc: multibyte conversion failure` on patches with non-UTF-8 bytes (aresium's
   test CSVs, e.g. `eval/files/cases/accent-latin1.csv`). The check then prints "could not scan personal terms", so
   those commits are never scanned for terms.

## Read first

- `README.md` → the privacy guard section; `privacy-check.sh` (`scan_commit`); `tests/test-privacy-check.sh`.

## Build

- Term scan: only the commit message and the **added** lines inside hunks (`+`, never the `+++` file header) are
  checked. Removed lines and context are ignored. Same in `pre-push` and `--all` mode.
- Make the term scan byte-safe: it must never abort on invalid UTF-8, Latin-1 or binary-looking bytes. Matching stays
  case-insensitive for ASCII letters; non-ASCII bytes are compared as they are (a UTF-8 term matches UTF-8 text).
  Output stays as today: term number, short sha, file name, never the matched text.
- Tests in `tests/test-privacy-check.sh`, in its existing style, with made-up terms in a temporary HOME:
  a. a commit that only removes a line containing a term passes;
  b. a commit that adds such a line is blocked;
  c. a commit whose patch contains Latin-1 bytes, plus a term on another added line, is scanned without an error and
     the term is reported;
  d. a term in the commit message is blocked.
- `README.md`: one sentence that removed lines are not checked, so deleting personal data never needs `--no-verify`.

## Settled: do not re-open

- Gitleaks handling, the commit email check, hook installation and the terms file format stay as they are.
- Removed lines are safe to ignore: every line was added by some commit, and that commit is what gets scanned.

## Rules

Stay in the worktree. Never commit or push, no installs. Never open or print `~/.config/aresync/private-terms`;
tests make their own terms file.

## Done when

- `bash tests/test-privacy-check.sh` passes (give the exact command and its result lines), and the other test
  scripts in `tests/` still pass.
- `bash privacy-check.sh --all ~/aresium` (read-only) finishes without any "could not scan" line. It is expected to
  report blocked terms in that repo; only report whether "could not scan" appears.

## Final message

Files changed, the exact test commands and result lines, anything doubtful.
