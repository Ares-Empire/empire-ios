# 67: Arestemis: the black corner on the Hunt card

Status: merged 2026-11-01, did not fix it (build 4 still showed it). Its cause was wrong: the blur was not the problem; the pulse redrew pathless shadows offscreen every frame, fixed in brief 87. Its changes stay (the blur out of every shadow, the fade without a mask).
Branch: `claude/67-arestemis-black-corner` · Worktree: `../empire-ios-67-arestemis-black-corner` · Agent: Claude (design)

## Goal

On Patrik's iPhone a small black corner flashes on the hunt's card, and since build 3 it happens very often. After this
brief it never appears, and the card looks exactly as it does now. Arestemis build 4 goes to his phone right after.

## What Patrik sees (his words)

- Build 3, 2026-11-01, iPhone 17 (iPhone18,3), **iOS 27.0.1**: "I see it appearing in the 'Suche läuft' field on the
  'Jagd' screen. Rn very frequently. The black field goes black in the corner. It needs fixing." (That is the
  `HuntCard` at the top of the Hunt tab, with the status "Suche läuft"/"Hunting", in dark mode.)
- Build 2, 2026-10-31: "When opening and closing settings the background sometimes flickers a little with a small black
  corner." Settings opens from the gear on the same screen, so the card behind the sheet is the likely place both
  times, and one cause is likely.
- His hunt has been **active** since build 3 was installed, so the status dot pulses all the time. Earlier it was often
  paused.
- Brief 61's agent could not make it appear on the simulator (iOS 27.0). That fits a compositing glitch that shows on
  the device's GPU only, so not reproducing it on the simulator says little.

## What is in play (facts from the code, not conclusions)

- `HuntCard` (`Arestemis/Arestemis/Screens/HuntScreen.swift`) uses `.glassCard(accent: Look.accent, raised: true)`
  (`Shared/Design/EmpireDesign.swift`, `GlassCard`). That is a `ZStack` background of `shape.fill(.ultraThinMaterial)`
  (a backdrop blur), a translucent card fill and a white radial highlight from the top left. Over it sits the
  gradient edge stroke, and **`.shadow` on the whole composite**, which includes the card's content.
- Inside the card, `StatusDot` (`Screens/Style.swift`) runs a **`repeatForever` pulse**: a circle behind the dot, scale
  1 → 2.6, opacity 0.9 → 0, every 1.8 s, while the hunt is active.
- The Hunt tab's `WordmarkScrollView` has `.edgeFade(top: 16)`. That is a **`.mask` over the whole scroll view**
  (`Screens/Style.swift`, `edgeFade`), so everything in it, the materials included, is composited through a mask.
- Also on the card: `.animation(.easeOut(duration: 0.2), value: hunt?.active)`. On the screen: the overview reloads
  every 60 s, and a `TimelineView` updates "Last scan" every 5 s with `.numericText()`.
- Things to test, not conclusions:
  - a backdrop material inside a masked (offscreen) subtree that the pulse makes re-render every frame;
  - the shadow computed from the composite, which changes every frame with the pulse;
  - the material's rounded clip failing in single frames, so a square corner shows.

## Rules

- `AGENTS.md` and `CLAUDE.md` apply in full. You are the design agent: the fix must not change the look. The pulse stays
  (it is how the card says the hunt is running), unless you prove it cannot exist without the glitch; then say so and
  propose the closest look, do not just remove it.
- Work only in your worktree; build output in its `build/`. **Do not commit** (Claude reviews and commits). Your own
  simulator: `xcrun simctl create claude-67 "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-0`, delete it at the
  end. `-derivedDataPath build/DerivedData`.
- **Do not install anything on the physical iPhone** ("X", paired with this Mac). It is Patrik's phone with the
  TestFlight build and working push; a development build would replace it.
- If the fix is in `Shared/` (`GlassCard` is used by every app): first `git merge main` in your worktree, keep the change
  small, and check that Aresium, Aresus, Arestoteles and Empire still build and that one card screen per app looks
  the same (before/after screenshots).

## Build

1. **Find the cause.**
   - Try to make it show on the simulator: sample mode with an active hunt, Hunt tab on screen for a few minutes, open
     and close Settings, scroll a little so the card passes under the top fade, light and dark. Record with
     `xcrun simctl io claude-67 recordVideo` and look at the card's corners frame by frame.
   - Find out which layers render offscreen. Simulator's Debug menu has "Color Off-screen Rendered"; clicking it via
     `osascript` is fine.
   - Narrow it down in a scratch build by switching one piece off at a time: pulse, mask, shadow, material.
2. **Fix it at the source, with the look unchanged.** For example, keep the material out of a per-frame offscreen
   pass: a top fade that is not a mask over content holding materials, or a shadow taken from the card's shape instead
   of its animated content. Pick what the evidence supports. Check the other Arestemis screens for the same pattern
   (Listings, Search, Match detail use `edgeFade` and glass cards too) and fix them the same way.
3. **We cannot see Patrik's screen before build 4**, so the reasoning must hold on its own. In the final message, say
   why the change removes the cause, with evidence: offscreen colouring before/after, frames, or documented platform
   behaviour.

## Settled: do not re-open

- The glass card look (material, fill, highlight, edge, shadow) and the top fade stay as they look now.
- The pulse stays (see Rules).

## Out of scope

- Anything else in the app; the server. The German tab names were already changed (Jagd → Suche, Suche → Filter,
  commit 0e89d13). Leave them.

## Done when

- `xcodebuild test -scheme Arestemis` passes on `claude-67`; if `Shared/` changed, the other four apps build.
- Before/after screenshots in `build/67-*.png` (Hunt tab, light and dark, hunt active; Listings and Filter tabs), and
  the same for one screen per other app if `Shared/` changed.

## Final message

The cause and the evidence; the fix and why it removes the cause; files changed; the exact build and test summary
lines; the screenshots' paths; anything doubtful.
