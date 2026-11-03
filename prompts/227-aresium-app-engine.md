# 227: The Aresium app on the shared engine: balances and fixed costs

Status: merged 2026-11-03, build 21 (831 tests on Claude's run; the balance line Codex added was removed in round 2; engine a9e2cc6). On the phone: balances, fixed costs, marks.
Branch: `codex/227-app-engine` · Worktree: `../empire-ios-227-app-engine` · Model: `gpt-6.1-sol`, effort `high` ·
Simulator: `codex-227` (create it as `AGENTS.md` says)

## Goal

The app runs the shared engine (bundled from `aresium`, through JavaScriptCore). On 2026-11-03 the engine got two
things the app does not use yet: balances calculated per account from each day's booking chain (brief 223; the old
ones were wrong) and fixed costs with the monthly average (ported from the app's Swift in brief 218). After this
brief the app shows the corrected balances, takes fixed costs and the monthly average from the engine, and the
Swift copy (`Model/FixedCosts.swift`, `Model/FixedCostLedger.swift`) is deleted, so one copy remains.

## Read first

`AGENTS.md`, `CLAUDE.md` (the Aresium sections, "Monthly average and fixed costs"), `~/aresium/docs/BALANCE-CHECK.md`
→ iPhone handoff, `~/aresium/src/engine/fixed-costs.ts` and `balances.ts`, briefs 208, 216, 217, 218 and 223 here,
`Aresium/Aresium/Model/AresiumEngine.swift`, the two Swift files above and their tests.

## Build

1. **The new bundle:** `~/aresium/dist/aresium-engine.js` (Claude built it from `aresium` main `aaf3443`) into the
   app's engine resource.
2. **Balances:** pass each payment's stable `accountId` into the engine's source; the balance decoders accept `null`
   (`openingBalance`, `balanceByDay`, `dayBalance`, `endBalance`, `overview.balance`) and the charts keep gaps.
3. **Fixed costs from the engine:** the screens of brief 209 stay exactly as they are; only their data comes from the
   engine. **"Not fixed" marks already stored on the owner's phone must keep working:** if the engine's mark ids
   differ from the Swift ones, migrate the stored marks once, with a test.
4. **Same results, then delete:** run every case of `FixedCostsTests`, `FixedCostLedgerTests` and
   `FixedCostScreensTests` through the Swift code and the engine and show identical results; then delete the Swift
   copy and move the tests onto the engine path.
5. **Server sample fixtures:** update `AresiumTests/server-dashboard.sample.json` and its `.expected.json` as
   `CLAUDE.md` describes, since `/api/data` grew in brief 218.

## Settled

- No change to how any screen looks. No TestFlight upload (Claude does it). Do not touch `~/aresium`.
- Readable code in the existing style.

## Done when

`xcodebuild test` passes on `codex-227`, with the tests above. Screenshots of the overview (with the balance line)
and the fixed costs page on the made-up tour data: `build/227-overview.png`, `build/227-fixed-costs.png`.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the mark migration (needed or not), what
Claude must check on the phone, anything doubtful.
