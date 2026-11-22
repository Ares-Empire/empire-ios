# Aresium: Money paid back

Part of Aresium's notes; start at `docs/apps/Aresium.md` (its decisions in force). Covers linking a payment in to the expense it pays back, the amounts, the lists, several at once, whether it comes off the totals.

## Money paid back

**Money paid back** (briefs 201–203, the owner 2026-11-02: expenses paid back to him, one in full and two by half,
should show only his share; he chose a link made by hand, "it remains a completely optional thing to do"). **The
rule** (brief 201, aresium `docs/API-DATA.md`; the second exception to counting as it happened): a payment that came
in can pay back payments that went out, all or a part, because the person linked them; those euros come off the
expense, in its month, day and categories (tags too, once in the headline), and are not income. Limits: a payment in
pays back at most its own amount, an expense gets back at most its own; only stored bank payments in euros, never
transfers, withdrawals, receipts or cash entries; nothing is matched automatically. The engine gives each transaction
`counted` (only when it differs), the expense `paidBack`/`paidBackBy`, the payment in `paysBack`, and the dashboard
`paybacksIgnored` (logged in DEBUG; empty after any app operation). **The data** (brief 202, `Model/Paybacks.swift`,
`Model/PaybackLedger.swift`): a link lives on the payment in (`LedgerPayment.paysBack`, ledger schema 7, export schema
7); every number the app adds up itself uses `Transaction.countedAmount` (name groups, summed rows, the day page's
totals, the selection's total, the quick sort); a move to a transfer category drops the links at either end (its
undo brings them back). `DashboardStore.paybackState(for:)` (direction and `rest`, nil where it cannot take part),
`paybackSuggestions(for:)` (what fits first: whole, half, a third, a quarter or the rest within a cent; then the
nearest days; money in from 30 days before to 120 after the expense; at most 8), `paybackSearch(_:for:)` (names as
the name search spells them, no date window), `setPayback(from:to:amount:)` and `removePayback(from:to:)` (one save,
one rebuild, a `BatchUndo`); `from` is always the payment in. The state and the suggestions skip the search's
spellings (`paybackCandidates(names: false)`: no shop identities; brief 203 measured the state at 146 → 69 ms on the
sample and 489 → 417 ms at 5,000 payments on the simulator). Non-euro payments are not offered yet (`TODO(api)`: the
engine gives no currency after PayPal folding). The tour's sample has one made-up case (`TourData`: "Ferienwohnung
Fiktivsee" −128 €, half paid back by "Max Mustermann" a day later, linked by `linkSamplePayback`; DEBUG
`-sampleNoPayback` leaves it unlinked). **The screens** (brief 203, Claude; words and models `Model/PaybackPage.swift`,
look `Screens/PaybackScreens.swift`): optional and quiet: one action on a payment's page and one tour step, no prompts
after an import, no badges, no offers anywhere else. **The payment's page**: a section after its rows and receipt,
before the bank's own row (`PaybackSection`, `PaybackSectionContent`): while the payment has euros free one quiet row
in the secondary ink with SF `link`, "Pays back an expense…" / "Zahlt eine Ausgabe zurück …" (money in) or "Paid back
to you…" / "Wurde zurückgezahlt …" (money out), "Also pays back…" / "Also paid back by…" once linked; each link under
"Pays back" / "Paid back" as a card in the "All from" card's look (the other payment's name, its day and own amount,
the linked euros, the chevron), which opens the other payment's page **pushed on the sheet's own stack** (the
sheet is now `TransactionDetailSheet`'s `NavigationStack` with `PaymentDetailPage`s; a link back to a page already
open goes back to it; Done closes the sheet from any page); the pen beside the card ("Change link") opens its euros
with **Remove link**, and the card's long press has Change amount and Remove link; one line on what still counts
("Your share, €64.00, counts as spent." / "Paid back in full: none of it counts as spent.", "The rest, €16.00, counts
as income." / "None of it counts as income."). After a link is made, changed or removed the undo bar says so ("Linked:
€64.00 paid back.", "Changed to €50.00.", "Link removed.") with Undo; the page reads its payment again whenever the
dashboard is rebuilt (`TransactionDetailStore.refresh`). `PaybackLinks.load` reads the state off the main thread as the
page opens (the room of the action is kept meanwhile, so the bank's row does not jump). **The window**
(`PaybackSheet`, a sheet over the page as the change window): the bar "Paid back by" / "Pays back" with Cancel, the
payment's name and amount, "Which payment paid this back?" / "Which expense does this pay back?" (plural since brief
206), the search field ("Search names"), then SUGGESTED (each row: the category's tile, the name, its day and what
fits in the second ink, "29 Oct · half" / "29. Okt. · die Hälfte"; "in full", "a third", "a quarter", "the rest"; its
own amount; the chevron) or, while typing, what the search finds ("No payment found for “…”."); a row pushes
**Amount** (since brief 206 a row ticks and Next pushes it, below "Several at once"): the two
payments (the one that came in over the expense), "How much of it was paid back?", the field with the suggestion's
euros (else the smaller rest; `ReceiptAmount.typed`, whole cents), "At most €64.00." (in the expense colour when
passed), **Link** / **Verknüpfen** in the bar, muted until it can. A change opens at Amount (Save, Remove link).

## The lists

**The lists**: a row's number is what counts there (`PaybackWording.rowAmount`: `countedAmount`; a counted 0 reads
"0.00" in the quiet ink, without a sign), so a list's rows add up to its total; its quiet line says why, in place of
the city ("€128.00 · €64.00 back" / "128,00 € · 64,00 € zurück"; "€64.00 · pays back Ferienwohnung Fiktivsee" / "64,00 €
· zahlt … zurück", "… 2 expenses"), up to two lines; on a day's page after the category. Summed rows add "· €64.00
back" (money in: "· €64.00 not income") to their days. A name that counts nothing keeps its own side (`PaymentNameGroup.spends`:
the name's page, its "All from" line); the search writes "0.00" for it. **The tour**: step 11 of 23, after the
switch (`TourStep.payback`): the trip's page, its section ringed, "Paid back by someone? If you like, link the payment
here: then only your share counts." / "Hat dir jemand etwas zurückgezahlt? Wenn du magst, verknüpfe die Buchung hier:
Dann zählt nur dein Anteil."; Next goes on. DEBUG (with `-samplePhone`, the trip and Max Mustermann in last month's
Not sorted, `-sampleIncome` for the payment in): `-openPayback` (the window; `-paybackSearch <text>`, `-paybackPick
<text>`, `-paybackAmount <text>`, `-paybackKeyboardDown`), `-editPayback` (the first link's euros), `-openLinked` (the
first link's payment), `-scrollToPayback`, `-sampleNoPayback`. Tests: `PaybackScreensTests` (the words in both
languages, the rows' numbers and lines, the ends and the amount check, link from a payment in through change, remove
and undo on a real store, a search beyond the suggestions, a name that counts nothing, the tour's trip), `PaybackTests`
(brief 202), `TourTests`. Real touches (a temporary UI test in `Aresus/AresusUITests` driving Aresium, deleted; 3 of
3): Max Mustermann's page → Pays back an expense… → the suggestions leave out a Netflix payment eight months back and
the search finds it → the half suggestion → 64.00 → Link; the page shows the link and "None of it counts as income.",
his row "0.00" with its line; Overview's Not sorted falls by €64; the trip's row "−64.00" with "€128.00 · €64.00
back", its page shows the link and opens his page; the card's long press Remove link, the undo bar's Undo brings it
back. Screenshots: `build/203-*.png`.

## Several at once

**Several at once** (brief 206, Claude; the owner on build 17: "if I select many statements I can then select income
that payed them back and it just goes expense by expense until it's empty", and the other way round; the data is
brief 205's `Model/PaybackGroups.swift`). **One window for both starts** (brief 203's `PaybackWindow` and
`PaybackSheet`, grown, not copied): a payment's page (its action, as before) or a selection's bar; it reports the undo
bar's line and its `BatchUndo` to its owner (`done`), which closes it. **The bar's item** (`SelectionBar`, after
Category and Name): SF `link`, "Paid back" / "Zurückgezahlt" on an expense list, "Pays back" / "Zahlt zurück" on an
income list (`SelectionWording.paybackItem`, the page's words); muted while `paybackGroup(ids:)` is nil for the ticks
(nothing ticked, only receipts or transfers, both directions, all linked in full), read off the main thread 0.1 s after
the ticks stop (`PaybackOfferKey`), keeping its last state meanwhile so a slide does not make it flicker; a tap reads
the group again (the busy sign) and opens the window; it says nothing about rows left out. **The window**: this side
at the top (`PaybackHeading`): one payment's name and own amount as before, or "3 expenses" / "3 Ausgaben" ("2
payments in" / "2 Einnahmen") and the euros they can still be paid back or pay back, signed (`totalRest`, what their
rows count), with what was left out in one quiet line ("Left out: 1 receipt, 2 transfers." / "Nicht dabei: 1 Beleg, 2
Umbuchungen."; cash entries, withdrawals, another currency, "paid back in full" / "schon ganz zurückgezahlt", "used in
full" / "schon ganz verknüpft"); the question in the plural, which reads for one too ("Which payments paid this
back?" / "… these back?", "Which expenses does this pay back?" / "… do these pay back?"); the search; SUGGESTED (brief
205's group suggestions). Every row ticks with the selection's circle and highlight (`selectionMark`, VoiceOver
selected; the chevron is gone), a ticked search result stays shown above SUGGESTED once the field is cleared, a row
with euros already linked says what it has free ("€30.00 left" / "30,00 € übrig"). German bar title "Rückzahlung"
(was "Zurückgezahlt von"; Abbrechen and Verknüpfen beside it cut that and "Zurückgezahlt" to "Zurückgez…"). **How the money goes** (`PaybackPlanPanel`,
pure `PaybackPlanSummary`): while anything is ticked and the search has no keyboard (above it the panel covered the
results; it comes back with Search or a scroll), at the bottom in the selection bar's look (the card over the wall,
the line on top; fading, Reduce Motion none; more than three expenses scroll inside it): each expense in pouring
order, oldest first, its euros back on the right (0 in the muted ink when the money ran out before it), under its name
its day and "in full" / "ganz" or "€24.15 still open" / "24,15 € noch offen"; a hairline; brief 205's sentence ("3
expenses, €100.00 paid back.") and what stays open or stays income ("€24.15 still open." / "€15.85 stays income.";
never both). The preview is the pure `PaybackPlan` over the rests the window read; Link plans again under the save
revision (a save meanwhile: "The data changed. Select the payments again." in the window, nothing saved). **The bar's
button**: one payment on this side and at most one ticked: **Next** / **Weiter** (`paybackNext`) to brief 203's
amount step (typed euros), which now says under "At most …" what they leave ("€120.00 still open. €20.00 stays
income.", `PaybackPick.left(after:)`); otherwise **Link** / **Verknüpfen** (`linkPaybacks`), which pours
(`setPaybacks`): the window closes, a selection ends selecting, and the undo bar says brief 205's line ("3 expenses,
€100.00 paid back. €24.15 still open.") with one Undo for every link. Each link's euros can still be changed on a
payment's page (the pen). **The tour**: no new step; the select step says "move, rename or link them". DEBUG (with
`-samplePhone`): `-samplePaybackGroup` (made-up shared costs last month: Pizzeria Fiktivo −48 and Fiktiv Grillhaus −36
in Eating out with the month's Restaurant Fiktiva, Fiona Fiktiv +40 and Felix Fiktiv +100 Not sorted; Fiktiv
Sprachschule −200, and Erika Mustermann's two transfers +150 and +100 in Parents & family), `-selectPayments <n | i,j>`
(or `-selectRows <i,j>`), `-selectionPayback`, and in the window `-paybackPick <text,text>` (ticks; one on each side
goes on to Next unless `-paybackStay`) and `-paybackLink`. Tests: `PaybackManyScreensTests` (the words in both
languages, the summary from a plan, the heading and the bar's item, three expenses and one payment in with one undo,
two payments in and one expense found by name, a payment's page ticking two, a save meanwhile refused),
`PaybackScreensTests` (brief 203's flow through Next), `TourTests`. Real touches (a temporary UI test in
`Aresus/AresusUITests` driving Aresium, deleted; 3 of 3 runs): three dinners ticked by a slide down the circles, Paid
back, Felix ticked, the summary's rows oldest first (two in full, the third with what stays open), Link, the undo bar,
the rows' "€48.00 · €48.00 back", Undo takes all three links back; Parents & family's two transfers ticked, Pays back,
the course found by name, "€50.00 stays income.", Link, both rows "pays back Fiktiv Sprachschule"; Felix's page, one
ticked shows Next, a second Link, the page shows both links and "The rest, €16.00, counts as income.". Screenshots:
`build/206-*.png`.

## Whether it comes off the totals

**Whether it comes off the totals** (brief 314, the owner 2026-11-18): Settings → Your data on this iPhone → "Take off
money paid back" / "Rückzahlungen abziehen" (`SubtractPaybacksSetting`, `aresium.subtractPaybacks`, on by default).
Off, the engine (`subtractPaybacks: false`) keeps every link and its limits but gives no `counted`, so both payments
count as booked in every total, category, graph, average and widget. **What a payment has free is read from its links**
(`Paybacks.linked`, `TransactionDetail.paybackRest`), never from `countedAmount`. The settings that change the
dashboard travel as one value (`DashboardPreferences`, part of the cache's key). **The note** (`PaybackNoteLine`,
`Model/PaybackTotals.swift`): under a start page's total and at the top of a category's months, only where a link
touches that number: "Excludes €64.00 paid back" / "Ohne 64,00 € Rückzahlungen" while on, "Includes …" / "Mit …" while
off; whether it came off is read from the dashboard, so it always agrees with the number beside it. DEBUG
`-subtractPaybacks off`. Tests: `PaybackTests`.
