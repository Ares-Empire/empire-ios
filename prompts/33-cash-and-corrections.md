# 33: Receipts you can correct, cash entries by hand, and one Cash page

Status: merged 2026-10-28 (Aresium 328, Empire 204 tests; engine 4de0b4b)
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

## Part B (Claude's go: engine merged as aresium 4de0b4b; Claude copies the bundle into your worktree)

The engine's shapes, exactly (brief 32's final message):

- `SourceReceipt` (what `PhoneBackend` passes to `buildDashboardSource`) gains three optional fields from the stored
  receipt: `direction: "out" | "in"` (default "out"; "in" only with `method: "cash"`), `kind: "receipt" | "manual"`
  (labels only), `paidFrom: string | null` (cash out only: a withdrawal's payment id or a received entry's id; one that
  names nothing is ignored). **Never set `paymentId` on a hand entry** (a joined entry adds nothing and leaves the page).
- Cash received counts as money in, in its category (no category: "Other" income, as any money in), and is a source in
  the pool; it gets no covered row. Cash out takes first from its `paidFrom` source (no 92-day limit for a chosen one),
  then the latest source on or before its day (92 days back at most), the rest is spending of its own. On the same day
  a withdrawal is taken before a gift.
- Only when `receipts` is given (the app always gives it): withdrawals' dashboard transactions carry
  `cashWithdrawal: true`, and the dashboard has `cash: { months: { "YYYY-MM": { withdrawn, received, spent, unaccounted } },
  movements: [{ id, date, amount (wallet side: + in, − out), kind: "withdrawal" | "received" | "receipt" | "manual",
  place, category (the dashboard's name; "Uncategorised" for none), paidFrom: [source ids] | null (outs; [] = all from
  elsewhere), coveredBy: [ids] | null (ins: the outs that took from it), left: number | null (ins: what it still
  holds) }] }`, movements by date, newest last (same day: money in first). All four month numbers are positive euros;
  `unaccounted` is what the month's withdrawals still hold (the number their category shows). Card receipts, joined
  receipts and foreign-currency entries are not movements.
- The default category `cash` is now "Cash withdrawals" / "Abhebungen" (id unchanged).

Build:

1. **Add cash** ("Add cash" / "Bargeld eintragen"): a fourth item in phone mode's import menu, and on the Cash page.
   One window in the check window's look: **Spent / Received** (segmented), amount, date, what (spent: where or what
   for; received: from whom or what for), category (spent: the spending categories and Not sorted; received: the income
   categories and Not sorted), and for Spent **Paid from** (below). Stored as a receipt with `kind` manual, `method`
   cash, its `direction`, no rows. Its page (the receipt page's look) with Edit and Delete.
2. **The Cash page** ("Cash" / "Bargeld"): from a row on the dashboard (a wallet mark, below the categories, shown only
   when `dashboard.cash` has any movement; never counted in a total). On top the month (following the dashboard's
   Current / Overview and month like a category does): withdrawn, received, spent, **not accounted for**
   (`unaccounted`, with one plain line: in the wallet still, or spent without a receipt). Then the movements, newest
   first, from the wallet's side (+ / −), each with its kind in words (Withdrawal, Received, Receipt, Entry), place,
   category; a source shows what it still holds (`left`), a payment out where it came from ("from the withdrawal of
   3 Oct"). Tapping opens the withdrawal's payment page, the receipt's or the entry's page. Buttons: Add spending, Add
   received cash. Empty state when nothing yet.
3. **Paid from** on a cash receipt's or spent entry's page and in their windows: Automatic (default) or one source on or
   before its day (withdrawals and received entries, newest first, each with what it still holds). Saved as `paidFrom`;
   the dashboard is rebuilt.
4. **Names:** "Cash" / "Bargeld" is the page, so the own-category name check refuses them (the engine no longer
   reserves them); the withdrawals category's name comes from the engine. The covered row's words must now fit
   receipts and hand entries alike (your wording).
5. **Deleting** a received entry: what took from it is matched again automatically (the engine does it on the next
   build; check the page shows it).
6. `CLAUDE.md` (the Receipts part grows a Cash part: flow, files, launch arguments, tests).

**Tests:** a hand entry spent and received, stored with the right fields and never joined; Paid from saved and passed;
the Cash page's numbers from the engine's `cash` (two months, a gift spent, a withdrawal partly covered); deleting a
gift; the name check refusing Cash / Bargeld in both languages. **Screenshots** `build/33b-*.png` (de/en, light/dark,
one at the largest text size): Add cash (spent, received), the Cash page (with movements; empty), Paid from, an entry's
page, the dashboard row. DEBUG arguments to reach each with made-up data.

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
