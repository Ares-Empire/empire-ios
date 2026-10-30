# 35: Nothing counted twice, a quick category picker, corrections that survive an engine update

Status: running
Branch: `codex/35-counting` · Worktree: `../empire-ios-35-counting` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Patrik's first test of Aresium's phone mode (2026-10-30, `docs/reviews/2026-10-30-aresium-phone-test.md`, findings 1
and 3; read it) found a payment counted twice and a slow category picker. After this brief: no path in phone mode
counts a payment twice (each path has a test), several categories can be ticked in quick succession, and the person's
corrections keep working after the engine changes how it names merchants (brief 34 changes it in parallel).

## Read first

- `AGENTS.md`, `CLAUDE.md` (the "Aresium phone mode" entry and its parts on receipts and cash)
- `Aresium/Aresium/Model/PhoneBackend.swift` (`switchCategory`, `otherPayments`, `choose`, `unchoose`, `sort`,
  `categoryCounts`), `Model/PhoneLedger.swift` (`CategorySource`, `keeps`, `move`, `applySort`, `remember`, `learned`),
  `Model/PhoneSettingsModels.swift` (`CategoryPickerModel`: `toggle`, `work`, `isWorking`),
  `Screens/PhoneScreens.swift` (`CategoryPickerScreen.row`: `.disabled(model.isWorking)`), the phone-mode tests in
  `Aresium/AresiumTests/` (how they build a backend over a store in memory with the bundled engine).
- The engine's rules for own transfers and PayPal: `~/aresium/src/engine/sorting/transfers.ts`,
  `~/aresium/src/engine/paypal.ts` (read only; the engine is not changed here).

## Build

1. **The bug: "also move the N others" moves own transfers.** After a Switch, `otherPayments` offers every payment
   with the same merchant key that was not set by hand or by a receipt. The bank's PayPal line ("PayPal Europe … Ihr
   Einkauf bei La Pizzetta") and PayPal's top-up ("Bankgutschrift auf PayPal-Konto") carry the shop's name, so they
   share the purchase's key (`la pizzetta`) and leave Own transfers: the amount shows twice until the next sort.
   **Fix:** a payment whose category source is `structural` is never offered by `otherPayments` and never moved by
   `PhoneLedger.move` (a Switch by hand on that one payment stays possible). Test with the triple: purchase −107.69 and
   top-up +107.69 in a PayPal file, the bank line −107.69 a day later (made-up shop name); Switch the purchase, accept
   the follow-up: the dashboard's spending counts 107.69 once, both other rows stay Own transfers.
2. **Every other way a payment could count twice: one test each, a fix where the app is at fault.** Build each case
   from made-up files through the same calls the app makes (import, sort, Switch, follow-up, tick/untick, receipts,
   cash) and check the dashboard's spending and income totals and the Not sorted count:
   - the same file imported twice; two exports of one bank whose months overlap; a VR Bank CSV and a CAMT file of the
     same account and days (if the engine gives the same payment two ids across formats, do not invent a fuzzy
     match: report it with the numbers, Claude decides);
   - two PayPal exports that overlap; the PayPal file imported before the bank file, and after it;
   - an extra category added with Add (counts once in the totals);
   - a card receipt joined to its bank payment; a cash receipt covered by a withdrawal; a hand cash entry;
   - unticking a category and moving its payments to another one;
   - a transfer between two of the person's own accounts, both imported.
   A case that double counts because of the engine: report it (file, numbers), do not change the engine.
3. **The picker is quick.** Today every tap saves, sorts all payments, refreshes, then sorts once more for the counts,
   and every row is disabled meanwhile. **New:** a tick or untick shows at once and the rows stay tappable (remove the
   row's `.disabled`; keep `isWorking` only where a second action really must wait, such as Add). The ledger change
   (choose, unchoose) happens per tap; the sort and the counts run once, after the taps stop for about half a second
   (cancel and restart the wait on each tap), and before the picker closes (Done or back) so whatever opens next shows
   sorted payments. Unticking a category that has payments still asks where they go (the sheet); flush the pending sort
   before counting its payments. Test: five quick toggles cause one sort, and the result equals five slow toggles. Time
   one sort with the 5,000-payment timing source on the simulator and report it.
4. **Corrections survive an engine update.** Learned merchants are stored under the engine's `merchantKey`. When the
   engine changes how it builds keys (brief 34 does), the old keys no longer match. **New:** when the bundled engine's
   version (`Aresium/Aresium/Engine/engine-version.txt`) differs from the one the learned list was built with, the
   backend adds, for every payment set by hand (`manual`), its current key → its category to the learned list (the
   newest payment wins for a key; existing entries stay), then saves the version. Then one sort. No store schema change:
   keep the version in the app's own defaults or an existing stored setting. Test: a learned list made with an old key,
   a new engine version, the next import of that shop sorts by the correction.

## Settled: do not re-open

- No store schema change in this brief (brief 36 may add one for its own needs).
- The engine is not changed here; brief 34 changes it in parallel. Claude copies the new bundle in afterwards.
- No new screens or new looks; the picker keeps its look (only the rows stop being disabled).

## Out of scope

- `Screens/RecategoriseSheet.swift`, `Screens/BankGuideScreens.swift`, category icons (brief 36), server mode.

## API

None (phone mode only; the engine's calls as `PhoneBackend` makes them today).

## Done when

- `xcodebuild test -scheme Aresium` passes on your own simulator (commands in `AGENTS.md`), with the new tests above.
- The picker on the simulator with the sample data (`-samplePhone`): ticking four categories in a row works without
  waiting; save a screenshot to `build/35-picker.png`.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, a table of the cases in item 2 (case, result,
fixed or reported), the measured sort time, what is missing or doubtful.
