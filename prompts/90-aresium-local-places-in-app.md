# 90: The local places list in the app: measure memory first, then use it

Status: brief
Branch: `codex/90-local-places-app` · Worktree: `../empire-ios-90-local-places-app` · Model: `gpt-6.1-sol`, effort
`high` · Simulator: `codex-90` (create it: iPhone 17, iOS 27.0) · Needs aresium at `b04ff9b` or later (brief 86).

## Goal

Aresium brief 86 built a list of Germany's local places from OpenStreetMap (`~/aresium/data/local-places/de.json.gz`,
264,744 places, 3.4 MB compressed, 10.5 MB as JSON) and an optional engine input for it (`sortPayments(payments, {
categories, learned, localPlaces })`). For places in the list it sorts 437 of 500 right instead of 187, with no more
wrong answers; on Patrik's own data 5 more payments sort, all as he has them. Patrik (2026-11-01): "yes lets do that"
(measure what it costs on the phone, then decide).

What is not known: **how much memory the list takes on the iPhone** once it is unpacked and parsed inside the
engine's JavaScriptCore context, and how to load it so the app stays light. This brief measures that first and, if it
fits the budget below, uses the list in phone mode's sorting.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Aresium phone mode": the engine in JavaScriptCore, `AresiumEngine`, `bundledForPhone` made
  off the main thread, `PhoneBackend`'s sorting (`sort`, `categoryCounts`, the import), the picker's dry runs, Settings →
  About → Fonts & licences and `BundledLicence`), `scripts/aresium-engine.sh` (how the engine reaches the app).
- `~/aresium/data/local-places/README.md` and `REPORT.md`, `~/aresium/src/engine/sorting/local-places.ts`,
  `~/aresium/src/engine/sorting/sort.ts` (where `localPlaces` is used), `~/aresium/scripts/local-places-timing.swift`
  (brief 86's simulator start-time harness).

## Build

1. **Measure** on the simulator (and say how; Instruments' Allocations or `task_vm_info`'s `phys_footprint` before and
   after, several runs, release build if you can):
   - the app's memory with the engine as today, with the list loaded into the engine's context, and after the list is
     released again (the context's references dropped and JavaScriptCore's garbage collection run);
   - the time to load it (read, gunzip, parse in JavaScriptCore) and a `sortPayments` call over 1,250 and 5,000 made-up
     payments with and without the list.
   **Budget:** while loaded, at most 60 MB more than today; after release, back within 5 MB of today. If loading it
   for good stays under 25 MB more, keep it loaded; between 25 and 60, load it only while sorting (see 2). Over 60 MB:
   stop here, change nothing in the app, and report what a smaller format would need (for example a sorted string table
   searched in place instead of JSON objects, in aresium; say what you would change).
2. **Load it the light way** (only if the budget holds): the compressed list as a resource of the app (copied by
   `scripts/aresium-engine.sh` with its licence file, like the engine), read and unpacked off the main thread inside the
   ledger's or engine's own work, kept in the engine's context while sorting work happens (an import, the picker's
   counts and dry runs, the category changes that sort) and released after a quiet minute, on going to the background
   and on a memory warning. The engine bridge passes it to `sortPayments` without copying the 10 MB across the bridge
   on every call (a global in the context set once per load, for example). Phone mode only; the tour's store uses it too.
3. **Learning stays first:** a person's own choices and the structural rules always win over the list (the engine's
   order already does this; a test in the app proves it with a learned shop whose name is also in the list).
4. **The licence** (OpenStreetMap's ODbL): Settings → About → Fonts & licences gets an entry for the list, in the same
   look as the shop list's (`BundledLicence`): "Local places: © OpenStreetMap contributors", the ODbL's name, a link to
   openstreetmap.org/copyright, and a link to where the list itself can be downloaded:
   `https://aresium.de/osm/local-places-de.json.gz` (Claude puts the file there). German in the catalog.
5. **Tests** (the app): the list loads and sorts a made-up payment at a place in the list (a small test fixture list,
   not the 3.4 MB file, unless the real one is cheap enough in tests), release and reload work, nothing changes in
   server mode, learning wins, the licence entry exists. The existing tests pass.

## Settled: do not re-open

- Measure first; the budget decides; over budget nothing changes in the app.
- The person's own choices always win over the list.
- The list never leaves the phone and is never sent anywhere; nothing about payments is sent.

## Out of scope

- Making the list smaller in aresium (only describe it if the budget fails), the list's contents, server mode.

## Done when

- The measurements (memory and times, with and without, how measured) are in the final message and in a short
  section of `CLAUDE.md`.
- If within budget: `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS
  Simulator,name=codex-90' -derivedDataPath build/DerivedData` passes, `scripts/strings.py check` says 0 problems, a
  screenshot of the licence entry (`build/90-licence-*.png`, German and English), and `CLAUDE.md` updated.

## Final message

As in `AGENTS.md`: files changed, the measurements, the exact build and test summary lines, anything doubtful. Never
commit, push or merge: Claude does.
