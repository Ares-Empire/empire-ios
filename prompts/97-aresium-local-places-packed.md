# 97: The local places list in a packed format

Status: brief
Repo: **aresium** · Worktree: `../aresium-97-local-places-packed` (branch `codex/97-local-places-packed`) · Model:
`gpt-6.1-sol`, effort `high`

## Goal

Brief 86 built a list of Germany's local places from OpenStreetMap (264,744 places, 223,550 names) that sorts far more
local payments right (known places: 187 → 437 of 500, wrong unchanged). Brief 95 (empire-ios) measured it in the app:
as JSON parsed into JavaScriptCore it adds **about 103 MB** of memory (budget 60), and the process stays about 120 MB
higher even after the list is released (`~/empire-ios/CLAUDE.md` → "Local places memory gate (brief 95)").

Make the same list usable at **about its own size in memory**: one packed binary block searched in place through
typed arrays, with no JavaScript object per place or name, giving **exactly the same matches** as today's JSON list.

## Read first

- `AGENTS.md`, `data/local-places/README.md` and `REPORT.md`, `src/engine/sorting/local-places.ts` (the data type and
  `findLocalPlace`), `src/engine/sorting/towns.ts` (brief 96's town comparison), `scripts/build-local-places.ts`,
  `scripts/local-places-build.ts`, `scripts/eval-local-places.ts`, `src/engine/local-places.test.ts`, and brief 95's
  measurement in `~/empire-ios/CLAUDE.md` and `~/empire-ios/scripts/95-local-places-measure.sh` (how the app will load it).

## Build

1. **The packed format** (written by the list's build next to the JSON, e.g. `data/local-places/de.places.bin` and
   its `.gz`; the repo keeps the compressed one, as for the JSON): one byte buffer holding a header (format version,
   counts, the data date, section offsets), the normalised names as sorted UTF-8 with an offsets column, a category
   code per name, the town matches for ambiguous names (sorted name → town → category), the town names table, and the
   category ids. Integers as `Uint32Array`/`Uint16Array`/`Uint8Array` views on the same buffer; little endian; aligned.
   Document the layout in the README.
2. **The engine reads it in place:** `localPlaces` accepts either today's JSON object or the packed buffer
   (`ArrayBuffer` or `Uint8Array`); a small index object holds only the typed-array views and searches by binary search
   over the UTF-8 bytes (no string per entry, no decoding the whole table). Only the engine's own code; no Node built-in
   (the bundle runs in JavaScriptCore). The JSON path may stay for the evaluation tools.
3. **The same answers:** for every name and every town match in the list, the packed lookup equals the JSON lookup
   (a test over the whole list, run by `npm test` if it is fast enough, otherwise a script Claude runs; say which); the
   test set with the left-out list, the known-places sample (`npm run eval:local-places`) and Patrik's data (Claude)
   give identical numbers.
4. **Measured** (Node, as the scripts do, and say how): the packed file's size raw and gzip, the time to load it into
   the index, and memory: `process.memoryUsage()` (heap and `arrayBuffers`) with the JSON list against the packed one,
   after garbage collection (`--expose-gc`). Target: the packed index costs at most its buffer plus a few hundred KB.
   Also the lookup time per payment.
5. **For the app** (the next brief, empire-ios): say exactly how a native host should hand the buffer to the engine
   without copying it into JavaScript strings (JavaScriptCore can wrap native bytes as an `ArrayBuffer`); provide the
   engine function the host calls (for example `setLocalPlaces(buffer)` holding the index in the engine, and
   `sortPayments` using it when its option is `true`), so the 10 MB never crosses the bridge per call.

## Settled: do not re-open

- Identical matches to brief 86's list; no change to its contents or rules.
- Off by default; the app is the next brief.

## Out of scope

- The app; the list's contents; other sources.

## Done when

- `npm run typecheck`, `npm test`, `npm run engine` pass; the packed format has tests (round trip, lookups, ambiguous
  names with towns, a corrupt or wrong-version buffer refused with a clear error, the equality over the whole list).
- The final message has the measurements of item 4 and the host instructions of item 5.

## Final message

As in `AGENTS.md`: files changed, the exact check results, the measurements, anything doubtful. Never commit, push or
merge: Claude does.
