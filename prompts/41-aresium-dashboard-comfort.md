# 41: Aresium's dashboard: hold a payment to change its category, swipe the banner away, room to tap; Privacy in the app, a question before Log out

Status: running
Branch: `claude/41-dashboard` · Worktree: `../empire-ios-41-dashboard` · Built by: a Claude agent (flow and the feel)

## Goal

Patrik approved the comfort list of brief 38 (2026-10-30, all items). This brief builds the items on Aresium's
dashboard and in the shared Settings; brief 40 runs in parallel in the receipt, cash and file check windows. After this
brief the most common correction (a payment's category) takes one long press, the import banner goes with a swipe,
small controls are easy to hit, Privacy and Imprint open inside the app, and Log out asks first.

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules: Apple's own controls and gestures where they exist; "Languages", with the
  `Shared` table for text in `Shared/`; "Light mode"; "Settings (every app)"; the "Aresium phone mode" entry: Switch and
  "Also the other payments from <shop>?", receipts, the tour)
- `docs/reviews/2026-10-30-swipe-and-comfort.md` → "Aresium": the items below are its "Ways out" rows 2 and 4 and
  "Comfort" 1 and 3; "The other four apps" → Shared 1 is Log out
- The screens: `Screens/DashboardScreens.swift` and the payment lists (rows, receipt rows), `Screens/RecategoriseSheet.swift`
  and how a payment's page opens it (`Screens/TransactionDetailSheet.swift`, `DashboardStore`, `ContentView.swift`),
  `Screens/ImportControls.swift` (the result banner), `Screens/Components.swift` (`ScreenHeader`, `IconButton`), the
  start screen's page dots, `Model/TourModel.swift` (the switch step, `holdsTheScreen`), `Shared/Design/SettingsScreen.swift`
  (About's Privacy and Imprint, Account's Log out), `Shared/Settings/SettingsInfo.swift` (`LegalPage`),
  `Shared/Design/ProvinceLogin.swift` (`LoginScroll`'s "Privacy · Imprint")

## Build

1. **Hold a payment → Change category.** A long press on a payment row (every payment list of the dashboard, both
   modes) shows Apple's context menu with Change category, which opens the same change sheet the payment page's Change
   opens, with the same flow after it (the "Also the other payments from <shop>?" question, learning, the tour's
   `paymentRecategorised`). A receipt or cash entry row offers Edit (the same window its page's Edit opens). Rule: the
   menu offers only what the row's page offers (a payment whose page has no Change gets no Change). In the tour: decide
   by reading `TourModel` (off while it holds the screen, or answering the switch step like the page's Change); say
   which.
2. **Swipe the import banner away.** A swipe down on the result banner does what Dismiss does. Not while Retry and
   Discard are offered (a swipe there would drop the files without a choice). The 4.5 s fade of a success stays.
3. **Room to tap (44 pt).** The banner's Dismiss, Retry, Discard, "What is sent?" and "Not now"; the payment page's
   Change, Edit and Unjoin (Apple's small buttons: make them the regular size); the Expenses/Income page dots; the
   header's arrow, sun and gear (42 pt). Tap areas of at least 44 × 44 pt; the drawn size stays except the payment
   page's buttons. While you are in `TransactionDetailSheet`: its Receipt section's Edit and Unjoin get the busy sign
   brief 40 builds for the receipt page only if it is already in `Shared/`; otherwise leave it and say so.
4. **Privacy and Imprint inside the app** (every app: Settings → About, and `LoginScroll`'s "Privacy · Imprint" on the
   login screens and Aresium's Sign in): open `LegalPage`'s URL in Apple's in-app browser (`SFSafariViewController`,
   with its Done) instead of leaving for Safari. `Shared/` is compiled into the Aresium widget too: keep anything
   unavailable in an extension out of the widget's build, and build it.
5. **Log out asks first** (every app: Settings → Account → Log out). Apple's confirmation (`confirmationDialog` or an
   alert; say which and why) with a short line in the app's language: it logs out of all Ares apps on this iPhone, and
   in Aresium the data on this iPhone stays. Log out (destructive), Cancel. Sample mode as before.

## Settled: do not re-open

- No new looks besides the regular-size buttons on the payment page; the header stays Aresium's own.
- The context menu is Apple's own (`.contextMenu`), with its own lifted preview.

## Out of scope

- The receipt, cash and file check windows and the receipt page (`ReceiptCheckView`, `ReceiptCaptureScreens`,
  `CashScreens`, `FileCheck*`, `ReceiptPageView`): brief 40 runs in parallel there.
- The category picker and its model (brief 39 just changed them).
- Create account's swipe-away (item 11 of Patrik's list): later, with the other apps.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium` passes on your own simulator (`claude-41`,
  commands in `AGENTS.md`), with new tests where there is logic (the menu's items follow the page's; the banner's swipe
  only without Retry and Discard; Log out only after the confirmation).
- The other apps build (`Empire`, `Arestoteles`, `Arestemis`, `Aresus`), since `Shared/` changes.
- `scripts/strings.py check`: 0 problems. Keep the German you fill in also in `build/41-de.json` (the `fill` input), so
  Claude can fill it again if the catalog conflicts with brief 40's at merge.
- Looked at on the simulator in English and German, light and dark: screenshots `build/41-*.png` (the context menu on a
  payment and a receipt row, the change sheet opened from it, the banner mid-swipe if you can, the payment page's
  buttons, Privacy inside the app, the Log out question).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, the choices you made
(tour, confirmation style, Return/Done anywhere you touched), what is missing or doubtful. Never commit, push or merge:
Claude does.
