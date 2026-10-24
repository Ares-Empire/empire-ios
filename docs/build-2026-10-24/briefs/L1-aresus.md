# L1: Aresus server in English and German

Read `L-COMMON.md` (same folder) first; it holds the language contract, the German style and the test rules.
Worktree: `~/wt/aresus-lang` (branch `languages`). Venv: `/opt/homebrew/bin/python3 -m venv .venv &&
.venv/bin/pip install -e '.[dev]'` (look at `pyproject.toml` for the extras); tests: `.venv/bin/python -m pytest -q`.
Read `CLAUDE.md`, `docs/API.md`, then `lines.py`, `timefmt.py`, `decide.py`, `checks.py`, `sync.py`, `vitals.py`,
`service.py`, `push.py`, `store.py`, `models.py`, `checks.yaml`.

## Build

1. **`texts.py`:** every sentence and word Aresus writes, English and German, and the time words (`ago`, `span`,
   `clock`) per language. `timefmt.py` keeps the timestamp helpers; its word functions take the language.
2. **Every contract field that is a sentence or a word follows the request language:** `Province.word`, `line`;
   `Server.issue`; `Overview.summary`; `Check.name` and `detail`; `Incident.summary`; `RunSummary.summary`; the
   problems' `message` where Aresus words it from the problem `key` (`sync.py` `_PATTERNS`/`_FIXED`); machine counts
   ("2 machines"). Not translated: province, machine, unit and container names, `Deploy.subject`, the run's `lines`,
   systemd's own state words (`inactive (dead)`), and the free-text `message` Aresync sends when Aresus has no wording
   for its key.
3. **Lines from `checks.yaml`:** each line text gets a German twin in the file (choose a clear YAML shape, e.g.
   `text` + `de`, and a plain line as `{en, de}` or a `line_de` key; keep a plain English string valid, then German =
   English). Check `name`s get an optional German name the same way. Template values that are words (`{website.word}`
   up/down, `{accounts.ok}` ok/down, the `ago` filter, `{sync.machines}`) render in the language. Add the German to
   every line in the real `checks.yaml` and to the fake world (`fake.py`).
4. **The check round** decides once and renders the lines in both languages (they depend on `now`), so a request only
   picks one. **Incidents** store both summaries (a migration in `store.py`; old rows: English for both).
5. **Pushes** (`push.py`): send the English title/body as now plus `localized: {"de": {"title": ..., "body": ...}}`
   (only the fields that differ). The push service accepts this from the parallel brief L3 (contract in
   `~/ares-empire/docs/PUSH.md` on its branch; if the field is not there yet, build against this description:
   `localized` maps a language to any of `title`, `subtitle`, `body`; a device whose registered language is `de` gets
   those, every other device the top-level ones). The 10-minute flap rule compares the English text.
6. **Routes:** read the language per request (`Accept-Language`), set `Content-Language`; error bodies the app shows
   (401/403/404/503 `{"error": ...}`) in both languages.
7. `docs/API.md`: a "Language" section; `README.md`/`CLAUDE.md` where they become wrong.

## German (use these; word everything else the same way, short)

| English | German |
|---|---|
| Issue / Active / Inactive / Planned (word) | Problem / Aktiv / Inaktiv / Geplant |
| Everything running · 1 issue · 2 issues | Alles läuft · 1 Problem · 2 Probleme |
| Website down since 14:02 (502) · Website down (502) | Website ausgefallen seit 14:02 (502) · Website ausgefallen (502) |
| Running again after 6 min | Läuft wieder nach 6 Min. |
| Not built yet · Not checked yet · Off on purpose · Paused | Noch nicht gebaut · Noch nicht geprüft · Absichtlich aus · Pausiert |
| Hunting · last scan 4 min ago | Sucht · letzter Scan vor 4 Min. |
| Not deployed · Runs on the MacBook · Runs on the PC · Not on the server | Nicht ausgerollt · Läuft auf dem MacBook · Läuft auf dem PC · Nicht auf dem Server |
| 2 machines · 1 machine · last sync 4 min ago | 2 Geräte · 1 Gerät · letzter Sync vor 4 Min. |
| just now · 45 min ago · 5 h ago · 3 days ago · never | gerade eben · vor 45 Min. · vor 5 Std. · vor 3 Tagen · nie |
| 45 min · 5 h · 3 days · 23 Oct | 45 Min. · 5 Std. · 3 Tage · 23. Okt. |
| website up / down · ok / down | Website erreichbar / ausgefallen · ok / ausgefallen |
| Disk 92 % full · Memory 95 % used · Server numbers unreadable | Festplatte zu 92 % voll · Arbeitsspeicher zu 95 % belegt · Serverwerte nicht lesbar |
| Website · Accounts · Database container · TLS certificate · Bot | Website · Konten · Datenbank-Container · TLS-Zertifikat · Bot |
| active for 5 h · waiting · last run 4 min ago · last run failed (exit-code) | aktiv seit 5 Std. · wartet · letzter Lauf vor 4 Min. · letzter Lauf fehlgeschlagen (exit-code) |
| timeout after 10 s · unreachable · expires in 61 days / 1 day | Zeitüberschreitung nach 10 s · nicht erreichbar · läuft in 61 Tagen / 1 Tag ab |
| invalid: … · check failed (…) · check error: … | ungültig: … · Prüfung fehlgeschlagen (…) · Prüffehler: … |
| pulled 2 · pushed 1 · cloned · committed · deployed · nothing to do · failed | 2 gepullt · 1 gepusht · geklont · committet · deployt · nichts zu tun · fehlgeschlagen |
| rebase conflict in aresium · pull fails in … · push fails in … | Rebase-Konflikt in aresium · Pull schlägt fehl in … · Push schlägt fehl in … |
| … · 2 more · and 2 more | … · 2 weitere · und 2 weitere |
| gh not logged in · pull-only (real commit email) · … is not a git repo | gh nicht angemeldet · nur Pull (echte Commit-E-Mail) · … ist kein Git-Repo |
| no report for 3 h · Server has not reported for 3 h | kein Bericht seit 3 Std. · Server hat sich seit 3 Std. nicht gemeldet |
| 1 open problem, not alerted yet | 1 offenes Problem, noch nicht gemeldet |

## Done when

- All tests pass, with new ones for both languages on every field above, the YAML shapes (old plain strings still
  load), the incident migration, the push payload and the header parsing.
- `ARESUS_FAKE=1` serves `/overview` in German with `Accept-Language: de` (show a short excerpt in your final message).
- Deploy steps: Aresus deploys itself after a push to `main` (Aresync hook); say whether anything else is needed.
