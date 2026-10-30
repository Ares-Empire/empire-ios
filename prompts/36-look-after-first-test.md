# 36: The look after the first phone test: own categories' icons, Save at the top, a readable bank-guide line

Status: merged 2026-10-30 (Aresium 361 tests, Empire tests pass, the other apps build; store schema 4; the light-mode bug found and fixed in AppRoot)
Branch: `claude/36-look` · Worktree: `../empire-ios-36-look` · Built by: a Claude agent (flow and the look)

## Goal

Patrik's first test of Aresium's phone mode (2026-10-30, `docs/reviews/2026-10-30-aresium-phone-test.md`, findings 4–7;
read it) found three things about the look. After this brief, each category of one's own gets an icon of its own
(fitting its name where possible), the category change sheet saves from the top like every iOS edit sheet, and the bank
guide's "only on the website" line is easy to read in light and dark.

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules: ink only, gold only as an accent, no slogans, Apple's own controls where they
  exist; "Light mode"; "Languages"; the "Aresium phone mode" entry)
- `Aresium/Aresium/Model/PhoneCategories.swift` (`look(of:)`, `sourceCategories`), `Model/PhoneLedger.swift`
  (`StoredChosen`, `choose(_:name:)`), `Model/PhoneBackend.swift` (`addCustom`), `Model/PhoneStore.swift` (schema
  stages), where the engine's icon names (`Tag`, `ShoppingCart`, …, from `~/aresium/src/engine/categories.ts`) become
  SF Symbols in the app, `Screens/PhoneScreens.swift` (`CategoryPickerScreen`), `Screens/RecategoriseSheet.swift`,
  `Screens/BankGuideScreens.swift` (the `otherPlaceLine` note, line ~272), `Shared/Design/FormPieces.swift` (`FormNote`).

## Build

1. **Own categories get their own icon.** Today every category made with "A category of your own" shows the engine's
   one fallback (`CUSTOM_CATEGORY_LOOK`: Tag, grey). New: when one is created, it gets an icon that fits its name if a
   word of the name is known (a word list in English and German, for example fitness/sport → a dumbbell, Haustier/pet →
   a paw, Kaffee/coffee → a cup, Geschenke/gifts → a gift, Auto/car → a car, Kinder/kids, Garten/garden, Musik/music,
   Spiele/games, Reisen/travel, Bildung/learning, Spenden/donations; choose well-known SF Symbols that exist on iOS 26),
   otherwise the first icon of a fixed set that no other own category uses yet; and a colour from a small set that
   sits with the default categories' colours, also differing from the other own categories where possible. Two own
   categories never share an icon unless the set is used up. The choice is **stored** with the category so it never
   changes (a lightweight store stage after the current one, as briefs 31 and 33 did; a test opens a store made by
   today's main). Own categories that exist already get theirs in their creation order when the store is opened. The
   picker, the dashboard and every list show the stored look. Keep the word list and the choice in a model with unit
   tests, out of the views.
2. **Save at the top of the category change sheet** (`RecategoriseSheet`). Patrik: Save at the bottom is far from a
   category at the top, and iOS edit sheets keep Cancel top left and Save top right. Move Save into the toolbar
   (`.confirmationAction`, disabled as today, "Saving…" state kept); keep "Save & remove from current" in Add mode where
   it reads well (your call); the follow-up question after a Switch works as before.
3. **The bank guide's "In der App der Bank geht das nicht, nur auf der Website."** (`FormNote`, 12.5 pt, `Ink.muted`)
   is too small and faint, in dark mode most of all. Show it as part of the guide: the size of the steps' text and a
   colour with enough contrast in both looks (`Ink.secondary` or the guide's own style). Do not change `FormNote` for
   everyone.
4. **Light mode check.** With the simulator in light appearance and the app's choice "Like the iPhone" (the default),
   the app is light; with the simulator dark, dark. Screenshot the start screen both ways (`build/36-light.png`,
   `build/36-dark.png`). If it does not follow, find out why and fix it.

## Settled: do not re-open

- Icons are SF Symbols, chosen on the phone; nothing is sent anywhere, no AI.
- The default categories keep their engine looks.

## Out of scope

- The engine (brief 34 runs in parallel in `aresium`), `PhoneBackend.switchCategory`/`otherPayments`, `PhoneLedger.move`
  and the picker's sorting/waiting logic (brief 35 runs in parallel in `../empire-ios-35-counting`: avoid those
  functions so the merges stay clean; adding a field to `StoredChosen` and a store stage is yours).

## Done when

- `xcodebuild test -scheme Aresium` passes on your own simulator (`claude-36`, commands in `AGENTS.md`), with the new
  tests (the word list, distinct icons, the stored choice, the store stage from today's main).
- Screenshots in `build/`: the picker with three own categories (`36-own-categories.png`, light and dark), the change
  sheet with Save at the top (`36-recategorise.png`), the bank guide line in dark (`36-bank-guide-dark.png`), and the
  two light-mode ones.
- Every new string in English and German (the String Catalogs).

## Final message

Files changed, the exact build and test summary lines, the screenshots' paths, what is missing or doubtful. Never commit,
push or merge: Claude does.
