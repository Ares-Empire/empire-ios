# 47: The payment's page made simpler (tap the name or the pen), build 4's gaps, and polish from Patrik's phone

Status: draft
Branch: `claude/47-page-polish` · Worktree: `../empire-ios-47-page-polish` · Built by: a Claude agent (the look and the feel)

## Goal

Patrik tested build 4 on his iPhone 17 (2026-10-30 evening): "very nice work", and:

- **C. Renaming is hard to find.** He wants the payment's page cleared up: the name editable where it stands, with a
  small pen next to it (a button too), the Name row and its Rename button gone; the category the same way (the
  category chip leads to the change window, a small pen next to it), the sentence on why it is sorted there and the big
  Change button gone.
- **A. Settings' switches:** in dark mode he could not tell on from off. Cause found: Settings tints its switches
  `Ink.primary`, white in dark, so "on" is a white track under a white knob (`Shared/Design/SettingsScreen.swift:131`;
  Aresium's Lock and Graph switches use `Ink.secondary` instead).
- **B. The "Aresium" screen flashes for a split second when changing settings.** Almost surely the app switcher cover
  (`Shared/Design/PrivacyCover.swift`), shown on `willDeactivate`, which iOS also sends when the app itself shows a
  system prompt (the notification permission, Face ID when turning the lock on, maybe others).
- **E. The back swipe needs the finger to travel about half the screen** on a category's payments (back to the start
  screen) and on the name's page (back to the payments). Both screens have brief 44's row swipe.
- **The gaps Claude listed after build 4** (Patrik: fix them): the Cash page's movement rows have no swipe (and no long
  press, open since brief 41); receipt rows have no "All from" in their long press (the receipt's page has no such
  line); "Use the bank's name" on a payment named through its shop removes the shop's name for all of them.

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules; "Languages"; "Light mode"; "Settings"; "App switcher cover"; the "Aresium
  phone mode" entry: the payment page, brief 43's names API, brief 44's renaming and swipe, "Comfort in the windows")
- `docs/reviews/2026-10-30-aresium-phone-test.md` (the rounds so far), `docs/reviews/2026-10-30-swipe-and-comfort.md`
- `Aresium/Aresium/Screens/TransactionDetailSheet.swift`, `Model/PaymentPage.swift`, `Model/TransactionDetailStore.swift`,
  `Screens/RecategoriseSheet.swift`, `Screens/RenameSheet.swift`, `Model/PaymentRename.swift`, `Model/PaymentNames.swift`,
  `Screens/PaymentList.swift`, `Screens/RowSwipe.swift`, `Screens/NameScreen.swift`, `Screens/CashScreens.swift`,
  `Screens/ReceiptPageView.swift`, `Model/PaymentRows.swift`, `Shared/Design/BackSwipe.swift`,
  `Shared/Design/PrivacyCover.swift`, `Shared/Design/SettingsScreen.swift`, `Shared/AppRoot.swift`.

## Build

1. **The payment's page (C).**
   - The name (the page's title) is editable where it stands: a **tap on the name or on a small pen next to it**
     turns it into a text field with the text selected and the keyboard up. Return or Done saves; then the same
     question as today when it applies ("Also the other N payments from <bank name>?", All N+1 / Only this one; the
     logic in `PaymentRename.swift` stays). A way to cancel that does not lose the old name, and "Use the bank's name"
     while an own name shows (your design: under the field while editing is fine). The bank's name stays small under
     the title. Server mode and Own names off: no pen, no editing.
   - Patrik asked for a **double tap**; Claude chose a single tap on the page (nothing else on the title takes taps, a
     single tap is found without being told, and a double tap still works since its first tap opens the field). On the
     **payment rows** there is no double tap (it would delay every row's tap while iOS waits for a second one): the
     long press keeps Rename. Say so in your final message so Claude can tell Patrik.
   - Remove the Name row and its Rename button (and `RenameSheet` if nothing else needs it; the long press's Rename
     then opens the page with the field ready, or keeps a small sheet: your choice, say which).
   - **Category:** the chip(s) (and a small pen next to them) open the change window; the big Change button goes, and
     the sentence on why it is there (`PaymentWording.categoryReason`) moves into the change window, one quiet line at
     its top, so the reason is not lost. Extra ("tag") categories: tapping them does the same. Server mode: as phone
     mode where the page offers Change today.
   - The pens: SF Symbol `pencil`, small, muted ink, each a real button with a 44 pt tap area and a VoiceOver label
     ("Rename", "Change category").
   - Check the page at the largest text size and in German.
2. **Gaps.**
   - The Cash page's movement rows: the same row behaviour as a month's list (long press with what the row's page
     offers, the left swipe to "All" where a group exists), through `PaymentList.swift`'s shared row if it fits.
   - Receipt and cash entry pages: the "All from <name>" card as on a payment's page when the group has more than this
     one; then their long press offers it too (the rule stays: the menu offers what the page offers).
   - "Use the bank's name" on a payment whose name comes from its shop: offer **Only this one** too, which shows the
     bank's name on this payment while the shop keeps its name (`PaymentNames`: e.g. an own name equal to the bank's
     name, kept for this payment and grouped with the bank's name; your call, tested, export and restore included).
3. **Switches (A).** Every switch in Settings and Aresium's own pages: on and off clearly different in light, dark and
   red mode (the track's on colour must stand apart from the white knob and from the off track). Stay within the design
   rules (ink, or the app's accent; no new colours without a reason; `ares-empire/EMPIRE.md` and `CLAUDE.md`). This is
   `Shared/`: every app gets it; build them all and look at one other app's Settings.
4. **The cover's flash (B).** Find which settings make "Aresium" flash (try each: Messages on with the permission
   prompt, Face ID on, the own code, Appearance, Language with its restart, Privacy/Imprint, Export's share sheet,
   Delete data) and fix each cause. For the app's own system prompts: do not show the cover while a prompt the app
   asked for is up (it still shows for the app switcher, Control Center and the background, as `CLAUDE.md` describes).
   If the language restart is one, make its rebuild not flash the cover or the launch wall. `Shared/`: every app.
5. **The back swipe's distance (E).** Measure, with real touches on the simulator (as brief 44 did, a temporary UI
   test), how far a slow drag must go before letting go goes back, and how short a quick flick can be: on a month's
   payments, on the name's page, on a category's months (no row swipe there), and in Apple's own Settings app on the
   same simulator. If ours needs more than Apple's, find why (brief 44's `RowSwipeRecognizer`, the scroll view, the
   content pop gesture) and fix it; if it is the same, say so with the numbers (iOS goes back at about half the width
   for a slow drag, or on a flick), and do not build a gesture of our own.

## Settled: do not re-open

- No double tap on rows; single tap (and the pen) on the page's name.
- The change window's flow, the rename question and brief 43's data stay; only "Only this one" for the bank's name is
  new.

## Out of scope

- Summing payments of one name inside a list (Patrik's D): waits for his answer on Claude's design.
- Recognising one shop under changing names (Patrik's È): brief 48 changes the engine in parallel (`~/aresium`); do not
  change `merchantKey`, `nameKey` or the grouping.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium` passes on your own simulator (`claude-47`), with
  tests where there is logic (the bank's name for one payment, the menus following the pages, the cover's rule).
- The other apps build (`Shared/` changes): `Empire`, `Arestoteles`, `Arestemis`, `Aresus`.
- `scripts/strings.py check`: 0 problems.
- Screenshots `build/47-*.png` in English and German, light and dark (and red for the switches): the page with the pens,
  the name being edited with the keyboard, the question, the category's change window with the reason line, a Cash row
  mid-swipe, a receipt page's "All from" card, the switches on and off, and the measured numbers for E in your final
  message.
- `CLAUDE.md` updated where these screens and rules are described (the payment page, brief 44's entry, the cover).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, your choices and the
numbers for B and E, what is missing or doubtful. Never commit, push or merge: Claude does.
