# Swipe back, ways out and comfort (2026-10-30)

Patrik's phone test of build 2 (`2026-10-30-aresium-phone-test.md`, second round, findings 9 and 10): on the dashboard a
swipe to the right did not go back, only the arrow did, and he asked which other screens should get the usual gesture,
plus other comfort gaps, to choose from. Brief 38 built the swipe on Aresium's dashboard; the rest of this page is a
list to choose from. Nothing in the lists is built yet. Sizes: S = under an hour, M = a few hours, L = a day or more.

## Aresium

### Built: the back swipe on the dashboard (brief 38)

On every dashboard screen with a back arrow (a category's months, a month's payments, the Cash pages; server and phone
mode), a swipe to the right now goes back: from the left edge, or from anywhere on the screen as iOS 26 allows, with
the iPhone's own animation; half a swipe let go stays where it was. It does exactly what the arrow does, and there is
no swipe where there is no arrow (the start screen keeps its sideways swipe between Expenses and Income). In the tour
it is off while the tour points at something, because the arrow takes no taps then either. Checked on the simulator
(below); **to check on the phone:** Expenses → Groceries → back by swipe, from the edge and from the middle; a half
swipe let go; the graph still opens a month with a tap.

How it was checked: a temporary UI test drove Aresium on the simulator (iOS 27.0): Overview → Groceries → October and
back twice (from the edge, then from the middle), the same tapped in, phone mode, a half swipe let go (still on
October), the graph's tap after the swipe, the start screen's sideways swipe both ways, no swipe on the start screen,
the tour (step 6: no swipe; step 2: a category opened on the side goes back, the step stays). Mid-swipe:
`build/38-swipe.png`.

### Ways out: the gaps

What a person would try and what happens now. The usual gesture: back swipe for a pushed screen, swipe down for a
sheet.

| Screen | How you leave now | What is missing | Fix | Size |
|---|---|---|---|---|
| "Is this the same payment?" after a bank import, and inside the receipt window after saving a receipt | Pick a payment, "None of these" at the very end of the list, or swipe down | No button to answer later: someone who does not know the swipe scrolls to "None of these", which declines the payments rather than putting the question off | "Later" at the top left, doing what swipe down does (the receipt waits) | S |
| Import result banner (bottom of the dashboard) | Dismiss, Retry or Discard (small words); a success goes by itself after 4.5 s, a failure stays | No swipe to put it away, as with a notification | Swipe down on it does what Dismiss does (not while Retry and Discard are offered: that would drop the files) | S |
| "Does this look right?" (an unknown bank's file) | Yes, import, or Cancel; No shows the next reading | No way back to the reading before after tapping No by mistake | A Back next to No | S |
| Settings → Privacy, Imprint | They open Safari: you leave Aresium and come back with the iPhone's "◀ Aresium" corner | Leaving the app for a page you only want to glance at | Show them inside the app (Apple's in-app browser with Done) | S |

### Ways out: fine as they are

- **Back swipe and swipe down work:** Settings and every page in it (Language, Appearance, Fonts & licences, Lock, Own
  code, Categories, Receipts, the bank guide), the bank guide sheet and a bank's page, a payment's page, a receipt's or
  cash entry's page and the pages in it (Join with a payment, Paid from), Covered by receipts, "What is sent?", the
  category picker after an import (closing it still sorts), the untick question, the tour's Settings.
- **Swipe down held back on purpose:** the change sheet while it saves or asks "Also the other payments?"; the receipt
  window while you check what was read (the photo is not kept, so the reading would be lost); Edit receipt; Add cash
  while something is typed; the file check (it needs Yes or Cancel); Contact & support with an unsent message (its X
  asks first) or while sending; Sign in and Forgot password while they talk to the server; the account pages (change
  password, leave, delete) and the own-code entry hide their back button while they work.
- **No gesture by design:** the scanner (Apple's own, with its Cancel); the lock screen (code or Face ID only); the
  tour's dashboard while the tour points at something (End tour is always on the card).

### Comfort

Ranked by how often someone would hit it. Each: the screen, what is wrong, the fix, the size.

1. **Payment rows: no long press.** Changing a payment's category, the most common correction, takes four steps (tap
   the row, Change, pick, Save). *Fix:* a long press on a payment row offers Change category (and on a receipt row,
   Edit), straight to the picker. M
2. **Number fields have no Done.** Total and Amount in euros (receipt window) and Amount (Add cash) use the number
   pad, which has no Return key; the keyboard goes only when you scroll. The receipt's Shop closes the keyboard on
   Return instead of going on to the next field. *Fix:* Done above the number pad; Shop's Return moves on. S
3. **Small things to hit.** The import banner's Dismiss, Retry, Discard, "What is sent?" and "Not now" are bare 13 pt
   words, about 16 pt tall; the payment page's Change, Edit and Unjoin are Apple's small buttons (about 28 pt); the
   Expenses/Income dots are 30 × 24 pt; the header's arrow, sun and gear 42 pt. Apple's minimum is 44 pt. *Fix:* 44 pt
   tap areas (the drawn size can stay) and the regular button size on the payment page. S
4. **Add cash's Cancel throws away what was typed without asking,** while swipe down is held back exactly to protect
   it (Contact & support's X asks first). *Fix:* "Discard this entry?" when something was typed. S
5. **Some waits show only as greyed buttons:** on a receipt's page (Edit, Change, Unjoin, Delete), the join list and
   the receipt question's answers, a tap greys the buttons with no spinner, so on a slow moment it looks as if nothing
   happened. *Fix:* a small spinner in the tapped button while it works. S

Already fine: a tap on the status bar scrolls the start screen back to the top (tried on the simulator); pull to
refresh on every dashboard list; the sideways swipe between Expenses and Income; the keyboard's Return in Sign in,
Change password, Create account and the bank's name sends or moves on. Left out on purpose: the category picker's
waits (brief 39 is changing it; check after that).

## The other four apps (read-only audit, 2026-10-30)

**Ways out: no gaps.** In Empire, Arestemis, Aresus and Arestoteles every pushed screen shows the system's navigation
bar (the bar is hidden only on the tab roots, which have nothing to go back to), so the back swipe works everywhere;
checked on the simulator with a scratch UI test in Aresus. The shared back-swipe piece is not needed there today.
The shared account pages, Contact & support and Create account behave right on swipe down, except item 2 below.

### Shared (every app)

1. **Log out without asking.** Settings → Account → Log out logs out of all Ares apps on this iPhone at once, with no
   confirmation (`Shared/Design/SettingsScreen.swift:263–273`). *Fix:* "Log out of all Ares apps?" first. S
2. **Create account loses what was typed.** Swiping the Create account sheet away throws away the typed email,
   password and name; after "Confirm your email" swiping away leaves the email out of the login field
   (`Shared/Design/AccountSheets.swift:140–147, :265`). *Fix:* hold swipe down while something is typed (as Contact &
   support does); carry the email into the login field after the confirm step. S

### Empire

1. **Approvals can't be refreshed.** No pull to refresh; on a failed load it says "Pending accounts could not be
   loaded." with no Try again (`Empire/Empire/Screens/EmpireSheets.swift:29, :452–453`). *Fix:* pull to refresh and a
   Try again button. S

### Arestemis

1. **Dismiss has no undo.** On Listings a full swipe left dismisses a listing at once, and dismissed listings appear
   nowhere afterwards (`ListingsScreen.swift:87–92`, `MatchDetailScreen.swift:122, :135`). *Fix:* an Undo for a few
   seconds, or a Dismissed filter. S
2. **Hunt → Latest rows have no actions.** Unlike Listings, they have no swipe and no long press
   (`HuntScreen.swift:116–121`). *Fix:* the same swipe and long-press actions as Listings. S
3. **Search: easy to lose edits.** Save is only at the end of a long form; leaving the tab shows no sign of unsaved
   changes, and closing the app loses them (`SearchScreen.swift:12, :25, :328–352`). *Fix:* Save in the header while
   something changed, and keep the draft. S–M
4. **Tiny chip buttons.** The × and + on city and area chips are 22 × 22 pt (`Style.swift:126–129`,
   `SearchScreen.swift:183–186`). *Fix:* 44 pt tap areas. S
5. **Listings stop at "Show older".** The list ends at a button instead of loading on as you scroll
   (`ListingsScreen.swift:96–101`). *Fix:* load the next page when the end comes into view. S
6. **Add place: the keyboard's Search does nothing useful.** It only closes the keyboard (`SearchScreen.swift:473`).
   *Fix:* it adds the first suggestion, or searches. S
7. **Match page: "More" is a small text button** (`MatchDetailScreen.swift:221`). *Fix:* a regular-size button. S

### Aresus

1. **Run report has no close button.** The run sheet closes only by pulling down, and a pull first scrolls the log
   (`AresusTabs.swift:25–31`, `RunSheet.swift:14–38`). *Fix:* Done in the sheet's top corner. S
2. **Province page: no way to open the province.** It shows the status but no link to its website or app
   (`ProvinceDetailScreen.swift:62–78`). *Fix:* an Open row. S
3. **Aresync tab has no Settings gear,** unlike the Aresus tab (`SyncScreen.swift:13`). *Fix:* the same gear. S

### Arestoteles

1. **Sheets lose typed text.** Quick note, Edit passage, Reword, Change my view and Add a position close on swipe down
   or Close and throw away the text without asking; Edit text does it right
   (`Sheets.swift:25, :286–335, :392–455, :532, :545`; the right example `:163, :177`). *Fix:* as Edit text: ask
   before discarding. S
2. **Note pages hide the tab bar,** so after following links several notes deep there is no tap on the tab to jump
   back (`NoteScreen.swift:24`). *Fix:* keep the tab bar on note pages. S
3. **"Add a position" only at the end of the list** (`PositionsScreen.swift:51–57`). *Fix:* a + in the header. S
4. **To discuss → Done has no undo.** It marks the item done at once (`Sheets.swift:374`). *Fix:* an Undo for a few
   seconds. S
