# 53: Adding up payments of one name inside a category's list

Status: merged 2026-10-30 (566 Aresium tests pass with briefs 47 and 54; words Add up / Summieren, Separate / Auflösen; the full swipe stays All)
Branch: `claude/53-sums` · Worktree: `../empire-ios-53-sums` · Built by: a Claude agent (the look and the feel)

## Goal

Patrik (2026-10-30, after build 4, his D): "10 Vinted purchases in Clothes in October" are ten rows; he wants them as
one row with the sum and a sign that it is several, and a way back. Claude's design with his additions is agreed
(`docs/reviews/2026-10-30-aresium-phone-test.md` → "Fourth round" → D). His words: "once summed up, zusammenfassen
becomes separate or smth so a user can make it normal again"; "summing up all things autom. can be a settings toggle
that just sums every category and if users select to do it per category they get a little icon at the top of each that
shows if its summed up or not and they can press it to do it"; "cleanly".

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules; "Languages"; "Light mode"; "Settings"; the "Aresium phone mode" entry: brief
  43's names and groups, "Renaming and the name's page" with brief 44's swipe and brief 47's changes, "Comfort on the
  dashboard": the long press and its rule that the menu offers what the page offers)
- `docs/reviews/2026-10-30-aresium-phone-test.md` (the rounds; D's agreed design)
- `Aresium/Aresium/Screens/PaymentList.swift` (`PaymentRow`, shared by a month's list, the name's page and the Cash
  page), `Screens/RowSwipe.swift` (`RowSwipeRule`, `RowSwipeRecognizer`), `Screens/DashboardScreens.swift`
  (`TransactionsScreen`, `DashboardRoute`, `DashboardStack`), `Screens/NameScreen.swift`, `Model/PaymentRows.swift`
  (`PaymentRowAction`, `rowActions(for:)`), `Model/PaymentNames.swift` (`nameKey`, `nameGroups`), `Model/GraphSetting.swift`
  and Settings' Dashboard section in `ContentView.swift` (where Graph is), `Model/TourModel.swift` (the tour's own
  place and store).

## Build

1. **The choices (a model, tested).** Four levels, the more specific wins:
   - **everywhere:** Settings → Dashboard → a switch, "Add up same names" / German your call (short; Patrik's word is
     "zusammenfassen"), with a line saying what it does. Off by default.
   - **a category:** all names in one category (the icon below), overriding everywhere;
   - **a name:** one name in every category (a switch on the name's page), overriding a category's choice;
   - **a name in a category:** the swipe's choice, overriding everything.
   Each level but everywhere is on, off or not set. A tap on a category's icon sets that category to the opposite of
   what it shows and clears the name-in-this-category choices there (so the tap really means "all" or "none"); the name
   page's switch sets the name and clears that name's per-category choices. Keyed by something that survives a language
   restart and a category's shown name changing (not `Transaction.categoryName` if that is translated: find the
   category's stable id) and by `nameKey` (opaque: brief 54 changes how it is built, in parallel; never parse it).
   Stored on the iPhone in Aresium's defaults (`aresium.sums`), not in the export (a view choice, as the graph), deleted
   with Delete data. The tour has its own, empty and in memory: it never reads or changes the person's.
2. **The summed row.** In a category's payment list (a month's payments; Current and Overview), every name with two or
   more payments in that list that is summed shows as one row where its newest payment would be: the name, a small
   stack mark with the count ("10×"), the sum of the rows (net, with the list's sign and colour rules: a refund among
   purchases lowers it). A tap opens it in place, its payments below it, each the usual `PaymentRow` (tap, long press);
   a tap on the summed row closes it. Opening and closing animate with the system's spring, no jump of the rows around
   it (Reduce Motion: no slide). A name with one payment in the list stays a normal row. Totals and the category's
   numbers never change: summing is only how the list shows. Grouping is computed once per list change in the model,
   never per row or per `body`.
3. **The swipe.** On a single payment with a name that has two or more payments in this list: two actions, **sum**
   (the name in this category, every month, remembered) and **All** (the name's page, as today). On a summed row:
   **separate** (Patrik's "make it normal again"; German your call, Patrik said "Auflösen") and All. Words and icons
   your design, short enough for one line in both languages; the full swipe stays All (as in build 4). The rule's
   distances in `RowSwipeRule` for two actions, tested. One row open at a time as today. VoiceOver actions with the
   same names.
4. **The long press** on a summed row: separate and All with this name (the rule stays: the menu offers what the row
   offers). On a single row with a group in the list: sum added.
5. **The category's icon.** At the top of a category's payment list, a small stack icon in the header's style showing
   whether that category is summed (on and off clearly different in light, dark and red mode); a tap sums or separates
   every name there. VoiceOver: a button with its state. Not on the Cash page, the name's page or "Covered" lists.
6. **The name's page:** a switch "in every category" (wording yours), under the totals. It sets the name's choice.
7. **German** for every new text (`scripts/strings.py`).

## Settled: do not re-open

- Four levels, the more specific wins; off by default; the full swipe stays All.
- Display only: no total, export or engine changes.

## Out of scope

- `Model/PaymentNames.swift`'s keys and grouping, `PhoneBackend`, `AresiumEngine`, `Engine/`: brief 54 (Codex) changes
  them in parallel (one shop under changing names). Use `nameKey` as it comes.
- The payment's page.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium` passes on your own simulator (`claude-53`), with
  tests for the choices (each level, precedence, the icon's tap clearing, the name page's switch clearing, a language
  switch keeping them, Delete data clearing, the tour not touching them), the grouping (newest position, net sum, one
  payment stays single, covered rows untouched), the swipe rule with two actions, and the menus.
- `scripts/strings.py check`: 0 problems.
- Screenshots `build/53-*.png` in English and German, light and dark (one in red mode): a list with a summed row closed
  and open, a row mid-swipe with both actions, a summed row's swipe, the long press on a summed row, the category's icon
  on and off, the name page's switch, the Settings switch, the largest text size for the summed row. Sample:
  `-samplePhone -sampleLongName` gives three payments of one name in Clothes this month; add a DEBUG argument for a
  summed state if needed.
- `CLAUDE.md` updated (the "Aresium phone mode" entry, near "Renaming and the name's page").

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, your choices (words,
icons, the summed row's look, the swipe's distances), what is missing or doubtful. Never commit, push or merge: Claude
does.
