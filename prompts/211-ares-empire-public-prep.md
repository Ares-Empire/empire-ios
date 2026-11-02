# 211: Ares Empire ready to be public: owner details from a file, server IP out, Arestemis research out

Status: merged 2026-11-02
Repo: `ares-empire` · Branch: `codex/211-public-prep` · Worktree: `../ares-empire-211-public-prep` · Model: `gpt-6.1-sol`, effort `high`

## Goal

This repo will go public. Today the owner's name, postal address and email are typed into the legal pages, the
contact code, the accounts mail hook, tests and docs; the server's IP address is in a doc; and the Arestemis site
research lives here. After this brief the live pages show exactly what they show today, but the owner details come
from one file outside every repo, the IP is gone, and the Arestemis research is no longer in this repo.

## Read first

- `CLAUDE.md`, `README.md`, `EMPIRE.md` → "How we build apps".
- `webauth/legal.py`, `webauth/contact.py`, `webauth/server.py`, `webauth/test_contact.py`, `webauth/test_server.py`.
- `accounts/pb_hooks/lib/mail.js`, `accounts/test-rules.sh`, `deploy/install-accounts.sh`.
- Files that hold owner details today: `web/legal/{imprint,impressum,privacy,datenschutz}.html`,
  `webauth/contact.py`, `accounts/pb_hooks/lib/mail.js`, `accounts/test-rules.sh`, `webauth/test_*.py`,
  `docs/PRIVACY.md`, `docs/ACCOUNTS.md`. The server IP: `docs/BACKUP.md`.

## The owner file (the same contract in ares-empire, ares and aresium)

- Path: `$ARES_OWNER_FILE` if set, else `~/.config/ares-empire/owner.json` for the user the process runs as (on the
  server that is root: `/root/.config/ares-empire/owner.json`, already in place).
- Content: a JSON object with exactly the keys `name`, `street`, `city` (postcode and town in one line) and `email`,
  each a non-empty string. Anything else is an error.
- A missing or invalid file fails loudly at startup with a message that names the path and the problem, never with
  the values. A legal page is never served with an empty or placeholder address.
- Tests use a made-up file through `ARES_OWNER_FILE` (`Erika Musterfrau`, `Musterstraße 1`, `12345 Musterstadt`,
  `owner@example.org`). No test reads the real file.

## Build

1. **Legal and contact pages:** the four legal pages and the contact pages get placeholders for name, street, city
   and email, filled from the owner file when served (load it once at startup). With the real file the pages must
   read exactly as today. Tests: each page rendered with the made-up file contains its values and no placeholder is
   left; startup with a missing or invalid file fails.
2. **`webauth/contact.py`:** `OWNER_EMAIL` comes from the owner file.
3. **Accounts mail hook:** PocketBase runs as the user `empire-accounts` and cannot read root's home.
   `deploy/install-accounts.sh` (run as root) reads the owner file and hands only the email to the service through its
   environment (a systemd drop-in or the environment file the unit already uses; follow what the script does today).
   `accounts/pb_hooks/lib/mail.js` reads it from there. The install script refuses to run without the owner file; the
   hook throws a clear error rather than sending to a guessed address when the variable is missing.
   `accounts/test-rules.sh` uses a made-up address.
4. **Docs:** in `docs/PRIVACY.md` and `docs/ACCOUNTS.md` the values become a pointer to the owner file. Describe the
   owner file once (where it lives on the server and the Mac, its keys, which services read it, that it is never in a
   repo) in `docs/PRIVACY.md`, and link there from where the values were. `docs/BACKUP.md`: the IP becomes
   `<the server's IP address>`.
5. **Arestemis research out:** delete `docs/ARESTEMIS-SITES.md` and `docs/ARESTEMIS-ANYTHING.md`; Claude copies them
   into the private Arestemis repo under the same names (`docs/ARESTEMIS-SITES.md`, `docs/ARESTEMIS-ANYTHING.md`).
   Every link to them now names that place ("the Arestemis repo, `docs/ARESTEMIS-ANYTHING.md`"). In what remains, cut
   any description of how Arestemis gets past sites' blocks to a plain statement: no per-site findings and no
   techniques. "Some sites are read through a proxy provider" is fine where the privacy record needs it. Check at least `EMPIRE.md`, `docs/PRIVACY.md`,
   `docs/ARESTEMIS-APP.md`, `docs/API-EMPIRE.md`, `web/app/empire-data.js` and `tools/empire_samples.py`, then search the repo for anything else on sites' blocks.
   After changing `web/app/empire-data.js`, run `python3 tools/empire_samples.py --web`.
   Leave `web/legal/` texts alone apart from the owner details: the public privacy policy keeps its list of processors.

## Settled: do not re-open

- One owner file per machine for all three sites, not a config per repo: the same details serve three sites and had
  to be changed in two places before.
- The live output does not change.
- The real values never go into the repo, tests, docs, logs, or your final message. Do not print them.

## Out of scope

Anything else. No restyling, no new features, no changes to texts beyond what is listed.

## Rules

Stay in the worktree. Never commit or push, no installs.

## Done when

- The Python tests pass (`python3 -m unittest discover -s webauth -p 'test_*.py'` or what the repo uses; give the exact
  command and result line). `bash accounts/test-rules.sh` if it runs locally, else say why not.
- `grep -rliF -f ~/.config/aresync/private-terms --exclude-dir=.git .` prints nothing (file names only, never `-n`).

## Final message

Files changed; the exact test commands and result lines; the server steps Claude must run after merging (for example
`deploy/install-accounts.sh`, service restarts); anything doubtful.
