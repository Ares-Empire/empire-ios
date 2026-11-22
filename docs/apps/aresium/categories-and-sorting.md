# Aresium: Categories and sorting

Part of Aresium's notes; start at `docs/apps/Aresium.md` (its decisions in force). Covers counting as it happened, category names/rename/removal, category sides, Save in Add asks, quick sort, New category where a category is chosen.

## Counting as it happened

**Counting as it happened** (brief 71, the owner 2026-11-01: "booking everything as it happens is clearer and more
truthful"): every payment counts once, in the direction it went, under its own category (and its extra ones): money
out is Ausgaben, money in is Einnahmen, whatever the category's side; nothing is netted, so a returned order shows as
spent and as received, and there is no Refunds / Rückerstattungen row. The one exception is a withdrawal's cash covered
by receipts, which moves to the receipt's category. A payment's `categoriesIn` (its spending lists) holds categories
only for money out, its `incomeBuckets` only for money in; `PaymentNames` groups a row that has either. Unsorted money in counts under the same "Uncategorised" as unsorted money out (aresium cd20cf8, 2026-11-01; it was "Other", which showed untranslated and in English shared its row with the default category Other), so both sides show it as "Not sorted" / "Nicht sortiert" (`CategoryName.shown`).

## Category names, rename and removal

**Category names, rename and removal** (brief 80): every New category field uses
`PhoneBackend.useCategory(named:side:sorting:)`: a name in either original language or a chosen personal name,
ignoring case and accents, reuses that category. The result is made, existing, offered on this side, or a default
ticked (with waiting payments sorted). Built-ins and reserved page names still refuse. Settings clears the add row
and shows the result in a quiet line using the shown name; the change, receipt and cash windows pick it. A newly
ticked Friends is offered for money in too; existing chosen entries and restored side choices are preserved.
Holding any chosen row in Categories opens Apple's menu: Rename…, Use the original name while a default is renamed
(with its original name as subtitle), the existing side choices, then Delete for one's own or Remove for a default.
Rename uses Apple's name-field alert with a plain ink button, keeps a rejected name for correction, and checks other
categories while allowing its own current and original names. Defaults keep their personal name in the existing
`customName` field (no storage migration); it stays in both languages until restored to the original.
Delete/Remove confirms in Apple's dialog anchored at the row, with the payment count and re-sorting explanation;
Remove also says it can be ticked again. Both reuse `unchoose(id, moveTo: nil)` and sort: primary manual choices are
reset, learned rules and built-in sorting run again, unknowns stay Not sorted, extra-category references go, receipts
and cash entries become Not sorted. Own rules go with a deleted category; default rules wait for its next tick.
The tick's existing move-to sheet is unchanged. Rows/counts update in the picker; its close rebuilds the dashboard.
Dashboard source/detail/tag names use `PhoneCategoryList.name(of:)`; open category routes carry their stable id and
follow a rename (or close on removal), and stale widget name links open the dashboard. Sum choices keep their id keys.
Export schema 6 carries default personal names; schemas 1–5 still restore; SwiftData was on V6 then (now V8: `LedgerSchemaCurrent` in `PhoneStore.swift`).
The tour's categories card mentions holding to rename/delete. Tests: `CategoryEditingTests`, `TourTests` and the
existing category/window/export suites. DEBUG with `-samplePhone -openSheet settings -openCategories`: `-sampleRenameCategory <id>
-categoryName <name>` renames before display; `-renameCategory <id>` opens the alert; `-removeCategory <id>` opens
its confirmation; `-sampleTick <id,id,…>` seeds defaults absent from the sample (use it for Friends);
`-categoryAddName <name> -categoryAddSide spend|income` uses the add row; `-scrollToCategory <id>`
brings its row into view (`own` brings the add row). `-sampleNoOtherSide <id,id,…>` reproduces existing offers;
`-sampleCategoryPayments <id|name> -sampleCategoryPaymentCount <n>` puts made-up payments there for confirmations. Context menus are checked with real UI-test long presses.
Screenshots: `build/80-*.png` (English/German, light/dark).

## Category sides

**Category sides** (brief 69): every category has one home side, which since brief 71 decides only where it is
offered (the menus), not where its money counts. Defaults take `kind` from the engine's
catalog; one's own store `side` (`"spend"` or `"income"`) in schema 6's chosen category, alongside `otherSide` (false
by default) for any chosen category. Transfers have no side and are offered in both directions. `PhoneStorage.open`
runs `PhoneLedger.giveCategoriesSides` before exposing the store: the engine's old no-side counting (primary
categories, including receipts and cash as usual) gives an own category income for a positive net, otherwise spending;
a default spending category with a positive net gets `otherSide`. An empty income default stays income. The internal
`sidesAssigned` flag makes this once-only, so removing an offer survives reopening. Export schema 5 keeps both values;
restore of schemas 1–4 assigns them after all payments and receipts are present. `PhoneCategoryList.offered(for:includingTransfers:)` is the shared menu rule: home categories, transfers when requested, then other-home categories
with `otherSide`; receipts and cash omit transfers and append Not sorted. The dashboard's engine `pick` has the same
membership, ordered by its totals. New category requires `CategorySide` in `PhoneBackend.addCustom(named:side:)`:
change window follows the payment, receipt uses spending, Add cash follows Spent/Received; Settings → Categories the
add row's side (brief 70). `setSide(_:of:)` changes one's own home and keeps the old
direction offered if it holds primary payments or receipts/entries; `setOtherSide(_:for:)` changes a chosen
non-transfer's additional offer. `ChosenCategory` equality includes both fields, so dashboard invalidation notices.
`TransactionDetailStore.otherSideChoices` lists unused other-home choices; `pickFromOtherSide` picks locally and shows
it last before the tiles. Save stores `otherSide` for the picks actually saved (Switch and Add); Cancel stores nothing.
`stopOffering` removes an additional offer immediately, except a home or current category. The tour uses its own
store and the same APIs. Tests: `CategorySideTests`, updated `NewCategoryInChangeTests` and
`NewCategoryInWindowsTests`.

## Category sides on screen

**Category sides on screen** (brief 70, the owner 2026-11-01: own categories for income too, menus not bloated, "if
category A is on expenses but also has incomes then it should be addable not just switchable"; a side only decides
where a category is offered, and since brief 71 every payment counts in the direction it went, so no screen explains
any effect on totals). Words in one place, `Model/CategorySideWording.swift` (both languages, tested); the German uses
the app's terms (money in = Einnahmen, money out = Ausgaben: "Geldeingänge" wrapped in the context menu). **The
change window** (`RecategoriseSheet`): the grid ends with two quiet action tiles in brief 60's look (`ActionTile`: the
tiles' size, the second ink, the line's thin outline, no category colour), for money in and money out alike, in
Switch and Add, phone mode only: **Other category…** / "Andere Kategorie …" (`square.grid.2x2`; the two-arrow symbol
looked like Own transfers' tile beside it), only while `otherSideChoices` is not empty
(`TransactionDetailStore.offersOtherCategory`), then New category, last as before. Other category… is Apple's menu
(not a sheet: tried with every default ticked, 30 spending categories for money in, it scrolls as iOS's menus do and
stays readable, and it spares a third sheet over the payment's page and the window): one quiet header line, "From
spending" / "Aus den Ausgaben" for money in, "From income" / "Aus den Einnahmen" for money out (`otherSideListLine`),
then the categories in the engine's order, each with its symbol in its own colour (`CategoryMenuIcon`: a UIKit image
drawn as it is, since a menu draws plain symbols in its own ink), `menuOrder(.fixed)` so the header stays on top when
it opens upwards. Picking one closes it and shows the category before the action tiles, picked
(`pickFromOtherSide`); Save stores it as offered here (brief 69). **Taking one back:** a tile offered here only from
the other side (stored, or picked in this opening; never this side's own, a transfer or the payment's current
category, `offeredFromOtherSide`) has Apple's context menu with one entry, "Not for money in" / "Nicht für
Einnahmen" (or "Not for money out" / "Nicht für Ausgaben", `stopOfferingEntry`, `minus.circle`); every other tile has
no long press. It stores at once (`stopOffering`); one picked in this opening only leaves the window, nothing stored.
No mark on such tiles: in the grid they read as categories like the rest, and the person put them there; the long
press is the only difference. **Settings → Categories** (`CategoryPickerScreen`, also after an import and in the
tour's Settings): one's own rows say their side in a quiet line under the name ("Spending" / "Ausgaben", "Income" /
"Einnahmen", 12 pt muted, the up-down chevron), which is Apple's menu: the two sides (`setSide`) and, after a divider,
"Also for money in" (or out) as a tick (`setOtherSide`). A ticked row offered on the other side too says so in the same
quiet line ("Also for money in" / "Auch für Einnahmen", or "Also for money out" / "Auch für Ausgaben"), for default
and own categories; that line is the same menu. Every ticked row but a transfer's has the same choices on its long
press (Apple's context menu; a default row only the tick); an unticked row and a transfer's none
(`CategoryGroup.Item`: `side`, `otherSide`, `canOfferOtherSide`, `choosesSide`, `showsOtherSide`). The line's menu is
laid over the row where a hidden copy of the line stands (`SideLineAnchor`, `overlayPreferenceValue`): inside the row's
button the button took its tap and ticked the row off (seen with real taps). The menus' tick is Apple's toggle
(`.toggleStyle(.automatic)`): Settings' `EmpireSwitchStyle` drew it greyed in a menu. Chosen from the line rather than
a chip on the right (the count and the tick are there already) or two sections (switching would still need a long
press, and the add row would be in neither). **Adding one** asks the side under the field, as a row's line (Apple's
menu, spending first, kept while the picker is open: `CategoryPickerModel.newSide`, `addCustom()`). A side change or
an offer refreshes the rows at once and builds the dashboard again when the picker closes (no sort). DEBUG (with
`-samplePhone`): `-sampleIncome` (the income side, also for `-sampleCategory`, e.g. `-sampleIncome -sampleCategory
Other -sampleMonth 2026-10 -samplePhoneTransaction Erika -sampleRecategorise switch`: a money-in window),
`-otherCategoryPick <name>` (picked from the list in that window), `-sampleOwnIncome <name,…>` (own income
categories), `-sampleOtherSide <id or own name,…>` (offered on the other side too), `-sampleChooseAll` (every default
ticked: the longest list). The menus and context menus need real taps: a temporary UI test in `Aresus/AresusUITests`
driving Aresium (deleted). Tests: `CategorySideScreensTests`. Screenshots: `build/70-*.png`.

## Save in Add asks

**Save in Add asks** (brief 83; phone mode, `CategoryQuestions.swift`): after adding a category, Save asks
“Also remove from <current>?” with the Foundation-formatted list of the remaining categories, Remove and Keep both.
Remove uses Switch's learning and shop question; Not sorted promotes the first category without asking. The quiet
bottom button is gone. Keep both, or changing only extras, asks whether to add/remove those extras on the shop's
eligible other bank payments. The count excludes rows already carrying an addition, rows without a removed extra,
own transfers and structural rows; receipt and cash rows have no extras. All adds/removes extras in one ledger job
and one rebuild, preserving primary categories and learning nothing. The follow-up's `wording` builds its title,
optional message and button titles for both one payment and a selection.

## Selection window API for Add

**Selection window API for Add:** call `DashboardStore.prepareAddCategories(ids:names:currentCategory:removing:)`
on Save with the list's category and the added/removed extra names (`offeredCategories(for:mode: .add)` omits
Own transfers). Present the returned `BatchAddRequest.question`
if present (`RemoveCurrentQuestion.title/message/removeTitle/keepTitle`); then call `request.save(removeCurrent:)`.
Without a question call `request.save()`. The returned `BatchChangeResult.followUp` is the usual shared, single-use
follow-up; its original undo also restores an applied answer. Remove switches only selected rows whose primary is
the list's category; the others get extras. Unsorted selected rows switch automatically. The lower-level
`addCategory(ids:name:removingCurrent:)` and `addCategories(ids:names:removing:removingCurrent:)` save an already
answered choice. The selection screens are brief 82's (below).

DEBUG (with `-samplePhone -sampleCategory Groceries -sampleMonth 2026-10 -samplePhoneTransaction REWE
-sampleRecategorise add`): `-samplePick Clothes -sampleAddSave` picks and taps Save after the sheet opens;
`-sampleRemoveAnswer keep|remove` answers the first alert and shows the shop alert. Tests: `AddQuestionsTests`,
plus updated new-category and other-side tests. Screenshots: `build/83-en-remove.png`, `build/83-de-remove.png`,
`build/83-en-add.png`, `build/83-de-add.png` (English/German; the Add screenshots use Keep both).

## Quick sort

**Quick sort** (brief 99, the owner 2026-11-01, after three sorting rounds still left about 240 of his payments Not sorted
on day one, most of them personal: "a way to see the top not sorted factors and going through them"; logic
`Model/QuickSort.swift` and `Model/QuickSortFlow.swift`, look `Screens/QuickSortScreens.swift`, phone mode only).

## The groups

**The groups** (`QuickSort.groups(in:)`, pure): every Not sorted row (no category; a withdrawal's covered row is none)
over every month, grouped by `Transaction.nameKey` (the name groups' key: shop identity, own name, or the exact bank
line for an empty merchant key; a person paying or paid by transfer is a name too) and **split by direction**
(`CategorySide(amount:)`: a name's money in and money out are two cards), ranked by count, then money in integer cents,
then the newest payment, then the key (singles last by that). A group has the newest row (its shown name), count,
cents, first and last day, up to three example texts (`Transaction.purpose`, the bank's text, set on phone rows by
`PhoneDashboard.addPurposes`; tidied, newest first, none repeated ignoring case and accents, none that only repeats
the name or the bank's line) and its ids. Built off the main thread (`QuickSortCache.build`, a detached task) from each
phone dashboard in `DashboardStore.reload` before it is published, and published in the same turn with its
`revision` (`builtQuickSort`), so `quickSortGroups` (and `quickSortTally`: names, payments, `hasRepeats`) never belong
to another dashboard; server mode has none. **Sorting a card** (`QuickSortCard`, a `CategoryWindow`, so its tiles,
Other category… and New category are the change window's own: the grid is one view, `CategoryGrid`, extracted from
`RecategoriseSheet`, with `pick`/`pickFromOtherSide` for what a tile does and `working` greying the others; New
category's `createCategory()` now returns the name it picked): a tap is brief 81's
`switchCategory(ids:to:span: .allMonths)` at once (by hand, every payment learned, one save and rebuild, its undo),
after storing a category picked from the other side as offered here (brief 69). Brief 81's question about the shop's
other payments is never asked: it is applied by itself only when every payment it would move is the same name's, same
direction and Not sorted in the rebuilt dashboard (`QuickSort.takesFollowUp`; by construction they are in the card, so
only payments imported while the flow is open, a shared file, qualify). Found while building it, and left alone: the
question can also hold the shop's payments in the other direction (a card of their own), its payments under an own
name (a card of their own) and its payments already sorted by the built-in list or a learned rule (the quick sort
changes no sorted payment). **The flow** (`QuickSortFlow`, in `DashboardPlace.quickSort`, a sheet of `DashboardStack`
at full height): the groups as they were when it opened, one outcome per card (`sorted(payments:)`, `skipped`, `gone`
for one whose payments were all sorted meanwhile); Skip; Undo puts back the last card sorted (brief 81's single-use
undo, so only the last; any later save refuses it with "Cannot undo because the data changed.", shown as a line), the
card shows again and the cards after it come again. The look (Claude's): the bar "Not sorted" / "Nicht sortiert" with
`navigationSubtitle` "3 of 12 · 41 sorted" / "3 von 12 · 41 sortiert" and Done (gone at the end, where the summary's
Done is the way out); the list's thin bar for how far; the card (`palette.card`, the line, radius 14): the direction in
small capitals ("MONEY OUT" / "AUSGABEN", "MONEY IN" / "EINNAHMEN"), the name in the payment page's title style (22 pt
bold), the money signed as the payment page shows it (`palette.expenseText` / `palette.balance`, mono 20 bold), "18
payments · Jan – Oct 2026" (Foundation's interval style: "Jan.–Okt. 2026"), a hairline and the example lines in quiet
type; VoiceOver reads it as one (`QuickSortWording.spoken`), the tiles are buttons. Over the tiles "A tap sorts all 18
and Aresium remembers the name." / "Einmal tippen sortiert alle 18, und Aresium merkt sich den Namen." (not "Ein
Tipp", which reads as advice). Undo ("Widerrufen", the shared undo bar's word, iOS's own) and Skip ("Überspringen")
in the selection's bottom bar (`BottomBar`/`BarItem`, shared with `SelectionBar` now). A tap sorts, a light haptic
(`sensoryFeedback`, not for an undo), and the next card slides in from the right while the last fades (from the left
after Undo; Reduce Motion: a fade). At the end a ringed check, "84 payments sorted" / "Nothing sorted", "From 9 names ·
3 skipped" or "… Everything is sorted.", Done. **Where it starts:** (1) **the offer after an import** (`QuickSortOffer`,
in the import result's place and card as brief 46's: `OfferCard`, shared with the messages' offer now): set by
`ImportStore.finishIfDone` when an import in phone mode added payments (`offersQuickSort`); shown while payments are
Not sorted once the import's work, the category picker and the result are gone, never over another window
(`ContentView.windowOpen` or the flow), in the tour or behind the lock; it goes first, the messages' offer waits
(`ReminderOffer.Moment.quickSort`). "34 payments not sorted" / "34 Buchungen nicht sortiert", "From 12 names. One tap
sorts all payments of a name." / "Von 12 Namen. Einmal tippen sortiert alle Buchungen eines Namens.", **Go through** /
**Durchgehen** (the flow) and **Later** / **Später** (also the swipe down). Answered by either, by opening the flow from
Not sorted's card, or over when nothing is left Not sorted (`QuickSortOffer.expires`, so it never shows later without
an import); the next import that adds payments offers again. The cards are **names**, not payees: the app calls
whoever a payment is with its name everywhere (Search names, the name's page), and "payee" / "Absender" are one
direction only. (2) **The card at the top of Not sorted's month list** (Current and Overview, both sides; while
selecting it stays in its place, faded and taking no taps, brief 200; `DashboardStore.offersQuickSort(on:)`: phone mode while some name has two or more payments Not sorted and a category is chosen, brief 215; before, the categories' card stands there):
`QuickSortListCard`, a list row on the card colour with the line, the stack symbol in the day tile's place, "Sort name
by name" / "Name für Name sortieren", "9 names · 42 payments · all months" / "9 Namen · 42 Buchungen · alle Monate",
the chevron. Not in server mode. DEBUG (with `-samplePhone`): `-sampleQuickSort` (made-up people to go through: a
relative's monthly transfers in and one payment back, a friend paid for a garage, a drinks shop),
`-sampleQuickSortOffer` (the offer, as after an import), `-openQuickSort` (the flow at launch; `-quickSortSkip <n>`
skips n cards, `-quickSortSort <category>` sorts the card shown, `-quickSortFinish` skips the rest: the end); the
card: `-sampleCategory Uncategorised -sampleMonth <YYYY-MM>`. Tests: `QuickSortTests` (grouping: names, persons, own
names, directions, covered rows, sorted payments out, ranking, all months, the texts; server mode; a tap: manual,
learned, the next import sorted by it; Skip and Undo, a refused undo; the question only for the name's own Not sorted
payments, newcomers taken; New category on a card; the offer's conditions and its end; the card on Not sorted; the
words in both languages; VoiceOver's line), `TourTests`, `MessageScreensTests` (the messages' offer after the quick
sort's). Real touches (a temporary UI test in `Aresus/AresusUITests` driving Aresium, deleted; 3 of 3 runs): the
made-up bank file imported into the empty store, the picker ticked and closed, the result gone, the offer's Go through
opens the flow; a tile sorts and the next card comes; Skip; Undo brings the sorted card back (and is then off); Done
closes it and the offer does not come back; Not sorted's card opens the flow, Skip, a swipe down closes it.
Screenshots: `build/99-{offer,list,person,shop,end}-{en,de}-{light,dark}.png`, red mode `build/99-person-en-red.png`
and `build/99-offer-de-red.png`, contact sheets `build/99-sheet-en.png`, `build/99-sheet-de.png`,
`build/99-sheet-red.png`.

## New category where a category is chosen

**New category where a category is chosen** (brief 60,
the owner after build 7: "otherwise you have to leave, create it, come back"): one piece for three places,
`NewCategoryModel` (`Model/NewCategory.swift`: the alert's name, kept after a name problem; whether the alert shows;
the busy state; the problem's line; `create(in:side:offer:)` resolves the name with `PhoneBackend.useCategory(named:side:sorting:)`,
Settings → Categories' path with its name check and brief 36's icon and colour, then the window's `offer` puts it
among its choices and picks it) and `Screens/NewCategoryPieces.swift` (`newCategoryAlert`: Apple's alert "New
category" / "Neue Kategorie" with the field "Name", Cancel and Create / Anlegen; `CategoryMenuRow`). **The change
window** (`RecategoriseSheet`, `TransactionDetailStore.newCategory`, `createCategory`): the grid's last tile, "New
category" with `plus`, the category tiles' size, the second ink and the line's thin outline, no category colour; in
Switch and Add, phone mode only, for money out and money in alike: the new category gets the payment's side
(`CategorySide.spend` / `.income`), so the engine offers it in that direction immediately. Create rebuilds the
dashboard and picks it (the target in Switch, an extra in Add); one
made in this opening of the window comes last, just before the tile (`madeHere`), the next opening has the
dashboard's order. While it is made the tile shows `BusyLabel` and the other tiles are greyed (0.4, `whileWorking`),
the segmented control and Save are off and the swipe down is held. Nothing about the payment is saved before Save;
after a Switch the shop question follows as for any category, and the shop learns it. Cancel after making one keeps
the category. **The receipt window and Add cash** (`ReceiptCheckView`, `CashEntryView`, both `CategoryMenuRow`): the
category menu ends with "New category…" / "Neue Kategorie …" (`plus`, after a divider); the same alert; the category
is made, offered and picked there (`ReceiptCheckModel.createCategory`, `CashEntryModel.createCategory`; in Add cash for
spent and received alike, with the side of that window); while it is made the chip shows a spinner and the menu is
off. A name problem (built-in or reserved) makes nothing and keeps the typed name for the next tap: one
line in the window's error style (the change window's under the grid, `FormProblem` under the menus' row) with
Settings → Categories' words (`LedgerError`). Create is off while the name is empty or spaces; the keyboard's Return
creates, and on an empty or spaces-only field iOS's Return closes the alert like Cancel (nothing made, no line).
Create is a plain button in the window's ink, not Apple's filled default button, which iOS draws in the system blue
whatever the tint (checked 2026-10-31). The windows' Cancel still asks first (a category picked is a change) and the
category stays after it. **The dashboard catches up:** a category made in the receipt window or Add cash whose window
was then cancelled changes no payment, so `DashboardStore.reloadIfCategoriesChanged()` (called by
`TransactionDetailStore.load` in phone mode) builds the dashboard again when the store's chosen categories differ from
the ones it was built with (`builtChosen`), so the change window offers it. The tour's switch step keeps the tile; a
category made there goes with the tour's store. DEBUG (with `-samplePhone`): on a payment's page with
`-sampleRecategorise switch|add` (and in `-sampleReceipt`'s or `-addCash spent|received`'s window): `-newCategory` (the
alert), `-newCategoryName <text>` (typed in it), `-newCategoryCreate` (Create: picked, or the problem's line;
`-holdWork` keeps it busy; `NewCategoryModel.debugLaunch`); on the page also `-newCategorySave` (then Save) and
`-newCategoryAnswer only|all` (the shop question answered). Tests: `NewCategoryInChangeTests`,
`NewCategoryInWindowsTests`. Screenshots: `build/60-*.png` (the menus open: a temporary UI test with real taps,
deleted).
