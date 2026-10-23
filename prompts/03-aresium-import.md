# 03: Import bank and PayPal exports

Status: draft
Branch: `codex/03-aresium-import` · Worktree: `../empire-ios-03-aresium-import` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Patrik imports his VR Bank and PayPal exports on the phone, two ways: the import button on the start screen
(as on the website), and sharing the export file from another app (Files, Mail, the bank app) to Aresium.
Afterwards every screen shows the new numbers.

## Read first

- `AGENTS.md`, `CLAUDE.md` (always). The app as it is now: `Aresium/Aresium/` (brief 01 built it).
- `~/aresium/docs/API-DATA.md` → "Other routes the clients use" (`POST /api/import`).
- `~/aresium/src/web/server.ts` (the `/api/import` handler: body, 400/409 cases), `~/aresium/web/public/app/upload.js`
  (what the website sends and how it words the result), `~/aresium/web/public/app/mobile.jsx` (the import button,
  busy spinner, toast).
- `Aresium/Aresium/Info.plist`: the app is already registered for `.csv` (`public.comma-separated-values-text`)
  and `.xml` (`public.xml`), so the share sheet offers Aresium and the app receives the file URL.

## Build

1. **API** in a new file `API/APIClient+Import.swift` (extension): `POST /api/import` with
   `{files: [{name, content}]}`, Bearer and 401 handling as `dashboard`; decode `{results: [...]}` and the
   `{error}` body of 400/409.
2. **Reading files:** only names ending in `.csv`/`.xml` (case-insensitive); more than 20 MB → an error naming
   the file. Decode the bytes exactly like the website's `File.text()`: UTF-8 with invalid bytes replaced
   (`String(decoding:as: UTF8.self)`), so the server gets the same text as from the website. Access
   security-scoped URLs correctly.
3. **Import button** on the start screen's control row, as on the mobile website: opens `.fileImporter`
   (multiple, csv + xml); spinner while busy; button disabled meanwhile.
4. **Share sheet:** handle incoming file URLs (`onOpenURL`) with the same import flow. If the user is not
   logged in yet, keep the files and import right after login. Several files at once are one request.
5. **Result:** a short message worded like `summarize()` in `upload.js` (e.g. "12 new transactions imported ·
   1 skipped", or "3 added · 1 file(s) failed"), shown as a toast-like banner that disappears after ~4.5 s; on
   failure the server's `error` text. After any successful request, reload the dashboard.
6. **Sample mode** (`-sampleData`): the button and shared files show "Not available with sample data".
7. **Tests:** the request body and headers for two files; skipping other extensions; the 20 MB guard; UTF-8
   replacement on invalid bytes (a Latin-1 "ä"); the summary wording for success, skipped and failed files;
   409 shows the server's message; a successful import triggers a reload; files arriving while logged out
   are imported after login. Use the fakes in `AresiumTests.swift`.

## Settled: do not re-open

- No share extension: the document types in `Info.plist` are the mechanism (decided 2026-10-23, simpler and
  no app groups). Do not edit `Info.plist` or the project file.
- The server parses and categorises; the app sends text and shows the result. No parsing of CSV/XML in the app.
- No logging of file contents or transactions.

## Out of scope

- Transaction detail and recategorise (brief 02 runs in parallel and owns those files: the detail and
  recategorise sheets, the transactions screen's row tap, `pick`). Keep edits to existing files to the minimum:
  the start screen's control row, `ContentView`'s URL handling, the store's reload hook if needed.
- The red mode, widgets.

## Done when

- `xcodebuild test` passes on your own simulator, with the tests above, and the existing 21 still pass.
- Screenshots in sample mode: `build/03-start-import-button.png`; and with a fake success result shown:
  `build/03-import-result.png` (a launch argument or test hook may inject it; say how).
- Say whether `xcrun simctl openurl <your simulator> file:///…/test.csv` reached the handler, or what happened.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots, what is missing or
doubtful.
