# 31: Receipts in the app: scan or pick a receipt, check it, keep it once

Status: running (part A done and checked 2026-10-27; part B running)
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

## Part B: check, keep, match (Claude's go: 2026-10-27, engine merged as aresium 008a420)

The engine is in your worktree's bundle already (`Engine/aresium-engine.js`, `engine-version.txt` = 008a420; Claude ran
`scripts/aresium-engine.sh`). Its functions, exactly (from brief 30's final message):

- `readReceipt({ observations, codes? }) → { shop, categoryId, date "YYYY-MM-DD"|null, time "HH:MM"|null, total,
  currency ("EUR" when the receipt names none; null only for an unpinned "kr"), method "card"|"cash"|null, language
  "de"|"en"|"fr"|"it"|"es"|"nl"|"pt"|null, from "code"|"text", rows [string] (Latin letters: look-alikes mapped),
  sure { shop, date, total, method } }`. Card and cash on one receipt gives `method: null`. Foreign shops get a
  category only when the (German) shop list knows them.
- `matchReceipt({ date, total, currency?, shop? }, payments [{ id, date, amount, currency?, counterparty?,
  description? }], taken [id]) → { exact: id|null, candidates: [{ id, why: "severalSame"|"amountDiffers"|"otherCurrency",
  days 0–7, difference (bank − receipt; null for another currency) }] }` (best first, at most 5).
- `buildDashboardSource({ transactions, categories, today, receipts? })`, each receipt `{ id, date, total, currency,
  method "card"|"cash", category (name)|null, shop, paymentId|null }`. New optional fields on the dashboard's
  transactions: `receiptId` (the row is a receipt), `provisional: true` (a card receipt waiting for its bank payment),
  `coveredBy: [receiptIds]` (a withdrawal's "covered by receipts" row: positive, in the withdrawal's category and
  month, never income). Receipts in another currency are left out until the app sends the euro amount; a receipt
  joined to a payment that no longer exists counts as not joined.

Build (D8 in the plan is the rule set; ask nothing the engine already answers):

1. **Offered for real:** remove `ReceiptCaptureModel.offered`'s DEBUG gate (phone mode only, as in part A).
2. **The check window** after reading (the file check window's look and wording style: "Does this look right?"):
   shop (editable), date, total, currency only when it is not EUR, **Card / Cash** (Apple's segmented control), and the
   category (the person's chosen categories, Not sorted; preset from `categoryId` when that category is chosen). Fields
   the engine is not sure of come first and are marked plainly. Card or cash not read: preset **Card** when
   `matchReceipt` finds an exact match or candidates for it, otherwise nothing chosen and Save waits for a choice (D8:
   never guessed silently). Another currency paid in cash: an "Amount in euros" field, required. Nothing read at all:
   the same window with empty fields (typed by hand), never a dead end. The read text folded at the bottom ("As on the
   receipt"). Save / Cancel.
3. **Storage:** a receipt model in the ledger (SwiftData; adding a model must open existing stores: test it with a
   store made by today's main): id, date, time, shop, total, currency, euro amount (foreign cash), method, category id
   and how it was set, the rows, `from`, the joined payment id, created. No image. Export/restore **schema 2** with the
   receipts (restore still accepts schema 1). "Delete Aresium data" and "Forgot the code?" take them too.
4. **Joining:** on Save of a card receipt, `matchReceipt` over the stored payments (`taken` = the other receipts'
   payment ids). Exact → joined at once; if that bank payment has no category, it takes the receipt's (a new category
   source `receipt`, with its sentence on the payment page: "Sorted by its receipt."). Candidates → **"Is this the same
   payment?"**: the receipt on top, the candidates as the dashboard's rows with what differs ("€20.00 more: cash back or
   a tip?", "another currency", "two payments match"), and "None of these" (it waits). Nothing → waits ("Waiting for
   the bank statement"). **After every bank import** the waiting card receipts are matched again: exact ones join by
   themselves (the result line says how many), candidates are asked once after the import (after the category picker
   when both are due). The person can also join or unjoin by hand on the receipt's page.
5. **Dashboard:** `PhoneBackend` passes the receipts to `buildDashboardSource`. A receipt row opens the **receipt's
   page** (the payment page's look: shop, amount, date written out, Card / Cash, "Waiting for the bank statement" or
   "Paid in cash", category with Change, "As on the receipt" folded, Join with a payment… for a waiting card receipt,
   Delete receipt). A provisional row carries a quiet "waiting" mark in the lists. A `coveredBy` row reads "Covered by
   receipts" and opens the list of those receipts. A joined bank payment's page gets a "Receipt" section (shop, the
   rows folded, Unjoin). Changing a receipt's category learns its shop, as a Switch does.
6. **Settings → Your data → Receipts:** every receipt with its state (joined, waiting, cash), newest first; foreign
   card receipts that wait show here (the dashboard leaves them out until joined).
7. **The tour's import step** mentions receipts in its sentence; the tour never opens the camera or reads anything.
8. **Docs:** `CLAUDE.md` (a "Receipts" part in the phone mode entry: the flow, files, launch arguments, tests),
   `docs/APP-STORE.md` (the camera: what for; nothing collected).

**Tests:** storage and opening an old store; export/restore 2 and 1; on Save: exact joins (and gives an unsorted
payment its category), candidates are asked, none waits; after a bank import: waiting ones join or are asked; cash
receipts and the covered row (through the real engine); deleting a receipt unjoins and uncovers; foreign cash needs
euros; method not read → must choose, Card preset when a match exists; the new category source's sentence in both
languages. **Screenshots** `build/31b-*.png` (de/en, light/dark, one at the largest text size): the check window (all
sure; unsure fields first; nothing read), the question, a waiting receipt in a category, Cash with its covered row, the
receipt's page, a joined payment's page, Settings → Receipts. DEBUG arguments to reach each with the made-up receipt.

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
