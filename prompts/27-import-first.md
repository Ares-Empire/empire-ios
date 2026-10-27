# 27: Import data opens the file first; the categories come after the import

Status: running
Repo: empire-ios · Worktree: `../empire-ios-27-import-first` (branch `claude/27-import-first`) · Built by: a Claude
agent (flow and the picker's wording)

## Goal

Patrik pressed "Daten importieren" on the first screen (2026-10-27) and the category picker opened, not the file. He
wants it the other way round: **Import data always opens the file picker first. When an import has added payments and
no category is chosen yet, the category picker opens right after it**, with the payments already in. Ticking a
category sorts the waiting payments into it at once (`PhoneBackend.choose` already sorts again), so people see their
own payments land while they pick.

Today `ImportFlow` (`Model/FirstScreen.swift`) puts the picker before the file picker for the first screen, the
dashboard's import button (`chooseCategoriesFirst` in `ContentView`) and the guide's Choose file
(`BankGuideScreens.swift`).

## Read first

- `AGENTS.md`, `CLAUDE.md` (Aresium phone mode; the first screen; Languages; the design rules).
- `Model/FirstScreen.swift` (`ImportFlow`, `MainScreen`), `ContentView.swift` (the picker sheet, the file importer,
  `importData`, `chooseCategoriesFirst`, `guideImport`), `Screens/BankGuideScreens.swift` (Choose file),
  `Model/ImportStore.swift` (where an import ends, the result line, the file check sheet), `Model/PhoneBackend.swift`
  (`importFiles`, `sort`, `choose`, `addCustom`), `Screens/PhoneScreens.swift` (`PhoneFirstScreen`,
  `CategoryPickerScreen`), `Model/TourData.swift`/`TourModel.swift` (any step that says categories come first).

## Build

1. **One rule, at the end of an import, not at the buttons.** Import data (first screen, dashboard, the guide's Choose
   file) opens the file picker at once. The category picker opens when an import in phone mode **finished and added
   at least one payment** while no category is chosen, whatever started it: the file picker, a file shared into the
   app, a file confirmed in the file check window. Not after: a cancelled file picker, a failed file, a file whose
   payments were all already there, a restore from an export, the tour. Once per import (several files picked
   together: once, after the last). Decide it in one place (the import's end, e.g. `ImportStore` or a small model it
   reports to), not in each screen; remove what the old order leaves unused (`ImportFlow`'s categories-first path,
   `chooseCategoriesFirst`, the guide's own copy of the flow if it is no longer needed). Opening the picker on its own
   from Settings → Categories stays as it is.
2. **The picker after an import** shows one short line at the top saying the payments are in and to tick the
   categories used, sorting happens right away (English in the code, German "du", plain; no slogan). Nothing is
   preselected (Patrik, 2026-10-26: stays). Closing it with nothing ticked is allowed: the payments stay as Not sorted
   and the next import asks again.
3. **The result line stays true.** The import's line says e.g. "120 new · 0 sorted · 120 not sorted" before any
   category exists. After the picker closes, what the person reads must match the store (recount the sorted / not
   sorted of that import, or show a line that does not claim numbers that changed). Say what you chose.
4. **Text that describes the old order**: the first screen's comment, the tour's steps, the guide, `CLAUDE.md` (the
   phone mode and first screen entries, lines ~503–513 and ~592). Fix any that say categories come first.
5. **DEBUG**: a launch argument that shows the picker as it opens after an import (made-up data, `-samplePhone…`
   style), for screenshots.

## Settled: do not re-open

- Nothing preselected; the list, its groups and the untick question stay as they are.
- The look of the first screen, the tour and the picker stays (only the new line in the picker).
- Server mode (Patrik's) is unchanged: its import has no category picker.

## Out of scope

The payment detail page, the engine, the server, other apps.

## Done when

- `xcodebuild test` for Aresium passes (`-parallel-testing-enabled NO`) on **your own simulator** (create one, delete
  it at the end; never the booted "iPhone 17" 56D5D752…, Patrik uses it), with tests for: Import data opens the file
  picker first; the picker opens after an import that added payments with no category chosen; not after a cancelled /
  failed / all-duplicate import, a restore or with categories chosen; once for several files; ticking after the
  import sorts the waiting payments; the result line after the picker. Empire builds if `Shared/` changed.
- `scripts/strings.py check` 0 problems; the picker looked at in German and English, light and dark, and at the largest
  text size. Screenshots `build/27-*.png` (first screen → file picker; the picker after an import with the new line;
  the dashboard after ticking).
- Final message: files changed, test counts, the screenshots, what you chose for the result line, anything doubtful.
  Never commit, push, merge or deploy; never touch the server, any database or other repos. No real data: there are no
  real payments on this Mac and you must not look for any; use the made-up tour/sample files.

## Added (Patrik, 2026-10-27, sent to the running agent)

**Counts in the picker:** each row shows how many of the person's payments the category has (ticked; own categories)
or would get if ticked (default categories not ticked: one `sortPayments` dry run over the payments waiting as Not
sorted with every default category plus the chosen ones; nothing stored), as a quiet number ("34", read as "34
payments"). None at 0 or without payments. Recounted after every tick. Nothing preselected; the list's order stays.
Shown wherever the picker shows (after an import, Settings → Categories, the tour's Settings). One function on the
phone side (category id → count), tested.
