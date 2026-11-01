# 83: Add asks: remove from the current category? and the shop's other payments?

Status: brief
Branch: `codex/83-add-asks` · Worktree: `../empire-ios-83-add-asks` · Model: `gpt-6.1-sol`, effort `high` · Simulator:
`codex-83` (create it: iPhone 17, iOS 27.0) · Starts after briefs 80 and 81 are merged (branch from that main); brief
82 (the selection's screens) shows this brief's questions for a selection.

## Goal

Patrik (2026-11-01, on build 10):

- "When changing an expenses category via the 'add to' menu it doesnt suggest to move the other payments too. If I
  change the category just via change it suggests it but not if I change it via the multiple selection. it should
  suggest it there too and change other payments".
- "in the add to menu lets add that when the user selects 'Speichern' it a) suggests moving other payments and b) asks
  if the payment should be removed from the current category. because that button is all the way down and easy to
  miss".

In the change window (`RecategoriseSheet`), **Switch** saves and then asks "Also the other payments from <shop>?"
(`MerchantFollowUp`, `TransactionDetailStore.followUp`). **Add** (extra categories; several can be ticked) saves with
`setTags` and asks nothing; taking the payment out of its current category is a separate quiet button at the very end
of the window, "Save & remove from current" / "Speichern & aus aktueller entfernen", which Patrik missed. After this
brief **Save in Add asks both**, and that button goes.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Aresium phone mode": the change window and the shop question, extra categories, shop
  identities (brief 54), counting as it happened (brief 71), brief 81's selection API and brief 80's changes).
- `Screens/RecategoriseSheet.swift`, `Model/TransactionDetailStore.swift` (`save(dropCurrent:)`, `canRemoveCurrent`,
  `followUp`, `finish`), `Model/PhoneBackend.swift` (`switchCategory` and its `MerchantFollowUp`, `setTags` with
  `dropCurrent`), `Model/AresiumBackend.swift` (`MerchantFollowUp`), `Model/PhoneLedger.swift` (`otherShopPayments`,
  `setCategory`), brief 81's `Model/BatchChanges.swift` (`switchCategory` and `addCategory` for a selection, follow-up,
  undo), the alert after a Switch, and their tests.

## Build

1. **Question 1, after Save in Add: remove from the current category?** Asked when the save adds a category and the
   payment has a current category other than the added ones (`canRemoveCurrent`), Apple's alert, as the Switch's
   question looks: "Also remove from Groceries?" / "Auch aus Lebensmittel entfernen?", the line "Then it counts only
   under Clothes." / "Dann zählt sie nur unter Kleidung." (two or more: "Clothes and Gifts" / "Kleidung und
   Geschenke", Foundation's list format), **Remove** / **Entfernen** and **Keep both** / **Beide behalten**. Remove
   saves as today's "Save & remove from current" (`dropCurrent`: the first added becomes the category, the rest stay
   extras); Keep both as today's Save.
   - A payment that is **Not sorted** is not asked: the first added category becomes its category (as Remove), since
     a payment both Not sorted and in Clothes means nothing.
   - Own transfers are never offered in Add, as today.
   - The quiet button at the window's end goes (the question replaces it); its catalog keys go with it.
2. **Question 2: the shop's other payments.**
   - After **Remove** (or a Not sorted payment's first category) the payment's category changed: it is a Switch, so it
     does exactly what Switch does, learning the shop and asking "Also the other payments from <shop>?" (moving them to
     the new category; the other added categories stay on this payment only). Reuse the Switch's code path, do not copy
     it.
   - After **Keep both**, or a save that only added or took off extras: when the payment's shop (its shop identity, as
     the Switch's question uses) has other payments the change would also change, ask, in the same alert:
     - added: "Also add Clothes to the other 23 payments from Vinted?" / "Kleidung auch zu den anderen 23 Buchungen von
       Vinted hinzufügen?", **All 24** / **Alle 24** and **Only this one** / **Nur diese**;
     - taken off: "Also remove Clothes from the other 23 payments from Vinted?" / "Kleidung auch bei den anderen 23
       Buchungen von Vinted entfernen?";
     - both in one save: one question naming both ("Also add Gifts and remove Clothes for the other 23 payments from
       Vinted?" / "Bei den anderen 23 Buchungen von Vinted auch Geschenke hinzufügen und Kleidung entfernen?").
     The count is the shop's other payments the answer would change (a category to add that is not already their
     primary or an extra; a category to remove that they carry as an extra), each once; own transfers and structural
     payments never; receipts and cash entries have no extras. None: no question.
     **All** adds or removes those extras on each of them in one ledger job, then one rebuild; it never changes their
     primary category and learns nothing (new payments from the shop do not get the extra by themselves: extras are
     often about an occasion, a trip, not the shop). **Only this one** keeps the saved result.
3. **A selection** (brief 81's `addCategory`, Add in the window for several payments): the same two questions, once
   for all. Question 1 names the list's category ("Also remove them from Groceries?" / "Auch aus Lebensmittel
   entfernen?") and is asked when it is the current category of at least one selected payment and not Not sorted;
   Remove makes it a Switch for those (brief 81's `switchCategory`, its learning and its one question for all shops),
   the others get the Add. From Not sorted, Add is a Switch. Question 2 after Keep both as in item 2, for all the
   selection's shops at once ("Also add Clothes to the other 23 payments from these 6 shops?"). The selection's undo
   also undoes an applied answer, as brief 81's Switch does.
4. The questions' words are built in one place for one payment and a selection (`MerchantFollowUp` gains what was added
   and removed, or a sibling type; question 1 a small value of its own), so brief 82's screens show them as the single
   window does.

## Settled: do not re-open

- Save in Add asks: first remove from the current category (not for Not sorted), then the shop's other payments.
- Remove means a Switch, with the Switch's learning and question; the bottom button goes.
- An Add answer never changes another payment's primary category and learns nothing for new payments.

## Out of scope

- Remembering extras for new payments; the selection's screens (brief 82); server mode.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=codex-83'
  -derivedDataPath build/DerivedData` passes, with new tests: question 1 asked and not asked (Not sorted, nothing
  added, only the current), Remove behaving as a Switch (learning, its question, its follow-up applied), Keep both then
  the Add question with the right count (already primary, already extra, own transfers and structural ones not
  counted), All adds to each and changes no primary, Only this one changes nothing else, removing an extra asks and
  removes, added and removed in one save, no question without others, a selection's questions and its undo, the words
  in both languages, the bottom button gone.
- `scripts/strings.py check`: 0 problems.
- Screenshots `build/83-*.png` (German and English): question 1 and the Add question (`-sampleRecategorise add` and a
  DEBUG argument that ticks a category and taps Save, as brief 60's did), listed in `CLAUDE.md`.
- `CLAUDE.md` updated (the change window: Save in Add asks).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, anything doubtful.
Never commit, push or merge: Claude does.
