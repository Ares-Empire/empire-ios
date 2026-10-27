# 28: The payment page in plain words

Status: running
Repo: empire-ios · Worktree: `../empire-ios-28-payment-detail` (branch `claude/28-payment-detail`) · Built by: a
Claude agent (the look and the wording)

## Goal

Tapping a payment opens its page (`Screens/TransactionDetailSheet.swift`, data `Model/TransactionDetail.swift`). It
still shows values straight from storage: "via starter" / "über starter", "Source: bank", dates as `2026-10-04`, a
long "External ID", a disclosure "Original bank record". Friends see this page in the tour (the payment step) and on
every payment they tap. Make it read like the rest of Aresium: plain words in the app's language, readable dates,
nothing internal. Patrik agreed 2026-10-27.

The same page serves both modes: phone mode (everyone) and server mode (Patrik's own data from aresium.de). Change
the presentation for both through one place; the data and the backends stay as they are.

## Read first

- `AGENTS.md`, `CLAUDE.md` (Languages, Light mode, the design rules, "Aresium phone mode"); the memory of the design
  restraint: ink only, no slogans, no new colours, start from the existing pieces (the Settings rows, `CategoryChip`,
  the dashboard's rows).
- `Model/TransactionDetail.swift` (`rows`, `originalRows`, `accountLabel`), `Screens/TransactionDetailSheet.swift`,
  `Model/PhoneBackend.swift` → `detail(_:account:list:)` (only to read what phone mode fills in), `Model/PhoneLedger.swift`
  → `CategorySource`, the server's sample `transaction-detail.sample.json`, `Model/DisplayFormatting.swift` and the
  app's date/money formatting (`Format`, `Money`, `AppLanguage.locale`).
- The values that arrive: phone mode's category source `structural | learned | starter | manual | none` (meanings in
  `CategorySource`), the server's `rule | llm | manual` (`~/aresium/src/data/queries.ts`, read only); a payment's
  source `bank | paypal`.

## Build

1. **One display model, pure and tested.** Put the wording in `TransactionDetail` (or a small type next to it) as
   functions that take `language: AppLanguage = .current`, not in the view. Unknown values never show raw: a category
   source or source the code does not know gives no line.
2. **The top:** the shop, the amount, the date written out in the app's language (e.g. "Sat 4 Oct 2026" /
   "Sa. 4. Okt. 2026", or the weekday in full if it reads better; your call, the same style as elsewhere in the app).
3. **Category:** the chip and Change stay. The "via …" line becomes a short sentence on why it is in this category:
   the shop list (`starter`), learned from the person's earlier change for this shop (`learned`), chosen by the person
   (`manual`), a transfer between the person's own accounts (`structural`); server: a rule (`rule`), sorted
   automatically (`llm`), chosen by you (`manual`). Nothing for `none` (the chip already says Not sorted).
4. **The rows:** Account (name, IBAN in groups of four); the other party labelled by direction ("To" for money out,
   "From" for money in, or one plain label if that reads better in German: "Empfänger"/"Auftraggeber" are the bank
   words, pick what a non-banker understands); the payment text ("Verwendungszweck" in German is fine, it is the word
   on every statement); Balance after; the value date only when it differs from the booking date, written out like
   the top. "Source" goes, or shows only when it tells something (a payment from a PayPal file: say so plainly); the
   account row already names the account. **External ID goes** from the page.
5. **The bank's own row** (the disclosure): a plain title ("As in your bank's file" / "So steht es in der
   Bankdatei"), closed by default, the column names and values inside as now.
6. Server-only rows (Location, Trip, Place type, Recurring; empty in phone mode): keep them, but no raw value
   (`placeType` values from the server: show them only through a mapping you write for the known ones, else hide);
   list what you saw in the final message.
7. **The title** of the page: "Payment" / "Buchung" (the app's term), not "Transaction".

## Settled: do not re-open

- No change to the data, the backends, the server or the engine; only how the page reads.
- Change (Switch/Add) and its sheet stay as they are. The tour's payment step keeps working (`.tourAnchor(.change)`).

## Out of scope

The category picker, the import flow, `ContentView`'s import wiring, `ImportStore`, `FirstScreen.swift`: another
Claude agent works on those in parallel (brief 27). Do not touch them. `Localizable.xcstrings` and `CLAUDE.md` are
merged by Claude afterwards; edit them normally.

## Done when

- `xcodebuild test` for Aresium passes (`-parallel-testing-enabled NO`) on **your own simulator** (create one, delete
  it at the end; never the booted "iPhone 17" 56D5D752…, Patrik uses it), with tests for: every category source in
  both languages (phone and server values, an unknown one gives nothing), the date written out in both languages, the
  value date hidden when equal, the direction label, the IBAN grouping, External ID absent, the source line.
- `scripts/strings.py check` 0 problems; German "du", plain.
- Screenshots `build/28-*.png`: a phone payment (`-samplePhone -sampleCategory <name> -sampleMonth <YYYY-MM>
  -samplePhoneTransaction <text>`) with the bank's row open and closed, an own-transfer payment, a server sample payment
  (`-sampleData`), each in German and English, light and dark, and one at the largest text size; the tour's payment
  step (`-samplePhoneEmpty -tour 6` or the step that shows it).
- `CLAUDE.md` mentions the page in the phone mode entry. Final message: files changed, test counts, the screenshots,
  anything doubtful. Never commit, push, merge or deploy; never touch the server, any database or other repos. No real
  data: there are no real payments on this Mac and you must not look for any; only the made-up samples.
