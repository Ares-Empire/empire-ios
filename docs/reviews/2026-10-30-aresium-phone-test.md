# Aresium on the phone: Patrik's first test (2026-10-30)

Build 0.1 (1), internal TestFlight, phone mode (signed out), with Patrik's real VR Bank and PayPal files (rebuilt from
his server rows on 2026-10-29). Patrik keeps testing; new findings go here. Causes checked in the code and, for sorting,
on his files with the engine (numbers below are from that run, every default category ticked).

**Good:** the demo; the import explanation.

## Findings, most important first

1. **PayPal counted twice after "also move the others"** (bug; must be fixed before anyone else gets the app).
   After a Switch, `PhoneBackend.otherPayments` offers every payment with the same merchant key that was not set by
   hand or by a receipt. The bank's PayPal line ("Ihr Einkauf bei <shop>") and PayPal's top-up carry the shop's name,
   so they get the same key as the purchase and are moved out of Own transfers as well: the amount shows twice. The
   next sort puts them back (`applySort` sees the structural change), so it lasts until the next import or tick. The
   engine itself is right: all 158 bank PayPal lines and 158 top-ups are own transfers.
   *Fix:* the follow-up and `PhoneLedger.move` never move a structural payment; a test with the triple (purchase,
   top-up, bank line).
2. **Sorting on day one: 43% of payments not sorted** (400 of 930, own transfers not counted; 68% of all payments
   sorted). The plan's "98.4% right" is how many *sorted* payments were right, not how many get sorted.
   - **Vinted, 91 of the 400:** not in the shop list (marketplaces were left out) and under two names in PayPal
     ("MGP Vinted - Kleiderkreisel", "Vinted, UAB"). *Fix:* Vinted → Clothes in the hand-written rules.
   - **Card payments never learn:** VR Bank's card lines have no counterparty, only "Penny <town> DEU <town> EUR 9,47
     Umsatz vom … MC Hauptkarte …", and `merchantKey` keeps the amount and card text, so every payment is a merchant of
     its own (49 unsorted, 49 keys for 40 shops). That is why Penny had to be sorted three times; Penny through PayPal
     is a third spelling. *Fix:* cut VR's card tail (country, town, currency, amount, "Umsatz vom", card) in
     `merchantKey`, so all of them become "penny <town>".
   - **"Penny <town>" not in the shop list:** a short brand matches only before one of 24 big cities (`citySuffix`).
     *Fix:* a known brand followed by any town word matches, keeping the listed exceptions (Penny Reisen, Pennyblack).
   - **The other ~260:** people (rent, family), subscriptions (Apple, Anthropic, hosting) and small shops. Stable keys
     make each one a single correction; a few clear brands can be added. Also check: PayPal's currency-conversion rows
     sit in Not sorted (the dashboard leaves them out, but the list may show them).
   - *Cost:* engine changes in `aresium` (key, matcher, rules) with tests, measured again on these files. No cost in
     app size or speed (same list, one more pattern).
3. **Category picker slow; several ticks in a row impossible.** Each tap saves, sorts all payments
   (`PhoneBackend.choose`), refreshes, then sorts once more for the counts (`categoryCounts`), and every row is
   disabled meanwhile (`.disabled(model.isWorking)`). *Fix:* the tick shows at once and rows stay tappable; one sort
   after the taps stop (or on Done), then the counts.
4. **Own categories all get the same icon** (`CUSTOM_CATEGORY_LOOK`). *Fix:* an icon from the name (a word list in
   English and German: fitness → dumbbell, Haustier → pawprint, …), otherwise the next one of a set, so two own
   categories never look alike. Look: Claude.
5. **Save at the bottom of the category change screen** (`RecategoriseSheet`): far from a category at the top. Patrik's
   feeling matches iOS: an edit sheet has Save at the top right and Cancel at the top left. *Fix:* Save into the toolbar.
6. **"In der App der Bank geht das nicht, nur auf der Website." small and faint in dark mode** (bank guide,
   `FormNote`: 12.5 pt in `Ink.muted`). *Fix:* show this line as part of the guide, larger and brighter.
7. **Light mode** (not a priority): the default is "Like the iPhone" (`Appearance.iPhone`). Check on the phone:
   Einstellungen → Darstellung says "Wie das iPhone", and the app is light while the iPhone is.

**Order:** 1, then 2 (engine), then 3; 4–6 together (the look); then build 2 to TestFlight.

## Fixed in build 2 (2026-10-30)

- 1 and every other way of counting twice: brief 35 (the follow-up never moves own transfers; a test per path), brief 37
  (the same bank payment from two file formats), brief 34 (PayPal's withdrawals to the bank were counted as spending:
  found in Patrik's data, now own transfers; currency conversions too).
- 2: brief 34 (aresium e76fadd): on Patrik's files Not sorted 400 → 280; Vinted 91 → 3 (the 3 are sales); every Penny
  (card and PayPal) Groceries under one key; PayPal's own entries no longer keyed by the person's email. What stays
  is mostly people and services only the person can name: one correction each now.
- 3: brief 35. 4–6: brief 36. 7: brief 36 found a real bug (an open app stayed one light/dark switch behind) and fixed
  it in `AppRoot`, for every app.

## Second round: build 2 (2026-10-30)

Patrik: every finding above is fixed on the phone. New, about comfort (his phone is an iPhone 17, 120 Hz, so a
main-thread pause of more than about 8 ms shows while scrolling):

8. **Scrolling the category picker is sometimes jerky, most of all after ticking some.** Likely cause, from the code:
   after the taps stop, the picker sorts, counts and rebuilds the dashboard behind it (`CategoryPickerModel.flushPending`
   → `changed()`), and parts of that run on the main actor (`PhoneBackend` is `@MainActor`: `dashboard(auth:)` builds
   the engine's input from every payment there); each tap also replaces the whole list twice. *Fix:* brief 39 measures
   first, then moves the work off the main thread.
9. **No swipe back on the dashboard's screens** (Expenses → Groceries → a month: only the arrow goes back). Cause: the
   dashboard draws its own header (`ScreenHeader` with its back arrow) and hides the system navigation bar on every
   screen (`DashboardStack`), and iOS turns its back swipe off when the bar is hidden. Arestemis, Aresus and Arestoteles
   hide the bar on their tab roots too. *Fix:* brief 38 (the swipe, doing what the arrow does).
10. **Patrik's request:** find every other screen in the five apps that cannot be left with the usual gesture but
    should be, and other comfort gaps; he chooses which get fixed. Brief 38 (Aresium) and a read-only check of the other
    four apps.

## Fixed in build 3 (2026-10-30)

- 8: brief 39 (Codex). The suspect was real: the sort, the counts and the dashboard's input ran on the main thread, and
  SwiftData ran the ledger actor's jobs there too. Main-thread time after a burst of ticks, measured on the simulator:
  86 → 0.1 ms at 1,000 payments, 404 → 0.2 ms at 5,000. The dashboard is now rebuilt only when the picker closes.
- 9: brief 38 (`Shared/Design/BackSwipe.swift`): the system's own back swipe, from the edge and from the middle, on
  every dashboard screen with a back arrow; it does what the arrow does. Checked on the iOS 27 simulator; to check on
  the phone.
- 10: the list (`docs/reviews/2026-10-30-swipe-and-comfort.md`); Patrik approved every item. Aresium's are in build 3
  (briefs 40 and 41: Later, Back in the file check, Done on the number pad, Cancel that asks, the busy sign, a long
  press on a payment to change its category, the import result swiped away, 44 pt tap areas, Privacy and Imprint
  inside the app, Log out asks first); the other four apps' wait for their first TestFlight (CLAUDE.md → Open 15).
- Also: the German "Done" is "Fertig" now, iOS's own word (was "Erledigt").

## Third round: wishes after build 3 (2026-10-30 evening), built for build 4

Patrik, after testing build 3 ("fantastic work"), asked for:

11. **Rename payments** to names one remembers; Aresium keeps the name with the bank's, so new imports are still
    sorted by the bank's name and get the name automatically; the payment's page shows the bank's name small under the
    own name; a setting switches between own and bank names. *Built:* briefs 43 (data, Codex) and 44 (screens).
    Renaming asks, as the category change does, "Also the other N payments from <bank name>?" (All: the shop, also
    future imports; Only this one). Without renaming, "the same name" is Aresium's shop recognition, so the spellings
    of one shop count together.
12. **Add up all payments of one name**, reached by swiping a row (like Mail). *Decided (Patrik):* swipe left only, no
    direction setting (a right swipe would take the back swipe from the middle). Claude added, since a swipe cannot be
    seen: a visible "All from <name>" card on the payment's page and the same entry in the long press. *Built:* brief
    44 (the name's page: totals, graph, months, payments).
13. **The graph was off again after reopening the app;** he prefers it on. *Built:* brief 42: the graph is a setting
    (Settings → Dashboard → Graph, on by default, kept); the header's sun and graph buttons are gone (light and dark:
    Settings → General → Appearance). A category's page shows the graph above its months.
14. **Aresium's messages from the app, not Telegram,** with settings for whether, which and how often. *Done:* the
    Telegram bot (`aresium-bot.service`) stopped and disabled on the server. *Decided (Patrik):* two messages, an import
    reminder that names no bank or service, and a month review. *Built:* briefs 45 (local notifications, Codex) and 46
    (Settings → Messages, a one-time offer after the first import). Also: red mode's expense graph line was nearly
    black on the red; now light.

## Fourth round: after build 4 (2026-10-30 night)

Patrik: "very nice work"; new findings. **A** Settings' switches unreadable in dark (white track under a white knob)
→ brief 47. **B** the "Aresium" cover flashes when changing settings → brief 47. **C** renaming hard to find → brief 47:
tap the page's name or a pen (Patrik asked for a double tap; Claude chose a single tap on the page and no double tap on
rows, which would delay every tap: Patrik agreed), the category's chip or pen opens the change window, the Name row,
the big Change button and the reason sentence go (the sentence moves into the change window). The long press's last
entry ("All from <long bank name>") is too long to read → brief 47. **E** the back swipe needs half the screen on lists
with the row swipe → brief 47 measures against Apple's Settings. **È** one shop under changing names (Vinted MGP →
Vinted UAB, dm, Apple, cut-off names, names in another order, card fee text) → brief 48 (engine), then the app's wiring.
**Gaps after build 4** (Patrik: fix) → brief 47.

**D, summing payments of one name inside a list** (Claude's design with Patrik's additions, agreed 2026-10-30):
- Swipe left on a payment: **Zusammenfassen** (this name in this category, every month, remembered) and **Alle** (the
  name's page). A summed row: the name, a small stack mark with the count ("10×"), the total; a tap opens it in place
  (the payments below), a tap closes it; its swipe offers **Auflösen** (back to single payments) instead.
- **All names of one category at once:** a small stack icon at the top of the category's payment list, showing whether
  it is on; a tap sums or unsums every name there.
- **Every category:** Settings → Dashboard → a switch to sum every name in every category automatically (the icons then
  show on; tapping one turns it off for that category only).
- **One name in every category:** a switch on the name's page.
- The more specific choice wins (a name unsummed in one category stays single even when everything is summed).

**In build 5** (2026-10-30 night): C, A, B and the gaps (brief 47; E measured equal to Apple's Settings: a slow drag
goes back past about half the width, a flick of about 53 pt at once, so nothing changed); È (brief 48 in the engine,
aresium 01ebd85, brief 54 in the app: groups, names, "also the others" and receipt presets per shop); D as agreed
(brief 53: "Add up" / "Summieren", "Separate" / "Auflösen", the full swipe stays All). F (silky smooth) is no item of
its own: each brief kept work off the main thread and measured where it could.

## Fifth round: build 5 on the phone (2026-10-31)

First, build 5 looked like an old app (no Mitteilungen in Settings, English categories, no swipe, no new features):
logging in to Arestemis had switched Aresium to server mode, Patrik's old website data. The server now answers `phone`
for him too (aresium 7c87e02, `APP_SERVER_MODE_USERS` empty); after reopening the app, all was there. Then:

1. **A date's tile reads like a count:** a summed row says "44×", a single row "44". Patrik: write the day "44." so it
   reads as a date. → brief 55 (the day's number as the language writes a day alone: "4." in German, "4" in English,
   where the summed tile keeps its stack and ×).
2. **The name's page lists the payments under its months,** "very weird". Each month should be a row like a category's
   months that opens a page with that month's payments, with the back swipe. → brief 55.
3. **Settings felt laggy at times.** → brief 57 (Codex measures opening, scrolling and every switch, then fixes what
   holds the main thread).
4. **The category's add-up icon did nothing** in Oct 2026 Kleidung after Vinted was added up and separated by hand (it
   worked in Groceries). Cause: the icon showed the category's own choice, not what the list showed; after Separate it
   still said on, so the tap turned it off and nothing changed. → fix 58 (Claude): the icon shows what the list shows,
   its tap means all or none there, and a choice equal to what it would be anyway is not stored.
5. **New: the graph shows each month's number while sliding over it** (as on the website), and a tap on a month opens
   it. → brief 56 (every graph; Overview's month opens that month's page, as the website's).
6. **New: the graph moves away while scrolling the categories,** so they get more room; a Settings switch turns it off.
   → brief 56.
7. **Settings and Import on one level, without their boxes** ("unless you disagree"). → brief 56: agreed, and the other
   header buttons (back, the add-up icon, red mode's X) lose their boxes too, so every header looks alike.
8. **The tour explains the new features and switches** and stays coherent. → brief 59, after 55–58 are merged.

**In build 6** (2026-10-31 morning): 1 and 2 (brief 55: "4." in German, the name's months open their own page; a month
with only a refund keeps its row), 3 (brief 57: the Face ID check, Messages' choices and the category picker no longer
work on the main thread or redraw the dashboard; what remains on the simulator is iOS drawing the sheet), 4 (fix 58),
5–7 (brief 56: hold 0.25 s, then slide; a tap opens the month, Overview's month as its own page; the graph scrolls away
with the list, "Diagramm weicht beim Scrollen aus" in Settings → Dashboard; the Expenses/Income dots moved under the
range picker; every header button without its box). 8 (the tour) follows in build 7.

**In build 7** (2026-10-31 evening): 8 (brief 59). The tour is one walk of 18 steps: the start screen, the graph (hold
and slide, a tap opens the month), a category, a payment (rename it, change its category), the swipe to the left and
adding up (Summieren, the icon, Alle and the name's page), then Settings in its real order (Kategorien and Eigene
Namen, Mitteilungen, Sperre, Dashboard's switches, Kontakt & Support), import (files, receipts and cash), done. With
the graph off it has 17 steps and no card mentions the graph. Adding up in the tour never touches the real choices.

**After build 7** (2026-10-31 evening), Patrik: "its very clean. Ive only noticed one more thing we should add: In the
category change screen there should be a way to add a new category because otherwise you have to leave, create it,
come back." Then, for the receipt window and Add cash: "yes lets do that too, seems sensible".

**In build 8** (2026-10-31 night): brief 60. The change window's grid ends with "Neue Kategorie"; the receipt window's
and Bargeld eintragen's category menus end with "Neue Kategorie …". A name, Anlegen, and the new category is made (its
own icon and colour) and already picked; a taken or reserved name makes nothing and says why. On a payment of money in
the tile is not offered: a new category counts as spending until money in lands in it, so it could not take one (an
older limit, also in Settings; open for Patrik to decide).

**After build 8** (2026-11-01), Patrik on the money-in limit: "yes definetly, good call. own categories for income. but
not all default categories should show up there Id argue since not all of them can be income right? And not sure if
custom categories should be automatically shared between income and expenses because it could unnecessarily bloat the
menu." Claude proposed one home side per category (defaults by the engine's list, one's own by where it is made,
switchable in Settings), which he took ("yes good idea"), adding: "if category A is on expenses but also has incomes
then it should be addable not just switchable." So any category can also be offered on the other side, added from the
change window by using it there ("Andere Kategorie …"), removable again; money in on a spending category lowers its
spending, money out on an income category lowers that income. Transfers are offered both ways. Briefs 68 (engine,
Codex), 69 (data, Codex), 70 (screens, a Claude agent). Asked separately: should paid-back money still also count
under Einnahmen as Rückerstattungen (today it lowers the spending and counts as income too)?
Patrik's answer (2026-11-01): "booking everything as it happens is clearer and more truthful. Plus in the other way
errors are worse. So while returns and refunds are kinda weird with the expense 100 income 100 I do think doing it
that way is best overall and easier because we dont rely on matching." So every payment counts once, in the direction
it went, under its own category; nothing is subtracted (only a withdrawal's cash covered by receipts still moves to the
receipt's category). "Rückerstattungen" goes: money back shows under Einnahmen with its category's name. Brief 71
(engine, Codex); the sides only decide the menus.

**In build 9** (2026-11-01): briefs 68–71. Every category has a side. On an income payment the change window now
offers "Neue Kategorie" (made as an income category) and "Andere Kategorie …": a menu of the spending categories
(Freunde for a friend's payback); one picked there is offered for money in from then on, and a long press on its tile
takes it back ("Nicht für Einnahmen"). The same works the other way on a purchase. Settings → Kategorien shows each own
category's side under its name (a menu: Ausgaben, Einnahmen, "Auch für Einnahmen/Ausgaben"), says when a category is
offered the other way too, and the add row asks the side. Bargeld eintragen and the receipt window offer the categories
of their side. Counting: every payment once, as it happened (money out Ausgaben, money in Einnahmen, under its own
category; "Rückerstattungen" gone; a Zalando return shows as spent and received). Existing data keeps its menus:
own categories got the side their money gave them, and a spending category that counted as income (Freunde) stays
offered for money in.

**After build 9** (2026-11-01), Patrik: "sometimes the issue still happens that the same vendor has different names: I
found it in resales (check data)". Claude checked his files on the Mac: Vinted is one shop to Aresium (all 157 payments
in one shop identity), but each row showed its own bank line ("MGP Vinted - Kleiderkreisel" before, "Vinted, UAB"
after the change). Fix: a shop shows the bank name of its newest payment unless it has an own name (brief 76). New
feature: "Search expenses and filter by day … make days clickable too and lead to a screen with that days expenses and
income (in two tabs with swipe). For search: A small search icon … search by names which uses own given and also
original names organized by best match." Briefs 76 (data, Codex) and 77 (screens, a Claude agent): the day's page is a
sheet so its sides can be swiped; search finds names and opens the name's page. The bank files in Downloads may stay
on his Mac ("this is my device").

**In build 10** (2026-11-01): briefs 76 and 77. A shop shows one name: the bank line of its newest payment that names
it by itself (checked on Patrik's files: 101 of 167 shops get one name, Vinted "Vinted, UAB", Apple "Apple Services";
never a PayPal or a card statement line, which would show another payment's amount and date); the payment's page keeps
its own line under the title. A tap on a day of the day graph (Aktuell, a month's page) opens that day as a sheet:
Ausgaben and Einnahmen swipe, each with the day's total and rows (category in the day's place; rows have no swipe
there, the long press keeps "Alle mit dem Namen"). The magnifying glass in the header opens Suche: names (own and the
banks') best match first, a typo forgiven, "Bei der Bank: …" when found by another line, the newest names before
typing; a result opens the name's page. The tour has 19 steps (the search). Unsorted money in now shows as "Nicht
sortiert" on the income side too (it showed the engine's untranslated "Other").

**After build 10** (Patrik, 2026-11-01): Freunde was a spending category and could not be added for money in ("already
exists"); categories should be renamable and deletable ("on delete items that can be resorted get resorted and
otherwise not sorted"); several payments should be selectable like in Mail and moved or renamed at once; Add in the
change window should ask about the shop's other payments and whether to leave the current category (its button at the
end was easy to miss).

**In build 11** (2026-11-01): brief 80. A typed category name that exists is that category: in Settings → Kategorien's
add row and every window's New category it is offered on the other side ("Freunde gibt es jetzt auch für
Einnahmen."), ticked, or picked; only Nicht sortiert and Eigene Umbuchungen are refused. Freunde is offered both ways
when ticked. A category's long press in Settings → Kategorien: Umbenennen … (defaults too, "Originalnamen verwenden"
takes the original back), Löschen (own) or Entfernen (default): its payments are sorted again, what Aresium cannot
sort goes to Nicht sortiert. The tour's categories card says so. Also in it, not visible yet: brief 81's data for
selecting several payments (the screens follow in build 12 with brief 82, and Add's questions with brief 83).

**In build 12** (2026-11-01): briefs 81–85. **Selecting several payments** in a category's month list (Not sorted
too): the circle icon in the header; the rows slide right with circles as in Mail; "Alle"/"Fertig"; the bar's
**Kategorie** (the change window for all of them, Verschieben or Hinzufügen) and **Name**; one question for all their
shops ("Auch 92 weitere Buchungen von 3 Geschäften verschieben?"); then "… verschoben · Widerrufen". **Save in
Hinzufügen** asks "Auch aus Lebensmittel entfernen?" (Entfernen works like Verschieben) and then "Kleidung auch zu den
anderen 39 Buchungen von … hinzufügen?"; the button at the window's end is gone. The tour has 20 steps. The engine:
sorting round 1 (sales on Vinted/eBay/Kleinanzeigen, florists and gifts, many food words, more brands, clear purposes;
a bank's PayPal line counts as a transfer only for the months a PayPal export covers) and reading round 1 (no test
file read wrong any more; spreadsheet-rewritten dates, cut-off files refused, re-saved VR Bank files keep their ids).

**In build 13** (2026-11-01): the engine's sorting round 3 (chains as card statements spell them, "MC DONALDS",
"MEDIAMARKTSATURN", long company names; business words in compounds and cut off at the field's end; the SPC* prefix;
towns without their umlauts; regional utilities, car dealers and charging operators; memberships) and a list of
Germany's local places from OpenStreetMap (264,744 places, packed, kept loaded: about 13 MB). On Patrik's data a new
person's day one sorts 984 payments (was 966 before round 1), 969 as he has them, and needs 103 fixes over 14 months
(was 111). Settings → Über → Schriften & Lizenzen lists "© OpenStreetMap-Mitwirkende" with the ODbL and the list's
download (aresium.de/osm/).
