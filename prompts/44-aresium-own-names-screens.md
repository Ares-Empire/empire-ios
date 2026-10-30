# 44: Renaming a payment, and all payments of one name (the screens)

Status: draft
Branch: `claude/44-names-screens` · Worktree: `../empire-ios-44-names-screens` · Built by: a Claude agent (the look)

## Goal

Patrik (2026-10-30): people rename payments to names they remember; the bank's name stays small under the own name on
the payment's page; a setting switches between own and bank names; payments of the same name can be added up, reached
by swiping a row (like Mail). He chose: **swipe left only, no direction setting** (a right swipe would take the back
swipe from the middle of the screen). Claude added, and Patrik read it: since a swipe cannot be seen, the payment's page
also gets a visible "All from <name>" line, and the long press gets the same entry.

Brief 43 (merged) built the data: read its API in `CLAUDE.md` → "Aresium phone mode" → "Payment names and groups" and
"Brief 44 API". This brief builds the screens on it, phone mode only (server mode offers no rename).

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules: Apple's own controls and gestures; "Languages"; "Light mode"; "Settings";
  the "Aresium phone mode" entry, with brief 43's API; "Comfort in the windows": `DiscardingCancel`, `whileWorking`)
- `docs/reviews/2026-10-30-swipe-and-comfort.md` (what briefs 38, 40, 41 settled: 44 pt tap areas, the long press)
- `Aresium/Aresium/Screens/TransactionDetailSheet.swift` (the payment's page), `Screens/RecategoriseSheet.swift` and
  `Model/TransactionDetailStore.swift` (Change, Save, "Also the other payments from <shop>?": mirror this flow),
  `Screens/DashboardScreens.swift` (`TransactionsScreen` rows, `menu(for:)`, `DashboardRoute`, `DashboardStack`),
  `Model/PaymentRows.swift` (`PaymentRowAction`, `rowActions(for:)`), `Model/PaymentNames.swift`,
  `Shared/Design/BackSwipe.swift` (the back swipe from anywhere: your row swipe is leftward only, so they never meet),
  `ContentView.swift` (the Settings sheet: `PhoneSettingsSection`).

## Build

1. **The payment's page.** The shown name stays the title; when it is an own name, the bank's name small under it
   (Patrik). A clear way to rename (your design: a pencil next to the name, a Rename button, or a row; Apple-like and
   found without help).
2. **Renaming.** A small sheet: one field with the own name (empty with the bank's name as placeholder when there is
   none), Cancel and Save at the top (the iOS standard), Save off while nothing changed; "Use the bank's name" when an
   own name exists (removes it). Cancel after typing asks first (`DiscardingCancel`). After Save, when
   `canRenameShop` and N > 0, ask as the category change does: "Also the other N payments from <bank name>?" with a
   line that new payments get the name too; answers "All N+1" (the shop) and "Only this one". N = 0 or no merchant key:
   only this payment, no question. Decide sensibly what editing does when the shown name comes from the shop's rule
   vs. the payment alone (`paymentOwnName` / `shopOwnName`), and say what you chose. While it saves: the busy sign
   (`whileWorking`). Errors as the category change shows them.
3. **"All from <name>".** On the payment's page, a line with the name's count and money out (and in, if any), e.g.
   "All from Penny · 23 payments · 412,30 €", opening the name's page. Only when the row has a group
   (`DashboardStore.nameGroup(for:)`), and only when the group has more than this one payment.
4. **The name's page.** Title the name. The totals over all months (out; in only if there is any), the count; the
   months that have payments with their amounts (the dashboard's `ValueRow` bars, newest first or as the category page
   orders months: match it); the payments below, newest first, each opening its page as on a month's list. A graph above
   the months as on a category's page: brief 42 (in parallel) makes the graph a setting and puts a category's graph above
   its months; give the page a `showsGraph` input (default true) that Claude wires to brief 42's setting at merge, and
   draw the graph with the same `SeriesChart` call a category uses. Pushed on the dashboard's stack (a new
   `DashboardRoute` case or field), so the header's arrow and the back swipe work. From the payment's page (a sheet):
   choose between pushing inside the sheet and closing it then pushing on the dashboard; say which and why.
5. **Swipe left on a row** (every payment list of the dashboard, both modes where a group exists; not covered rows):
   the row slides and shows one action, "All from <name>" (an icon and a short label as Mail's), a tap on it opens the
   name's page; a full swipe past a threshold opens it at once, with a haptic as the threshold is crossed. One row open
   at a time; it closes on scroll, on a tap elsewhere and when the page opens. Vertical scrolling must not catch on it
   (start the swipe only for a clearly horizontal drag). VoiceOver: an accessibility action with the same name. Reduce
   Motion: no slide, the action still there. The lists are a `LazyVStack` in a `ScrollView`, not a `List`, so this is
   your own gesture: keep it in one reusable modifier with its threshold logic tested.
6. **Long press** (brief 41's menu): add "Rename" and "All from <name>" where the page offers them
   (`PaymentRowAction`, the rule stays: the menu offers only what the page offers).
7. **Settings:** in Aresium's part (phone mode) a toggle "Own names" (German "Eigene Namen") with a short note that off
   shows the bank's names and keeps your names; it calls `DashboardStore.setOwnNames(_:)`, never the defaults directly.
   Brief 42 adds a Graph toggle in the same section in parallel: keep yours a separate row so the merge stays simple.
8. **German** for every new text (`scripts/strings.py`).

## Settled: do not re-open

- Swipe left only, no direction setting. The page's line and the long press's entry as well as the swipe.
- The bank's name stays what sorting reads; a rename never changes a category.
- Phone mode only; receipts and cash entries keep their Shop (their Edit), and get no Rename.

## Out of scope

- `StartScreen`, `CategoryScreen` and the header (`Components.swift`'s `ScreenHeader`, `ContentView`'s header code),
  the tour's graph step: brief 42 changes them in parallel.
- `Model/` beyond what the screens need (`PaymentRows.swift`'s actions, a route): brief 45 (Codex) runs in parallel on
  Aresium's messages in `Model/` and `ContentView.swift`'s URL routing. If brief 43's API lacks something, describe it
  instead of rebuilding it.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium` passes on your own simulator (`claude-44`,
  commands in `AGENTS.md`), with tests where there is logic (the swipe's threshold and direction; the menu's items
  follow the page's; the question only with N > 0 and a merchant key; the line only for a group of more than one).
- `scripts/strings.py check`: 0 problems.
- Looked at on the simulator (phone sample, `-samplePhone`) in English and German, light and dark: screenshots
  `build/44-*.png` (the page with an own name and the bank's under it, the rename sheet, the question, the page's
  "All from" line, the name's page, a row mid-swipe, the long-press menu, the setting on and off).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, your choices (the
rename control, editing a shop name vs. a payment's, where the name's page opens from the sheet, the swipe's threshold),
what is missing or doubtful. Never commit, push or merge: Claude does.
