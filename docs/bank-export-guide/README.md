# How to get the bank file: steps per bank

Research for brief 19 (`prompts/19-bank-export-guide.md`), checked 2026-10-27. For each bank Aresium reads,
the data gives the steps on the bank's website and in its iPhone app, the file type to pick, the limits, how the
file reaches Aresium, the sources and how sure the steps are.

**The data lives in the app:** [`Aresium/Aresium/Guide/bank-steps.json`](../../Aresium/Aresium/Guide/bank-steps.json)
(one copy only; moved there by brief 24, `prompts/24-tour-and-bank-guide.md`). Aresium shows it as it is: Settings →
Help → "Get the file from your bank", the first run's import step and the empty dashboard (`BankGuide`,
`Screens/BankGuideScreens.swift`; `BankGuideTests` checks every entry). "`steps.json`" below means that file. Brief 24
also made the data fit the screen: a place without steps (an app that exports nothing, or one no source describes) has
no `de`/`en` and the app says so in one line, its sentence moved to the bank's `notes`; `fileType.pick` lists the
label(s) to choose (`{de, en}` where they differ), `fileType.de/en` is the screen's one plain line on why (the
research's lines on the other party's IBAN moved to `notes` as "File: …"); each bank has a `title`; the `toAresium`
steps name the guide's „Datei auswählen“ button. To change a bank's steps, edit that file and run the tests.

## How the data was collected

- **Public sources only.** Nobody logged in anywhere and no real payment data was downloaded. Tools: web search and
  page fetches. The search order was the bank's own help pages first, then community guides (forums, the banks'
  communities), then accounting and budgeting tools' import guides (Lexware, FIBUscan, Firefly III, fibunu,
  vereinsguru, Portfolio Performance, beancount importers and others).
- **Five research agents** each took 3–4 banks; the iPhone side (Safari downloads, Files, ZIP, AirDrop, Numbers) and
  the "another bank" entry were done separately, and the source addresses were checked again before writing.
- **A label is in quotes only when a source shows it for that bank.** Where a source paraphrases, or the label comes
  from a sister bank (Deutsche Bank uses Postbank's platform), the step describes the action without quoting a
  label, and the bank's `notes` say what is missing.
- **What limited the research:** the agents' shared search allowance ran out near the end. Some bank pages refuse
  automatic reading: comdirect's FAQ (401) and community (403), Revolut (403), American Express (no readable text),
  Consorsbank's FAQ (loads its text by script). ing.de timed out, and its help page was read through a text-reader
  service; Revolut's and C24's through a reader service and the help centre's public API. Those facts come from the
  banks' own text, but not from opening the page directly.
- Every source in `steps.json` carries the date it was checked (2026-10-27) and, in its `supports` text, the page's own
  date where the page shows one. Bank sites change: DKB (2023), Postbank (2023), Deutsche Bank (Aug 2025), the VR
  Banking app (Aug 2026), Trade Republic (Apr 2026) and Barclays → easybank (Feb 2026; systems move in Q1 2027) all
  changed recently.

## Overview

"Found" means the steps come from a source; "unsure" means a part is not confirmed (the bank's notes say which);
"website only" means the bank's iPhone app cannot export a transactions file (PDF statements do not count).

| Bank | Website | iPhone app | File to pick | Confidence (website / app) |
|---|---|---|---|---|
| Sparkasse | found | website only | „Excel (CSV-CAMT V8)“ or „V2“ | medium / high |
| Volksbank, Raiffeisenbank (VR) | found | found, taps unsure (VR Banking 9.2+) | „CSV“ | medium / low |
| ING | found | website only | „CSV (Excel)“ | medium / medium |
| DKB (Girokonto and Visa) | found | website only (app: PDF) | „CSV“ | medium / high |
| comdirect | found | unsure (no export described) | „Export als csv“ | medium / low |
| Commerzbank | found | website only | „CSV“ | high / high |
| Deutsche Bank | unsure (Postbank's platform) | unsure | CSV | medium / low |
| Postbank | found | unsure (no export described) | „Als CSV exportieren“ | high / low |
| N26 | found (app.n26.com) | website only (app: PDF) | „CSV“ | high / high |
| Revolut | unsure | found | „Excel“ (gives a CSV) | low / medium |
| Trade Republic | none (app only) | found | „Transaktionsexport“ (CSV) | medium / medium |
| Consorsbank | unsure (export button unknown) | website only | CSV | low / medium |
| C24 | found (needs a computer) | unsure (no export described) | „CSV-Format“ | high / medium |
| American Express | found (third-party guides) | unsure | CSV, with all details | medium / low |
| Targobank | unsure (format dialog unknown) | unsure (app lists no export) | CSV | medium / low |
| Barclays (now easybank) | unsure (Excel only, label unknown) | website only (app: PDF) | Excel → CSV with Numbers | low / medium |
| PayPal | unsure (report names) | website only | CSV | low / medium |
| Another bank | generic | generic | CAMT, else CSV, else MT940 | medium / low |

No bank in this list offers private customers CAMT or MT940 as an easy web download except Sparkasse (CAMT XML as a
ZIP, MT940) and VR banks (MT940, CAMT only when the bank switched it on). So CSV is the pick almost everywhere;
CSV-CAMT at Sparkasse carries the other party's IBAN anyway. Files without the other party's IBAN: ING, Revolut,
PayPal (and comdirect and Commerzbank keep it inside the booking text).

## How the file reaches Aresium

`steps.json` → `toAresium` holds the shared iPhone steps; each bank lists the ones that apply, the usual one first:

- `safari`: the website download in Safari lands in Files → „Downloads“; Aresium's import picks it from there, or
  Safari's Downloads button → the file → Share → Aresium.
- `share`: from a bank app's share sheet straight to Aresium (VR Banking, Revolut, Trade Republic).
- `computer`: the export was done on a computer (C24 needs one: its web banking opens by scanning a QR code with the
  phone); AirDrop or iCloud Drive to the iPhone.
- `unzip`: tap the ZIP in Files, which makes a folder; import the files inside (PayPal reports over 50,000 rows;
  Sparkasse's XML CAMT).
- `desktopSite`: Safari's „Desktop-Website anfordern“ when a bank's phone site hides the export. Where this menu sits
  in iOS 26 differs between sources, so the step says only "page menu".
- `numbers`: Barclays/easybank's Excel file → Numbers → „Mehr“ → „Exportieren“ → CSV.

## Findings that matter for Aresium beyond the screen

These came up during the research; none was changed (brief 19 wrote only these two files).

1. **Sparkasse's XML CAMT** is a ZIP with one XML file per booking day. CSV-CAMT is one file with the same
   information, so the guide recommends it (as the brief expected).
2. **VR banks' MT940 may save as `.mta`.** Aresium's file picker and share sheet list `.sta`, `.mt940` and `.txt`
   only, so such a file is not offered. The guide recommends CSV, which avoids it.
3. **Trade Republic's CSV holds the securities account and the cash account in one file** (column `account_type`).
   Worth checking that the engine does not read share purchases as payments. A newer file adds `value_date`.
4. **PayPal has two CSV reports.** The activity download has „Typ“, and „Auswirkung auf Guthaben“ only if that field
   is added (PayPal's docs: not selected by default). The balance report (Guthabenbericht), which a July 2026 guide
   leads to, has neither. Aresium's PayPal reader drops memo rows by the first and recognises bank top-ups by the
   type, so its result depends on which report a person downloads.
5. **American Express: tick „alle weiteren Transaktionsdetails einschließen“.** The engine's `amex` profile matches
   the header with „Weitere Details … Betreff“, which the file has only with the details included. One guide
   (domonda) says to untick it; that file would go to the column check.
6. **comdirect: one export per account or card.** One CSV can hold Girokonto, Visa and Tagesgeld sections, and the
   engine reads the first section only. Lists over 500 rows may export only the page shown.
7. **DKB's delimiter** switched between `;` and `,`; the engine already accepts both.
8. **Do not mix file types for one account.** The plan (`ares-empire/docs/ARESIUM-FOR-OTHERS.md`) notes that the same
   period imported once as CSV and once as CAMT creates duplicates; the guide names one file type per bank.

## Per bank: what is unsure, and what to check once with an account

Each item below is something a friend with an account at that bank can confirm in a few minutes. Their answer goes
into `steps.json` (labels, `status`, `confidence`), with the date.

**Sparkasse** (medium). The path „Umsätze“ → export → CSV-CAMT is the same in sources from 2016 to 2026, but the
current button name „Exportieren & Drucken“ and the names „Excel (CSV-CAMT V8/V2)“ come from 2023 and 2026
third-party guides; no official page from 2024–2026 was found. Each Sparkasse runs its own site on the same platform.
Check: the export button's text; which CSV-CAMT versions are listed (after MT940 was switched off for business
software in Nov 2025); how far back the date filter goes and whether a TAN is asked; whether the export works in
Safari on the iPhone; umlauts in the file; the English site's labels.

**Volksbanken und Raiffeisenbanken** (website medium, app low). The labels come from one bank's guide (VR Bank
Fulda, current design) and match a 2023 guide; a bank can still show the older design (three dots → „Export“). The
app export is new (VR Banking 9.2, Aug 2026): only „Exportieren“ in the „Umsatzübersicht“ is quoted. Check: the
labels at their own bank; whether „CAMT“ appears under „Format“; how many months fit in one file; the app's taps and
whether its CSV has the same columns as the website's; whether the site or app has English labels.

**ING** (medium). ING's help confirms „Exportieren“ at the page bottom and 390 days; „CSV (Excel)“ and „Jetzt
exportieren“ come from two guides (2023, 2026) that agree. Check: the date filter's label; whether „CSV (Excel)“ is
the only format; that umlauts come out right; whether the app has any export.

**DKB** (website medium, app high). DKB confirms „Exportieren“ in the „Umsatzübersicht“ and that the Visa card has its
own list; the „CSV“ choice comes from a 2024 guide and a user comment. Check: the filter's labels; that „Exportieren“
offers „CSV“; the Visa card's path; how far back the dates go; whether the web banking has English.

**comdirect** (website medium, app low). The FAQ was read only through the search index. Check: how the Visa card is
chosen (a selector, or listed with the Girokonto); the button that reloads the list after changing the period;
whether an export over 500 rows is complete; whether the redesigned app (July 2025) exports anything.

**Commerzbank** (high). Check: the menu name that leads to the Umsatzübersicht; whether 12 or 24 months can be
exported (two official pages disagree); the English labels.

**Deutsche Bank** (medium). Deutsche Bank publishes no export guide; the steps are Postbank's on the same platform
(since 2025-08-25), plus „Als CSV exportieren“ confirmed for its securities account. Check: the whole path, and
especially the period fields and the create button (Postbank: „Von“, „Bis“, „Erstellen“); the English labels; how far
back; whether the app exports; the file name and header of a new export.

**Postbank** (website high, app low). Check: where the finished CSV appears after „Erstellen“; how far back „Von“
goes; whether the app exports anything; whether there is an English site.

**N26** (high). Check: whether app.n26.com works in Safari on the iPhone or sends you to the app; whether the period
has a limit; that the file is a plain .csv.

**Revolut** (website low, app medium). The app's labels are official in both languages; that „Excel“ gives a .csv
comes from third-party guides. Check: the file's ending; the share or save button after „Generieren“; whether
app.revolut.com has a statement export and its labels; that the „Excel“ option is still offered on iOS.

**Trade Republic** (medium). No official help article; the German labels agree across several 2026 guides, the
English ones vary. Check: the English labels; where the profile icon is (top right or bottom right); the order
„Teilen“ → period → „Erstellen“; whether the website gained an export; whether the file has `value_date`.

**Consorsbank** (website low). Only „Mein Konto & Depot“ is confirmed by the bank. Check: the path to the
Girokonto's transactions; the export button's label and format names; whether the period is one month or free, and
how far back; the file's encoding and delimiter; whether the app or the site has English.

**C24** (website high, app medium). Check: whether the app has an export (transaction list, share menu); the exact
period options; whether one file includes Pockets and other accounts; the encoding.

**American Express** (website medium, app low). Only accounting tools' guides; Amex's own pages could not be read.
Check: the labels and their order; the list of formats; how far back; whether the German site has English; whether
the app exports; the header with and without the details box ticked; the date format and the signs.

**Targobank** (website medium, app low). The official FAQ gives „Konten > Übersicht > Download der Umsätze“, but a
2025 Targobank guide shows a different submenu. Check: where „Download der Umsätze“ is today; which formats the
dialog offers; that the default CSV opens in Aresium; how far back.

**Barclays / easybank** (website low). No public easybank page describes the transactions download; the Excel export
rests on 2013/2021 forum posts and Firefly III's notes. Check: the button's name and place, and the file's ending
(.xlsx, .xls or .csv); whether a TAN is asked and how far back; that the CSV saved from Numbers opens in Aresium;
again after the move to BAWAG's systems (planned Q1 2027).

**PayPal** (website low, app medium). The first steps are official („Aktivitäten“, download icon,
„Benutzerdefiniert“, „Herunterladen“); the report's name in between is not. Check: which reports the „Benutzerdefiniert“
screen offers today; which CSV comes out (with „Typ“ and „Auswirkung auf Guthaben“, or the Guthabenbericht's
columns); whether „Auswirkung auf Guthaben“ has to be added; whether the English menu says “Activity” or “History”;
whether paypal.com in Safari shows the download icon or needs the desktop site.

**Another bank** (generic). Built from the patterns above: „Umsätze“ / „Umsatzanzeige“ / „Kontoumsätze“, then
„Export“, „Exportieren“, „Download“, a download icon or three dots; CAMT first, then CSV, then MT940. Nothing to check;
a bank that friends use often gets its own entry once someone sends its steps.
