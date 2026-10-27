# 24: A tour with made-up data, and "How do I get my file?" per bank

Status: merged 2026-10-27 (Aresium 224 tests with brief 23; research notes kept off the screen)
Repo: empire-ios · Worktree: `../empire-ios-24-tour` (branch `claude/24-tour`) · Built by: a Claude agent (flow,
data and the look)

## Goal

Patrik tried the first run (2026-10-27) and asked for two things:
- **How to get the file:** he didn't know how to get a file of his payments out of his bank the first time. Aresium
  shows, per bank, the exact steps. The research is done: `docs/bank-export-guide/steps.json` and its `README.md`
  (brief 19; 16 banks, PayPal and "another bank", German and English, with confidence per bank).
- **A tour, "like those app guides":** the app filled with made-up data; each step highlights the real button with one
  short sentence and waits for the person to tap it, or to press Weiter. It shows: income and expenses, Current and
  Overview, the graph, opening a category and a payment, changing a payment's category (and that Aresium remembers
  the shop), choosing and adding categories, and where imports go.

## Read first

`AGENTS.md`, `CLAUDE.md` ("Aresium phone mode": the samples `-samplePhone` (a made-up store in a temporary folder,
filled through the real import), the first run, the Current-view route; Languages; Light mode; the design rules:
Aresium's own look, ink only, no new colours or fonts, no slogans). The code: `ContentView.swift`,
`Screens/PhoneScreens.swift` (`PhoneFirstRun`, `FirstRunStep`), `Screens/DashboardScreens.swift`,
`Screens/ImportControls.swift`, `Screens/RecategoriseSheet.swift`, `Screens/TransactionDetailSheet.swift`,
`Model/ModeStore.swift`, `Model/PhoneBackend.swift`, `Model/PhoneSample.swift`. The steps data and its README.

## Build

1. **The steps in the app.** Move `docs/bank-export-guide/steps.json` into the app (`Aresium/Aresium/Guide/`, the
   folder is synchronised, so it is bundled; one copy only: the README points to the new place). A Codable model;
   a test that every entry decodes and has German and English website steps or an explicit "not on the website".
2. **"Wie komme ich an meine Datei?"** — a sheet: a search field ("Deine Bank") over the list of banks (their
   `names` match), "Andere Bank" last. A bank's page: Website / App (the app part only when it has steps; else one line
   "In der App der Bank geht das nicht, nur auf der Website."), numbered steps, which file to pick and why (one line),
   the limits, then "So kommt die Datei zu Aresium" (from `toAresium`: Safari's download → Teilen → Aresium; the bank's
   app → Teilen → Aresium; a computer → AirDrop or Dateien), and **Datei auswählen** (the import picker). For medium
   or low confidence a quiet line: "Bei deiner Bank kann ein Knopf etwas anders heißen." No sources, no jargon, no
   "CSV" in the sentences of the screen (the bank's own label in a step is fine). Opened from: the first run's import
   step (a line under it), the empty dashboard's import area, and Settings → Help → "Datei von der Bank holen".
3. **The tour.** Offered as a quiet line on the first run ("Erst umsehen? Tour mit Beispieldaten") and in Settings →
   Help → "Tour durch Aresium"; never as a pop-up by itself. It runs the real dashboard on a made-up store in a
   temporary folder (as `-samplePhone`), never on the person's store: nothing the person does in the tour changes
   their data, categories or learned shops; at the end or on "Tour beenden" (always visible) the temporary store is
   deleted and the app is as before. The steps (each: the real control highlighted, the rest dimmed, one short card;
   it goes on when the person does the thing or taps Weiter):
   1. "Das ist Aresium mit erfundenen Beispieldaten." (no highlight)
   2. Expenses ↔ income (the page dots / swipe): "Wisch zur Seite: deine Einnahmen."
   3. Current / Overview: "Überblick zeigt alle Monate."
   4. The graph button: "Der Verlauf als Grafik."
   5. A category row: "Tippe auf eine Kategorie: ihre Buchungen in diesem Monat."
   6. A payment: "Jede Buchung im Detail."
   7. Change its category: "Falsch einsortiert? Wähl die richtige Kategorie. Aresium merkt sich den Laden." (the
      "also the other N payments" question appears as in real use)
   8. Settings → Kategorien: "Hier wählst du Kategorien und legst eigene an."
   9. The import button: "Hier kommen neue Dateien von deiner Bank rein." with a link to step 2's guide.
   10. "Fertig. Jetzt mit deinen eigenen Daten." → back.
   Highlights follow the real controls (anchor preferences), work in light and dark, both languages, the largest text
   sizes, VoiceOver (the card is read and the highlighted control is focusable), Reduce Motion (no movement). Keep the
   tour's state in one model that tests can drive step by step.
4. **German** for every new string (`scripts/strings.py sync`, `fill`, "du", plain), `check` 0 problems; every new
   screen looked at in German.
5. **Notes:** `CLAUDE.md` (the phone mode entry: the guide, the tour, the launch arguments).

## Who owns what (another agent works at the same time)

Brief 23 (the unknown-file window and sending a format) runs in parallel in `../empire-ios-23-file-check`. It owns the
import window, the column check (`LayoutConfirmSheet`, moving to `Screens/FileCheck*.swift`) and the import result's
send card. **You own the first run, the tour (new `Tour*` files, anchors on the dashboard's controls) and the guide
(new `BankGuide*` files)**; do not edit `LayoutConfirmSheet`, `MenuChip` or `ImportStore`'s layout flow. String catalogs
will be merged by Claude.

## Done when

- `xcodebuild test` for Aresium passes (`-parallel-testing-enabled NO`) on **your own simulator** (create one, delete
  it at the end; never the booted "iPhone 17" 56D5D752…, Patrik uses it), with tests for: the steps data, the bank
  search, the tour's steps advancing on the action and on Weiter, ending at any step leaves the person's store
  untouched and deletes the temporary one.
- DEBUG launch arguments for screenshots: the guide's list, a bank (one high, one low confidence, one with app steps),
  each tour step; screenshots `build/24-*.png` light and dark, English and German, one at the largest text size;
  contact sheet `build/24-sheet.png`. No real data (there are no real payments on this Mac and you must not look for
  any).
- Final message: files, test counts, screenshots, anything doubtful. Never commit, push, merge or deploy; never touch
  the server, any database or other repos.
