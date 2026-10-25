# G1: switching the language restarts the app by itself

Read `COMMON.md` (same folder) first, then `~/empire-ios/CLAUDE.md` (Languages, Settings),
`~/ares-empire/docs/LANGUAGES.md`, `Shared/Language/` (`AppLanguage`, `LanguageSetting`), `Shared/Design/LanguageScreen.swift`
and `SettingsScreen.swift`, and each app's root (`<App>App.swift`, `ContentView.swift`). Worktree:
`~/wt/empire-ios-langrestart` (branch `language-restart`). Simulator: create `agent-langrestart` yourself
(`xcrun simctl create agent-langrestart "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-0`); never use the
booted "iPhone 17" (Patrik's). You may edit `Shared/`. Brief F2 (accounts) edits `Shared/Auth`, the login screens and
Settings → Account at the same time: stay out of those parts.

## Why

Patrik (2026-10-25), after switching Aresus to English and seeing nothing change: "can we make them automatically
restart? and can we make it like most apps do so that you press 'English', a small window opens that basically tells
you youre about to switch and the app will restart, you either hit cancel or apply ... and the app restarts. ... lets do
that for all apps we have so far".

## What it does

- Settings → Language → tapping a language that differs from the one shown opens a confirmation (a native alert or
  confirmation dialog): title like "Switch to English?" / "Auf Deutsch umstellen?" (each in the language it switches
  to, plus the current one if that reads better: decide and say why), one line "<App> restarts in English.", Cancel and
  a confirm button ("Restart" / "Neu starten").
- Confirm: the choice is saved as today (the app's own `AppleLanguages`, the same setting iOS's per-app Language
  uses), then the app **restarts inside itself**: the whole view tree is built again in the new language (back to the
  main screen, sheets closed), the stores reload so server sentences come in the new language (`Accept-Language`),
  push registration sends the new language. No `exit()` (Apple asks apps never to quit themselves).
- Every text must follow, not only SwiftUI literals: `String(localized:)` in models and components, the shared tables
  (`Shared`, `AresiumShared`, `AresusShared`), plurals, `AppLanguage.current`, the formatters (`AppLanguage.locale`).

## First: prove it works (spike, then decide)

Before building it into five apps, find a clean way in one app (Aresus) that switches **all** of these at runtime:
SwiftUI `Text("…")`, `Text("…", tableName: "Shared")`, `String(localized:)` with and without a table, a plural, and a
date/number formatted with `AppLanguage.locale`. Likely pieces: the root keyed by the language (`.id(language)`),
`.environment(\.locale, language.locale)`, and making the localized lookups use the chosen language's `.lproj`
(for example one shared lookup bundle that `AppLanguage` sets; measure, don't guess, and prefer a supported API over
swizzling if one covers every path). Write unit/UI tests that pin each path in both directions.

If no clean way covers every path, stop and report the findings in your final message instead of shipping a half
switch (the fallback the lead will decide on: the same confirmation, then the app saves the choice and asks to be
reopened).

## Then

- One shared piece (`Shared/Language/` + the confirmation in `LanguageScreen`), each app's root wired to it.
- The widgets (Aresium's, Aresus's): check what language they show after the switch and say so (they run in their own
  process); make them follow if it is simple.
- Tests: the switch logic and every lookup path (both directions); each app's suite passes (one after another);
  `scripts/strings.py check` 0 problems.
- Screenshots per app: the confirmation (German and English), the app after switching both ways (a screen with
  literals, model texts, a plural and a date). `CLAUDE.md` (Languages) and `ares-empire/docs/LANGUAGES.md` content
  for the lead (you can't edit ares-empire: put the new paragraph in your final message).
