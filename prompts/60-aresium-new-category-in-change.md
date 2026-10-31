# 60: A new category straight from the change window

Status: merged 2026-10-31 (all 632 Aresium tests pass; the change window's tile for money out only, a new category being a spending one until money in lands in it; the receipt and cash menus too; one shared NewCategoryModel; Create a plain button, so Return on an empty field closes the alert)
Branch: `claude/60-new-category` · Worktree: `../empire-ios-60-new-category` · Built by: a Claude agent (a screen's
look and flow) · Simulator: `claude-60`

## Goal

Patrik (2026-10-31, after build 7): "In the category change screen there should be a way to add a new category because
otherwise you have to leave, create it, come back." After this brief, the change window (a payment's category chip or
pen, or a row's long press → Change category) offers **New category**. The person types a name and the new category is
made, shows among the choices and is picked. Save then moves (or adds) the payment as with any other category.

## Read first

- `AGENTS.md`, `CLAUDE.md`: "Languages", "Light mode", and in the "Aresium phone mode" entry: own categories' looks
  (brief 36, `Model/OwnCategoryLook.swift`), the category picker (brief 27, `CategoryPickerModel`), the payment page and
  the change window (briefs 28, 41, 47), the tour's switch step (brief 59).
- `Aresium/Aresium/Screens/RecategoriseSheet.swift` (the window), `Model/TransactionDetailStore.swift` (`choices`,
  `select`, `save`, the shop question `followUp`), `Model/PhoneBackend.swift` (`addCustom(named:)`),
  `Model/PhoneCategories.swift` (`checkedName`: empty, taken, reserved names), `Model/PhoneSettingsModels.swift`
  (Settings → Categories' own field and how it shows a name problem), `AresiumShared/Dashboard.swift`
  (`recategorisationChoices(amount:)`, the dashboard's `pick` lists).

## Build

1. **The tile:** the last item of the window's grid is a tile, **New category** / **Neue Kategorie** with a `plus`
   symbol, the same size as the category tiles. It is quiet: muted ink, a thin outline in the line colour, no category
   colour, so it reads as an action rather than a category. It shows in both modes (Switch / Verschieben and Add /
   Hinzufügen), in phone mode only.
2. **Typing the name:** a tap opens Apple's alert with a text field: title "New category" / "Neue Kategorie", the field
   empty with the placeholder "Name", **Cancel** and **Create** / **Anlegen**. Create stays off while the field is empty
   (after trimming). The keyboard's Return creates too.
3. **Making it:** Create goes through the same path as Settings → Categories (`PhoneBackend.addCustom(named:)`: the
   same name check, the icon and colour from brief 36, ticked). It never copies that logic. While it is being made, the
   tile shows the app's busy sign (`BusyLabel`) and the other tiles are greyed, as elsewhere.
4. **After making it:** the new category shows in the grid, before the tile, with its icon and colour, and is
   **picked**: in Switch the target, in Add one of the extras. Save is then on. Nothing about the payment is saved before
   Save. After a Switch, the shop question follows as for any category ("Also the other payments from …?"), so the shop
   can learn the new category.
5. **A name problem** (empty, already taken by any category in either language, a reserved name like "Bargeld"): no
   category is made. One line under the grid in the window's error style says why, using the words Settings →
   Categories uses for the same problem (reuse them, no new wording). The next tap on the tile opens the alert with the
   typed name kept, so it can be corrected.
6. **Cancel after making one:** the category stays (it exists in Settings → Categories like any own category and can
   be removed there); only the payment's change is dropped.
7. **Which side:** find out how the dashboard's `pick.spend` / `pick.income` treat own categories (money out and money
   in). Show the tile only in a window whose list can hold an own category, and make sure the category made there shows
   in that same window right away (the window's `choices` read the dashboard, which must be rebuilt or updated so the
   new one is in it before it is picked). If own categories cannot be a target for money in today, there is no tile for
   money in: say so in your final message rather than changing the engine.
8. **The tour:** its switch step uses this window on the tour's own store. The tile may stay there; a category made in
   the tour goes with the tour's store and never reaches the person's. The step still goes on when the payment is moved.
9. **German** for every new text (`scripts/strings.py`).
10. **The receipt window and Add cash too** (Patrik, 2026-10-31, added while the build ran: "yes lets do that too, seems
    sensible"). The receipt check window (new reading and Edit receipt, `ReceiptCheckView`) and the cash entry window
    (Add cash and Edit entry, `CashEntryView`) pick their category from a `MenuChip` menu. That menu ends with **New
    category…** / **Neue Kategorie …** (a `plus` symbol, after a divider). It opens the same alert, makes the category
    the same way and picks it in that window. A name problem shows as one line under the category field in the window's
    own problem style. Nothing else in those windows changes: their Cancel still asks before throwing away typed values,
    and a category made there stays after Cancel, as in item 6. In Add cash an own category shows for spent and for
    received alike (`CashCategories`: one's own may be either), so the item is in both.
11. **One piece for all three places.** The alert, the busy state, the name check's line and keeping the typed name
    live in one shared piece (for example a small model plus a view modifier), used by the change window, the receipt
    window and the cash window. No copy of the flow in a second or third place.

## Settled: do not re-open

- Apple's alert with a text field, not a new sheet or an inline field: it is the iOS way, and it keeps the grid as it is.
- The new category is picked at once. Making one and then having to find and tap it again would be the old detour in
  a smaller form.
- The window's other parts (Cancel and Save in the bar, the segmented Switch/Add, "Currently in" and its reason line, the
  shop question) stay as they are.

## Out of scope

- Server mode (no own categories there) and the server sample.
- Editing or deleting categories from this window.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=claude-60'
  -derivedDataPath build/DerivedData` passes, with new tests: the category is made through `addCustom` and picked in
  Switch and in Add, Save moves the payment there and the shop question follows; a taken or reserved name makes nothing
  and keeps the typed name; Cancel after making keeps the category and leaves the payment where it was; no tile in
  server mode; on the side without own categories (if there is one) no tile; in the tour the person's store is untouched.
  The receipt and cash windows: New category… in the menu makes the category and picks it; their Cancel keeps it.
- `scripts/strings.py check`: 0 problems.
- Screenshots `build/60-*.png` in German and English, light and dark: the window with the tile (Switch and Add), the
  alert with a typed name, the new category picked, the name problem line, the payment's page after Save with the new
  chip; the receipt window's and Add cash's menu with New category… and a category made there picked. Add DEBUG launch arguments for these states as other briefs did, and list them in `CLAUDE.md`.
- `CLAUDE.md` updated (the change window's part of "Aresium phone mode").

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, your choices, the
answer to item 7 (which sides show the tile), what is missing or doubtful. Never commit, push or merge: Claude does.
