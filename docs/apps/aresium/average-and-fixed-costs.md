# Aresium: Monthly average and fixed costs

Part of Aresium's notes; start at `docs/apps/Aresium.md` (its decisions in force). Covers the average line under Overview's total, fixed and regular payments, Not fixed.

## Monthly average and fixed costs — data API

**Monthly average and fixed costs — data API** (brief 208; screens in 209):
`DashboardStore.monthlyAverage(side:)` returns `MonthlyAverage?` (`amount`, integer `cents`, `count`, `first`/`last`
month keys): all non-partial months, excluding the earliest payment's month when it starts after day 7; nil below
two months. Both backends use the engine's monthly totals, including paybacks, rounded to whole cents.
Phone mode's `fixedCosts(side:)` returns `FixedCostList?`: `running`, `ended`, `takenOut`, `monthlyTotal` and
`monthlyCents`. `fixedCost(id:)` resolves any entry, or nil after it disappears. Entries expose `name`, `category`,
`side`, `cadence`, `amount`/`cents`, `monthlyEquivalent`/`monthlyCents`, `count`, `first`, `last`, `nextDue`,
`running`, `notFixed`, row `ids` newest first and `newest` (`Transaction`). Detection groups eligible bank rows by
`nameKey` and direction, splits amounts at 10% or €3, follows calendar cadences and uses the ledger's newest bank
payment as its reference. A double cadence gap is normalized as one missed payment before the median is taken.
The cache is built off main and published with each dashboard's revision, like `QuickSortCache`; server mode is nil.
`try await setNotFixed(entry, true|false)` saves once, reloads once and returns `BatchUndo`. Schema/export 8 adds
`FixedCostMark`: `key` (the anchor payment's original merchant key, else its exact bank line), direction,
cadence, and a payment-id anchor to distinguish two subscriptions at one shop with one cadence. No amount enters
the mark. The earliest import sequence supplies the anchor, so older files imported later preserve an unmarked entry's id too.
Engine revision rebuilding moves merchant keys by the name rules' longest current whole-word prefix;
bank lines and absent shops stay. Display names and shop identities never enter the stored key. Export schemas 1–7 still restore; deleting the store deletes the marks.
Pure `FixedCostWording.cadence(_:language:)` and `nextDue(_:referenceDay:language:)` supply both languages;
due dates include the year only when it differs from the reference year's (default: today).

## Monthly average and fixed costs on screen

**Monthly average and fixed costs on screen** (brief 209, Claude; the owner 2026-11-02 after build 18: "lets do monthly
and fixcost screen feature first"; words and models `Model/FixedCostPage.swift`, look `Screens/FixedCostScreens.swift`).

## The Overview's line

**The Overview's line** (`AverageLine`, `AverageLineView`): under a side's total on Overview only (Current and a
month's page are one month; nothing while `monthlyAverage` is nil), in the total's column, right-aligned, one quiet
line: "Avg. €1,571 a month · €1,048 fixed ›" / "Ø 1.571 € im Monat · davon 1.048 € fix ›" (income "€2,600 regular" /
"davon 2.600 € regelmäßig"; English writes "Avg." since "Ø" is a German habit). The average in the muted ink, the
fixed part in the second ink with a small chevron: a button over 44 pt that pushes the page. Where the line would not
fit (large text) the fixed part takes a second line of its own (`ViewThatFits`), never a smaller font. The fixed part
shows while any entry is running, a taken-out one too, so the person who took every one out still reaches the page (at
€0) to count one again; server mode and sides with none show the average alone. "Finished months only" is said once,
in VoiceOver ("Average of the finished months: €1,571 a month" / "Durchschnitt der abgeschlossenen Monate: …"), no
footnote; the fixed part reads "Fixed costs: €1,048 a month", a button. **The page** (`DashboardRoute.fixedCosts(side)`,
`FixedCostsScreen`, pushed like a name's page: the header "Fixed costs" / "Fixkosten" or "Regular income" /
"Regelmäßige Einnahmen" with its arrow and gear, the back swipe): the start screen's heading (`SideTotal` with a
`caption`: "Expenses €1,048 a month" / "Ausgaben 1.048 € im Monat") and under it, in the total's column, "€12,571 a
year"; the running entries as the lists' rows (`FixedCostRow`: the category's tile, the name with the amount as a
payment shows it, "−780.00" in the side's colour, a quiet line "monthly · next 2 Dec" / "monatlich · nächste am 2.
Dez.", a not-monthly one adds its share a month, "yearly · next 15 Oct 2027 · €41.58 a month", on one line where it
fits, else the share on a second, as in German; the chevron); then **ENDED** / **BEENDET** ("monthly · last 10 Jul" /
"monatlich · zuletzt am 10. Juli", `FixedCostWording.last`) and **NOT COUNTED** / **NICHT GEZÄHLT** in the search's
small capitals, their rows quieter (the tile at half, the name in the second ink, the amount muted); at the end one
quiet line: "Found in payments of the same name with about the same amount at the same interval, monthly to yearly.
Hold a row to take it out." / "Gefunden in Buchungen desselben Namens mit etwa gleichem Betrag im gleichen Abstand,
monatlich bis jährlich. Halte eine Zeile gedrückt, um sie herauszunehmen." No small-capitals line above the total (the
header names the page). Empty: one centred line, "No fixed costs found yet. They show up after three payments of one
name at the same interval, a yearly one after two." (income "No regular income found yet. It shows up …"). **Rows:** a
tap opens the name's page of the entry's `newest` (`nameRoute(for:)`, as "All with this name"); the long press (and
VoiceOver's action) **Not fixed** / **Nicht fix** (income **Not regular** / **Nicht regelmäßig**, `minus.circle`) on
running and ended rows, **Count again** / **Wieder zählen** (`plus.circle`) on taken-out ones: `setNotFixed` at once,
then the shared undo bar ("StreamFiktiv taken out of fixed costs." / "StreamFiktiv aus den Fixkosten genommen.",
"… counted again." / "… wird wieder gezählt.") with Undo (`BatchUndo`); the page, the total and the Overview's line
follow the store. A store changed meanwhile says "The payments changed meanwhile. Try again." A row's identity names
its section (`FixedCostPage.Row.id`): with the entry's id alone the lazy list kept the old row's look after it moved to
Not counted. VoiceOver reads a row as one, with commas for the screen's middle dots ("StreamFiktiv, −12.99, monthly, next 14
Nov"), the total with "a month".
The list's change fades (0.25 s; Reduce Motion: none). The tour points at the Overview's line in its own step
(brief 229, below). DEBUG (with `-samplePhone`): `-sampleFixedCosts` (an older made-up statement and contracts over 14 months:
the tour's regular payments in the five months before its own, the rent at €750 before its raise to €780, StreamFiktiv
at €7.99 and €12.99, a yearly Fiktiv Versicherung AG at €498.96, a quarterly Fiktiv Bank fee, a Fiktiv Fitness GmbH
cancelled four months ago; sorted by hand into Subscriptions, Insurance, Fees and Sports & fitness), `-openFixedCosts
expenses|income` (the page over Overview), `-fixedCostOut <text>` (takes the first running or ended entry whose name
contains it out, as the long press), `-scrollToEnd` (the page's end); the empty page: `-sampleSize 40 -openFixedCosts
expenses`. The tour's sample includes rent, Spotify, Netflix and a monthly liability insurance; shopping dates and
amounts vary so groceries and dm do not look like contracts (brief 229; detection unchanged). Tests: `FixedCostScreensTests` (the
line's and the page's words in both languages, the line only on Overview with an average, its fixed part only while one
runs, at €0 once all are taken out, the sections, shares and quiet rows, a row's identity per section, the route, the
line and the page following a real store through Not fixed and Undo, the row's name page). Real touches (a temporary
UI test in `Aresus/AresusUITests` driving Aresium, deleted; 3 of 3 runs): the Overview's line opens the fixed costs, the
rows, Ended and the total as the sample says, a long press → Not fixed moves StreamFiktiv €12.99 to Not counted and the
total falls by €13, Undo brings it back, a row opens the name's page and back returns, the income side's line opens
Regular income. Screenshots: `build/209-{overview,overview-income,page,page-end,income,empty}-{en,de}-{dark,light}.png`,
red mode `build/209-{overview,page,income}-de-red.png`, the long press and the undo bar after it (from the UI test)
`build/209-{longpress,notfixed}-{en-dark,de-light}.png`.
