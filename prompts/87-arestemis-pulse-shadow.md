# 87: Arestemis: the black rectangle on the hunt card, for real

Status: merged 2026-11-01 (the pulse redrew pathless shadows offscreen every frame; GlassCard now draws none, look kept; Arestemis build 5 is the test on the phone)
Branch: `claude/arestemis-pulse-shadow` · Worktree: `../empire-ios-pulse-shadow` · Done by Claude (small fix, no agent)

## What Patrik saw

Build 4, 2026-11-01 evening, iPhone 17, iOS 27.0.1, dark: "I still get the black corner on my phone. I can even force
it by reloading the screen." His screenshot (20:16, Hunt tab, hunt active): a sharp greenish-black rectangle from the
screen's left edge to 103 pt, from 105 pt to 229 pt down, over the hunt card's top left. Brief 67's fix (the blur out
of the shadow, the fade without a mask) did not remove it, so its cause was wrong.

## The cause, from the screenshot

- **Its edges are the pulse's shadow.** `StatusDot`'s pulse ring is 8 pt and grows to 2.6×; at full size it spans
  x 31.5–52.3 pt, y 142.4–163.2 pt (the dot's centre measured in the screenshot at 41.9, 152.8). Its shadow (the card's,
  radius 22, y 14) reaches about 51 pt around it, moved 14 pt down: right edge 52.3 + 51 = 103.3 (measured 103.3), top
  142.4 + 14 − 51 = 105.4 (105.3), bottom 163.2 + 14 + 51 = 228.2 (228.7), left past the screen's edge.
- **Its place in the drawing order is the pulse's.** Inside the rectangle the card's fill is darkened (29,30,32 →
  9,9,9) but the card's edge line (an overlay, drawn last) is intact on top, and so are the dot and the text drawn after
  the pulse. Something drawn after the fill and before the dot: the pulse ring is the first piece of the card's content.
- **Why the pulse has a shadow.** `GlassCard` put `.shadow` around its whole content. SwiftUI gives every layer under a
  `.shadow` a shadow of its own without a path (brief 67's layer dump: the pulse ring is a `CALayer` with
  `SHADOW(radius 13.9 …, path=none)`, its opacity and scale animated). Core Animation draws such a shadow from the
  layer's pixels in an offscreen pass, for the pulse every frame. On the phone's GPU that pass sometimes came out as an
  opaque dark block the size of the shadow. Never on the simulator.

## What else is in that patch every frame

Removing only the content's shadows (the first step) cut a pulse frame's offscreen passes on the simulator from about
45 to 17 (`CA_PRINT_OFFSCREENS`), but those 17 were the card surface's own shadows (fill, highlight, edge) and the
blur's masked shadow (`MaterialShadow`), all redrawn under the pulse. The order of drawing allows any pass drawn after
the fill to be the culprit (the highlight's shadow too), so every one of them had to go, not only the pulse's.

## The fix

`GlassCard` (`Shared/Design/EmpireDesign.swift`), from the bottom up, the old order of drawing kept:
1. the blur with its shadow as part of its style (`Material.ultraThinMaterial.shadow(.drop(…))`, no pass), as dark as
   the blur's and the fill's shadows used to be together outside the card (`CardShadow.outside`: exact where the shadow
   is whole, off by at most a quarter of the two opacities multiplied where it fades). `MaterialShadow` and its mask go;
2. a still image inside the card's outline (`.clipShape` + `drawingGroup`, drawn once): the fill over its shadow, which
   shows through the see-through fill as the card's depth, and the highlight's shadow alone (the highlight in the
   shadow's colour, moved down and blurred as a shadow is);
3. the highlight, its shadow outside the card as part of its style;
4. the content, with no shadow (it used to: a 22 pt blur under every word and chip, never meant). In light mode the
   chips and the selected segment inside cards lose a grey halo; dark mode is unchanged;
5. the edge, its shadow as part of its style.

Tried on the way: a shape style's shadow for the fill too (it is drawn only outside the shape, so the light cards
turned flat white), and one still image with room for the whole shadow (a `List` row cuts off what its content draws
past the row: the listings' shadows ended in a straight line).

Per pulse frame on the simulator now: no shadow, mask or group pass (the blur's own refresh remains, as for any iOS
blur). Tools: `scripts/offscreens/` (from brief 67's), the rule in `CLAUDE.md`.

## Done when

- Before/after screenshots of every app (Arestemis Hunt, Listings, Filter, Settings; Aresium, Aresus, Arestoteles,
  Empire), light and dark: dark unchanged, light only without the content's halos (`build/shots/`, local).
- Arestemis's tests pass; all five apps build.
- Build 5 goes to Patrik's phone; he checks the Hunt tab with the hunt running and a pull to refresh.
