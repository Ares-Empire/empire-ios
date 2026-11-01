# 69: Every category has a side: the app's data and choices

Status: merged 2026-11-01 (660 Aresium tests pass; schema 6, export 5; existing stores keep their menus)
Branch: `codex/69-category-sides` · Worktree: `../empire-ios-69-category-sides` · Model: `gpt-6.1-sol`, effort `high`
· The screens follow in brief 70 (a Claude agent), on this brief's API.

## Goal

Patrik (2026-11-01): "own categories for income. but not all default categories should show up there … not sure if
custom categories should be automatically shared between income and expenses because it could unnecessarily bloat the
menu", and then: "if category A is on expenses but also has incomes then it should be addable not just switchable."

Settled with him:

- **Every category has one home side**, spending or income, where its money is counted. A default category has the
  side the engine's list gives it (`categories.ts`: the Income group is income, Savings & investing and Own transfers
  are transfers, all others spending). One's own category gets its side when it is made: made for money in, income;
  for money out, spending; in Settings → Categories the person chooses. It can be switched later.
- **Any category can also be offered on the other side** (`otherSide`), added from the change window when it is first
  needed there (brief 70) and removable again. A spending category offered for money in takes money paid back (it
  lowers the spending); an income category offered for money out takes money given back (it lowers the income).
- Transfers are offered for money in and out alike.

Brief 68 (aresium, merged before this starts) made the engine count by a given side and build the change window's
lists from it (`SourceCategory.side`, `SourceCategory.otherSide`, `Category.otherSide`, `pick`). This brief stores the
sides in the phone's store, passes them to the engine, moves existing stores over without changing what they show, and
gives every place that offers categories one rule. No screen changes here beyond what the API needs to compile.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Aresium phone mode": storage and its schema versions, own categories' looks of brief 36,
  the change window and New category of brief 60, Cash, receipts, the tour).
- `prompts/68-aresium-category-sides-engine.md` and the engine's `docs/API-DATA.md` (in `~/aresium`, as merged).
- `Aresium/Aresium/Model/PhoneStore.swift` (the schema versions, `LedgerMigrationPlan`), `PhoneLedger.swift`
  (`ChosenCategory`, `choose`, `giveOwnCategoriesLooks` as the model for work done when the store opens),
  `PhoneCategories.swift` (`PhoneCategoryList`, `sourceCategories`, `isTransfer`), `PhoneBackend.swift` (`addCustom`,
  `choose`, `unchoose`), `LedgerExport.swift`, `EngineTypes.swift` (`SourceCategory`), `Cash.swift`
  (`CashCategories`), `ReceiptCheck.swift` (`loadChoices`), `NewCategory.swift`, `TransactionDetailStore.swift`
  (`choices`, `offersNewCategory`, `createCategory`, `save`), `AresiumShared/Dashboard.swift`
  (`recategorisationChoices`, `takesNewCategory`, `CategoryChoices`), `PhoneSettingsModels.swift`
  (`CategoryPickerModel.addCustom`), `Model/TourData.swift`.

## Build

1. **The engine copy.** Claude runs `bash scripts/aresium-engine.sh` in this worktree before you start, so
   `Engine/aresium-engine.js` has brief 68. `SourceCategory` (Swift) gets `side: String?` and `otherSide: Bool?`
   (encoded only when set), `Category` (AresiumShared) decodes `otherSide`.
2. **Storing the side** (schema version 6, a lightweight stage, as versions 3–5): the stored chosen category gets
   `side: String?` (only one's own: `"spend"` or `"income"`; nil for defaults, whose side is the engine's list's) and
   `otherSide: Bool = false` (any category). `ChosenCategory` carries both. Freeze version 5's models as they are, as
   the file's rule says.
3. **Moving existing stores over without a visible change.** Today a category's side is its money's net (brief 68's
   "no side given" rule). When the store opens (as `giveOwnCategoriesLooks` does, once, before anything is read):
   - one's own category without a side gets `income` when its payments add up to more money in than out, else
     `spend`, so it stays where it is today;
   - a default spending category whose payments add up to more money in than out (today counted as income and offered
     for money in, Friends for example) gets `otherSide`, so it is still offered for money in. Its money now counts as
     paid back on the spending side; that is the fix, not a regression.
   - An income default with no money in (Selling things before the first sale) gets nothing: being offered for money
     out was the bug.
   Count with the payments' categories as stored (primary category only; receipts and cash entries count as they do
   in the engine's input). Write a test for each case on a version 5 store made by version 5's code (as
   `OwnCategoryLookTests` does for version 3).
4. **Passing it on.** `PhoneCategoryList.sourceCategories` sends every category's `side` (a default's from the
   catalog's `kind`, one's own from the store; transfers stay `excludeFromTotals` with no side) and `otherSide` when
   true. The dashboard's `pick` then has the new lists.
5. **One rule for what is offered** (`PhoneCategoryList`, pure, tested): `offered(for: direction)` gives the ids a
   payment of that direction may be put in: its side's categories, then the other side's ones with `otherSide`, and
   transfers for the change window. The receipt window (money out, `ReceiptCheckModel.loadChoices`; today it offers
   every chosen category) and Add cash (`CashCategories`; today one's own in both lists) use it, without transfers (cash
   and receipts are never a transfer); Not sorted stays last. A test checks, on a sample store, that the change
   window's lists from the engine's `pick` hold exactly the same categories as `offered(for:)` with transfers, so the
   two can never drift apart.
6. **Making one's own category with a side.** `PhoneBackend.addCustom(named:side:)` (the side required; no default
   that could put a category on the wrong side silently). `NewCategoryModel.create` passes the side of the window it
   was opened in: the change window's payment (money in → income), the receipt window spending, Add cash spent or
   received. Settings' field (`CategoryPickerModel.addCustom`) takes a side the screen gives (brief 70 draws the
   choice; until then pass `spend`).
7. **Changing sides.** `PhoneBackend`:
   - `setSide(_ side:, of id:)` for one's own category. When the category holds payments of the side it leaves
     (money in for income), it keeps being offered there (`otherSide` set), so those payments can still be moved; the
     person can remove that.
   - `setOtherSide(_ on: Bool, for id:)` for any chosen category (not transfers).
   - Both rebuild the dashboard as other category changes do (`DashboardStore` must notice: `builtChosen` compares
     the new fields too).
8. **The change window's model** (`TransactionDetailStore`, no look):
   - `offersNewCategory`: phone mode, both directions now (remove `Dashboard.takesNewCategory` and its money-out rule).
     The category made there gets the payment's side.
   - `otherSideChoices: [Category]`: the categories of the other side not offered for this payment's direction yet
     (what brief 70's "Other category…" shows), in their own side's order. Empty in server mode and in the tour's
     money-in payments only if the tour's store has none.
   - `pickFromOtherSide(_ name:)`: picks it (the Switch target, or an extra in Add) and shows it among the choices
     before the tiles, as a category made there does (`madeHere`). Nothing is stored before Save.
   - On Save, a category picked from the other side gets `otherSide` (stored), in Switch and in Add, then the payment
     is saved as today (the shop question follows a Switch as for any category). Cancel stores nothing.
   - `stopOffering(_ name:)` removes `otherSide` for a category that is offered here only through it (not one of this
     side's own, not the payment's current category). It is stored at once and the choices update.
9. **Export and restore:** export schema 5 carries `side` and `otherSide`; restoring 4 and older decides sides as in
   item 3 after the payments are in.
10. **The tour** (`TourData`, the tour's store): its categories get their sides as the person's would; its switch step
    still moves REWE as before. Nothing of the tour reaches the person's store.

## Settled: do not re-open

- One home side per category for its totals; `otherSide` only widens where it is offered. A category is never counted
  on both sides.
- A category is added to the other side by using it there (brief 70), never automatically for all.
- Existing stores show the same categories in the same menus after the move as before, except the bug cases in item 3.

## Out of scope

- Every screen's look (brief 70): the tiles, Settings' side choice and its rows.
- The engine (brief 68), server mode, the server sample.
- Whether paid-back money also counts as income (Patrik decides separately).

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=codex-69'
  -derivedDataPath build/DerivedData` passes (create the simulator `codex-69`, iPhone 17, iOS 27.0), with new tests:
  the store's move from version 5 (each case of item 3); `sourceCategories` with sides; `offered(for:)` and its match
  with the engine's `pick`; New category on both sides of the change window, in the receipt window and both kinds of
  Add cash; picking from the other side, Save storing `otherSide` (Switch and Add), Cancel storing nothing;
  `stopOffering`; `setSide` keeping the old side offered when it holds payments; export 5 and restore of 4; the tour's
  store untouched.
- `scripts/strings.py check`: 0 problems (no new visible words expected here).
- `CLAUDE.md`'s "Aresium phone mode" says how sides are stored, moved over and offered (replace brief 60's "only for
  money out" sentences).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the API brief 70 builds on (names and what
each does), anything doubtful. Never commit, push or merge: Claude does.
