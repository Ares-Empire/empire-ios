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
