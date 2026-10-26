# 10: Aresium engine test run (M5): the server's code inside the app

Status: merged 2026-10-26 (one engine confirmed: exact results; JIT off: 11 ms for 5,000 payments, 0.43 s for 5,000 CSV rows on the simulator)
Branches: `codex/10-engine-test-run` in both repos · Worktrees: `../empire-ios-10-engine-test-run` and
`~/aresium-10-engine-test-run` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Decide by measurement whether the iPhone app can run Aresium's own TypeScript logic (the dashboard and the bank-file
readers) in JavaScriptCore, Apple's built-in JavaScript engine, and get exactly the server's results, fast enough.
This is measurement M5 of `~/ares-empire/docs/ARESIUM-FOR-OTHERS.md` (read "1. One app, two modes" and "D1"): if it
works, one engine serves both the server (Patrik) and phone mode (everyone else). Nothing in the app's screens changes.

## Read first

- `AGENTS.md`, `CLAUDE.md` of empire-ios (rules apply in full; the exception for the second repo is below).
- `~/ares-empire/docs/ARESIUM-FOR-OTHERS.md` → "1. One app, two modes", "Decisions" → D1, "Measurements" → M5.
- aresium: `src/data/dashboard.ts` (`buildDashboard`, already pure), `src/data/sample-source.ts`,
  `scripts/build-sample.ts`, `src/import/vrbank-csv.ts`, `camt.ts`, `paypal-csv.ts`, `util.ts`, `types.ts`,
  `errors.ts`, `package.json` (tests: `npm test`, `tsx --test`).
- empire-ios: `scripts/aresium-fixtures.mjs`, `Aresium/AresiumTests/server-dashboard.sample.json` and the tests that
  use it (`ServerSampleMatchesWebsiteTests`).

## Build

**In the aresium worktree** (`~/aresium-10-engine-test-run`; you may run `npm ci` and
`npm install --save-dev esbuild` there, the npm registry is the only network you may use):

1. **`src/import/sha1.ts`:** a small pure-TypeScript SHA-1 over UTF-8 text, returning lowercase hex, identical to
   `createHash("sha1").update(text).digest("hex")`. Replace `node:crypto` in `vrbank-csv.ts` and `camt.ts` with it.
   Test it against `node:crypto` on ASCII, umlauts, emoji, empty and long text. The ids of existing transactions must
   not change: the same input must give the same `externalId` as before.
2. **`src/engine/index.ts`:** the engine's one entry, pure functions only: `buildDashboard(source)`,
   `parseVrBankCsv(text)`, `parseCamt(text)`, `parsePaypalCsv(text)`, and `version`. Dates cross the boundary as
   ISO strings (say so in a comment if a parser returns `Date` objects; convert in a thin wrapper, don't change the
   parsers' return types for the server).
3. **`scripts/build-engine.ts`** (`npm run engine`): esbuild bundles the entry into one file,
   `dist/aresium-engine.js`, an IIFE that sets `globalThis.AresiumEngine`, target ES2020, no Node built-ins (the build
   fails if one is imported). Also write `dist/dashboard.sample-source.json` (`buildSampleSource()` as JSON).
4. **`src/engine/engine.test.ts`:** the bundle, loaded with `node:vm` in an empty context (no `require`, no
   `process`), gives the same output as the direct imports for: the sample source's dashboard; each parser on a made-up
   file (write one per format under `src/engine/fixtures/`, with real header lines and formats but invented payments,
   umlauts included).
5. **Timing source:** `scripts/build-engine.ts` also writes `dist/timing-source-5000.json` (a made-up source with
   5,000 transactions over 24 months, built deterministically from the sample's categories) and
   `dist/timing-vr-5000.csv` (5,000 made-up VR Bank CSV rows).

**In the empire-ios worktree:**

6. Copy `aresium-engine.js`, `dashboard.sample-source.json`, `timing-source-5000.json`, `timing-vr-5000.csv` and the
   made-up parser files into `Aresium/AresiumTests/Engine/` (test resources only; nothing in the app target).
7. **`Aresium/AresiumTests/EngineTests.swift`** (Swift Testing): load the bundle into a `JSContext`
   (JavaScriptCore), surface JS exceptions as test failures, and check:
   - `buildDashboard(sample source)` equals `server-dashboard.sample.json` (compare parsed JSON, numbers exact);
   - the dashboard decodes into the app's own `Dashboard` type;
   - each parser's result for the made-up files equals what Node gives (write Node's answers next to the files in
     step 4 and copy them too);
   - timings (median of 5, reported with `print` and in your final message): bundle load; dashboard for the sample, for
     1,246 transactions (take the first 1,246 of the timing source) and for 5,000; parsing the 5,000-row CSV.
8. **Without the fast mode:** apps on an iPhone get JavaScriptCore without its JIT compiler. Run the timing test a
   second time with JIT switched off (try `TEST_RUNNER_JSC_useJIT=false`, which passes `JSC_useJIT=false` to the test
   runner, and check it took effect, e.g. by a clear slowdown or JSC's own option dump); report both sets of numbers
   and say whether switching it off worked.

## Settled: do not re-open

- TypeScript stays the source; the bundle is generated, never edited by hand. No rewrite of the logic in Swift.
- esbuild for bundling (a dev dependency of aresium only); no other new packages anywhere.
- Tests only on the app side: no change to the Aresium app target, its screens or `project.pbxproj` (the tests
  folder is folder-synchronized).
- The server's behaviour stays the same: `npm test` and `npm run typecheck` pass, ids unchanged.

## Out of scope

- Phone storage, imports in the app, categories, sorting: later briefs.
- Refactoring `queries.ts` (database code) into the engine.

## API

None (no network calls).

## Done when

- aresium: `npm run typecheck`, `npm test` (including the new tests) and `npm run engine` pass in the worktree.
- empire-ios: `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium` passes on your own simulator
  (`-parallel-testing-enabled NO`), the new `EngineTests` included, and the timing numbers are in your final message.

## Final message

As in `AGENTS.md`: files changed in each repo, the exact build and test summary lines, the timing table (JIT on and
off, and whether off worked), the bundle's size, and anything that differed between Node and JavaScriptCore.
