# 04: The red "Aresium mode", the ARESIUM band and its intro animation

Status: merged 2026-10-23. 56 tests pass on main after the merge.
Branch: `codex/04-aresium-red-mode` · Worktree: `../empire-ios-04-aresium-red-mode` · Model: `gpt-6.1-sol`, effort `high`

## Goal

The app gets the mobile website's signature: the big ARESIUM wordmark band at the bottom of every screen,
and tapping it switches into the red Aresium mode with the same intro animation (the word flies up to the
centre, vibrates as it lands, settles into the band while the background morphs). Tapping again, or the X in
the header, leaves it the same way.

## Read first

- `AGENTS.md`, `CLAUDE.md` (always). The app as it is now: `Aresium/Aresium/` (`Screens/Theme.swift` holds the
  dark/light themes and fonts; the header's theme button is in `Screens/Components.swift` /
  `Screens/DashboardScreens.swift`).
- The template:
  - `~/aresium/web/public/app/aresium-intro.js`: the animation, with exact timings (`CFG`), the keyframes
    (`enterWord`, `exitWord`: offsets, translate in vh, x jitter in px, rotation, scale, easings) and when the
    real theme swaps (`swapAt`).
  - `~/aresium/web/public/index.html`: the red theme tokens (`html[data-theme="red"]`, lines ~47–75, incl. the
    layered body gradient), `.aresium-band` / `.mob-band` / `.aresium-word` (size, letter layout spread across the
    full width, gradient text fill per theme).
  - `~/aresium/web/public/app/mobile.jsx`: `THEME_COLORS.red` (expenses `#0a0a0a`, balance `#ffffff`; income
    stays `#34E27A`), the band button, `toggleRed`, and the header theme button (sun/moon, and an X while red,
    which leaves red mode back to the previous theme).

## Build

1. **Red theme** in `Theme.swift`: every token the app already uses, for red, from the website's values; the
   background as the same layered gradient.
2. **The band** below the content on every screen (start, category, month; not on the login screen): the
   ARESIUM letters spread across the full width, Space Grotesk 700, gradient text as on the website for
   dark/light and for red, roughly the website's height (`.mob-band`: 14% of the screen, min 84 pt, above the
   home indicator). Tapping it toggles red mode.
3. **The intro** as a full-screen overlay, matching `aresium-intro.js`: 1.5 s total; background overlay fades to
   the target theme in the first half; the word moves along the same keyframes (enter and the mirrored exit);
   the real theme swaps at 56 % while the overlay covers the screen; the real band is hidden while the overlay
   word is shown, so the landing is seamless. Use SwiftUI's keyframe animations (`keyframeAnimator` or
   equivalent). A soft haptic when the word lands. Taps during the animation are ignored.
4. **Reduce Motion** on: switch instantly, no overlay (as the website does).
5. **Header theme button**: sun/moon as now; X while red, which leaves red mode to the theme used before it.
6. **Remember the theme** (dark, light or red) across launches (`@AppStorage` is fine: it is a display
   preference, not data).
7. **Tests:** theme state machine (dark → red → back to dark; light → red → back to light; the X button; the
   remembered value); Reduce Motion skips the overlay; taps during the animation are ignored. Pure logic in a
   small type so it is testable without UI.

## Settled: do not re-open

- Native SwiftUI animation, no video, no third-party packages.
- Timings and keyframes from `aresium-intro.js` are the spec; small adjustments for points vs vh are fine.
- The band is part of every dashboard screen, as on the mobile website.

## Out of scope

- Widgets, anything about data, import, detail or recategorise (do not change their files beyond colours that
  come from `Theme.swift`).

## Done when

- `xcodebuild test` passes on your own simulator, the existing 44 tests too.
- Screenshots in sample mode: `build/04-red-start.png`, `build/04-red-category.png`, `build/04-dark-band.png`,
  `build/04-light-band.png`, and two frames of the intro mid-flight: `build/04-intro-hero.png` (word at the
  centre) and `build/04-intro-landing.png` (word settling). Say how you captured them (e.g. a launch argument
  that pauses the animation at a given progress).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots, what is missing or
doubtful.
