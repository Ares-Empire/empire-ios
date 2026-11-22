# Aresium: Lock, widget and messages

Part of Aresium's notes; start at `docs/apps/Aresium.md` (its decisions in force). Covers the widget snapshot, the lock, local messages and their settings, notification taps.

## The widget snapshot

**The widget snapshot** belongs to the store it shows: phone mode's carries `phone: true` and is shown whoever is
logged in; server mode's carries its account and follows the marker as before (`WidgetSnapshotStore.readShown`).

## The lock

**The lock** (brief 22, `Model/AppLock.swift`, `Screens/LockScreen.swift`, `Screens/LockSettings.swift`): optional,
off by default; Settings → Lock (both modes): "Lock with Face ID" (Touch ID on such phones; without an own code the
iPhone's code is the fallback, `deviceOwnerAuthentication`; turning it on or, when it is the whole lock, off asks
Face ID first) and Own code (set, change, remove; 6 digits; changing and removing ask the current code; with it only
Face ID or the code opens Aresium, `deviceOwnerAuthenticationWithBiometrics`). The code is kept as a salted
PBKDF2-SHA256 hash (310,000 rounds, CommonCrypto), with the Face ID switch and the wrong-code count, in one Keychain
item of Aresium's own group (`$(AppIdentifierPrefix)de.ares-empire.aresium`, named explicitly, since the default
group is the first in the entitlements, the shared one; `AfterFirstUnlockThisDeviceOnly`). Wrong codes: after 5 wait
1 minute, then 5, 15, 60 (the count survives a restart; a clock set back never shortens a wait). A file
`Application Support/Aresium/lock-in-use` marks a lock set in this install: a Keychain lock without it is left from a
deleted install and is removed. It locks at launch and after more than 10 seconds in the background (`LockTiming`;
inactive, as under the Files picker, the share sheet or Control Center, never locks). The lock screen is a window of
its own above everything, the app switcher cover included (`LockWindow`, level alert + 2; the cover is alert + 1),
shown before the app is seen when it comes back; it is the cover's wall and band with the code pad (a Face ID key
when Face ID is on; "Forgot the code?" deletes Aresium's data on this iPhone and the lock, and in server mode also
logs out, so the lock never opens the server's data to someone without the code) or, with Face ID alone, one Face ID
button under the band where the cover has it. Face ID is offered once by itself when locked and active. A file shared
into Aresium (or dropped on it) while locked waits unread until it is unlocked (brief 204, below). While the lock is
on, the widgets show only "Locked" (no numbers are kept for them: `widget-locked.json` in the App Group).
`NSFaceIDUsageDescription` in `Info.plist`, German in
`InfoPlist.xcstrings`. **Contact & support** always without a login: the `contact` path (above). **Push:** Aresium never
registers a device (only the cleanup-only center that removes the other apps' devices when someone logs out here).

## Local messages

**Local messages** (brief 45, logic only; Settings and the offer are brief 46): phone mode uses
`UNUserNotificationCenter`, never remote push. `DashboardStore.messages: AresiumMessages?` is the page's model;
only the live `ContentView` installs it (`installMessages(lock:active:)`). Tests and the server sample have none (the
phone sample a pretend one since brief 46, below); the tour
suspends scheduling and removes Aresium's pending/delivered messages until it ends. The model and its serial queue
survive a language restart (`AresiumMessages.live`); the rebuilt store supplies the new language and dashboard.
All notification-center calls and review planning run on `MessageScheduler`, a worker actor. Account reductions
run on the ledger's own executor (`MessageScheduler.swift`'s extension), without returning its payment array.

## Brief 46's API

**Brief 46's API:**
- `preferences: MessagePreferences` (read-only): `enabled` (default false), `importReminder` (true),
`interval: MessageInterval` (`week`, `fortnight` default, `month`), `monthReview` (true), `hour` (18), `minute` (0).
Copy the struct, change a field and call `setPreferences(_:)`; `setEnabled(_:)` changes just the master switch.
Settings/history live under `aresium.messages.preferences` and `aresium.messages.history` in UserDefaults;
`aresium.messages.progress` keeps consumed reminder slots and their scheduled dates (no amounts).
- `authorization: MessageAuthorization`: `notAsked`, `allowed`, `denied`; `error: String?` reports a scheduling
failure. Enabling asks once for **alert and sound**, no badge; a refusal leaves all choices intact. `refresh()`
refreshes permission and schedules again (also called on foreground/launch). `idle()` awaits queued work.
- `shouldOfferReminder: Bool`: true after an import added payments, while Messages is off and the offer was never
answered. `finishReminderOffer()` consumes it, including Not now; the offer page saves its switches separately.
- `recordImport(accounts:addedPayments:at:)`: stable account IDs and a completion time; every account timestamp
advances, but the reminder and offer move only with new payments. `ImportStore` calls `importFinished(_:ledger:)`
after each batch, including confirmed layouts, before rebuilding the dashboard. Each file read into an account counts
as an import of it, also one that added nothing (`PhoneImportResult.accountID`).
- `dashboardBuilt(_:)`, `setPhoneMode(_:ledger:)`, `setTour(_:)`, `setLocked(_:)`: wired to dashboard builds,
backend switches, the tour and `AppLock`'s saved settings. `deleteAll()` resets all message defaults and removes
owned pending/delivered notifications; `ModeStore.deleteLocalData()` awaits it (Settings and Forgot the code).
Reminders are three absolute one-shot requests (`aresium.reminder.1...3`), each another interval after the anchor,
at the chosen wall-clock time, using calendar arithmetic across DST. The anchor is the last import that added
payments; before one exists it is when the reminder was enabled. Past dates are never queued again; persisted elapsed slots prevent a time/interval change or relaunch
from resetting the limit. An import starts the three dates again. Text: "Time for new statements" / "Your last
import was 14 days ago." (calendar days at delivery, then 28/42 for a fortnight); before any import, or with the lock
on, the body is "Import your statements to keep your dashboard up to date." (the lock hides the day count too).
The next review is at the next 3rd, for its preceding calendar month, only with payments in the dashboard. It uses
`byMonth`'s expense/income/category totals unchanged; complete requires every participating ledger account to have
an import timestamp at or after the following month's midnight. No complete history means "Import your statements
to complete October."; complete: "October: 1,234 € spent, 2,100 € in. Most on Groceries: 320 €." (up to two decimal
places); no spending omits the category sentence. Locked: "Your October review is ready." Turning the lock on also
clears delivered messages, so earlier numbers disappear. Turning Messages off removes only `aresium.reminder.` and
`aresium.review.` pending/delivered identifiers; unrelated notifications are preserved.

## Taps

**Taps:** Aresium's own `InboxLaunchDelegate` is the notification delegate (set before launch finishes), retaining
a tapped URL in `MessageTapRouter`; no shared push registration changes. `ContentView` feeds it into the existing
file/widget URL route, ending a tour first. `AresiumURL.importData` (`aresium://import`) opens phone mode's file
picker after the store and lock are ready; `.review("2026-10")` (`aresium://review/2026-10`) opens that month's
dashboard totals/categories/graph (`DashboardStore.showReview(month:)`). This month stays focused until the app goes to the background, a widget/start
link, backend switch or a rebuilt root; `showReview(month: nil)` restores Current's own month (below). No new screen.

## DEBUG verification

**DEBUG verification:** `-enableMessages -logMessages` enables live local messages and logs owned pending IDs;
never combine it with sample/test arguments (those install no live model). It uses the normal interval, with no
accelerated delivery argument. Verified on `codex-45` (2026-10-30): Allow, three pending reminders
(`build/45-pending.log`), and the import route opening the file picker (`build/45-import-route.png`).
`MessageTests` injects clock, calendar and center; no system scheduling in tests.

## English catalog keys added, German left to Claude

**English catalog keys added, German left to Claude:** "Time for new statements", "Your last import was %lld days
ago.", "Import your statements to keep your dashboard up to date.", "Month review", "Your %@ review is ready.", "Import
your statements to complete %@.", "%@: %@ spent, %@ in. Most on %@: %@.", "%@: %@ spent, %@ in.".

## Settings → Messages and the offer

**Settings → Messages and the offer** (brief 46, the screens; `Screens/MessagesSettings.swift`, words and choices in
`Model/MessageSettings.swift`): phone mode only, a section "Messages" / "Mitteilungen" of its own after "Your data on
this iPhone" and before Lock (the messages are about the data; Dashboard stays last, above Appearance), one row
"Reminder and review" / "Erinnerung & Rückblick" (the ampersand keeps it on one line beside "Nur Erinnerung") with its
state on the right (`MessageWording.state`: Off, On, Reminder only, Review only, None
chosen, Off in iOS). The page: the Messages switch (iOS asks the first time, brief 45); while on, Import reminder with
its line and How often (Apple's menu from the column check's `MenuChip`: every week, every 2 weeks, every month), Month
review with its line, Time (Apple's compact time picker, `MessageTime`); while iOS has the notifications off, a line
and Allow in iOS Settings (`openNotificationSettingsURLString`), the switches keep what was chosen; `error` as a
`FormProblem`; the note "made on this iPhone, nothing sent", plus "no numbers" while the lock is on. **The offer**
(`ReminderOffer`): in the import result's place and card (`BottomToast` in `Screens/ImportControls.swift`, the
result's chrome and swipe, shared since brief 46), only once the result (with its send card), the category picker
after an import, the import's work and every other window are gone, never in the tour or behind the lock
(`ReminderOffer.shows`, built from the stores by `ReminderOffer.Moment(messages:imports:…)`): "Remind you to import
new statements?", the line names the reminder's interval and the review, Turn on (both messages, interval and time
kept; then, once iOS allowed, "Messages are on. You can change them in Settings." in the result's place) and Not now
(also a swipe down); both answer it for good. **Not in the opening of the app whose import readied it** (brief 215,
the first-run review's finding 11: a newcomer met the result, the quick sort's offer and this in one minute): the
first import that adds payments readies it and it waits until Aresium is opened again, a launch or coming back from
the background (`AresiumMessages.offerWaitsForNextOpening`, ended by `appOpenedAgain()` through
`DashboardStore.appReturned`; `ReminderOffer.Moment.firstOpening`); another import in the same opening does not end
the wait (a file confirmed in the file check is an import of its own). `-sampleReminderOffer`'s made-up import counts
as an earlier opening. The start screen's expense graph in red mode draws the light ink
(`Palette.expense`; the website's black read at about 1.3:1 on the app's darker red), as the widget's line; income
keeps its green (about 10:1). **DEBUG** (with `-samplePhone`/`-samplePhoneEmpty`; the sample gets a pretend model,
`Model/MessageSample.swift`: its own defaults emptied at launch, a center that reaches nothing in iOS):
`-openMessages` (with `-openSheet settings`: the page), `-sampleMessages on|reminder|review|none` (Messages on with
both, one or none), `-sampleNotifications allowed|denied|notAsked` (the pretend iOS's answer; allowed by default),
`-sampleReminderOffer` (the sample may offer: a made-up import at launch, so the offer shows on the dashboard; with
`-samplePhoneEmpty -sampleImport -samplePickerDone` after the picker and the result, as live), `-sampleMessagesFail`
(planning fails: the page's failure line). Without these the sample neither offers nor plans anything. Tests:
`MessageScreensTests` (the row's words, the page's words and time, the offer after the picker and the result and never
with the send card, once; Turn on; the red graph's contrast). Screenshots: `build/46-*.png`, contact sheet
`build/46-sheet.png`.
