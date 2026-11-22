# Local places memory gates (briefs 95 and 98, 2026-11-01)

Codex's two measurement reports, moved out of `CLAUDE.md` on 2026-11-22. Brief 95's result (over budget, stopped) was superseded by brief 98's (adopted, kept loaded). Paths are relative to the home folder.

## Local places memory gate (brief 95, 2026-11-01)

**Over budget; app integration stopped.** The shipped engine, resources, sorting and licence UI are unchanged.
Measured on `codex-95`, iPhone 17 (`iPhone18,3`), iOS 27.0 / 24A434, Apple M5 / 16 GB. These are simulator
app-hosted measurements with a fresh `AresiumEngine` on a worker, Release `-O`, no `DEBUG`, and
`task_vm_info.phys_footprint` (decimal MB); physical-device memory remains unmeasured. Three independent candidate
processes used aresium `b04ff9b`; the separate control used today's shipped engine, `400754e5`.

| Candidate process | Before loading, MB | Loaded after GC, MB | Added, MB | Released after sorting and 10 s, MB |
|---|---:|---:|---:|---:|
| 1 | 114.61 | 217.83 | 103.22 | 240.85 |
| 2 | 115.89 | 219.68 | 103.79 | 239.72 |
| 3 | 114.79 | 218.07 | 103.28 | 242.91 |

Today's no-list control: **116.66 MB** initially, **120.39 MB** after the same number of sorts and 10 s of GC.
After each load, temporary native data/strings leave an autorelease pool, then three `JSGarbageCollect` calls run
and 250 ms elapse. After sorting, the context's list global is set to `undefined` and checked, GC runs three times
immediately and after each of ten one-second waits. The release figures are process footprint, including retained
VM/allocator pages; they do not prove a live-object leak. Both the +60 MB loaded and +5 MB released gates fail.

Loading the 3,428,315-byte gzip (10,503,935-byte JSON) took **100.45 ms median**, **90.68–155.39 ms** across the
three processes: read **0.96 ms**, gunzip plus UTF-8 **19.32 ms**, native string bridge plus JSC JSON parse
**83.41 ms** (component medians). File reads use the warm filesystem cache; this is not cold-launch timing.

| Fictional payments | Today's engine, no list | Candidate, no list | Candidate, with list |
|---|---:|---:|---:|
| 1,250 | 9.89 ms | 17.27 ms | 10.24 ms |
| 5,000 | 44.81 ms | 40.41 ms | 48.16 ms |

Sort medians include the string bridge, JSC input parsing, sorting, result JSON and Swift decoding; input JSON is
prepared beforehand. Three warmups per size precede sampling; five paired samples per size/variant/process
alternate order (15 each), with ten per size in the control. Timings vary with JIT/GC and simulator scheduling;
the 1,250-payment figures do not establish a speedup. Payments use fictional amounts and merchants plus REWE.

Reproduce with `bash scripts/95-local-places-measure.sh` after creating/booting the owned simulator. It builds the
candidate into `build/` using aresium's existing esbuild, reads the source repo only, runs one `xcodebuild test`
and three `test-without-building` calls, and exports diagnostics and result summaries. Existing tests depend on
DEBUG-only helpers, so this Release-only experiment excludes their sources via a command-line build setting;
the project file is untouched. **Four runs: one test each, zero failures** (`TEST SUCCEEDED`, then three
`TEST EXECUTE SUCCEEDED`). The full suite was not run; the initial full Release compilation failed on those
existing helpers. `python3 scripts/strings.py check`: **0 problem(s)**. No new UI strings or licence screenshots.
Raw results: `build/95-measure-final.log`, `build/95-20261101-215832-*.xcresult` and matching diagnostics;
gzip SHA-256: `6cf2685ffbd014173646f9bb3ba87ad59dc3cca64db04817c17025153faeba9b`.

Before another app attempt, change the format in aresium: a sorted UTF-8 name blob with offset tables and flat
integer category/town columns, exposed as typed arrays and searched in place. Give the builder and matcher the
same ordering; decode only a matched record, avoiding hundreds of thousands of nested JS arrays and strings.
Keep structural rules and learning first, preserve the existing matching safeguards, then remeasure the new format
against the same two memory gates. This format change is outside brief 95.
## Packed local places memory gate (brief 98, 2026-11-01)

**Adopted and kept loaded (Claude's clarified decision).** The loaded measurements are **12.40–13.68 MB** above
baseline, median **12.75 MB**, with about **93.90 ms once at the first phone engine's start**. The 5 MB release
limit applies only to the 25–60 MB tier that unloads after sorting, not this under-25 MB lifetime tier.
`scripts/aresium-engine.sh` refreshed the engine from aresium
`main` at `eadfc47e97b6241923f1c992a40826eb2f19582e` (briefs 96/97, 524,873 bytes), copied
`Engine/de.places.bin.gz` (3,281,615 bytes) and generated `Engine/local-places-licence.txt` from the packed
metadata. `bundledForPhone` makes the context off main, awaits native loading on `PackedLocalPlacesCache`'s serial
actor, and installs the actual no-copy buffer once through `AresiumEngine.setLocalPlaces`. The cache's weak entries
share the immutable 9,779,212-byte allocation across simultaneous phone/tour contexts; every JSC ArrayBuffer retains
its native owner independently. Once all contexts and callers release that owner, the allocation can be freed.
No clearing timer, background clearing or memory-warning clearing is installed. Each context still validates its own
views, but does not inflate or copy the shared data again. All phone import/sort/categoryCounts/picker dry-run paths
pass `localPlaces: true` at the two engine call sites in `PhonePickerWork.swift`. Other engine callers omit the option;
server mode uses its existing HTTP contract and never passes or loads the list.

Settings → About → Fonts & licences lists `BundledLicence.localPlaces()` alongside the shop list, with attribution,
ODbL 1.0 and links for copyright, the licence and `https://aresium.de/osm/local-places-de.places.bin.gz`. The five new
English strings and their German translations are in Aresium's own catalog; the shared licence page supports optional
link data with the same existing typography and colours.

Measured on the owned `codex-98`, iPhone 17 (`iPhone18,3`), iOS 27.0 / 24A434, Apple M5 / 16 GB. Release `-O`,
no `DEBUG`, app-hosted `task_vm_info.phys_footprint`, decimal MB. Three fresh candidate processes and a fourth
fresh no-list control all use the same refreshed engine. Physical-device memory remains unmeasured.

| Process | Initial, MB | Before load, MB | Loaded after GC, MB | Added, MB | Cleared after sorting + 10 s, MB | Retained from initial, MB |
|---|---:|---:|---:|---:|---:|---:|
| 1 | 118.92 | 119.69 | 133.37 | 13.68 | 163.06 | 44.14 |
| 2 | 131.65 | 132.01 | 144.76 | 12.75 | 164.68 | 33.03 |
| 3 | 119.64 | 119.62 | 132.03 | 12.40 | 162.14 | 42.50 |
| No-list control | 123.47 | — | — | — | 135.74 | 12.27 |

The loaded increment fits the 25 MB lifetime-loading tier. The initial implementation stopped because it treated
the release gate as universal; Claude clarified that the release gate applies only to the middle tier, and directed
adoption in the kept-loaded tier. The release experiment remains recorded: after subtracting the control's own
12.27 MB growth, candidates retain **31.87 / 20.76 / 30.23 MB** more, median **30.23 MB**. Absolute released
footprints are **27.31 / 28.93 / 26.39 MB** above control. These process-footprint results include retained
allocator/VM/JIT pages and the app host; they do not establish a live-object leak or confirm when the native
deallocator ran. Initial-footprint variation and the timing outlier limit precision. Release results do not gate
this adoption because normal engines keep the list for their lifetime. These measurements were captured before
production loading was enabled; no physical-device measurement or cold-launch timing is claimed.

Inflation reads the gzip trailer's exact size (9,779,212 bytes), validates it with zlib and writes directly into
one aligned native allocation. On the worker, `JSObjectMakeArrayBufferWithBytesNoCopy` wraps it; a retained owner
is released by the JSC deallocator, including on a C API exception. The actual protected buffer is passed through
`JSObjectCallAsFunction` to `AresiumEngine.setLocalPlaces`, with no list JSON/string/base64/number-array conversion.
The harness retains no host JSValue/global for the packed buffer. Loading temporaries leave scope, GC runs three
times and 250 ms elapse before the loaded snapshot. After the paired sorts, `setLocalPlaces(null)` clears the
installed list; GC runs three times immediately and after each of ten one-second waits, with snapshots at 1/5/10 s.
The control makes the same number of sorts and collections without loading the list.

| Loading | Median | Range across three processes |
|---|---:|---:|
| Read | 0.82 ms | 0.82–1.87 ms |
| Native inflate | 10.94 ms | 10.61–151.67 ms |
| No-copy handover + engine validation | 82.39 ms | 46.75–158.07 ms |
| Total | 93.90 ms | 58.59–311.67 ms |

Component medians need not sum to the total median. Reads use the warm filesystem cache, not cold-launch timing.

| Fictional payments | Current engine control, no list | Candidate, no list | Candidate, packed list |
|---|---:|---:|---:|
| 1,250 | 15.85 ms | 22.65 ms | 19.23 ms |
| 5,000 | 55.38 ms | 60.13 ms | 57.04 ms |

Sort medians include input string bridging/JSC parsing, sorting, result JSON and Swift decoding, with prebuilt
input JSON. The existing harness uses fictional merchants/amounts plus REWE, three warmups per size and five
paired samples per size/variant/process, alternating order (15 samples each); the control has ten samples per
size. These timings reflect this workload, GC/JIT and simulator scheduling, and do not establish a speedup.

Reproduction/check commands run from this worktree:

```sh
xcrun simctl create codex-98 'iPhone 17' com.apple.CoreSimulator.SimRuntime.iOS-27-0
bash scripts/aresium-engine.sh ~/aresium > build-engine-98.log 2>&1
mv build-engine-98.log build/98-engine.log
bash scripts/98-local-places-measure.sh > build/98-measure.log 2>&1
python3 scripts/strings.py check > build/98-strings-check.log 2>&1
git diff --check
xcrun simctl delete codex-98
```

The measurement script runs `xcodebuild test` once, then three `xcodebuild test-without-building` calls, with
`-project Aresium/Aresium.xcodeproj -scheme Aresium -configuration Release -destination
'platform=iOS Simulator,name=codex-98' -derivedDataPath build/DerivedData ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES
-parallel-testing-enabled NO -only-testing:AresiumTests/LocalPlacesMeasurementTests`, and excludes the other test
Swift sources via `EXCLUDED_SOURCE_FILE_NAMES` because their helpers require DEBUG (as in brief 95).
**Four runs: one test each, zero failures**: `TEST SUCCEEDED`, then three `TEST EXECUTE SUCCEEDED`.
Initial measurement checks: `python3 scripts/strings.py check`: **0 problem(s)**; `git diff --check`: pass.
The adoption's full-suite and screenshot checks are recorded below. No `TODO(api)`.
`PackedLocalPlacesTests` uses the small fictional fixture generated by aresium's packer through
`scripts/98-local-places-fixture.mjs`: actual no-copy backing address, opt-in and disabled categories, clear/reload,
concurrent native cache sharing, independent context clearing, corrupt gzip/packed replacement, phone import,
picker dry-run/counts, choosing/sorting, learning and structural precedence, server import contract isolation,
and the bilingual licence attribution/links.

Raw results: `build/98-measure.log`, `build/98-20261101-222124-{1,2,3,baseline}.xcresult`, matching diagnostics and
`*-summary.json`; condensed measurements in `build/98-measurements.json`.
Engine SHA-256: `64f25badb23afdf2913a321a80a1e74e64de0bd719064ba5d88b4fa620cb986e`.
Packed gzip SHA-256: `2ab7d4938cc2a35be9a46819d1cde71ce5aa5590f1f3c2a71072fff2660caab9`.

Adoption verification (same owned iPhone 17 / iOS 27.0 simulator):

```sh
node --import ~/aresium/node_modules/tsx/dist/loader.mjs scripts/98-local-places-fixture.mjs ~/aresium
TMPDIR="$PWD/build/tmp" python3 scripts/strings.py sync > build/98-strings-sync.log 2>&1
python3 scripts/strings.py fill build/98-de.json > build/98-strings-fill.log 2>&1
xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=codex-98' -derivedDataPath build/DerivedData > build/98-test-final.log 2>&1
python3 scripts/strings.py check > build/98-strings-check.log 2>&1
git diff --check
```

Final full-suite summary: **`TEST SUCCEEDED`**; **`Test run with 665 tests in 77 suites passed after 61.628 seconds.`**
The xcresult summary reports **665 total, 661 passed, 0 failed, 4 skipped** (772 passed including expanded parameter
cases in its device breakdown). The four skips are the opt-in shared-login probe, memory measurement and two timing
experiments. All seven new packed-list tests pass, including one native read/inflate off main, reuse after removing
the source fixture file, and the person's learned correction beating the listed category on a later import.
No existing sample expectations were changed for the refreshed engine. Two earlier full runs failed only in new
tests: one used the build before German was filled; the second compared serialized JSON bytes despite unordered
keys. The finished catalog and structural request-field assertions fix those failures; the final run passes.
`python3 scripts/strings.py check`: **0 problem(s)**. `git diff --check`: pass.

New catalog strings (English and German): “Local places · © OpenStreetMap contributors”, “Local places for sorting”,
“OpenStreetMap copyright and contributors”, “Open Database License (ODbL) 1.0”, and “Download the local places list”.
Unrelated catalog normalization by the all-project export was restored; only Aresium's five additions remain.

Screenshots: `build/98-licence-{en,de}-{dark,light}.png` (the entry) and
`build/98-licence-detail-{en,de}-{dark,light}.png` (the attribution/licence/download page), captured with the app's
existing sample launch arguments and visually inspected in both languages and appearances. The full command log
is `build/98-screenshot-commands.json`; capture waits for the actual licence text and the navigation transition.
The licence page retains the existing single-line navigation title, which truncates its long attribution title;
the list's two-line name and the page's attribution paragraph show the full attribution.

Final test artifacts: `build/98-test-final.log`, `build/98-test-summary.json`, `build/98-test-final-diagnostics` and
`build/DerivedData/Logs/Test/Test-Aresium-2026.11.01_22-35-57-+0100.xcresult` (see the log for the exact result path).
The public download URL is linked as requested; hosting it remains Claude's deployment step and was not checked
over the network. Physical-device memory remains unmeasured. No commit, push or merge; `codex-98` deleted after QA.
