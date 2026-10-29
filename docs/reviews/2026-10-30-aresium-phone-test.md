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
