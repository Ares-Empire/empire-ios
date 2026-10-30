# 45: Aresium's own messages: the import reminder and the month review (the logic)

Status: draft
Branch: `codex/45-messages` · Worktree: `../empire-ios-45-messages` · Model: `gpt-6.1-sol`, effort `high`

## Goal

Patrik (2026-10-30): Aresium's messages come from the app from now on; the Telegram bot is stopped (done). They need
settings: whether they come at all, which ones, and how often. He chose two messages: an **import reminder** that names
no bank or service, and a **month review**.

Aresium keeps its data on the iPhone (no account, no server), so the app schedules **local notifications** itself
(`UNUserNotificationCenter`): no device token, no push service, nothing leaves the phone. They look like any push on
the lock screen.

This brief builds the logic: the settings model, the scheduling, the texts, a tap's routing, tests. **No screens:** a
Claude agent builds the Settings page and the one-time offer after an import on top of what you make (brief 46). Write
the API down in `CLAUDE.md` (the "Aresium phone mode" entry) so that brief can use it without reading all of your code.

## Read first

- `AGENTS.md`, `CLAUDE.md` (the "Aresium phone mode" entry: the lock and the widgets' "Locked", languages and the
  in-app restart, the tour and the samples, "Delete all data"; brief 39's rule: no work after a tap on the main thread)
- `Aresium/Aresium/ContentView.swift` (`.onOpenURL`, `AresiumURL`: the widgets' links, reuse them for a tap),
  `Model/ImportStore.swift` (where an import ends and how many payments it added, per account), `Model/DashboardStore.swift`
  (the dashboard: months, totals, categories), `AresiumShared/Dashboard.swift`, `Model/AppLock.swift`,
  `Shared/Push/PushAppDelegate.swift` and `PushCenter.swift` (Aresium today: a cleanup-only center; who is the
  `UNUserNotificationCenter` delegate; a local notification's tap must reach Aresium's routing without registering any
  device), `Model/WidgetSnapshotPublisher.swift` (how the widgets get numbers, and none while locked).

## Behaviour (settled with Patrik; build exactly this)

1. **Settings** (UserDefaults, keys under `aresium.messages.`): *Messages* on/off (off until the person turns it on);
   *Import reminder* on/off and its interval (every week, every 2 weeks, every month; default 2 weeks); *Month review*
   on/off; the *time of day* both use (default 18:00). Turning Messages on asks iOS for permission (alert, sound,
   badge: no badge needed; say what you ask for) the first time; a denial leaves the settings as chosen and the model
   says so (`authorization` state for the page: not asked, allowed, denied).
2. **Import reminder.** Fires `interval` after the *last import* at the chosen time (the last import: when an import
   added payments; before any, when the reminder was turned on). Every import moves it. If nothing is imported, it
   comes again after another interval, at most three times in a row, then stops until the next import. **No bank,
   service or account name in it** (Patrik). Text, English in the code, German by Claude: title "Time for new
   statements" / body "Your last import was 14 days ago." (the real number of days at the time it fires; say if you
   word it differently).
3. **Month review.** On the 3rd of a month at the chosen time: last month's money out, money in, and the category with
   the most spending, from the dashboard as it is ("October: 1,234 € spent, 2,100 € in. Most on Groceries: 320 €.").
   *Complete* only if every account that has a payment in that month was imported again after the month ended (keep
   the last import time per account, in UserDefaults, written where an import ends). Not complete: "Import your
   statements to complete October." instead of numbers. Recompute and reschedule after every dashboard build and at
   launch (the data only changes in the app), so an import on the 2nd makes the review on the 3rd complete. A month
   with no payments at all sends nothing.
4. **The lock.** While Aresium's lock is on, no message carries a number or a category: the review says "Your October
   review is ready." (the same rule as the widgets' "Locked").
5. **A tap** opens Aresium (behind the lock, if on): the reminder → the import (what the start screen's Import offers:
   the file picker in phone mode); the review → that month on the dashboard. Through the existing URL routing
   (`AresiumURL`), so a tour ends first, as with a widget link.
6. **Language:** texts in the app's language when scheduled; scheduled again after the in-app language switch.
7. **Never** in the samples, the tour, tests, or server mode (Patrik's own server view: no messages); "Delete all data"
   and turning Messages off remove everything pending and delivered of Aresium's. Only Aresium's own identifiers
   (`aresium.reminder…`, `aresium.review…`) are touched, never another app's.
8. **Off the main thread:** computing the review from the dashboard and the scheduling calls run off the main actor.
9. **The one-time offer** after the first import that added payments (brief 46 shows it): a flag in the model, "should
   offer the reminder", true once while Messages is off and it was never offered; the page's answer sets it done.

## Settled: do not re-open

- Local notifications only; no push registration for Aresium, no server change.
- Two messages only; the reminder names no bank, service or account.
- Off until turned on; numbers hidden while the lock is on.

## Out of scope

- Every file in `Screens/` except what a tap's routing strictly needs in `ContentView.swift` (keep it to a few lines;
  brief 42 changes the header there in parallel). The Settings page and the offer: brief 46.
- `Model/PhoneLedger.swift`, `PhoneStore.swift`, `PhoneBackend.swift`, the dashboard's data: brief 43 (Codex) changes
  them in parallel. Read them; do not edit them. If you need a hook there, describe it in your final message.
- The other apps and `Shared/Push`'s registration (change `Shared/` only if the tap routing needs it, then build every
  app).

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium` passes on your own simulator (`codex-45`,
  commands in `AGENTS.md`), with new tests (made-up data, an injected clock, calendar and notification center) for:
  the reminder's date from the last import and the interval at the chosen time (across a daylight-saving change); an
  import moves it; three repeats then stop; its text names no account; the review's numbers and its top category;
  complete vs not complete per account; a month without payments sends nothing; the lock hides numbers; off removes
  everything; samples and tour never schedule; the tap routes.
- On the simulator: Messages on, permission allowed, a reminder scheduled (log the pending requests; you may shorten
  the interval with a DEBUG launch argument to see one arrive, and list that argument in `CLAUDE.md`).
- The API is described in `CLAUDE.md` → "Aresium phone mode". The widget and the other apps build if you touched
  `Shared/`.

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the API (names and one line each), your
choices (texts, the permission options, how the tap reaches the routing), the strings you added, what is missing or
doubtful. Never commit, push or merge: Claude does.
