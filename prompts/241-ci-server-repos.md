# 241: CI for the public server repos and a local runner for the private ones

Status: merged 2026-11-07 (aresium ff1f096, ares-empire 83497c3, Arestoteles eda940c, ares 7deb029, aresync f9068ff; all four public CIs green on main)
Branch: `codex/241-ci` in each of the five repos · Worktrees: `~/ci-241/<repo>` (aresium, ares-empire, Arestoteles,
ares, aresync); Codex works in `~/ci-241` · Model: `gpt-6.1-sol`, effort `high` (established tooling across five repos:
careful setup, fresh-clone debugging and failure handling, but no hard design; Astra's 3× allowance is not needed)

## Goal

Every push and pull request to the four public server repos runs their existing tests on GitHub Actions, with no
secrets, so a broken change shows red before or right after it lands. The private repos (no Actions budget) get one
local command, `bash tests/run-local.sh` in aresync, that runs all their suites. This matters most after 2026-11-21,
when Claude builds alone.

## Read first

- `~/ares-empire/EMPIRE.md` → "How we build apps"
- Each repo's `AGENTS.md` / `CLAUDE.md` / `README.md`, above all their privacy rules (aresium `AGENTS.md`,
  Arestoteles `CLAUDE.md`, ares `CLAUDE.md`, aresync `README.md` → Privacy guard)
- The test commands below and the files they name
- `~/Arestoteles/.github/workflows/ci.yml` (manual only today; its "the repository is private" comment is stale: the
  repo is public) and `~/AresOS/.github/workflows/os-image.yml` (the Empire's style: actions pinned by commit SHA,
  read-only `permissions`, `concurrency`, `timeout-minutes`)

## How you work here

You run without a sandbox (the suites need network installs, temp servers and the private checkouts), so these are
rules, not walls:
- Write only inside `~/ci-241/` and temp folders (`mktemp -d`). Never touch `~/aresium`, `~/ares-empire`,
  `~/Arestoteles`, `~/ares`, `~/aresync` themselves; `~/Arestemis` and `~/aresus` only by running their tests.
- Never commit, push, or touch git config or GitHub settings (Claude commits and pushes). No global installs (no
  Homebrew, no `npm -g`, no `pip install` outside a venv you create in a temp folder or worktree).
- Network only for: npm and PyPI installs, the PocketBase release download, and read-only GitHub API calls
  (`gh api repos/<owner>/<action>/...`) to look up the commit SHA of an action tag.
- Tools present on this Mac: `node` 26, `python3` 3.14, `/usr/bin/ruby`, `age`, `age-keygen`, `gitleaks`, PocketBase
  0.40.6 at `~/.pocketbase-test/pocketbase` (its release `checksums.txt` is next to it). Not present: `actionlint`,
  `shellcheck`, `pwsh`, PyYAML. Check YAML with `ruby -ryaml -e 'YAML.load_file(ARGV[0])' <file>` and by reading.

## Build

1. **aresium** `.github/workflows/ci.yml`: `npm ci`, `npx prisma generate`, `npm run typecheck`, `npm test`,
   `npm run engine`. The money-review parity harness compiles an older commit with `git show`
   (`scripts/money-review-module.ts`, `MONEY_REVIEW_BASE`), so check out with `fetch-depth: 0`. Never drop or skip the
   parity tests to get green. Node: the version the server runs (find it in `deploy/` or the docs; say where), via
   `actions/setup-node` with npm caching keyed on `package-lock.json`.
2. **ares-empire** `.github/workflows/ci.yml`: install `push/requirements.txt` and `requests` into the job's Python, the
   `age` package (apt), and PocketBase 0.40.6 for linux amd64, downloaded by exact version and checked against this
   SHA-256 before use: `0e1f609158ed945f809f8a02ae012aa0427129c66ebb63c1aee76f2c0309373f`
   (`pocketbase_0.40.6_linux_amd64.zip`). Then run:
   `python3 -m unittest discover -s webauth -p 'test_*.py'`;
   `python3 -m unittest test_empire_http push.test_push backup.test_backup tools.test_empire_samples tools.test_empire_sync`;
   `node --test accounts/test_jobs.js`; `POCKETBASE=<binary> bash accounts/test-rules.sh`.
   The backup archive tests must really run (fail the job if `age` is missing rather than letting them skip). Python
   version: the server's (find it in `deploy/` or the docs; say where). Check that the README's "Run it locally" list
   names all of these and fix the list if not.
3. **Arestoteles** `.github/workflows/ci.yml`: run on push and pull_request (keep `workflow_dispatch`), replace the stale
   comment with a true one, pin the actions by SHA, run `python -m pip install -e '.[dev]'` and
   `python -m pytest -q --ignore=tests/test_real_vault.py`. Only the documented model-file skips are allowed: make the
   job fail if any other test is skipped (e.g. check pytest's `-rs` summary), so a missing tool like Ruby cannot turn a
   check into a silent skip.
4. **ares** `.github/workflows/ci.yml`, job name "owner contract": the four owner tests that do not need the private
   companions submodule:
   `python3 tools/check-owner.py OwnerChecks.test_override_and_default OwnerChecks.test_invalid_files OwnerChecks.test_unreadable_file OwnerChecks.test_legal_escaping`.
   Do not check out submodules (`submodules: false`). The full build (`test_full_build_and_missing_file`) needs the
   private submodule and stays local: say so in the README's test section.
5. **aresync** `tests/run-local.sh` (aresync is private; this script is the local stand-in for CI):
   - Runs every aresync suite its README names (each section's "Tests:" line: `test-report.sh`, `test-hooks.sh`, `test-submodules.sh`,
     `test-privacy-check.sh`, `test-backup.sh`, `test-drop.sh`, `sh tests/test-name-me.sh`,
     `/usr/bin/python3 tests/test_board.py`, `python3 tests/test_backup.py`; check the README and `tests/` for any
     suite the list misses, e.g. `test_drop.py`), then the Arestemis and aresus pytest suites, each with its own
     `.venv/bin/python -m pytest -q -p no:cacheprovider` (no `.pytest_cache` written into those checkouts). Paths
     default to `~/Arestemis` and `~/aresus` and can be overridden (`ARESTEMIS_DIR`, `ARESUS_DIR`).
   - Options: `--only aresync|arestemis|aresus` (repeatable) to run part of it.
   - Prints one line per suite (name, passed/failed, duration, skips) and a final summary line; exits non-zero if any
     suite fails or is missing. Skips caused by a missing tool (age, gitleaks) are listed as such, separately from
     intended skips. Windows (`test-windows-sync.ps1`, needs `pwsh`) is reported as "not run on this machine".
   - Contacts only test-local services; never the live server, Aresus, Telegram or GitHub. If a suite needs
     `EMPIRE_BACKUP_SOURCE` for its synthetic two-repo round trip, set it to a temp fixture, never a real folder.
   - Prints nothing personal: suite names, counts and durations only; a failing suite's own output goes to a log file
     in a temp folder whose path is printed.
6. **Every workflow:**
   - Triggers: `push` (all branches, so Claude sees a branch's result before merging), `pull_request`,
     `workflow_dispatch`.
   - `runs-on: ubuntu-24.04` (pinned, not `-latest`); `timeout-minutes` per job; `concurrency` with
     `cancel-in-progress: true` keyed on workflow and ref; top-level `permissions: contents: read` and nothing more.
   - Every action pinned by full commit SHA with the tag in a comment (`actions/checkout@<sha> # v4.x.y`); look up the
     SHA with `gh api`, never invent one.
   - No secrets of any kind (not even `secrets.GITHUB_TOKEN` in a step), no deploy steps, no artifact uploads, no
     caches that could hold anything but public packages. Test output must not contain personal data: the suites
     already use invented data; do not add steps that print environment or config.
7. A short "Tests and CI" section in each of the five READMEs: what runs where (CI on GitHub for public repos; local
   runner for private ones), the exact local commands, and the known gaps (ares full build; Arestoteles real vault and
   model files; Windows). Keep the READMEs' existing style; no badges.

## Settled: do not re-open

- Public repos only on GitHub Actions; the private ones (aresync, Arestemis, aresus) run locally (the org's Actions
  budget for private repos is $0).
- No secrets of any kind in public workflows: no tokens, keys, owner files, database URLs or private-repo access. The
  ares companions submodule stays out of CI.
- No change to application code or to existing test expectations. If a test fails on a clean machine, find out why
  and report it; fix only the CI setup, never the assertion.
- No new dependencies in any repo's package files.

## Out of scope

- iPhone apps (brief 242), AresOS, Arestemis/aresus code, security fixes (another session does those).
- Branch protection and required checks (Patrik's call).

## API

None.

## Done when

- For each public repo, the workflow's commands pass on this Mac in a **fresh clone** (`git clone --no-local
  ~/ci-241/<repo> <tmp>`, full history, then copy your new and changed files over it): no gitignored local file
  (`.env`, `config/personal.json`, `data/`, `node_modules`, `.venv`) is needed. Show each suite's summary line.
  For ares-empire use `POCKETBASE=~/.pocketbase-test/pocketbase` locally; for Arestoteles a fresh venv in a temp folder.
- `bash tests/run-local.sh` in `~/ci-241/aresync` passes on this Mac; show its full summary. Show also that it exits
  non-zero when a suite fails (e.g. point `ARESUS_DIR` at an empty temp folder).
- Each workflow file loads with Ruby's YAML parser, and you have read it once more against point 6.
- A list of what only a real GitHub run can prove (Claude pushes the branches and checks them).

## Final message

As in `AGENTS.md`: files changed per repo, the exact test summary lines, the Node/Python versions chosen and where
they come from, what is missing or doubtful.
