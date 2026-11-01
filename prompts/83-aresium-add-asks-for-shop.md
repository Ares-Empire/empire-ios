# 83: Adding a category asks about the shop's other payments too

Status: brief
Branch: `codex/83-add-asks-for-shop` · Worktree: `../empire-ios-83-add-asks-for-shop` · Model: `gpt-6.1-sol`, effort
`high` · Simulator: `codex-83` (create it: iPhone 17, iOS 27.0) · Starts after briefs 80 and 81 are merged (branch from
that main).

## Goal

Patrik (2026-11-01, on build 10): "When changing an expenses category via the 'add to' menu it doesnt suggest to move
the other payments too. If I change the category just via change it suggests it but not if I change it via the
multiple selection. it should suggest it there too and change other payments".

In the change window (`RecategoriseSheet`), **Switch** saves and then asks "Also the other payments from <shop>?"
(`MerchantFollowUp`, `TransactionDetailStore.followUp`); **Add** (the extra categories, several can be ticked) saves
with `setTags` and asks nothing. After this brief Add asks too, and its answer changes the shop's other payments.

## Read first

- `AGENTS.md`, `CLAUDE.md` ("Aresium phone mode": the change window and the shop question, extra categories, shop
  identities (brief 54), counting as it happened (brief 71), brief 81's selection API and brief 80's changes).
- `Model/TransactionDetailStore.swift` (`save`, `followUp`, `finish`), `Model/PhoneBackend.swift` (`switchCategory`
  and its `MerchantFollowUp`, `setTags`), `Model/AresiumBackend.swift` (`MerchantFollowUp`),
  `Model/PhoneLedger.swift` (`otherShopPayments`, `setCategory`), brief 81's `Model/BatchChanges.swift` (its
  `addCategory` for a selection, its follow-up and undo), the screens that show the follow-up (the alert after a
  Switch), and their tests.

## Build

1. **Add asks.** After Add saved a change of a bank payment's extra categories, when the payment's shop (its shop
   identity, as the Switch's question uses) has other payments that the change would also change, the window asks,
   in the same alert as after a Switch:
   - categories added: "Also add Clothes to the other 23 payments from Vinted?" / "Kleidung auch zu den anderen 23
     Buchungen von Vinted hinzufügen?" (two or more: "Clothes and Gifts", "Kleidung und Geschenke"; Foundation's list
     format), **All 24** / **Alle 24** and **Only this one** / **Nur diese**;
   - categories taken off: "Also remove Clothes from the other 23 payments from Vinted?" / "Kleidung auch bei den
     anderen 23 Buchungen von Vinted entfernen?", the same two answers;
   - both in one save: one question naming both ("Also add Gifts and remove Clothes for the other 23 payments from
     Vinted?" / "Bei den anderen 23 Buchungen von Vinted auch Geschenke hinzufügen und Kleidung entfernen?").
   The count is the shop's other payments that the answer would change (a category to add that is not already their
   primary or an extra; a category to remove that they carry as an extra), each once; own transfers and structural
   payments never; receipts and cash entries have no extras. None: no question, as today.
2. **All** adds (or removes) those extra categories on each of them, in one ledger job, then one rebuild. It never
   changes their primary category and learns nothing: new payments from the shop do not get the extra category by
   themselves (extras are often about an occasion, a trip, not the shop). **Only this one** keeps today's result.
3. **A selection** (brief 81's `addCategory`): the same, once for all the selection's shops ("Also add Clothes to the
   other 23 payments from these 6 shops?"), and its undo also undoes an applied answer, as brief 81's Switch does.
4. The question's words are built in one place for one payment and a selection (`MerchantFollowUp` gains what was
   added and removed, or a sibling type; the screens show it where they show the Switch's).

## Settled: do not re-open

- Add asks as Switch asks; All changes the shop's other existing payments; nothing is learned for new payments.
- A payment's primary category is never changed by an Add answer.

## Out of scope

- Remembering extras for new payments; the selection's screens (brief 82); server mode.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium -destination 'platform=iOS Simulator,name=codex-83'
  -derivedDataPath build/DerivedData` passes, with new tests: Add with other shop payments asks with the right count
  (already primary, already extra, own transfers and structural ones not counted), All adds to each and changes no
  primary, Only this one changes nothing else, removing asks and removes, added and removed in one save, no question
  without others, a selection's one question and its undo, the words in both languages.
- `scripts/strings.py check`: 0 problems.
- A screenshot `build/83-*.png` of the question after Add (German and English, `-sampleRecategorise add` and a DEBUG
  argument that picks a category, as brief 60's did), listed in `CLAUDE.md`.
- `CLAUDE.md` updated (the change window: Add asks too).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshot's path, anything doubtful.
Never commit, push or merge: Claude does.
