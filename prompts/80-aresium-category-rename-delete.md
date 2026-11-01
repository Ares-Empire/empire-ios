# 80: A name that exists is used, categories can be renamed and deleted

Status: merged 2026-11-01 (735 Aresium tests; export schema 6, storage V6; German "Die 12 Buchungen darin …" so it fits every category)
Branch: `codex/80-category-rename-delete` · Worktree: `../empire-ios-80-category-rename-delete` · Model: `gpt-6.1-sol`,
effort `high` · Simulator: `codex-80` (create it: iPhone 17, iOS 27.0) · The look is settled below (Apple's alert, menu
and confirmation as the app already uses them); Claude checks the screenshots.

## Goal

Patrik (2026-11-01, on build 10): "In expenses I have the category friends but not in income and I cant add it there
because it tells me it already exists. can we fix that? Also: Lets make categories renamable and deletable. on delete
items that can be resorted get resorted and otherwise not sorted".

Three things:

1. **A name that exists is used, not refused.** Typing "Freunde" as a new category for money in today ends in
   `LedgerError.nameTaken` ("There is already a category with this name."), although Friends is his spending category
   and brief 69/70 let any category be offered on the other side ("Andere Kategorie …", the side line's "Also for money
   in"). He did not find those, and the add said no. After this brief, a typed name that belongs to a category the
   person can have **is that category**: offered on this side if needed, ticked if needed, and picked where a window
   was choosing one.
2. **Rename** every category in the person's list, the defaults too.
3. **Delete** one's own categories, and **remove** a default from the list, with Patrik's rule: its payments are sorted
   again, and those Aresium cannot sort go to Not sorted.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Languages", "Light mode", and in "Aresium phone mode": category sides (briefs 69, 70), New
  category where a category is chosen (brief 60), the category picker, payment names and the sums' keys (brief 53), the
  tour (briefs 59, 77)).
- `Model/PhoneCategories.swift` (`PhoneCategoryList`: `checkedName`, `name(of:)`, `id(named:)`, `offered`),
  `Model/PhoneBackend.swift` (`choose`, `addCustom`, `setSide`, `setOtherSide`, `unchoose`, `sort`),
  `Model/PhoneLedger.swift` (`choose`, `unchoose`, `setOtherSide`, `LedgerError`, the stored chosen category and its
  `customName`), `Model/NewCategory.swift`, `Model/PhoneSettingsModels.swift` (`CategoryPickerModel`: `toggle`,
  `untick`, `addCustom`), `Screens/PhoneScreens.swift` (`CategoryPickerScreen`, its rows' context menu and side line,
  `UntickSheet`), `Screens/NewCategoryPieces.swift`, `Model/LedgerExport.swift`, `Model/TourModel.swift` (the categories
  step's words), and their tests (`CategorySideTests`, `CategorySideScreensTests`, `NewCategoryInChangeTests`,
  `NewCategoryInWindowsTests`, `CategoryCountsTests`, `TourTests`).

## Build

1. **A typed name that exists** (one function for every place that makes a category: Settings → Categories' add row,
   the change window's New category, the receipt window's and Add cash's "New category…"; replaces their
   `addCustom(named:side:)` call): the name is compared as `checkedName` does (case and accents ignored, both
   languages of the defaults, one's own names, renamed names from item 2). It answers what happened:
   - **made**: no category has the name: made as today.
   - **existing**: a chosen category with the name is already offered for this side (its home, its other-side offer,
     or a transfer): nothing changes.
   - **offered**: a chosen category whose home is the other side, not offered here yet (Patrik's Freunde): its
     other-side offer is turned on (`setOtherSide`), as "Andere Kategorie …" saves it.
   - **ticked**: a default not in the list: ticked as a tap in Settings → Categories ticks it (its waiting payments
     sorted), and offered on this side too when its home is the other one.
   - Still refused: the built-ins (Not sorted, Own transfers) and the reserved names, with today's line.
   In a window (change, receipt, cash) every outcome but the refusal picks that category, as a made one is picked
   today. In Settings → Categories the add row clears and says what happened in one quiet line where its problem line
   shows today (not as a problem): "Friends is already in your list." / "Freunde ist schon in deiner Liste.", "Friends
   is now offered for money in too." / "Freunde gibt es jetzt auch für Einnahmen." (out: "… for money out too." / "…
   auch für Ausgaben."), "Friends is ticked." / "Freunde ist angehakt." (with " Also for money in." where it was
   offered too). The name in these lines is the category's as shown, not as typed.
2. **Friends both ways by default:** when the default Friends is ticked (in the picker, after an import, by item 1), it
   is offered for money in too (a friend pays back their share). Existing stores are not changed.
3. **Rename** (phone mode, every chosen category but the built-ins):
   - One's own: its name changes. A default: the person's own name for it is kept with its chosen entry (the stored
     chosen category already has `customName`; if a store change is needed after all, add schema V7 as `CLAUDE.md`
     says, never edit V6). A renamed default shows that name in both languages, until "Use the original name" /
     "Originalnamen verwenden" takes it back.
   - The new name is checked as a new one (`checkedName`), except against the category's own present and original
     names. Empty or only spaces: today's line. The look (icon, colour), side, offer, payments, receipts, cash entries,
     learned rules and the sums' choices (keyed by id, `DashboardStore.sumCategoryKey`) stay with the category.
   - Find everything that keys a category by its shown name (the dashboard is built by name; routes, the widget's
     category links, `id(named:)`, open pages) and make it follow the rename or fall back calmly (a widget link to the
     old name opens the dashboard, not an error). Say in the final message what you found.
   - Export and restore carry a renamed default (raise the export's schema if its meaning changes, keep 1–5
     restorable).
4. **Delete and remove** (Patrik's rule): one's own category is **deleted**; a default is **removed** from the list
   (unticked; it can be ticked again). Both: its payments become Not sorted and are sorted again with the rest of the
   list (learned rules, then the built-in sorting), so those Aresium can sort land in a category and the rest stay Not
   sorted; it leaves every payment's extra categories; receipts and cash entries in it go to Not sorted. Learned rules
   into one's own category go with it; rules into a default stay (they work again if it is ticked again), as `unchoose`
   does today. That is today's untick with "Not sorted" (`unchoose(id, moveTo: nil)` and the sort): reuse it, do not
   copy it. Built-ins cannot be deleted. The tick's own question (`UntickSheet`, moving the payments into one chosen
   category) stays as it is.
5. **On screen** (Settings → Categories, `CategoryPickerScreen`, also the tour's Settings and the picker after an
   import):
   - **The long press** of every ticked row (Apple's context menu; today the side choices for one's own, the offer tick
     for a default, nothing for a transfer) gets, first, **Rename…** / **Umbenennen …** (`pencil`) and, while a default
     is renamed, **Use the original name** (`arrow.uturn.backward`, its original name as the entry's subtitle), then the
     side choices as today, then after a divider **Delete** / **Löschen** (one's own) or **Remove** / **Entfernen** (a
     default), destructive (`trash` / `minus.circle`). A transfer's row gets Rename… and Remove.
   - **Rename…** opens Apple's alert as New category's (`newCategoryAlert`'s pieces: a field, Cancel, the action as a
     plain button in the window's ink, never the system blue): "Rename category" / "Kategorie umbenennen", the field
     holding the current name, the action "Rename" / "Umbenennen", off while the name is empty or unchanged; the
     keyboard's Return renames. A name problem keeps the typed name and shows the picker's problem line.
   - **Delete / Remove** asks with Apple's confirmation dialog (as Settings' Log out: a popover from the row on iOS 26):
     title "Delete Hobby?" / "Hobby löschen?" (Remove: "Remove Friends?" / "Freunde entfernen?"), message "Its 12
     payments are sorted again. Those Aresium can't sort go to Not sorted." / "Seine 12 Buchungen werden neu sortiert.
     Was Aresium nicht sortieren kann, kommt zu Nicht sortiert." (Remove adds "You can tick it again any time." / "Du
     kannst sie jederzeit wieder anhaken."; with no payments only that line, or for Delete none), the destructive
     button with the same word, Cancel. Plurals in the catalog (1 payment / 1 Buchung).
   - The rows, counts and lists follow at once; the dashboard is built again when the picker closes, as a side change.
   - **The tour:** the categories step's card says that holding a category renames or deletes it (both languages;
     keep it one or two lines). `TourTests` follow.
6. **German** for every new text (`scripts/strings.py`), checked on screen.

## Settled: do not re-open

- A typed name that exists means that category; only built-ins and reserved names are refused.
- Delete and Remove sort again, the rest Not sorted; no question where the payments go (the tick's own sheet keeps
  that choice).
- Defaults can be renamed; the original name can be taken back.
- Apple's alert, context menu and confirmation dialog, in the app's ink.

## Out of scope

- Renaming or deleting from the change window's tiles or the dashboard's rows; server mode; the engine.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=codex-80'
  -derivedDataPath build/DerivedData` passes, with new tests: each outcome of item 1 in both languages (case and
  accents ignored; Patrik's case: Friends a spending category, "Freunde" typed for money in in the change window ends
  offered and picked; in Settings the line), refused built-ins, Friends ticked is offered both ways, rename of one's
  own and of a default (both languages, the check against others but not itself, the original name back, everything
  keyed by id kept, the dashboard showing the new name, a language switch keeping it, export and restore), delete and
  remove (a payment the built-in sorting knows is sorted again, an unknown one Not sorted, a manual choice sorted
  again, extra categories and receipts, learned rules as described), the tour's card.
- `scripts/strings.py check`: 0 problems.
- Screenshots `build/80-*.png` (German and English, light and dark once each): the long press of an own row and of a
  renamed default, the rename alert, the delete and remove confirmations, the add row's three lines. DEBUG launch
  arguments for them as earlier briefs did (`-openCategories`, …), listed in `CLAUDE.md`. Context menus need real taps:
  a temporary UI test as brief 70 used, deleted after.
- `CLAUDE.md` updated ("Aresium phone mode": a typed name that exists, rename, delete and remove).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, what keyed a category
by name and what you did about it, your choices and why, anything doubtful. Never commit, push or merge: Claude does.
