# 50: Aresus comfort before its first TestFlight build (Patrik's list nos. 20–22)

Status: draft
Branch: `codex/50-aresus-comfort` · Worktrees: `../empire-ios-50-aresus-comfort` (this repo) and
`../aresus-50-province-links` (the aresus repo, branch `codex/50-province-links`) · Model: `gpt-6.1-sol`, effort `high`

## Goal

Patrik approved the comfort list for Aresus (2026-10-30, all items). After this brief the run report has a close
button, a province's page opens that province (its app when installed, else its website), and the Aresync tab has the
same Settings gear as the Aresus tab.

Three other briefs run at the same time: 49 (Arestemis), 51 (Arestoteles), 52 (Empire and the shared Create account).
52 changes `Empire/Empire/Screens/EmpireSheets.swift` and `Shared/Design/AccountSheets.swift`; stay out of those.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Languages", "Light mode", the "Aresus app" and "Empire app" entries under Setup state)
- `docs/reviews/2026-10-30-swipe-and-comfort.md` → "The other four apps" → "Aresus"
- This repo: `Aresus/Aresus/Screens/` (`AresusTabs.swift`, `RunSheet.swift`, `ProvinceDetailScreen.swift`,
  `SyncScreen.swift`, `WatchtowerScreen.swift` for the gear), `Aresus/Aresus/Model/AresusModels.swift`,
  `Aresus/Aresus/Samples/`, `Empire/Empire/Model/ProvinceOpener.swift` and its tests in `Empire/EmpireTests/`
- The aresus repo (`~/aresus`, read its `CLAUDE.md` and `docs/API.md`): `src/aresus/hub.py` (reads the hub's
  `state.json`), `src/aresus/models.py` (`ProvinceDetail`), `src/aresus/service.py`, `src/aresus/config.py`,
  `tests/`, `docs/samples/`
- The hub's app links: `~/ares-empire/webauth/apps.json` (`{"<slug>": {"scheme": "arestemis://", "install": …}}`;
  on the server `/root/ares-empire/webauth/apps.json`), and the `url` of each project in the hub's data
  (`~/ares-empire/web/app/empire-data.js` has the same `projects` shape as the server's `data/state.json`)

## Build

1. **Done on the run report** (list no. 20). The run sheet (`RunSheet`, presented from `AresusTabs.swift`) closes
   only by pulling down, and a pull first scrolls the log. Give it the same close button as the shared sheets
   (`Button(role: .close)` in the top-right toolbar place, as `Shared/Design/AccountSheets.swift` does; iOS 26 draws
   it as ✕). Wrap the sheet in a `NavigationStack` only if that is what the toolbar needs; the report's own header
   and layout stay as they are.
2. **Open on a province's page** (list no. 21).
   - **The aresus server** (worktree `../aresus-50-province-links`, from `main` of `~/aresus`): `ProvinceDetail`
     gains `url: str | None` (the project's `url` in the hub's `state.json`; empty → null) and `app: str | None`
     (the `scheme` for that slug in the hub's `webauth/apps.json`; missing → null). Read `apps.json` the way
     `hub.py` reads `state.json` (re-read when it changes; a missing or broken file means null, logged once), with
     its path in `config.py` (`HUB_APPS`, default `/root/ares-empire/webauth/apps.json`). Tests for both fields,
     including the missing and broken files. Update `docs/API.md` and `docs/samples/` (the province detail samples).
     Run its tests (`.venv/bin/python -m pytest -q`, `CLAUDE.md` there → Test and run; `ARESUS_FAKE=1` on the Mac).
   - **The app:** decode both as optional (an older server without them keeps working), copy the updated samples into
     `Aresus/Aresus/Samples/`. The Empire app already has the opening rule (`ProvinceOpener`: the app's URL when iOS
     takes it, else the https website, else nothing). Move that rule into `Shared/` (for example
     `Shared/Navigation/ProvinceOpener.swift`, taking the app link and the website as strings) so Empire and Aresus use
     one copy; Empire keeps its coming-soon check and its behaviour, and its existing tests pass unchanged or move
     with the code. **Nothing in `Shared/` may use `UIApplication.shared`** (the Aresium widget compiles `Shared/`):
     the opener that really opens stays in each app target, or use SwiftUI's `OpenURLAction` with its completion.
   - **The row:** on the province's page, under the hero, one row "Open <name>" with `arrow.up.right`, built from the
     page's existing row look (the rows its sections already use), only when the province has an app link or a
     website, and never for Aresus's own page (slug `aresus`). If nothing opened (the app is not installed and there is
     no website), a muted line under the row: "<name> isn't on this iPhone." (the Empire app's wording).
3. **The gear on the Aresync tab** (list no. 22). `SyncScreen`'s header gets the same `GlassIconButton` gear as
   `WatchtowerScreen`'s, opening the same Settings sheet in the same way (find how the Aresus tab presents it and reuse
   that state, do not add a second sheet).

## Settled: do not re-open

- No new looks: Apple's controls, `Shared/Design` and Aresus's own pieces only.
- The links come from the server (the hub's data), never a table in the app.
- One opening rule for both apps, in `Shared/`.

## Out of scope

- `Shared/Design/AccountSheets.swift`, `Empire/Empire/Screens/EmpireSheets.swift` (brief 52), Arestemis,
  Arestoteles, Aresium. Deploying the aresus server (Claude deploys after the merge).
- `project.pbxproj`.

## API

- `GET /api/aresus/provinces/{slug}` (`aresus/docs/API.md`): two new optional fields, `url` (https string or null) and
  `app` (a URL scheme such as `"arestemis://"`, or null). Everything else unchanged.

## Done when

- aresus: `pytest -q` passes, with the new tests.
- This repo: `xcodebuild test` passes for **Aresus** and **Empire** on your own simulator (`codex-50`, commands in
  `AGENTS.md`), with tests for: decoding with and without the new fields, the shared opener's order (app, website,
  nothing) and Empire's coming-soon case.
- `scripts/strings.py sync` then `scripts/strings.py check`: 0 problems. Write the German yourself (du, short;
  Aresus's terms: Problem, Aktiv, Inaktiv), and keep it also in `build/50-de.json`.
- Looked at on the simulator in English and German, light and dark (`-sampleData`): screenshots `build/50-*.png` of
  the run sheet with its close button (`-openRun <id>`), a province page with Open (`-openProvince <slug>`), the
  Aresync tab's header with the gear (`-tab aresync`).

## Final message

As in `AGENTS.md`: files changed in both repos, the exact build and test summary lines, the screenshots' paths, the
German strings you added, what is missing or doubtful. Never commit, push or merge in either repo: Claude does.
