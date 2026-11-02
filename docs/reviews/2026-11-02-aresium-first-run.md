# Aresium: the first run, as a new tester meets it (2026-11-02)

Build 18 (0.1 (18), Debug build of `main` at 99c71a9) on a freshly erased simulator (`claude-207`, iPhone 17,
iOS 27.0), no sample arguments, no Ares login, only Aresium installed. Walked with real taps (a temporary UI test in
`Aresus/AresusUITests` driving Aresium, deleted afterwards) in English/dark and German/light, plus a few checks in the
other combinations. Made-up files only: the engine's fixtures (`vrbank.csv`, `dkb.csv`, `camt.xml`, `paypal.csv`,
`unknown-fiktivbank.csv`), a made-up three-month VR Bank file (`Umsaetze-Girokonto-Fiktiv.csv`, 74 payments,
Aug to 2 Nov 2026) and a made-up MT940 file (`fiktivbank.sta`), put in Files → On My iPhone → Aresium-Test. Nothing was
sent through the app. Screenshots: `build/207-*.png` in the worktree.

## Verdict

**The reviewer gets through.** The first screen is clear, Start tour works from start to end in both languages,
nothing in it overlaps or points at the wrong thing, and Import data reads CSV, CAMT and MT940 files (one or several
at once). Two things the reviewer will see this week are worth fixing first if a build goes out before the review
ends: the tour's "this month" is squeezed into 1–2 days at the start of a month, and Settings shows an Ares account
sign-in that nobody but Patrik can use.

**I would hand it to a friend after three small fixes.** The main path (import, tick categories, quick sort, look
around) works and reads well. What can go wrong for a friend: (1) tapping Done on the category list without ticking
anything leaves every payment Not sorted, and the app then offers no way back that a newcomer would find; (2) on the
first days of a month the start screen shows almost nothing right after a big import; (3) in German the import
result's button says "Entfernen", which reads as "delete".

## Findings, most important first

### Blocks a tester

**1. Done on the category list with nothing ticked: every payment stays Not sorted, and the quick sort cannot sort
them.**
- *Where:* first import → the category list that opens by itself ("Categories · 0 chosen") → Done.
- *What happens:* Done is allowed with nothing ticked (by design: "the next import asks again"). All 74 payments
  land in Not sorted (Overview: one row, "Not sorted €5,241"). The quick sort offer then appears ("74 payments not
  sorted · From 16 names"), but its first card, REWE Markt GmbH, offers only **Own transfers** and **New category**:
  the default categories are not offered because none is chosen, and the category the engine knows for REWE
  (Groceries) is not suggested. Nothing on the start screen says "choose your categories"; the only way back is
  Settings → Categories, which a newcomer does not know about.
- *Why it matters:* "Done" is the most visible button on that sheet, and a newcomer who wants to "look first" taps it.
  They then see an app that sorts nothing, and the tool meant to help asks them to type category names by hand.
- *Suggestion:* when nothing is ticked, let Done ask once ("Tick the 12 categories that have payments?" / "Not
  now"), or let the quick sort offer the default categories (the engine's own suggestion first, ticking it on use).
  A quiet line on a dashboard that has only Not sorted, leading to the category list, would also do.
- *Screenshots:* `207-noticks-quicksort-de-light.png`, `207-noticks-overview-de-light.png`,
  `207-noticks2-de-light.png`.
- *Fixed in build 19 (brief 215):* Done with nothing ticked asks once, "Use the 12 categories that fit?" (Use ticks
  every category the rows count payments for and sorts; Not now leaves them); while none is chosen the start screen and
  Not sorted's list show a card "Choose your categories" that opens the list, and the quick sort waits until one is.

### Confuses

**2. Right after a first import early in a month, the start screen shows almost nothing.**
- *Where:* the start screen (Current) after the first import, on 1–7 November (when testers start).
- *What happens:* Current always shows the newest month in the data. With a fresh export on 2 November that month has
  two days: the start screen shows one row, "Rent €780", and a two-point day graph, while the result line said "74
  new". The three full months are only on Overview. (With an older file whose newest month is February, Current shows
  February, which reads fine: `207-oldfile-current2-de-light.png`.)
- *Why it matters:* the first look after the import decides whether the app "worked". "Where are my 74 payments?"
- *Suggestion:* right after an import, while this month has only a few days, open on last month (the existing
  `reviewMonth` already does this for the review message) or on Overview, with one quiet line saying which month is
  shown.
- *Screenshots:* `207-after-picker-en-dark.png`, `207-quicksort-offer-en-dark.png`.
- *Fixed in build 19 (brief 215):* on the 1st–7th, while the newest month is the running one, Current opens on last
  month (read when the app is opened, never while it is open), with "NOVEMBER SO FAR ›" on the range line one tap away
  and "‹ OCTOBER" back.

**3. German: the import result's "Dismiss" is "Entfernen" (remove).**
- *Where:* any import → the result card at the bottom ("3 neu · 0 schon da · …") → its button.
- *What happens:* the button reads "Entfernen": Aresium's catalog translates `Dismiss` as Arestemis's does (where it
  removes a listing, so "Entfernen" is right there), but here the button only closes a notice
  (`Screens/ImportControls.swift`, `store.close()`).
- *Why it matters:* a German newcomer may think it removes the payments just imported, and leave the card alone or
  worry after tapping it.
- *Suggestion:* "Schließen" or "OK" for this button (a key of its own in Aresium's catalog).
- *Screenshots:* `207-multi-result-de-light.png` (the card, mid-fade, over the quick sort offer).
- *Fixed in build 19 (brief 215):* the button is "Close" / "Schließen", a key of its own; Arestemis keeps "Entfernen".

**4. The tour on the first days of a month: "this month" is pressed into one or two days.**
- *Where:* Start tour (first screen) → step 1 and every list in the tour, on 1–3 November (the review is running
  now).
- *What happens:* the tour fills this month by pressing the whole month's payments into the days gone by. On
  2 November Current's graph has two points (day 1 high, day 2 low: it reads as a fall), and Groceries lists five
  payments on the 1st and the rest on the 2nd. On the 1st the graph is a single point.
- *Why it matters:* the reviewer's and the first testers' first look at the app is this sample; a two-point falling
  line and a crowded day look like a bug.
- *Suggestion:* in the first week of a month, let the tour's made-up world treat last month as its "this month" (the
  tour has its own store and its own clock), so it always shows a full month.
- *Screenshots:* `207-tour-01-de-light.png`, `207-tour-07-de-light.png`, `207-tour-02done-en-dark.png` (income: falls
  from €2,600 to €0).

**5. Settings → Ares account: a sign-in nobody but Patrik can use.**
- *Where:* Settings, last section "Ares account" → Sign in.
- *What happens:* the section says "Only for an Aresium server of your own. Your data here stays on this iPhone."; the
  sheet has Email, Password, "One Ares account for all Ares apps", Log in and Forgot password, and no way to make an
  account.
- *Why it matters:* a tester reads "Ares account" and "all Ares apps" and wonders what they are missing or how to get
  one; a reviewer may ask for a demo account despite the review notes. It is the one place in the app that is not for
  them.
- *Suggestion:* show the section only when an Ares login already exists on the iPhone (or behind a long press on
  Version); otherwise say plainly "Only for the developer. Aresium needs no account." and drop the "One Ares account
  for all Ares apps" line from this sheet (it went from the logins on 2026-10-31).
- *Screenshots:* `207-settings-end-en-dark.png`, `207-signin-en-dark.png`.
- *Fixed in build 19 (brief 215):* signed out, Aresium's Settings have no "Ares account" section (it shows only while a
  login of the Ares apps exists), and the Sign in sheet lost "One Ares account for all Ares apps".

**6. Check the guide for PayPal, N26 and Trade Republic once before friends with these accounts start.** (Content,
not the screens; the guide's own notes flag all three.)
- *PayPal* (`Guide/bank-steps.json`, website confidence "low"): the steps say "choose 'Benutzerdefiniert' and the
  report with your payments". The notes say PayPal has two CSV reports with different columns, the reader needs
  "Transaktionscode" and "Netto"/"Brutto", and drops hold rows by "Auswirkung auf Guthaben", which PayPal does not
  include by default. A friend who picks the other report gets a file the app reads differently. Patrik's own PayPal
  file worked in build 1, so he knows which report: name it and its settings in the steps.
- *N26:* the notes say it is unchecked whether app.n26.com works in Safari on the iPhone or sends you to the app.
  Many N26 users have only a phone. One look (no login needed to see where the page goes) settles whether the page
  should lead with "use a computer".
- *Trade Republic:* the notes say one export holds the cash and the securities account and that the engine "should be
  checked for securities rows being read as payments". A savings plan would show up as spending. A made-up Trade
  Republic file through the engine settles it.

### Polish

**7. English month lists say "activities".** Category → a month: the subtitle is "Oct 2026 · activities" (key
`%@ · activities`, also "No activity"); everywhere else the English app says "payments", and the German says
"Buchungen". Suggest "payments". `207-month-list-en-dark.png`.
*Fixed in build 19 (brief 215):* "Oct 2026 · payments", "No payments", "No payments recorded."

**8. German tour step 4 is hard to read.** "Halte den Finger auf dem Diagramm und zieh: jeder Monat mit seiner Zahl.
Antippen öffnet den Monat, zeigt es Tage, den Tag." The second sentence does not parse on first reading. Suggest e.g.
"Ein Tipp öffnet den Monat, oder den Tag, wenn das Diagramm Tage zeigt." `207-tour-04-de-light.png`.

**9. Tour step 14 says "again".** "Swipe the row again: All shows every payment of the name." / "Wisch die Zeile noch
einmal …" assumes the swipe of step 12; someone who tapped Next there never swiped, and the ringed row is not added
up. Suggest "Swipe a row: All shows …". `207-tour-14-en-dark.png`.

**10. The header's import icon points up.** The start screen's import button is `tray.and.arrow.up`, which iOS uses
for share/export; the drop overlay of the same app uses `tray.and.arrow.down`. A newcomer looking for "import" may pass
it by (the tour's step 20 does point at it). Suggest the downward tray, as in the drop overlay. `207-after-picker-en-dark.png`.
*Fixed in build 19 (brief 215):* `tray.and.arrow.down`, as the drop overlay.

**11. Three cards in a row after the first import.** The result card, then the quick sort offer, then "Remind you to
import new statements?". Each is calm, but a newcomer is asked three things in a minute. Suggest holding the
reminders offer until a later launch or the second import. `207-after-picker-en-dark.png`,
`207-quicksort-offer-en-dark.png`, `207-overview-en-dark.png`.
*Fixed in build 19 (brief 215):* the reminders' offer waits until Aresium is opened again (a launch, or coming back to
it); a second import in the same opening does not bring it.

**12. Overview's graph drops at the current month.** With two days of November, Overview's line falls from about
€1,500 to €780 at Nov; it reads as "spent less". Suggest drawing the unfinished month differently (dashed, or a
quiet "so far"). `207-overview-en-dark.png`.
*Fixed in build 19 (brief 215):* every month graph draws the stretch to the running month dashed over a fainter area,
no legend.

**13. Tour step 10 hides which payment it is.** The payment page scrolls so the paid-back section shows; the name
"Ferienwohnung Fiktivsee" and "−128.00" sit under the bar, half covered. "To: Ferienwohnung Fiktivsee" is still
readable, so this is small. `207-tour-10-en-dark.png`.

**14. Cash row wording for a newcomer.** With withdrawals and no receipts, Overview shows "Cash · €300.00 not
accounted for" ("nicht erfasst"). Without receipts it can read like a warning. Optional: say what to do or what it
means. `207-noticks-overview-de-light.png`.
*Fixed in build 19 (brief 215):* "Cash · €300.00 without receipts" / "300,00 € ohne Belege" (the Cash page keeps its
explained heading).

**15. Review notes in `docs/APP-STORE.md` are older than the app.** They say "choose a few categories, then import
the attached made-up bank file" (the app is file-first since brief 27) and do not mention Start tour. Check that the
text in App Store Connect is the newer one, and update the doc.

### Not checked, and why

- **Offline:** the simulator shares the Mac's network, so it was not cut. From the code: Contact & support says "No
  connection. Send it again when you're online.", the legal pages show Safari's own offline page, and a bank format or
  bank request waits in the outbox.
- **Lock with Face ID:** on the simulator (no Face ID enrolled) the switch stays off without a message; a simulator
  artifact, check on a phone. **Scan receipt:** the simulator's camera cannot record.
- **Harness note:** XCUITest launches pass the Aresus scheme's pinned language (en/GB), so a relaunch from the test
  looked English after switching to German; launched by `simctl` the app kept German and Light. Not a bug.

## What worked well (leave as is)

- **First screen:** one calm empty state, one main button, the tour as the quiet second, "How do I get my file?" and
  "Restore from an export" as links; the line "Everything stays on this iPhone" answers the first worry
  (`207-first-en-dark.png`, `207-first-de-light.png`).
- **File first, then categories:** the list opens by itself with "Your payments are in. Aresium sorts them as you
  tick." and a count on every row, so it is obvious which to tick (`207-picker-after-import-en-dark.png`). Unticking
  a ticked row asks where its payments go (`207-picker-ticked-en-dark.png`).
- **Imports:** 74 payments read in a few seconds; the same file again says "0 new · 74 already there" and changes
  nothing (`207-reimport-same-en-dark.png`); CAMT, PayPal and MT940 picked together are all read, one line each
  (`207-multi-result-de-light.png`).
- **Unknown bank:** "Aresium doesn't know this bank yet. This is how your payments would look:", three real rows,
  "Does this look right?"; No shows the next reading with what changed ("Name und Verwendungszweck getauscht"), then
  plain column questions with the file's own values. The "Help Aresium learn your bank" card says "Only how its file
  is laid out goes to us, never a payment", and "What is sent?" lists exactly that (`207-unknown-file-en-dark.png`,
  `207-unknown-columns-de-light.png`, `207-unknown-result-en-dark.png`, `207-unknown-whatissent-en-dark.png`).
- **Quick sort:** the card, the example text, "A tap sorts all 3 and Aresium remembers the name", Other category… as
  a menu, Undo and Skip; the end screen "Everything is sorted." (`207-quicksort-en-dark.png`,
  `207-quicksort-done-en-dark.png`).
- **Payment page:** name with pen, amount, date written out, "All from …", category chip, the bank's fields, "As in
  your bank's file" (`207-payment-page-en-dark.png`).
- **The tour:** 22 steps, every ring on the control its card names, in both languages and both looks; cards never
  cover their target; doing the thing (swipe to income, tap Overview, search) moves it on; End tour works at every
  step; leaving the app mid-tour and coming back resumes the same step; killing the app mid-tour leaves no tour
  folder and opens on the empty first screen; after the last step the empty first screen is back
  (`207-tour-*-{en-dark,de-light}.png`, `207-tour-resume-en-dark.png`, `207-after-kill-mid-tour-en-dark.png`,
  `207-after-tour-de-light.png`).
- **Bank guide:** clear list with where each bank's export lives ("On the website", "In the app"), honest "This
  doesn't work in the bank's app, only on the website", the Safari download steps, Choose file at the bottom; an
  unknown bank gets the general steps and "Tell us about your bank" (`207-guide-*.png`). Search finds "Sparkasse
  Hannover" and "VR-Bank Ostbayern".
- **Settings:** Delete data asks with plain words and returns to the first screen (`207-delete-de-light.png`); the
  language switch asks and restarts in German (`207-language-confirm-en-dark.png`, `207-dashboard-de-dark.png`);
  Contact & support is clear about what is sent (`207-contact-en-dark.png`); Privacy and Imprint open inside the app
  and close back to Settings (`207-privacy-en-dark.png`, `207-imprint-en-dark.png`).
- **A photo that is not a receipt:** "Aresium couldn't read this receipt. Type what's on it:" with the fields, no
  error (`207-photo-notreceipt-de-light.png`).
- **Red mode** (tapping the band at the end of the first screen) is reachable by accident, but the X in the header
  leaves it at once (`207-first-redmode-en-dark.png`); no change needed.

## Banks missing from the guide

Searched in the guide; each of these gets "We don't know this bank yet":

- **HypoVereinsbank / HVB (UniCredit):** a large bank in Bavaria, so likely among friends in Munich.
- **Sparda-Bank, PSD Bank, GLS Bank, BBBank, Münchner Bank:** cooperative banks under their own names. If they use the
  same online banking as the Volksbank page, adding their names to that page's search names is enough; otherwise a
  page each (at least Sparda-Bank).
- **Haspa** (Hamburger Sparkasse) and **1822direkt:** "Hamburger Sparkasse" is found, "Haspa" is not; 1822direkt
  belongs to the Frankfurter Sparkasse but has its own banking. Check whether the Sparkasse steps hold, then add the
  names.
- **Santander, norisbank.**
- **Newer accounts young people use:** Tomorrow, bunq, Wise, Openbank, Scalable Capital (its current account), Klarna
  (card/balance), Vivid.
