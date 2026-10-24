# E4: finding the language setting, in every app

Read `E-COMMON.md` first, then `ares-empire/docs/LANGUAGES.md`, `Shared/Language/AppLanguage.swift` and the Languages
section of `~/empire-ios/CLAUDE.md`. Worktree: `~/wt/empire-ios-language` (branch `language-entry`). Simulator:
`agent-language`. You may edit `Shared/` (but nothing in `Shared/` may use `UIApplication.shared`: the Aresium
widget compiles it).

## Why

Patrik (2026-10-24): "how do I switch languages? We build english and german for each app but at least in arestoteles
I dont see how to switch." The decision so far: no switch inside the apps, because iOS has one per app (Settings →
Apps → the app → Language). It holds (one setting that the app, its widget and its server texts all follow), but
nobody finds it. So every app gets a visible entry that leads to it.

## 1. Find out how iOS 27 behaves (simulator)

- Does an app's page in the Settings app show the Language entry when the phone lists only **one** language (German),
  and when it lists **two** (German, English)? Set the simulator's list with
  `xcrun simctl spawn <udid> defaults write -g AppleLanguages -array de` (or `-array de en`), reboot the simulator,
  open the app's settings page from the app (a DEBUG launch argument that opens `UIApplication.openSettingsURLString`)
  and screenshot it.
- Does writing the app's own `AppleLanguages` (`xcrun simctl spawn <udid> defaults write de.ares-empire.arestoteles
  AppleLanguages -array en`) switch the app at its next launch, and does the Settings page then show that language?
- Put the findings in your final message (with the screenshots' names).

## 2. One shared entry for every app

A shared piece in `Shared/` (logic in `Shared/Language/`, the view in `Shared/Design/`), placed in each app where its
account actions are, next to Log out: Arestoteles (the header menu, `Screens/Style.swift`), Arestemis
(`Screens/SettingsSheet.swift`), Aresus (`Screens/WatchtowerScreen.swift`), Aresium (`Screens/Components.swift`),
Empire (`Screens/EmpireHome.swift`; if it has only an icon button for Log out, make the smallest clean change). It
shows the language the app shows now: "Sprache · Deutsch" / "Language · English".

- **If iOS shows its Language entry even with one language listed:** the entry opens the app's settings page.
- **If iOS needs two languages listed:** the entry opens a small sheet with three choices: like the iPhone, English,
  Deutsch. Choosing writes the app's own `AppleLanguages` (the setting iOS's per-app Language uses; "like the iPhone"
  removes it) and says in one line that the app switches the next time it is opened. Below, one muted line where iOS
  keeps the same setting.
- Pure logic (the current choice, writing/removing the setting, the shown name) unit-tested in `EmpireTests` or
  wherever `Shared/Language` is tested now (`AppLanguageTests`).

## Done when

- All five apps build; each app's test suite passes (one after another); `scripts/strings.py check` says 0 problems.
- Screenshots per app (German and English) of the entry where it sits and of what it opens; one showing an app
  switched to English after a relaunch.
- `~/empire-ios/CLAUDE.md` → Languages updated (where the entry is, how it works). Not `ares-empire` (the lead updates
  `LANGUAGES.md`).
