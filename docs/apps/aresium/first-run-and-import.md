# Aresium: First run, import, bank guide, tour, files from outside

Part of Aresium's notes; start at `docs/apps/Aresium.md` (its decisions in force). Covers the first screen, Start tour, an unknown bank's file, My bank is missing, How do I get my file?, the tour, files from outside and dropped files.

## Current view

**Current view:** a category opens this month's payments directly (`CategoryRoute`; the widget's category links too);
Overview keeps the month list first. **Screens** (`Screens/PhoneScreens.swift` and `Screens/FileCheck*.swift`,
Claude's look from the dashboard's rows, `CategoryTile`/`DayTile`, and the Settings pieces; ink only): **the first
screen** (brief 25, the owner 2026-10-27; `PhoneFirstScreen`, logic `Model/FirstScreen.swift`): while phone mode has no
payment, a calm empty state a little above the middle (a mark in a thin circle as the store's own states): "No data
yet", one line on what Aresium does and that everything stays on this iPhone, **Import data** (the main button) and
**Start tour** (quiet), then the quiet links "How do I get my file?" and "Restore from an export"; it ends with the
band. **The file first** (brief 27, the owner 2026-10-27: Import data had opened the categories, which felt wrong):
Import data, the dashboard's import button and the guide's Choose file open the file picker at once. Choosing
categories is no step of its own: **when an import in phone mode ended and added payments while no category is
chosen, the category picker opens** over the dashboard with the payments already in, whatever brought the files (the
file picker, the share sheet, the file check window), once per import (several files: after the last, also after a
file check that was skipped). Not after a cancelled picker, a failed file, a file whose payments were all there
already, a restore from an export, the tour, or with categories chosen. It is decided in one place, the import's end
(`ImportStore.finishIfDone` → `asksForCategories`, with `AresiumBackend.waitsForCategories`; ContentView only presents
it, once no other sheet is open). Its line on top: "Your payments are in. Aresium sorts them as you tick." Ticking
sorts the waiting payments at once (`PhoneBackend.choose`). **Done with nothing ticked asks once** (brief 215, the
first-run review's finding 1: a newcomer who tapped Done to "look first" found every payment Not sorted and a quick
sort that offered only Own transfers and New category): Apple's alert "Use the 12 categories that fit?" / "Die 12
passenden Kategorien verwenden?", "Aresium sorts your payments right away. You can change your categories any time
in Settings → Categories." (`ChooseCategoriesWording`), **Use** / **Verwenden** (a plain button in ink: ticks every
default category the rows count payments for, `CategoryPickerModel.fitting`, sorts and closes, `useFitting`) and
**Not now** / **Nicht jetzt** (closes as it is: the payments stay Not sorted and the next import asks again). Nothing
that fits (or something ticked): Done closes at once (`closes()`). While it would ask, the sheet's swipe down is held,
so the way out is Done. **While no category is chosen** and payments exist (`DashboardStore.waitsForCategories`), the
start screen's pages start with one card in the quick sort card's look (`ListCard`, shared; `CategoriesCard`: the
categories' grid symbol, "Choose your categories" / "Wähl deine Kategorien", "Then Aresium sorts your payments." /
"Dann sortiert Aresium deine Buchungen.", one line each), and Not sorted's list has it in the quick sort card's place; it opens
the same list as after an import (`DashboardPlace.choosesCategories`, presented by ContentView with the import's;
Done asks there too). The quick sort's offer and card wait until a category is chosen (`QuickSortOffer.Moment
.categories`; the import's offer then shows). DEBUG: `-samplePhoneEmpty -sampleImport -samplePickerDone` (Done:
the question) `-sampleFitAnswer use|notNow`. Tests: `FirstRunTests`. **The result line stays true:** the import's line ("4 new · 0
already there · 0 sorted · 4 not sorted") waits under the picker and, when it closes, is counted again from the store
for that import's own payments (`PhoneImportResult.newIDs`, `AresiumBackend.recount`), then goes after the usual
pause; the files' lines claim no sorting. What shows is `MainScreen.choose` (the tour, the store's state, the first
screen, the dashboard): after the tour, finished or ended early, the first screen is back while there is no data, so
the made-up data is never shown outside the tour. Then the category picker (the default list by group, nothing
ticked at first, one's own names; unticking a category with payments asks where they go, Not sorted first; **each row
shows a quiet number** (brief 27, the owner 2026-10-27; `PhoneBackend.categoryCounts`): a ticked category and one's own
the payments in them, a default one not ticked how many of the payments waiting as Not sorted it would get if ticked
(one dry run of `sortPayments` over the waiting payments with every default category besides the chosen ones; nothing
stored; an estimate, since a learned shop's unticked category can take a payment), none at 0 or before any payment,
counted again after every change; in muted ink before the tick, under the name at the accessibility text sizes; read
out as "34 payments"; with numbers on the rows the picker's note adds "The number by a category is how many of your
payments it has, or would get once ticked."; in every picker: after an import, Settings → Categories, the tour's
Settings; one's own rows say their side and every ticked row whether it is also offered the other way, brief 70's
"Category sides on screen" in `categories-and-sorting.md`), after a Switch the alert "Also the other payments from <shop>?" (the count on its button), the store's
opening state.

## An unknown bank's file

**An unknown bank's file** (brief 23, the owner 2026-10-27: most people don't know what a CSV is;
`Model/FileCheck.swift`,
`Screens/FileCheckSheet.swift`): a window with the file's name, "Aresium doesn't know this bank yet. This is how your
payments would look:", the first 3 payments as the dashboard's rows (day tile, who or the text, the whole date, the
amount; no column names) and "Does this look right?" with Yes, import / No. The readings are the engine's
(`readingsOfUnknownFile`, up to 4, best first, computed at import and carried by `LayoutRequest`); No shows the next
one with a line on what changed (`FileCheckWording`: "Day and month swapped", "Money in and out swapped", "Name and
payment text swapped", …; none for the first shown or a reason without a plain sentence); after the last one (or with
none) the column check, the last resort (`ColumnCheckModel`, `Screens/FileCheckColumns.swift`): plain questions
("Which column is the date?", the amount or two columns for money out and in, the name, the payment text) as menus of
the file's columns by name and first value, how dates and amounts are written, the first payments read that way,
Import. Cancel everywhere leaves the file out; only the layout the person confirmed is saved. **Sending the format**
(`Model/BankFormatShare.swift`, `Screens/FileCheckSend.swift`): when a file is read with a confirmed layout whose
`shareableLayout` is ok (else nothing is offered and only the engine's reason is logged, category `formats`), the
import's result shows one quiet card, "Help Aresium learn your bank": the bank's name (the engine's name for it as a
suggestion when it has one; for an unknown file it has none today) and Send (the keyboard's Send too); "What is
sent?" opens the format as `SharedFormat` shows it (every column with what it holds, date and number style, separator,
any other setting, the name, the app's version and language). Send posts `{bank, layout, app_version, language}` to
the account server's `bank_formats` (no token, `Accept-Language` of the request; ares-empire `docs/ACCOUNTS.md` → Bank
formats). Not now, closing the result and Send each mean the layout is never offered again (a SHA-256 of its separator
and header in the outbox's file, below). Sent: "Thank you. Aresium learns your bank with the next update."

## "My bank is missing"

**"My bank is missing"** (brief 25; `Model/BankRequest.swift`, `Screens/BankRequestView.swift`): when the guide's
search finds no bank (`BankGuide.results` → `.unknown`), the list shows Another bank's steps in place under a card,
"We don't know this bank yet. The general steps below may help." with **Tell us about your bank**: it opens the name
(prefilled with the search text, following it until edited) and Send, so two taps; Another bank's own page ends with
the same card ("Your bank is missing? Tell us which one.", the field empty and focused). Send posts `{bank,
app_version, language}` to the account server's `bank_requests` (brief 26, ares-empire; `Accept-Language`, no token;
200, 400 with `message` and `data.bank.code`, 429 at 5 an hour per address). Sent: "Thank you. We'll look at adding
it." Not in the tour (its guide gets no outbox: nothing real is sent there). **One outbox for both**
(`Model/BankOutbox.swift`, generalised from brief 23's `BankFormatOutbox`): `BankOutbox` carries a `BankSubmission`
(`.format` or `.request`, each to its own collection through `BankOutboxAPI`) and keeps what could not go at once in
one file, `Application Support/Aresium/bank-outbox.json` (`PhoneStorage.bankOutboxURL`: the request bodies with their
kind and failed tries, and the asked format layouts; brief 23's `bank-formats.json` reached no phone, so nothing moves
over; an entry without a kind still reads as a format), deleted with Aresium's data. Offline or a server error: sent by
itself at the next start or foreground (`sendWaiting`, one round a minute), at most 3 tries (a try without a
connection does not count); a 400 is final (a card or form still on screen shows the server's sentence; a 400 about
the name only lets the person type it again); a 429 waits for the next start. **A name that looks like personal
data** (an IBAN, an email, a date, an amount, a long number) is not sent: "Only the bank's name, please: no account
number, IBAN, email, date or amount." under the field, for both kinds. The rule is the engine's own (`looksPersonal`,
which `shareableLayout` applies to a format's words; the bundle exports no `looksPersonal`, so the bridge's
`personalData` runs it through a one-column `shareableLayout`, `AresiumEngine.personalData`), loaded the first time a
name is checked (`BankNameCheck`); the server checks again. Sample mode only pretends. The dashboard's own
"Uncategorised" (engine and server) shows as "Not sorted" in both modes and the widget through `CategoryName.shown`
(AresiumShared); Switch, Add, routes and links keep the real name.

## "How do I get my file?"

**"How do I get my file?"** (brief 24, the owner 2026-10-27: he did not know how the first time): the per-bank steps of
brief 19's research, now in the app (`Guide/bank-steps.json`, one copy; how it was researched and what is unsure:
`docs/bank-export-guide/README.md`; `Model/BankGuide.swift`, `Screens/BankGuideScreens.swift`). A list with a search
("Your bank": every typed word starts a word of a bank's names, or a name is among the typed words, `BankSearch`),
Another bank always last; a bank's page: Website / App (only places with steps; for the other one line, "doesn't work"
or "Aresium knows no way" when no source describes one), the numbered steps, the quiet line "a button may be called a
little differently" below high confidence, which file (the bank's labels as chips) and why, Good to know (the limits),
how the file gets to Aresium (the bank's `toAresium` ways, the usual one open), Choose file (the file picker; the
files are imported once the guide has closed, and in phone mode the category picker follows while none is chosen). No
sources and no format names in the screen's own sentences (`BankGuideTests` checks the data). Opened from the first
screen, an empty dashboard page and Settings → Help → Get the file from your bank
(`SettingsScreen`'s `help` slot, Shared). **The tour** (brief 24, `Model/TourModel.swift`, `Model/TourData.swift`,
`Screens/TourScreens.swift`): offered as Start tour on the first screen and Settings → Help → Tour of Aresium, never by
itself; when it ends the first screen comes back while there is no data. The real dashboard (`DashboardStack`, the same view as the person's, on its own `DashboardPlace`) on
`TourWorld`: a store in `tmp/aresium-tour-<uuid>/` filled through the real import with `TourData` (a made-up VR Bank
file, this month always full), its own session (never logged in) and widget numbers inside that folder; the person's
store, categories and learned shops are never opened. The folder is deleted on End tour (always on the card), at the
end, when a widget's link or a shared file opens the app, and at the next launch if the app was closed during a tour
(`removeLeftovers`). **Twenty-three steps, twenty-two while the graph is hidden** (brief 59, the owner 2026-10-31: "update the
tour so it explains everything and is coherent"; brief 77 added the search, brief 82 selecting, brief 99 the quick sort,
brief 203 money paid back, brief 229 the average and fixed costs; `TourStep`, one walk: the start screen, a
category, a payment and what can be done with it, the list's swipe and adding up, Settings' places in their real
order, import, done): welcome; income (the page dots, the swipe); overview (the range); fixedCosts (brief 229: Overview's spending side,
the average/fixed line under the total, `.averageLine`; "Your average month and its fixed costs. Tap to see rent,
subscriptions and insurance, and when each is due." / "Dein durchschnittlicher Monat und was davon fix ist. Tippe hier
für Miete, Abos und Versicherungen und wann sie fällig sind."; a tap opens the real Fixed costs page, whose rows and
name pages are free to try; Next returns to the graph, as Search's Next continues the tour); graph (Overview's graph: hold
and slide reads each month, a tap opens its month's page, which the ring follows, and there a day's; the card says so:
"… A tap opens the month, or the day where it shows days."; Next); search (brief 77: the start screen's magnifying
glass, `.search`; on the search's page and the names it opens the tour points at nothing, so they are free to try on
the tour's store; Next, as the graph's, since the category's step brings the start screen back: "Search a name, your
own or the bank's. A tap shows all its payments." / "Such nach einem Namen, deinem eigenen oder dem der Bank.
Antippen zeigt alle seine Buchungen."); category (a row); payment (its row opens the page); rename
(`.paymentName`: the page's name and pen, the field while open; goes on when a name is saved, `onRenamed`); switch
(the category's chip and pen, `.change`; the shop question answered); payback (brief 203: the made-up trip's page,
`TourWorld.paybackTrip`, over the list, its section ringed, `.payback`; Next goes on; the page and the payment its link
opens are free to try on the tour's store); select (brief 82: the list's select icon,
`.selectIcon`; selecting frees the screen, Next goes on and ends it); addUp (the list's first single row whose name
has more payments there: the swipe's or the long press's Add up); sumIcon (the header's icon of adding up, `.sumIcon`;
its tap); allFrom (the name added up at addUp, `.summed(key)`, or its first row: All opens the name's page, which
stays under the next step's gear); categories (the gear, then Categories with Own names, `.dataRows`; the picker free);
messages (`.messagesRow`); lock; dashboardSettings (`.dashboardRows`: Graph, Graph moves away, Add up same names);
contact; import (files, receipts and cash); quickSort (brief 99: this month's Not sorted list with its card ringed,
`.quickSortCard`, "What an import leaves Not sorted, you go through here name by name. …"; the card opens the flow on
the tour's store, free to sort, and closing it goes on); done. Without the graph the graph step drops out and the Dashboard card
says only "Here you add up same names in every list." (`TourStep.text(showingGraph:)`): no card mentions the graph.
The cards' words are `TourStep.text` (German in the catalog). Each step points at a real control (`.tourAnchor`, anchor preferences; a payment row's and a summed
row's anchor sit outside their swipe, so the ring stays still and the swipe's actions lie inside it);
`.tourSpotlight` (shared since brief 139, `Shared/Design/TourPieces.swift`) on each screen and sheet draws a light veil in the wall's colour, `TourVeil.veil` 0.3 (brief 24 had
0.74, far too dark: the app under it must read easily, the owner 2026-10-27), and the full-ink ring, and keeps taps off
the rest except at the swipe to income; `.tourCard` the glass card with Next and End tour, on a sheet's scroll view
after its spotlight (the payment's page, the tour's Settings and the picker pushed there: on the sheet's
NavigationStack the list ran on under the card and Contact & support could not be reached, brief 59);
`.tourScrollsToTarget` scrolls only as far as it takes, the control's lower edge to 60 % of the view, and not at all
when it shows there (`TourScrollPlace`; a start page's moving graph went half away for a category row that nearly
showed). `TourData` has a third grocer (ALDI SUED, twice a month, varying made-up amounts) so Groceries keeps two names
with several payments after the switch step moved REWE out, and the icon step has something to add. A step goes on when the
person does the thing (`TourModel.update`: the swipe, Overview, a category, a payment, a name's page; `importTapped`;
`settingsRowTapped(_:)` for the Settings rows; `paymentRenamed` through `DashboardStore.onRenamed`;
`paymentRecategorised` through `DashboardStore.onRecategorised`; `sumsChanged` through `PaymentSums.onChange`, all
nil outside the tour) or taps Next, and Next gets the step's screen ready (`prepare`: Overview for the graph, the
payment's page, the list under it, the tour's Settings). While the tour holds the screen the back swipe and the rows'
long press and swipe are off (`DashboardStack(shortcuts:)`), except at addUp and allFrom, where the ringed row's swipe
and long press work (`DashboardStack(rowShortcuts:)`, `TourModel.rowShortcuts`) and the back swipe stays off. A step
whose control is not on screen (the person tapped the row's page open, or All at addUp) points at nothing, so the
screen is free until they come back; Next always gets the screen ready again. **Adding up in the tour**: its
`DashboardStore` has an empty `PaymentSums()` in memory, never the person's `aresium.sums`; the swipe's Add up, the
icon and the name's page's switch work on it; nothing is added up before addUp, so the rows the earlier steps point at
are single. In the tour the gear opens the tour's own Settings: the person's sections it points at in the real order
(Your data on this iPhone with Categories on the made-up store and Own names; Messages; Lock; Dashboard; Help →
Contact & support), each but Categories a picture of the tour's own state built from the real rows
(`OwnNamesRow`, `DashboardSettingsRows`, `MessageWording.state`) that only points and goes on: no setting changes, no
lock is set, no message planned and iOS never asked, no form opens, nothing is sent; the tour never sees `AppLock`,
`AresiumMessages` or the support form, nor writes the graph, own names or messages settings (`TourTests` compares the
app's defaults before and after a walk). The import button only answers its step, the band does not enter red mode.
VoiceOver: the card takes the focus at each step, the highlighted control stays reachable; Reduce Motion: the ring
jumps, nothing slides. Launch arguments (DEBUG, with `-samplePhone` or `-samplePhoneEmpty`): `-openGuide list|<bank
id>` (`-guidePlace app|website`, `-guideSearch <text>`, `-scrollToEnd` the page's end), `-tour <1–23>` (`-tourSettings`:
its Settings open). Tests: `BankGuideTests`, `TourTests` (every step's target and what moves it on, Next's screens,
the hidden graph's 22 and its words, the search's step, every card's German, adding up in memory only, the person's store and defaults
untouched, ending at any step). Screenshots: `build/24-*.png`, contact sheet `build/24-sheet.png`; brief 59's walk
`build/59-*.png`.

## Files from outside

**Files from outside** (brief 204, 2026-11-02; the owner asked for Aresium in the share sheet and for dropping a file on
the main screen). One way in for every file that comes from outside: ContentView's `receiveFromOutside` (the share
sheet's, Files' Open With's and AirDrop's copy through `route`, a drop's copies) → `ImportStore.receive(_:source:
.shared)`, held unread while the lock is on, the copies removed once read (`ImportFileReader.removeSharedCopy`) and
left-overs at the next launch (`clearInbox`, sparing the file the launch was opened with). **The share sheet,
checked with real touches** (a temporary UI test in `Aresus/AresusUITests` driving the simulator's Files app and
Aresium, deleted; 3 of 3 runs): made-up VR Bank and PayPal `.csv`, a CAMT `.xml` and an MT940 `.sta` in On My
iPhone; each one's share sheet shows Aresium in its app row; choosing it opens Aresium (from cold or from the
background), the category picker follows as after any import, the result line counts the payments and iOS's copy is
gone; with the lock on (Aresium's own code), from cold and after more than 10 s away, the lock screen shows, the copy
waits unread and is imported once the code is typed. **Found and fixed:** (1) iOS puts its copy in `tmp/<bundle
id>-Inbox` (an app with scenes), not `Documents/Inbox`, so the copies were never removed (`ImportFileReader.inboxes`
names both); (2) a file that opened Aresium from cold was read before the phone's store had opened, with the
server's types, so an MT940 `.sta` was refused ("Pick a VR Bank or PayPal .csv (or CAMT .xml) export."); files that
come before the mode is known now wait unread until it is (`ImportStore.unread`, read in `sessionChanged`). AirDrop's
"open in Aresium" hands the file over the same way; the simulator has no AirDrop, so that is untested.

## Dropping files

**Dropping files** (`Model/FileDrop.swift`, `Screens/FileDropScreens.swift`): phone mode's main screen (the first
screen and every dashboard page; not the tour, the store while it opens, server mode or behind the lock:
`FileDrop.targetOn`; sheets and the lock screen are views of their own and take no drop) takes one or several files of
the import's types by their own extensions (`FileDrop.importType`: CSV, CAMT XML, MT940, `.txt`, `.zip`; not
Markdown, a property list, an SVG or an export's `.json`, which only conform to text or XML; plain text only with a
name, so a piece of text dragged from a page is not taken; a mixed drop takes its bank files). Anything else gets the
system's "not allowed" badge (`onDrop(of: [.item])` with a `.forbidden` proposal). Letting go copies each file out of
the drop at once into `tmp/Dropped/<uuid>/` under its own name (Files suggests it; the system's copy lasts only while
its handler runs; the handler is built nonisolated, as Swift stops the app when the system calls a main-actor closure
on its own queue) and hands the copies to `receiveFromOutside`. **While accepted files hover** the screen fades
(0.18 s, 0.12 s with Reduce Motion; nothing moves) to the app's own wall (`Wall`; a veil let the first screen's
button and the dashboard's cards show through as grey ghosts) with the first screen's mark in its thin circle
(`tray.and.arrow.down`), "Let go to import" / "Zum Importieren loslassen" and the file's name (several: "2 files" /
"2 Dateien"); ink only, in light, dark and red. VoiceOver: a drop point "Import files" / "Dateien importieren" on the
header's title and on the first screen's heading (`FileDropPoint`; not tried with VoiceOver's own Drag). Letting go
starts the import feedback a picked file's import shows. **Real touches** (the same temporary UI test, 3 of 3): the
iPhone's two-handed drop played with XCTest's own touch paths (the private `XCPointerEventPath` and
`XCSynthesizedEventRecord`, two fingers in one event): one finger holds the file in Files until it lifts (0.55 s;
sooner Files scrolls, later its context menu opens and no drag starts) and pulls it out, a second swipes along the
bottom edge to Aresium, the first carries the file over Aresium, holds and lets go: onto a fresh install's first
screen, then the dashboard (the hover's words, the picker, the result, no copies left); `Notiz.json` gets the "not
allowed" badge and imports nothing; over the lock screen nothing is taken and nothing waits. Files' context menu
never reports its animations done, so XCTest waited 60 s after each touch there; the test switched that wait off
(`shouldSkipPreEventQuiescence`). Tests: `FileDropTests`, `AresiumTests.theShareSheetsCopyInTmpIsRemovedToo`.
Screenshots: `build/204-{share,hover,dropped}-{en,de}-{light,dark}.png`, red `build/204-{hover,dropped}-de-red.png`.
