# 200: Selecting calmer, and selecting by sliding a finger, as in Mail

Status: brief
Branch: `claude/200-select-by-sliding` · Worktree: `../empire-ios-200-select-by-sliding` · Built by: a Claude agent (how
selecting moves and feels under the finger; the small model behind the slide) · Simulator: `claude-200` (create it:
iPhone 17, iOS 27.0)

## Goal

Patrik (2026-11-02, build 14 on his iPhone), about selecting payments in a category's month list (brief 82): "selecting
statements is quite bouncy. I think it should be less bouncy. And can we build it like mail so you can basically just
slide your finger up and down and it keeps selecting statements or when going up deselecting them".

Two things, one feel:

1. **Calmer.** Starting selecting, ticking a row and ending it should look settled: the rows slide aside, the circles
   come, and nothing else moves, overshoots or jumps.
2. **Select by sliding**, as Mail does in its Edit mode: a finger that goes down over the rows ticks each row it
   passes; going back up unticks the rows it leaves again; it scrolls the list when the finger nears the top or bottom.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Several payments at once on screen", brief 82; "Several payments at once — data API",
  brief 81; the row swipe, `Screens/RowSwipe.swift`, brief 44/53: a `UIPanGestureRecognizer` subclass inside the scroll
  view, and why a plain recognizer got no moves there; "Nothing that moves sits over or under a pathless shadow"; the
  back swipe, `BackSwipe`, brief 38/47).
- `Model/PaymentSelection.swift`, `Screens/SelectionScreens.swift` (`SelectionMarkLook`, `SelectionHeader`,
  `SelectionBar`), `Screens/PaymentList.swift` (`PaymentRow`), `Screens/DashboardScreens.swift` (the month list:
  `tick`, where selecting starts and ends, the bar's `safeAreaInset`), `Screens/SummedRows.swift` (`SumMotion`).

## Build

1. **Find the bounce first, then remove it.** Patrik could not say which part bounces, so look before changing:
   record the simulator (`xcrun simctl io <udid> recordVideo`, then frames; or a burst of screenshots) while selecting
   starts (the header's circle), while rows are ticked one after the other and with All, and at Done. Measure what
   moves and how far: the rows' slide (today `SumMotion`, a spring without bounce, 0.38 s), the header swapping from the
   list's two-line header (title and "Okt. 2026 · Buchungen") to the selection's one-line header (does the list jump up
   and back?), the bar rising in the bottom inset (does the list's content shift?), the plain button's press highlight,
   the ticked row's background, the count's number change. Say what you found.
   **The aim:** Mail's calm. The rows and circles slide in one short ease-out without overshoot (about 0.25 s; your
   call), nothing else moves: the header keeps its height and place, the list keeps its scroll position and nothing in
   it shifts when the bar comes or goes, a tick changes at once (or with a very short fade), no scale or spring on a
   tick. Reduce Motion: no movement, as today. Leave `SumMotion` itself alone for adding up (Patrik has not asked about
   that); give selecting its own motion if it needs one.
2. **Select by sliding** (only while the list selects; phone mode, as selecting is):
   - **Where a slide starts:** on a row's circle column (the strip at the rows' left the slide made room for; give it
     a comfortable width, at least 44 pt) a drag selects at once, in any direction; elsewhere on a row a vertical drag
     scrolls the list as today. Also start it from a drag that begins **sideways** on a row and then turns up or down
     (as Photos selects; the rows have no swipe while selecting, so sideways is free). Taps still tick one row; the
     header's buttons, the bar and the undo bar keep working; the back swipe still waits while selecting.
   - **What it does** (Mail's and Photos' rule): the first row touched decides: an unticked row means the slide ticks,
     a ticked row means it unticks. Every row between the first row and the finger takes that state; rows the finger
     leaves again on the way back return to the state they had before the slide began. A summed row counts as one row
     (all its payments, `selectionIDs(for:)`); a withdrawal's covered row is passed over (no circle, never ticked).
   - **Near the edges** the list scrolls by itself, faster the closer the finger is to the top or bottom edge of the
     list's visible area, and stops at the list's start and end; the rows coming into view are ticked as they pass under
     the finger.
   - **Feel:** the header's count follows live; a light haptic as each row changes, or none (your call; nothing heavy).
     VoiceOver is unchanged (rows stay selectable one by one; the slide is a shortcut).
   - **Structure:** the rule as a pure, tested model (`PaymentSelection` or a small type beside it: the rows' order,
     the first row and its state, the finger's row; the ticked set out); the gesture in `Screens/` (a recognizer in
     the row swipe's manner if SwiftUI's own gestures fight the scroll view, as they did there); the rows' frames from
     the list's own layout, never guessed from a fixed height (rows differ: summed rows, sums opened elsewhere, a
     second line).
3. **The tour's select step** keeps working (its store, its ring); `TourTests` follow if a word changes.
4. **German** for any new text (`scripts/strings.py`); light, dark and red mode.

## Settled: do not re-open

- Mail's model: the slide ticks or unticks by the first row's state, the way back restores, the edges scroll.
- Selecting stays where it is (a category's month list, the header's circle, the bar's Category and Name).

## Out of scope

- Selecting elsewhere (a name's page, the day's page, search), adding up's motion, the quick sort.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=claude-200'
  -derivedDataPath build/DerivedData` passes, with tests for the slide's rule (ticking down, unticking from a ticked
  row, the way back restoring each row's earlier state, a summed row as one, covered rows passed, the list's start and
  end), and the existing selection tests still passing.
- `scripts/strings.py check`: 0 problems.
- **Real touches** (a temporary UI test in `Aresus/AresusUITests` driving Aresium, deleted after; 3 of 3 runs): a slide
  down the circle column from the first row ticks five rows; sliding back up two rows unticks those two; a slide starting
  on a ticked row unticks; a sideways-then-down slide ticks; a slide held at the bottom edge scrolls and ticks rows that
  came into view; a vertical drag on a row's middle scrolls and ticks nothing; a tap still ticks one row; Done ends
  selecting.
- **Before and after** of the motion: what moved before (numbers from the recording) and that after it only the rows
  slide; a short recording or frame strip of start, ticks and Done saved as `build/200-motion-before.*` and
  `build/200-motion-after.*`.
- Screenshots `build/200-*.png` in German and English, light and dark (red once): selecting with several rows ticked
  by a slide.
- `CLAUDE.md` updated (brief 82's section: the motion and the slide).

## Final message

As in `AGENTS.md`: files changed, the exact test summary (count the "' passed on" and "' failed on" lines), what the
bounce was, the choices you made and why, anything doubtful. Never commit, push or merge: Claude does.
