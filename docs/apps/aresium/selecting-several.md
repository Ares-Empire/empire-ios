# Aresium: Selecting several payments

Part of Aresium's notes; start at `docs/apps/Aresium.md` (its decisions in force). Covers the selection data API, selecting on screen, renaming several, selecting by sliding.

## Several payments at once — data API

**Several payments at once — data API** (brief 81; screens in 82; `Model/BatchChanges.swift`,
`Model/BatchLedger.swift`): phone mode's category month lists, Current and Overview, Not sorted included.
`DashboardStore.offersSelection(in:)` (or `category:month:side:`) and `selectableRows(in:)` exclude covered rows;
`selectionIDs(for: PaymentListEntry)` returns one id or all a sum's member ids. Keep a `Set<String>` of these row ids.
`selectionRows(_:)` resolves live rows; `selectionSummary(_:)` returns `PaymentSelectionSummary`: `counts`
(`BatchCounts.bankPayments`, `receipts`, `cashEntries`, `total`), `side`, positive `total` in euros, a shared
`currentCategory`, `canSwitch`, `canRename` (Own names must show). `offeredCategories(for:)` returns `[Category]`
from `PhoneCategoryList.offered` for that side, leaving out a common primary category. Empty, missing, mixed-month
or mixed-side action selections are refused (`switchCategory(ids:to:span: .allMonths)`, brief 99, lets one name's
payments of one direction span every month: the quick sort's card). Server mode offers nothing; the tour's ledger
uses the same API.
`switchCategory(ids:to:)`, `addCategory(ids:name:)`, `rename(ids:to:scope:)` are async/throwing and return
`BatchChangeResult`: `action`, `category`, `changed` and `skipped` counts, localized `message`, `undo`, optional
`followUp`. Switch sets bank rows manual and learns each payment, changes receipts as Edit (learns their shops)
and entries as Edit (no learning); one save, no sort. Add preserves primary/source and extras, skips bank rows
already carrying the category and receipts/entries. `renameInfo(ids:)` returns `BatchRenameInfo` with
`bankPaymentCount`, `otherPaymentCount` (distinct shops, excluding selected ids), `shopCount`, `allPaymentCount`
and skipped receipt/entry counts. `BatchRenameScope.payments` sets each selected bank row's own name;
`.shops` consolidates each distinct shop's rule and drops selected overrides; keyless rows get their own name.
Names use the single rename's trim/60-character rule; empty removes names in that scope. Receipts and entries
keep their typed Shop. These APIs also exist on `PhoneBackend` (save/summary only; no dashboard rebuild).
`BatchMerchantFollowUp` supplies `count`, `shopCount`, `shop` (one shop only), `category`, localized `question`;
`apply()` returns a new result with the same undo handle. It moves each eligible other bank payment once,
excluding manual, receipt-set, structural, own-transfer, selected and already-target rows, and replaces every
relevant alias's learned rule. `BatchUndo.perform()` returns `.undone` or `.unavailable` with a localized
`message`; the original handle also undoes an applied follow-up. Each store action, applied question and
successful undo rebuilds dashboard/widgets once. An observer of **every save on the ledger context** increments
a revision; tokens also check ledger identity and complete before/after value snapshots. An intervening import
or save (even changing a payment and changing it back) invalidates the whole undo/question before any write.
Undo restores only the changed row category/source/extras, own names, and added/replaced/removed learned/name
rules, with one save. The revision also protects planning across engine awaits. All ledger work
stays on its executor in one operation per action; the bridge's `learnMany` calls the existing engine `learn`
for each correction in one JSON crossing. Tests: `BatchChangesTests`, including 500 selected rows / 60 shops
(79.739 ms on codex-81, including learning, save and undo snapshots; the learning bridge 1.575 ms).

## Several payments at once on screen

**Several payments at once on screen** (brief 82, the owner 2026-11-01: "make expenses / incomes selectable and then
moveable / changable at the same time … like in Mail when selecting mails"; logic `Model/PaymentSelection.swift`, look
`Screens/SelectionScreens.swift`). **The icon:** a category's month list (Current and Overview, Not sorted included;
phone mode, while `DashboardStore.offersSelection(on:)`) has `checkmark.circle` in the header's buttons
(`ScreenHeader.select`, after red mode's X, before the icon of adding up; VoiceOver "Select" / "Auswählen"); nowhere
else. **Selecting** (`PaymentSelection`: the list's route and the ticked row ids, kept in `DashboardPlace.selection`, so
the header, the rows and the bar read one state; it follows its list through a rename, `isSameList`, and ends when
another page is on top, `DashboardPlace.path`'s `didSet`): the rows slide right by a circle and its gap
(`SelectionLook.inset` 34 pt) in selecting's own motion (`SelectionMotion`, brief 200 below; Reduce Motion: none), an
empty circle (muted ink) at each selectable row's left edge; a tap anywhere on a row ticks it, and so does a finger
sliding over the rows (brief 200 below) (`checkmark.circle.fill`, the app's ink with the tick in
the wall's colour; the row on `palette.card2`, radius 12; VoiceOver: selected). The rows' long press and swipe are off,
the scroll works. A summed row has one circle for its payments and stays closed (open sums close as selecting
starts); a withdrawal's covered row has no circle and is faded (0.45). **The header** (`SelectionHeader`, in
`DashboardStack`'s `PageHeader` in place of the screen's header, at its height, the same `HeaderLayout`): "All" /
"Alle" (then "None" / "Keine") on
the left, the count as the title ("3 selected" / "3 ausgewählt", "Select payments" / "Buchungen auswählen" at 0),
"Done" / "Fertig" on the right (ends selecting, nothing changed), words in ink on the wall; the back arrow, the gear
and the back swipe wait. **The bar** (`SelectionBar`, a bottom `safeAreaInset`, fading in and out with selecting):
Category
(`square.grid.2x2`) and Name (`pencil`), symbol over word, on the card colour laid over the wall's with the line on top,
into the home indicator's area; muted while off (`SelectionBarState`: both off at 0, Name off without a bank payment,
not offered while Own names is off, as the page's pen); it stays at the bottom under the keyboard. **Category** opens
the one change window: `RecategoriseSheet` is generic over `CategoryWindow` (`Model/CategoryWindow.swift`), which
`TransactionDetailStore` (one payment) and `SelectionCategoryChange` (a selection) implement; the picking (Switch's
target, Add's extras, a category made here or picked from the other side, taking one back, New category) is one shared
piece (`CategoryPicks` and the protocol's extension), so neither window copies the other. The selection's heading:
"10 payments" / "10 Buchungen" and their total under it, signed in the side's colour as a payment's amount shows,
"Currently in" the list's category; its lines say "they" (`CategoryWindowWording.modeLine`); the grid brief 81's
`offeredCategories`; Save switches (`switchCategory`) or for Add asks brief 83's "Also remove them from Groceries?"
(`prepareAddCategories`), then the shops' other payments in the merger's words (`CategoryQuestionWording`, e.g. "Also
move 92 other payments from 3 shops?", **Move 92 more** / **Only these**), with the single window's alert pieces.

## Name

**Name** (`SelectionRename`, `selectionRenameAlerts`): Apple's alert "Name for 10 payments" / "Name für 10 Buchungen"
(the bank payments that take it), the field with the name they all show or empty, "Receipts and cash entries keep
their shop." when any are ticked, Cancel and Rename (a plain button in ink); Rename is on once the name is new. Then,
when the shops have other payments (`renameInfo(ids:)`), the single rename's question for all of them
(`SelectionRenameQuestion`: "Also the other 14 payments from these 3 shops?", one shop "… from REWE?" with the name they
show, else "… from this shop?"; "With All, new payments from … get the name too."; **All 24** (`.shops`) / **Only
these** (`.payments`)); without others the payments alone. **After an action** selecting ends, the list shows the store
as it is, and the shared undo bar (`UndoBar`, `accent: nil` = Undo in ink; above the selection's bar while one shows)
says it in brief 81's words (`result.message`; after All the selection's and the others' count together,
`SelectionWording.done`) with Undo (`BatchUndo.perform`); a refused undo shows its line alone ("Cannot undo because
the data changed."), as does a failed action (`UndoOffer(message:)` without Undo, Shared). **The tour**: step 12 of 23
(`TourStep.select`, after the payment's paid back step and before Add up): the ring on the icon (`.selectIcon`), "Tap to select
several payments and move, rename or link them at once." / "Tippe hier, um mehrere Buchungen auszuwählen und auf einmal
zu verschieben, umzubenennen oder zu verknüpfen." (brief 206 added "link"), Next; selecting frees the screen and works on the tour's store; Next ends it.
DEBUG (with `-samplePhone -sampleCategory <name> -sampleMonth <YYYY-MM>`): `-selectPayments <n|all>` (selecting, the
first n rows ticked; 0 none), `-selectionWindow` (Category; `-selectionMode add`, `-samplePick <name,…>`,
`-selectionSave`, `-selectionAnswer remove|keep|all|only`), `-selectionName` (`-selectionNameText <text>`,
`-selectionRename`, `-selectionRenameAnswer all|only`), `-sampleUndoRefused` (the refused line). Tests:
`SelectionScreensTests` (the icon only where offered, ticking, All/None, a summed row, a covered row, selecting
following its list, the bar's states, the window's heading and choices, Switch with the shops' question and one undo,
Only these and a refused undo, Add's removal question, one view for one payment and a selection, Name's start, question
and both answers, the words in both languages), `TourTests`. Real touches (a temporary UI test in
`Aresus/AresusUITests` driving Aresium, deleted): the icon starts selecting, a tap ticks and unticks, All and None,
Done ends it, Category → Climbing → Save → Only these moves Not sorted's rows out and Undo puts them back, Add →
Clothes → Save → Keep both → the shops' question → Only these, Name → the alert → the question → Only these renames
both, the list scrolls while selecting (4 of 4; a test that taps Rename in the very instant the last key is typed
loses the tap, a moment later it works). Screenshots: `build/82-*.png`.

## Calmer, and selecting by sliding

**Calmer, and selecting by sliding** (brief 200, the owner on build 14, 2026-11-02: "selecting statements is quite bouncy
… can we build it like mail so you can basically just slide your finger up and down and it keeps selecting statements
or when going up deselecting them"). **What bounced** (a recording of build 14 on the simulator, its frames measured;
`build/200-motion-before.{mp4,png}`): every tick slid the new circle in from up to 29 pt left of its place while the
old one slid away (the circle swapped two views, and the swap took the circle's own way in, `.offset(x: -34)`), and
the header's count rolled letter by letter with a blur for 0.56 s (`numericText`), drifting sideways as its width
changed; All and None slid every circle at once; the rows' spring (`SumMotion`, 0.38 s) took 0.49 s, its last 4 pt
creeping; the header swapped in one frame both ways; the bar came in one frame and sank out over 0.45 s; the list itself
never moved (0 pt, measured on the amounts' column, also with the bar coming and going at the list's end). **Now**
(`build/200-motion-after.{mp4,png}`): `SelectionMotion` (an ease-out of 0.25 s; Reduce Motion: none; DEBUG
`-selectSlow <s>`) starts and ends selecting (the icon, Done, the end after an action, open sums closing): the rows and
their circles slide 34 pt (done in 0.23 s, measured), the header and the bar fade in place (`PageHeader`: the two
headers in one `ZStack`, the selection's at the page header's measured height; the incoming header and the bar fade in
by themselves, `fadesIn`, since insertions there took no animation, not even a transition's own; the outgoing header
keeps its last words, `lastShown`). A tick fades the circle (both symbols always there, one seen) and the row's
background in 0.1 s; nothing moves; the count changes at once. Not sorted's quick sort card stays in its place while
selecting, faded (0.45) and taking no taps (it had gone, moving every row up). `SumMotion` is adding up's alone again.
The plain button's press dim (to about 80 % while the finger is down, back over about 0.3 s) is left: press feedback,
as iOS's lists give, not motion. **The slide** (`Model/SlideSelection.swift`, pure; `Screens/SlideSelect.swift`):
while a list selects, a drag that starts on a row's circle column (`SelectionLook.column`: from the list's margin to
the day's tile, 58 pt) slides at once in any direction; elsewhere on a row only a drag that starts clearly sideways
(the row swipe's measure, decided after 6 pt, `SlideStart`) slides, and may then turn up or down (Photos'); a vertical
drag there scrolls. The first row decides (`SlideSelection`: not ticked, the slide ticks; ticked, it unticks); every
row between it and the finger takes that state and every other row is as it was before the slide, so the way back
restores; a summed row is one row (`selectionIDs(for:)`); a covered row is passed over and no slide starts on it;
beyond the list's start or end the finger counts as over its first or last row. The finger's row comes from the rows'
frames in the list's own layout (`slideRow`, `onGeometryChange` in `SlideSpace.list`, the space around the gesture
so both are measured in one place; `SlideRows`: a lazy list lays out only the rows near the screen, and a finger
beyond them is over the nearest). Near the top or bottom of the visible part (`ScrollGeometry`: under the header,
above the bar) the list scrolls by itself (`SlideScroll`: a 60 pt zone, the speed growing with the square of the depth
to 900 pt/s at the edge and past it; a display link and `ScrollPosition.scrollTo(y:)`), the rows coming in ticked as
they pass under the finger; it stops at the list's start and where its last row stands just above the bar (not into
the band). One `SlideSelectRecognizer` (a `UIPanGestureRecognizer` subclass, as the row swipe's) over the whole list:
it asks where the touch went down (`SlideTracker.place`), fails at once off the rows, and the list's own pan waits for
it while it decides (`shouldBeRequiredToFail`), so a drag on the column never scrolls instead. A light selection haptic
per change (`sensoryFeedback(.selection)`; the finger hides the circle it ticks). Taps still tick one row; the header,
the bar and the undo bar work; the back swipe waits; VoiceOver is unchanged (the slide is a shortcut). Tests:
`SlideSelectionTests`, `SlideTrackerTests`, `SelectionScreensTests` (a slide over a real list with a summed and a
covered row). Real touches (a temporary UI test in `Aresus/AresusUITests` driving Aresium, with XCTest's own
multi-point touch paths, deleted; 3 of 3): down the column over five rows ticks five; down five and back up
two leaves three; a slide from a ticked row unticks; sideways on a row's middle then down ticks; a tap ticks one row;
Category opens the window for the slid selection; Done ends selecting; on a 48-row list a vertical drag on a row's
middle scrolls and ticks nothing, and a slide held at the bottom edge scrolls and ticks the rows that came into view
(held 5 s: all 48, the last row 8 pt above the bar). Screenshots: `build/200-slide-{en,de}-{light,dark}.png`,
`build/200-slide-de-red.png`.
