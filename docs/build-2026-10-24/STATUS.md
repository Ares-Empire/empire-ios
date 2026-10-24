# Build 2026-10-24: Arestemis app, Aresus app (+ Aresync), Empire push

Patrik is away; Claude runs this with Claude subagents (no Codex this time: Patrik's Codex runs elsewhere). The
heartbeat (cron, :07 and :32) reads this file and continues from the first open step. Keep it current.

**Decisions:** `ares-empire/docs/ARESTEMIS-APP.md`, `ARESUS-APP.md`, `PUSH.md`. **Contracts:** `Arestemis/docs/API.md`,
`aresus/docs/API.md`, `ares-empire/docs/PUSH.md`. **Briefs:** `briefs/` next to this file.

**Patrik's rules for this build (2026-10-24):** UI and design are the point: classy, clean, in the style of the
existing sites and apps without copying them. One accent colour per app, truly only as an accent (Arestemis moonlight
violet, Aresus lightning blue); red is the special mode, not needed now. Existing apps may change but must not look
worse. Good code structure. No websites for these apps (SwiftUI only). Old flat search deleted, no backups now, auto
deploy via Aresync approved, schedules: my call (frequent is fine where it costs nothing). Don't scope Arescribe.
Stop only for a genuine problem.

**Logins for testing:** see memory `empire-test-logins` (Keychain items `empire-test-account`,
`empire-accounts-superuser`). Never write passwords into files.

## Agents and worktrees (never work in the main checkouts: Aresync auto-commits them)

| Package | Agent | Worktree (branch) | State |
|---|---|---|---|
| P: Empire push service + `Shared/Push` | Claude subagent | `~/wt/ares-empire-push` (`push`), `~/wt/empire-ios-push` (`push`) | merged + deployed (dry run) |
| T: Arestemis server (API, hunts, AI check, places) | Claude subagent | `~/wt/Arestemis-api` (`app-api`) | merged + deployed |
| S: Aresus server + Aresync reports | Claude subagent | `~/wt/aresus-server` (`server`), `~/wt/aresync-report` (`report`) | merged + deployed |
| A1: Arestemis iOS app | Claude subagent | `~/wt/empire-ios-arestemis` (`arestemis-app`) | merged, push wired |
| A2: Aresus iOS app | Claude subagent | `~/wt/empire-ios-aresus` (`aresus-app`) | merged, polished, push wired |
| D: Shared design kit, two Xcode projects, icons | me | `~/empire-ios` main (small commits) | done 04:28 |

## Steps

- [x] 1. Accounts: services `arestemis`, `aresus` (migration live 04:10, data copy `pb_data.before-services-20261024`);
      Claude superuser; test account has all four services.
- [x] 2. Decision records + contracts written.
- [x] 3. Commit docs; aresus repo initial commit; worktrees.
- [x] 4. Spawn P, T, S (background, 04:20). Their results arrive as task notifications; if the session restarted and they are gone, check each branch's commits and re-run what is missing.
- [x] 5. D: Shared/Design (+ move ProvinceMarks), Arestemis + Aresus projects (URL schemes, push entitlements), icons,
      sample JSON copied into the projects. Screenshot Empire + Aresium before/after if they switch to Shared/Design.
- [x] 6. Spawn A1, A2 (background, 04:29) with the design brief (`briefs/DESIGN.md`).
- [x] 7. Review + merge P (45 + 31 tests pass on my run). Deployed: `empire-push.service` (dry run, :8095/:8096),
      Caddy `/api/push/*` (backup `Caddyfile.bak-20261024-push`); register/unregister 204 with the test account, `/send`
      not reachable from outside. Code runs from `/opt/empire-push/push` → re-run `deploy/install-push.sh` after changes
      to `push/` (the ares-empire Aresync hook must do this). PushCenter wiring into the apps: step 10.
- [x] 8. Review + merge T (266 tests pass; ownership checks reviewed). Server move `/root/flatsniper` → `/root/Arestemis`, `arestemis.service`, Caddy route,
      Groq model, delete old config/db, live test with the test account. Done 05:08: `arestemis.service` from
      `/root/Arestemis` (fresh clone), `.env` from the old one + gpt-oss-120b + TELEGRAM_FALLBACK_USER=Patrik, Caddy
      `/api/arestemis/*` (backup `Caddyfile.bak-20261024-arestemis`), server Aresync REPOS + `hooks/Arestemis`,
      flatsniper.service removed. Live: places Germany-wide OK; TEST hunt id 1 on the test account started 05:08
      (München, broad) — **pause + delete it after checking matches**. `/root/flatsniper` still there: delete after.
- [x] 9. Review + merge S (107 + 32 + 7 tests pass on my run). Deploy aresus (`aresus.service`), Caddy route, machine tokens (Mac, server), Aresync report
      on Mac + server, server Aresync REPOS + hooks. Done: `aresus.service` live, Caddy `/api/aresus/*` (backup
      `Caddyfile.bak-20261024-aresus`), machine tokens Server + Aresium (token files `/root/.config/aresus-*-token.out`,
      600), server REPOS="ares-empire aresus aresync" + hooks ares-empire, aresus; both machines report. My fix:
      `hide: [arescope]` + Arestudy/AresOS/Aresify as Inactive. **Left:** add `Arestemis` to server REPOS + its hook
      after the move (step 8); Windows token when Patrik sets up the laptop; retire Aresync Telegram once push works.
- [x] 10. Review A1, A2 on the simulator (screenshots), design polish, wire Shared/Push, live login with the test
      account, `simctl push` tests.
- [x] 11. Hub: ~~app schemes~~ (done 04:30: `APP_SCHEMES` in webauth/server.py, live; Empire Info.plist queries), chronicle lines, EMPIRE.md connections,
      empire-ios README/CLAUDE.md, IPHONE-APPS.md.
- [ ] 12. Report for Patrik (what works, screenshots, what waits for Apple).

## Log

- 04:10 migration live. 04:14 superuser + test account services.
- 04:20 P, T, S started. Groq key in Keychain item `groq-api-key`.
- 04:28 Shared/Design (+ProvinceLogin), both projects, icons. Empire screenshot identical after moving marks.
- 04:29 A1, A2 started (simulators agent-arestemis, agent-aresus).
- 04:30 hub app schemes live. Test token helper: scratchpad `testtoken.sh <file>`.
- Caddy plan (apply per deploy, `caddy validate` first): inside `ares-empire.de, www.ares-empire.de` add
  `handle /api/push/* {reverse_proxy 127.0.0.1:8095}`, `/api/arestemis/*` → 8097, `/api/aresus/*` → 8098, and wrap the hub
  proxy in a final `handle { reverse_proxy 172.18.0.1:5185 }`.
- 04:33 heartbeat: no agent finished yet; P and S have uncommitted work in progress. (Times above corrected to git times.)
- 04:36 Patrik's real account (admin, id o3hbhzk8bo1352x) given services arestemis + aresus (his own apps); TELEGRAM_FALLBACK_USER candidate.
- push merged + deployed; merged-main build/test of the apps running in the background.
- merged main (push): Empire tests pass, Aresium (+widget), Arestemis, Aresus build.
- 04:56 S merged and deployed; Aresus overview live (1 issue = Arestemis not deployed yet, correct). Careful: a
  `config.bak` in ~/aresync is NOT git-ignored (Aresync would commit it with the Telegram token): deleted; never back
  up configs inside a synced repo.
- 05:05 A2 merged (48 tests pass). Live on the simulator with the test account (login written into the shared Keychain
  with the Empire SharedLoginProbe test + scratchpad `testtoken.sh`; see below). Polish: inactive provinces as slim
  rows, issue lines wrap; Aresus checks.yaml: readable check names, shorter lines. PushCenter wired into Aresus
  (permission prompt shows after login). Live login on a simulator:
  `TEST_RUNNER_SHARED_LOGIN_PROBE=write TEST_RUNNER_SHARED_LOGIN_PROBE_TOKEN="$(cat tok)" xcodebuild test -project
  Empire/Empire.xcodeproj -scheme Empire -destination id=<udid> -parallel-testing-enabled NO
  -only-testing:EmpireTests/SharedLoginProbe`.
- 05:08 Arestemis server live; test hunt running; Aresus sync-lock fix (66ffe12) deploying via Aresync.
- 05:12 Live test of Arestemis (test hunt id 1, München broad): pipeline works (seed 113, scan: 10 read, 4 AI-checked,
  2 matches, 1 rejected). Found + fixed (e02c620): 10 m² WG rooms passed 'sqm_min 15' → new `room_sqm_min` (contract
  addition), AI prompt: numbers are HARD LIMITS (fail, never pass with a warning), Groq 429 → fallback model
  gpt-oss-20b. A1 told about room_sqm_min. Background check reports 10 min of results after the deploy.
- 05:10 Aresus sync-lock fix confirmed: deploy run had no failed pull.
- 05:27 10 min under the new rules: 13 matches, all rooms ≥ 15 m², AI checked every candidate, no 429 errors. Test hunt PAUSED (kept: real matches for the app review with the test account). Note for the app: 'About you' caption should suggest gender + age (listings restrict on them).
- 05:30 A1 merged (77 tests pass), push wired into Arestemis, 'About you' asks for gender + age; live with the test
  account (28 real matches). /root/flatsniper deleted, worktrees + agent simulators removed. EMPIRE.md chronicle,
  connections, decision records, IPHONE-APPS, PUSH status, empire-ios CLAUDE.md 'Open' updated. Final regression run
  (Aresium + Empire tests) and hub data refresh running. Next: step 12, the report for Patrik.
