# 98: The packed local places list in the app, measured

Status: brief
Branch: `codex/98-local-places-packed-app` · Worktree: `../empire-ios-98-local-places-packed-app` · Model:
`gpt-6.1-sol`, effort `high` · Simulator: `codex-98` (create it: iPhone 17, iOS 27.0) · Needs aresium at `eadfc47` or
later (brief 97).

## Goal

Brief 95 measured the local places list (OpenStreetMap, aresium brief 86) in the app as JSON: about 103 MB more memory,
over the 60 MB budget, so nothing was adopted. Aresium brief 97 made a **packed format** (`~/aresium/data/local-places/
de.places.bin.gz`, 3.3 MB; 9.8 MB unpacked) that the engine searches in place: in Node it costs about 76 KB of heap plus
the buffer itself, with exactly the JSON list's answers (also on Patrik's data). This brief brings the packed list into
phone mode's sorting **if the app's own measurement stays within budget**.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Aresium phone mode": the engine in JavaScriptCore, `AresiumEngine`, `bundledForPhone`,
  `PhoneBackend`'s sorting, the picker's dry runs, Settings → About → Fonts & licences and `BundledLicence`; and "Local
  places memory gate (brief 95)" with its harness `LocalPlacesMeasurementTests` and `scripts/95-local-places-measure.sh`).
- `~/aresium/data/local-places/README.md` (the packed layout, **the host instructions**: inflate natively, wrap the bytes
  with JavaScriptCore's no-copy `ArrayBuffer`, `AresiumEngine.setLocalPlaces(buffer)` once, sorts pass
  `localPlaces: true`, `setLocalPlaces(null)` to clear), `PACKED-REPORT.md`, `~/aresium/src/engine/sorting/local-places.ts`.

## Build

1. **The engine and the list reach the app:** `scripts/aresium-engine.sh` copies the engine (with brief 96's round 3
   and brief 97) and also `de.places.bin.gz` and its licence note into the app's resources. Run it from `~/aresium`'s
   main.
2. **Measure first** with brief 95's harness, extended for the packed list (Release, three fresh processes,
   `phys_footprint`): before loading, loaded, after `setLocalPlaces(null)` and garbage collection, and today's engine as
   the control; the time to read, inflate and hand it over; a sort of 1,250 and 5,000 made-up payments with and
   without it. **Budget:** loaded at most 25 MB above the control → keep it loaded for the engine's lifetime; 25 to 60
   MB → load it only around sorting work and clear it after a quiet minute, on going to the background and on a
   memory warning; over 60 MB, or more than 5 MB left after clearing: stop, change nothing else, report.
3. **Load it the light way** (within budget): read and inflate off the main thread (Compression framework or zlib),
   keep the bytes in native memory the context references without copying (the no-copy `ArrayBuffer` through the
   context's `JSGlobalContextRef`, with a deallocator that frees them), call `setLocalPlaces` once, and pass
   `localPlaces: true` in phone mode's sorting calls (import, `sort`, `categoryCounts` and the picker's dry runs,
   anything that calls the engine's sorting). The tour's store too. Server mode never.
4. **The person's choices win:** learning and the structural rules stay first (the engine's order); a test with a
   learned shop whose name is in the list proves it in the app.
5. **The licence** (ODbL): Settings → About → Fonts & licences gets an entry in the shop list's look
   (`BundledLicence`): "Local places · © OpenStreetMap contributors", the ODbL, a link to
   openstreetmap.org/copyright, and where the list can be downloaded,
   `https://aresium.de/osm/local-places-de.places.bin.gz` (Claude puts the file there). German in the catalog.
6. **Tests:** a small packed fixture list built by aresium's packer (not the 3.3 MB file) sorts a made-up payment at a
   listed place; clearing and loading again work; server mode passes nothing; learning wins; the licence entry exists;
   the existing tests pass (the engine's round 3 may change sample expectations: update them only where the new engine
   sorts something it did not before, and say which).

## Settled: do not re-open

- Measure first; the budget decides.
- The list never leaves the phone; nothing about payments is sent.
- The person's own choices always win.

## Out of scope

- The list's contents and format (aresium), server mode, other screens.

## Done when

- The measurements are in the final message and in `CLAUDE.md` (beside brief 95's).
- Within budget: `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS
  Simulator,name=codex-98' -derivedDataPath build/DerivedData` passes, `scripts/strings.py check` says 0 problems,
  screenshots of the licence entry (`build/98-licence-*.png`, German and English), `CLAUDE.md` updated.

## Final message

As in `AGENTS.md`: files changed, the measurements, the exact build and test summary lines, anything doubtful. Never
commit, push or merge: Claude does.
