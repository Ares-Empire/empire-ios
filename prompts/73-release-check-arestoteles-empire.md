# 73: Arestoteles and the Empire app: ready for the iPhone? (review)

Status: running
Worktree: `~/empire-ios-73-review` (detached at `main`, read-only) · Model: `gpt-6.1-sol`, effort `high`, `-s read-only`

## Goal

Arestoteles and the Empire app go to Patrik's iPhone for the first time: a Release build, App Store signing, internal
TestFlight, a real device. Until now they ran only on the simulator in Debug. Find what works there but would break,
or behave differently, on the phone. **Report only: change no file.**

Arestemis and Aresus already run on the phone from the same repo and the same `Shared/` code, with the shared login,
push and widgets working. So any way Arestoteles or the Empire app differs from them in setup is the first suspect.

## Read first

- `AGENTS.md`, `CLAUDE.md` (Setup state, One login for all apps, App switcher cover), `README.md` → Releasing
- `docs/APP-STORE.md` (privacy manifests, encryption)
- `scripts/testflight.sh` (how the upload is made)
- `~/ares-empire/docs/PUSH.md` and the push service in `~/ares-empire/push/` (read only)
- `~/ares-empire/docs/ARESTOTELES-APP.md`, `~/ares-empire/docs/EMPIRE-APP.md`

## Check

1. **Setup compared with Arestemis and Aresus:** Info.plist, entitlements, and the Release build settings in each
   `project.pbxproj` (team, bundle id, version and build number, `INFOPLIST_KEY_*`, `CODE_SIGN_*`,
   `DEVELOPMENT_ASSET_PATHS`, capabilities). List every difference and say whether it matters on the phone.
2. **Release versus Debug:** anything the app needs that sits behind `#if DEBUG` (server addresses, sample data,
   launch arguments); DEBUG-only paths reachable in Release; `Preview Content` or samples shipped in the Release bundle.
3. **Links between apps:** the URL schemes the Empire app opens (`aresium://` and the others) against
   `LSApplicationQueriesSchemes`, and each province app's own registered scheme (Arestoteles's especially). Any
   universal link or `https` hand-off (Arestoteles's Discuss: `DiscussPrompt.target`) and what it does on a device.
4. **Push in the Empire app:** permission, registration and sending the device token to the push service, compared
   step by step with Arestemis (which works on the phone). Which APNs environment the service uses for a TestFlight
   build's token, and whether the Empire app's `aps-environment` (`development` in the file) is changed to
   production by App Store signing as it was for Arestemis. Does Arestoteles ask for notifications at all?
5. **Network and storage:** every server address in Release is https and points at production; no ATS exceptions
   needed. Where Arestoteles keeps its saved vault (Caches or Application Support, excluded from backup or not) and
   anything else written to disk that a device would treat differently from the simulator.
6. **Privacy manifests and Info.plist keys** in both apps match `docs/APP-STORE.md`; every permission the app can ask
   for has its usage description; `ITSAppUsesNonExemptEncryption` is set.
7. Anything else you find that an upload would refuse or that would break on the phone.

## Out of scope

- The look of any screen, and the Arestoteles bust and icon (brief 72 replaces them).
- Aresium, Arestemis, Aresus as subjects (only as the comparison).
- Changing, building or running anything; the read-only sandbox cannot run `xcodebuild` anyway.

## Final message

Findings ordered: **blocker** (the upload is refused, or the app breaks on the phone), **fix before upload**,
**later**. Each with `file:line`, the evidence, and the fix in one sentence. Then one line per check above that you
found fine. Say plainly where you are guessing.
