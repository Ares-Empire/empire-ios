# 61: Arestemis Settings: a compact Application section, the flicker, and ImmoScout24 in the app

Status: merged 2026-10-31 (tests pass; every changed screen in both languages and looks; Claude: settings load with the home screen so the sheet opens complete, samples from the Arestemis repo, `docs/briefs/63-arestemis-more-portals.md`; the flicker not reproduced on iOS 27.0)
Branch: `claude/61-arestemis-settings` · Worktree: `../empire-ios-61-arestemis-settings` · Agent: Claude (design)

## Goal

Patrik tested Arestemis build 2 on his iPhone (2026-10-31) and asked, in his words:

- "In settings lets move the Bewerbung down and make it smaller like the other settings. Lets give it a toggle between
  automatic generation and own text. Then you can click on it and it opens a screen with either a field for your own
  text or notes that the automatic generation should include."
- "When opening and closing settings the background sometimes flickers a little with a small black corner."

Two server briefs run at the same time: **62** (the server stores `application_notes` and the automatic text uses
them instead of the own text) and **63** (the server gains the portal `immoscout24`). This brief is the app's side of
both, plus the flicker. Arestemis build 3 goes to Patrik's phone right after it.

## Rules

- `AGENTS.md` and `CLAUDE.md` apply in full (Languages, Light mode, the Arestemis entry, Settings). You are the design
  agent: the look is yours, built from the **existing components only** (`SettingsSection`, `SettingsRow`,
  `SettingsRowStyle`, `SettingsDivider`, `TextArea`, `Caption`, `FormNote`, `glassCard`, the shared switch style
  `EmpireSwitchStyle` that SettingsScreen already applies). No new looks, no new decoration.
- Work only in your worktree; build output in its `build/`. **Do not commit** (Claude reviews and commits). Your own
  simulator: `xcrun simctl create claude-61 "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-0`, delete it at the
  end. `-derivedDataPath build/DerivedData`.
- Another session works on Aresium at the same time and may change `Shared/`. If you need to change `Shared/`, first
  `git merge main` in your worktree, keep the change small, and check that Aresium, Aresus, Arestoteles and Empire still
  build.
- German: you write it (String Catalogs; edit single keys with `scripts/strings.py`'s own `load`/`save` via
  `sys.path.insert(0, 'scripts')`, then `python3 scripts/strings.py check` must say 0 problems; do not run a full
  `sync`). German uses "du". No "KI"/"AI" anywhere in Arestemis's text (Patrik, 2026-10-31).

## Read first

- `Arestemis/Arestemis/Screens/SettingsSheet.swift` (the section as it is: segmented picker, two text areas, captions,
  then Notifications), `Shared/Design/SettingsScreen.swift` (the rows of General, Help, About: the look to match; how
  Language and Appearance open as pages with `navigationDestination`), `Shared/Design/` pages such as
  `LanguageScreen`/`AppearanceScreen` (the look of a page inside Settings)
- `Arestemis/Arestemis/Model/ArestemisModels.swift` (`Settings`, `Source`, `Place`, `Search`, `SourceStatus`,
  `Listing`), `Model/ArestemisStore.swift` (load/save settings), `Model/AppNavigation.swift` (launch arguments for
  screenshots), `ContentView.swift` (the sheet with `.presentationBackground(Ink.background)`)
- `docs/reviews/2026-10-31-arestemis-phone-test.md` (rounds 1–2: Patrik's earlier notes on the same app)
- The server contract: `~/Arestemis/docs/API.md` (Settings, Source). Read only.

## Build

### 1. The Application section, compact (Patrik's first note)

- **Order** of Arestemis's own sections: Notifications first, then **Application** ("Bewerbung"), then the shared
  sections as now. The app's own sections stay in the `appSection` slot (no `Shared/` change needed for this).
- **Application** becomes one `SettingsSection` card of rows, the same height and type as General's rows:
  1. A switch row **"Write automatically"** ("Automatisch schreiben"), on = `applicationMode == .ai`, off = `.own`.
     A short subtitle under the title is fine if it reads well ("One text per listing" · "Ein Text pro Angebot").
  2. A row that opens a page, and changes with the switch:
     off → **"Your text"** ("Dein Text"), on → **"Notes"** ("Hinweise"). Its value/subtitle shows the first line of
     what is written, or "Not written yet" / "None" in the muted ink.
  3. A row **"About you"** ("Über dich") that opens its page (it is used by the check and by automatic texts, so it
     stays in both modes).
- **The pages** (pushed inside the Settings navigation, like Language): the page title, one `TextArea` in a glass
  card, and its caption under it. Keep the keyboard's Done.
  - Your text: the existing placeholder "Hallo, …" and caption "Your text as it is, with the greeting adapted when the
    contact's name is known."
  - Notes: placeholder like "e.g. I can come to a viewing any evening, my parents act as guarantors"; caption: every
    automatic text includes these points, and only these notes and the facts about you are used, nothing is made up
    (your wording, short).
  - About you: the existing placeholder and caption (gender and age needed for the check).
- Changes are still saved when the Settings sheet closes (one draft for the whole sheet; the pages edit the same
  draft). Check that text typed on a page is saved after going back and closing.
- Remove the segmented picker and the old captions. Nothing else on the page changes.
- Launch argument for screenshots, like the existing ones: `-openSettingsPage ownText|notes|aboutMe` (with
  `-openSheet settings`).

### 2. `application_notes` in the app's `Settings`

- `Settings.applicationNotes: String` ↔ `application_notes`. **Decoding must accept a server answer without the
  field** (the server change described in the Arestemis repo, `docs/briefs/62-arestemis-application-notes.md` may land a little later): missing = `""`. Encoding always sends it.
- Sample data and `SampleBackend` get the field. Tests in `DecodingTests` for both cases.

### 3. ImmoScout24 in the app

- `Source` gains `immoscout24` (name "ImmoScout24", wherever the app names portals).
- **Unknown portal values must never break the app again**: an array of sources (`Place.sources`, `Search.sources`,
  `Overview.sources`) skips values the app does not know, and a listing from an unknown portal still decodes (show
  the server's `source_name`). The portal list in Search shows only known portals. Tests for each case.

### 4. The flicker (Patrik's second note)

Opening and closing Settings (the gear on the Hunt tab) sometimes flickers the background and shows **a small black
corner** for a moment. Reproduce it on your simulator (record with `xcrun simctl io claude-61 recordVideo` while
opening and closing, in light and dark; look at the frames; Simulator's slow animations help), find the cause and fix
it at its source. Candidates to check, not conclusions: the sheet's `.presentationBackground(Ink.background)` against
`SettingsScreen`'s `SettingsWall` background and the `NavigationStack`'s own background; the settings loading state
switching to the content while the sheet animates; the window or root view background behind a large sheet. If the
cause is in `Shared/` (every app's Settings), fix it there under the rule above and check another app's Settings too.
If you cannot reproduce it, say so and what you tried; do not ship a guess.

## Settled: do not re-open

- Automatic mode uses the facts about you and the notes, not the own text (the Arestemis repo, `docs/briefs/62-arestemis-application-notes.md`). The own text stays stored.
- The switch, not a segmented control; the row and its page follow the switch.
- No changes to the Application sheet (it already says "Automatisch geschrieben" / "Dein Text").

## Out of scope

- The server (the Arestemis repo, `docs/briefs/62-arestemis-application-notes.md`, `docs/briefs/63-arestemis-more-portals.md`). Aresium. The Hunt, Search and Listings screens beyond the portal enum.

## Done when

- `xcodebuild test -scheme Arestemis` passes on `claude-61` with the new tests; `python3 scripts/strings.py check` 0
  problems; if `Shared/` changed, Aresium, Aresus, Arestoteles and Empire build.
- Screenshots in `build/61-*.png`, German and English, light and dark: Settings top (Notifications + Application, the
  switch off and on), each of the three pages with text and empty, and Search's portal list with ImmoScout24.
- The flicker: before/after frames or a clear description of what you saw and changed.

## Final message

Files changed; the exact build and test summary lines; the screenshots' paths; the flicker's cause and fix (or what
you tried); new strings with their German; anything missing or doubtful.
