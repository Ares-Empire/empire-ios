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
| T: Arestemis server (API, hunts, AI check, places) | Claude subagent | `~/wt/Arestemis-api` (`app-api`) | running since 04:20 |
| S: Aresus server + Aresync reports | Claude subagent | `~/wt/aresus-server` (`server`), `~/wt/aresync-report` (`report`) | running since 04:20 |
| A1: Arestemis iOS app | Claude subagent | `~/wt/empire-ios-arestemis` (`arestemis-app`) | running since 04:29 |
| A2: Aresus iOS app | Claude subagent | `~/wt/empire-ios-aresus` (`aresus-app`) | running since 04:29 |
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
- [ ] 8. Review + merge T. Server move `/root/flatsniper` → `/root/Arestemis`, `arestemis.service`, Caddy route,
      Groq model, delete old config/db, live test with the test account.
- [ ] 9. Review + merge S. Deploy aresus (`aresus.service`), Caddy route, machine tokens (Mac, server), Aresync report
      on Mac + server, server Aresync REPOS + hooks.
- [ ] 10. Review A1, A2 on the simulator (screenshots), design polish, wire Shared/Push, live login with the test
      account, `simctl push` tests.
- [ ] 11. Hub: ~~app schemes~~ (done 04:30: `APP_SCHEMES` in webauth/server.py, live; Empire Info.plist queries), chronicle lines, EMPIRE.md connections,
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
