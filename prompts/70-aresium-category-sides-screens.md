# 70: Every category has a side: the screens

Status: draft (starts after brief 69 is merged)
Branch: `claude/70-category-sides` · Worktree: `../empire-ios-70-category-sides` · Built by: a Claude agent (the look
and flow of the change window and Settings → Categories) · Simulator: `claude-70`

## Goal

Patrik (2026-11-01), on the change window and Settings → Categories: one's own categories for income too, the menus
not bloated with categories that cannot fit, and "if category A is on expenses but also has incomes then it should be
addable not just switchable." Briefs 68 (engine) and 69 (data) gave every category a home side and let any category be
offered on the other side too (`otherSide`). This brief draws it:

- The change window offers **New category** for money in too, and **Other category…** to bring in a category of the
  other side (a friend paying back their share → Friends). From then on that category is offered there.
- Settings → Categories shows each own category's side and lets the person switch it; any category offered on the
  other side says so there and can be taken back.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Languages", "Light mode", and in "Aresium phone mode": the change window and New category
  of brief 60, the category picker of brief 27, own categories' looks of brief 36, the tour's switch step of brief 59,
  and the sides as brief 69 wrote them).
- `prompts/69-aresium-category-sides-data.md` and its final message (`codex-runs/69-category-sides.md`): the API.
- `Aresium/Aresium/Screens/RecategoriseSheet.swift`, `Screens/NewCategoryPieces.swift`, `Screens/PhoneScreens.swift`
  (the picker: `CategoryPickerSection`, `CategoryPickerRow`, "Your own" and its `addRow`),
  `Model/TransactionDetailStore.swift`, `Model/PhoneSettingsModels.swift`, `Screens/Components.swift` (`MenuChip`).

## Build

1. **New category for money in.** The tile of brief 60 shows on both sides now (`offersNewCategory`). Nothing else
   about it changes.
2. **Other category…** / **Andere Kategorie …**: a tile in the grid's quiet action style (brief 60's tile: the tiles'
   size, the second ink, the line's thin outline, no category colour), only while `otherSideChoices` is not empty,
   in Switch and Add, phone mode only. A tap shows the other side's categories with their icons and colours, with one
   short line saying what it means for this payment: for money in, that the money counts as paid back and lowers that
   category's spending; for money out, that it counts as given back and lowers that income (your words, plain, the
   app's terms Ausgaben/Einnahmen). Apple's menu is the first thing to try; if the list is long enough to be awkward
   there (money in can list some 30 spending categories), a small sheet with the window's tiles is fine: choose what
   reads best on the phone and say why. Picking one closes it and the category shows in the grid before the action
   tiles, picked (`pickFromOtherSide`); Save stores it as offered here (brief 69 does that).
3. **Taking one back in the window.** A long press on a tile that is offered here only from the other side gives
   Apple's context menu with one entry, "Not for money in" / "Nicht für Geldeingänge" (or "… money out" / "…
   Geldausgänge"; wording yours, short) (`stopOffering`). Such tiles need no mark of their own; if you find one helps
   (it is the only way to know why the long press differs), keep it quiet and tell me.
4. **Settings → Categories** (the picker; also after an import and in the tour's Settings):
   - **Your own, with a side.** Each own category's row says its side quietly (Spending / Income, "Ausgaben" /
     "Einnahmen"), and the side can be switched there (`setSide`). Find the plainest way that fits the picker's rows,
     where a tap already ticks or unticks: a context menu on the row, or the side as a small menu chip on the row, or
     two sections (Your own · Spending, Your own · Income). Say which and why.
   - **Adding one** asks the side with the name: the add row gets a compact choice next to the field (spending first),
     passed to `CategoryPickerModel.addCustom`.
   - **Offered on the other side too:** a row whose category has `otherSide` shows a quiet second line ("Also for
     money in" / "Auch für Geldeingänge", or for money out), and the row's long press (or your side control) can take
     it back and also turn it on (`setOtherSide`), for default and own categories, never for transfers.
5. **The tour:** its switch step and the tour's Settings keep working; no new step. If the tour's Settings shows the
   side on the own categories' rows, the tour's made-up store has none, so nothing changes there.
6. **German** for every new text (`scripts/strings.py`), checked on screen: a label that wraps gets a shorter word.

## Settled: do not re-open

- One home side per category; "Other category…" only offers it on this side too, it never moves its totals.
- A category reaches the other side's menu only by being used there (or by the person in Settings), never by itself.
- Brief 60's New category tile, alert and flow stay as they are, now on both sides.
- Apple's controls (menus, context menus, alerts) over custom ones where they fit.

## Out of scope

- The data and its rules (brief 69), the engine (brief 68), server mode.
- Whether paid-back money also counts as income (Patrik decides separately).

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=claude-70'
  -derivedDataPath build/DerivedData` passes, with tests for what the screens decide (when each tile shows, the menu's
  entries and line, the context menu's entry, the side shown and switched in Settings, the add row's side).
- `scripts/strings.py check`: 0 problems.
- Screenshots `build/70-*.png` in German and English, light and dark (red mode once): the change window for money in
  with New category and Other category; the other side's list open; a category picked from it; the long press's entry;
  the window for money out with an income category from the other side; Settings → Categories with own categories on
  both sides, the side being switched, the add row's choice, a row offered on the other side. DEBUG launch arguments
  for these states as other briefs did, listed in `CLAUDE.md`.
- `CLAUDE.md` updated (the change window's part and the picker's part of "Aresium phone mode").

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, your choices (the
list's form, Settings' side control, any mark on tiles) and why, what is missing or doubtful. Never commit, push or
merge: Claude does.
