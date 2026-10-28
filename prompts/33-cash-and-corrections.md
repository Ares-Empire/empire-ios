# 33: Receipts you can correct, cash entries by hand, and one Cash page

Status: running (part A; part B starts when Claude says the engine of brief 32 is merged)
Repo: empire-ios · Worktree: `../empire-ios-33-cash` (branch `claude/33-cash`) · Built by: a Claude agent (flow, data
and the look)

## Goal

Patrik tried receipts (2026-10-28) and asked for two things (D9 in `~/ares-empire/docs/ARESIUM-FOR-OTHERS.md`; read it,
with part 6 and D8):

1. **The check window must be correctable.** It asks "Does this look right?" but, to him, offers nothing to do when it
   is not: shop, amount, category and card or cash must all be plainly editable, before saving and afterwards, and
   Aresium should learn from corrections where it can.
2. **Cash that never came from the bank** (a gift, money from selling something): cash entries by hand (spent and
   received), received cash as a source that cash spending can come from, a choice of where a cash payment came from,
   and **one "Cash" page** with every cash movement. The engine part is brief 32 (running in parallel in the aresium
   repo); this brief is the app.

## Read first

- `AGENTS.md`, `CLAUDE.md` (the "Aresium phone mode" entry, its "Receipts" part, the design rules: ink only, no
  slogans, Apple's own controls where they exist), brief 31 (`prompts/31-receipts-app.md`) and its code:
  `Model/Receipts.swift`, `Model/PhoneReceipts.swift`, `Model/ReceiptCheck.swift`, `Screens/ReceiptCheckView.swift`,
  `Screens/ReceiptPageView.swift`, `Model/PhoneStore.swift` (schema versions), `Model/LedgerExport.swift`,
  `Screens/ImportControls.swift`.

## Part A (now)

1. **Every field visibly editable in the check window.** Shop (a text field), date, total (with its currency), Card /
   Cash, category: each looks like something to tap (the Settings pieces' field look, a chevron or the field
   background), also the ones the engine was sure of; the unsure ones stay first and marked. One quiet line under the
   top: "Something wrong? Tap it and change it." Save stays at the bottom with "Does this look right?".
2. **Edit after saving:** the receipt's page gets **Edit**, the same window filled from the stored receipt. A change of
   total, date, currency or card/cash unjoins and matches again by the D8 rules (asking when unsure); a change of shop
   or category only updates.
3. **Learning from corrections.** A shop name the person changed is remembered: the shop as read (normalised: lower
   case, letters and digits only) → the name typed, and the next receipt read the same way shows the corrected name
   (marked "Corrected by you before"). The category chosen for a receipt is learned for its shop as a Switch does (it
   may already be: check). Total and card/cash are not learned (misreads are random; one shop takes both); say so in a
   comment.
4. **One storage step for this brief (parts A and B): ledger schema 3**, a lightweight stage after 2 (version 2's
   models stay unchanged in the file, as brief 31 did with 1): receipts get `direction` ("out" | "in", default "out"),
   `kind` ("receipt" | "manual", default "receipt") and `paidFrom` (an id or nil); a new model for the shop-name
   corrections. Export/restore **schema 3** (still reads 2 and 1). A test opens a version 2 store made by today's main
   (as brief 31's fixture did for version 1).

## Part B (after Claude's go: the engine's exact shapes come with it)

In short (details follow): "Add cash" in the import menu and on the Cash page (spent or received, amount, date, what or
from whom, category: spending categories for spent, income ones for received); the **Cash page** (from a row on the
dashboard when there is any cash movement): the month's withdrawn, received, spent and not accounted for, every
movement from the wallet's side, tap one to open it; on a cash receipt's or entry's page **Paid from** (automatic, or
one of the sources before it); the renamed "Cash withdrawals" / "Abhebungen" category comes from the engine.

## Settled: do not re-open

- No photo kept, nothing leaves the phone; phone mode only.
- Withdrawals stay spending (their unaccounted rest); the Cash page is a view and never counts in the totals.

## Done when (part A)

- `xcodebuild test` for Aresium passes (`-parallel-testing-enabled NO`) on **your own simulator** (create one, delete it
  at the end; never the booted "iPhone 17" 56D5D752…, Patrik uses it), with tests for: every field editable and saved;
  editing after saving (unjoin and match again on an amount change; no re-match on a shop change); a corrected shop name
  applied to the next receipt read the same way; schema 3 opening a version 2 store; export 3 and restore of 2 and 1.
- `scripts/strings.py check` 0 problems; the window looked at in German and English, light and dark, and at the largest
  text size. Screenshots `build/33-*.png` (the window with every field editable, sure and unsure; Edit on a saved
  receipt; a receipt showing the corrected shop).
- Final message (plain English): files changed, test counts, the screenshots, anything doubtful. Then **wait** for part
  B in the worktree. Never commit, push, merge or deploy; never touch the server, any database or other repos. No real
  data: only made-up receipts and payments.
