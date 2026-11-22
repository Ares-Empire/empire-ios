# 319: Arestia's 3D page kept on the phone, checked before it is fetched again

Status: built on branch arestia-3d (Codex gpt-6.2-sol; Claude simplified the timing log), PR open
Branch: `arestia-3d` · Worktree: `~/empire-ios-arestia-3d` (shared with Claude, who works on the viewer page itself
elsewhere; don't touch files outside this brief's list) · Model: `gpt-6.2-sol`, effort `xhigh` (a bounded build from a
tight brief, but in the 3D tab's coordinator, whose load/handover/retire ordering went through nine review rounds:
xhigh for the concurrency, sol because the design is settled here and a fresh reviewer checks it after)

## Goal

The owner, 2026-11-20, after trying the 3D tab on his iPhone: "the flat model takes a while to load, can we improve
that?", and on the lead's suggestions: "keeping it loaded when switching tabs is smart. and copy on phone seems
sensible too". Today every load of the 3D tab downloads flatd's `GET /viewer` (8.2 MB) before anything shows. After
this brief the app keeps one copy of the page per pairing, shows it at once, checks flatd for a newer one in the
background with an ETag (a 304 costs nothing), swaps only when it changed, never reloads the page just because the
tab was switched, and reloads it cleanly (from the copy) when iOS ended WebKit's page process.

## Read first

- `AGENTS.md`, `CLAUDE.md` (the Arestia bullet), `docs/ARESTIA-APP.md` (the trust model: one flat per install, the
  page fetched through the pinned client and handed to the web view as data, Forget).
- `Arestia/Arestia/Screens/FlatScreen.swift` (the tab, `FlatPage`, `FlatWebView.Coordinator`: `load`, `fail`,
  `retire`, `PageHandover` use, `webViewWebContentProcessDidTerminate`).
- `Arestia/Arestia/Model/ViewerBridge.swift` (`PageMessage`, `PageScript`, `PageHandover`).
- `Arestia/ArestiaShared/FlatdClient.swift` (`viewerPage()`, `request`, `send`: how statuses map to `FlatdError`).
- `Arestia/Arestia/Model/FlatStore.swift`: only `FlatSession.forget()` (near the end) and `FlatStore.pageClient()`.
- `scripts/fake-flatd.py` (`/viewer`, `--viewer`).
- The tests in `Arestia/ArestiaTests/` that cover the page and the client (`ContractTests`, `ClientTests`,
  `ReviewRound*Tests`), for their style and fakes.

## Build

1. **`Arestia/Arestia/Model/ViewerPageCache.swift`** (new): the one kept copy of flatd's page.
   - Folder: `Application Support/ArestiaViewer/` in the app's own container (not the App Group: the Control Center
     extension never shows the page; not Caches). The folder is excluded from backups (`isExcludedFromBackup`): the
     page is the flat's private model and must not travel into a backup. The folder URL is injectable for tests.
   - Per pairing two files: `<pairing UUID>.html` (the page's bytes) and `<pairing UUID>.json` (meta: the pairing id,
     the pin's SPKI SHA-256 as flatd's identity, the ETag or null, the page's SHA-256 hex, its byte count, when saved).
   - Written atomically with `Data.WritingOptions.completeFileProtectionUntilFirstUserAuthentication` (both files; the
     same "readable after the first unlock" as the pairing's Keychain item). The page first, the meta last, so a meta
     never points at a half-written page.
   - `page(pairing: UUID, pin: <the pin type>) -> Kept?` returns the bytes, the ETag and the hash only when the meta's
     pairing id **and** pin match and the bytes' SHA-256 equals the meta's. Every other file in the folder (another
     pairing, a broken or mismatching pair) is deleted on that read. `save(_:etag:pairing:pin:)` does the same purge
     after writing. Pages over 32 MB are not kept (still shown). `removeAll()` deletes the folder.
   - File work runs off the main actor (8 MB reads and SHA-256s); the type is `Sendable` and safe to call from a
     detached task. CryptoKit for the hash.
   - Errors are logged (category `viewer`, no flat content in logs) and mean "no copy", never a failure of the tab.
2. **`FlatdClient`**: `viewerPage(ifNoneMatch: String?) async throws -> ViewerPage` with
   `enum ViewerPage { case unchanged; case page(Data, etag: String?) }`. Sends `If-None-Match` when given; 304 is
   `.unchanged` (not an error); 200 reads the `ETag` header as sent (keep the quotes; send it back exactly). Same
   pinned transport, same timeout. Keep `viewerPage()` working if anything still calls it, else replace it. Update
   its doc comment ("never bundled or kept" is no longer true: one copy per pairing is kept, see the decision record).
3. **`FlatWebView.Coordinator.load`** (FlatScreen.swift):
   - Resolve the client as now. Then read the copy for `store.pairingID` and the client's pin, off the main actor.
   - **A copy:** hand it to the web view at once, exactly as a fetched page is handed over now (the network fence
     `blockTheNetwork()` first, a new document through `PageHandover`, the 30 s `ready` deadline). Then check flatd in
     the background with `If-None-Match`: `.unchanged` → nothing (log it); `.page` with the same SHA-256 → save it
     (new ETag), no swap; `.page` with different bytes → save it and hand it over as a new document at once (rare:
     only after the viewer was rebuilt). A failed check while the copy is shown is logged only; the copy stays.
   - **No copy:** fetch as now (with the same error handling and calm card), save it, hand it over.
   - Keep every guarantee the coordinator has now: a newer load (Try again, a fresh code of the flat) or `retire()`
     cancels the read, the fetch and the check, and nothing of an older load is handed over or shown as a problem;
     only the newest document may speak; nothing runs for a retired store. Factor the "hand this HTML over as the new
     document" part into one function used by all three paths.
   - Record timings with `ContinuousClock` from the start of `load` and log them as `.notice` (public: numbers and
     these fixed words only): where the page came from (copy / flatd), its size, the read or download time, handed
     over, committed, `ready`; and the check's outcome and time. One line at `ready`, one when the check ends.
4. **Page process ended** (`webViewWebContentProcessDidTerminate`): reload cleanly, from the copy.
   - Count an automatic reload toward `maxAutomaticReloads` only when the page ended within 60 s of its load (a page
     that keeps ending WebKit while starting still ends in Try again after three). A page that lived longer (iOS took
     the memory back while the app was in the background) reloads without counting, and resets the count.
   - When the tab is not shown, or the app is not active, don't reload now: mark it and reload when the tab is shown
     again (pass `isShown` from `FlatScreen` into `FlatWebView`; `updateUIView` sees it change). Until then the tab
     shows the loading line, as now.
5. **Keep the page across tab switches.** The web view must not be torn down or reloaded when the user goes to Home
   and back. Check it: a DEBUG-only log line in `makeUIView` and `dismantleUIView` and at `ready`, then on the
   simulator switch tabs a few times with AXe and confirm `makeUIView` ran once and `ready` once. If SwiftUI's
   `TabView` does dismantle it, restructure so the web view lives on (say so and how in your final message).
6. **Page log levels** (`PageMessage`, BRIDGE.md v1 additions, already settled with the page):
   `{"v":1,"type":"log","level":"error"|"warn"|"info","message":"…","timing":{"html":412,"script":905,…}}`.
   `level` defaults to `error` when missing or unknown; `timing` is optional: an object of names (≤ 24, each ≤ 24
   characters of `[A-Za-z0-9_]`) to finite numbers (ms since the page started); anything else in it is dropped.
   Parse into `case log(level: PageLogLevel, text: String, timing: [String: Int])`. Log: `error` → `.error`,
   `warn` → `.notice`, `info` → `.info`, the text as now (public in DEBUG, private in Release); a non-empty `timing`
   additionally as one `.notice` line, public (only names and numbers), e.g. `page timing: html 412, script 905, …`
   in the page's order.
7. **`scripts/fake-flatd.py`**: `/viewer` answers like flatd (aiohttp's `FileResponse`): a quoted `ETag` (any stable
   value for the bytes, e.g. the first 16 hex of their SHA-256), `Cache-Control: no-store`, and `304` with no body when
   `If-None-Match` names it (or `*`). With `--viewer <file>`, read the file on every request (flatd does: the viewer
   is rebuilt in place), so a rebuild while the fake runs is served. Update its docstring.
8. **Forget** (`FlatSession.forget()` in FlatStore.swift, the only change in that file, because another branch edits
   it): after `connection.forget()` succeeded, `ViewerPageCache.live.removeAll()` (a failure is logged; the copy can't
   be shown anyway, since a read needs the same pairing id and pin). Keep the edit to a couple of lines.
9. **Tests** (`Arestia/ArestiaTests/ViewerPageCacheTests.swift`, and `PageMessage` cases next to the existing ones):
   save + read for a pairing; another pairing's copy is never returned and is deleted by the read; a different pin is
   never returned; a page whose bytes don't match the meta's hash is not returned and is deleted; `removeAll` empties
   it; a page over the limit is not kept; the folder is excluded from backups and the files carry
   `completeUntilFirstUserAuthentication` (read the attribute back; if the simulator doesn't report it, assert the
   writing options through a seam instead and say so). Client: `If-None-Match` is sent, 304 → `.unchanged`,
   200 → `.page` with the ETag (with the tests' fake transport). Log: levels, defaults, timing filtering.
10. **Docs**: in `docs/ARESTIA-APP.md`, a new decision bullet "**The 3D page is kept on the phone**" (2026-11-20,
    the owner's words above) next to "The 3D tab": where, the protection, excluded from backups, tied to the pairing
    (id and pin), deleted by Forget and never shown for another pairing, the ETag check and the swap, and the web view
    kept across tab switches with the clean reload after WebKit ended the page. Fix the sentences that say the page
    is never kept (also in `FlatScreen.swift`'s comments: `websiteDataStore = .nonPersistent()` stays, and its comment
    should say the web view keeps nothing, the app keeps the one copy). Update the Arestia bullet in `CLAUDE.md` in
    one short clause.

## Settled: do not re-open

- One copy per pairing, in Application Support, excluded from backups, protection
  `completeUntilFirstUserAuthentication` (the owner's lead asked for "at least complete-until-first-unlock").
- A copy is shown only for the same pairing id and the same pin; Forget deletes it; nothing of it reaches the App Group.
- A changed page is swapped in at once (rare); the copy stays when the check fails.
- The web view still never talks to the network and keeps nothing itself (`nonPersistent`).
- The page handed over is always `load(_:mimeType:characterEncodingName:baseURL:)` with `Coordinator.pageURL`, never
  a file URL (the origin and the network fence stay as they are).

## Out of scope

- `HomeScreen`, `Automations`, Settings, `FlatStore` beyond the two lines in `FlatSession.forget()`, the Control Center
  extension, App Intents. Another branch is changing those right now.
- The viewer page itself (`flat3d.html` is private flat data: never read it, never put it in this repo; use the fake's
  stand-in page). No build number change, no upload, no commits (Claude commits).

## API

flatd `GET /viewer` (flatd's `flatd/api.py` `viewer`, aiohttp `FileResponse`; contract `API.md`, the note added on
flatd's branch `viewer-etag`): with the key as every request; `200` with `Content-Type: text/html; charset=utf-8`,
`Cache-Control: no-store` and a strong `ETag` (`"<mtime_ns hex>-<size hex>"`, quoted); `304 Not Modified`, empty body,
when `If-None-Match` names the current ETag; `404` when no page is configured. Nothing else.

## Done when

- `bash scripts/test-unit.sh Arestia` passes with the new tests; `python3 scripts/strings.py check` passes.
- On the simulator against `scripts/fake-flatd.py` (stand-in page): the 3D tab shows the page; quit and relaunch the
  app with the fake stopped: the tab still shows the kept page at once (the check fails quietly); with the fake back,
  a check logs "unchanged" (304); Home ↔ Flat several times: no new `makeUIView`, no second `ready`.
  Logs via `xcrun simctl spawn <udid> log stream --predicate 'subsystem == "de.ares-empire.arestia"'` or `log show`.
- Your final message: files changed, the exact test summary lines, the timing lines you saw, and anything doubtful.
