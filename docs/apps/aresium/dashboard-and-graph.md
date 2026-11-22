# Aresium: Dashboard, lists and the graph

Part of Aresium's notes; start at `docs/apps/Aresium.md` (its decisions in force). Covers adding up names in a list, which month Current shows, the payment page, comfort on the dashboard, the graph and the header, reading a graph, the graph moving away.

## Adding up names in a category's list

**Adding up names in a category's list** (brief 53, the owner's D after build 4: "10 Vinted purchases in Clothes in
October" as one row; `Model/PaymentSums.swift`, `Screens/SummedRows.swift`; phone mode only, server rows have no
names): only how a month's list of a category shows (Current and Overview); totals, the category's numbers, the export
and the engine never change. **Choices** (`SumChoices`, the more specific wins): everywhere (Settings → Dashboard →
"Add up same names" / "Gleiche Namen summieren", off by default), a category (the icon), a name (the name's page's
switch "Add up in every category" / "In jeder Kategorie summieren", on a card under the totals), a name in a category
(the swipe and the long press); every level but everywhere on, off or not set, and **a choice equal to what the levels
above give is not set** (fix 58, the owner 2026-10-31: in Oct 2026 Kleidung the icon did nothing after Vinted was added up
and separated by hand), so Separate after Add up, or a switch turned back, leaves nothing that outvotes a later choice.

## The icon shows what the list shows

**The icon shows what the list shows** (on while every name with two or more payments there is one row,
`PaymentList.allSummed`), not the category's own choice; its tap (`toggleCategory(_:names:)` with the list's
`sumKeys`) gives the category the opposite, clears the name-in-this-category choices there and gives the tap's choice
to any name there whose own (name page) choice says otherwise, so it always means all or none in that list; the name
page's switch sets the name and clears its per-category choices. Keyed by the category's stable id (`DashboardStore.sumCategoryKey`: "id:groceries"
for Groceries and Lebensmittel, "id:custom-…" for one's own; the dashboard's own entries such as Refunds by name) and
the opaque `nameKey`. Kept in Aresium's defaults (`aresium.sums`, JSON, `PaymentSums(defaults:)`), not in the export,
deleted with Delete data and "Forgot the code?" (`ModeStore.deleteLocalData`); tests and samples have an empty set in
memory (`DashboardStore(sums:)` defaults to it), the tour too, whose lists offer adding up on its own choices since
brief 59 (its addUp, sumIcon and allFrom steps; nothing is added up before them, so the rows earlier steps point at
stay single).
A choice keyed by a name key that later changes (a shop renamed gets an `own:` key) no longer applies. **The list** (`PaymentList`, built once per change of the dashboard or
the choices: `DashboardStore.paymentList(category:month:side:)` caches by `DashboardStore.revision`, which counts every
new dashboard, and `PaymentSums.revision`; the header's icon and the list read the same one): a name with two or more
payments there that adds up is one row where its newest payment would be (covered rows and rows without a name key
stay single). **The summed row:** the day's tile with a second tile peeking above it (`StackTile`, a stack, as SF
`square.stack`) and the count ("5×"), the name as the newest payment shows it, the days ("4–28 Oct" / "4.–28. Okt.",
Foundation's interval style), the net sum in cents with the list's sign and colour. A tap opens it in place: a card
(`palette.card`, the line, radius 12) holds the summed row, a hairline and its payments, each the usual `PaymentRow`
(tap, long press, swipe All); a tap closes it. Opening, closing, Add up, Separate and the icon animate with a spring
without bounce (0.38 s, `SumMotion`; Reduce Motion none): the card grows and clips its payments to its height, the rows
below glide. **The swipe** (`RowSwipeRule` with `count`): a single row whose name has more payments in the list shows
**Add up** / **Summieren** (`rectangle.compress.vertical`) and All; a summed row **Separate** / **Auflösen**
(`rectangle.expand.vertical`) and All; members of an open sum All only. The inner action is a raised tile (`Ink.card2`,
the edge, the first ink), All keeps its grey fill. Each action 84 pt (drawn 78, 6 pt gaps): one opens at 84, two at
168; the full swipe (the last, All) at max(open + 84, 55 % of the row): 168 for one (as before), 252 for two on an
iPhone 17's 378 pt row; past it All takes the whole room (`RowSwipeRule.widths`). VoiceOver actions by the same names.
The actions' words grow only up to the largest standard text size (fixed tiles; "Summieren" was cut at the largest
accessibility size), and a row's day shrinks into its tile there instead of turning into "…" (`DayTile` for every
tile since brief 55).

## The long press

**The long press** (`DashboardStore.rowActions(for: PaymentListEntry)`): a single row with a group in the list adds Add
up before "All with this name"; a summed row offers Separate and "All with this name". **The icon** (`SumCategoryButton`
in `ScreenHeader`, after red mode's X and before the gear): `square.stack` on the wall (brief 56: no box; on in full ink
with `square.stack.fill` at 24 % under it, its front tile lit, off the outline in muted ink; the filled symbol alone
reads as a jar); only on a category's month list while some name has
two or more payments there (not the Cash page, a name's page or a covered list); VoiceOver "Add up same names", a
toggle, On/Off. DEBUG (with `-samplePhone`): `-sampleSums on` (everywhere on, in memory), `-sampleSumOpen <text>` (opens
that summed row; `-sumsDelay <s>` first), `-sumsSlow <s>` (the motion stretched, for screenshots halfway),
`-sampleSwipe <pt> -swipeRow <text>` also on a summed row. Tests: `PaymentSumsTests` (`SumChoicesTests`,
`PaymentSumsStoreTests`, `PaymentListTests`, `RowSwipeTwoActionsTests`, `PaymentSumsStoreFlowTests`: the levels, the
clearing, a language switch, Delete data, the tour, the grouping, the menus). Screenshots: `build/53-*.png`.

## Which month Current shows

**Which month Current shows** (brief 215, the first-run review's finding 2: on 2 November a fresh import of three
months showed "Rent" and a two-point graph after "74 new"): one rule, `Model/CurrentMonth.swift`, read with the day the
person opened the app (`DashboardStore.openedOn`: at launch and on coming back from the background, never while the
app is open, so the start screen never changes its month under anyone): in a month's first seven days, while the
data's newest month is that running month and the month before it is in the data, Current opens on the month before
(the month review's month, a full month for the first look); otherwise on the newest month, as before. A month chosen
wins until the app goes to the background (`DashboardStore.CurrentChoice`, which holds what `reviewMonth` held): a
review message's, the range line's other month, or the newest from a widget's link (`showNewestMonth`: the widget
shows the newest). **The range line's other month** (`OtherMonthLink` in `StartPage`, Current only): on the right of
"OCT 2026", in the line's small capitals a little stronger, "NOVEMBER SO FAR ›" / "NOVEMBER BISHER ›" (the running
month, `Month.partial`) or "‹ OCTOBER" / "‹ OKTOBER" back (`CurrentMonth.other`, `CurrentMonthWording`): one tap
either way, kept until the app goes to the background; from the 8th there is none. Only the app's own dashboard has a
clock (`DashboardStore(clock:)`): tests, the tour and previews show the newest month whatever the day. DEBUG
`-openedOn <YYYY-MM-DD>` pins the day (screenshots, the real-touch check). Tests: `FirstRunTests`.

## The payment page

**The payment page** (brief 28, the owner 2026-10-27;
`Screens/TransactionDetailSheet.swift`, its words in `Model/PaymentPage.swift`, one place for both modes): "Payment" /
"Buchung"; the shop, the amount, the booking date written out ("Sunday, 4 October 2026" / "Sonntag, 4. Oktober 2026");
the category's chip with a pen (brief 47: both open the change window), the sentence on why it is there moved into that
window's top (`PaymentWording.categoryReason`; phone `structural` "A transfer
between your own accounts.", `learned` "Aresium learned this from a change you made.", `starter` "Sorted by Aresium's
built-in list.", `manual` "You chose this category."; server `rule` "Sorted by a rule.", `llm` "Sorted
automatically."; nothing for `none`, a payment not sorted, or a value it does not know); then Account (name,
IBAN in groups of four, "From your PayPal file" only when a PayPal payment's account is not called PayPal), To / From
(An / Von) by the direction, Payment text (Verwendungszweck; not when it repeats the title), Balance after, Value date
only when it is another day, and the server's Location, Trip, Kind of place (only the place types it knows) and
Recurring. No Source, Booking date or External ID rows. The bank's own row comes last, closed ("As in your bank's
file", or PayPal's). The labels form one column as wide as the longest (a `Grid`), above their values at the
accessibility text sizes. Its Edit and Unjoin are Apple's regular-size bordered buttons (brief 41; drawn 32 pt
tall, they take taps about 5 pt beyond their edges by themselves, measured on iOS 27.0; neither a tap area in the label
nor a content shape on the button widens that).

## Comfort on the dashboard

**Comfort on the dashboard** (brief 41, the owner's approved list of 2026-10-30,
`docs/reviews/2026-10-30-swipe-and-comfort.md`): **a long press on a payment row** (a month's list, both modes) is
Apple's context menu with what the row's page offers (`Model/PaymentRows.swift`: `DashboardStore.page(for:)` decides
what a row's tap opens and `rowActions(for:)` its menu, so the two never differ): a payment Change category (only when
its page shows Change), opening the same change sheet at once (`TransactionDetailStore.beginRecategorisationFromRow`:
it fills as the payment loads, or says why it could not, with Retry) with the same flow after it (the shop question,
learning, the tour's `paymentRecategorised`); a receipt or cash entry row Edit (the window its page's Edit opens,
`ReceiptEditSheet`; if it cannot open, the row's page opens); a withdrawal's covered row nothing (its long hold
opens its list, as a tap). The Cash page's movement rows have the same tap, long press and swipe since brief 47
(`DashboardStore.cashRows`: each movement's dashboard row; one the dashboard lists nowhere only opens its page). The back swipe and
this menu are the dashboard's shortcuts (`DashboardStack.shortcuts`): the tour turns both off while it holds the
screen (at the payment step the ringed row must open the page the card speaks of), except the rows' swipe and long
press at its swipe steps (`rowShortcuts`, brief 59). **The import result goes with a
swipe down** (`ImportStore.closesBySwipe`: where Close or the send card's Not now would, never while Retry and
Discard are offered or the format is sending, nor while the result scrolls; VoiceOver's escape does the same); a
success still goes by itself after 4.5 s. DEBUG `-sampleBannerDrag <points>` shows it moved as halfway through the
swipe (with `-sampleImportResult` or `-sampleFormat`). **Tap areas of 44 pt** (`minimumTapArea()` in `Screens/Components.swift`:
the area grows around a control drawn smaller, layout unchanged): the result's Close (brief 215: "Close" /
"Schließen", a key of its own; it was "Dismiss", which Aresium's catalog shared with Arestemis's "Entfernen", read as
removing the payments just imported), Retry, Discard, "What is
sent?" and Not now, the header's 42 pt buttons (`IconButton`, `headerButtonFace`) and the import button; the
Expenses/Income dots are 44 × 44 pt each. Tests: `DashboardComfortTests` (`PaymentRowMenuTests`,
`ImportBannerSwipeTests`, `LogOutQuestionTests`). Screenshots: `build/41-*.png`.

## The graph and the header

**The graph and the header** (brief 56, the owner's fifth round of 2026-10-31, items 5–7 in
`docs/reviews/2026-10-30-aresium-phone-test.md`). **The running month** (brief 215, the first-run review's finding
12: Overview's line fell at the unfinished month and read as "spent less"): every month graph (Overview's, a
category's months, a name's months) draws the stretch to a month still running (`ChartPoint.running`, the engine's
`Month.partial`) dashed, over a fainter area (`ChartStretches`: two series, no legend); the day graphs are unchanged.

## Reading a graph

**Reading a graph** (every `SeriesChart`: the start screen's day and
month graphs, a month's page, a category's months, a name's months): a finger held still for 0.25 s on the graph
(`ChartHold`, UIKit's long press, `ChartReading.holdDuration`, 10 pt of wander) and then followed shows a dashed guide
line (`Palette.guide`, the website's `--guide`), a dot on the line ringed in the wall's colour and a one-line chip just
above the plot, over the axis's "EUR" (the website's `.chart-tip`: the day written out "Wed 14 Oct" / "Mi. 14. Okt."
or the month "Sep 2026", a dot in the line's colour, the amount to the cent; `ChartReading.chip`, `ChartPoint.title`,
the nearest point `ChartReading.nearest`), a selection haptic per point; letting go hides it. A drag that moves before
the hold is up stays the scroll's, the pages' or the back swipe's; once the hold has begun they give way until the
finger lifts. A short tap opens a month where one opens (`onPick`): Overview's graph that month's page, a category's
that month's payments, a name's its month (brief 55); a day graph's that day's page (brief 77). VoiceOver reads the points as
before (the finger's layer is hidden). DEBUG `-readGraph <index>` shows the chip on that point (every graph shown);
the debug log category `graph` records each point read (the real-touch check reads it). **A month's page**
(`DashboardRoute(monthPage:side:)`, `MonthScreen`, pushed on the dashboard's stack; the header shows the month and
"Expenses and income" / "Ausgaben und Einnahmen"): that month as Current shows this month, the start screen's pages
(`DashboardPages`) over `DashboardScope.month(key)`. `DashboardStore` serves every scope (`.current`, which is the review
month while one is shown, `.overview`, `.month`): `totals(_:)`, `rows(side:scope:)`, `startChart(side:scope:)`,
`rangeLabel(_:)`, `route(category:side:scope:)`, `cashRoute(_:)`, `cashUnaccounted(_:)`, `monthPage(atChartIndex:side:)`;
the older `current:` forms call them. Its categories open that month's payments, its Cash row that month's Cash page.
Its Expenses and Income turn only with the dots (they slide; `DashboardPages(swipesPages: false)`): it is a pushed
page, so a swipe right goes back from either side, as on every pushed page (with the pager there, a swipe right on
Expenses only bounced; real touches, brief 56: middle swipe back 4 of 4, edge swipe at 400 pt/s 5 of 5; a synthetic
1500 pt/s flick from x = 2 right after a push was lost 3 to 4 of 5 there, on a category's page and on main alike). A
sideways swipe to the left that starts on a category row there opens that row (seen once; the row's button takes it).
DEBUG `-openMonthPage <YYYY-MM>` (with `-samplePhone`) opens it at launch.

## The graph moves away

**The graph moves away** (Settings → Dashboard, under Graph and only while the graph shows: "Graph moves away when
scrolling" / "Diagramm weicht beim Scrollen aus" (the Graph row is "Diagramm"), one line; `aresium.graphMoves`,
`GraphMotionSetting` beside `GraphSetting` in `Model/GraphSetting.swift`, on by default, not in the export; the tour
takes it when it starts, `TourModel.graphMoves`): the graph is the first part of its list (each start page and
month's page, a category's months; the name's page always had it so), so it scrolls up with the rows and nothing of
its own runs per frame (no view body, no state; the pages line up only when a scroll rests); off, it stays above the
list as before. Measured on the simulator (Time Profiler, the same eight finger-held 400 pt drags each way): no hang
either way; 2.8 s of main-thread time with it on against 2.0 s off over the run, mostly SwiftUI's own updates of the
larger moving content (the graph and the rows it uncovers); Aresium's code under 4 % of it (the graph's axis labels,
which Swift Charts asks for again while the graph moves, and the pages lining up at rest). Instruments' Hitches do not
run on the simulator, so frame drops are for the phone to judge. The range picker has its own row under the header; the Expenses/Income dots stand under it,
above the pages, so they are always in reach; a sideways swipe moves a whole page with its graph and heading. When a
page's list comes to rest, the page beside it lines up (`GraphMotion.follow`: the same place while the graph is partly
there, at least the graph's height while it is wholly away), and again as its first sliver comes into view (a page
out of sight may not take a scroll); while the graph moves, a page's content is at least the screen plus the graph,
so two rows can take it away as well. DEBUG `-scrollGraph <points>` scrolls the shown page that far. **The header**
(`ScreenHeader`, every screen alike): each button on the wall without card or outline (`HeaderButtonLook`: a 19 pt
symbol in the second ink, drawn 42 pt, taps over 44 pt, 44 pt apart): red mode's X first (the others keep their
places when it comes), then the page's own (the start screen's search, brief 77, and import button, beside the gear
since brief 56, with its menu and spinner, the tray with the arrow in, `tray.and.arrow.down`, as the drop overlay's
since brief 215: the arrow out read as share or export; a category's select icon, brief 82, and icon of adding up), then the gear; the title stays in the middle of the screen while it
fits (`HeaderLayout`). The tour's `.search`, `.importButton` and `.settings` rings follow them there. Tests:
`GraphAndHeaderTests` (`ChartReadingTests`, `MonthPageTests`, `MonthRouteTests`, `GraphMotionSettingTests`).
Screenshots: `build/56-*.png`.
