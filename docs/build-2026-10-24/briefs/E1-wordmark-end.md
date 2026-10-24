# E1: the app's name ends the main screen, in every app

Read `E-COMMON.md` first. Worktree: `~/wt/empire-ios-wordmark` (branch `wordmark-end`). Simulator: `agent-wordmark`.
You may edit `Shared/Design/` for this brief.

## Why

Patrik (2026-10-24): "Lets make it general app design that when scrolling down, the bottom has the app name there
like in Aresus, Arestemis and Aresium. Although: in Aresium the word is always seen but it should only be there when
scrolling down (like in Aresus and Arestemis)."

## The rule (for every app, now and later)

- The app's `WordmarkBand` (`Shared/Design/EmpireDesign.swift`) ends the scroll content of the app's **main screen**
  (the first tab's root). It scrolls with the content and is never fixed on screen.
- It is **not visible when the screen opens**: when the content is shorter than the screen, the band starts just below
  the bottom edge, so it only shows when you scroll down. When the content is longer, it simply follows the content
  (as in Aresus now: 44 pt above, 10 pt below).
- **One shared piece** in `Shared/Design/` does this (for example a view that ends the content and knows the visible
  height, or a scroll container; choose the smallest clean API, documented in one comment). No app measures the screen
  itself.

## Work

1. Build the shared piece. Move Aresus (`Aresus/Aresus/Screens/WatchtowerScreen.swift`) and Arestemis
   (`Arestemis/Arestemis/Screens/HuntScreen.swift`) onto it with the same look as now. Keep their `-scrollToEnd` /
   `-scrollBottom` launch arguments working.
2. **Aresium:** its band (`AresiumBand` in `Aresium/Aresium/ContentView.swift`, with the palette for its special mode)
   is fixed on screen today. Move it to the end of the start screen's scroll content on the shared piece, keeping its
   look and its special-mode colours (the special mode must still look as it does). Add `-scrollToEnd` for the
   screenshots if there is no such argument.
3. **Arestoteles:** add the band (`ARESTOTELES`) at the end of the Positions tab (its main tab,
   `Arestoteles/Arestoteles/Screens/PositionsScreen.swift`). Add `-scrollToEnd` for it.
4. **Empire app:** look at its home. If it scrolls and does not end with a wordmark, add one (the word the hub uses for
   itself; check `ares-empire/web/app/mobile.jsx` and the existing Empire screens). If it does not scroll, leave it and
   say so.
5. Update the rule in `DESIGN.md` (this folder, the line about `WordmarkBand`) and in `~/empire-ios/CLAUDE.md` (one
   line under a fitting place, e.g. a short "Design" note at the top, naming the shared piece).

## Done when

- All five apps build; each app's test suite passes (run them one after another).
- Screenshots per app, in German: the main screen as it opens (no band visible, also when the content is short: use
  Aresus `-sampleAllGood` or an app's empty sample if there is one) and scrolled to the end (band visible). Aresium also
  in its special mode at the end.
