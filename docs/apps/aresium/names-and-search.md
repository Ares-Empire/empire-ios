# Aresium: Names, shops and search

Part of Aresium's notes; start at `docs/apps/Aresium.md` (its decisions in force). Covers payment names and own names, shop identities, one bank name per shop, renaming and a name's page, "All from <name>", name search, a day's page.

## Payment names and groups

**Payment names and groups** (brief 43, data only; `Model/PaymentNames.swift`, screens in brief 44):
`LedgerPayment.place` always stays the bank name; sorting, learning and receipt matching use only those original
fields. Schema 5 adds `LedgerPayment.ownName` and merchant → name rules (`PhoneLedger.paymentNames()`); export schema
4 carries both, older stores migrate through every frozen version and exports 1–3 still restore. Delete data deletes
names with the store. Names trim whitespace and keep at most 60 characters (Swift grapheme clusters); empty removes
only the selected scope. Removing a payment override reveals a remaining shop rule; changing/removing a shop rule
leaves payment overrides intact. An empty merchant key allows only the payment scope.

## Shop identities

**Shop identities** (brief 54): one engine `shopIdentities` call per name/lookup job over the distinct keys of all
bank payments, receipts, stored name rules, learned category rules and bank-line-only probes (`ShopIdentities.swift`,
`names.identities`). `AresiumEngine.nameKeys` batches the full merchant keys, place-alone probes (counterparty =
place, empty description) and the engine's `cardMerchant(place)` checks in one bridge call. The probes share the
identity universe; they only qualify display names and never become additional learned/name rule keys.
Original merchant keys and stored/exported rules stay unchanged. Different names of one shop group together, including
receipts and cash entries; payment-only names and exact bank-line grouping for empty keys keep their behavior. A name
rule uses the exact merchant key first, then the lexical first rule of its shop. Renaming/removing a shop name
removes the other name rules of that identity. The category question counts that shop’s eligible other payments;
All replaces the learned rules of every current/stored key of the shop, so an older exact rule cannot win later.
Manual, receipt-set and own-transfer categories never move with it. Receipt learned-category presets use the same
exact-first, then valid lexical rule precedence as sorting, over the receipt's key and the learned keys only (as
`sortPayments` does for one payment), so opening a receipt never reads every stored payment. Receipt OCR name corrections still match the print as read.
When the engine revision changes (also on restore), manual corrections rebuild learned keys and obsolete name keys
move to their longest current whole-word prefix; an existing rule at that current key wins. Absent shops stay stored.

## Brief 44 API

**Brief 44 API:** get a `TransactionDetailStore` with `DashboardStore.transactionDetailStore(for:)` as for category
changes. `await prepareRename()` loads the detail and `renameInfo` (`PaymentRenameInfo`, nil in server mode);
`canRename` is false there. The info has `bankName`, effective `ownName`/`source` (`.shop` or `.payment`), both
`paymentOwnName` and `shopOwnName` for scope-specific editing/removal, `canRenameShop`, and `otherPaymentCount` (N,
all other bank payments of the same shop identity, 0 for an empty key). Call `await rename(to:scope:)` with `.shop` or
`.payment`: saves, refreshes the detail/info and rebuilds the dashboard/widget; use the existing `isSaving` and
`saveError`. Row and page use the same store. Phone samples use their real temporary ledger, as category changes do.
The lower-level `PhoneBackend.renameInfo(id:)` returns that info; `rename(id:name:scope:)` saves and returns the new
`TransactionDetail` (callers outside the detail store must reload their dashboard).

## One bank name per shop

**One bank name per shop** (brief 76): after counting, `PaymentNames` chooses `LedgerPayment.place` from the
shop identity's newest qualifying bank payment (booking date, then later store order) for every bank row without
an effective own name. A line qualifies only when the engine's merchant key of that line alone belongs to the same
shop identity AND `cardMerchant(line)` returns null. Card statements carrying a payment's amount/date never supply
the shop name; a payment service named as counterparty cannot supply it merely because the shop appears in the
description. Both checks use the engine, with no Swift copies of its patterns. If no line qualifies, each payment keeps its own bank line. A payment's own
name still wins over the shop rule; Own names off hides only own names, keeping the
shop's newest qualifying bank line. An empty merchant key keeps its own bank line. `Transaction.bankName` and the detail's
`bankName` carry that payment's original line whenever different, including when the title is the shop's bank name
(`isOwnName` remains false). Cash withdrawals, name pages/months, summed rows and the rename field follow the shown
name; receipts and cash entries keep their typed Shop. `PaymentRenameInfo.shopBankName`/`bankDisplayName` supply
the fallback to details and `RenamePlan.start`; original fields never change or reach the engine under a display name.

## Name search API

**Name search API** (brief 76, data only; screens in 77): `NameSearch.results(for:in:)` takes a query and
`Dashboard.nameGroups`; `DashboardStore.searchNames(_:)` uses a `NameSearch.Index` cached by dashboard `revision`
for keystrokes. A group retains `names`: shown spellings, every original bank line and every own name (also hidden
names). All query words must match one spelling, folding case, accents and ß/ss, with punctuation treated as spaces.
Ranking: equal, full prefix, all word prefixes in any order, all substrings, then one insertion/deletion/substitution
per query word of at least four letters (short words must match exactly as substrings). Within each tier: shown name,
more payments, newer last payment; the opaque key breaks remaining ties. Empty queries return none; at most 50 hits.
`NameSearchResult` returns `key` (also `id`), `shownName`, optional `matchedName` (the other original spelling),
`count`, positive `moneyOut`/`moneyIn`, `newestDate` and `categoryName` (the newest row's); `nameGroup(_ key:)`
looks up that result's group. Server mode has no name groups and returns no hits. The index builds once per
dashboard; `NameSearchTests` times 1,000 groups / 5,000 payments.

## Setting

**Setting:** `DashboardStore.ownNames` (or `PhoneBackend.ownNames`) reads `aresium.ownNames`, default true.
Settings calls `await DashboardStore.setOwnNames(_:)` to persist and rebuild, rather than writing defaults directly.
Off hides own names without deleting them. `Transaction.place` and `TransactionDetail.place` carry the shown name;
optional `bankName` is set only when different, `isOwnName` says whether the shown name is own, `ownNameSource` says
which scope, and `nameKey` is an opaque grouping key. These fields are absent in server data.

## All payments of this name

**All payments of this name:** `DashboardStore.nameGroup(for:)` looks up the prebuilt `Dashboard.nameGroups` dictionary
by a row’s `nameKey` (nil for excluded/covered rows or server mode). `PaymentNameGroup` has `rows` newest first,
`count`, separate positive `moneyOut`/`moneyIn`, and `months[YYYY-MM]` (`PaymentNameAmounts`, the same two numbers),
including zeroes for every dashboard month. Built once per dashboard on the ledger worker, after the engine counted
it: own names fold case and diacritics; otherwise the engine’s shop identities, or exact bank lines for empty merchant keys.
Receipts/entries keep their Shop on screen but join that shop’s key/rule (waiting card receipts count until joined,
as on the dashboard). Covered rows and payments counting in neither overall total are excluded; tags cannot add
them back. The ledger executor also does name saving, merchant-key input and the question’s count off main;
`PaymentNamesTests` checks the worker spans (`names.*`) and opens an actual schema 3 store with all record types.

## Renaming and the name's page

**Renaming and the name's page** (brief 44, the screens; the owner 2026-10-30: swipe left only, no direction setting;
**brief 47**, the owner's test of build 4: renaming was hard to find): the payment's page shows the shown name as its
title and, whenever different, this payment's original bank line small under it. **The name is edited where it
stands** (brief 47; brief 44's Name row, its Rename button and `RenameSheet` are gone): in phone mode with Own names on, a small pen
(`PenButton`: SF `pencil`, muted ink, 44 pt tap area, VoiceOver "Rename") follows the title, and a single tap on the
name or the pen (the owner asked for a double tap; a single tap is found without being told and a double tap still
works, its first tap opens the field; the owner agreed 2026-10-30) turns the title into a field in the title's own font
and place (a field's box reaching into the margin), the name all selected and the keyboard up
(`TransactionDetailSheet`: `nameEditor`, `PaymentRenameModel`; the selection is set once the field has the keyboard).
Under it "Your bank's name: …", "Only the name you see changes. …" and, while an own name shows, "Use the bank's
name" (bordered). The bar shows Cancel and Save instead of Done while the field is open (Save off while unchanged;
Cancel after typing asks, `DiscardingCancel`; the page's swipe down is held back while something is typed); Return
(the keyboard's Done) saves, and closes the field when nothing changed. `RenamePlan` (`Model/PaymentRename.swift`):
the field starts with the shown name, the bank's too. A new name asks whenever there is a merchant key and N > 0:
"Also the other payments from <bank>?" with "With All, new payments … get the name too.", **All N+1** (the shop's
rule; this payment's own name is dropped) or **Only this one**. "Use the bank's name" on a name other payments share
through the shop's rule asks "Use the bank's name for all N+1 payments?": **All N+1** (the rule goes), **Only this
one** (brief 47: this payment shows the bank's name while the shop keeps its name; stored as the payment's own name
equal to the bank's name as names are kept, `PaymentNames.keptBankName`, read by `PaymentNames.shown` as no own name,
so the payment shows the shop's bank name and counts with that shop; export and restore carry it as any own name),
Cancel. Server mode and Own names off: no pen, no field. **The category** (brief 47): the chip and a pen beside it ("Change
category") open the change window, an extra category's chip opens it at Add; the Change button and the reason sentence
went, the reason (`PaymentWording.categoryReason`) is one quiet line under "Currently in" at the window's top. Server
mode the same wherever the page has categories to change to.

## A day's payments API

**A day's payments API** (brief 76, data only; screens in 77): `DashboardStore.day(_:)` takes `YYYY-MM-DD` and
returns `DayPayments` cached by dashboard `revision`. `date`, `expenses` and `income`; each side has `rows` and
`total`, also accessible as `day[.expenses]` / `day[.income]`. Each `DayPayments.Row` has the usual `TransactionRow`
in `row`, a convenience `transaction`, `id`, and the dashboard's `Category` (name, icon, colour and kind) in
`category`. Rows keep the month lists' stable order and covered rows, one occurrence per payment despite extra
categories. The category is the primary list on that side, else its first list (server mode's Other, for example).
Totals come directly from `dayExpense` / `dayIncome`, including covered cash on the withdrawal's date; transfers
stay absent as in month lists. Phone and server mode both work; invalid/absent dates return empty lists and zero.
`dayDate(atChartIndex:scope:)` maps a zero-based day point on `.current` (including a review month) or `.month(key)`
to its date; `.overview`, missing months and indices outside the graph return nil. `DayPaymentsTests` compares every
sample day with the graphs and month lists in both modes, plus covered cash, extra categories and revision changes.

## A day's page and the search on screen

**A day's page and the search on screen** (brief 77, the owner 2026-11-01: "make days clickable too and lead to a screen
with that days expenses and income (in two tabs with swipe)", "A small search icon … search by names which uses own
given and also original names organized by best match"). **A day's page** (`Screens/DayScreen.swift` `DaySheet`, words
and the tap in `Model/DayPage.swift`): a short tap on a day of a day graph (the start screen's Current, a month's
page; `SeriesChart.onPick` → `DashboardStore.dayRoute(atChartIndex:side:scope:)`) opens that day on the side of the
graph tapped (`DayRoute`, `DashboardPlace.day`); holding and sliding still reads the graph and opens nothing. A sheet
(presented by `DashboardStack`), not a pushed page, so a sideways swipe turns its sides and a swipe down closes it; it
opens at medium height (`.presentationDetents([.medium, .large])`, Claude's choice: a day has a few rows, and the
graph that was tapped stays in view above it; pulled or scrolled up it takes the whole screen): the
bar "Day" / "Tag" with Done (as the payment's page's "Payment"), the day written out as the title, 22 pt bold
(`DayPageWording.title`, the payment page's date: "Monday, 12 October 2026" / "Montag, 12. Oktober 2026"; too long
for a centred bar title in German), the start screen's dots (`PageDots`, shared with `DashboardPages`), then the two
sides as pages (`TabView` paging): each the day's total to the cent under the side's word in the start screen's
heading (`SideTotal`, shared with `StartPage`) and the day's rows (`DashboardStore.day`, read in `body`, so after a
row's page or window closes it shows the store as it is) or one quiet line ("No spending on this day." / "Keine
Ausgaben an diesem Tag.", "No income on this day." / "Keine Einnahmen an diesem Tag."). **The rows**
(`PaymentRow(day:)`): a month's list's row with the category in the day's place (`PaymentRowLabel(category:)`: its
tile, and its name first in the quiet line, "Groceries · Munich"; every row has the same day there, and nothing else
says the category), the tap (the payment's page over the sheet), the long press (Change category, Rename, "All with
this name"); **no swipe of their own** (`PaymentRow.swipes`, Claude's choice, 2026-11-01): a swipe left on a row
would have to mean both "All" and "to Income", and the owner asked for the sides to swipe; tried with real touches, a
sideways swipe that starts on a row turns the side. "All" is in the long press and on the payment's page. A name's
page asked for there closes the sheet, then is pushed on the dashboard's stack (`DashboardStack.afterDay`). In the
tour the sheet has its spotlight and card; the tour's steps close it (`TourModel.closeSheets`). **The search**
(`Screens/SearchScreen.swift`, words in `Model/SearchPage.swift`): a magnifying glass (`magnifyingglass`, an
`IconButton` in `HeaderButtonLook`) in the start screen's header before the import button, phone mode only
(`DashboardStore.offersSearch`: server rows have no names). It pushes `DashboardRoute.search` on the dashboard's stack
(the header "Search" / "Suche" with its arrow and gear; the back swipe works): `SearchField` in Apple's search field
look (a capsule with the magnifying glass, the prompt "Search names" / "Namen suchen" and the clear button; the second
card and the line, the cursor in ink), the keyboard up as the page opens (once: back from a name's page it stays down
and the query is kept); a scroll puts the keyboard away. **Before typing** (Claude's choice): one quiet line, "Finds
your own names and the bank's." / "Findet deine eigenen Namen und die der Bank.", and under "LATEST" / "ZULETZT" the
names of the eight newest payments (`DashboardStore.latestNames`, `NameSearch.latest`), so the likely ones are one
tap away and the rows show what a result looks like; the line alone would leave the page empty above the keyboard. **While typing**: `searchNames` best match first; **a result** (`NameResultRow`, lines in
`SearchPage.Row`): the newest payment's category tile, the shown name with the money out (the list's red, "−84.50")
and under it the money in ("+35.00") when there is any, a quiet line "5 payments · 22 Oct · Clothes" (the newest
day, its year only in another year; "last"/"zuletzt" made the German line too long for the category), and when found
by another name that name in a second quiet line, up to two lines rather than cut: a bank payment's line "Bank's
name: MGP Vinted - Kleiderkreisel" / "Bei der Bank: …" (the key the payment page's VoiceOver line shares; "Name bei
der Bank" wrapped the row), an own name (another payment's, or hidden while Own
names is off) "Your name: …" / "Dein Name: …", a receipt's typed Shop alone (`SearchPage.kind`); a chevron, as rows
that open a page. A tap opens the name's page (`DashboardRoute.name`). No match: "No name found for “…”." / "Kein
Name für „…“ gefunden." DEBUG (with `-samplePhone`): `-openDay <YYYY-MM-DD>` (`-daySide income`), `-openSearch`
(`-searchText <text>` typed, `-searchKeyboardDown` without the keyboard), `-sampleShopLines` (made-up Vinted
payments under two bank lines, "MGP Vinted - Kleiderkreisel" four and three months ago, "Vinted, UAB" since, with one
sale on the 12th of last month: a search for "Kleider" finds it by the older line). Tests: `SearchAndDayScreensTests`
(which tap opens which day on which side, the day page's words and empty side, the rows' category, the page
following the store, the search only in phone mode, the result rows' lines in both languages, before typing),
`TourTests`. Real touches (a temporary UI test in `Aresus/AresusUITests`, deleted; 3 of 3 runs each, the day's
sheet again at medium height): a tap on the 12th opens its page on the side tapped, a sideways swipe starting on a row
turns to Income and back, a swipe down closes it, a row's tap opens the payment's page over it, the long press's "All
with this name" closes it and pushes the name's page, a hold-and-slide reads 5–20 Oct (the `graph` log) and opens nothing, a hold alone opens nothing, a tap on
Current's day opens it, the search's field has the keyboard at once, "Kleider" finds Vinted with its bank's line, the
result opens the name's page and back keeps the query, the edge swipe leaves the search. Screenshots:
`build/77-*.png`.

## "All from <name>"

**"All from <name>"** (a card under the date on the
payment's page, a withdrawal's too, and since brief 47 a receipt's and a cash entry's page opened from a list,
`ReceiptPageView(nameLine:openName:)`, `DashboardStore.receiptNameLine`; only when the group has more than this
payment; the long press; the swipe) opens the **name's page** (`Screens/NameScreen.swift`, `DashboardRoute.name`,
pushed on the dashboard's stack, so the arrow and the back swipe work; from the payment's sheet it closes the sheet
first): the count and range, Spent (and Received when any), the switch (brief 53), the graph above the months
(`showsGraph` = the Graph setting), then the months with a payment of the name oldest first, as a category's months
(`ValueRow` with the chevron; a month without the name has no row). **The name's months** (brief 55, the owner's fifth
round: the payments listed below the months were "very weird"; "make each month just as the other months"): a month's
row or its graph point (`SeriesChart.onPick`, the one hook) opens that month's payments of the name on a page of its
own (`NameMonthScreen`, `DashboardRoute(name:month:)`, pushed like the others): the name as the header's title, "Oct
2026 · payments" / "Okt. 2026 · Buchungen" under it (brief 215: "activities" went; "No payments" too) (a category's month list's line), the arrow and the back swipe
(Apple's, `BackSwipe` unchanged); its rows a category's month list's, in its order (`Transaction.listOrder`, by day):
`PaymentRow` with tap, long press and the swipe's All, no Add up (every row is the same name). All, "All with this
name" and a payment page's "All from" there go back to the name's page below instead of stacking a second copy
(`DashboardPlace.open`). A month with only money the other way (a refund of a shop, no purchase) keeps its row, its
payments being nowhere else: an empty bar and the money signed in its colour ("+€80", `NameWording.otherSide`). The
page (with every month's rows) is built once per dashboard (`DashboardStore.namePage`, cached by `revision`), never
in `body`. After a row's page, change sheet or Edit window closes (each now tells its list, `closed`), the month's page
follows a rename that took the name along, together with the name's page below (`NamePageStep.follow`,
`DashboardPlace.follow`, in place), and goes back one page when the month has no payments of the name left
(`NamePageStep.back`: renamed alone, moved out of the counted payments). The tour never reaches it. DEBUG:
`-openNameMonth <YYYY-MM>` with `-openName <text>`; `-sampleDay31` adds a made-up REWE purchase on the newest 31st,
`-sampleRefund` a made-up Zalando refund this month (a month with only a refund).
Tests: `NameMonthsTests` (`DayWordingTests`, `DashboardPlaceTests`). Screenshots: `build/55-*.png`. **The day's
tile** (brief 55, the owner: "44×" next to "44" was confusing): every tile showing a date (a payment's row, the Cash
page's movements, the receipt check's and the file check's payments) writes the day as the language writes it alone,
German "4.", English "4" (`DayWording.alone`, one function; Foundation's lone day has no dot in German either); the
tile keeps its size and shrinks its words at the largest text sizes (`DayTile`, "31." included). **The swipe** (`Shared/Design/RowSwipe.swift` since brief 93, shared with Aresus's drops: `RowSwipeRule`, tested, inside a `UIPanGestureRecognizer`
subclass, since a plain recognizer got no moves inside the scroll view): only a drag at least twice as sideways as
vertical and leftward (rightward on an open row closes it); it opens at 84 pt and fires at 55 % of the row (at least
168 pt) with a haptic at the threshold; one row open at a time, closed by a scroll or a tap elsewhere; the action is a
quiet grey "All" with a stack icon, VoiceOver's action "All from <name>", Reduce Motion fades it in. The month's list,
the name's page and the Cash page (brief 47) share one row (`Screens/PaymentList.swift`: `PaymentRow`, generic over
its label: `PaymentRowLabel`, or the Cash page's `CashMovementRow`; tap, long press, swipe, and the windows they
open). The long press adds Rename (it opens the payment's page with the name's field ready, `PaymentRowMenu.rename`;
no double tap on rows, which would delay every row's tap) and **"All with this name"** / "Alle mit dem Namen"
(brief 47: every entry short; "All from <long bank name>" could not be read; the lifted row shows the name; "dem",
not "diesem", which wrapped the entry) where the page offers them (`PaymentRowAction`); receipts' and entries' rows
add it too now that their page has the card.

## Own names

**Own names** ("Eigene Namen") is a toggle in Settings → Your data on this iPhone (`DashboardStore.setOwnNames`).
Launch arguments (DEBUG, with `-samplePhone`): `-sampleNames` (made-up own names), `-ownNames off`, `-openRename` (the
name's field open), `-renameText <text>`, `-renameSave`, `-renameBankName`, `-openAllFrom`, `-openName <text>`,
`-sampleSwipe <pt> -swipeRow <text>` (on the Cash page too), `-sampleLongName` (three payments under a long made-up
bank name this month; the engine sorts them into Clothes), `-sampleShopReceipt` (a cash receipt from the sample's
LIDL, so a receipt's page shows the "All from" card).
Tests: `PaymentNameScreensTests` (brief 47: `RenamePlanTests` for the field's start and the bank's name kept for one
payment, with export and restore; `PaymentRowMenuTests` for receipts' "All from" and the Cash page's rows).
Screenshots: `build/44-*.png`, `build/47-*.png`. Real-touch checks (a temporary UI test, deleted): a slanted vertical
drag scrolls and opens nothing; the back swipe from the middle still works 6 of 6. **The back swipe's distance**
(brief 47, the owner: "about half the screen" on a month's payments and the name's page; measured with real touches on
the iOS 27.0 simulator, iPhone 17, 402 pt wide, a binary search to 8 pt; slow = 150 pt/s held still before letting go,
flick = 3000 pt/s): a month's payments, the name's page, a category's months and Apple's own Settings → General all
go back after the same distance: a slow drag from the edge 189 pt (47 % of the width), from the content (x 100) 215 pt;
a flick from the edge 99–105 pt, from the content 53 pt; a thumb resting 0.3 s before it drags the same. That is
iOS's own rule (a slow drag goes back past about half the width, a flick at once), so the row swipe and the long press
take nothing from it and the gesture stays the system's. Measuring on a DEBUG launch that pushes screens (`-sampleMonth`,
`-openName`) misleads: count the pushes, and the month list's launch actions now act once (`launchActionsDone`), as
they reopened the name's page each time the list showed again.
