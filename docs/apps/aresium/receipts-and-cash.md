# Aresium: Receipts and cash

Part of Aresium's notes; start at `docs/apps/Aresium.md` (its decisions in force). Covers receipts read from a photo, correcting receipts, cash entries, comfort in the windows.

## Receipts

**Receipts** (brief 31, the owner 2026-10-27; D8 in `ares-empire/docs/ARESIUM-FOR-OTHERS.md` → part 6; phone mode
only). **Capture:** in phone mode Import (the first screen's Import data, the dashboard's import button) is Apple's
menu: Choose file, Scan receipt (only where `VNDocumentCameraViewController.isSupported`; the iOS 27 simulator says
yes but cannot record, so there the scanner stops: "The scanner stopped. Try again."), Choose photo (`PhotosPicker`,
no library access needed); server mode keeps its button; in the tour every item only answers the import step
(`ImportChoices.tour`). `NSCameraUsageDescription` (German in `InfoPlist.xcstrings`). Reading on the phone
(`Model/ReceiptCapture.swift`): `RecognizeTextRequest` (accurate, the language detected, minimum text height 0.005:
the default dropped pieces of a long receipt) and `DetectBarcodesRequest` for QR codes, which falls back to Core
Image's QR detector when it throws (its model does not load on the simulator); off the main actor, cancelled with
its sheet; the image is never written and is released after reading. Vision's boxes become the engine's in one place
(`ReceiptBox`: top left, y down, page n at y = n). **The engine:** `readReceipt` (shop, date, total, currency, card or
cash, the rows, what it is sure of), `matchReceipt`, and `buildDashboardSource`'s `receipts` (`AresiumEngine`,
`EngineTypes.swift`). **The check window** (`Model/ReceiptCheck.swift`, `Screens/ReceiptCheckView.swift`, the file
check window's look): "This is what Aresium read from the receipt:", the fields not sure or not found first under
"Please check" (each says which: "Aresium is not sure about this." / "Not found on the receipt."), then "Read from
the receipt"; Shop (text), Date (Apple's date picker), Total (with its currency, brief 33; an undecided "kr" must
be chosen), Paid by Card / Cash (segmented; not read: Card only when a stored bank payment matches, with
that said, else nothing and Save waits), Amount in euros (another currency paid in cash, required), Category (the
person's categories and Not sorted; the shop list's one preset when chosen; one picked by hand teaches the shop),
"As on the receipt" folded, "Does this look right?" and Save (the line above it says what is still missing).
Nothing read: the same window empty ("Aresium couldn't read this receipt. Type what it says:"). **Keeping and
joining** (`Model/Receipts.swift`, `Model/PhoneReceipts.swift`, `StoredReceipt`): the read rows and the confirmed
values, never the image. A card receipt is matched on Save (`taken`: other receipts' payments and the ones the person
declined): one exact match joins at once (a payment Not sorted takes the receipt's category, source `receipt`:
"Sorted by its receipt."), candidates ask **"Is this the same payment?"** in the same sheet (the receipt, then the
payments as the dashboard's rows with what differs: "€20.00 more: cash back or a tip?", "One of 2 payments with this
amount", "Paid in another currency"; "None of these" declines them and it waits), none waits ("Waiting for the bank
statement", counted on its own meanwhile, `provisional`). After every bank import (`PhoneBackend.importFiles` →
`matchWaitingReceipts`) the waiting card receipts are matched again: exact ones join (the result line adds "· 1
receipt joined"), candidates queue in `PhoneBackend.receiptQuestions` and ContentView asks them once each after the
import's windows and the category picker (`ReceiptQuestionSheet`; closing it lets the receipt wait). A saved
receipt's line goes to the import's result banner. **Cash** counts in its category and is taken out of the
withdrawals before it by the engine: the withdrawal's category shows a "Covered by receipts" row (`coveredBy`), which
opens those receipts. A card receipt in another currency waits outside the dashboard until joined (Settings → Receipts
shows it). **Pages:** a receipt row in a payment list (a clock mark and "Waiting for the bank statement" or "Paid in
cash") opens the receipt's page (`Screens/ReceiptPageView.swift`, `ReceiptPageModel`: shop, amount, the day written
out, Paid by and where it stands, Category with Change (learns the shop), the bank payment with Unjoin or Join with a
payment… (the engine's candidates, else money out from the receipt's day to a week later), "As on the receipt",
Delete receipt: unjoins, a category its payment took from it goes, the cash is uncovered). A joined payment's page has
a Receipt section (shop, day, the rows folded, Unjoin). Settings → Your data → Receipts lists them newest first with
where each stands. The tour's import step: "Files from your bank, receipts and cash come in here." (brief 59); the tour never
opens the camera or reads anything. Launch arguments (DEBUG, with `-samplePhone`/`-samplePhoneEmpty`):
`-sampleReceipt` (the made-up receipt, `ReceiptSample`, read through Vision and the engine: the check window, all
read but the shop; `-sampleReceiptShop REWE` prints a chain the shop list knows: all sure), `-sampleReceiptUnsure` (a café receipt without code, payment line or total word),
`-sampleReceiptBlank` (nothing read), `-sampleReceiptQuestion` (saved with two payments of its amount and one €20
more: the question), `-sampleReceipts` (kept receipts: waiting in Groceries, cash after the month's withdrawal, one
joined to the month's first REWE payment, one in pounds; then `-sampleCategory Groceries -sampleMonth <YYYY-MM>
-samplePhoneTransaction <shop>` opens a page, `-samplePhoneTransaction Covered` in Cash withdrawals the covered receipts,
`-samplePhoneTransaction REWE` the joined payment), `-openSheet settings -openReceipts` (Settings → Receipts),
`-openReceiptText` ("As on the receipt" open), `-choosePhoto` (the photo picker). Tests: `ReceiptCaptureTests`
(Vision, boxes, pages, photos, cancelling), `ReceiptBookTests` (a version 1 store from
`AresiumTests/Fixtures/ledger-v1`, export 2 and 1, joining, asking, waiting, after an import, cash and its covered
row, deleting, foreign cash, card or cash not read, the words in both languages). Screenshots: `build/31-*.png`
(part A), `build/31b-*.png`.

## Correcting receipts

**Correcting receipts** (brief 33 part A, the owner 2026-10-28: the window asked "Does this look right?" but seemed to
offer nothing to do when it was not; D9). **Every value looks like something to tap:** Shop and Total (and Amount in
euros) sit in the fields' box (`Ink.field`, a thin line; `fieldBox`, a tap anywhere on it focuses the field), the
total's currency and the category are the column check's `MenuChip` menus (any receipt's currency can be changed; an
undecided "kr" says Choose), the date and Card / Cash are Apple's own; under the top the quiet line "Something
wrong? Tap it and change it." **Edit after saving:** the receipt's page has Edit in its bar, a joined payment's
Receipt section Edit beside Unjoin; both open the same window filled from the stored receipt ("This is the receipt as
you saved it.", one section, nothing marked; `ReceiptCheckModel(editing:)`, `ReceiptEditSheet`,
`ReceiptPageModel.beginEdit`). Saving (`PhoneBackend.updateReceipt`): a new total, date, currency or card or cash
(`ReceiptEdit.matchesAgain`; said above Save while it was joined or is card: "Aresium looks for its bank payment again
when you save.") unjoins it (its payment loses a category it had from the receipt and is sorted again), forgets the
payments declined for it and matches it again as on Save (exact joins, candidates asked in the same sheet, none
waits); a new shop, category or euro amount only updates (a joined payment that took its category from the receipt
follows the new one). **Learning** (`Model/ReceiptCorrections.swift`): a shop name the person changed (on Save or
later) is remembered for the shop as read (`ShopNames.key`: lower case, letters and digits only; kept as
`StoredShopName`, the receipt keeps `shopAsRead`), so the next receipt read the same way shows it, in the read
section with "Corrected by you before." (`Mark.corrected`); saving the name exactly as read drops it. A category
picked by hand is learned for the shop as a Switch (`learnShop`, as in brief 31) and is now preset for the shop's
next receipt (`learnedCategory(forShop:)`, before the shop list's). The total and card or cash are never learned
(misreads are one print's; one shop takes both). Launch arguments (DEBUG): `-sampleShopCorrection <name>` (the
made-up receipt's shop corrected before, with `-sampleReceipt`), `-editReceipt` (Edit open on the page that
`-samplePhoneTransaction` opens, the receipt's or a joined payment's; `-editReceiptTotal <text>` types a total).
Tests: `ReceiptCorrectionTests` (every field changed and saved, Edit filled from the receipt, a new total joins
again or asks, cash instead of card, shop or category only update, the corrected shop through Vision and the engine,
forgetting it, the learned category preset, total and card or cash not learned, a version 2 store from
`AresiumTests/Fixtures/ledger-v2.store`, export 3 and restore of 2 and 1, schema 3's checks). Screenshots:
`build/33-*.png`.

## Cash

**Cash** (brief 33 part B, the owner 2026-10-28, D9; the engine is brief 32's, aresium 4de0b4b; `Model/Cash.swift`,
`Model/PhoneCash.swift`, `Screens/CashScreens.swift`). **Hand entries:** Add cash ("Bargeld eintragen"), the fourth
item of phone mode's import menu (the first screen's too; `banknote`) and the Cash page's Add spending / Add received
cash: one window in the check window's look (`CashEntryView`, `CashEntryModel`): Spent / Received (segmented, with
a line on what each is for), Amount (euros only), Date, What ("Where or what for" / "From whom or what for"),
Category (its home side's categories, then the other side's with `otherSide`, no transfers, Not sorted last;
`CashCategories`), and for Spent **Paid from**. Kept as a receipt (`CashEntryDraft` → `LedgerReceipt`: kind
`manual`, cash, its direction, no rows, never joined: `PhoneDashboard.source` never sends a hand entry's payment,
and cash is never matched); its category is not learned (an entry names an occasion more often than a shop). A store
with only receipts or entries shows the dashboard, not the first screen (`MainScreen.choose(phoneRecords:)`). The
entry's page is the receipt's page ("Cash entry"; title what was typed, else "Cash spent" / "Cash received"; a
received one shows what it still holds, Left; Edit opens the same window, `.entry` in `ReceiptEditSheet`; Delete
entry). **Paid from** (cash receipts and spent entries, in their windows and on their pages): Automatic (default) or
one withdrawal or received entry on or before the day, newest first, each with what it still holds (`PaidFromList`,
from the engine's movements, `CashPage.sources`; the last 92 days first, the older ones behind "Show older",
`CashPage.split`, Claude 2026-10-28); saved as `paidFrom` (`setPaidFrom`), the dashboard rebuilt; the
page says where the engine took it from ("From the withdrawal of 18 Oct", "From the cash received on 3 Oct", "… and 1
more", "From cash not recorded here"). Deleting a received entry, or making it spent, sends what was paid from it
back to automatic (`PhoneLedger.forgetPaidFrom`). **The engine:** phone mode always passes the receipts (even none),
with `direction`, `kind` and `paidFrom` (`SourceReceipt`), so the dashboard carries `cash` (`CashView`: the months'
withdrawn, received, spent, unaccounted; every movement from the wallet's side) and marks withdrawals
`cashWithdrawal` (`Transaction`). **The Cash page** ("Cash" / "Bargeld"; `DashboardRoute(cash: true)`): a row below
the categories on both pages of the dashboard (`CashRow`: a wallet mark, "Cash", what is not accounted for in plain
words, "€300.00 without receipts" / "300,00 € ohne Belege" since brief 215, as Overview's Cash months; no
amount column, set apart by a hairline), only while `cash` has a movement; it follows Current / Overview like a
category (`DashboardStore.cashRoute`): this month's page, or its months (`CashMonthsScreen`). The month's page
(`CashScreen`): Not accounted for with its number and "In your wallet still, or spent without a receipt.", then
Withdrawn, Received, Spent; Add spending, Add received cash; the movements newest first (`CashMovementRow`: day, place
or what, kind and category, what a source still holds or where the money came from, + / − amount); a tap opens the
withdrawal's payment page or the receipt's or entry's page; "No cash this month." with a line and the two buttons when
empty. A view: it counts in no total. **Names:** "Cash" / "Bargeld" is the page (one key; "Bezahlt mit: Karte |
Bargeld" uses it too), so one's own category may not take it (`PhoneCategoryList.reservedNames`); the withdrawals'
category is the engine's "Cash withdrawals" / "Abhebungen". The covered row in it reads "Accounted for" /
"Erfasst", "Counted where it was spent" (receipts and entries alike); its list "Accounted for". Launch arguments
(DEBUG, with `-samplePhone`): `-sampleCash` (made-up entries around the sample's withdrawal on the 18th: a gift from
grandma, a flea market paid from it, an ice cream after the withdrawal; last month a bike sold and a cinema ticket),
`-openCash` (the Cash page; `-cashMonth <YYYY-MM>` another month, an empty one for the empty state;
`-sampleOverview` its months), `-cashOpen <text>` (on the page, the movement whose place contains it),
`-addCash spent|received` (Add cash, from the import menu or with `-openCash` from the page), `-openPaidFrom` (Paid
from in that window, or on the page `-cashOpen` opened). Tests: `CashTests` (entries stored and never joined, no
payment to the engine, the window's categories and Edit, Paid from saved and passed, deleting a gift, the page over
two months, the words in both languages, the name check, only cash shows the dashboard). Screenshots:
`build/33b-*.png`.

## Comfort in the windows

**Comfort in the windows** (brief 40, the owner 2026-10-30; `docs/reviews/2026-10-30-swipe-and-comfort.md`; the pieces
in `Screens/WindowComfort.swift`). "Is this the same payment?" has **Later** top left (in the receipt window after
Save, in Edit receipt, after an import): what a swipe down does, the receipt waits and nothing is declined; after Save
it (and the swipe) shows "Receipt saved. It waits for the bank statement." and builds the dashboard again
(`ReceiptCaptureModel.later`); after an import the next queued question opens after it, and the next import asks
again. The file check has **Back** beside No from the second reading (Back and No share No's half, Yes keeps its own,
`EqualWidthRow`) and beside Import in the column check when there were readings (to the last reading; the column
check keeps its answers; `FileCheckModel.back`). **Number pads** (Total, Amount in euros, Add cash's Amount) have
Done above them (`numberPadDone`; iOS 26 floats it outside the keyboard's safe area, so the bottom bar rises clear of
it, `clearOfKeyboardDone`); Shop's Return moves to Total, What's Return closes the keyboard. **Cancel asks first**
(`DiscardingCancel`, as Contact & support's X: "Discard this receipt?" / "Discard this entry?" / "Discard your
changes?", Discard, Keep editing) when something would be lost: a new reading always (unless nothing was read or
typed), Edit receipt, Add cash and Edit entry once a value changed (`hasSomethingToDiscard`, `hasChanges`: amounts by
their number, the date by its day); Add cash's swipe down is held back on the same rule. **The busy sign:** the
tapped button shows the spinner (`BusyLabel`; a payment row in its amount's place; Edit in the bar in its word's
place), the others are greyed (`whileWorking`): a receipt's page (Edit, both Change, Unjoin, Delete;
`ReceiptPageModel.working`), Join with a payment, the question's rows and None of these. Launch arguments (DEBUG):
`-sampleImportQuestion` (two waiting receipts asked after a made-up import; `-tapLater` taps Later on the first),
`-typeIn shop|total|euros|amount|what` (the cursor there; several comma-separated, one every 2 s), `-askDiscard`
(Cancel tapped once there is something to discard; `-cashAmount <text>` types Add cash's amount), `-holdWork` (a
tapped button's work waits a minute) with `-tapWork category|unjoin|delete` on a receipt's page or `-tapAnswer
first|none` on the question. Tests: `WindowComfortTests`. Screenshots: `build/40-*.png`.
