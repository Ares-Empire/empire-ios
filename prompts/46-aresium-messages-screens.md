# 46: Aresium's messages in Settings, and the offer after the first import (the screens)

Status: draft
Branch: `claude/46-messages-screens` · Worktree: `../empire-ios-46-messages-screens` · Built by: a Claude agent (the look)

## Goal

Patrik (2026-10-30): Aresium's messages come from the app (the Telegram bot is stopped). He wants a setting for whether
they come at all, which ones and how often. He chose two: an **import reminder** that names no bank or service, and a
**month review**. Brief 45 (merged) built the logic as local notifications: read its API in `CLAUDE.md` → "Aresium
phone mode" → "Local messages" and "Brief 46's API". This brief builds the Settings page, the one-time offer after an
import, and one small fix in red mode.

## Read first

- `AGENTS.md`, `CLAUDE.md` (design rules; "Languages"; "Light mode"; "Settings (every app)"; the "Aresium phone mode"
  entry: brief 45's API, the import result's send card "Help Aresium learn your bank", the category picker after an
  import, the tour)
- `Aresium/Aresium/Model/AresiumMessages.swift`, `Model/MessagePlan.swift` (what each message says, the intervals),
  `ContentView.swift` (the Settings sheet's Aresium sections: `PhoneSettingsSection`, `LockSettingsSection`, brief 42's
  `DashboardSettingsSection`), `Screens/LockSettings.swift` (a settings page of Aresium's own, the model to follow),
  `Screens/ImportControls.swift` (`ImportFeedback`, the send card), `Shared/Design/SettingsScreen.swift` (the pieces:
  `SettingsSection`, `SettingsRow`, `FormNote`).

## Build

1. **Settings → Messages** (phone mode only; German "Mitteilungen"): a row in Aresium's part of Settings opening a
   page (its place among Aresium's sections: your choice, say why). On the page:
   - **Messages** on/off (`setEnabled`). Turning it on makes iOS ask for permission the first time (brief 45 does it).
   - While on: **Import reminder** on/off with **how often** (every week, every 2 weeks, every month; Apple's own
     picker style, your choice which), and a line that says what it is ("A reminder to import new statements, counted
     from your last import."); **Month review** on/off with a line ("On the 3rd: last month's spending and income.");
     **Time** (Apple's time picker, hours and minutes) for both.
   - A quiet note: these are set on this iPhone and nothing is sent anywhere; while the lock is on they show no
     numbers (only if the lock is on or worth saying; keep it short).
   - **Denied** (`authorization == .denied`): a line that iOS has Aresium's notifications off, and a button that opens
     Aresium's page in the iPhone's Settings (`UIApplication.openNotificationSettingsURLString`). The switches keep
     what was chosen.
   - `error` shown as the other Settings pages show a failure.
   - The row on the Settings list shows the state on its right ("Off", or what is on, short).
2. **The offer** (`shouldOfferReminder`, once): after the first import that added payments, while Messages is off. A
   quiet card where the import's result shows (as "Help Aresium learn your bank"; never at the same time as that card or
   the category picker after an import: after them), e.g. "Remind you to import new statements?" with a line on the
   reminder every 2 weeks and the month review, **Turn on** and **Not now**. Turn on: Messages on with both (iOS asks for
   permission then); both answers call `finishReminderOffer()`. Never in the tour or the samples (unless a DEBUG launch
   argument asks for it for screenshots; list it in `CLAUDE.md`).
3. **Red mode's graph line:** in red mode the start screen's expenses graph draws its line almost black (brief 42's
   agent saw it; the graph was out of its scope). Make it read on the red wall, as the category graphs do, and check
   income too.
4. **German** for every new text (`scripts/strings.py`; brief 45's message texts already have German).

## Settled: do not re-open

- Two messages; off until turned on; the reminder names no bank, service or account.
- Local notifications only (brief 45); no account, no server.

## Out of scope

- The payment rows, the payment's page, the name page and the "Own names" toggle: brief 44 (another Claude agent) runs
  in parallel there and adds its own row to Aresium's Settings: keep yours separate so the merge stays simple.
- Brief 45's logic (`Model/AresiumMessages.swift`, `MessagePlan.swift`, `MessageScheduler.swift`): use its API; if it
  lacks something, describe it instead of changing the scheduling.

## Done when

- `xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium` passes on your own simulator (`claude-46`,
  commands in `AGENTS.md`), with tests where there is logic (the row's state text; the offer shows once and not with
  the send card or the picker; Turn on sets both messages).
- `scripts/strings.py check`: 0 problems.
- Looked at on the simulator (`-samplePhone`; the live model's DEBUG `-enableMessages -logMessages` from brief 45 where
  needed) in English and German, light and dark: screenshots `build/46-*.png` (Settings with the row, the page off,
  on, denied; the offer after an import; red mode's start screen with the graph). Allow the permission on the simulator
  and check a pending reminder exists afterwards (`-logMessages`).

## Final message

As in `AGENTS.md`: files changed, the exact build and test summary lines, the screenshots' paths, your choices (the
page's place, the interval control, the offer's place and words), what is missing or doubtful. Never commit, push or
merge: Claude does.
