# 81: Several payments changed at once: the data

Status: brief
Branch: `codex/81-select-many-data` · Worktree: `../empire-ios-81-select-many-data` · Model: `gpt-6.1-sol`, effort
`high` · Simulator: `codex-81` (create it: iPhone 17, iOS 27.0) · The screens follow in brief 82 (a Claude agent) on
this brief's API.

## Goal

Patrik (2026-11-01, on build 10): "lets make expenses / incomes selectable and then moveable / changable at the same
time. so e.g. Im in not sorted and select 10 expenses to move them into a different category at the same time or give
all expenses the same name or smth like that. I think we add a small icon when inside a category that shifts
statements slightly to the right and shows circles to tick like in Mail when selecting mails".

This brief gives what the screens need to change many rows of a category's month list at once (Not sorted included):
**switch them to a category**, **add a category** to them, **give them one name**, each with **one** follow-up
question for the shops' other payments and an **undo**. It behaves as doing the same thing to each row by hand, one
after the other, with the questions asked once for all.

**Runs beside brief 80** (`../empire-ios-80-category-rename-delete`: a typed category name that exists, rename and
delete categories; it edits `PhoneCategories`, `NewCategory`, `PhoneSettingsModels`, `PhoneScreens`, `LedgerExport`,
`TourModel`, parts of `PhoneBackend`/`PhoneLedger`). Keep this brief's code in new files where you can
(`Model/BatchChanges.swift`, extensions of `PhoneBackend`, `PhoneLedger` and `DashboardStore` there), and do not touch
the screens (`Screens/`) or the change window: brief 82 does.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Aresium phone mode": the change window and the shop question, learning, payment names and
  renaming (briefs 43, 44, 47, 54, 76), adding up names (brief 53: summed rows and `PaymentList`), receipts and cash
  entries in lists, covered rows, counting as it happened (brief 71), the undo bar `Shared/Design/UndoBar.swift`).
- `Model/PhoneBackend.swift` (`switchCategory(id:to:auth:)` with its `MerchantFollowUp`, `setTags`, `rename`,
  `renameInfo`), `Model/PhoneLedger.swift` (`setCategory`, `move`, `remember`, `otherShopPayments`), `Model/PaymentNames.swift`,
  `Model/PaymentRename.swift` (`RenamePlan`), `Model/ShopIdentities.swift`, `Model/DashboardStore.swift` and
  `Model/PaymentRows.swift` (`paymentList`, `PaymentListEntry`, `rowActions`, `page(for:)`), the receipt and cash
  entry category changes (their Edit), `Model/TransactionDetailStore.swift`, and their tests.

## Build

1. **What can be selected** (`DashboardStore`, phone mode only; `offersSelection` false in server mode and for lists
   with nothing selectable): in a category's month list (`paymentList(category:month:side:)`, Current and Overview,
   Not sorted included) every bank or PayPal payment, receipt and cash entry row; not a withdrawal's covered row. A
   summed row (brief 53) stands for its payments: `selectionIDs(for entry:)` gives a row's ids (one, or a sum's
   members), so selecting a sum selects them all. A selection is a set of row ids; `selectionSummary(_:)` says how
   many payments, receipts and cash entries it holds, their side (one list is one side), the money in total, how many
   are bank payments (renaming applies only to those; receipts and entries keep their typed Shop) and whether a switch
   or rename is possible.
2. **Switch** (`switchCategory(ids:to:)`): each selected row is set to the category by hand, as a single Switch does:
   a bank payment `.manual` and its shop learned (`engine.learn` per payment, one `remember` for all); a receipt or a
   cash entry as its Edit sets it. One save, one dashboard rebuild, no sort. Then **one** follow-up, as the single
   Switch's `MerchantFollowUp` but for all the selection's shops together: the other payments of those shops that the
   single Switch would move (not set by hand, not structural, not receipt-set, not own transfers, not already in the
   target, not selected), counted once each; nil when none. Its words need: the count, the number of shops, and the
   shop's name when it is one shop. Applying it does what the single follow-up does, for every shop.
3. **Add a category** (`addCategory(ids:name:)`): the category as an extra on each selected bank payment, as `setTags`
   adds one (skipped where it is the primary or already there; receipts and entries have no extras: skipped and
   counted). No learning, no follow-up.
4. **One name** (`renameInfo(ids:)`, `rename(ids:to:scope:)`): for the bank payments of the selection. `renameInfo`
   gives the counts the question needs: how many bank payments are selected, how many other payments their shops have
   (as the single rename's `otherPaymentCount`, over the distinct shop identities, none for an empty merchant key),
   how many shops. Scope `.payments`: the name as each payment's own name (as "Only this one"). Scope `.shops`: the
   name as the shop rule of each distinct shop identity of the selection (as "All"), payments with an empty merchant
   key get it as their own name; the selected payments' own names are dropped so the shop's shows, as the single All
   does. An empty name removes own names in the chosen scope, as today. Same trimming and 60-character limit.
5. **Undo** (each of the three, and an applied follow-up): the result carries an undo that puts back exactly what
   changed: each row's category, source and extras, the learned rules it replaced or added (old value back, new key
   removed), the names and name rules, then one rebuild. An undo after the follow-up undoes both. It works only while
   nothing else changed those payments (an import or another change in between: say how you guard it, for example a
   store revision; when it cannot undo, it says so instead of half-undoing).
6. **Fast with many rows:** one ledger job per action on the ledger's executor (as the single changes run), never one
   per row; measure 500 selected rows from 60 shops in a test (under 300 ms on the simulator for the ledger work, the
   engine's learning in one batched call if the bridge allows, say what it takes).
7. **`DashboardStore` API for the screens** (brief 82): the selection's rows and summary, `switchCategory`,
   `addCategory`, `renameInfo`, `rename`, each returning a result with the counts for a line ("10 payments moved to
   Groceries", "Name given to 10 payments", with receipts or entries skipped counted), the follow-up, and the undo;
   `offeredCategories(for:)` the choices for the selection's side as the change window offers them for one payment of
   that side (`PhoneCategoryList.offered`), its current category left out when all selected rows share it. The tour's
   store works the same (no special case).
8. **English keys** for any text the model builds (the result lines, the follow-up's question), German left to the
   screens' brief or written by you with `scripts/strings.py` (then `check` must pass). Keep the words short; brief 82
   decides where they show.

## Settled: do not re-open

- One selection in one list (one side); a summed row selects its payments; covered rows are not selectable.
- Each action behaves as the single action done on each row, with one question for all shops and one undo.
- Renaming touches bank payments only.

## Out of scope

- Every screen (brief 82): the icon, the circles, the bar, the window, the undo bar, the tour.
- Selecting on the day's page, a name's page, search or the Cash page.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=codex-81'
  -derivedDataPath build/DerivedData` passes, with new tests: selectable rows and summary (sums, covered rows,
  receipts, entries); Switch from Not sorted of payments from several shops (each set by hand, each shop learned, the
  follow-up counting each other payment once and excluding hand-set, structural, selected and already-target ones;
  applying it); Add (skips counted); rename in both scopes (several shops, an empty merchant key, existing own names
  and rules), an empty name; undo of each, of a follow-up, and refused after another change; 500 rows timed; server mode
  offers nothing.
- `scripts/strings.py check`: 0 problems.
- `CLAUDE.md`'s "Aresium phone mode" gains the API (as briefs 76 and 69 described theirs).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the API brief 82 builds on (names and what
each returns), the timing measured, how undo is guarded, anything doubtful. Never commit, push or merge: Claude does.
