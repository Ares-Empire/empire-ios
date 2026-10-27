# 23: An unknown bank file: "Does this look right?", and sending its format in two taps

Status: open (2026-10-27)
Repo: empire-ios · Worktree: `../empire-ios-23-file-check` (branch `claude/23-file-check`) · Built by: a Claude agent
(flow, data and the look)

## Goal

Patrik tried the first run (2026-10-27): most people don't know what a CSV is, and today's column check (each column's
meaning as a menu) asks them to. Replace it with a window that shows the first payments the way they will look in
the app and asks "Sieht das richtig aus?" / "Does this look right?". Yes imports; No shows the next way of reading the
file; only when every reading is wrong does the detailed column check appear (as a last resort, simplified). After a
confirmed unknown file, the person can send its **format** (never a payment) and the bank's name to us in two taps
(type the name, Send), so Claude adds that bank for everyone with the next update.

## Read first

`AGENTS.md`, `CLAUDE.md` ("Aresium phone mode", Languages, Light mode, the design rules). The plan:
`~/ares-empire/docs/ARESIUM-FOR-OTHERS.md` (D7 and the paragraph after it). The code: `Model/ImportStore.swift`
(`LayoutRequest`), `Model/LayoutDraft.swift` (`LayoutConfirmModel`), `Screens/PhoneScreens.swift`
(`LayoutConfirmSheet`, `MenuChip`), `Model/PhoneBackend.swift` (import with a layout), `Model/AresiumEngine.swift`,
`Model/EngineTypes.swift`. The engine's new exports (in the bundled `Engine/aresium-engine.js`, source
`~/aresium/src/engine/readers/readings.ts` and `share.ts`, read-only for you):
- `readingsOfUnknownFile(bytes, savedLayouts)` → up to 4 `{ reason, layout, preview }`, best first; `reason` null for
  the guess or one of `dateFormat`, `debitCredit`, `amount`, `sign`, `invertSign`, `counterpartyText`,
  `counterparty`, `valueDate`; `preview` = the first ≤ 5 `BankTxn` (the app's struct); `[]` when it is not an
  unknown CSV or nothing reads (then the column check).
- `shareableLayout(layout)` → `{ ok: true, layout }` or `{ ok: false, reason }` (`iban`, `email`, `date`, `amount`,
  `digits`, `tooLong`, `tooWide`, `tooLarge`, `invalid`).
The inbox (merged, deployed by Claude later): `~/ares-empire/docs/ACCOUNTS.md` → bank formats:
`POST https://auth.ares-empire.de/api/collections/bank_formats/records`, JSON `{bank, layout, app_version, language}`,
`Accept-Language`, no token; 200 / 400 with `message` in the request's language and `data.<field>.code` / 429.

## Build

1. **The engine calls** in `AresiumEngine` (typed, Codable, like the others): readings and shareable layout.
2. **The new window** (replaces `LayoutConfirmSheet` for an unknown CSV): the file's name; "Aresium kennt diese Bank
   noch nicht. So würden deine Buchungen aussehen:"; the first 3 payments as the dashboard's rows look (day tile,
   the other party or text, the amount in Aresium's money style; not a table, no column names); "Sieht das richtig
   aus?" with **Ja, importieren** and **Nein**. No → the next reading, with one short line on what changed when it
   helps ("Tag und Monat getauscht", "Ein- und Ausgänge getauscht", "Name und Verwendungszweck getauscht" …; none for
   reasons without a plain sentence). After the last reading, No → the column check as today (move it to its own
   file, keep it working, make its wording plain: "Welche Spalte ist das Datum?" rather than column jargon), and
   Cancel everywhere. Confirming saves the layout as today (only confirmed guesses are saved).
3. **Sending the format** — after a confirmed unknown file is imported, the result shows one quiet card: "Hilf
   Aresium, deine Bank zu lernen" with a name field ("Name der Bank", the account's bank name from the file as a
   suggestion when the engine has one) and **Senden**; a small "Was wird gesendet?" opens exactly what goes out (the
   column names and their meaning, the date and number style, the bank's name; never a payment). Two taps: type,
   Send. Not now / dismiss is one tap and never asks again for that layout. Before sending: `shareableLayout` must say
   ok, else the card is not shown at all (log the reason, no data). Offline or a server error: the submission is kept
   (Application Support, only the layout + name + app version + language) and sent by itself on the next app start or
   foreground with a connection, at most 3 tries; a 400 is final (show the server's `message` once if the person is
   still on the card, else drop it); a 429 waits for the next start. Sent → "Danke. Aresium lernt deine Bank mit dem
   nächsten Update." No account, no token, no email. Sample mode only pretends.
4. **German** for every new string (`scripts/strings.py sync`, `fill`, "du", plain), `check` 0 problems; every new
   screen looked at in German.
5. **Notes:** `CLAUDE.md` (the phone mode entry: the new window, sending, the launch arguments), and in
   `docs/APP-STORE.md` nothing changes unless the data types do (they don't: no personal data is sent).

## Who owns what (another agent works at the same time)

Brief 24 (the tour and the bank-steps screen) runs in parallel in `../empire-ios-24-tour`. It owns the first run
(`PhoneFirstRun`, `FirstRunStep`), the dashboard's tour overlay and new `Tour*`/`BankGuide*` files. **You own the
import window, the column check and sending**; do not edit `PhoneFirstRun`/`FirstRunStep` or the dashboard screens
beyond the import result. Put your screens in new files (`Screens/FileCheck*.swift`) and remove the old sheet from
`PhoneScreens.swift`. String catalogs will be merged by Claude.

## Done when

- `xcodebuild test` for Aresium passes (`-parallel-testing-enabled NO`) on **your own simulator** (create one, delete
  it at the end; never the booted "iPhone 17" 56D5D752…, Patrik uses it), with tests for: the readings flow (yes on
  the first, no → second, all no → column check), the sentences per reason, the send card only for a confirmed
  unknown layout that `shareableLayout` accepts, the request body, the queue (offline, retry, 400 final, 429 waits),
  "not now" never asks again.
- DEBUG launch arguments for screenshots: the window on reading 1 and 2, the column check, the send card, "what is
  sent", sent, and a 400; screenshots `build/23-*.png` light and dark, English and German, one at the largest text
  size; contact sheet `build/23-sheet.png`. Use the engine's made-up fixtures (`AresiumTests/Engine/`) or new
  made-up files; no real data (there are no real payments on this Mac and you must not look for any).
- Final message: files, test counts, screenshots, anything doubtful. Never commit, push, merge or deploy; never touch
  the server, any database or other repos.
