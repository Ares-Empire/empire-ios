# 89: Aresync on the Mac: drops land in their folders, receipts get their inventory row

Status: draft
Branch: `codex/89-drops` · Worktree: `../aresync-89-drops` (a worktree of **`~/aresync`**, not of empire-ios) ·
Model: `gpt-6.1-sol`, effort `high`

## Goal

Patrik sends a file or photo from the Aresus app; it lands in a chosen folder on his MacBook, from anywhere. The
server half is brief 88 (built at the same time). This brief builds the Mac half: a small program that runs every
minute while the Mac is awake, fetches waiting drops from Aresus, decrypts them, writes each into its folder under its
name (never overwriting anything), adds a receipt's row to the receipts folder's `INVENTORY.md`, reports where it
landed, and sends the Mac's folder list so the phone can offer it.

## Rules for you (this repo has no AGENTS.md)

- Write only inside your worktree. Never commit, push or touch git config (Claude commits). Install nothing. No network
  (tests use a local fake server on 127.0.0.1).
- **Never read, list or write anything in the real `~/Documents` or `~/Downloads`**, and never the real Keychain:
  tests use a temp folder as the home and `DROP_IDENTITY_FILE` with a throwaway key made by `age-keygen`.
- **Python must run on `/usr/bin/python3` (3.9.6)** and on newer ones: `from __future__ import annotations`, no
  `match`, standard library only. Shell stays bash 3.2 compatible, like the rest of the repo.
- No real personal data in tests or fixtures; the inventory fixture below is made up.
- Never put the machine token on a command line or in a log.

## Read first

- **The contract, settled:** `~/aresus/docs/API.md` → "Drops (Aresync drop, version 1)" (read only). Build the Mac side
  exactly to it: `PUT /drops/folders`, `GET /drops/pending`, `GET /drops/{id}/file`, `POST /drops/{id}/done`,
  `POST /drops/{id}/failed`, with `Authorization: Bearer <ARESUS_TOKEN>`. If it cannot work, leave `TODO(contract)`.
- Why: `~/ares-empire/docs/ARESYNC-DROP.md` (read only), sections "How a file travels", "Rules the Mac keeps",
  "Receipts".
- This repo: `README.md` (sections on Aresus reports and "Backups (Mac)"), `config.example`, `backup.sh`
  (`backup_identity`: the age key from the Keychain), `backup.py` (style), `com.aresync.sync.plist`,
  `tests/test-backup.sh` and `tests/fake-aresus.py` (how tests run).

## Build

1. **`drop.py`** with commands `run` (one pass) and `folders` (print the folder list it would send, for checks).
   Settings come from `config`: read them by sourcing `config` in `/bin/bash` and printing only the needed variables
   (do not write a shell parser). New settings in `config.example`, all off by default:
   `DROP_URL=""` (base, e.g. `https://www.ares-empire.de/api/aresus`; empty = drops off, `run` exits quietly),
   `DROP_DOCUMENTS="$HOME/Documents"`, `DROP_DOWNLOADS="$HOME/Downloads"`, `DROP_FALLBACK="Zu sortieren"` (relative
   to documents), `DROP_RECEIPTS=""` (relative to documents; empty = receipts go to the fallback), `DROP_AGE` (default:
   `age` on PATH), `DROP_IDENTITY_FILE=""` (tests only). The token is the existing `ARESUS_TOKEN`. The secret key comes
   from the Keychain item **"Ares Empire drop key"**, account `age` (as `backup.sh` reads its key), passed to `age`
   without writing it to disk.
2. **One pass (`run`):** take a lock (one run at a time); send the folder list when it changed or 30 minutes passed;
   fetch the pending drops; process each one; exit. Network errors: one log line, exit 0, next minute tries again.
3. **One drop:**
   - Download the encrypted file into a private temp folder (mode 700).
   - Decrypt with `age -d` straight into a hidden part file in the destination folder
     (`.aresync-drop-<id>.part`), counting bytes and computing sha256 while writing. Mismatch with `size`/`sha256` →
     delete it, `POST failed` with `checksum`. Age fails → `failed` with `decrypt`. Writing fails → `write`.
   - Place it under its name **without overwriting**: `os.link` part → final name, on "exists" try `name (2).ext`,
     `name (3).ext` …, then unlink the part file.
   - `POST done`. **Idempotent:** keep a small local state file (`~/aresync/.drop-state.json`, git-ignored) of drops
     already written (id → path, fallback, inventory). A pending drop found there is only reported again, never
     written twice.
4. **Where it goes** (paths resolved with `realpath`; "inside a git repo" = a folder from the root down to it contains
   `.git`):
   - `kind: file`, `target: null` → the fallback folder (`DropDone.fallback: null`).
   - `kind: file` with a target: `<root>/<folder>` must exist as a folder, resolve inside its root (else
     `outside_roots`), not be inside a git repo (else `in_repo`); missing → `folder_gone`. Those three go to the
     fallback folder with that reason. `new_folder` is made inside it (an existing one is used).
   - `kind: receipt`: the receipts folder (`DROP_RECEIPTS`); `Permanent/` inside it when `flat` or `keep` (made when
     missing). Not set or missing → fallback folder with `receipts_folder_gone`, no inventory row.
   - The fallback folder is `<documents>/<DROP_FALLBACK>`, made on first use.
   - Re-check the name against the contract's rules for new names before writing; a failing name is a `failed` with
     `other` (the server should never let one through).
5. **The receipt's inventory row** (only for a receipt that landed in the receipts folder or its `Permanent/`), in
   `<receipts>/INVENTORY.md`. All logic in pure functions with tests; written with a temp file + `os.replace`;
   every other byte of the file stays as it was. **If the file does not look exactly as expected** (header, separator,
   the "Nächste Fälligkeit" line, the Permanent table), leave it untouched and report `inventory: "skipped"`.
   - Dates: base = receipt date + 25 months (24 months Gewährleistung + 1 month buffer; day clamped to the month's
     end). `tax` → 31 December of (year + 5). `warranty_until` → that date + 1 month. **`Löschen ab` = the latest.**
   - `Grund` (German, in this order, only the parts that apply): `Gewährleistung 24 Mon. ab Lieferung <date> →
     <date + 24 Mon.>, + 1 Mon. Puffer.` · `Steuererklärung <year>: bis Ende der Festsetzungsfrist (<tax date>).` ·
     `Herstellergarantie bis <warranty>, + 1 Mon. Puffer.` · `Vom iPhone abgelegt (Aresync).`
   - Main table row: `| **<Löschen ab>** | `<file>` | <date> | <shop> | <item> | <Betrag> | <Grund> | ja |`, inserted
     so the table stays sorted by `Löschen ab` (after rows with the same date). `Betrag` German: `89,99 €`,
     `1.299,00 €`. A `|` inside a cell becomes `\|`.
   - Then the line starting `**Nächste Fälligkeit:` gets the table's earliest date: replace only the date inside
     `**Nächste Fälligkeit: <date>**`, keep the rest of the line.
   - `Permanent/` receipts: a row in the Permanent table instead: `| `<file>` | <date> | <shop> – <item> | <Betrag> |
     <Warum> |`, where `Warum` joins with `; `: `Wohnung: Nachweis für Verkauf und Spekulationsfrist` (flat),
     `Wertnachweis (Hausrat), solange im Besitz` (keep), `Steuererklärung <year>` (tax). It replaces the placeholder
     row `| _(leer)_ | | | | |` when that is the only row, else it is appended to the table.
   - The fixture to test against (made up, the real file has exactly this shape):
     ```markdown
     # Inventar & Löschliste

     Sorted by `Löschen ab`, earliest first. Last reviewed: **2026-10-03**

     | Löschen ab | Datei | Rechnungsdatum | Händler | Artikel | Betrag | Grund | Noch im Besitz? |
     |---|---|---|---|---|---|---|---|
     | **2028-10-18** | `2026-09-18 Shop - Iron - 62,99 EUR.pdf` | 2026-09-18 | Shop | Iron | 62,99 € | Gewährleistung 24 Mon. ab Lieferung 2026-09-18 → 2028-09-18, + 1 Mon. Puffer. | ja |

     **Nächste Fälligkeit: 2028-10-18** — nothing expires before then.

     ---

     ## Permanent (nie löschen)

     | Datei | Datum | Was | Betrag | Warum permanent |
     |---|---|---|---|---|
     | _(leer)_ | | | | |
     ```
6. **The folder list:** the folders under documents and downloads, up to 4 levels, paths relative to each root with
   `/`, sorted, at most 5000 in all (stop walking past that). Skip: names starting with `.`; any folder containing
   `.git` (and everything below it); `node_modules`, `__pycache__`, `.venv`, `venv`, `build`, `dist`, `DerivedData`,
   `Pods`; package folders (`.app`, `.bundle`, `.framework`, `.xcodeproj`, `.xcworkspace`, `.photoslibrary`,
   `.musiclibrary`, `.imovielibrary`, `.fcpbundle`, `.pages`, `.numbers`, `.key`, `.rtfd`, `.playground`, `.xcassets`,
   `.lproj`, `.plugin`, `.kext`). Plus `fallback`, `fallback_count` (visible files directly in the fallback folder)
   and `receipts`. Unreadable folders are skipped, never an error.
7. **`com.aresync.drop.plist`:** label `com.aresync.drop`, `/usr/bin/python3 -I /Users/pab/aresync/drop.py run`
   (a fixed interpreter path, so the macOS permission for Documents and Downloads, granted once, stays),
   `StartInterval` 60, `RunAtLoad`, the same PATH and HOME as `com.aresync.sync.plist`, logs to `drop.out.log` /
   `drop.err.log` (git-ignored like the others). One log line per drop: id, size, where it landed; never contents or
   the token.
8. **README** → a "Drops (Mac)" section: what it does, the settings, setting it up (make the key with `age-keygen`, put
   the secret line into the Keychain item, give the `age1…` public half to the server's `DROP_AGE_RECIPIENT`, set
   `DROP_URL` and `DROP_RECEIPTS`, load the agent with `launchctl`), that macOS asks once whether Python may access
   Documents and Downloads, and how to check it (`python3 drop.py folders`, the logs).
9. **Tests:** `tests/test-drop.sh` in the style of the other tests (bash runner, temp home with made-up Documents and
   Downloads, a real throwaway age key, a local fake drop server; extend `tests/fake-aresus.py` or add
   `tests/fake-drops.py`). Pure Python parts may also have `unittest` tests run by the script with `/usr/bin/python3`.

## Settled: do not re-open

- The contract (Claude's, 2026-11-01). The rules above for where files go, never overwriting, never touching existing
  files, and the inventory rules (Patrik, 2026-11-01).
- Its own launchd agent, separate from the daily sync run; `/usr/bin/python3`.
- A separate Keychain item from the backup key.
- No AI anywhere in this program.

## Out of scope

- The server (brief 88), the app, loading the agent on this Mac, making the real key (Claude does the live setup).
- The Windows laptop.
- Changing `aresync.sh` or the backup code (read them only).

## Done when

- `bash tests/test-drop.sh` passes, with checks for: a file into a chosen folder; a new folder; a name that exists →
  `(2)`; each fallback reason; a receipt into the receipts folder and one into `Permanent/` with the exact rows and the
  "Nächste Fälligkeit" line (dates: a normal receipt, one with `tax`, one with a later `warranty_until`, a 31 January
  date for the month-end clamp); an inventory file that looks different → untouched and `skipped`; checksum mismatch
  and wrong key → `failed` with nothing left in the destination; a drop reported again after a lost `done`, never
  written twice; the folder list skips (a repo, a hidden folder, `node_modules`, an `.app`, level 5); `DROP_URL` empty →
  quiet exit; the token never in a log or `ps` line.
- The existing tests still pass: `bash tests/test-backup.sh`, `tests/test-report.sh`, `tests/test-hooks.sh`,
  `tests/test-privacy-check.sh`, `tests/test-submodules.sh`.
- `drop.py` runs under `/usr/bin/python3` (3.9) and under `python3` on PATH.

## Final message

Files changed, the exact summary lines of every test script, every `TODO(contract)`, and anything doubtful.
