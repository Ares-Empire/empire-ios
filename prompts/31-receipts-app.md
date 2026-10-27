# 31: Receipts in the app: scan or pick a receipt, check it, keep it once

Status: running (part A; part B starts when Claude says the engine of brief 30 is merged)
Repo: empire-ios · Worktree: `../empire-ios-31-receipts` (branch `claude/31-receipts`) · Built by: a Claude agent
(flow, data and the look)

## Goal

Patrik wants receipts in Aresium (2026-10-27, D8 in `~/ares-empire/docs/ARESIUM-FOR-OTHERS.md` → part 6 "Version 1";
read it first). In phone mode the import button becomes Apple's usual menu: **Choose file**, **Scan receipt**,
**Choose photo**. The iPhone reads the receipt on the phone; the engine (brief 30, running in parallel in the aresium
repo) turns it into shop, date, total, currency and card or cash, matches it to the bank payment so nothing counts
twice, and counts cash once. This brief is the app: capture (part A, now), then the check window, storage, matching
questions and the dashboard (part B, once the engine is merged; Claude sends you its exact functions then).

## Read first

- `AGENTS.md`, `CLAUDE.md` (the "Aresium phone mode" entry: the first screen, `ImportStore` and the import's end, the
  file check window's look, the tour, Languages, Light mode, the design rules: ink only, no slogans, Apple's own
  controls where they exist).
- `Screens/ImportControls.swift` (`ImportButton`), `Screens/PhoneScreens.swift` (`PhoneFirstScreen`'s Import data),
  `ContentView.swift` (where the import button sits, the file importer), `Model/ImportStore.swift`,
  `Screens/FileCheckSheet.swift` (the look to reuse for the receipt's check window in part B), `Model/TourModel.swift`
  (the import step points at the import button).

## Part A: capture (now)

1. **The menu.** In phone mode, every place that offers Import data (the first screen's main button and the
   dashboard's import button) opens a SwiftUI `Menu` with Choose file (as today), Scan receipt and Choose photo, with
   SF Symbols (`doc`, `doc.viewfinder`, `photo`), in the app's language. Scan receipt only where the document camera is
   supported (`VNDocumentCameraViewController.isSupported`; the simulator has no camera, so it is hidden there). The
   guide's Choose file stays files only. Server mode (Patrik's) keeps today's button: no receipts there yet. The tour's
   import step keeps pointing at the button and still only answers its step (no menu action runs in the tour).
2. **Scan receipt:** Apple's document scanner (VisionKit, `VNDocumentCameraViewController` in a representable), which
   straightens the receipt; a long receipt can be several pages. **Choose photo:** `PhotosPicker` (one image; no
   photo-library permission is needed for it). `NSCameraUsageDescription` in `Info.plist` with its German in
   `InfoPlist.xcstrings` (plain: what the camera is for, that the photo stays on the iPhone and is not kept).
3. **Reading:** Vision text recognition on the phone (`RecognizeTextRequest`, or `RecognizeDocumentsRequest` if it
   reads receipts better: try both on the test images and say which you chose and why), accurate level, automatic
   language detection, and barcode detection for QR codes (`DetectBarcodesRequest`). The result is the engine's input,
   exactly this JSON (`ReceiptCapture`, `Codable`): `{ observations: [{ text, x, y, width, height }], codes: [string] }`
   with boxes normalised 0–1, **origin top left, y growing downwards** (Vision's own boxes start at the bottom left:
   convert in one place), each scanned page's y offset by its page number (page 2 starts at y = 1). Reading runs off
   the main actor and is cancelled with its sheet. The image is never written to disk and is released after reading.
4. **Until part B:** after reading, a plain DEBUG-only sheet lists the observations and codes (it goes in part B). No
   storage yet. Do not change the ledger, the backends or the engine bundle in part A.
5. **Made-up receipts for tests and screenshots:** a small DEBUG renderer that draws a made-up German receipt (shop
   name, address, items with right-aligned prices, SUMME, girocard lines, date, a register QR code with a made-up
   payload, in a receipt-like monospaced font, slightly tilted) into an image; `-sampleReceipt` reads it through the
   real Vision path at launch (the simulator has no camera). Tests: rendering and reading one finds the shop line, the
   SUMME row's amount and the QR payload; the box conversion (bottom-left → top-left, pages) is pinned with numbers.
   Also add one made-up receipt image to your simulator's Photos (`xcrun simctl addmedia <udid> <png>`) and check
   Choose photo by hand.

## Part B: check, keep, match (after Claude's go)

Written from brief 30's final message; in short: the check window (shop, date, total, card or cash, category; the
fields the engine is unsure of first; card or cash must be chosen when not read; another currency paid in cash asks for
the euro amount), storage (a receipt model in the ledger: the read rows, no image; export/restore schema 2), matching on
save and after every bank import (an exact single match joins; every candidate is asked: "Is this the same payment?"),
the payment page's receipt section, receipts waiting for the bank statement and the cash covered by receipts in the
dashboard, the tour's import step, `CLAUDE.md`. Claude sends the details.

## Settled: do not re-open

- No photo kept, no AI, nothing leaves the phone; phone mode only for now.
- Apple's own pieces (Menu, the document scanner, PhotosPicker, Vision), styled only where the app draws its own.

## Done when (part A)

- `xcodebuild test` for Aresium passes (`-parallel-testing-enabled NO`) on **your own simulator** (create one, delete
  it at the end; never the booted "iPhone 17" 56D5D752…, Patrik uses it); new tests as in A5.
- `scripts/strings.py check` 0 problems; the menu looked at in German and English, light and dark.
- Screenshots `build/31-*.png`: the menu on the first screen and on the dashboard, the photo picker, the DEBUG list
  after `-sampleReceipt`.
- Final message (plain English): files changed, test counts, which Vision request you chose and how well it read the
  made-up receipt (rows joined or split, the QR found), screenshots, anything doubtful. Then **wait** for part B (stay
  in the worktree). Never commit, push, merge or deploy; never touch the server, any database or other repos. No real
  data: no real receipts or payments; only made-up ones.
