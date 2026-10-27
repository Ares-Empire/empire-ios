# 18: Phone mode finished: the look of the new screens, German, and the loose ends

Status: merged 2026-10-27
Repo: empire-ios · Worktree: `../empire-ios-18-phone-finish` (branch `claude/18-phone-finish`) · Built by: a Claude
agent (design work)

## Goal

Brief 15 built Aresium's phone mode with plain structural screens. Make them look like Aresium, write their German,
and close the small gaps it left, so a friend's first minutes with the app feel finished: open the app, pick
categories, import a bank file (confirming the columns once if the bank is unknown), see the dashboard, correct a
payment.

## Read first

- `AGENTS.md`, `CLAUDE.md` (Languages, Light mode, Settings; the design rules: "Design stays with Claude", start
  from the existing components, not new decoration), `~/ares-empire/EMPIRE.md` → the crown language, and the memory
  of the design restraint: Aresium's look is the website's (`~/aresium/web/public/app/mobile.jsx`, `index.html`
  themes), ink only, red is the special mode, no slogans, no new accent colours.
- The screens as they are: `Aresium/Aresium/Screens/PhoneScreens.swift`, `ContentView`, `DashboardScreens`,
  `ImportControls`, `RecategoriseSheet`, `Model/LayoutDraft.swift`, `Model/PhoneSettingsModels.swift`; the existing
  look to match: `Screens/Components.swift`, `LoginScreen.swift`, `TransactionDetailSheet.swift`, `Shared/Design/`
  (`FormPieces`, `SettingsScreen`, `AccountScreens`). Screenshots of the structural versions: run the sample arguments
  below.
- The plan: `~/ares-empire/docs/ARESIUM-FOR-OTHERS.md` (parts 2–5).

## Build

1. **The look** of: the first run (`-samplePhoneEmpty`: what Aresium does with your data, in one or two calm
   sentences, then the two steps "Choose categories" and "Import a bank file" as clear actions, and Restore as a quiet
   link), the category picker (`-samplePhone -openSheet categories`: groups as the dashboard's rows look, each with
   its icon and colour; own categories; the untick question), the column check (`-sampleLayout`: the file's name, each
   column with its sample values and its meaning as a menu, the first payments read that way, Confirm), the merchant
   question (`… -samplePhoneSwitch "Eating out"`: keep it a short dialog, readable), the import result line, the
   "needs a connection" state (`-sampleModeOffline`), and the Settings rows for the data. Light and dark, both
   languages, the large text sizes not breaking. Reuse Aresium's own pieces; no new components unless one is missing.
2. **German** for every new key (`scripts/strings.py sync`, then `fill`; "du", plain; the app's terms Buchung,
   Ausgaben, Einnahmen; "Kategorien", "Bankdatei", "Spalten"). `scripts/strings.py check` must say 0 problems. Look at
   each new screen in German; a label that wraps gets a shorter word.
3. **"Uncategorised" in the app's language:** the dashboard's synthesised category arrives named `Uncategorised`
   (from the engine and the server). Show it as "Not sorted" / "Nicht sortiert" wherever a category name is shown, in
   both modes, through one display function (not at each call site); Switch/Add keep sending the real name.
4. **The shop list's licence:** Settings → About → Fonts & licences also shows the name-suggestion-index notice
   (BSD-3-Clause, "Copyright 2026, name-suggestion-index contributors", the full text from
   `~/aresium/src/engine/sorting/shops.de.json`'s header), only in Aresium (the other apps do not ship the list).
5. **Share sheet:** Aresium is also offered for MT940 files (`.sta`, `.mt940`, and `.txt` only if the system allows a
   narrow enough type; say what you chose) in `Aresium/Aresium/Info.plist`'s document types.
6. **Notes:** `CLAUDE.md` → Setup state gets an "Aresium phone mode" entry (how it works, the files, the launch
   arguments, the data lifecycle, the engine script) in the style of the other entries; Open 5 says phone mode is built.

## Settled: do not re-open

- No change to the data side, the mode logic or the lifecycle (brief 15, checked). No new colours or fonts.
- Server mode's screens look exactly as today.

## Done when

- `xcodebuild test` for Aresium passes; Empire builds (Shared untouched unless needed).
- Screenshots in `build/18-*.png` of every screen above in light and dark, English and German, plus one at the
  largest text size; a contact sheet `build/18-sheet.png`.
- Final message: files changed, test counts, the screenshots, and anything you would still change.
