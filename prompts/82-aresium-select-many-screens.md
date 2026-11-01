# 82: Several payments changed at once: the screens

Status: merged 2026-11-01 (765 Aresium tests; real touches 4 of 4; the tour has 20 steps)
Branch: `claude/82-select-many` · Worktree: `../empire-ios-82-select-many` · Built by: a Claude agent (the look and
flow) · Simulator: `claude-82` (create it: iPhone 17, iOS 27.0)

## Goal

Patrik (2026-11-01, on build 10): "lets make expenses / incomes selectable and then moveable / changable at the same
time. so e.g. Im in not sorted and select 10 expenses to move them into a different category at the same time or give
all expenses the same name or smth like that. I think we add a small icon when inside a category that shifts
statements slightly to the right and shows circles to tick like in Mail when selecting mails".

Brief 81 built the data (`DashboardStore`: what can be selected, switch, add a category, one name, the follow-up
question, undo); its API is in `CLAUDE.md` ("Aresium phone mode") and Codex's final message
(`codex-runs/81-select-many-data.md`). Briefs 80 and 83 are merged before you start: brief 80 made a typed category name that exists into
that category and added Rename and Delete to Settings → Categories; brief 83 made Save in Add ask "Also remove from <current>?" and about the shop's other payments, for one payment and (as an API) for a selection. This brief draws the selection.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Languages", "Light mode", and in "Aresium phone mode": the header (`ScreenHeader`,
  `HeaderButtonLook`, brief 56), a category's month list and its rows (`PaymentList`, `PaymentRow`, the swipe, the long
  press, summed rows and their motion `SumMotion`, brief 53), the change window (`RecategoriseSheet`, briefs 47, 60, 70,
  80), renaming and its question (`RenamePlan`, brief 47), the undo bar (`Shared/Design/UndoBar.swift`), the tour
  (briefs 59, 77)).
- Brief 81's API and tests, `Screens/PaymentList.swift`, `Screens/SummedRows.swift`, `Screens/DashboardScreens.swift`,
  `Screens/RecategoriseSheet.swift`, `Screens/NewCategoryPieces.swift`, `Model/TourModel.swift`,
  `Screens/TourScreens.swift`. Mail's own selection on iOS 26/27 is the model for the feel.

## Build

1. **The icon.** On a category's month list (Current and Overview, Not sorted included; phone mode, while
   `offersSelection`), a select button in the header's row of buttons (`HeaderButtonLook`, `checkmark.circle`, before
   the icon of adding up; VoiceOver "Select" / "Auswählen"). Nowhere else.
2. **Selecting, as Mail does.** A tap on the icon turns the list into selection: the rows slide a little to the right
   (about the width of a circle and its gap) and an empty circle appears at each selectable row's left edge; a tap
   anywhere on a row ticks or unticks it (the circle fills in the app's ink with a tick, the row lightly highlighted).
   The rows' own tap, long press and swipe are off while selecting; the list scrolls as usual. A summed row has one
   circle and stands for its payments (closed while selecting); a withdrawal's covered row has no circle. The motion
   is the list's own (`SumMotion`'s spring, no bounce; Reduce Motion: none).
   - **The header while selecting:** the count as the title ("3 selected" / "3 ausgewählt", "Select payments" /
     "Buchungen auswählen" at 0), "All" / "Alle" on the left (then "None" / "Keine"), "Done" / "Fertig" on the right
     (ends selecting, nothing changed). The back arrow, the back swipe and the gear wait until it ends.
   - **The bar:** at the bottom, as Mail's toolbar, in the app's own card look (`palette.card`, the line, the safe
     area): **Category** / **Kategorie** (`square.grid.2x2`) and **Name** / **Name** (`pencil`), each with its word
     under the symbol; off at 0 selected; Name off while no bank payment is selected (receipts and cash keep their
     typed Shop). It rises as selecting starts and goes with it.
3. **Category** opens the change window (`RecategoriseSheet`) for the selection: its title names the selection ("10
   payments" / "10 Buchungen", their total under it as the single payment's amount shows), the choices
   `offeredCategories`, its Switch and Add as for one payment ("Add" adds the category to every selected payment), the
   tiles "Andere Kategorie …" and New category working as they do for one payment. Make `RecategoriseSheet` serve one
   payment and a selection from one view (a small protocol or model it reads), never a copy. Save does brief 81's
   switch, or for Add brief 83's questions (merged before you start; `CLAUDE.md` → "Save in Add asks" and "Selection
   window API for Add": `prepareAddCategories`, its `RemoveCurrentQuestion` "Also remove them from Groceries?", then
   `save(removeCurrent:)`), shown with the same alert pieces the single window uses (brief 83's `RecategoriseSheet`
   presenter); then the follow-up question, if any, as the single window asks it (its `wording`: one shop "Also the
   other 23 payments from REWE?", several "Also the other 23 payments from these 6 shops?"; **All 33** / **Only these
   10**).
4. **Name** opens Apple's alert as New category's (`newCategoryAlert`'s pieces): "Name for 10 payments" / "Name für 10
   Buchungen", the field empty (or the name all of them show, when they share one), the action "Rename" /
   "Umbenennen" as a plain button in the window's ink; then, when the shops have other payments (`renameInfo`), the
   single rename's question for all of them ("Also the other 14 payments from these 3 shops?", **All 24** / **Only
   these 10**).
5. **After an action** selecting ends, the list shows the store as it is now (rows moved out leave it, as after a
   single Switch), and the undo bar (`UndoBar`) says what happened in brief 81's words ("10 payments moved to
   Groceries", "Name given to 10 payments", with "2 receipts kept their shop" when any) with **Undo**, which calls the
   result's undo; when the undo is refused, its line says so.
6. **The tour** (brief 59: it explains everything): one step in a category's month list for the select icon, in the
   order the screen is walked (near the adding up steps), the ring on the icon, a card in the tour's words ("Tap to
   select several payments and move or rename them at once." / "Tippe hier, um mehrere Buchungen auszuwählen und auf
   einmal zu verschieben oder umzubenennen."), Next; selecting works on the tour's store if the person tries it.
   `TourTests` follow (20 steps, 19 without the graph).
7. **German** for every new text (`scripts/strings.py`), checked on screen; light, dark and red mode.

## Settled: do not re-open

- Mail's way: an icon, rows sliding right, circles, a tap ticks; a bar at the bottom.
- One window for one payment and for a selection; the same questions as for one payment, asked once.
- After an action selecting ends, with an undo.

## Out of scope

- The data (brief 81); selecting on the day's page, a name's page, the search or the Cash page.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=claude-82'
  -derivedDataPath build/DerivedData` passes, with tests for what the screens decide (the icon only where selecting is
  offered, the header's words and the bar's states, a summed row ticking its payments, the window's title for a
  selection, the questions' words in both languages, the tour's step).
- `scripts/strings.py check`: 0 problems.
- Real touches (a temporary UI test, deleted after): the icon starts selecting, a tap ticks and unticks, All and None,
  Done ends it, Category → a tile → Save moves the rows out of Not sorted and the undo puts them back, Name → the alert
  → the question → the names change, the scroll still works while selecting.
- Screenshots `build/82-*.png` in German and English, light and dark (red mode once): the list selecting with some
  ticked, the bar, the window for a selection, the question, the rename alert, the undo bar, the tour's step. DEBUG
  launch arguments for these states as other briefs did, listed in `CLAUDE.md`.
- `CLAUDE.md` updated.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, your choices and why,
what is missing or doubtful. Never commit, push or merge: Claude does.
