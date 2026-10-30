# 40: Aresium's windows: a way to answer later, a way back, Done on the number pad, no silent discards, a sign while it works

Status: running
Branch: `claude/40-sheets` · Worktree: `../empire-ios-40-sheets` · Built by: a Claude agent (flow and the feel)

## Goal

Patrik approved the comfort list of brief 38 (2026-10-30, all items). This brief builds the items in Aresium's windows
(receipts, cash, the file check); brief 41 runs in parallel on the dashboard and the shared Settings. After this brief a
person can put a question off without saying no, undo a No in the file check, close the number pad, never loses typed
text without being asked, and sees that a tapped button is working.

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules: Apple's own controls and gestures where they exist; "Languages": every new
  text in English in the code and German in the catalog; "Light mode"; the "Aresium phone mode" entry: receipts,
  correcting receipts, cash, the unknown bank's file)
- `docs/reviews/2026-10-30-swipe-and-comfort.md` → "Aresium": the items below are its "Ways out" rows 1 and 3 and
  "Comfort" 2, 4 and 5, with what was found
- The screens: `Screens/ReceiptCheckView.swift`, `Screens/ReceiptCaptureScreens.swift`, the receipt question after an
  import (`ReceiptQuestionSheet`, presented from `ContentView.swift`), `Screens/FileCheckSheet.swift`,
  `Screens/FileCheckColumns.swift`, `Model/FileCheck.swift`, `Screens/CashScreens.swift` (`CashEntryView`),
  `Screens/ReceiptPageView.swift` (`ReceiptPageModel`), `Model/ReceiptCheck.swift`, `Model/Cash.swift`

## Build

1. **"Is this the same payment?" gets Later** (both places: the question after a bank import, and the same question
   inside the receipt window after Save). A "Later" button in the sheet's top-left corner (Apple's
   `cancellationAction` place) that does exactly what swipe down does today: the receipt keeps waiting and nothing is
   declined. "None of these" stays as it is (it declines). Several queued questions: Later closes this one as swipe
   down does now; say what happens to the rest.
2. **The file check gets Back** ("Does this look right?" for an unknown bank's file). After No, a Back next to No shows
   the reading before, with its line; on the first reading there is no Back. From the column check (the last resort),
   Back returns to the last reading. Cancel stays as it is.
3. **Done on the number pad and Return that moves on.** The receipt window's Total and Amount in euros, Edit receipt's
   and Add cash's Amount use the number pad, which has no Return: put Done above the keyboard (Apple's keyboard toolbar,
   `ToolbarItemGroup(placement: .keyboard)`), closing it. Shop's Return moves to Total (not closing the keyboard); in
   Add cash, What's Return closes the keyboard. Any other text field in these windows: Return does the next sensible
   thing; say what you chose for each.
4. **No silent discards.** Add cash's Cancel throws away what was typed without asking, while swipe down is held back
   to protect it. A Cancel (or Close) in these windows that would throw away something the person typed or changed, or
   a reading that cannot be had again (the photo is not kept), asks first, like Contact & support's X: "Discard this
   entry?" / "Discard this receipt?" / "Discard your changes?" with Discard (destructive) and Keep editing. Nothing typed
   or changed: Cancel closes at once. Check Add cash, Edit of a cash entry, the receipt window and Edit receipt; say which
   already asked.
5. **A sign while it works.** On a receipt's page (Edit, Change, Unjoin, Delete), in "Join with a payment…" and in the
   receipt question's answers, a tap greys the buttons and nothing else shows. Show a small spinner in the button that
   was tapped (the others stay greyed and untappable as now) until the work ends. One small piece, reused, not one per
   screen; if `Shared/Design` already has a busy button style, use it.

## Settled: do not re-open

- No new looks: Apple's controls, the existing tokens and button styles. No change to what any button does besides the
  above.
- Swipe down on these sheets stays held back where it is held back now.

## Out of scope

- `Screens/TransactionDetailSheet.swift` (a payment's page, including its Receipt section's Edit and Unjoin), the
  dashboard's screens and rows, `Screens/ImportControls.swift` (the result banner), `Screens/Components.swift`
  (the header), `Shared/` except reusing what is there: brief 41 runs in parallel there. If one of your items needs a
  change in them, describe it in your final message.
- The category picker and its model (brief 39 just changed them).

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium` passes on your own simulator (`claude-40`,
  commands in `AGENTS.md`), with new tests where there is logic (the file check's Back over the readings and into and
  out of the column check; "has something to discard" for each window; Later leaves the receipt waiting and declines
  nothing).
- `scripts/strings.py check`: 0 problems. Keep the German you fill in also in `build/40-de.json` (the `fill` input), so
  Claude can fill it again if the catalog conflicts with brief 41's at merge.
- Looked at on the simulator in English and German, light and dark: screenshots `build/40-*.png` (Later in both
  places, Back in the file check, Done above the number pad, a discard question, a spinner in a button: a DEBUG
  argument that holds the work, if there is none).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, the choices you made
(items 1, 3, 4), what is missing or doubtful. Never commit, push or merge: Claude does.
