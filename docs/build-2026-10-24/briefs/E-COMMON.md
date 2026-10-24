# Late evening 2026-10-24: four builds in parallel (E1–E4)

Read `COMMON.md` (same folder) first; its rules hold for every E brief. Then `~/empire-ios/CLAUDE.md` (the code map
of every app, the Languages section, the launch arguments) and `DESIGN.md` (same folder: the family look; its rules
hold, except where your brief lets you edit `Shared/`).

- **Four agents at once:** E1 (the app name ends the main screen, all apps), E2 (Arestoteles: search in each tab and
  meaning search in the Search tab), E3 (meaning search on the Arestoteles server), E4 (finding the language setting,
  all apps). Stay inside your brief; the lead merges and resolves overlaps. If you must touch a file another brief
  owns, keep the change small and name it in your final message.
- **Your simulator:** create it yourself, never use the booted "iPhone 17" (that is Patrik's):
  `xcrun simctl create <name> "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-0`, then boot it.
  Build with your own `-derivedDataPath build/DerivedData` inside your worktree. Run tests with
  `-parallel-testing-enabled NO`; never run two test runs on one simulator at the same time.
- **Every new text in English and German** (`CLAUDE.md` → Languages: English in the code, German in the String
  Catalogs, `scripts/strings.py sync`, `fill`, then `check` must say 0 problems). Look at every changed screen in
  German (the simulators are German) and in English (`-AppleLanguages "(en)" -AppleLocale en_GB`).
- **Screenshots** of every changed screen into `build/screens/` in your worktree, looked at by you before you finish.
- **Patrik's vault** (`~/Documents/Patrik Breeck/Weltbild`) is read-only for you and only where your brief says so;
  never copy its text into a file, test, commit or your final message.
